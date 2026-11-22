#!/usr/bin/env bash
# check-key.sh — Verify Corp API key exists in GNOME Keyring
# Usage: bash check-key.sh
# Checks presence and length only. Never outputs the key value.
# Lock-aware (1.2.1): a locked keyring is reported as locked (exit 3), not as
# "not found", and the script never triggers the GNOME unlock prompt.
# Exit codes: 0 present · 1 missing / tool missing · 3 keyring locked · 4 item unreadable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-keyring.sh"
source ~/.agents/scripts/trace-lib.sh 2>/dev/null || true
trace_init "goose-corp-provider" "check-key" 2>/dev/null || true

ENV_VAR="CUSTOM_CORP_API_KEY"

trace_step "keyring-check" "Checking GNOME Keyring for $ENV_VAR" 2>/dev/null || true

for t in secret-tool gdbus jq; do
  if ! command -v "$t" &>/dev/null; then
    echo "❌ $t not found. GNOME Keyring tools are required."
    echo "   Install: sudo dnf install -y libsecret glib2 jq"
    trace_end 1 2>/dev/null || true
    exit 1
  fi
done

rc=0; KEY=$(keyring_get "$ENV_VAR") || rc=$?
if [[ $rc -ne 0 ]]; then
  keyring_explain "$rc" "$ENV_VAR"
  [[ $rc -eq 1 ]] && echo "   Run: goose configure → Configure Providers → Corp (or store-key.sh in your own terminal)"
  trace_end "$rc" 2>/dev/null || true
  exit "$rc"
fi

echo "✅ $ENV_VAR present in GNOME Keyring (${#KEY} chars)"
unset KEY

trace_end 0 2>/dev/null || true
