#!/usr/bin/env bash
# check-key.sh — Verify Corp API key exists in GNOME Keyring
# Usage: bash check-key.sh
# Checks presence and length only. Never outputs the key value.
set -euo pipefail

source ~/.agents/scripts/trace-lib.sh 2>/dev/null || true
trace_init "goose-corp-provider" "check-key" 2>/dev/null || true

ENV_VAR="CUSTOM_CORP_API_KEY"

trace_step "keyring-check" "Checking GNOME Keyring for $ENV_VAR" 2>/dev/null || true

if ! command -v secret-tool &>/dev/null; then
  echo "❌ secret-tool not found. GNOME Keyring is required."
  echo "   Install: sudo dnf install -y libsecret"
  trace_end 1 2>/dev/null || true
  exit 1
fi

KEYRING_DATA=$(secret-tool lookup service goose 2>/dev/null || echo '{}')

KEY=$(echo "$KEYRING_DATA" | jq -r ".${ENV_VAR} // empty" 2>/dev/null)

if [[ -z "$KEY" ]]; then
  echo "❌ $ENV_VAR not found in GNOME Keyring."
  echo "   Run: goose configure → Configure Providers → Corp"
  trace_end 1 2>/dev/null || true
  exit 1
fi

KEY_LEN=${#KEY}
echo "✅ $ENV_VAR present in GNOME Keyring (${KEY_LEN} chars)"

trace_end 0 2>/dev/null || true
