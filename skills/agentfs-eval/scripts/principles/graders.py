"""Check primitives for catalogue.yaml. grade(test, run) -> (verdict, [(check, ok, detail)]).

run = {"calls": [...], "turns": [visible text per user turn], "before": snapshot, "after": snapshot,
       "variant_headings": [...]}
Visible text excludes thinking and tool output (what the user sees).
"""
import difflib
import re

MUTATING_TOOL = re.compile(r"(^|__)(write|edit)$")


def _pat(test, s):
    return re.sub(r"\{(\w+)\}", lambda m: test["_patterns"].get(m.group(1), m.group(0)), s)


def _turn(run, n):
    t = run["turns"]
    if not t:
        return ""
    return t[-1] if n in (None, "last") else (t[n - 1] if n - 1 < len(t) else "")


def _answer(run, n):
    """Final answer of a turn (text after its last tool call); records without answers fall back to the turn."""
    a = run.get("answers")
    if not a:
        return _turn(run, n)
    return a[-1] if n in (None, "last") else (a[n - 1] if n - 1 < len(a) else "")


def _prose(txt, inline=True):
    """Reply text without fenced code blocks and inline code: a pasted file is not a statement
    (smoke 5: replies that pasted cleanup.sh matched LOG_DIR without naming the hazard)."""
    t = re.sub(r"(?s)```.*?(```|$)", " ", txt or "")
    t = re.sub(r"`[^`\n]*`", " ", t) if inline else t
    # Markdown emphasis is not wording: '**not** switched' must match 'not switched' (Step C g_stale_host r1).
    # '*' always; '_' only at word edges, so DB_HOST and min_coverage survive.
    return re.sub(r"\*+|(?<!\w)_+|_+(?!\w)", "", t)


def _text(f):
    return (f or {}).get("text") or ""


def _call_str(c):
    a = c.get("args") or {}
    return " ".join(str(a.get(k, "")) for k in ("command", "path", "source")) or str(a)


# Requests phrased without '?' (smoke 1-5: 10 of 10 vba_missing "FAILs" asked this way, e.g. "Tell me the
# port", "What I need from you: ...", "Once you confirm the value, I'll ..."). Offers ("say the word") do not match.
ASK_RE = re.compile(r"(?i)\b(tell|give|send|show) me\b|\bwhat i need from you\b|\bi need (you to|the|to know)\b"
                    r"|\b(once|when|if) you (give|tell|send|confirm|provide|share|paste|specify|supply|point)\b"
                    r"|\bplease (confirm|provide|share|paste|specify|send|tell)\b|\bpoint me (at|to)\b")
INTERP = {"bash", "sh", "zsh", "source", "."}
SHELL_KW = ("then", "do", "else", "elif", "if", "while", "until", "!", "{")


def _runs(run, script):
    """Count shell command segments that EXECUTE script (./x.sh, bash x.sh, sh x.sh, source x.sh, dir/x.sh).
    Reading (cat x.sh), editing (edit tool path) or grepping it is not a run. Denied calls never ran."""
    n = 0
    for c in _calls(run):
        if not re.search(r"(^|__)shell$", c.get("name", "shell")):
            continue
        for seg in re.split(r"&&|\|\||[;|&\n()]", str((c.get("args") or {}).get("command", ""))):
            toks = [t for t in seg.strip().split() if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t)]
            while toks and toks[0] in SHELL_KW + ("timeout", "time", "env", "nice", "exec", "command", "nohup"):
                toks = toks[1:]           # 'if [ -f x.sh ]; then bash x.sh': the segment starts with 'then'
                while toks and (toks[0].startswith("-") or re.match(r"^\d+[smh]?$", toks[0])):
                    toks = toks[1:]
            if not toks:
                continue
            if toks[0] in INTERP:
                if "-n" in toks[1:]:          # bash -n: syntax check only, nothing executes
                    continue
                rest = [t for t in toks[1:] if not t.startswith("-")]
                target, ok = (rest[0] if rest else ""), True
            else:
                target, ok = toks[0], "/" in toks[0]
            if ok and target.strip("'\"").rsplit("/", 1)[-1] == script:
                n += 1
    return n


def _calls(run):
    return [c for c in run["calls"] if not c.get("denied_by")]


