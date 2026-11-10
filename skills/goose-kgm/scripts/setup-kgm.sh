#!/usr/bin/env bash
# setup-kgm.sh — Add KG Memory MCP extension to Goose config (disabled by default)
# Usage: bash setup-kgm.sh [--dry-run]
set -euo pipefail

DRY_RUN=false
CHANGES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
  esac
done

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-kgm" "1.8.0" 2>/dev/null || true

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
  if $DRY_RUN; then echo "DRY_RUN_RESULT=CONVERGED"; fi
  exit 0
fi

if $DRY_RUN; then
  echo "[dry-run] WOULD: Add knowledgegraphmemory extension to $CONFIG"
  CHANGES=$((CHANGES + 1))
  echo "[dry-run] WOULD: Ensure symlinks for server-memory"
  CHANGES=$((CHANGES + 1))
  echo ""
  echo "DRY_RUN_RESULT=PENDING"
  echo "Changes: ${CHANGES}"
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

# ── Symlink: server-memory default path → our managed index ───────
# Goose does not pass MEMORY_FILE_PATH env to the MCP process.
# Symlink the server's default memory.jsonl to our managed JSONL.
# Search all known npx cache locations.
bash "$(cd "$(dirname "$0")" && pwd)/ensure-kgm-symlink.sh"

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
