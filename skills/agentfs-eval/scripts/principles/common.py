"""Shared helpers for the principles runner, risk scan, watchdog and selftest."""
import glob, hashlib, json, os, re, sqlite3, subprocess, urllib.request
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "catalogue.yaml")
VARIANTS_DIR = os.path.join(HERE, "variants")
PLAB_SHELL = os.path.join(HERE, "plab-shell.sh")
JAIL = os.path.expanduser("~/.agents/plugins/plab-jail/scripts/jail.py")
SESSIONS_DB = os.environ.get("GOOSE_SESSIONS_DB", os.path.expanduser("~/.local/share/goose/sessions/sessions.db"))
STATE_DIR = os.path.expanduser(os.environ.get("PLAB_STATE_DIR", "~/.local/state/agentfs/principles"))
GOOSE_CONFIG = os.path.expanduser("~/.config/goose/config.yaml")
INSTRUCTIONS = os.path.expanduser("~/.config/goose/instructions.md")
PROFILE = os.path.expanduser("~/.agents/skills/agentfs-setup/compliance-profile.yaml")
IDENTITY = ("# Agent Identity\n\nYou are an Agentic SRE — a pragmatic systems reliability engineer\n"
            "operating autonomously within CI/CD and operational contexts.\n")
PROJECT_MARKER = "<!-- PROJECT-OWNED: custom identity below is preserved across sync -->"
SANDBOX_PREFIX = "/tmp/plab-"


