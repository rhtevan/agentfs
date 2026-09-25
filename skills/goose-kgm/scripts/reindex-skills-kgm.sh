#!/usr/bin/env bash
# reindex-skills-kgm.sh — Generate KGM JSONL index from skill frontmatter
#
# Usage: bash reindex-skills-kgm.sh
#
# Reads ~/.agents/skills/index.md to discover skills, then generates
# AgentSkill entities with signal phrases and load_skill actions.
# Output: ~/.agents/skills/.kgm-skills.jsonl

set -euo pipefail

SKILLS_DIR="$HOME/.agents/skills"
INDEX="$SKILLS_DIR/index.md"
JSONL_PATH="$SKILLS_DIR/.kgm-skills.jsonl"

if [[ ! -f "$INDEX" ]]; then
  echo "❌ Skills index not found: $INDEX"
  exit 1
fi

python3 << 'PYEOF'
import json, re, os
from pathlib import Path

skills_dir = Path(os.path.expanduser("~/.agents/skills"))
index_path = skills_dir / "index.md"
jsonl_path = skills_dir / ".kgm-skills.jsonl"

index_text = index_path.read_text()

# Parse: | [name](./name/SKILL.md) | tags | signals/description | date |
pattern = re.compile(r'\|\s*\[([^\]]+)\]\([^)]+\)\s*\|[^|]*\|\s*([^|]+)\|')

entries = []
for m in pattern.finditer(index_text):
    name = m.group(1).strip()
    signals = m.group(2).strip()
    entity = {
        "type": "entity",
        "name": f"skill:{name}",
        "entityType": "AgentSkill",
        "observations": [
            f"Signals: {signals}",
            f'Action: load_skill(name: "{name}")'
        ]
    }
    entries.append(json.dumps(entity))

with open(jsonl_path, 'w') as f:
    for entry in entries:
        f.write(entry + '\n')

print(f"✅ Skills KGM index: {jsonl_path}")
print(f"   Skills indexed: {len(entries)}")
PYEOF
