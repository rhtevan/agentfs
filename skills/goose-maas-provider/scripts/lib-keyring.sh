#!/usr/bin/env bash
# lib-keyring.sh — safe access to goose's secrets item in GNOME Keyring (source it)
#
# Goose keeps every provider key in ONE keyring item (attributes below) whose
# secret is a JSON map {"CUSTOM_CORP_API_KEY": "...", "CUSTOM_MAAS_API_KEY": ...}.
# These helpers:
#   - check the lock state over D-Bus first, so a script never triggers the
#     GNOME unlock prompt and never mistakes "locked" for "not found";
#   - never print secret values;
#   - let store-key.sh refuse to write unless the current map was read cleanly
#     (a failed read written back as {} would erase every other goose key).
#
# Return codes used by keyring_read_map / keyring_get:
#   0 ok · 1 key not set · 3 keyring locked/unavailable · 4 item unreadable

GOOSE_KR_ATTRS=(application rust-keyring service goose target default username secrets)
GOOSE_KR_LABEL="secrets@goose:default (keyring v3.6.3)"

# keyring_state → prints unlocked | locked | unavailable (no prompt)
keyring_state() {
  local out
  out=$(gdbus call --session --dest org.freedesktop.secrets \
        --object-path /org/freedesktop/secrets/aliases/default \
        --method org.freedesktop.DBus.Properties.Get \
        org.freedesktop.Secret.Collection Locked 2>/dev/null) || { echo unavailable; return 0; }
  case "$out" in
    *false*) echo unlocked ;;
    *true*)  echo locked ;;
    *)       echo unavailable ;;
  esac
}

# keyring_item_exists → 0 exists · 1 absent · 2 query failed (reads no secret)
keyring_item_exists() {
  local out
  out=$(gdbus call --session --dest org.freedesktop.secrets \
        --object-path /org/freedesktop/secrets \
        --method org.freedesktop.Secret.Service.SearchItems \
        "{'application': 'rust-keyring', 'service': 'goose', 'target': 'default', 'username': 'secrets'}" \
        2>/dev/null) || return 2
  [[ "$out" == *objectpath* ]] && return 0
  return 1
}

# keyring_read_map → prints the JSON map ("{}" if the item does not exist yet)
keyring_read_map() {
  [[ "$(keyring_state)" == unlocked ]] || return 3
  local rc=0 data
  keyring_item_exists || rc=$?
  case $rc in
    1) printf '{}'; return 0 ;;
    2) return 3 ;;
  esac
  data=$(secret-tool lookup "${GOOSE_KR_ATTRS[@]}" 2>/dev/null) || return 4
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$data" || return 4
  printf '%s' "$data"
}

# keyring_get NAME → prints the value of one key
keyring_get() {
  local map rc=0 val
  map=$(keyring_read_map) || rc=$?
  [[ $rc -eq 0 ]] || return $rc
  val=$(jq -r --arg k "$1" '.[$k] // empty' <<<"$map")
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

# keyring_explain RC NAME → one-line human message for a non-zero return code
keyring_explain() {
  case "$1" in
    1) echo "❌ $2 not found in GNOME Keyring." ;;
    3) echo "🔒 GNOME Keyring is locked or unavailable — unlock it (Passwords and Keys → Login → Unlock, or log in again) and re-run." ;;
    4) echo "❌ The goose keyring item exists but could not be read as JSON — not touching it. Inspect it in Passwords and Keys." ;;
    *) echo "❌ Keyring error (rc=$1) for $2." ;;
  esac
}

# auth_header_file KEY → prints the path of a 0600 temp file holding the
# Authorization header, for curl -H @FILE (keeps the key off the command line).
# The caller removes it (trap).
auth_header_file() {
  local f
  f=$(mktemp "${TMPDIR:-/tmp}/kr-hdr.XXXXXX")
  chmod 600 "$f"
  printf 'Authorization: Bearer %s\n' "$1" >"$f"
  printf '%s' "$f"
}
