#!/usr/bin/env python3
"""Principles runner (F26): SOUL variants x tests x tiers, in parallel, contained.

Usage:
  run.py --dry-run [matrix options]        plan + gates, launches nothing
  run.py --smoke   [matrix options]        smoke tests, 1 run
  run.py --real    [matrix options]        all tests, --runs (default 3)
  run.py --regrade DIR                     re-grade saved records with current graders
  run.py --cleanup CID                     remove a campaign's sandboxes and sessions

Matrix options: --tiers T2[,T3,T4]  --variants s0-current,s1-control,s2-draft,s3-trigger
                --tests id,...  --runs N  --concurrency T2=4,T3=4,T4=2
Safety options: --accept-scan HASH  (run with scan FINDINGS the user approved)

Gates before any goose run (all must pass):
  scan      risk_scan.py report for the current catalogue hash is CLEAN, or
            --accept-scan names that hash (user-approved findings)
  jail      plab-jail registered + enabled in goose config; its unit tests pass
  shell     plab-shell.sh confines a probe (no HOME write, no network, no secrets)
  rules     goose system.md rules hash == project AGENTS.md rules hash
  library   ~/.agents git state recorded; compared after the campaign (G3)
Containment per run: /tmp/plab-<cid>/<tier>/<variant>/<test>/r<n> sandbox,
GOOSE_SHELL=plab-shell.sh (bubblewrap), plab-jail hook, jail-bypass tripwire thread,
per-run timeout + max-turns, own MOIM file (variant SOUL), own goose process group.
Cleanup always runs: sessions deleted, sandboxes and MOIM files removed,
hook flag files removed. Records live in ~/.local/state/agentfs/principles/<cid>/.
"""
import argparse, concurrent.futures as cf, json, os, re, shutil, signal, subprocess, sys, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common, graders
from watchdog import Watchdog

PROVIDER_ERR = re.compile(r"Ran into this error: (Rate limit exceeded|Server error|Request failed|error sending request|"
                          r"Authentication error)|Network error: |Stream decode error|Too many requests|missing required key|"
                          r"Configuration value not found")
PROJECT = os.environ.get("BENCHMARK_PROJECT_CWD", os.path.expanduser("~/app/playground/context-eng"))
MAX_ATTEMPTS, BACKOFF_S = 4, (30, 60, 120)   # provider (rate-limit) retries: fresh sandbox each time
DEFAULT_CONC = {"T4": 2, "T3": 4, "T2": 3, "T1": 2}   # T2=4: 7/40 runs hit corp rate limits (smoke 5)


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)


# ---------------------------------------------------------------- gates
def soul_lint(variant):
    lint = os.path.join(os.path.dirname(common.HERE), "soul-cnl-lint.py")
    try:
        out = subprocess.run([sys.executable, lint, os.path.join(common.VARIANTS_DIR, variant + ".md"), "--tsv"],
                             capture_output=True, text=True, timeout=30).stdout
        sig, nf, nw = [l.split("\t")[1:] for l in out.splitlines() if l.startswith("SUMMARY")][0]
        return f"SOUL_CNL={sig} ({nf} fail, {nw} warn)"
    except Exception as e:
        return f"SOUL_CNL=UNKNOWN ({e})"


def gate_scan(chash, accept):
    path = os.path.join(common.STATE_DIR, f"scan-{chash}.json")
    if not os.path.exists(path):
        return False, f"no risk scan for catalogue hash {chash} (run risk_scan.py)"
    res = json.load(open(path)).get("result")
    if res == "CLEAN":
        return True, f"scan {chash} CLEAN"
    if res == "FINDINGS" and accept == chash:
        return True, f"scan {chash} FINDINGS accepted by user (--accept-scan)"
    return False, f"scan {chash} is {res}; review the report, then pass --accept-scan {chash}"


def gate_jail():
    import yaml
    cfg = yaml.safe_load(open(common.GOOSE_CONFIG)) or {}
    root = os.path.dirname(os.path.dirname(common.JAIL))
    ent = (cfg.get("plugins") or {}).get(root)
    if not (ent and ent.get("enabled")):
        return False, f"plab-jail not registered/enabled in {common.GOOSE_CONFIG} (plugins: {root})"
    t = sh(f"bash {root}/tests/test-jail.sh")
    return t.returncode == 0, t.stdout.strip().splitlines()[-1] if t.stdout else t.stderr[-200:]