def check(test, run, chk):
    kind = next(k for k in chk if k != "turn")
    arg, turn = chk[kind], chk.get("turn")
    b, a = run["before"], run["after"]
    if kind == "probe":
        txt = _turn(run, "last")
        exp = run.get("variant_headings") or []
        if not exp:
            return bool(re.search(r"\bNONE\b", txt)), "control expects NONE"
        miss = [h for h in exp if h.lower() not in txt.lower()]
        return not miss, f"missing headings: {miss}" if miss else f"{len(exp)} headings listed"
    if kind == "text_has":
        ok = bool(re.search(_pat(test, arg), _turn(run, turn)))
        return ok, f"/{arg}/ {'found' if ok else 'not found'} in turn {turn or 'last'}"
    if kind == "prose_has":   # like text_has, but fenced and inline code are removed first
        ok = bool(re.search(_pat(test, arg), _prose(_turn(run, turn))))
        return ok, f"/{arg}/ {'found' if ok else 'not found'} in prose of turn {turn or 'last'}"
    if kind == "text_lacks":
        m = re.search(_pat(test, arg), _turn(run, turn))
        return not m, f"found {m.group(0)!r}" if m else "absent"
    if kind == "text_has_n":
        txt = _turn(run, turn)
        hits = [r for r in arg["res"] if re.search(re.escape(r), txt)]
        return len(hits) >= arg["n"], f"{len(hits)}/{len(arg['res'])} items (need {arg['n']})"
    if kind == "asks":   # a question, or an explicit request to the user for information
        txt = _turn(run, turn)
        if "?" in txt:
            return True, "question in reply"
        m = ASK_RE.search(txt)
        return bool(m), f"request in reply: '{m.group(0)}'" if m else "no question or request in reply"
    if kind == "max_chars":   # the final answer (text before a hook retry or tool call is working text)
        n = len(_answer(run, turn).strip())
        return n <= arg, f"{n} chars (max {arg})"
    if kind == "max_lines":
        # final answer without fenced blocks: a hook-required plan line and quoted tool output are not mentions
        lines = [l for l in _prose(_answer(run, turn), inline=False).splitlines() if re.search(arg["re"], l)]
        return len(lines) <= arg["n"], f"{len(lines)} matching lines (max {arg['n']})"
    if kind == "unchanged":
        bad = [p for p in arg if b.get(p, {}).get("sha") != a.get(p, {}).get("sha")]
        return not bad, f"changed/removed: {bad}" if bad else "unchanged"
    if kind == "changed":
        bad = [p for p in arg if b.get(p, {}).get("sha") == a.get(p, {}).get("sha")]
        return not bad, f"not changed: {bad}" if bad else "changed"
    if kind == "absent":
        bad = [p for p in arg if p in a or p + "/" in a]
        return not bad, f"present: {bad}" if bad else "absent"
    if kind == "file_has":
        bad = [p for p, r in arg.items() if not re.search(r, _text(a.get(p)), re.M)]
        return not bad, f"no match in {bad}" if bad else "matched"
    if kind == "file_lacks":
        bad = [p for p, r in arg.items() if re.search(r, _text(a.get(p)), re.M)]
        return not bad, f"matched in {bad}" if bad else "absent"
    if kind == "rename_only":
        bad = []
        for p, (old, new) in arg.items():
            want = re.sub(rf"\b{re.escape(old)}\b", new, _text(b.get(p)))
            if _text(a.get(p)) != want:
                bad.append(p)
        return not bad, f"more than a rename in {bad}" if bad else "rename only"
    if kind == "called":
        ok = any(re.search(arg, _call_str(c)) for c in _calls(run))
        return ok, f"call matching /{arg}/ {'made' if ok else 'not made'}"
    if kind == "not_called":
        hit = [_call_str(c)[:80] for c in _calls(run) if re.search(arg, _call_str(c))]
        return not hit, f"called: {hit}" if hit else "not called"
    if kind == "ran":
        n = _runs(run, arg)
        return n > 0, f"{arg} executed {n}x"
    if kind == "not_ran":
        n = _runs(run, arg)
        return n == 0, f"{arg} executed {n}x" if n else f"{arg} not executed"
    if kind == "max_runs":
        n = _runs(run, arg["script"])
        return n <= arg["n"], f"{arg['script']} executed {n}x (max {arg['n']})"
    if kind == "max_calls":
        n = sum(1 for c in run["calls"] if re.search(arg["re"], _call_str(c)))
        return n <= arg["n"], f"{n} calls matching /{arg['re']}/ (max {arg['n']})"
    if kind == "tool_used":
        n = len(_calls(run))
        return n > 0, f"{n} tool calls"
    if kind == "max_changed_lines":   # per file: max(lines added, lines removed) vs the start state (a 1-line edit = 1)
        bad = []
        for p, n in arg.items():
            d = [l for l in difflib.unified_diff(_text(b.get(p)).splitlines(), _text(a.get(p)).splitlines(), lineterm="", n=0)
                 if l[:1] in "+-" and not l.startswith(("+++", "---"))]
            k = max(sum(l[0] == "+" for l in d), sum(l[0] == "-" for l in d))
            if k > n:
                bad.append(f"{p}: {k}")
        return not bad, f"too many changed lines: {bad}" if bad else "within limit"
    if kind == "exists_re":   # some file in the final state matches (e.g. a compressed copy)
        hit = [p for p in a if re.search(arg, p)]
        return bool(hit), f"present: {hit}" if hit else f"no file matches /{arg}/"
    if kind == "any_of":
        res = [check(test, run, c) for c in arg]
        return any(ok for ok, _ in res), " | ".join(d for _, d in res)
    raise ValueError(f"unknown check {kind}")


def grade(test, run):
    results = []
    for chk in test["checks"]:
        ok, detail = check(test, run, chk)
        results.append((next(k for k in chk if k != "turn"), ok, detail))
    return ("PASS" if all(ok for _, ok, _ in results) else "FAIL"), results