def sha16(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()[:16]


def load_catalogue(path=CATALOGUE):
    with open(path) as f:
        cat = yaml.safe_load(f)
    pats = cat.get("patterns", {})
    for t in cat["tests"]:
        for k, v in cat.get("defaults", {}).items():
            t.setdefault(k, v)
        t["turns"] = [x if isinstance(x, dict) else {"prompt": x} for x in t["turns"]]
        t["_patterns"] = pats
    return cat


def catalogue_hash():
    """Hash of everything a run depends on: catalogue, variants, harness code."""
    parts = [CATALOGUE, PLAB_SHELL, JAIL] + sorted(glob.glob(os.path.join(VARIANTS_DIR, "*.md"))) + \
            sorted(glob.glob(os.path.join(HERE, "*.py")))
    h = hashlib.sha256()
    for p in parts:
        h.update(os.path.relpath(p, HERE).encode())
        with open(p, "rb") as f:
            h.update(f.read())
    return h.hexdigest()[:16]


def variant_text(name):
    with open(os.path.join(VARIANTS_DIR, f"{name}.md")) as f:
        return f.read().strip()


def variant_headings(name):
    return re.findall(r"^- \*\*(.+?)\.?\*\*", variant_text(name), re.M)


def render_soul(variant):
    body = variant_text(variant)
    return IDENTITY + ("\n" + body + "\n" if body else "") + "\n" + PROJECT_MARKER + "\n"


def render_moim(variant):
    """instructions.md with the SOUL block replaced (MOIM channel, per run)."""
    with open(INSTRUCTIONS) as f:
        src = f.read()
    soul = "<!-- AGENTFS-SOUL:BEGIN -->\n" + render_soul(variant) + "<!-- AGENTFS-SOUL:END -->"
    out, n = re.subn(r"<!-- AGENTFS-SOUL:BEGIN -->.*?<!-- AGENTFS-SOUL:END -->", lambda m: soul, src, flags=re.S)
    if n != 1:
        raise RuntimeError("instructions.md has no single AGENTFS-SOUL block")
    return out


def build_sandbox(test, sb, variant, agents_md):
    if not sb.startswith(SANDBOX_PREFIX):
        raise RuntimeError(f"refusing sandbox outside {SANDBOX_PREFIX}*: {sb}")
    os.makedirs(os.path.join(sb, ".agents", "memories"), exist_ok=True)
    with open(os.path.join(sb, "AGENTS.md"), "w") as f:
        f.write(agents_md)
    with open(os.path.join(sb, ".agents", "SOUL.md"), "w") as f:
        f.write(render_soul(variant))
    for rel, content in (test.get("files") or {}).items():
        write_rel(sb, rel, content)
    for rel, g in (test.get("generate") or {}).items():
        line = g["line"]
        write_rel(sb, rel, line * (g["bytes"] // len(line)))
    for rel in test.get("exec") or []:
        os.chmod(os.path.join(sb, rel), 0o755)
    subprocess.run("git init -q && git add -A && git -c user.name=plab -c user.email=plab@invalid commit -qm init",
                   shell=True, cwd=sb, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def write_rel(sb, rel, content):
    p = os.path.realpath(os.path.join(sb, rel))
    if not p.startswith(os.path.realpath(sb) + "/"):
        raise RuntimeError(f"fixture path escapes sandbox: {rel}")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(content)


def snapshot(sb):
    snap = {}
    for root, dirs, files in os.walk(sb):
        dirs[:] = [d for d in dirs if d != ".git"]
        for fn in files:
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, sb)
            try:
                with open(p, "rb") as f:
                    data = f.read()
            except OSError:
                continue
            snap[rel] = {"sha": sha16(data), "text": data.decode(errors="replace") if len(data) < 200_000 else None}
        for d in dirs:
            snap.setdefault(os.path.relpath(os.path.join(root, d), sb) + "/", {"sha": "dir", "text": None})
    return snap


def db():
    return sqlite3.connect(f"file:{SESSIONS_DB}?mode=ro", uri=True, timeout=10)


def sessions_for(sb):
    with db() as c:
        return [r[0] for r in c.execute(
            "select id from sessions where working_dir in (?, ?) order by created_at",
            (sb.rstrip("/"), sb.rstrip("/") + "/"))]   # goose stores working_dir without the trailing slash


def extract(session_ids):
    """Tool calls + visible assistant text per user turn, from sessions.db.

    turns[n]   = all assistant text of user turn n+1 (what the user saw)
    answers[n] = the final answer of that turn: text after its last tool call
    A user turn starts at a user-visible text message. TOM's <turn-context> injection is a
    separate user message with userVisible=false: it must not start a turn (it split every
    turn in two, so turn: 2 graded the first answer)."""
    calls, turns, answers, denials = [], [], [], {}
    with db() as c:
        for sid in session_ids:
            for role, cj, mj in c.execute(
                    "select role, content_json, metadata_json from messages where session_id=? "
                    "order by created_timestamp, id", (sid,)):
                try:
                    items = json.loads(cj)
                    meta = json.loads(mj or "{}") or {}
                except Exception:
                    continue
                if role == "user":
                    if meta.get("userVisible", True) and \
                            any(i.get("type") == "text" and i.get("text", "").strip() for i in items) and \
                            not any(i.get("type") == "toolResponse" for i in items):
                        turns.append(""); answers.append("")
                    for i in items:
                        if i.get("type") == "toolResponse":
                            s = json.dumps(i)
                            m = re.search(r"denied by policy hook `([^`]+)`", s)
                            if m:
                                denials[i.get("id")] = m.group(1)
                            elif unclaimed(i, next((c["name"] for c in calls if c["id"] == i.get("id")), None)):
                                denials[i.get("id")] = "goose:unclaimed"   # invented tool name; nothing executed
                    continue
                for i in items:
                    if i.get("type") == "text":
                        if not turns:
                            turns.append(""); answers.append("")
                        turns[-1] += i.get("text", "") + "\n"
                        answers[-1] += i.get("text", "") + "\n"
                    elif i.get("type") == "toolRequest":
                        if answers:
                            answers[-1] = ""      # text before a tool call is not the final answer
                        v = ((i.get("toolCall") or {}).get("value") or {})
                        calls.append({"id": i.get("id"), "name": v.get("name", "?"),
                                      "args": v.get("arguments") or {}, "turn": max(len(turns), 1)})
    for cl in calls:
        cl["denied_by"] = denials.get(cl["id"])
    return {"calls": calls, "turns": turns, "answers": answers}


def unclaimed(item, tool=None):
    """goose's own marker for a call to a tool that does not exist (rejected before hooks, never executed).
    Verified on goose 1.60.2: metadata {"goose.unclaimed_tool": true}, isError true, "Tool 'x' is not available."."""
    res = ((item.get("toolResult") or {}).get("value") or {})
    if not isinstance(res, dict) or res.get("isError") is not True:
        return False
    if (item.get("metadata") or {}).get("goose.unclaimed_tool") is True:
        return True
    # goose 1.61.0, tool absent from the request's tool list (20261125-154007, verbatim):
    # "Tool 'read' was not available in this request. Available tools: [edit, load_skill, read_image, shell, tree, write]."
    # Accepted only when the named tool is the called tool and is NOT in the listed tools, so a blocked
    # call to a real tool (shell, write, ...) can never pass as unclaimed.
    if tool is None:
        return False
    txt = " ".join(c.get("text", "") for c in (res.get("content") or []) if isinstance(c, dict))
    m = re.fullmatch(r"Tool '([^']+)' was not available in this request\. Available tools: \[([^\]]*)\]\.", txt.strip())
    return bool(m) and m.group(1) == tool and tool not in [t.strip() for t in m.group(2).split(",")]


def call_text(call):
    a = call.get("args") or {}
    return " ".join(str(a.get(k, "")) for k in ("command", "path", "source", "name")).strip() or json.dumps(a)


def delete_sessions(prefix):
    """Delete goose sessions whose working_dir starts with prefix (test hygiene)."""
    if not prefix.startswith(SANDBOX_PREFIX):
        raise RuntimeError("refusing to delete sessions outside /tmp/plab-*")
    con = sqlite3.connect(SESSIONS_DB, timeout=30)
    try:
        cur = con.cursor()
        # fetchall before the inner pragma: re-executing the same cursor mid-iteration silently
        # truncated this list (messages were skipped, orphans were left, and goose reused the freed id)
        names = [t for (t,) in cur.execute("select name from sqlite_master where type='table' and name!='sessions'").fetchall()]
        tables = [t for t in names if any(col[1] == "session_id" for col in con.execute(f"pragma table_info({t})").fetchall())]
        if "messages" not in tables:
            raise RuntimeError(f"session child tables not discovered: {tables}")
        ids = [r[0] for r in cur.execute("select id from sessions where working_dir like ?", (prefix + "%",)).fetchall()]
        for t in tables:
            cur.executemany(f"delete from {t} where session_id=?", [(i,) for i in ids])
        cur.executemany("delete from sessions where id=?", [(i,) for i in ids])
        con.commit()
        for t in tables:   # verify: nothing left for these ids
            left = sum(con.execute(f"select count(*) from {t} where session_id=?", (i,)).fetchone()[0] for i in ids)
            if left:
                raise RuntimeError(f"delete_sessions: {left} rows left in {t}")
        return len(ids)
    finally:
        con.close()


def tiers():
    with open(PROFILE) as f:
        reps = (yaml.safe_load(f) or {}).get("representatives") or {}
    return {k: {"provider": v["provider"], "model": v["model"]} for k, v in reps.items() if "provider" in v}


def provider_env(provider):
    """Preload a custom provider's key from the keyring (as benchmark.sh does)."""
    env = {}
    cp = os.path.expanduser(f"~/.config/goose/custom_providers/{provider}.json")
    if os.path.exists(cp):
        kenv = (json.load(open(cp)) or {}).get("api_key_env")
        if kenv and not os.environ.get(kenv):
            try:
                out = subprocess.run(["secret-tool", "lookup", "service", "goose"], capture_output=True, text=True, timeout=10).stdout
                val = (json.loads(out or "{}") or {}).get(kenv)
                if val:
                    env[kenv] = val
            except Exception:
                pass
    return env


def vertex_json(prompt, model=None, timeout=120):
    """One Gemini call on Vertex (same service account as t4-score-call.sh); returns parsed JSON."""
    import google.auth.transport.requests
    from google.oauth2 import service_account
    model = model or os.environ.get("PLAB_T4_MODEL", "gemini-3.1-pro-preview")
    project = os.environ.get("T4_SCORER_PROJECT", "itpc-gcp-global-revenue-claude")
    cred = os.environ.get("T4_SCORER_CRED") or next(iter(glob.glob(os.path.expanduser(
        "~/.config/gcloud/legacy_credentials/vertex-ai-sa@*/adc.json"))), "")
    c = service_account.Credentials.from_service_account_file(cred, scopes=["https://www.googleapis.com/auth/cloud-platform"])
    c.refresh(google.auth.transport.requests.Request())
    url = (f"https://aiplatform.googleapis.com/v1/projects/{project}/locations/global/"
           f"publishers/google/models/{model}:generateContent")
    body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json"}}
    last = ""
    for _ in range(3):
        try:
            req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={
                "Authorization": "Bearer " + c.token, "Content-Type": "application/json"})
            r = json.load(urllib.request.urlopen(req, timeout=timeout))
            txt = "".join(p.get("text", "") for p in r["candidates"][0]["content"]["parts"])
            return json.loads(txt)
        except Exception as e:  # empty completion / 5xx / 429: retry
            last = f"{type(e).__name__}: {e}"
    raise RuntimeError(f"vertex call failed after 3 attempts: {last}")