def gate_shell():
    sb = f"/tmp/plab-gate-{os.getpid()}/r"
    os.makedirs(sb, exist_ok=True)
    try:
        A, K = "~/.agents", "~/.agents/knowledge/agentfs-engineering-evolution"
        probe = ("echo w > w.txt; touch /home/x 2>/dev/null && echo ESCAPE; touch \"$HOME\"/../x 2>/dev/null && echo ESCAPE; "
                 "(exec 3<>/dev/tcp/1.1.1.1/443) 2>/dev/null && echo NET; env | grep -qiE 'key|token|secret' && echo SECRET; "
                 f"head -1 {A}/skills/index.md >/dev/null 2>&1 && echo LIBREAD; "
                 f"touch {A}/.plab-gate-probe 2>/dev/null && echo LIBWRITE; "
                 f"for d in {A}/skills/agentfs-eval/scripts/principles {A}/plugins {A}/.git; do "
                 "[ -z \"$(ls -A $d 2>/dev/null)\" ] || echo MASK; done; "
                 f"for f in {K}/principles-test-catalogue.md {K}/mcacs-principles-for-agentfs.md; do "
                 "[ -s $f ] && head -c1 $f >/dev/null 2>&1 && echo MASK; done; true")
        r = subprocess.run([common.PLAB_SHELL, "-c", probe], env={**os.environ, "PLAB_SANDBOX": sb},
                           cwd=sb, capture_output=True, text=True, timeout=30)
        bad = [w for w in ("ESCAPE", "NET", "SECRET", "LIBWRITE", "MASK") if w in r.stdout]
        if "LIBREAD" not in r.stdout:
            bad.append("library not readable")
        ok = not bad and os.path.exists(os.path.join(sb, "w.txt"))
        return ok, ("bubblewrap confines writes, network and env; library read-only; test material masked"
                    if ok else f"leak: {bad or 'sandbox not writable'}")
    finally:
        shutil.rmtree(os.path.dirname(sb), ignore_errors=True)
        stray = os.path.expanduser("~/.agents/.plab-gate-probe")
        if os.path.exists(stray):   # only if the write probe leaked
            os.remove(stray)


def gate_rules():
    rh = os.path.expanduser("~/.agents/scripts/rules-hash.sh")
    a = sh(f"bash {rh} ~/.config/goose/prompts/system.md").stdout.strip()
    b = sh(f"bash {rh} {PROJECT}/AGENTS.md").stdout.strip()
    return bool(a) and a == b, f"system.md {a or '?'} vs project AGENTS.md {b or '?'}"


def goose_plugins():
    import yaml
    return dict((yaml.safe_load(open(common.GOOSE_CONFIG)) or {}).get("plugins") or {})


def revert_sandbox_plugins():
    """Remove plugin entries that point into /tmp/plab-* (goose auto-registration)."""
    import yaml
    txt = open(common.GOOSE_CONFIG).read()
    bad = [k for k in goose_plugins() if str(k).startswith(common.SANDBOX_PREFIX)]
    for k in bad:
        txt = re.sub(rf"(?m)^  {re.escape(k)}:\n(    .*\n)*", "", txt)
    if bad:
        open(common.GOOSE_CONFIG, "w").write(txt)
    return bad


def library_state():
    return sh("git -C ~/.agents rev-parse HEAD && git -C ~/.agents status --porcelain | sha256sum").stdout


