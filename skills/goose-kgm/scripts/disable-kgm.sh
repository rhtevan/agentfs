#!/usr/bin/env bash
# disable-kgm.sh — Disable KG Memory MCP extension in Goose config
set -euo pipefail

CONFIG="$HOME/.config/goose/config.yaml"

if ! grep -q 'knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
  echo "❌ KGM extension not configured. Nothing to disable."
  exit 1
fi

python3 << 'PYEOF'
import yaml, os

config_path = os.path.expanduser("~/.config/goose/config.yaml")

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

ext = config.get('extensions', {}).get('knowledgegraphmemory')
if ext and not ext.get('enabled'):
    print("✅ KGM extension already disabled.")
else:
    config['extensions']['knowledgegraphmemory']['enabled'] = False
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print("✅ KGM extension disabled. JSONL file preserved for re-enable.")
PYEOF
