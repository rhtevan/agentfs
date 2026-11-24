#!/usr/bin/env bash
# post-write-enforce: clear pending flag after post-write.sh runs.
# Called by AfterShellExecution when command matches post-write.sh (goose runs
# it only after a successful shell command).
# 1.4.0 (2026-11-24): the matcher is a substring test, so a command that only
# MENTIONED post-write.sh (grep, echo, a heredoc comment) cleared the flag.
# Now a segment must RUN it: `bash .../post-write.sh`, `.../post-write.sh`, or
# `bash $P` / `bash ${S}/post-write.sh` with P / S assigned earlier in the command.
# Test: CLEAR_FLAG_TEST_CMD="<command>" clear-flag.sh -> exit 0 runs it, 1 does not.
set -euo pipefail

runs_post_write() {  # $1 = shell command
  local cmd="${1//$'\\\n'/ }" seg w1 w2 rest script
  local -A vars=()
  # Hide quoted text so separators inside quotes do not split segments.
  cmd="$(printf '%s' "$cmd" | sed -E "s/'[^']*'/Q/g; s/\"[^\"]*\"/Q/g")"
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*(\(|\{)?[[:space:]]*//; s/^((do|then|else|if|!)[[:space:]]+)+//')"
    if [[ "$seg" =~ ^([A-Za-z_][A-Za-z0-9_]*)=([^[:space:]]*)[[:space:]]*$ ]]; then
      vars[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"; continue
    fi
    seg="$(printf '%s' "$seg" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//')"
    w1="${seg%% *}"; rest="${seg#"$w1"}"; rest="${rest# }"; w2="${rest%% *}"
    script="$w1"; [[ "${w1##*/}" == bash || "${w1##*/}" == sh ]] && script="$w2"
    if [[ "$script" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(.*)$ && -n "${vars[${BASH_REMATCH[1]}]:-}" ]]; then
      script="${vars[${BASH_REMATCH[1]}]}${BASH_REMATCH[2]}"
    fi
    [[ "${script##*/}" == post-write.sh ]] && return 0
  done < <(printf '%s\n' "$cmd" | sed -E 's/(\&\&|\|\||;|\|)/\n/g')
  return 1
}

if [[ -n "${CLEAR_FLAG_TEST_CMD:-}" ]]; then runs_post_write "$CLEAR_FLAG_TEST_CMD"; exit; fi

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // .matcher_context // ""')"
runs_post_write "$command" || exit 0

flag_file="/tmp/goose-postwrite/${session_id}"
[[ -f "$flag_file" ]] || exit 0
# 1.5.0 (plugin 1.6.0): remove only the files post-write.sh was run on, so
# `post-write.sh A` no longer clears a pending B (also a race when a write and
# a post-write for another file run in one parallel batch). A file argument
# that cannot be resolved, or a helper failure, clears everything (as before).
# "(python3 edit)" entries have no concrete file: any post-write run clears them.
cwd="$(printf '%s' "$payload" | jq -r '.working_dir // ""')"
done_paths="$(PW_ARGS_CMD="$command" PW_ARGS_CWD="${cwd:-$PWD}" \
  python3 "$(dirname "$0")/detect-shell-write.py" 2>/dev/null || echo '*')"
if [[ -z "$done_paths" || "$done_paths" == *'*'* ]]; then rm -f "$flag_file"; exit 0; fi
remaining="$(grep -v -x -F -f <(printf '%s\n' "$done_paths"; printf '%s\n' "$done_paths" | sed 's/$/ (deleted)/') "$flag_file" \
  | grep -v '(python3 edit)$' || true)"
if [[ -z "$remaining" ]]; then rm -f "$flag_file"; else printf '%s\n' "$remaining" > "$flag_file"; fi