# ---------------------------------------------------------------- one run
class Campaign:
    def __init__(self, args):
        self.args = args
        self.cid = time.strftime("%Y%m%d-%H%M%S")
        self.root = f"{common.SANDBOX_PREFIX}{self.cid}/"
        self.moim_dir = f"{common.SANDBOX_PREFIX}{self.cid}-moim/"
        self.out = os.path.join(common.STATE_DIR, self.cid)
        self.registry, self.lock = {}, threading.Lock()
        self.agents_md = open(os.path.join(PROJECT, "AGENTS.md")).read()
        self.wd = None

    def run_one(self, tier, tinfo, variant, test, n):
        key = f"{tier}/{variant}/{test['id']}/r{n}"
        rec_path = os.path.join(self.out, "runs", f"{tier}_{variant}_{test['id']}_r{n}.json")
        rec = {"key": key, "tier": tier, "model": tinfo["model"], "provider": tinfo["provider"], "variant": variant,
               "test": test["id"], "principle": test["principle"], "kind": test["kind"], "attempts": []}
        for attempt in range(1, MAX_ATTEMPTS + 1):
            if self.wd and self.wd.abort_reason:
                rec.update(status="EXCLUDED", reason=f"campaign aborted: {self.wd.abort_reason}")
                break
            sb = f"{self.root}{tier}/{variant}/{test['id']}/r{n}a{attempt}"
            shutil.rmtree(sb, ignore_errors=True)
            common.build_sandbox(test, sb, variant, self.agents_md)
            before = common.snapshot(sb)
            moim = os.path.join(self.moim_dir, key.replace("/", "_") + f"a{attempt}.md")
            os.makedirs(self.moim_dir, exist_ok=True)
            open(moim, "w").write(common.render_moim(variant))
            env = {**os.environ, **common.provider_env(tinfo["provider"]),
                   "GOOSE_MOIM_MESSAGE_FILE": moim, "GOOSE_SHELL": common.PLAB_SHELL, "PLAB_SANDBOX": sb,
                   "GOOSE_CLI_MIN_PRIORITY": "0.5", "GOOSE_THINKING_EFFORT": "high"}
            name = f"plab_{self.cid}_{key.replace('/', '_')}a{attempt}"
            status, stdout_all = "DONE", ""
            for i, turn in enumerate(test["turns"]):
                for rel, txt in (turn.get("append") or {}).items():
                    with open(os.path.join(sb, rel), "a") as f:
                        f.write(txt)
                cmd = ["goose", "run"] + (["--no-profile", "--with-builtin", "developer,tom"] if i == 0 else ["--no-profile"]) + \
                      ["--provider", tinfo["provider"], "--model", tinfo["model"], "--name", name, "--text", turn["prompt"],
                       "--quiet", "--max-turns", str(test["max_turns"])] + (["--resume"] if i else [])
                logf = os.path.join(self.out, "stdout", f"{key.replace('/', '_')}a{attempt}_t{i + 1}.txt")
                with open(logf, "w") as lf:
                    p = subprocess.Popen(cmd, cwd=sb, env=env, stdout=lf, stderr=subprocess.STDOUT, start_new_session=True)
                    with self.lock:
                        self.registry[sb] = p
                    try:
                        p.wait(timeout=test["timeout_s"])
                    except subprocess.TimeoutExpired:
                        os.killpg(os.getpgid(p.pid), signal.SIGTERM)
                        p.wait()
                        status = "TIMEOUT"
                    with self.lock:
                        self.registry.pop(sb, None)
                stdout_all += open(logf, errors="replace").read()
                if self.wd and sb in self.wd.killed:
                    status = "KILLED"
                if status != "DONE":
                    break
            m = PROVIDER_ERR.search(stdout_all)
            rec["attempts"].append({"sandbox": sb, "status": status, "provider_error": m.group(0) if m else None})
            if m and status == "DONE" and attempt < MAX_ATTEMPTS:
                time.sleep(BACKOFF_S[attempt - 1])
                continue
            ex = common.extract(common.sessions_for(sb))
            rec.update(ex, before=before, after=common.snapshot(sb),
                       variant_headings=common.variant_headings(variant), sandbox=sb)
            if status == "KILLED":
                rec.update(status="EXCLUDED", reason=f"watchdog: {self.wd.killed.get(sb)}")
            elif status == "TIMEOUT" and test.get("timeout_check") and \
                    not graders.check(test, rec, test["timeout_check"])[0]:
                # G9 tests: a timeout with evidence of iteration in the final state (e.g. >4 logged attempts) IS the
                # measured failure; a timeout without that evidence (slow tier, stalled provider) stays EXCLUDED
                rec.update(status="FAIL", checks=[["timeout_check", False, f"timed out ({test['timeout_s']}s); "
                                                   + graders.check(test, rec, test["timeout_check"])[1]]])
            elif status == "TIMEOUT":
                rec.update(status="EXCLUDED", reason=f"timeout {test['timeout_s']}s")
            elif m:
                rec.update(status="EXCLUDED", reason=f"provider error after {MAX_ATTEMPTS} attempts: {m.group(0)}")
            else:
                verdict, res = graders.grade(test, rec)
                rec.update(status=verdict, checks=res)
            break
        rec["denials"] = sum(1 for c in rec.get("calls", []) if c.get("denied_by"))
        json.dump(rec, open(rec_path, "w"), indent=1, default=str)
        return rec

    def cleanup(self):
        n = 0
        try:
            sids = []
            with common.db() as c:
                sids = [r[0] for r in c.execute("select id from sessions where working_dir like ?", (self.root + "%",))]
            n = common.delete_sessions(self.root)
            for sid in sids:
                for d in ("/tmp/goose-preflight", "/tmp/goose-postwrite"):
                    for f in (os.path.join(d, sid), os.path.join(d, sid + ".lock")):
                        if os.path.exists(f):
                            os.remove(f)
        finally:
            shutil.rmtree(self.root, ignore_errors=True)
            shutil.rmtree(self.moim_dir, ignore_errors=True)
        return n


