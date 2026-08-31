#!/usr/bin/env bash
# enable-kgm.sh — Enable KG Memory MCP extension in Goose config
set -euo pipefail

CONFIG="$HOME/.config/goose/config.yaml"

if ! grep -q 'knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
  echo "❌ KGM extension not configured. Run setup-kgm.sh first."
  exit 1
fi

python3 << 'PYEOF'
import yaml, os

config_path = os.path.expanduser("~/.config/goose/config.yaml")

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

ext = config.get('extensions', {}).get('knowledgegraphmemory')
if ext and ext.get('enabled'):
    print("✅ KGM extension already enabled.")
else:
    config['extensions']['knowledgegraphmemory']['enabled'] = True
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print("✅ KGM extension enabled. Restart Goose session to activate.")
PYEOF
