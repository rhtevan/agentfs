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
#
# Safety (1.2.1): refuses to run if the keyring is locked/unavailable; never
# treats a failed read as {} (that erased every other goose key); re-reads the
# map right before writing and verifies afterwards that every previous key
# survived. The key goes to curl via a 0600 header file and to jq via env.
# Exit codes: 0 stored · 1 validation/store failed · 2 usage · 3 keyring locked · 4 item unreadable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-keyring.sh"

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

if ! command -v gdbus &>/dev/null; then
  echo "❌ gdbus not found. Install: sudo dnf install -y glib2"
  exit 1
fi

# Check the keyring BEFORE asking for the key
if [[ "$(keyring_state)" != unlocked ]]; then
  keyring_explain 3 "$ENV_VAR"
  echo "   Key NOT saved."
  exit 3
fi
rc=0; BEFORE=$(keyring_read_map) || rc=$?
if [[ $rc -ne 0 ]]; then
  keyring_explain "$rc" "$ENV_VAR"
  echo "   Key NOT saved."
  exit "$rc"
fi
echo "Keyring: unlocked · goose item holds $(jq 'length' <<<"$BEFORE") key(s): $(jq -r 'keys | join(", ")' <<<"$BEFORE" | sed 's/^$/(none)/')"

# Prompt for key if not provided via --key
if [[ -z "$KEY" ]]; then
  read -rsp "Enter Corp API key: " KEY || true
  echo
fi
KEY="${KEY//[[:space:]]/}"

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
      2>/dev/null \
      | jq -r '.data[]?.id | select(test("embed|rerank|guardian|parse|diffusion|whisper"; "i") | not)' \
      | head -1 || echo "")
  fi

  if [[ -z "$MODEL" ]]; then
    echo "❌ Cannot determine a model to validate against."
    echo "   Pass --model MODEL_ID, or check connectivity to ${HOST}."
    exit 1
  fi

  echo "Validating key against Corp endpoint (model: ${MODEL})..."

  HDR=$(auth_header_file "$KEY"); trap 'rm -f "$HDR"' EXIT
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 \
    "${HOST}/oai/v1/chat/completions" \
    -H @"$HDR" \
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

# Re-read right before writing (never treat a failed read as {}), merge, write back
rc=0; CURRENT=$(keyring_read_map) || rc=$?
if [[ $rc -ne 0 ]]; then
  keyring_explain "$rc" "$ENV_VAR"; echo "   Key NOT saved."; exit "$rc"
fi
MERGED=$(KEYVAL="$KEY" jq -c --arg n "$ENV_VAR" '. + {($n): env.KEYVAL}' <<<"$CURRENT")
printf '%s' "$MERGED" | secret-tool store --label "$GOOSE_KR_LABEL" "${GOOSE_KR_ATTRS[@]}"

# Verify: new key present and every previous key survived
rc=0; AFTER=$(keyring_read_map) || rc=$?
if [[ $rc -ne 0 ]] \
   || ! KEYVAL="$KEY" jq -e --arg n "$ENV_VAR" '.[$n] == env.KEYVAL' <<<"$AFTER" >/dev/null \
   || ! jq -e --argjson before "$(jq -c 'keys' <<<"$CURRENT")" '(keys) as $k | all($before[]; . as $x | $k | index($x) != null)' <<<"$AFTER" >/dev/null; then
  echo "❌ Post-write check failed — inspect the 'secrets@goose:default' item in Passwords and Keys."
  exit 1
fi
unset KEY MERGED
echo "✅ $ENV_VAR stored in GNOME Keyring. Goose item now holds $(jq 'length' <<<"$AFTER") key(s): $(jq -r 'keys | join(", ")' <<<"$AFTER")"
echo "   Restart Goose Desktop if it is open (goose caches secrets per process)."
