#!/usr/bin/env bash
# setup.sh — Configure Goose custom provider for Skupper VAN model
# Usage: bash setup.sh [HOST_OR_PROFILE]
#   Accepts: host name (rhel-ai, rhtevan-work) or profile name (g8b-fp8-spec-128k)
#   Default: rhel-ai (port 9000)
#
# ⚠️  POISON-JSON SAFEGUARD: Goose Desktop loads ALL JSON files in
#     ~/.config/goose/custom_providers/. One malformed file breaks
#     ALL providers. This script:
#       1. Writes JSON via Python json.dumps (not bash heredoc)
#       2. Round-trip validates before committing to disk
#       3. Restores backup on any validation failure
#     NEVER write this JSON manually or via heredoc interpolation.

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_JSON="$PROVIDER_DIR/custom_skupper.json"
CONFIG_YAML="$HOME/.config/goose/config.yaml"

TARGET="${1:-rhel-ai}"

# ── Host-based routing ─────────────────────────────────────────
# Skupper routes by host:port. Resolve target to host + port.
declare -A HOST_TO_PORT=(
  [rhel-ai]=9000
  [rhtevan-work]=10000
)

declare -A PROFILE_TO_HOST=(
  [g350m-2k]=rhtevan-work
  [g3b-16k]=rhtevan-work
  [g8b-spec-128k]=rhel-ai
  [g8b-fp8-spec-128k]=rhel-ai
)

# Resolve target to host
if [[ -n "${HOST_TO_PORT[$TARGET]:-}" ]]; then
  HOST="$TARGET"
elif [[ -n "${PROFILE_TO_HOST[$TARGET]:-}" ]]; then
  HOST="${PROFILE_TO_HOST[$TARGET]}"
else
  echo "❌ Unknown target: $TARGET" >&2
  echo "Available hosts: ${!HOST_TO_PORT[*]}" >&2
  echo "Available profiles: ${!PROFILE_TO_HOST[*]}" >&2
  exit 1
fi

PORT="${HOST_TO_PORT[$HOST]}"

echo "=== Goose Skupper Provider — Setup ==="
echo "  Target:     $TARGET"
echo "  Host:       $HOST"
echo "  Port:       $PORT"
echo

# ── Step 1: Discover model from live API ──────────────────────
echo "Step 1: Discover model from API"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PORT}/v1/models" 2>/dev/null) || true
HTTP_CODE=${HTTP_CODE:-000}

if [[ "$HTTP_CODE" == "200" ]]; then
  # Discover model ID and context from live API
  DISCOVERY=$(python3 << PYEOF
import json, urllib.request

try:
    with urllib.request.urlopen("http://localhost:${PORT}/v1/models") as resp:
        data = json.load(resp)
    model = data["data"][0]
    model_id = model["id"]
    # vLLM returns max_model_len; llama.cpp returns meta.n_ctx
    ctx = model.get("max_model_len")
    if ctx is None:
        meta = model.get("meta", {})
        ctx = meta.get("n_ctx") or meta.get("n_ctx_train") or 4096
    print(json.dumps({"model_id": model_id, "context": int(ctx)}))
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    sys.exit(1)
PYEOF
  ) || true

  if [[ -n "$DISCOVERY" ]]; then
    MODEL_ID=$(echo "$DISCOVERY" | python3 -c "import json,sys; print(json.load(sys.stdin)['model_id'])" 2>/dev/null || echo "")
    CTX=$(echo "$DISCOVERY" | python3 -c "import json,sys; print(json.load(sys.stdin)['context'])" 2>/dev/null || echo "")
  fi

  if [[ -n "${MODEL_ID:-}" && -n "${CTX:-}" ]]; then
    echo "  ✅ Discovered: $MODEL_ID (context: $CTX)"
  else
    echo "  ⚠️  API responded but could not parse model info"
    echo "  Provider will be configured with placeholder values."
    MODEL_ID="unknown-model"
    CTX=4096
  fi
else
  echo "  ⚠️  localhost:$PORT not responding (HTTP $HTTP_CODE)"
  echo "  Provider will be configured with placeholder values."
  echo "  Start the model via hosted-model-ctl, then re-run setup."
  MODEL_ID="unknown-model"
  CTX=4096
