#!/bin/bash
# plab-shell.sh — GOOSE_SHELL for principles-lab test sessions (hard boundary).
#
# goose runs every shell tool call as "$GOOSE_SHELL -c <command>". The runner
# sets GOOSE_SHELL to this file and PLAB_SANDBOX to the run's sandbox dir, so
# each command runs inside bubblewrap:
#   - / is read-only; the sandbox is the only writable bind
#   - $HOME, /tmp and /run/user are empty tmpfs (no credentials, keyring
#     socket, goose DB, ~/.agents library, other sandboxes or repos visible)
#   - no network (--unshare-net); own pid/ipc namespaces; dies with goose
#   - clean environment (--clearenv): provider keys never reach the model
#   - the sandbox's .agents/ is read-only (goose auto-registers .agents/plugins
#     dirs into the global config; a sandbox plugin must never be created)
#   - ~/.agents is visible READ-ONLY (the Rules point models at its indexes,
#     skills and knowledge), with test materials masked: the principles runner
#     (answer key), plugins (jail internals), .git (history holds both), .traces,
#     and the principles knowledge docs
#   - CPU 120 s, file size 512 MB (ulimit -f counts 1 KiB blocks), 256 processes
#   - a dummy git identity (no ~/.gitconfig in the empty home)
# Fail-closed: without a valid PLAB_SANDBOX (or bwrap) nothing runs.
set -u
SB="${PLAB_SANDBOX:-}"
if [[ ! "$SB" =~ ^/tmp/plab-[A-Za-z0-9_.-]+/ || ! -d "$SB" ]]; then
  echo "plab-shell: refusing to run: PLAB_SANDBOX unset or not a /tmp/plab-* directory" >&2; exit 126
fi
A="$HOME/.agents"; K="$A/knowledge/agentfs-engineering-evolution"
for m in "$A/skills/agentfs-eval/scripts/principles" "$A/plugins" "$A/.git" \
         "$K/principles-test-catalogue.md" "$K/mcacs-principles-for-agentfs.md"; do
  [[ -e "$m" ]] || { echo "plab-shell: refusing to run: mask target missing: $m" >&2; exit 126; }
done
OPT=(); [[ -d "$A/.traces" ]] && OPT=(--tmpfs "$A/.traces")   # gitignored session traces, optional
command -v bwrap >/dev/null || { echo "plab-shell: bwrap not found; refusing to run unconfined" >&2; exit 126; }
exec bwrap \
  --ro-bind / / --dev /dev --proc /proc \
  --tmpfs /tmp --tmpfs "$HOME" --tmpfs /run/user \
  --ro-bind-try "$A" "$A" \
  --tmpfs "$A/skills/agentfs-eval/scripts/principles" --tmpfs "$A/plugins" \
  --tmpfs "$A/.git" "${OPT[@]}" \
  --ro-bind /dev/null "$K/principles-test-catalogue.md" \
  --ro-bind /dev/null "$K/mcacs-principles-for-agentfs.md" \
  --bind "$SB" "$SB" --ro-bind-try "$SB/.agents" "$SB/.agents" \
  --unshare-net --unshare-pid --unshare-ipc --die-with-parent --new-session \
  --clearenv --setenv HOME "$HOME" --setenv USER "${USER:-user}" \
  --setenv PATH /usr/local/bin:/usr/bin:/bin --setenv LANG "${LANG:-C.UTF-8}" \
  --setenv TERM dumb --setenv PLAB_SANDBOX "$SB" \
  --setenv GIT_AUTHOR_NAME plab --setenv GIT_AUTHOR_EMAIL plab@localhost \
  --setenv GIT_COMMITTER_NAME plab --setenv GIT_COMMITTER_EMAIL plab@localhost \
  --chdir "$SB" \
  /bin/bash -c 'ulimit -t 120 -f 524288 -u 256 2>/dev/null; exec /bin/bash "$@"' plab-shell "$@"
