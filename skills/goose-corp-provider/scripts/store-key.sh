#!/usr/bin/env bash
# store-key.sh — Store or rotate Corp API key in GNOME Keyring
#
# USER-RUN ONLY — this is the one interactive script in this skill.
# Run directly from a terminal, NOT through a goose session.
#
# Usage: bash store-key.sh [--validate] [--key KEY]
#   --validate  test the key against the Corp endpoint before storing
#   --key KEY   provide key as argument (for automation; prefer stdin for humans)
#
# Without --key, prompts interactively for the key (no echo).
set -euo pipefail

HOST="https://models.corp.redhat.com"
ENV_VAR="CUSTOM_CORP_API_KEY"
VALIDATE=true
KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate) VALIDATE=true; shift ;;
    --no-validate) VALIDATE=false; shift ;;
    --key) KEY="$2"; shift 2 ;;
    *) echo "Usage: store-key.sh [--validate] [--no-validate] [--key KEY]" >&2; exit 2 ;;
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
  echo "Validating key against Corp endpoint..."

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 \
    "${HOST}/oai/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"granite-3-1-8b-instruct","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' \
    2>/dev/null || echo "000")

  case "$HTTP_CODE" in
    200)
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
CURRENT=$(secret-tool lookup service goose 2>/dev/null || echo '{}')
MERGED=$(echo "$CURRENT" | jq --arg k "$KEY" ". + {\"$ENV_VAR\": \$k}")
echo -n "$MERGED" | secret-tool store \
  --label "secrets@goose:default (keyring v3.6.3)" service goose

echo "✅ $ENV_VAR stored in GNOME Keyring."
