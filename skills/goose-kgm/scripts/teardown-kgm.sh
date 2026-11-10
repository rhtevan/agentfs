#!/usr/bin/env bash
# teardown-kgm.sh — Remove KG Memory MCP extension from Goose config
# Usage: bash teardown-kgm.sh [--dry-run]
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
JSONL_PATH="$HOME/.agents/knowledge/.kgm-index.jsonl"

# ── Dry-run check ──────────────────────────────────────────────────
if $DRY_RUN; then
  if grep -q 'knowledge-graph-memory\|knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
    echo "[dry-run] WOULD: Remove KGM extension from $CONFIG"
    CHANGES=$((CHANGES + 1))
  else
    echo "[dry-run] NO CHANGE — KGM extension not in config"
  fi
  if [[ -f "$JSONL_PATH" ]]; then
    echo "[dry-run] WOULD: Remove $JSONL_PATH"
    CHANGES=$((CHANGES + 1))
  else
    echo "[dry-run] NO CHANGE — JSONL file does not exist"
  fi
  echo ""
  if [[ $CHANGES -eq 0 ]]; then
    echo "DRY_RUN_RESULT=CONVERGED"
  else
    echo "DRY_RUN_RESULT=PENDING"
  fi
  echo "Changes: ${CHANGES}"
  exit 0
fi

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
