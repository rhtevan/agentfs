#!/usr/bin/env bash
# Regression cases for scripts/detect-shell-write.py: which .agents/ files a
# shell command writes (one per line; empty = nothing to flag). Added 1.5.0.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/detect-shell-write.py"
H="$HOME"; fail=0; n=0
check() {  # expected (newline-separated, may be empty) command [cwd]
  n=$((n + 1))
  local got; got="$(DETECT_TEST_CMD="$2" DETECT_TEST_CWD="${3:-/home/u/proj}" python3 "$D")"
  [[ "$got" == "$1" ]] || { printf 'FAIL :: %s\n  expected: [%s]\n  got:      [%s]\n' "$2" "$1" "$got"; fail=1; }
}

# --- flagged ---
check "$H/.agents/skills/x/SKILL.md" "sed -i 's/a/b/' ~/.agents/skills/x/SKILL.md"
check "$H/.agents/skills/x/SKILL.md" "cd ~/.agents/skills/x && sed -i -e 's/a/b/' SKILL.md"
check "/home/u/proj/.agents/memories/MEMORY.md" "echo '- note' >> .agents/memories/MEMORY.md"
check "/home/u/proj/.agents/SOUL.md" "printf x | tee .agents/SOUL.md"
check "$H/.agents/skills/x/scripts/a.sh" "cp /tmp/a.sh ~/.agents/skills/x/scripts/a.sh"
check "$H/.agents/skills/x/b.md
$H/.agents/skills/x/a.md (deleted)" "mv ~/.agents/skills/x/a.md ~/.agents/skills/x/b.md"
check "$H/.agents/skills/x/old.sh (deleted)" "git -C ~/.agents rm skills/x/old.sh"
check "$H/.agents/skills/x/old.sh (deleted)" "rm -f ~/.agents/skills/x/old.sh"
check "$H/.agents/skills/agentfs-eval/scripts/agentfs-behavior.sh" "cd ~/.agents/skills/agentfs-eval/scripts && python3 - <<'EOF'
p='agentfs-behavior.sh'; s=open(p).read()
open(p,'w').write(s)
EOF"
check "$H/.agents/README.md" "cd ~/.agents && python3 - <<'EOF'
p='README.md'; s=open(p).read()
open(p,'w').write(s)
EOF"
check "$H/.agents/skills/y/ (python3 edit)" "cd ~/.agents/skills/y && python3 - <<'EOF'
import json
p=name(); open(p,'w').write('x')
EOF"
check "$H/.agents/knowledge/b/c.md" "K=~/.agents/knowledge/b; sed -i 's/a/b/' \$K/c.md"
check "$H/.agents/skills/z/SKILL.md" "perl -pi -e 's/a/b/' ~/.agents/skills/z/SKILL.md"

check "$H/.agents/skills/h/scripts/install.sh" "python3 - <<'EOF'
import pathlib
p=pathlib.Path.home()/\".agents/skills/h/scripts/install.sh\"; s=p.read_text()
p.write_text(s)
EOF"
check "$H/.agents/k/plan.md" "cd ~/.agents/k && python3 - plan.md <<'EOF'
import sys
p=sys.argv[1]; open(p,'w').write('x')
EOF"

check "$H/.agents/skills/g/scripts/rm-guard.sh
$H/.agents/skills/g/SKILL.md" "cd ~/.agents/skills/g && python3 - <<'EOF'
p='scripts/rm-guard.sh'; s=open(p).read(); open(p,'w').write(s)
p='SKILL.md'; s=open(p).read(); open(p,'w').write(s)
EOF"

# --- not flagged ---
check "" "rm -f .agents/log.md.lock; cp x ~/.agents/skills/a/CHANGELOG.md.tmp"
check "" "cd /tmp && python3 - <<'EOF'
I=os.path.expanduser('~/.agents/plugins/p/scripts/is-readonly.sh')
open('/tmp/out.txt','w').write(I)
EOF"
check "" "T=\$(mktemp); echo x > \$T; rm -f \$T"
check "" "R=\$(mktemp -d /tmp/t.XXXX) && cd \$R && mkdir -p .agents/memories && echo m > .agents/memories/MEMORY.md"
check "" "P=/tmp/hooktest/.agents/plugins/x; mkdir -p \$P/hooks; echo '{}' > \$P/plugin.json"
check "" "mkdir -p ~/.agents/skills/x/tests"
check "" "cd ~/.agents && git add -A && git commit -qm x && git push -q"
check "" "bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh create a b"
check "" "grep -rn x ~/.agents/skills | head > /tmp/out.txt"
check "" "sed -n 1,20p ~/.agents/skills/x/SKILL.md"
check "" "echo x >> ~/.agents/log.md"
check "" "sed -i 's/a/b/' ~/.agents/skills/index.md"
check "" "echo '{}' > ~/.agents/.traces/x.jsonl"
check "" "cd ~/.agents && python3 - <<'EOF'
print(open('README.md').read()[:10])
EOF"
check "" "cp ~/.agents/skills/x/a.sh /tmp/a.sh"
check "" "sed -i 's/a/b/' /home/u/proj/src/app.py"

echo "detect-shell-write cases: $n run, $([[ $fail == 0 ]] && echo 'all pass' || echo 'FAILURES above')"
exit $fail
