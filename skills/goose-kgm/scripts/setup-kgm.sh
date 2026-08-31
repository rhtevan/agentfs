#!/usr/bin/env bash
# setup-kgm.sh — Add KG Memory MCP extension to Goose config (disabled by default)
set -euo pipefail

CONFIG="$HOME/.config/goose/config.yaml"
JSONL_DIR="$HOME/.agents/knowledge"
JSONL_PATH="$JSONL_DIR/.kgm-index.jsonl"
GITIGNORE="$HOME/.agents/.gitignore"

# ── Preflight ──────────────────────────────────────────────────────
if [[ ! -f "$CONFIG" ]]; then
  echo "❌ Goose config not found: $CONFIG"
  exit 1
fi

# Check if already configured
if grep -q 'knowledge-graph-memory\|knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
  echo "✅ KGM extension already configured in $CONFIG"
  echo "   Use enable-kgm.sh to enable it."
  exit 0
fi

# ── Add extension entry ────────────────────────────────────────────
# Insert after the 'extensions:' key using python for safe YAML manipulation
python3 << 'PYEOF'
import yaml, sys, os

config_path = os.path.expanduser("~/.config/goose/config.yaml")
jsonl_path = os.path.expanduser("~/.agents/knowledge/.kgm-index.jsonl")

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

if 'extensions' not in config:
    config['extensions'] = {}

config['extensions']['knowledgegraphmemory'] = {
    'enabled': False,
    'type': 'stdio',
    'name': 'Knowledge Graph Memory',
    'description': 'Deterministic search index over OKF knowledge bundles via MCP',
    'cmd': 'npx',
    'args': ['-y', '@modelcontextprotocol/server-memory'],
    'envs': {'MEMORY_FILE_PATH': jsonl_path},
    'env_keys': [],
    'timeout': 300,
}

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

print(f"✅ Added knowledgegraphmemory extension to {config_path}")
print(f"   MEMORY_FILE_PATH: {jsonl_path}")
print(f"   enabled: false (use enable-kgm.sh to activate)")
PYEOF

# ── Ensure JSONL directory exists ──────────────────────────────────
mkdir -p "$JSONL_DIR"

# ── Ensure .kgm-index.jsonl is gitignored ──────────────────────────
if [[ -f "$GITIGNORE" ]]; then
  if ! grep -q '.kgm-index.jsonl' "$GITIGNORE" 2>/dev/null; then
    echo '.kgm-index.jsonl' >> "$GITIGNORE"
    echo "✅ Added .kgm-index.jsonl to $GITIGNORE"
  fi
else
  echo '.kgm-index.jsonl' > "$GITIGNORE"
  echo "✅ Created $GITIGNORE with .kgm-index.jsonl"
fi
