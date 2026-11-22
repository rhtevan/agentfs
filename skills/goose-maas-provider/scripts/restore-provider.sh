#!/usr/bin/env bash
# restore-provider.sh — Create/refresh the MaaS custom provider for Goose
#
# Writes custom_providers/custom_maas.json and adds a providers.custom_maas
# entry to config.yaml. Does NOT store the API key (store-key.sh or
# 'goose configure' → MaaS) and never sets GOOSE_TOOLSHIM.
#
# Usage: restore-provider.sh [--url URL] [--model MODEL] [--dry-run] [--force] [--activate] [--skip-tool-check]
#
# Flags:
#   --url URL     MaaS endpoint (default: base_url of an existing custom_maas.json,
#                 else https://maas-rhdp.apps.maas.redhatworkshops.io)
#   --model MODEL Default model for a NEW providers.custom_maas entry (default: llama-scout-17b)
#   --dry-run     Report changes, write nothing (DRY_RUN_RESULT=CONVERGED|PENDING)
#   --force       Overwrite custom_maas.json without a .bak copy
#   --activate    Also set active_provider: custom_maas
#   --skip-tool-check  Do not run test-model-compat.sh --all on the live list
# Env: GOOSE_CONFIG_DIR (default ~/.config/goose)
#
# Model list: live <url>/v1/models when CUSTOM_MAAS_API_KEY is in the keyring;
# otherwise the existing JSON's list is kept, or a static list on first setup.
# Live list: models that test NO_TOOLS (never emit tool_calls) are dropped;
# FLAKY/ERROR results are kept (fail open). context_limit per model comes from
# <url>/v1/model/info (max_input_tokens, else max_tokens; default 128000).
# config.yaml: line-level insert after a timestamped backup; a YAML post-check
# restores the backup on any other change. An existing entry is never modified.
#
# Exit codes: 0 success/converged · 1 failure · 2 usage error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-keyring.sh"
source ~/.agents/scripts/trace-lib.sh 2>/dev/null || true
trace_init "goose-maas-provider" "1.6.1" 2>/dev/null || true

DEFAULT_URL="https://maas-rhdp.apps.maas.redhatworkshops.io"
MAAS_URL=""
DEFAULT_MODEL="llama-scout-17b"
DRY_RUN=false
FORCE=false
ACTIVATE=false
TOOL_CHECK=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) MAAS_URL="${2:?--url needs a value}"; shift 2 ;;
    --model) DEFAULT_MODEL="${2:?--model needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --activate) ACTIVATE=true; shift ;;
    --skip-tool-check) TOOL_CHECK=false; shift ;;
    *) echo "Usage: restore-provider.sh [--url URL] [--model MODEL] [--dry-run] [--force] [--activate] [--skip-tool-check]" >&2; exit 2 ;;
  esac
done

GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
PROVIDER_DIR="$GOOSE_CONFIG_DIR/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_maas.json"
CONFIG_FILE="$GOOSE_CONFIG_DIR/config.yaml"

if [[ -z "$MAAS_URL" ]]; then
  MAAS_URL=$(jq -r '.base_url // empty' "$PROVIDER_FILE" 2>/dev/null || true)
  MAAS_URL="${MAAS_URL:-$DEFAULT_URL}"
fi
MAAS_URL="${MAAS_URL%/}"

model_entry='{name: ., context_limit: ($ctx[.] // 128000), input_token_cost: null, output_token_cost: null, currency: null, supports_cache_control: null, reasoning: false}'
STATIC_MODELS='["llama-scout-17b","gpt-oss-120b","qwen3-14b","qwen36-35b-a3b"]'
CTX='{}'
DROPPED=()

