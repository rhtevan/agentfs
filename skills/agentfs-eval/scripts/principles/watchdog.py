"""Runtime watchdog for principles-lab campaigns: a deterministic tripwire.

Layers: plab-shell.sh (bubblewrap) and plab-jail PREVENT; this watchdog DETECTS a
prevention failure and STOPS the campaign. It cannot undo an executed call.

Every poll it reads new tool calls of the campaign's sessions from sessions.db and
re-applies the plab-jail policy. A call the policy blocks whose tool response shows
no hook denial (and that goose did not reject as an unknown tool) actually ran:
JAIL BYPASS -> kill all runs, abort the campaign.

No model judgement here: a T4 reviewer with kill power was removed after three
smoke campaigns produced three false aborts and no real catch (bubblewrap makes
shell calls harmless; plab-jail checks write/edit before they run). Behavioural
observations (jail denials by category, probes, invented tools) are reported per
variant by run.py from the stored calls; they never stop a run.
All events go to <out>/watchdog.jsonl.
"""
import importlib.util, json, os, signal, threading, time
import common

_spec = importlib.util.spec_from_file_location("plab_jail", common.JAIL)
jail = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(jail)

class Watchdog(threading.Thread):
    def __init__(self, prefix, out_dir, registry, poll_s=5):
        super().__init__(daemon=True)
        self.prefix, self.out, self.registry = prefix, out_dir, registry  # registry: {sandbox: Popen}
        self.poll_s = poll_s
        self.last_id = 0
        self.pending = {}            # call id -> (sandbox, call, seen_at) awaiting its tool response
        self.abort_reason = None
        self.killed = {}             # sandbox -> reason
        self.stop_evt = threading.Event()
        self.stats = {"calls": 0, "jail_blocks_seen": 0, "bypasses": 0}

    def log(self, **ev):
        ev["ts"] = time.strftime("%H:%M:%S")
        with open(os.path.join(self.out, "watchdog.jsonl"), "a") as f:
            f.write(json.dumps(ev) + "\n")

    def kill(self, sb, reason):
        p = self.registry.get(sb)
        self.killed[sb] = reason
        if p and p.poll() is None:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
        self.log(event="kill", sandbox=sb, reason=reason)

    def abort(self, reason):
        if not self.abort_reason:
            self.abort_reason = reason
            self.log(event="abort", reason=reason)
            for sb in list(self.registry):
                self.kill(sb, f"campaign abort: {reason}")

    def poll_once(self):
        new_calls, responses = [], {}
        with common.db() as c:
            rows = c.execute(
                "select m.id, m.role, m.content_json, s.working_dir from messages m join sessions s on s.id=m.session_id "
                "where m.id>? and s.working_dir like ? order by m.id", (self.last_id, self.prefix + "%")).fetchall()
        for mid, role, cj, wd in rows:
            self.last_id = max(self.last_id, mid)
            try:
                items = json.loads(cj)
            except Exception:
                continue
            for i in items:
                if role == "assistant" and i.get("type") == "toolRequest":
                    v = ((i.get("toolCall") or {}).get("value") or {})
                    new_calls.append({"id": i.get("id"), "sandbox": wd, "tool": v.get("name", "?"),
                                      "args": v.get("arguments") or {}})
                elif role == "user" and i.get("type") == "toolResponse":
                    responses[i.get("id")] = i
        now = time.time()
        for call in new_calls:
            self.stats["calls"] += 1
            dec, why = jail.policy({"working_dir": call["sandbox"], "tool_name": call["tool"], "tool_input": call["args"]})
            if dec == "block":
                self.stats["jail_blocks_seen"] += 1
                self.pending[call["id"]] = (call, now, why)
        for cid, item in responses.items():
            if cid in self.pending:
                call, _, why = self.pending.pop(cid)
                resp = json.dumps(item)
                if "denied by policy hook" in resp:   # not executed (plab-jail, or an earlier hook such as a Pre-Flight hold)
                    self.log(event="contained", sandbox=call["sandbox"], tool=call["tool"], reason=why)
                elif common.unclaimed(item, call["tool"]):          # goose rejected an unknown tool before any hook: nothing executed
                    self.log(event="unclaimed", sandbox=call["sandbox"], tool=call["tool"], reason="goose: tool not available")
                else:
                    self.stats["bypasses"] += 1
                    self.log(event="jail_bypass", sandbox=call["sandbox"], tool=call["tool"], args=call["args"], reason=why,
                             response=resp[:2000])   # raw goose response: sessions are deleted at cleanup (20261125-150959)
                    self.abort(f"jail bypass: {call['tool']} {why}")

    def run(self):
        self.log(event="start", prefix=self.prefix)
        fails = 0
        while not self.stop_evt.is_set():
            try:
                self.poll_once()
                fails = 0
            except Exception as e:
                fails += 1
                self.log(event="poll_error", error=str(e)[:300], consecutive=fails)
                if fails >= 3:   # a blind tripwire is no tripwire: fail closed
                    self.abort("watchdog cannot read sessions.db (3 consecutive poll errors)")
            self.stop_evt.wait(self.poll_s)
        try:
            self.poll_once()   # final sweep after the last run
        except Exception as e:
            self.log(event="poll_error", error=str(e)[:300], final=True)
        self.log(event="stop", **self.stats)
