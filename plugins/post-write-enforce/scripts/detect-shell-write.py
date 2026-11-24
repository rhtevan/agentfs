#!/usr/bin/env python3
"""post-write-enforce: flag .agents/ files written by a SHELL command.

Called by AfterShellExecution (matcher: \\.agents; goose runs it only after a
successful command). 1.5.0 (2026-11-24, F28): before this, only the write/edit
tools set the pending flag, so python3/sed -i/redirect edits under .agents/
never got the Rule 6 post-write reminder.

Detects write targets of: redirects (> >>), tee, sed -i / perl -i, cp, mv,
install, ln, touch, mkdir, rm, rmdir, unlink, git mv, git rm, and python3 /
python -c or heredoc bodies that write files. `cd DIR` and `VAR=value` are
tracked so relative paths resolve. Exempt (same as detect-write.sh):
log.md, index.md, CHANGELOG.md; plus dot-paths under .agents (.git, .traces,
.kgm-*.jsonl). A command that also RUNS post-write.sh is not flagged.

1.6.0: also runs on PostToolUseFailure (a failed shell command may have
written before failing; the event also fires for denied calls, so only
targets with evidence of a change are flagged). A post-write.sh run in the
same command covers only the files it was run on. Not detected (by design):
writes made inside a script the command runs (`bash some-script.sh`).

Test: DETECT_TEST_CMD="<cmd>" [DETECT_TEST_CWD=dir] detect-shell-write.py
prints one target per line and writes no flag. PW_ARGS_CMD="<cmd>"
[PW_ARGS_CWD=dir] prints the resolved post-write.sh file arguments ("*" if
one cannot be resolved) — used by clear-flag.sh.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time

EXEMPT = {"log.md", "index.md", "CHANGELOG.md"}
SEPS = {";", "&&", "||", "|", "&", "\n"}
REDIRS = {">", ">>", ">|", "&>", "&>>"}
# python-ish write indicators inside a -c string or heredoc body
PY_WRITE = re.compile(r"open\([^)]*['\"][wax]\+?b?['\"]|\.write_text\(|\.write_bytes\(|"
                      r"shutil\.(copy|move)|os\.(remove|unlink|rename|replace)\(|\.unlink\(")
PY_PATH = re.compile(r"['\"]([^'\"\s]+\.(?:md|sh|py|ya?ml|json|jsonl|txt|toml|cfg|conf|env))['\"]")
PY_OPEN_W = re.compile(r"open\(\s*([^,()]+?)\s*,\s*['\"][wax]")
PY_WRITE_TEXT = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\.write_(?:text|bytes)\(")
CLEAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "clear-flag.sh")


def expand(word, env, cwd):
    # 1.6.0: $PWD is the cd-tracked directory, not the hook process's PWD.
    word = re.sub(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?",
                  lambda m: cwd if m.group(1) == "PWD" and "PWD" not in env
                  else env.get(m.group(1), os.environ.get(m.group(1), m.group(0))), word)
    word = os.path.expanduser(word)
    if not os.path.isabs(word):
        word = os.path.join(cwd, word)
    return os.path.normpath(word)


def in_agents(path):
    if "$" in path or path.startswith("/tmp/"):  # unresolved variable / scratch space
        return False
    parts = path.split(os.sep)
    if ".agents" not in parts:
        return False
    rest = parts[parts.index(".agents") + 1:]
    if not rest or any(p.startswith(".") for p in rest):
        return False
    return parts[-1] not in EXEMPT and not re.search(r"\.(lock|tmp|bak[^/]*)$", parts[-1])


def inplace_files(prog, args):
    """Files edited by sed -i / perl -i: skip options and expression values."""
    files, script_given, k = [], False, 0
    while k < len(args):
        a = args[k]
        if a in {"-e", "-f", "--expression", "--file"} or (
                prog == "perl" and a.startswith("-") and not a.startswith("--") and a.endswith("e")):
            script_given, k = True, k + 2
            continue
        if a.startswith("-"):
            k += 1
            continue
        if not script_given and prog == "sed":
            script_given = True  # first operand is the sed script
        else:
            files.append(a)
        k += 1
    return files


def py_resolve(expr, code, argv, env, cwd, depth=0):
    """Paths a python write-call expression can name ([] = unresolved).
    A variable yields every value assigned to it (p='a.sh' ... p='SKILL.md')."""
    expr = expr.strip()
    m = re.match(r"^[rbf]?(['\"])(.+?)\1$", expr)
    if m:
        return [expand(m.group(2), env, cwd)]
    m = re.match(r"^sys\.argv\[(\d+)\]$", expr)
    if m:
        k = int(m.group(1)) - 1
        return [expand(argv[k], env, cwd)] if 0 <= k < len(argv) else []
    m = re.search(r"Path\.home\(\)\s*/\s*(['\"])(.+?)\1", expr)
    if m:
        return [os.path.normpath(os.path.join(os.path.expanduser("~"), m.group(2)))]
    m = re.search(r"(?:expanduser|Path)\(\s*(['\"])(.+?)\1\s*\)", expr)
    if m:
        return [expand(m.group(2), env, cwd)]
    if depth < 3 and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", expr):
        out = []
        for val in re.findall(r"(?m)(?:^|;)\s*" + expr + r"\s*=\s*([^;\n]+)", code):
            if val.strip() != expr:
                got = py_resolve(val, code, argv, env, cwd, depth + 1)
                if not got:
                    return []  # one unresolved assignment: treat the variable as unresolved
                out += got
        return out
    return []


def python_targets(code, argv, env, cwd):
    """Files a python -c / heredoc body writes. Resolved write calls win; an
    unresolved one (loop variable) falls back to existing .agents/ files named
    in the code, then to the working directory when it is under .agents/."""
    exprs = PY_OPEN_W.findall(code) + PY_WRITE_TEXT.findall(code)
    resolved = [py_resolve(e, code, argv, env, cwd) for e in exprs]
    hits = [p for ps in resolved for p in ps if in_agents(p)]
    if exprs and all(resolved):
        return list(dict.fromkeys(hits))
    named = []
    for lit in PY_PATH.findall(code):
        for base in (cwd, os.path.expanduser("~")):
            cand = expand(lit, env, base)
            if in_agents(cand) and os.path.isfile(cand):
                named.append(cand)
                break
    if hits or named:
        return hits + [p for p in named if p not in hits]
    return [f"{cwd}/ (python3 edit)"] if in_agents(os.path.join(cwd, "x")) else []


def split_heredocs(cmd):
    """Return (shell_text, {line_index: body}) with heredoc bodies removed."""
    lines, out, bodies, i = cmd.split("\n"), [], {}, 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", line)
        if m:
            term, body, i = m.group(1), [], i + 1
            while i < len(lines) and lines[i].strip() != term:
                body.append(lines[i])
                i += 1
            bodies[len(out) - 1] = "\n".join(body)
        i += 1
    return out, bodies


def segments(line):
    lex = shlex.shlex(line, posix=True, punctuation_chars=";&|<>")
    lex.whitespace_split = True
    lex.commenters = "#"
    seg = []
    try:
        for tok in lex:
            if tok in SEPS:
                if seg:
                    yield seg
                seg = []
            else:
                seg.append(tok)
    except ValueError:  # unbalanced quotes: fall back to a plain split
        seg = line.split()
    if seg:
        yield seg


def targets(cmd, cwd):
    env, found = {}, []
    lines, bodies = split_heredocs(cmd.replace("\\\n", " "))
    for li, line in enumerate(lines):
        body = bodies.get(li, "")
        for seg in segments(line):
            words, k = [], 0
            while k < len(seg):  # pull redirect targets out of the word list
                t = seg[k]
                if t in REDIRS and k + 1 < len(seg):
                    found.append((expand(seg[k + 1], env, cwd), False))
                    k += 2
                    continue
                if t in {"<", "<<", "<<-", ">&", "<&"} and k + 1 < len(seg):
                    k += 2
                    continue
                if t.isdigit() and k + 1 < len(seg) and seg[k + 1] in REDIRS | {">&"}:
                    k += 1
                    continue
                words.append(t)
                k += 1
            while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
                name, _, val = words[0].partition("=")
                if len(words) == 1:
                    env[name] = val
                words = words[1:]
            while words and words[0] in {"then", "do", "else", "!", "{", "(", "sudo", "command"}:
                words = words[1:]
            if not words:
                continue
            w0, args = os.path.basename(words[0]), words[1:]
            plain = [a for a in args if not a.startswith("-")]
            if w0 == "cd":
                cwd = expand(plain[0] if plain else "~", env, cwd)
            elif w0 == "tee":
                found += [(expand(a, env, cwd), False) for a in plain]
            elif w0 in {"sed", "perl"} and any(re.match(r"^-[a-zA-Z]*i", a) for a in args):
                found += [(expand(a, env, cwd), False) for a in inplace_files(w0, args)]
            elif w0 in {"cp", "install", "ln"} and plain:
                found.append((expand(plain[-1], env, cwd), False))
            elif w0 == "mv" and len(plain) >= 2:
                found.append((expand(plain[-1], env, cwd), False))
                found += [(expand(a, env, cwd), True) for a in plain[:-1]]
            elif w0 == "touch":
                found += [(expand(a, env, cwd), False) for a in plain]
            elif w0 in {"rm", "rmdir", "unlink"}:
                found += [(expand(a, env, cwd), True) for a in plain]
            elif w0 == "git" and args:
                sub = args[2:] if args[0] == "-C" and len(args) > 2 else args
                gcwd = expand(args[1], env, cwd) if args[0] == "-C" and len(args) > 1 else cwd
                gplain = [a for a in sub[1:] if not a.startswith("-")]
                if sub and sub[0] == "rm":
                    found += [(expand(a, env, gcwd), True) for a in gplain]
                elif sub and sub[0] == "mv" and len(gplain) >= 2:
                    found.append((expand(gplain[-1], env, gcwd), False))
                    found += [(expand(a, env, gcwd), True) for a in gplain[:-1]]
            elif re.match(r"^python[0-9.]*$", w0):
                code = body
                if "-c" in args and args.index("-c") + 1 < len(args):
                    code = args[args.index("-c") + 1]
                if code and PY_WRITE.search(code):
                    argv = [a for a in args if a != "-c" and a != code][1:] if args[:1] == ["-"] else args
                    found += [(p, False) for p in python_targets(code, argv, env, cwd)]
    seen, out = set(), []
    for path, deleted in found:
        if path in seen:
            continue
        if path.endswith("(python3 edit)") or in_agents(path):
            seen.add(path)
            out.append(f"{path} (deleted)" if deleted else path)
    return out


def post_write_args(cmd, cwd):
    """1.6.0: resolved file argument of each post-write.sh run in cmd.

    Returns a list of paths, or None when a run's file argument cannot be
    resolved (unset $VAR, missing) — callers then treat it as "all files".
    """
    env, out = {}, []
    lines, _ = split_heredocs(cmd.replace("\\\n", " "))
    for line in lines:
        for seg in segments(line):
            words = [t for t in seg if t not in REDIRS]
            while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
                name, _, val = words[0].partition("=")
                if len(words) == 1:
                    env[name] = val
                words = words[1:]
            while words and words[0] in {"then", "do", "else", "!", "{", "(", "time"}:
                words = words[1:]
            if not words:
                continue
            if os.path.basename(words[0]) == "cd":
                plain = [a for a in words[1:] if not a.startswith("-")]
                cwd = expand(plain[0] if plain else "~", env, cwd)
                continue
            if os.path.basename(words[0]) in {"bash", "sh"}:
                words = [w for w in words[1:] if not w.startswith("-")]
            if not words or os.path.basename(expand(words[0], env, cwd)) != "post-write.sh":
                continue
            if len(words) < 2:
                return None
            path = expand(words[1], env, cwd)
            if "$" in path:
                return None
            out.append(path)
    return out


def changed_recently(hit, window=600):
    if hit.endswith("(python3 edit)"):
        return False  # no concrete file to check
    if hit.endswith(" (deleted)"):
        return not os.path.lexists(hit.removesuffix(" (deleted)"))
    try:
        return time.time() - os.lstat(hit).st_mtime < window
    except OSError:
        return False


def runs_post_write(cmd):
    r = subprocess.run(["bash", CLEAR], env={**os.environ, "CLEAR_FLAG_TEST_CMD": cmd},
                       stdin=subprocess.DEVNULL, capture_output=True)
    return r.returncode == 0


def main():
    test = os.environ.get("DETECT_TEST_CMD")
    if test is not None:
        print("\n".join(targets(test, os.environ.get("DETECT_TEST_CWD", os.getcwd()))))
        return
    pw_cmd = os.environ.get("PW_ARGS_CMD")
    if pw_cmd is not None:  # helper for clear-flag.sh: "*" = unresolved (clear all)
        args = post_write_args(pw_cmd, os.environ.get("PW_ARGS_CWD") or os.getcwd())
        print("*" if args is None else "\n".join(args))
        return
    payload = json.load(sys.stdin)
    cmd = (payload.get("tool_input") or {}).get("command") or payload.get("matcher_context") or ""
    sid = payload.get("session_id")
    if not cmd or not sid:
        return
    cwd = payload.get("working_dir") or os.getcwd()
    hits = targets(cmd, cwd)
    # 1.6.0: a post-write.sh run in the same command covers only the files it
    # was run on (was: any run suppressed every hit). Unresolved arg -> all.
    if hits and runs_post_write(cmd):
        done = post_write_args(cmd, cwd)
        if not done:
            return
        hits = [h for h in hits if h.removesuffix(" (deleted)") not in done]
    # 1.6.0 (F28 e): PostToolUseFailure also fires for a call denied by
    # approval policy, where nothing ran. Keep only targets with evidence of
    # a change: modified in the last 10 minutes, or gone if a deletion.
    if payload.get("event") == "PostToolUseFailure":
        hits = [h for h in hits if changed_recently(h)]
    if hits:
        os.makedirs("/tmp/goose-postwrite", exist_ok=True)
        with open(f"/tmp/goose-postwrite/{sid}", "a") as f:
            f.write("\n".join(hits) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:  # never break the session over a reminder
        pass
