#!/usr/bin/env bash
# End-to-end cases for the pending-flag lifecycle (added 1.6.0): feeds real
# hook payloads to detect-shell-write.py and clear-flag.sh and checks the
# flag file. Uses a throwaway session id and a temp .agents tree; cleans up.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
SID="pwe-test-$$"; FLAG="/tmp/goose-postwrite/$SID"
# not /tmp (paths under /tmp are exempt) and not directly in $HOME (rm-guard)
mkdir -p "$HOME/.cache"; T="$(mktemp -d -p "$HOME/.cache" pwe-test.XXXX)"; mkdir -p "$T/.agents/skills/x"
trap 'rm -rf "$T" "$FLAG"' EXIT
fail=0; n=0
payload() {  # event command
  jq -cn --arg e "$1" --arg c "$2" --arg s "$SID" --arg w "$T" \
    '{event:$e, session_id:$s, tool_name:"shell", tool_input:{command:$c}, working_dir:$w}'
}
flag() { [[ -f "$FLAG" ]] && sort "$FLAG" | tr '\n' ' ' | sed 's/ $//'; }
check() {  # description expected-flag-content
  n=$((n + 1)); local got; got="$(flag)"
  [[ "$got" == "$2" ]] || { printf 'FAIL :: %s\n  expected: [%s]\n  got:      [%s]\n' "$1" "$2" "$got"; fail=1; }
}
A="$T/.agents/skills/x/a.md"; B="$T/.agents/skills/x/b.md"; PW="$HOME/.agents/skills/agentfs-setup/scripts/post-write.sh"

# 1. post_write_args helper
n=$((n + 1)); got="$(PW_ARGS_CMD="cd $T && bash $PW .agents/skills/x/a.md 'd'" python3 "$S/detect-shell-write.py")"
[[ "$got" == "$A" ]] || { echo "FAIL :: post_write_args relative+cd: [$got]"; fail=1; }
n=$((n + 1)); got="$(PW_ARGS_CMD='bash ~/p/post-write.sh "$F" d' python3 "$S/detect-shell-write.py")"
[[ "$got" == "*" ]] || { echo "FAIL :: post_write_args unresolved: [$got]"; fail=1; }

# 2. shell writes A and B; post-write A clears only A
rm -f "$FLAG"; echo x > "$A"; echo x > "$B"
payload AfterShellExecution "echo x > $A; echo x > $B" | python3 "$S/detect-shell-write.py"
check "two shell writes flagged" "$A $B"
payload AfterShellExecution "bash $PW $A 'desc'" | bash "$S/clear-flag.sh"
check "post-write A leaves B pending" "$B"
payload AfterShellExecution "bash $PW $B 'desc'" | bash "$S/clear-flag.sh"
check "post-write B clears the flag" ""

# 3. write + post-write of the same file in one command: nothing pending;
#    of another file: the other stays pending
payload AfterShellExecution "echo y > $A && bash $PW $A d" | python3 "$S/detect-shell-write.py"
check "write+post-write same file" ""
payload AfterShellExecution "echo y > $A && echo y > $B && bash $PW $A d" | python3 "$S/detect-shell-write.py"
check "write A,B + post-write A" "$B"
rm -f "$FLAG"

# 4. unresolved post-write argument clears everything (pre-1.6.0 behaviour)
printf '%s\n' "$A" "$B" > "$FLAG"
payload AfterShellExecution 'bash ~/x/post-write.sh "$F" d' | bash "$S/clear-flag.sh"
check "unresolved arg clears all" ""

# 5. "(python3 edit)" entries are cleared by any post-write run
printf '%s\n' "$T/.agents/ (python3 edit)" "$B" > "$FLAG"
payload AfterShellExecution "bash $PW $B d" | bash "$S/clear-flag.sh"
check "python3-edit entry cleared" ""

# 6. PostToolUseFailure: flag only targets with evidence of a change
rm -f "$FLAG"; echo z > "$A"; touch -d '2 hours ago' "$B"
payload PostToolUseFailure "sed -i s/z/q/ $A && false" | python3 "$S/detect-shell-write.py"
check "failed command, file just modified" "$A"
rm -f "$FLAG"
payload PostToolUseFailure "sed -i s/z/q/ $B" | python3 "$S/detect-shell-write.py"
check "denied/failed command, file untouched" ""
payload PostToolUseFailure "rm $B" | python3 "$S/detect-shell-write.py"
check "denied rm, file still exists" ""
rm -f "$B"
payload PostToolUseFailure "rm $B; false" | python3 "$S/detect-shell-write.py"
check "failed command after rm, file gone" "$B (deleted)"

echo "flag-lifecycle cases: $n run, $([[ $fail == 0 ]] && echo 'all pass' || echo 'FAILURES above')"
exit $fail
