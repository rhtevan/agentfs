#!/usr/bin/env bash
# restore.sh — Restore/update the LiteLLM Vertex AI provider in Hermes config
# Usage: bash restore.sh [--dry-run] [--default-model MODEL]
# Default model: strongest served model (litellm-proxy-status `models.sh default`)
# Exit codes: 0 = success, 1 = failure, 2 = usage error
#
# This script surgically updates only the model: and providers.litellm-vertex-ai:
# sections in ~/.hermes/config.yaml. All other settings are preserved.
set -euo pipefail

DRY_RUN=false
CHANGES=0
ERRORS=0

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "hermes-litellm-provider" "2.5.0" 2>/dev/null || true

DEFAULT_MODEL=""   # empty → strongest served model
LITELLM_URL="${LITELLM_URL:-http://127.0.0.1:4000}"
PROVIDER_NAME="litellm-vertex-ai"
HERMES_CONFIG="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"
PROXY_MODELS="$HOME/.agents/skills/litellm-proxy-status/scripts/models.sh"
RANKER="$HOME/.agents/skills/gcp-vertex-models/scripts/models.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true; shift ;;
    --default-model) DEFAULT_MODEL="${2:?--default-model needs a value}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash restore.sh [--dry-run] [--default-model MODEL]"
      echo "  --default-model MODEL  Default model for conversation (default: strongest served model)"
      echo ""
      echo "Discovers models from LiteLLM proxy at $LITELLM_URL"
      echo "Updates only model: and providers.$PROVIDER_NAME: sections in config.yaml"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

# Pre-flight: check proxy is reachable
if ! curl -sf "$LITELLM_URL/health" &>/dev/null; then
  echo "❌ LiteLLM proxy not reachable at $LITELLM_URL"
  echo "   Start it with: systemctl --user start litellm-proxy"
  exit 1
fi