fi
echo

# ── Step 2: Backup existing JSON ──────────────────────────────
echo "Step 2: Backup existing config"
BACKUP=""
if [[ -f "$PROVIDER_JSON" ]]; then
  BACKUP="${PROVIDER_JSON}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$PROVIDER_JSON" "$BACKUP"
  echo "  ✅ Backed up to $(basename "$BACKUP")"
else
  echo "  (no existing file to backup)"
fi

if [[ -f "$CONFIG_YAML" ]]; then
  CONFIG_BACKUP="${CONFIG_YAML}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_YAML" "$CONFIG_BACKUP"
  echo "  ✅ Backed up config.yaml"
fi
echo

# ── Step 3: Write custom provider JSON via Python ─────────────
# ⚠️  Uses Python json.dumps for guaranteed valid JSON.
#     NEVER use bash heredoc with variable interpolation for this file.
#     A single malformed JSON in custom_providers/ breaks ALL providers
#     in Goose Desktop.
echo "Step 3: Write custom provider JSON"
mkdir -p "$PROVIDER_DIR"

# Pass values via environment to avoid heredoc injection risks
export _GSP_MODEL_ID="${MODEL_ID}"
export _GSP_PORT="${PORT}"
export _GSP_CTX="${CTX}"
export _GSP_OUTPUT="${PROVIDER_JSON}"

WRITE_RESULT=$(python3 << 'PYEOF'
import json, sys, os

model_id = os.environ["_GSP_MODEL_ID"]
port = int(os.environ["_GSP_PORT"])
ctx = int(os.environ["_GSP_CTX"])
output_path = os.environ["_GSP_OUTPUT"]

provider = {
    "name": "custom_skupper",
    "engine": "openai",
    "display_name": "Skupper",
    "description": "Skupper VAN to remote GPU model (IBM Granite)",
    "api_key_env": "",
    "base_url": f"http://localhost:{port}",
    "models": [
        {
            "name": model_id,
            "context_limit": ctx,
            "input_token_cost": None,
            "output_token_cost": None,
            "currency": None,
            "supports_cache_control": None,
            "reasoning": False
        }
    ],
    "headers": None,
    "timeout_seconds": 300,
    "supports_streaming": False,
    "requires_auth": False,
    "catalog_provider_id": None,
    "base_path": None,
    "env_vars": None,
    "dynamic_models": None,
    "skip_canonical_filtering": False,
    "model_doc_link": None,
    "setup_steps": [],
    "fast_model": None,
    "preserves_thinking": False
}

# Serialize
output = json.dumps(provider, indent=2)

# Round-trip validation — catches any structural issues
try:
    parsed = json.loads(output)
    required = ['name', 'engine', 'display_name', 'base_url', 'models',
                'requires_auth', 'timeout_seconds', 'supports_streaming',
                'api_key_env', 'headers', 'catalog_provider_id', 'base_path',
                'env_vars', 'dynamic_models', 'skip_canonical_filtering',
                'model_doc_link', 'setup_steps', 'fast_model', 'preserves_thinking',
                'description']
    missing = [f for f in required if f not in parsed]
    if missing:
        print(f"VALIDATION_FAILED:missing_fields:{','.join(missing)}", file=sys.stderr)
        sys.exit(1)
    if parsed['name'] != 'custom_skupper':
        print(f"VALIDATION_FAILED:wrong_name:{parsed['name']}", file=sys.stderr)
        sys.exit(1)
    if parsed['engine'] != 'openai':
        print(f"VALIDATION_FAILED:wrong_engine:{parsed['engine']}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(parsed['models'], list) or len(parsed['models']) == 0:
        print("VALIDATION_FAILED:models_empty", file=sys.stderr)
        sys.exit(1)
    if not isinstance(parsed['models'][0]['context_limit'], int):
        print(f"VALIDATION_FAILED:context_not_int:{type(parsed['models'][0]['context_limit'])}", file=sys.stderr)
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f"VALIDATION_FAILED:json_parse:{e}", file=sys.stderr)
    sys.exit(1)

# All checks passed — write atomically
with open(output_path, 'w') as f:
    f.write(output + '\n')

print("OK")
PYEOF
) || true

