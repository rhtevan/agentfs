#!/usr/bin/env bash
# setup.sh — Install/restore Goose custom provider for Headroom proxy
# Usage: setup.sh [--dry-run] [--model MODEL]   (env LITELLM_URL, default http://127.0.0.1:4000)
# Version: 2.1.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-headroom-provider" "2.1.0" 2>/dev/null || true

DRY_RUN=false
MODEL="claude-opus-5"
LITELLM_URL="${LITELLM_URL:-http://127.0.0.1:4000}"
CHANGES=0
ERRORS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true; shift ;;
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

PROVIDER_DIR="${HOME}/.config/goose/custom_providers"
PROVIDER_FILE="${PROVIDER_DIR}/custom_headroom.json"
CONFIG_YAML="${HOME}/.config/goose/config.yaml"
ENV_FILE="${HOME}/.config/goose/.env"

echo "=== Goose Headroom Provider Setup ==="
echo ""

# ── Step 1: Check Headroom proxy (precondition) ─────────────────────────
trace_step 1 "check_headroom_proxy" 0 "" 2>/dev/null || true

if curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
  echo "✓ Headroom proxy is running on :8787"
elif systemctl --user is-active headroom-proxy >/dev/null 2>&1; then
  echo "⚠ Headroom proxy service active but health check failed"
  ERRORS=$((ERRORS + 1))
else
  echo "⚠ Headroom proxy not running (use headroom-litellm-proxy skill to set up)"
  ERRORS=$((ERRORS + 1))
fi

# ── Models: discovered from LiteLLM (Headroom's upstream) ──────────────
# Headroom forwards to LiteLLM, so the provider JSON lists exactly the
# models LiteLLM serves (/model/info: name + max_input_tokens).
discover_models() {
  LITELLM_URL="$LITELLM_URL" python3 - << 'PYEOF'
import json, os, sys, urllib.request
try:
    data = json.load(urllib.request.urlopen(os.environ["LITELLM_URL"].rstrip("/") + "/model/info", timeout=10))["data"]
except Exception:
    sys.exit(1)
out = {}
for m in data:
    out[m["model_name"]] = (m.get("model_info") or {}).get("max_input_tokens") or 200000
def key(n):
    p = n.split("-")
    fam = {"opus": 0, "sonnet": 1, "haiku": 2}.get(p[1] if len(p) > 1 else "", 9)
    try:
        ver = tuple(-int(x) for x in p[2:])
    except ValueError:
        ver = (0,)
    return (fam, ver, n)
models = [{"name": n, "context_limit": out[n], "input_token_cost": None, "output_token_cost": None,
           "currency": None, "supports_cache_control": None, "reasoning": False} for n in sorted(out, key=key)]
print(json.dumps(models, indent=4))
PYEOF
}

# ── Step 2: Create/verify custom provider JSON ──────────────────────────
trace_step 2 "provider_json" 0 "path=${PROVIDER_FILE}" 2>/dev/null || true

if [[ -f "$PROVIDER_FILE" ]]; then
  echo "✓ NO CHANGE: Provider JSON exists: $PROVIDER_FILE"
  if grep -q '"custom_headroom"' "$PROVIDER_FILE"; then
    echo "  ✓ Contains custom_headroom provider"
  else
    echo "  ⚠ File exists but may not contain custom_headroom"
    ERRORS=$((ERRORS + 1))
  fi
  if LIVE_JSON="$(discover_models)"; then
    DRIFT="$(LIVE_JSON="$LIVE_JSON" PROVIDER_FILE="$PROVIDER_FILE" python3 -c '
import json, os
live = [m["name"] for m in json.loads(os.environ["LIVE_JSON"])]
cur = [m["name"] for m in json.load(open(os.environ["PROVIDER_FILE"])).get("models", [])]
add = [n for n in live if n not in cur]; gone = [n for n in cur if n not in live]
if add or gone:
    print("missing: %s | not served: %s" % (" ".join(add) or "-", " ".join(gone) or "-"))
')"
    if [[ -n "$DRIFT" ]]; then
      echo "  ℹ️  Model list differs from LiteLLM ($DRIFT)"
      echo "     To regenerate: mv $PROVIDER_FILE ${PROVIDER_FILE}.bak && bash $(realpath "$0")"
    else
      echo "  ✓ Model list matches LiteLLM"
    fi
  fi
