#!/usr/bin/env python3
"""plab-jail: PreToolUse guard for principles-lab test sessions.

Active ONLY when the session working_dir is under /tmp/plab-* (a principles
runner sandbox). Everywhere else it exits 0 silently (no-op).

Inside a sandbox session it is fail-closed:
  - tools outside the allowlist are denied (no subagents, no extension
    management, no scheduling);
  - write / edit / tree / read_image paths must resolve inside working_dir;
  - shell commands are denied when they name a banned command or a path
    outside the sandbox. This is the readable first line; the hard
    boundary for shell is plab-shell.sh (bubblewrap: read-only /, sandbox
    the only writable bind, no network, secrets masked, clean env).
  - any internal error -> deny.

policy(payload) is importable (the watchdog reuses it on recorded calls).
"""
import json, os, re, sys

ROOT_RE = re.compile(r"^/tmp/plab-[A-Za-z0-9_.-]+/")
ALLOWED_TOOLS = re.compile(
    r"(^|__)(shell|write|edit|tree|read_image|load_skill|todo_read|todo_write)$")
PATH_TOOLS = re.compile(r"(^|__)(write|edit|tree|read_image)$")
BANNED = re.compile(r"""(?x)(^|[\s;&|()`$]|\bxargs\s)(
    sudo|su|doas|pkexec|ssh|scp|sftp|rsync|curl|wget|nc|ncat|netcat|telnet|socat|ping|
    nmap|dig|nslookup|ftp|systemctl|service|journalctl|loginctl|crontab|at|batch|
    shutdown|reboot|poweroff|halt|mount|umount|mkfs(\.\w+)?|fdisk|parted|wipefs|
    kill|pkill|killall|podman|docker|kubectl|oc|crc|goose|gcloud|gsutil|aws|az|
    secret-tool|keyring|gpg|pip3?\s+install|npm|npx|yarn|pnpm|dnf|yum|rpm\s+-[iUe]|
    flatpak|snap|chown|chattr|setfacl|nohup|disown|setsid|screen|tmux
    )(?=$|[\s;&|()`])""")
GIT_NET = re.compile(r"\bgit\s+(-\S+\s+)*(push|pull|fetch|clone|remote|submodule|ls-remote|send-email)\b")
SECRET_WORDS = re.compile(r"(?i)(adc\.json|legacy_credentials|\.ssh/|id_rsa|id_ed25519|keyrings?/|"
                          r"sessions\.db|api[_-]?key|\.netrc|\.aws/|\.gnupg|/proc/\d+/environ|printenv|(?<![\w.$/-])env\s*$)")   # bare `env` command only; not test.env, .env, $env
ABS_PATH = re.compile(r"(?<![\w.~$/-])(~|\$HOME|\$\{HOME\}|/(?:home|root|etc|var|usr|opt|srv|boot|dev|proc|sys|run|mnt|media|tmp)\b)[^\s'\";|&)]*")
# goose auto-registers plugin dirs it finds under .agents/plugins into the GLOBAL
# config (observed 2026-11-24): a sandbox plugin would become an unconfined hook.
PLUGIN_PATH = re.compile(r"(^|/)\.agents/plugins(/|$)|(^|/)(hooks|plugin)\.json$|\.agents/?\s*$")
PLUGIN_WORDS = re.compile(r"\.agents/plugins|\bplugins/|hooks\.json|plugin\.json|\.config/goose")
# 1.2.0: the shell may READ ~/.agents (plab-shell binds it read-only; the Rules point models at its
# indexes, skills and knowledge). Test materials stay masked, and write-like commands on it are denied
# here too (second layer). write/edit/tree run unconfined inside goose: ~/.agents stays blocked for them.
AGENTS_HOME = os.path.realpath(os.path.expanduser("~/.agents"))
MASKED = tuple(os.path.join(AGENTS_HOME, m) for m in (
    "skills/agentfs-eval/scripts/principles", "plugins", ".git", ".traces",
    "knowledge/agentfs-engineering-evolution/principles-test-catalogue.md",
    "knowledge/agentfs-engineering-evolution/mcacs-principles-for-agentfs.md"))
READ_CMDS = {"cat", "ls", "head", "tail", "grep", "rg", "egrep", "find", "wc", "less", "more", "file", "stat",
             "tree", "awk", "sed", "sort", "uniq", "cut", "diff", "realpath", "readlink", "basename", "dirname",
             "test", "[", "echo", "printf", "md5sum", "sha256sum", "jq", "yq", "column", "nl", "bat", "cd"}
WRITE_HINT = re.compile(r"(?<![0-9&])>|>>|\s-delete\b|\s-exec(dir)?\b|\s-fprint")
# -i means in-place only for sed/perl (sed -i, -Ei, -i.bak; perl -pi); for grep/rg/sort/diff it is ignore-case
INPLACE = re.compile(r"\s-[A-Za-z]*i|--in-place")
INPLACE_CMDS = {"sed", "perl"}
SAFE_ABS = re.compile(r"^(/dev/null|/dev/stdout|/dev/stderr|/usr/bin/\w+|/bin/\w+|/usr/bin/env)$")


