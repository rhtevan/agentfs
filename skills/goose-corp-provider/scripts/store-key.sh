#!/usr/bin/env bash
# store-key.sh — Store or rotate Corp API key in GNOME Keyring
#
# USER-RUN ONLY — this is the one interactive script in this skill.
# Run directly from a terminal, NOT through a goose session.
#
# Usage: bash store-key.sh [--validate] [--key KEY] [--model MODEL_ID]
#   --validate     test the key against the Corp endpoint before storing
#   --key KEY      provide key as argument (for automation; prefer stdin for humans)
#   --model ID     model to validate against. Default: goose's configured
#                  custom_corp model, else the first chat model served.
#
# Without --key, prompts interactively for the key (no echo).
set -euo pipefail

HOST="https://models.corp.redhat.com"
ENV_VAR="CUSTOM_CORP_API_KEY"
VALIDATE=true
KEY=""
MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate) VALIDATE=true; shift ;;
    --no-validate) VALIDATE=false; shift ;;
    --key) KEY="$2"; shift 2 ;;
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    *) echo "Usage: store-key.sh [--validate] [--no-validate] [--key KEY] [--model MODEL_ID]" >&2; exit 2 ;;
  esac
done

if ! command -v secret-tool &>/dev/null; then
  echo "❌ secret-tool not found. Install: sudo dnf install -y libsecret"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq not found. Install: sudo dnf install -y jq"
  exit 1
fi

# Prompt for key if not provided via --key
if [[ -z "$KEY" ]]; then
  read -rsp "Enter Corp API key: " KEY
  echo
fi

if [[ -z "$KEY" ]]; then
  echo "❌ No key provided."
  exit 1
fi

# Validate the key
if [[ "$VALIDATE" == "true" ]]; then
  # Resolve the model to validate against, in priority order:
  #   1. --model
  #   2. the model goose is actually configured to use (config.yaml)
  #   3. the first chat model the endpoint currently serves
  # A hardcoded model is wrong twice over: it can be retired by the
  # provider (turning a valid key into a false 404), and a 200 for some
  # other model does not prove the key works for the model that
  # downstream consumers depend on.
  if [[ -z "$MODEL" ]]; then
    CONFIG="$HOME/.config/goose/config.yaml"
    if [[ -f "$CONFIG" ]]; then
      MODEL=$(python3 -c "
import yaml
try:
    with open('$CONFIG') as f: c = yaml.safe_load(f) or {}
    print((c.get('providers', {}).get('custom_corp', {}) or {}).get('model', '') or '')
except Exception:
    print('')
" 2>/dev/null || echo "")
    fi
  fi

  if [[ -z "$MODEL" ]]; then
    MODEL=$(curl -s --connect-timeout 10 --max-time 25 "${HOST}/oai/v1/models" \
      -H "Authorization: Bearer ${KEY}" 2>/dev/null \
      | jq -r '.data[]?.id | select(test("embed|rerank|guardian|parse|diffusion|whisper"; "i") | not)' \
      | head -1 || echo "")
  fi

  if [[ -z "$MODEL" ]]; then
    echo "❌ Cannot determine a model to validate against."
    echo "   Pass --model MODEL_ID, or check connectivity to ${HOST}."
    exit 1
  fi

  echo "Validating key against Corp endpoint (model: ${MODEL})..."

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 \
    "${HOST}/oai/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}" \
    2>/dev/null || echo "000")

  case "$HTTP_CODE" in
    2??)
      echo "✅ Key validated successfully."
      ;;
    401)
      echo "❌ Key validation failed (HTTP 401 — invalid or expired key)."
      echo "   Key NOT saved."
      exit 1
      ;;
    403)
      echo "❌ Key validation failed (HTTP 403 — insufficient permissions)."
      echo "   Key NOT saved."
      exit 1
      ;;
    000)
      echo "⚠️  Cannot reach Corp endpoint (connection failed)."
      echo "   Check VPN. Key NOT saved."
      exit 1
      ;;
    *)
      echo "⚠️  Unexpected response (HTTP $HTTP_CODE). Key NOT saved."
      exit 1
      ;;
  esac
fi

# Read current keyring, merge, write back
CURRENT=$(secret-tool lookup application rust-keyring service goose target default username secrets 2>/dev/null || echo '{}')
MERGED=$(echo "$CURRENT" | jq --arg k "$KEY" ". + {\"$ENV_VAR\": \$k}")
echo -n "$MERGED" | secret-tool store \
  --label "secrets@goose:default (keyring v3.6.3)" \
  application rust-keyring service goose target default username secrets

echo "✅ $ENV_VAR stored in GNOME Keyring."