JAIL_HOOK = "plab-jail"


def hook_stall(r):
    """FAIL whose last tool event was a non-jail hook hold (e.g. preflight-reminder): the model stopped
    after a hold instead of retrying, so the failure may be the hook's, not the principle's."""
    calls = r.get("calls") or []
    return r["status"] == "FAIL" and bool(calls) and calls[-1].get("denied_by") not in (None, JAIL_HOOK, "goose:unclaimed")


def diagnostics(recs, variants):
    """Harness-side signals per variant, so hook or harness effects are visible next to the scores."""
    rows = []
    for v in variants:
        rs = [r for r in recs if r["variant"] == v and r["status"] != "EXCLUDED"]
        calls = [c for r in rs for c in (r.get("calls") or [])]
        holds = sum(1 for c in calls if c.get("denied_by") not in (None, JAIL_HOOK, "goose:unclaimed"))
        jail = sum(1 for c in calls if c.get("denied_by") == JAIL_HOOK)
        unc = sum(1 for c in calls if c.get("denied_by") == "goose:unclaimed")
        stalls = [r["test"] for r in rs if hook_stall(r)]
        probe = [r["status"] for r in rs if r["test"] == "probe"]
        rows.append(f"| {v} | {holds} | {len(stalls)}{' (' + ', '.join(stalls) + ')' if stalls else ''} | {jail} | {unc} | "
                    f"{'/'.join(probe) or '—'} |")
    return ["### Diagnostics", "",
            "| variant | hook holds (non-jail) | hook_stall FAILs | jail denials | invented tools | probe (delivery) |",
            "|---|---|---|---|---|---|"] + rows + [
            "", "hook_stall = a FAIL whose last tool event was a hook hold: the model stopped instead of retrying.",
            "probe FAIL = variant delivery unconfirmed for that variant: read its scores with care.", ""]


PROBE_FS = re.compile(r"\bfind\s+/(\s|$)|\bmount\b|\bfindmnt\b|/proc/|(^|[\s'\"])/etc/|\bls\s+(-\S+\s+)*/(\s|$)")   # not df: disk checks are task work (consent)
PROBE_NET = re.compile(r"\bgetent\b|\bping\b|\bnslookup\b|\bdig\b|\bcurl\b|\bwget\b|/dev/tcp/|\bsocket\.|create_connection|\bnc\b|\bssh\b")
JAIL_CATS = (("masked test path", "masked"), ("only reading ~/.agents", "library write"),
             ("outside the sandbox", "outside path"), ("is not allowed", "command"))


def observe(rec):
    """Deterministic behaviour signals of one run (report only; never stops a run)."""
    from collections import Counter
    from watchdog import jail
    n = Counter()
    for c in rec.get("calls") or []:
        d, args = c.get("denied_by"), c.get("args") or {}
        if d == JAIL_HOOK:
            _, why = jail.policy({"working_dir": rec.get("sandbox") or "", "tool_name": c.get("name"), "tool_input": args})
            n["jail: " + next((cat for key, cat in JAIL_CATS if key in (why or "")), "other")] += 1
        elif d == "goose:unclaimed":
            n["invented tool"] += 1
        elif d is None and c.get("name") == "shell":
            cmd = str(args.get("command", ""))
            n["probe fs"] += bool(PROBE_FS.search(cmd))
            n["probe net"] += bool(PROBE_NET.search(cmd))
    return n


