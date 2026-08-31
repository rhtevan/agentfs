#!/usr/bin/env bash
# teardown-kgm.sh — Remove KG Memory MCP extension from Goose config
set -euo pipefail

CONFIG="$HOME/.config/goose/config.yaml"
JSONL_PATH="$HOME/.agents/knowledge/.kgm-index.jsonl"

# ── Remove extension entry ─────────────────────────────────────────
if ! grep -q 'knowledge-graph-memory\|knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
  echo "ℹ️  KGM extension not found in $CONFIG — nothing to remove."
else
  python3 << 'PYEOF'
import yaml, os

config_path = os.path.expanduser("~/.config/goose/config.yaml")

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

removed = False
for key in list(config.get('extensions', {}).keys()):
    if 'knowledge' in key.lower() and ('graph' in key.lower() or 'kgm' in key.lower()):
        del config['extensions'][key]
        removed = True

if removed:
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print(f"✅ Removed KGM extension from {config_path}")
else:
    print("ℹ️  KGM extension key not found — nothing to remove.")
PYEOF
fi

# ── Remove JSONL file ──────────────────────────────────────────────
if [[ -f "$JSONL_PATH" ]]; then
  rm -f "$JSONL_PATH"
  echo "✅ Removed $JSONL_PATH"
else
  echo "ℹ️  JSONL file not found — nothing to remove."
fi
