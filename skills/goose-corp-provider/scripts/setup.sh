#!/usr/bin/env bash
# setup.sh — Create Corp custom provider JSON and config.yaml entry
# Usage: bash setup.sh --model MODEL_ID [--dry-run] [--force]
#   --dry-run  Report changes, write nothing (DRY_RUN_RESULT=CONVERGED|PENDING)
#   --force    Overwrite custom_corp.json without a .bak copy
# Env: GOOSE_CONFIG_DIR (default ~/.config/goose)
# config.yaml: the providers.custom_corp entry is inserted line-level (no
# yaml.dump re-wrap), after a timestamped backup; a YAML post-check restores
# the backup if anything else changed. An existing entry is never modified.
# Exit codes: 0 = success/converged, 1 = failure, 2 = usage error
set -euo pipefail

source ~/.agents/scripts/trace-lib.sh 2>/dev/null || true
trace_init "goose-corp-provider" "1.2.0" 2>/dev/null || true

MODEL=""
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Usage: setup.sh --model MODEL_ID [--dry-run] [--force]" >&2; exit 2 ;;
  esac
done

[[ -z "$MODEL" ]] && { echo "ERROR: --model is required" >&2; exit 2; }

GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
PROVIDER_DIR="$GOOSE_CONFIG_DIR/custom_providers"
PROVIDER_FILE="${PROVIDER_DIR}/custom_corp.json"
CONFIG_FILE="$GOOSE_CONFIG_DIR/config.yaml"

trace_step "probe" "Fetching available models for provider JSON" 2>/dev/null || true

HOST="https://models.corp.redhat.com"
RESPONSE=$(curl -s --connect-timeout 10 "${HOST}/oai/v1/models" 2>/dev/null || echo '{"data":[]}')

# Filter to chat-capable models
MODELS_JSON=$(echo "$RESPONSE" | jq '[
  .data[]
  | select((.id | test("embed|rerank|guardian|parse|diffusion"; "i")) | not)
  | {
      name: .id,
      context_limit: 128000,
      input_token_cost: null,
      output_token_cost: null,
      currency: null,
      supports_cache_control: null,
      reasoning: false
    }
] | sort_by(.name)' 2>/dev/null || echo '[]')

MODEL_COUNT=$(echo "$MODELS_JSON" | jq 'length')

if [[ "$MODEL_COUNT" -eq 0 ]]; then
  echo "❌ No chat models found on Corp endpoint (VPN?)."
  trace_end 1 2>/dev/null || true
  exit 1
fi

# The endpoint lists some models under a dotted or a dashed alias at random per
# call (granite-4.1-8b / granite-4-1-8b), so names are compared with . == -
# Verify chosen default model exists
MODEL_EXISTS=$(echo "$MODELS_JSON" | jq --arg m "$MODEL" '[.[] | select((.name | gsub("\\."; "-")) == ($m | gsub("\\."; "-")))] | length')
if [[ "$MODEL_EXISTS" -eq 0 ]]; then
  echo "❌ Model '$MODEL' not found on Corp endpoint."
  echo "   Available chat models:"
  echo "$MODELS_JSON" | jq -r '.[].name' | sed 's/^/     /'
  trace_end 1 2>/dev/null || true
  exit 1
fi

TARGET_JSON=$(jq -n --argjson models "$MODELS_JSON" '{
  name: "custom_corp",
  engine: "openai",
  display_name: "Corp",
  description: "Red Hat Corp model service (models.corp.redhat.com)",
  api_key_env: "CUSTOM_CORP_API_KEY",
  base_url: "https://models.corp.redhat.com/oai/v1",
  models: $models,
  headers: null,
  timeout_seconds: 300,
  supports_streaming: true,
  requires_auth: true,
  catalog_provider_id: null,
  base_path: null,
  env_vars: null,
  dynamic_models: null,
  skip_canonical_filtering: false,
  model_doc_link: null,
  setup_steps: [],
  fast_model: null,
  preserves_thinking: true
}')

# --- Compare with current state ---
trace_step "plan" "Comparing with current state" 2>/dev/null || true
JSON_SAME=false
NORM='.models |= (map(.name |= gsub("\\."; "-")) | sort_by(.name))'
if [[ -f "$PROVIDER_FILE" ]] && [[ "$(jq -S "$NORM" "$PROVIDER_FILE" 2>/dev/null)" == "$(jq -S "$NORM" <<<"$TARGET_JSON")" ]]; then
  JSON_SAME=true
fi

