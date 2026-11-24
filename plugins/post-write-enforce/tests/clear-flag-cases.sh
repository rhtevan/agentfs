#!/usr/bin/env bash
# Regression cases for scripts/clear-flag.sh: 0 = the command RUNS post-write.sh
# (flag cleared), 1 = it only mentions it. Added 1.4.0 (2026-11-24).
set -uo pipefail
C="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/clear-flag.sh"
fail=0; n=0
check() { n=$((n + 1)); CLEAR_FLAG_TEST_CMD="$2" bash "$C"; local got=$?
  [[ $got == "$1" ]] || { echo "FAIL expected $1 got $got :: $2"; fail=1; }; }
check 0 'bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh f "d"'
check 0 'P=~/.agents/skills/agentfs-setup/scripts/post-write.sh; bash $P f "d"'
check 0 'S=~/x/scripts; bash ${S}/post-write.sh f d --version 1.0.0'
check 0 'cd ~/.agents && bash skills/agentfs-setup/scripts/post-write.sh a "b" 2>&1 | tail -3'
check 0 'bash -n x.sh && bash ~/a/post-write.sh x.sh "d"'
check 1 'grep -n post-write.sh f'
check 1 'echo "run post-write.sh next"'
check 1 'sed -n 1,30p ~/.agents/skills/agentfs-setup/scripts/post-write.sh'
check 1 "python3 - <<'X'
# post-write.sh
X"
echo "clear-flag cases: $n run, $([[ $fail == 0 ]] && echo 'all pass' || echo 'FAILURES above')"
exit $fail
