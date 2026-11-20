#!/usr/bin/env bash
# setup-kgm.sh — Add (or migrate) the KG Memory MCP extension in Goose config
# Usage: bash setup-kgm.sh [--dry-run]
#
# WHY the `env` wrapper: Goose 1.60.1 never sends inline `envs` over ACP
# (config_to_goose_extension drops them; goose_extension_to_config_without_secrets
# forces them empty). Desktop sessions are built from that ACP listing, so an
# `envs`-only MEMORY_FILE_PATH never reaches the server, which then reads an
# empty default file. `cmd`/`args` survive every path (new session, toggle,
# extension manager, CLI), so the path is passed as `env MEMORY_FILE_PATH=… npx …`.
#
# States:
#   missing  → add entry (wrapper form, enabled: false)
#   legacy   → migrate cmd/args to the wrapper, drop MEMORY_FILE_PATH from envs
#              (enabled and all other keys are preserved)
#   current  → nothing to do (CONVERGED)
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
source "${HOME}/.agents/scripts/agentfs-contract.sh"   # KGM_EXT_KEY / KGM_EXT_NAME / KGM_TOOL_PREFIX
trace_init "goose-kgm" "1.8.3" 2>/dev/null || true

CONFIG="$HOME/.config/goose/config.yaml"
JSONL_DIR="$HOME/.agents/knowledge"
JSONL_PATH="$JSONL_DIR/.kgm-index.jsonl"
GITIGNORE="$HOME/.agents/.gitignore"
export CONFIG JSONL_PATH

# ── Preflight ──────────────────────────────────────────────────────
if [[ ! -f "$CONFIG" ]]; then
  echo "❌ Goose config not found: $CONFIG"
  exit 1
fi

# ── Classify current entry: missing | legacy | current ─────────────
STATE=$(python3 << 'PYEOF'
import os, yaml
cfg = yaml.safe_load(open(os.environ['CONFIG'])) or {}
e = (cfg.get('extensions') or {}).get(os.environ['KGM_EXT_KEY'])
want_arg = f"MEMORY_FILE_PATH={os.environ['JSONL_PATH']}"
if not e:
    print("missing")
elif e.get('cmd') == 'env' and want_arg in (e.get('args') or []) \
        and 'MEMORY_FILE_PATH' not in (e.get('envs') or {}):
    print("current")
else:
    print("legacy")
PYEOF
)

GITIGNORE_PENDING=false
if [[ ! -f "$GITIGNORE" ]] || ! grep -q '.kgm-index.jsonl' "$GITIGNORE" 2>/dev/null; then
  GITIGNORE_PENDING=true
fi

if [[ "$STATE" == "current" && "$GITIGNORE_PENDING" == false ]]; then
  echo "✅ KGM extension already configured in $CONFIG (env wrapper form)"
  if $DRY_RUN; then echo "DRY_RUN_RESULT=CONVERGED"; fi
  exit 0
fi

if $DRY_RUN; then
  case "$STATE" in
    missing) echo "[dry-run] WOULD: Add $KGM_EXT_KEY extension to $CONFIG (cmd: env MEMORY_FILE_PATH=$JSONL_PATH npx …, enabled: false)"; CHANGES=$((CHANGES + 1)) ;;
    legacy)  echo "[dry-run] WOULD: Migrate $KGM_EXT_KEY to env wrapper form and drop MEMORY_FILE_PATH from envs (enabled preserved)"; CHANGES=$((CHANGES + 1)) ;;
  esac
  if $GITIGNORE_PENDING; then
    echo "[dry-run] WOULD: Add .kgm-index.jsonl to $GITIGNORE"
    CHANGES=$((CHANGES + 1))
  fi
  echo ""
  echo "DRY_RUN_RESULT=PENDING"
  echo "Changes: ${CHANGES}"
  exit 0
fi

# ── Add or migrate extension entry ─────────────────────────────────
# yaml.dump rewrites the whole file (drops comments/formatting): back up first.
if [[ "$STATE" != "current" ]]; then
  BACKUP="${CONFIG}.bak.pre-kgm"
  [[ -e "$BACKUP" ]] && BACKUP="${BACKUP}.$(date +%Y%m%d_%H%M%S)"   # never overwrite an earlier backup
  cp -p "$CONFIG" "$BACKUP"
  echo "   Backup: $BACKUP"
  STATE="$STATE" python3 << 'PYEOF'
import os, yaml

config_path = os.environ['CONFIG']
jsonl_path = os.environ['JSONL_PATH']
key, state = os.environ['KGM_EXT_KEY'], os.environ['STATE']

with open(config_path) as f:
    config = yaml.safe_load(f) or {}
exts = config.setdefault('extensions', {})

wrapper = {
    'cmd': 'env',
    'args': [f'MEMORY_FILE_PATH={jsonl_path}', 'npx', '-y', '@modelcontextprotocol/server-memory'],
}

if state == 'missing':
    exts[key] = {
        'enabled': False,
        'type': 'stdio',
        'name': os.environ['KGM_EXT_NAME'],
        'description': 'Deterministic search index over OKF knowledge bundles via MCP',
        **wrapper,
        'env_keys': [],
        'timeout': 300,
    }
    action = 'Added'
else:
    entry = exts[key]
    entry.update(wrapper)
    envs = dict(entry.get('envs') or {})
    envs.pop('MEMORY_FILE_PATH', None)
    if envs:
        entry['envs'] = envs
    else:
        entry.pop('envs', None)
    action = 'Migrated'

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

e = exts[key]
print(f"✅ {action} {key} extension in {config_path}")
print(f"   cmd: {e['cmd']} {' '.join(e['args'])}")
print(f"   enabled: {str(e.get('enabled')).lower()}")
print("   Start a new session (or restart Goose Desktop, then toggle KGM) to pick it up.")
PYEOF
fi

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