else
  if $DRY_RUN; then
    echo "[dry-run] WOULD CREATE: $PROVIDER_FILE"
    CHANGES=$((CHANGES + 1))
  else
    mkdir -p "$PROVIDER_DIR"
    if ! MODELS_JSON="$(discover_models)"; then
      echo "❌ LiteLLM unreachable at $LITELLM_URL — cannot build the model list" >&2
      exit 1
    fi
    cat > "$PROVIDER_FILE" << 'PROVIDER_EOF'
{
  "name": "custom_headroom",
  "engine": "openai",
  "display_name": "Headroom",
  "description": "Headroom context-optimization proxy → LiteLLM (Vertex AI Claude models)",
  "api_key_env": "",
  "base_url": "http://host.containers.internal:8787",
  "models": __MODELS__,
  "headers": null,
  "timeout_seconds": 600,
  "supports_streaming": true,
  "requires_auth": false,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": null,
  "preserves_thinking": true
}
PROVIDER_EOF
    MODELS_JSON="$MODELS_JSON" python3 - "$PROVIDER_FILE" << 'PYEOF'
import json, os, sys
p = sys.argv[1]
s = open(p).read().replace("__MODELS__", json.dumps(json.loads(os.environ["MODELS_JSON"]), indent=4).replace("\n", "\n  "))
json.loads(s)
open(p, "w").write(s)
PYEOF
    echo "✓ Created provider JSON: $PROVIDER_FILE"
  fi
fi

# ── Step 3: Check/add .env API key ───────────────────────────────────────
trace_step 3 "env_api_key" 0 "path=${ENV_FILE}" 2>/dev/null || true

if [[ -f "$ENV_FILE" ]] && grep -q 'CUSTOM_HEADROOM_API_KEY' "$ENV_FILE"; then
  echo "✓ NO CHANGE: API key entry exists in .env"
else
  if $DRY_RUN; then
    echo "[dry-run] WOULD APPEND: CUSTOM_HEADROOM_API_KEY to $ENV_FILE"
    CHANGES=$((CHANGES + 1))
  else
    echo 'CUSTOM_HEADROOM_API_KEY=sk-EXAMPLE-not-real' >> "$ENV_FILE"
    echo "✓ Added CUSTOM_HEADROOM_API_KEY to .env"
  fi
fi

# ── Step 4: Check config.yaml provider entry ─────────────────────────────
trace_step 4 "config_yaml" 0 "path=${CONFIG_YAML}" 2>/dev/null || true

if [[ -f "$CONFIG_YAML" ]]; then
  if grep -q 'custom_headroom' "$CONFIG_YAML"; then
    echo "✓ NO CHANGE: custom_headroom found in config.yaml"
    active=$(grep 'active_provider:' "$CONFIG_YAML" | awk '{print $2}' || true)
    echo "  Current active_provider: ${active:-not set}"
  else
    echo "⚠ custom_headroom not found in config.yaml"
    echo "  Add under providers: in $CONFIG_YAML →  custom_headroom: {enabled: true, model: $MODEL, configured: true}"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "⚠ config.yaml not found: $CONFIG_YAML"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
if $DRY_RUN; then
  if [[ $CHANGES -eq 0 && $ERRORS -eq 0 ]]; then
    echo "DRY_RUN_RESULT=CONVERGED"
    echo "Headroom provider is configured. No changes needed."
  elif [[ $CHANGES -gt 0 ]]; then
    echo "DRY_RUN_RESULT=PENDING"
    echo "$CHANGES change(s) would be applied. Run without --dry-run to apply."
  else
    echo "DRY_RUN_RESULT=PENDING"
    echo "$ERRORS precondition issue(s) found. Review above."
  fi
  exit 0
else
  if [[ $ERRORS -eq 0 ]]; then
    echo "APPLY_RESULT=OK"
    echo "✅ Headroom provider is configured."
  else
    echo "APPLY_RESULT=PARTIAL"
    echo "⚠ Setup completed with ${ERRORS} warning(s). Review above."
  fi
fi

trace_end 2>/dev/null || true
exit $ERRORS