# --- Model list source ---
trace_step "models" "Resolving model list" 2>/dev/null || true
KEY_RC=0
KEY=$(keyring_get CUSTOM_MAAS_API_KEY) || KEY_RC=$?
SOURCE=""
if [[ $KEY_RC -eq 0 ]]; then
  HDR=$(auth_header_file "$KEY"); trap 'rm -f "$HDR"' EXIT
  unset KEY
  RESP=$(curl -s --connect-timeout 10 --max-time 30 -H @"$HDR" "$MAAS_URL/v1/models" 2>/dev/null || true)
  IDS=$(jq -c '[.data[]?.id | select(test("embed|rerank|guardian|whisper|tts|diffusion"; "i") | not)] | sort' <<<"$RESP" 2>/dev/null || echo '[]')
  if [[ "$IDS" == "[]" ]]; then
    echo "❌ Key found but $MAAS_URL/v1/models returned no models (bad key, wrong URL, or VPN?)."
    echo "   Response: $(head -c 200 <<<"$RESP")"
    trace_end 1 2>/dev/null || true
    exit 1
  fi
  SOURCE="live"
  # Per-model context window from LiteLLM model info (largest entry per name)
  INFO=$(curl -s --connect-timeout 10 --max-time 30 -H @"$HDR" "$MAAS_URL/v1/model/info" 2>/dev/null || true)
  CTX=$(jq -c '[.data[]? | {n: .model_name, c: ((.model_info.max_input_tokens // .model_info.max_tokens) | numbers | floor)}]
               | group_by(.n) | map({(.[0].n): (map(.c) | max)}) | add // {}' <<<"$INFO" 2>/dev/null || echo '{}')
  [[ -n "$CTX" ]] || CTX='{}'
  # Drop models that never emit tool calls (fail open on errors)
  if $TOOL_CHECK; then
    echo "🔧 Tool-call check on $(jq 'length' <<<"$IDS") live model(s) (test-model-compat.sh --all)..."
    TC_OUT=$(bash "$SCRIPT_DIR/test-model-compat.sh" --url "$MAAS_URL" --all 2>&1 || true)
    while read -r _ m v; do
      [[ "$v" == NO_TOOLS ]] && DROPPED+=("$m")
      echo "   $m: $v"
    done < <(grep '^RESULT ' <<<"$TC_OUT")
    grep -q '^RESULT ' <<<"$TC_OUT" || echo "   ⚠️  tool check produced no results — keeping all models"
    if [[ ${#DROPPED[@]} -gt 0 ]]; then
      IDS=$(jq -c --args '. - $ARGS.positional' "${DROPPED[@]}" <<<"$IDS")
      echo "   ❌ Excluded (no tool calls): ${DROPPED[*]}"
      if [[ "$IDS" == "[]" ]]; then
        echo "❌ No live model supports tool calls — nothing to configure."
        trace_end 1 2>/dev/null || true
        exit 1
      fi
    fi
  fi
elif [[ -f "$PROVIDER_FILE" ]] && jq -e '.models | length > 0' "$PROVIDER_FILE" >/dev/null 2>&1; then
  IDS=$(jq -c '[.models[].name] | sort' "$PROVIDER_FILE")
  CTX=$(jq -c '[.models[] | select(.context_limit | numbers) | {(.name): .context_limit}] | add // {}' "$PROVIDER_FILE")
  SOURCE="existing"
else
  IDS=$(jq -c 'sort' <<<"$STATIC_MODELS")
  SOURCE="static"
fi
case $KEY_RC in
  0) ;;
  1) echo "ℹ️  CUSTOM_MAAS_API_KEY not in keyring — using the $SOURCE model list (re-run after storing the key for the live list)." ;;
  *) echo "ℹ️  $(keyring_explain "$KEY_RC" CUSTOM_MAAS_API_KEY) Using the $SOURCE model list." ;;
esac
MODEL_COUNT=$(jq 'length' <<<"$IDS")

TARGET_JSON=$(jq -n --arg url "$MAAS_URL" --argjson ids "$IDS" --argjson ctx "$CTX" "{
  name: \"custom_maas\",
  engine: \"openai\",
  display_name: \"MaaS\",
  description: \"Custom MaaS provider\",
  api_key_env: \"CUSTOM_MAAS_API_KEY\",
  base_url: \$url,
  models: (\$ids | map($model_entry)),
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
  preserves_thinking: false
}")

# --- Compare with current state ---
trace_step "plan" "Comparing with current state" 2>/dev/null || true
JSON_SAME=false
if [[ -f "$PROVIDER_FILE" ]] && [[ "$(jq -S '.models |= sort_by(.name)' "$PROVIDER_FILE" 2>/dev/null)" == "$(jq -S '.models |= sort_by(.name)' <<<"$TARGET_JSON")" ]]; then
  JSON_SAME=true
fi

CUR_MODEL="__NONE__"
CUR_ACTIVE=""
if [[ -f "$CONFIG_FILE" ]]; then
  read -r CUR_MODEL CUR_ACTIVE < <(CFG="$CONFIG_FILE" python3 -c '
import os, yaml
c = yaml.safe_load(open(os.environ["CFG"])) or {}
p = (c.get("providers") or {}).get("custom_maas")
print("__NONE__" if p is None else (p.get("model") or "__UNSET__"), c.get("active_provider") or "")')
fi

CHANGES=()
$JSON_SAME || CHANGES+=("$( [[ -f "$PROVIDER_FILE" ]] && echo update || echo create ) $PROVIDER_FILE ($MODEL_COUNT models, $SOURCE list, base_url $MAAS_URL)")
ENTRY_PENDING=false
if [[ "$CUR_MODEL" == "__NONE__" ]]; then
  if ! jq -e --arg m "$DEFAULT_MODEL" 'index($m) != null' <<<"$IDS" >/dev/null; then
    echo "❌ Default model '$DEFAULT_MODEL' is not in the $SOURCE model list. Pass --model with one of:"
    jq -r '.[]' <<<"$IDS" | sed 's/^/     /'
    trace_end 1 2>/dev/null || true
    exit 1
  fi
  CHANGES+=("add providers.custom_maas (enabled, model $DEFAULT_MODEL) to $CONFIG_FILE")
  ENTRY_PENDING=true
else
  if ! jq -e --arg m "$CUR_MODEL" 'index($m) != null' <<<"$IDS" >/dev/null; then
    echo "⚠️  providers.custom_maas.model '$CUR_MODEL' is not in the $SOURCE model list — not modified; pick another in goose configure or the Desktop model picker."
  fi
fi
ACTIVATE_PENDING=false
if $ACTIVATE && [[ "$CUR_ACTIVE" != "custom_maas" ]]; then
  CHANGES+=("active_provider: ${CUR_ACTIVE:-<unset>} → custom_maas")
  ACTIVATE_PENDING=true
fi

if [[ ${#CHANGES[@]} -eq 0 ]]; then
  echo "✅ MaaS provider already configured (custom_maas.json current, providers.custom_maas present). No changes needed."
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
  trace_step "write-json" "Writing custom_maas.json" 2>/dev/null || true
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
  echo "✅ Wrote $PROVIDER_FILE ($MODEL_COUNT models, $SOURCE list)"
fi

if $ENTRY_PENDING || $ACTIVATE_PENDING; then
  trace_step "config-yaml" "Editing config.yaml" 2>/dev/null || true
  touch "$CONFIG_FILE"
  cp -p "$CONFIG_FILE" "$CONFIG_FILE.bak.$STAMP"
  echo "📋 Backup: $CONFIG_FILE.bak.$STAMP"
  CFG="$CONFIG_FILE" DM="$DEFAULT_MODEL" ADD="$ENTRY_PENDING" ACT="$ACTIVATE_PENDING" python3 - << 'PYEOF' || { cp -p "$CONFIG_FILE.bak.$STAMP" "$CONFIG_FILE"; echo "❌ config.yaml edit failed — backup restored" >&2; trace_end 1 2>/dev/null || true; exit 1; }
import os, re, shutil, sys, yaml
path, dm = os.environ["CFG"], os.environ["DM"]
add, act = os.environ["ADD"] == "true", os.environ["ACT"] == "true"
text = open(path).read()
before = yaml.safe_load(text) or {}
lines = text.splitlines(keepends=True)
if lines and not lines[-1].endswith("\n"):
    lines[-1] += "\n"
if add:
    ENTRY = ["  custom_maas:\n", "    enabled: true\n", "    model: %s\n" % dm, "    configured: true\n"]
    pi = next((i for i, l in enumerate(lines) if l.rstrip("\n") == "providers:"), None)
    if pi is None:
        lines += ["providers:\n"] + ENTRY
    else:
        end = next((i for i in range(pi + 1, len(lines)) if lines[i].strip() and not lines[i].startswith(" ")), len(lines))
        lines[end:end] = ENTRY
    before.setdefault("providers", {})["custom_maas"] = {"enabled": True, "model": dm, "configured": True}
if act:
    ai = next((i for i, l in enumerate(lines) if re.match(r"^active_provider:", l)), None)
    if ai is None:
        lines.append("active_provider: custom_maas\n")
    else:
        lines[ai] = "active_provider: custom_maas\n"
    before["active_provider"] = "custom_maas"
new_text = "".join(lines)
if yaml.safe_load(new_text) != before:
    print("❌ post-check: unexpected change", file=sys.stderr); sys.exit(1)
tmp = path + ".tmp"; open(tmp, "w").write(new_text); shutil.copymode(path, tmp); os.replace(tmp, path)
PYEOF
  if $ENTRY_PENDING; then echo "✅ Added providers.custom_maas to config.yaml (default model: $DEFAULT_MODEL)"; fi
  if $ACTIVATE_PENDING; then echo "✅ active_provider set to custom_maas"; fi
fi

echo ""
echo "✅ MaaS provider restored."
if [[ $KEY_RC -ne 0 ]]; then
  echo "   Next: store the key — bash $SCRIPT_DIR/store-key.sh --validate (your own terminal) or goose configure → MaaS;"
  echo "         then re-run this script for the live model list, and restart Goose Desktop if it is open."
fi

trace_end 0 2>/dev/null || true