CUR_MODEL="__NONE__"
if [[ -f "$CONFIG_FILE" ]]; then
  CUR_MODEL=$(CFG="$CONFIG_FILE" python3 -c '
import os, yaml
p = ((yaml.safe_load(open(os.environ["CFG"])) or {}).get("providers") or {}).get("custom_corp")
print("__NONE__" if p is None else (p.get("model") or ""))')
fi

CHANGES=()
$JSON_SAME || CHANGES+=("$( [[ -f "$PROVIDER_FILE" ]] && echo update || echo create ) $PROVIDER_FILE ($MODEL_COUNT chat models)")
ENTRY_PENDING=false
if [[ "$CUR_MODEL" == "__NONE__" ]]; then
  CHANGES+=("add providers.custom_corp (enabled, model $MODEL) to $CONFIG_FILE")
  ENTRY_PENDING=true
elif [[ "$CUR_MODEL" != "$MODEL" ]]; then
  echo "ℹ️  providers.custom_corp exists with model ${CUR_MODEL:-<unset>} — not modified (change it in goose configure or the Desktop model picker)"
fi

if [[ ${#CHANGES[@]} -eq 0 ]]; then
  echo "✅ Corp provider already configured (custom_corp.json current, providers.custom_corp present). No changes needed."
  echo "DRY_RUN_RESULT=CONVERGED"
  trace_end 0 2>/dev/null || true
  exit 0
fi
echo "Changes:"
printf '  %s\n' "${CHANGES[@]}"
if $DRY_RUN; then
  echo "DRY_RUN_RESULT=PENDING"
  trace_end 0 2>/dev/null || true
  exit 0
fi

# --- Apply ---
STAMP=$(date +%Y%m%d_%H%M%S)

if ! $JSON_SAME; then
  trace_step "write-json" "Writing custom_corp.json" 2>/dev/null || true
  mkdir -p "$PROVIDER_DIR"
  if [[ -f "$PROVIDER_FILE" && "$FORCE" != "true" ]]; then
    cp -p "$PROVIDER_FILE" "$PROVIDER_FILE.bak.$STAMP"
    echo "📋 Backup: $PROVIDER_FILE.bak.$STAMP"
  fi
  printf '%s\n' "$TARGET_JSON" > "$PROVIDER_FILE.tmp"
  if ! jq empty "$PROVIDER_FILE.tmp" 2>/dev/null; then
    rm -f "$PROVIDER_FILE.tmp"
    echo "❌ Generated JSON is invalid."
    trace_end 1 2>/dev/null || true
    exit 1
  fi
  mv "$PROVIDER_FILE.tmp" "$PROVIDER_FILE"
  echo "✅ Wrote $PROVIDER_FILE ($MODEL_COUNT chat models)"
fi

if $ENTRY_PENDING; then
  trace_step "config-yaml" "Inserting providers.custom_corp" 2>/dev/null || true
  touch "$CONFIG_FILE"
  cp -p "$CONFIG_FILE" "$CONFIG_FILE.bak.$STAMP"
  echo "📋 Backup: $CONFIG_FILE.bak.$STAMP"
  CFG="$CONFIG_FILE" DM="$MODEL" python3 - << 'PYEOF' || { cp -p "$CONFIG_FILE.bak.$STAMP" "$CONFIG_FILE"; echo "❌ config.yaml edit failed — backup restored" >&2; trace_end 1 2>/dev/null || true; exit 1; }
import os, shutil, sys, yaml
path, dm = os.environ["CFG"], os.environ["DM"]
text = open(path).read()
before = yaml.safe_load(text) or {}
lines = text.splitlines(keepends=True)
if lines and not lines[-1].endswith("\n"):
    lines[-1] += "\n"
ENTRY = ["  custom_corp:\n", "    enabled: true\n", "    model: %s\n" % dm, "    configured: true\n"]
pi = next((i for i, l in enumerate(lines) if l.rstrip("\n") == "providers:"), None)
if pi is None:
    lines += ["providers:\n"] + ENTRY
else:
    end = next((i for i in range(pi + 1, len(lines)) if lines[i].strip() and not lines[i].startswith(" ")), len(lines))
    lines[end:end] = ENTRY
new_text = "".join(lines)
after = yaml.safe_load(new_text)
before.setdefault("providers", {})["custom_corp"] = {"enabled": True, "model": dm, "configured": True}
if after != before:
    print("❌ post-check: unexpected change", file=sys.stderr); sys.exit(1)
tmp = path + ".tmp"; open(tmp, "w").write(new_text); shutil.copymode(path, tmp); os.replace(tmp, path)
PYEOF
  echo "✅ Added providers.custom_corp to config.yaml (default model: $MODEL)"
fi

echo ""
echo "✅ Corp provider setup complete."
echo "   Next: run 'goose configure' → Configure Providers → Corp to store your API key (skip if check-key.sh passes)."

trace_end 0 2>/dev/null || true