# Discover models from live proxy (ranked: opus > sonnet > haiku, newest first)
MODELS=$(curl -sf "$LITELLM_URL/v1/models" | python3 -c "
import sys, json
for m in sorted(json.load(sys.stdin).get('data', []), key=lambda x: x['id']):
    print(m['id'])
" 2>/dev/null)

if [[ -z "$MODELS" ]]; then
  echo "❌ No models discovered from $LITELLM_URL/v1/models"
  exit 1
fi
if [[ -f "$RANKER" ]]; then
  RANKED=$(printf '%s\n' "$MODELS" | bash "$RANKER" rank 2>/dev/null || true)
  # rank drops unknown families; keep them at the end
  [[ -n "$RANKED" ]] && MODELS=$(printf '%s\n%s\n' "$RANKED" "$MODELS" | awk 'NF && !s[$0]++')
fi

echo "Discovered models:"
echo "$MODELS" | sed 's/^/  - /'
echo ""

# Default model: explicit --default-model, else strongest served model
if [[ -z "$DEFAULT_MODEL" ]]; then
  if [[ -f "$PROXY_MODELS" ]]; then
    DEFAULT_MODEL=$(bash "$PROXY_MODELS" default --url "$LITELLM_URL" 2>/dev/null || true)
  fi
  if [[ -z "$DEFAULT_MODEL" ]]; then
    DEFAULT_MODEL=$(echo "$MODELS" | head -1)
    echo "⚠️  litellm-proxy-status models.sh unavailable — using first ranked model"
  fi
  echo "Default model (strongest served): $DEFAULT_MODEL"
elif ! echo "$MODELS" | grep -qx "$DEFAULT_MODEL"; then
  echo "❌ Default model '$DEFAULT_MODEL' is not served by the proxy."
  echo "   Available: $(echo $MODELS | tr '\n' ' ')"
  exit 1
else
  echo "Default model (requested): $DEFAULT_MODEL"
fi
echo ""

# Build the models hash (YAML format)
MODELS_YAML=$(echo "$MODELS" | while read -r m; do echo "      $m: {}"; done)

# Key env name (Hermes convention)
KEY_ENV="HERMES_CUSTOM_$(echo "$PROVIDER_NAME" | tr '[:lower:]-' '[:upper:]_')_API_KEY"

if [[ ! -f "$HERMES_CONFIG" ]]; then
  echo "❌ $HERMES_CONFIG not found. Run 'hermes model' first to create initial config."
  exit 1
fi

# Convergence check: compare target sections with the current config
CURRENT=$(HERMES_CONFIG="$HERMES_CONFIG" PROV="$PROVIDER_NAME" python3 -c '
import os, yaml
c = yaml.safe_load(open(os.environ["HERMES_CONFIG"])) or {}
m = c.get("model") or {}
p = (c.get("providers") or {}).get(os.environ["PROV"]) or {}
print("%s|%s|%s|%s|%s" % (m.get("default"), m.get("provider"), p.get("default_model"), p.get("model"),
                          " ".join(sorted(p.get("models") or {})) if isinstance(p.get("models"), dict) else "?"))
')
TARGET="${DEFAULT_MODEL}|${PROVIDER_NAME}|${DEFAULT_MODEL}|${DEFAULT_MODEL}|$(echo "$MODELS" | sort | tr '\n' ' ' | sed 's/ $//')"
IFS='|' read -r CUR_DEF CUR_PROV _ _ CUR_MODELS <<< "$CURRENT"
echo "Current: model.default=$CUR_DEF model.provider=$CUR_PROV"
echo "Target:  model.default=$DEFAULT_MODEL model.provider=$PROVIDER_NAME"
if [[ "$CURRENT" == "$TARGET" ]]; then
  echo "DRY_RUN_RESULT=CONVERGED"
  echo "✅ Hermes already uses $DEFAULT_MODEL with the live model list. No changes needed."
  exit 0
fi
[[ "$CUR_DEF" != "$DEFAULT_MODEL" ]] && echo "  change: default model $CUR_DEF → $DEFAULT_MODEL"
[[ "$CUR_MODELS" != "$(echo "$MODELS" | sort | tr '\n' ' ' | sed 's/ $//')" ]] && echo "  change: models metadata → $(echo "$MODELS" | wc -l) live models"

if $DRY_RUN; then
  echo "[dry-run] WOULD: Update model: and providers.$PROVIDER_NAME: sections in $HERMES_CONFIG"
  echo "DRY_RUN_RESULT=PENDING"
  exit 0
fi

# Backup
# Hermes' own scheme (hermes_cli/config_backups.py): <HERMES_HOME>/backups/config/config.yaml.<reason>.<stamp>.
# Hermes sweeps config.yaml.bak.<digits> siblings into that dir anyway; it prunes only per reason,
# so reason "agentfs" copies are never deleted by Hermes.
BACKUP_DIR="$(dirname "$HERMES_CONFIG")/backups/config"
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/$(basename "$HERMES_CONFIG").agentfs.$(date +%Y%m%d-%H%M%S)"
cp -p "$HERMES_CONFIG" "$BACKUP"
echo "📋 Backup: $BACKUP"

# Line-level replacement of exactly two blocks (model: and providers.<name>:);
# every other line of config.yaml is kept byte-for-byte. Result is re-parsed
# and checked: everything outside the two blocks must be semantically unchanged.
HERMES_CONFIG="$HERMES_CONFIG" DEFAULT_MODEL="$DEFAULT_MODEL" PROV="$PROVIDER_NAME" \
LITELLM_URL="$LITELLM_URL" KEY_ENV="$KEY_ENV" MODELS="$MODELS" BACKUP="$BACKUP" python3 << 'PYEOF'
import os, sys, yaml, shutil
path, prov, dm = os.environ["HERMES_CONFIG"], os.environ["PROV"], os.environ["DEFAULT_MODEL"]
url, key_env = os.environ["LITELLM_URL"] + "/v1", os.environ["KEY_ENV"]
models = [m for m in os.environ["MODELS"].split("\n") if m]
orig_text = open(path).read()
orig = yaml.safe_load(orig_text) or {}
lines = orig_text.splitlines(keepends=True)

def dump(obj, indent):
    out = yaml.safe_dump(obj, default_flow_style=False, sort_keys=False, allow_unicode=True, width=10**9)
    return "".join(" " * indent + l + "\n" for l in out.splitlines())

def block_end(i, indent):
    j = i + 1
    while j < len(lines):
        l = lines[j]
        if l.strip() and not l.startswith("#") and (len(l) - len(l.lstrip(" "))) <= indent:
            break
        j += 1
    return j

model_blk = dump({"model": {"base_url": url, "default": dm, "provider": prov, "key_env": key_env}}, 0)
prov_blk = dump({prov: {"api": url, "name": "LiteLLM Vertex AI", "discover_models": True,
                        "default_model": dm, "base_url": url, "model": dm,
                        "models": {m: {} for m in models}, "key_env": key_env}}, 2)

# 1. model:
idx = next((i for i, l in enumerate(lines) if l.rstrip("\n") == "model:"), None)
if idx is None:
    lines = [model_blk] + lines
else:
    lines[idx:block_end(idx, 0)] = [model_blk]
# 2. providers.<prov>:
pidx = next((i for i, l in enumerate(lines) if l.rstrip("\n") == "providers:"), None)
if pidx is None:
    lines.append("providers:\n" + prov_blk)
else:
    pend = block_end(pidx, 0)
    cidx = next((i for i in range(pidx + 1, pend) if lines[i].rstrip("\n") == "  %s:" % prov), None)
    if cidx is None:
        lines.insert(pidx + 1, prov_blk)
    else:
        lines[cidx:block_end(cidx, 2)] = [prov_blk]
new_text = "".join(lines)

# Post-check: parses, targets correct, nothing else changed
new = yaml.safe_load(new_text)
ok = new["model"]["default"] == dm and new["providers"][prov]["default_model"] == dm
for k in set(orig) | set(new):
    if k not in ("model", "providers") and orig.get(k) != new.get(k):
        ok = False; print("❌ unexpected change in top-level key:", k)
for k in set(orig.get("providers") or {}) | set(new["providers"]):
    if k != prov and (orig.get("providers") or {}).get(k) != new["providers"].get(k):
        ok = False; print("❌ unexpected change in providers.%s" % k)
if not ok:
    print("❌ post-check failed — config not written (backup: %s)" % os.environ["BACKUP"])
    sys.exit(1)
tmp = path + ".tmp"
open(tmp, "w").write(new_text)
shutil.copymode(path, tmp)
os.replace(tmp, path)
print("✅ Updated model: and providers.%s: in %s" % (prov, path))
print("   default_model: %s" % dm)
print("   models: %s" % ", ".join(models))
PYEOF