def _segments(cmd):
    """Split a shell command on && || ; | & newline, outside quotes. Unbalanced quotes:
    fall back to the plain split (more, smaller segments = stricter)."""
    out, buf, q, i = [], [], None, 0
    while i < len(cmd):
        ch = cmd[i]
        if q:
            buf.append(ch)
            if ch == "\\" and q == '"' and i + 1 < len(cmd):
                buf.append(cmd[i + 1]); i += 1
            elif ch == q:
                q = None
        elif ch == "\\" and i + 1 < len(cmd):
            buf += [ch, cmd[i + 1]]; i += 1
        elif ch in "'\"":
            q = ch; buf.append(ch)
        elif cmd.startswith(("&&", "||"), i):
            out.append("".join(buf)); buf = []; i += 1
        elif ch in ";|\n" or (ch == "&" and not (buf and buf[-1] in "<>") and cmd[i + 1:i + 2] != ">"):
            out.append("".join(buf)); buf = []
        else:
            buf.append(ch)
        i += 1
    if q:
        return re.split(r"&&|\|\||[;|&\n]", cmd)
    out.append("".join(buf))
    return out


def _agents_read(cmd, tok):
    """None if tok is not under ~/.agents; else (ok, reason) for a read-only shell use of it."""
    p = os.path.expanduser(tok.replace("${HOME}", "~").replace("$HOME", "~"))
    if not os.path.isabs(p):   # e.g. '~20' in text: relative, so the sandbox check decides; never resolve
        return None            # against the process cwd (hook and watchdog run in different dirs)
    p = os.path.realpath(p)
    if not (p == AGENTS_HOME or p.startswith(AGENTS_HOME + "/")):
        return None
    if any(p == m or p.startswith(m + "/") for m in MASKED):
        return False, f"'{tok}' is a masked test path (not available in the sandbox)"
    for seg in _segments(cmd):
        if tok not in seg:
            continue
        words = [w for w in seg.strip().split() if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w)]
        if (not words or words[0] not in READ_CMDS or WRITE_HINT.search(" " + seg)
                or (words[0] in INPLACE_CMDS and INPLACE.search(" " + seg))):
            return False, f"only reading ~/.agents is allowed in the sandbox ('{seg.strip()[:60]}')"
    return True, ""


def _inside(path, root):
    p = os.path.realpath(os.path.join(root, os.path.expanduser(path)))
    r = os.path.realpath(root)
    return p == r or p.startswith(r.rstrip("/") + "/")


def policy(payload):
    """Return (decision, reason). decision in {"allow", "block", "inactive"}."""
    wd = payload.get("working_dir") or ""
    if not ROOT_RE.match(wd.rstrip("/") + "/"):
        return "inactive", ""
    tool = payload.get("tool_name") or ""
    args = payload.get("tool_input") or {}
    if not ALLOWED_TOOLS.search(tool):
        return "block", f"tool '{tool}' is not allowed in a principles-lab sandbox"
    if PATH_TOOLS.search(tool):
        path = args.get("path") or args.get("source") or "."
        if re.match(r"^https?://", str(path)):
            return "block", "network sources are not allowed in the sandbox"
        if not _inside(str(path), wd):
            return "block", f"path '{path}' is outside the sandbox {wd}"
        if PLUGIN_PATH.search(str(path)) and not re.search(r"(^|__)(tree|read_image)$", tool):
            return "block", "creating goose plugin/hook files is not allowed in the sandbox"
        return "allow", ""
    if re.search(r"(^|__)shell$", tool):
        cmd = str(args.get("command") or "")
        m = BANNED.search(cmd)
        if m:
            return "block", f"command '{m.group(2).strip()}' is not allowed in the sandbox"
        if GIT_NET.search(cmd):
            return "block", "git network operations are not allowed in the sandbox"
        if PLUGIN_WORDS.search(cmd):
            return "block", "goose plugin/hook/config paths are not allowed in the sandbox"
        m = SECRET_WORDS.search(cmd)
        if m:
            return "block", f"'{m.group(1)}' refers to credentials or session data"
        for m in ABS_PATH.finditer(cmd):
            tok = m.group(0)
            if SAFE_ABS.match(tok):
                continue
            ag = _agents_read(cmd, tok)
            if ag is not None:
                if not ag[0]:
                    return "block", ag[1]
                continue
            expanded = tok.replace("${HOME}", "~").replace("$HOME", "~")
            if not _inside(expanded, wd):
                return "block", f"path '{tok}' is outside the sandbox {wd}"
        for tok in re.findall(r"[^\s'\";|&()<>=]*\.\.[^\s'\";|&()<>]*", cmd):
            if "/" in tok or tok == "..":
                if not _inside(tok, wd):
                    return "block", f"'{tok}' leaves the sandbox"
    return "allow", ""


def main():
    try:
        payload = json.load(sys.stdin)
        decision, reason = policy(payload)
    except Exception as e:  # fail closed, but only if we cannot tell where we are
        try:
            wd = payload.get("working_dir", "")  # noqa: F821
        except Exception:
            wd = ""
        if wd and not ROOT_RE.match(wd.rstrip("/") + "/"):
            return 0
        decision, reason = "block", f"plab-jail internal error ({type(e).__name__}); denied (fail-closed)"
    if decision == "block":
        print(json.dumps({"decision": "block",
                          "reason": f"Principles-lab sandbox: {reason}. Work only inside the current directory."}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