if [[ "$WRITE_RESULT" == "OK" ]]; then
  echo "  ✅ Written $PROVIDER_JSON (validated)"
else
  echo "  ❌ FATAL: JSON validation failed — restoring backup"
  if [[ -n "$BACKUP" && -f "$BACKUP" ]]; then
    cp "$BACKUP" "$PROVIDER_JSON"
    echo "  ✅ Restored from backup"
  else
    rm -f "$PROVIDER_JSON"
    echo "  ✅ Removed invalid file (no backup to restore)"
  fi
  exit 1
fi
echo

# ── Step 4: Post-write independent validation ─────────────────
# Read back from disk and validate independently (defense-in-depth)
echo "Step 4: Post-write validation"
POST_VALID=$(python3 -c "
import json, sys
try:
    with open('$PROVIDER_JSON') as f:
        d = json.load(f)
    assert d['name'] == 'custom_skupper', f'wrong name: {d[\"name\"]}'
    assert d['engine'] == 'openai', f'wrong engine: {d[\"engine\"]}'
    assert isinstance(d['models'], list) and len(d['models']) > 0, 'empty models'
    assert isinstance(d['models'][0]['context_limit'], int), 'context not int'
    assert d['requires_auth'] == False, 'requires_auth not false'
    assert d['supports_streaming'] == False, 'streaming not false'
    print('VALID')
except Exception as e:
    print(f'INVALID:{e}', file=sys.stderr)
    sys.exit(1)
" 2>&1) || true

if [[ "$POST_VALID" == "VALID" ]]; then
  echo "  ✅ Post-write validation passed"
else
  echo "  ❌ FATAL: Post-write validation failed: $POST_VALID"
  echo "  Restoring backup to prevent provider poisoning."
  if [[ -n "$BACKUP" && -f "$BACKUP" ]]; then
    cp "$BACKUP" "$PROVIDER_JSON"
    echo "  ✅ Restored from backup"
  else
    rm -f "$PROVIDER_JSON"
    echo "  ✅ Removed invalid file"
  fi
  exit 1
fi
echo

# ── Step 5: Update config.yaml ────────────────────────────────
echo "Step 5: Update config.yaml"
if grep -q 'custom_skupper:' "$CONFIG_YAML" 2>/dev/null; then
  # Update existing entry — escape slashes in model ID for sed
  ESCAPED_MODEL="${MODEL_ID//\//\\/}"
  sed -i "/custom_skupper:/,/configured:/{s/model: .*/model: ${ESCAPED_MODEL}/}" "$CONFIG_YAML"
  echo "  ✅ Updated model in config.yaml"
else
  # Add new entry under providers:
  ESCAPED_MODEL="${MODEL_ID//\//\\/}"
  sed -i "/^providers:/a\\  custom_skupper:\n    enabled: true\n    model: ${ESCAPED_MODEL}\n    configured: true" "$CONFIG_YAML"
  echo "  ✅ Added custom_skupper to config.yaml"
fi
echo

# ── Step 6: Verify ────────────────────────────────────────────
echo "Step 6: Verify"
echo "  JSON:"
python3 -c "
import json
with open('$PROVIDER_JSON') as f:
    d = json.load(f)
print(f'    base_url: {d[\"base_url\"]}')
print(f'    model:    {d[\"models\"][0][\"name\"]}')
print(f'    context:  {d[\"models\"][0][\"context_limit\"]}')
"

echo "  config.yaml:"
grep -A3 'custom_skupper:' "$CONFIG_YAML" | sed 's/^/    /'
echo

# ── Step 7: Test ──────────────────────────────────────────────
echo "Step 7: Test"
if [[ "$HTTP_CODE" == "200" ]]; then
  RESPONSE=$(curl -s "http://localhost:${PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"${MODEL_ID}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello\"}], \"max_tokens\": 20}" 2>/dev/null)
  CHAT=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$CHAT" != "PARSE_ERROR" ]]; then
    echo "  ✅ Chat test: $CHAT"
  else
    echo "  ⚠️  Chat test failed (model may still be loading)"
  fi
else
  echo "  ⚠️  Skipped (endpoint not responding)"
fi
echo

echo "✅ Goose Skupper Provider configured: $HOST → localhost:$PORT ($MODEL_ID)"
