#!/usr/bin/env bash
# store-key.sh — Store or rotate the MaaS API key in GNOME Keyring
#
# USER-RUN ONLY — run it in your own terminal, NOT through a goose session.
#
# Usage: bash store-key.sh [--validate|--no-validate] [--url URL] [--key KEY]
#   --validate     (default) test the key with GET <url>/v1/models before storing
#   --no-validate  store without testing
#   --url URL      default: base_url of custom_maas.json, else the RHDP MaaS URL
#   --key KEY      for automation only (visible in ps/history); humans: omit it
#                  and paste at the hidden prompt
#
# Goose keeps all provider keys in ONE keyring item (a JSON map). This script
# merges CUSTOM_MAAS_API_KEY into that map. Safety (1.6.0):
#   - refuses to run if the keyring is locked/unavailable (no prompt, no write);
#   - refuses to write unless the current map was read cleanly — a failed read
#     is never treated as {} (that would erase every other goose key);
#   - after writing, re-reads the map and checks every previous key survived.
# Restart Goose Desktop afterwards (each goose process caches secrets).
#
# Exit codes: 0 stored · 1 validation/store failed · 2 usage · 3 keyring locked · 4 item unreadable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-keyring.sh"

ENV_VAR="CUSTOM_MAAS_API_KEY"
GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
VALIDATE=true
MAAS_URL=""
KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --validate) VALIDATE=true; shift ;;
    --no-validate) VALIDATE=false; shift ;;
    --url) MAAS_URL="${2:?--url needs a value}"; shift 2 ;;
    --key) KEY="${2:?--key needs a value}"; shift 2 ;;
    *) echo "Usage: store-key.sh [--validate|--no-validate] [--url URL] [--key KEY]" >&2; exit 2 ;;
  esac
done

for t in secret-tool gdbus jq curl; do
  command -v "$t" &>/dev/null || { echo "❌ $t not found (sudo dnf install -y libsecret glib2 jq curl)"; exit 1; }
done

if [[ -z "$MAAS_URL" ]]; then
  MAAS_URL=$(jq -r '.base_url // empty' "$GOOSE_CONFIG_DIR/custom_providers/custom_maas.json" 2>/dev/null || true)
  MAAS_URL="${MAAS_URL:-https://maas-rhdp.apps.maas.redhatworkshops.io}"
fi
MAAS_URL="${MAAS_URL%/}"

# Check the keyring BEFORE asking for the key
STATE=$(keyring_state)
if [[ "$STATE" != unlocked ]]; then
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
jq -e --arg n "$ENV_VAR" 'has($n)' <<<"$BEFORE" >/dev/null && echo "   ($ENV_VAR exists — it will be replaced)"

if [[ -z "$KEY" ]]; then
  read -rsp "Enter MaaS API key (input hidden): " KEY || true
  echo
fi
KEY="${KEY//[[:space:]]/}"
[[ -n "$KEY" ]] || { echo "❌ No key provided."; exit 1; }
[[ "$KEY" == sk-* ]] || echo "⚠️  Key does not start with 'sk-' — continuing."

if $VALIDATE; then
  echo "Validating against $MAAS_URL/v1/models ..."
  HDR=$(auth_header_file "$KEY"); trap 'rm -f "$HDR"' EXIT
  RESP=$(curl -s --connect-timeout 10 --max-time 30 -H @"$HDR" -w $'\n%{http_code}' "$MAAS_URL/v1/models" 2>/dev/null || true)
  rm -f "$HDR"
  CODE=$(tail -1 <<<"$RESP"); BODY=$(sed '$d' <<<"$RESP")
  case "$CODE" in
    200)
      N=$(jq '.data | length' <<<"$BODY" 2>/dev/null || echo 0)
      echo "✅ Key valid — $N models available." ;;
    401|403) echo "❌ Key rejected (HTTP $CODE). Key NOT saved."; exit 1 ;;
    000|"")  echo "❌ Cannot reach $MAAS_URL (VPN/network?). Key NOT saved. Use --no-validate to store anyway."; exit 1 ;;
    *)       echo "❌ Unexpected HTTP $CODE. Key NOT saved."; exit 1 ;;
  esac
fi

# Re-read right before writing (another process may have changed the map)
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
echo "✅ $ENV_VAR stored. Goose item now holds $(jq 'length' <<<"$AFTER") key(s): $(jq -r 'keys | join(", ")' <<<"$AFTER")"
echo "   Restart Goose Desktop if it is open (goose caches secrets per process)."
