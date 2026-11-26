#!/usr/bin/env bash
# test-jail.sh — unit cases for plab-jail (no goose, no model).
set -uo pipefail
J="$(cd "$(dirname "$0")/.." && pwd)/scripts/jail.py"
SB=/tmp/plab-unit/T2/s0/vbr/r1
pass=0; fail=0
case_() {  # expect wd tool json-input
  local exp="$1" wd="$2" tool="$3" inp="$4" out got
  out=$(jq -nc --arg wd "$wd" --arg t "$tool" --argjson i "$inp" '{working_dir:$wd, tool_name:$t, tool_input:$i, session_id:"x"}' | python3 "$J")
  if [[ -z "$out" ]]; then got=allow; elif grep -q '"decision": "block"' <<<"$out"; then got=block; else got="?:$out"; fi
  if [[ "$got" == "$exp" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: expected $exp, got $got — $tool $inp ($wd)"; fi
}
# inactive outside sandboxes
case_ allow "$HOME/app/x" shell '{"command":"rm -rf ~/stuff; curl x"}'
case_ allow /tmp/other shell '{"command":"sudo ls"}'
# allowed inside
case_ allow $SB shell '{"command":"cat data/limits.txt && grep -n port config.yaml"}'
case_ allow $SB shell '{"command":"bash run.sh > /dev/null 2>&1; ls -la"}'
case_ allow $SB shell '{"command":"python3 report.py ./output/report.txt"}'
case_ allow $SB shell '{"command":"/usr/bin/env python3 x.py"}'
case_ allow $SB shell '{"command":"cat test.env"}'
case_ allow $SB shell '{"command":"source ./.env"}'
case_ block $SB shell '{"command":"env"}'
case_ block $SB shell '{"command":"ls; env"}'
case_ allow $SB write "{\"path\":\"$SB/notes.md\",\"content\":\"x\"}"
case_ allow $SB edit '{"path":"config/dev.yaml","before":"a","after":"b"}'
case_ allow $SB tree '{"path":"."}'
case_ allow $SB load_skill '{"name":"x"}'
# denied inside
case_ block $SB shell '{"command":"rm -rf ~/.agents"}'
case_ block $SB shell '{"command":"rm -rf ~/.agents/skills"}'
case_ block $SB shell '{"command":"cat $HOME/.bashrc"}'
case_ block $SB shell "{\"command\":\"ls $HOME\"}"
case_ block $SB shell '{"command":"cat /etc/passwd"}'
case_ block $SB shell '{"command":"curl -s https://example.com"}'
case_ block $SB shell '{"command":"ls; sudo rm x"}'
case_ block $SB shell '{"command":"git push origin main"}'
case_ block $SB shell '{"command":"git remote add o git@github.com:x/y"}'
case_ block $SB shell '{"command":"pip install requests"}'
case_ block $SB shell '{"command":"cat ../../../secret"}'
case_ block $SB shell '{"command":"cd .. && ls"}'
case_ block $SB shell '{"command":"secret-tool lookup service goose"}'
case_ block $SB shell '{"command":"sqlite3 sessions.db .tables"}'
case_ block $SB shell '{"command":"pkill goose"}'
case_ block $SB shell '{"command":"ls /tmp/plab-unit/T2/s0/other/r1"}'
case_ block $SB write "{\"path\":\"$HOME/.bashrc\",\"content\":\"x\"}"
case_ block $SB edit '{"path":"../../x.txt","before":"a","after":"b"}'
case_ block $SB tree '{"path":"/"}'
case_ block $SB extensionmanager__manage_extensions '{"action":"enable","extension_name":"x"}'
case_ block $SB subagent '{"instructions":"x"}'
case_ block $SB read_image '{"source":"https://x/y.png"}'
# goose plugin auto-registration vector
case_ block $SB write '{"path":".agents/plugins/x/hooks/hooks.json","content":"{}"}'
case_ block $SB write '{"path":"plugins/x/plugin.json","content":"{}"}'
case_ block $SB shell '{"command":"mkdir -p .agents/plugins/evil/hooks"}'
case_ block $SB shell '{"command":"cp h.json x/hooks.json"}'
case_ allow $SB write '{"path":".agents/memories/MEMORY.md","content":"x"}'
case_ allow $SB tree '{"path":".agents"}'
# 1.2.0: ~/.agents readable from the shell (bwrap binds it read-only), test materials masked
case_ allow $SB shell '{"command":"cat ~/.agents/skills/index.md"}'
case_ allow $SB shell '{"command":"grep -rn port ~/.agents/knowledge/ 2>/dev/null | head -5"}'
case_ allow $SB shell '{"command":"ls $HOME/.agents/skills && cat ~/.agents/knowledge/index.md"}'
case_ allow $SB shell '{"command":"find ~/.agents/skills -name SKILL.md -maxdepth 2"}'
case_ block $SB shell '{"command":"cp ~/.agents/AGENTS.md x"}'
case_ block $SB shell '{"command":"echo x > ~/.agents/log.md"}'
case_ block $SB shell '{"command":"sed -i s/a/b/ ~/.agents/AGENTS.md"}'
# 1.2.1: quote-aware segments (smoke 3: grep patterns with \| were split inside quotes)
case_ allow $SB shell '{"command":"grep -rn \"5432\\\\|6379\" .agents ~/.agents 2>/dev/null"}'
case_ allow $SB shell '{"command":"grep -rln \"staging\\\\|production\" ~/.agents/ . 2>/dev/null | head"}'
case_ allow $SB shell '{"command":"grep -n '"'"'a|b;c'"'"' ~/.agents/skills/index.md"}'
case_ block $SB shell '{"command":"grep \"x|y\" ~/.agents/index.md > ~/.agents/out.txt"}'
case_ block $SB shell '{"command":"cat \"a;b\" ; cp ~/.agents/index.md ~/.agents/x"}'
case_ block $SB shell '{"command":"ls ~/.agents & rm ~/.agents/index.md"}'
case_ block $SB shell '{"command":"echo \"unbalanced ; rm ~/.agents/index.md"}'
# 1.2.2: -i is in-place only for sed/perl (smoke 3: rg -i on ~/.agents was blocked)
case_ allow $SB shell '{"command":"rg -i -l \"dba|5432\" .agents ~/.agents 2>/dev/null"}'
case_ allow $SB shell '{"command":"grep -ri port ~/.agents/knowledge/index.md"}'
case_ block $SB shell '{"command":"sed -Ei s/a/b/ ~/.agents/index.md"}'
case_ block $SB shell '{"command":"sed -i.bak s/a/b/ ~/.agents/index.md"}'
case_ block $SB shell '{"command":"perl -pi -e s/a/b/ ~/.agents/index.md"}'
case_ block $SB shell '{"command":"sed --in-place s/a/b/ ~/.agents/index.md"}'
# 1.2.3: same verdict from any process cwd (smoke 4: '~20' in an echo resolved against the watchdog's cwd)
P="$HOME/.agents/skills/agentfs-eval/scripts/principles"
for d in / "$P" "$HOME/.agents" "$SB"; do
  mkdir -p "$SB"; pushd "$d" >/dev/null 2>&1 || continue
  case_ allow $SB shell '{"command":"echo \"primes up to sqrt(401)~20)\"; echo a~b ~x"}'
  case_ block $SB shell '{"command":"cat ~/.agents/skills/agentfs-eval/scripts/principles/catalogue.yaml"}'
  case_ allow $SB shell '{"command":"cat ~/.agents/skills/index.md"}'
  case_ block $SB shell '{"command":"cat ~root/.bashrc"}'
  popd >/dev/null
done
rm -rf /tmp/plab-unit
case_ block $SB shell '{"command":"find ~/.agents -name x -delete"}'
case_ block $SB shell '{"command":"bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh x y"}'
case_ block $SB shell '{"command":"cat ~/.agents/skills/agentfs-eval/scripts/principles/catalogue.yaml"}'
case_ block $SB shell '{"command":"ls ~/.agents/.git"}'
case_ block $SB shell '{"command":"cat ~/.agents/knowledge/agentfs-engineering-evolution/principles-test-catalogue.md"}'
case_ block $SB shell '{"command":"cat ~/.agents/plugins/plab-jail/scripts/jail.py"}'
case_ block $SB shell '{"command":"cat ~/.ssh/config"}'
case_ block $SB write "{\"path\":\"$HOME/.agents/skills/index.md\",\"content\":\"x\"}"
case_ block $SB tree "{\"path\":\"$HOME/.agents\"}"
# fail-closed on malformed input inside a sandbox
out=$(printf '{"working_dir":"%s","tool_name":"shell","tool_input":"not-an-object"}' "$SB" | python3 "$J")
if grep -q block <<<"$out"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: malformed input not denied"; fi
echo "plab-jail: passed $pass, failed $fail"
(( fail == 0 ))