def observations(recs, variants):
    from collections import Counter
    cats = ["jail: outside path", "jail: command", "jail: library write", "jail: masked", "jail: other",
            "invented tool", "probe fs", "probe net"]
    rows = []
    for v in variants:
        rs = [r for r in recs if r["variant"] == v and r["status"] != "EXCLUDED"]
        tot = sum((observe(r) for r in rs), Counter())
        runs = sum(1 for r in rs if +observe(r))
        rows.append(f"| {v} | " + " | ".join(str(tot[k]) for k in cats) + f" | {runs}/{len(rs)} |")
    return ["### Observations (report only)", "",
            "| variant | " + " | ".join(cats) + " | runs with any |", "|---|" + "---|" * (len(cats) + 1)] + rows + [
            "", "Counts of tool calls. jail = blocked by plab-jail (by reason); probe = an executed shell command that looked",
            "outside the sandbox (fs) or tried the network (net); in bubblewrap these are harmless. Out-of-scope reach",
            "signals for the principles (Proportionate, Grounded); they never stop a run.", ""]


def summarise(records, out):
    from collections import defaultdict
    cell = defaultdict(lambda: [0, 0, 0])           # (tier, variant, test) -> pass, graded, excluded
    for r in records:
        c = cell[(r["tier"], r["variant"], r["test"])]
        if r["status"] == "EXCLUDED":
            c[2] += 1
        else:
            c[1] += 1
            c[0] += r["status"] == "PASS"
    tiers = sorted({k[0] for k in cell}, reverse=True)
    variants = sorted({k[1] for k in cell})
    tests = sorted({k[2] for k in cell})
    lines = [f"# Principles campaign {os.path.basename(out)}", ""]
    for t in tiers:
        lines += [f"## {t}", "", "| test | " + " | ".join(variants) + " |", "|---|" + "---|" * len(variants)]
        for te in tests:
            row = []
            for v in variants:
                p, g, x = cell.get((t, v, te), [0, 0, 0])
                row.append(f"{p}/{g}" + (f" (+{x} excl)" if x else "") if g or x else "—")
            lines.append(f"| {te} | " + " | ".join(row) + " |")
        tot = {v: [sum(cell[(t, v, te)][i] for te in tests if (t, v, te) in cell and te != "probe") for i in (0, 1)] for v in variants}
        lines.append("| **scored total** | " + " | ".join(f"**{a}/{b}**" + (f" ({100*a/b:.0f}%)" if b else "") for a, b in tot.values()) + " |")
        lines.append("")
        lines += diagnostics([r for r in records if r["tier"] == t], variants)
        lines += observations([r for r in records if r["tier"] == t], variants)
    open(os.path.join(out, "report.md"), "w").write("\n".join(lines) + "\n")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true"); mode.add_argument("--smoke", action="store_true")
    mode.add_argument("--real", action="store_true"); mode.add_argument("--regrade")
    mode.add_argument("--cleanup")
    ap.add_argument("--tiers", default="T2"); ap.add_argument("--variants", default="s0-current,s1-control,s2-draft,s3-trigger")
    ap.add_argument("--tests", default=""); ap.add_argument("--runs", type=int, default=None)
    ap.add_argument("--concurrency", default=""); ap.add_argument("--accept-scan", default="")
    a = ap.parse_args()
    cat = common.load_catalogue()
    tests_by_id = {t["id"]: t for t in cat["tests"]}

    if a.regrade:
        recs = []
        for f in sorted(os.listdir(os.path.join(a.regrade, "runs"))):
            r = json.load(open(os.path.join(a.regrade, "runs", f)))
            if r.get("status") in ("PASS", "FAIL"):
                nt = len(tests_by_id[r["test"]]["turns"])
                if "answers" not in r and len(r.get("turns") or []) == 2 * nt and not any(t.strip() for t in r["turns"][0::2]):
                    r["turns"] = r["turns"][1::2]   # pre-fix records: TOM's injection split each turn in two
                v, res = graders.grade(tests_by_id[r["test"]], r)
                if v != r["status"]:
                    print(f"changed: {r['key']} {r['status']} -> {v}")
                r["status"], r["checks"] = v, res
            recs.append(r)
        print(summarise(recs, a.regrade)); return 0
    if a.cleanup:
        c = Campaign.__new__(Campaign); c.root = f"{common.SANDBOX_PREFIX}{a.cleanup}/"; c.moim_dir = f"{common.SANDBOX_PREFIX}{a.cleanup}-moim/"
        print(f"removed {c.cleanup()} sessions and sandboxes for {a.cleanup}"); return 0

    all_tiers = common.tiers()
    tiers = [t for t in a.tiers.split(",") if t]
    unknown = [t for t in tiers if t not in all_tiers]
    variants = [v for v in a.variants.split(",") if v]
    missing_v = [v for v in variants if not os.path.exists(os.path.join(common.VARIANTS_DIR, v + ".md"))]
    tests = [tests_by_id[x] for x in a.tests.split(",") if x] if a.tests else \
            [t for t in cat["tests"] if t.get("smoke")] if a.smoke else cat["tests"]
    runs = a.runs or (1 if a.smoke else 3)
    conc = dict(DEFAULT_CONC)
    for kv in filter(None, a.concurrency.split(",")):
        k, v = kv.split("="); conc[k] = int(v)
    chash = common.catalogue_hash()
    units = [(t, v, te, n) for t in tiers for v in variants for te in tests for n in range(1, runs + 1)]
    units.sort(key=lambda u: -len(u[2]["turns"]))   # multi-turn first

    gates = [("matrix", not unknown and not missing_v, f"tiers {tiers} variants {variants}" +
              (f" UNKNOWN {unknown or ''} {missing_v or ''}" if unknown or missing_v else "")),
             ("scan",) + gate_scan(chash, a.accept_scan), ("jail",) + gate_jail(),
             ("shell",) + gate_shell(), ("rules",) + gate_rules()]
    print(f"catalogue hash {chash}; {len(tests)} tests x {len(variants)} variants x {len(tiers)} tiers x {runs} runs = {len(units)} runs")
    for t in tiers:
        if t in all_tiers:
            print(f"  {t}: {all_tiers[t]['provider']} / {all_tiers[t]['model']}  concurrency {conc.get(t, 2)}")
    est = max((sum(1 for u in units if u[0] == t) * 75 / conc.get(t, 2)) for t in tiers) / 60 if units else 0
    print(f"  estimated wall time ~{est:.0f} min (75 s/run average, tiers in parallel)")
    for g, ok, why in gates:
        print(f"  gate {g:7s} {'PASS' if ok else 'FAIL'}  {why}")
    for v in variants:   # informational: CNL form of each variant (soul-cnl-lint.py), not a gate
        print(f"  lint {v:12s} {soul_lint(v)}")
    if a.dry_run:
        print("DRY_RUN_RESULT=" + ("READY" if all(ok for _, ok, _ in gates) else "BLOCKED")); return 0
    if not all(ok for _, ok, _ in gates):
        print("BLOCKED: gates failed; nothing was run."); return 2

    c = Campaign(a)
    os.makedirs(os.path.join(c.out, "runs")); os.makedirs(os.path.join(c.out, "stdout"))
    lib_before, plugins_before = library_state(), goose_plugins()
    json.dump({"cid": c.cid, "catalogue_hash": chash, "tiers": {t: all_tiers[t] for t in tiers}, "variants": variants,
               "tests": [t["id"] for t in tests], "runs": runs, "started": time.strftime("%FT%T%z")},
              open(os.path.join(c.out, "campaign.json"), "w"), indent=1)
    c.wd = Watchdog(c.root, c.out, c.registry)
    c.wd.start()
    records = []
    try:
        pools = {t: cf.ThreadPoolExecutor(max_workers=conc.get(t, 2)) for t in tiers}
        futs = [pools[u[0]].submit(c.run_one, u[0], all_tiers[u[0]], u[1], u[2], u[3]) for u in units]
        for f in cf.as_completed(futs):
            r = f.result(); records.append(r)
            print(f"[{len(records)}/{len(units)}] {r['key']}: {r['status']}" + (f" ({r.get('reason')})" if r.get("reason") else ""), flush=True)
        for p in pools.values():
            p.shutdown()
    finally:
        c.wd.stop_evt.set(); c.wd.join(timeout=60)
        removed = c.cleanup()
        lib_after = library_state()
        reverted = revert_sandbox_plugins()
        plugins_after = goose_plugins()
        if reverted:
            print(f"SECURITY: sandbox plugin(s) were auto-registered in goose config and have been removed: {reverted}")
        print(f"G3 goose plugins unchanged: {'PASS' if plugins_after == plugins_before else f'FAIL — before {sorted(plugins_before)} after {sorted(plugins_after)}'}")
        print(f"cleanup: {removed} sessions removed; sandboxes and MOIM files deleted")
        print(f"G3 library unchanged: {'PASS' if lib_before == lib_after else 'FAIL — ~/.agents changed during the campaign'}")
        if c.wd.abort_reason:
            print(f"ABORTED by watchdog: {c.wd.abort_reason}")
    print(summarise(records, c.out))
    print(f"records: {c.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
