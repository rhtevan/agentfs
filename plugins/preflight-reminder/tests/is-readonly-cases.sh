#!/usr/bin/env bash
# Regression cases for scripts/is-readonly.sh (exit 0 = read-only, 1 = mutating).
# Run after every change: bash tests/is-readonly-cases.sh  -> prints failures, exit 1 on any.
# Added 1.7.0 (2026-11-24) after three bypasses were found in a live session.
set -uo pipefail
I="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/is-readonly.sh"
fail=0; n=0
check() {  # expected-exit command
  n=$((n + 1)); bash "$I" "$2"; local got=$?
  [[ $got == "$1" ]] || { echo "FAIL expected $1 got $got :: $2"; fail=1; }
}
RO=0; MUT=1

# --- read-only ---
check $RO 'git status --short'
check $RO 'git -C ~/.agents log -1'
check $RO '[[ -f x ]] && echo y'
check $RO 'A=1'
check $RO 'T=/x/y; bash ~/.agents/skills/agentfs-eval/scripts/template-check.sh "$T" 2>&1'
check $RO 'bash ~/.agents/skills/agentfs-eval/scripts/agentfs-check.sh /x 2>&1'
check $RO 'bash ~/.agents/scripts/update-compliance.sh --check 2>&1'
check $RO 'bash ~/.agents/skills/agentfs-setup/scripts/static-sheet-status.sh'
check $RO 'bash skills/agentfs-git-push/scripts/resolve-target.sh'
check $RO 'bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh f "desc"'
check $RO 'bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh clear'
check $RO 'sqlite3 -readonly db "select 1;" > /tmp/out.txt'
check $RO 'grep -n x f >> /tmp/a/b.log 2>/dev/null'
check $RO 'wc -l $(git ls-files)'
check $RO 'echo "$(date)"'
check $RO 'echo $((1 + 2))'
check $RO 'X=`date`'
check $RO 'cat a 2>&1 | head'
check $RO 'find ~ -maxdepth 2 \( -name a -o -name b \) 2>/dev/null | head'
check $RO 'for p in $(pgrep -f x); do [[ $(cat /proc/$p/comm) == node ]] && echo $p; done'
check $RO '(cd /x && ls)'
check $RO 'grep -n x \
  f.txt | head'
check $MUT 'echo x \
  && rm -rf /y'
check $RO 'echo a
# a comment line
ls'
check $RO 'P=~/.agents/skills/agentfs-setup/scripts/post-write.sh; bash $P f "d"'
check $RO 'S=~/.agents/skills/agentfs-setup/scripts; bash ${S}/post-write.sh f "d"'
check $RO 'I=$(ls index-*.js); grep -oE ".{70}[^A-Za-z_.\$](KK|qK)\(.{30}" $I | head'
check $RO 'for p in $(pgrep -f node); do echo "$p $(readlink /proc/$p/cwd)"; done'

# --- mutating ---
check $MUT 'bash ~/.agents/scripts/update-compliance.sh --tier T2 --remeasure'
check $MUT 'bash x/template-check.sh . > /home/x/out.txt'
check $MUT 'bash ~/.agents/scripts/run-parallel.sh real'
check $MUT 'update-compliance.sh --check-not'
check $MUT 'T=$PWD; rm -rf $T/x'
check $MUT 'FOO=bar python3 x.py'
check $MUT 'cat a > b'
check $MUT "sed -i 's/a/b/' f"
check $MUT 'ls; rm x'
check $MUT 'git push'
check $MUT 'python3 -c 1'
check $MUT 'find . -delete'
check $MUT 'X=$(rm -rf /tmp/a)'
check $MUT 'X=`rm -rf /tmp/a`; echo $X'
# 1.7.0 bypass: a mention of a bookkeeping script exempted the whole command
check $MUT 'rm -rf /home/x/proj; echo checkpoint.sh'
check $MUT "python3 -c 'open(\"x\",\"w\")'  # post-write.sh"
check $MUT 'sed -i s/a/b/ f.md # see post-write.sh'
check $MUT 'bash post-write.sh f d && rm -rf /x'
check $MUT "cd x && python3 - <<'EOF'
# post-write.sh never logs
open('f','w')
EOF"
# 1.7.0 bypass: command substitution inside arguments / double quotes
check $MUT 'echo $(rm -rf /x)'
check $MUT 'echo `rm -rf /x`'
check $MUT 'ls $(touch /x)'
check $MUT 'cat <(rm -rf /x)'
check $MUT 'echo "$(rm -rf /x)"'
check $MUT 'echo "$(cat a > /home/b)"'
# 1.7.0 /tmp redirect: traversal or other paths stay mutating
check $MUT 'cat a > /tmp/../home/x'
check $MUT 'cat a > ~/x'
check $MUT 'cat a > /tmpx'
check $MUT 'P=/x/rm.sh; bash $P'
check $MUT 'echo "$(ls $(rm -rf /x))"'
# 1.8.0 quote tokenizer: a quote inside the other kind, escaped \" and $'..'
check $MUT $'echo "it\'s" ; rm -rf /x ; echo \'y\''
check $RO  'grep -n "a\"b\|c" f.sh; sed -n 1,2p x.sh'
check $MUT "echo \$'a\\'b' ; rm -rf /x"
check $RO  "echo \$'a\\'b; rm'"
# 1.8.0 git: query subcommands read-only; branch creation / reflog expire mutating
check $RO  'git check-ignore -v x'
check $RO  'git -C ~/.agents check-ignore -q a/b'
check $RO  'git ls-tree HEAD'
check $RO  'git branch -a'
check $RO  'git branch --list "f*"'
check $MUT 'git branch newfeature'
check $MUT 'git reflog expire --all'
# 1.8.0 sqlite3/awk: only their own invocation is scanned
check $RO  'sqlite3 -readonly db "select * from t;" ; echo update done'
check $MUT 'sqlite3 db "select 1; drop table t;"'
check $MUT 'sqlite3 db ".output /home/x"'
check $MUT $'sqlite3 db <<EOF\nselect 1;\ninsert into t values(1);\nEOF'
check $RO  'awk "{print \$1}" f | grep "system("'
check $MUT "awk '{print > \"out.txt\"}' f"
check $MUT "awk 'BEGIN{system(\"rm x\")}'"
# 1.8.0 query-only subcommands
check $RO  'gsettings get org.gnome.x y'
check $MUT 'gsettings set org.gnome.x y z'
check $RO  'rpm -qa | grep goose'
check $RO  'rpm -qf /usr/bin/ls'
check $MUT 'rpm -e foo'
check $RO  'secret-tool lookup service x'
check $MUT 'secret-tool store --label x'
check $RO  'readelf -h /bin/ls'
# 1.8.0 scanner: '..' inside $(..) inside ".." is literal; awk literals are not operators
check $RO  $'echo "== $b: $(grep -c \'](\' $b/index.md) links; header: $(grep -m1 \'^type\' $b/index.md)"'
check $MUT $'echo "$(grep -c \'(\' f; rm -rf /x)"'
check $RO  "awk -F'|' -v p=\$p '{print p\" | \"\$5}' f"
check $MUT "awk '{print \$1 | \"sort\"}' f"

echo "is-readonly cases: $n run, $([[ $fail == 0 ]] && echo 'all pass' || echo 'FAILURES above')"
exit $fail
