#!/usr/bin/env bash
# set-default.sh — Set the default deployment profile for a host
# Usage:
#   bash set-default.sh PROFILE    — set PROFILE as default for its host
#   bash set-default.sh --show     — show current defaults for all hosts
#
# Changes are persisted by editing DEFAULT_PROFILES in common.sh.

source "$(dirname "$0")/common.sh"

COMMON_SH="$(dirname "$0")/common.sh"

if [[ "${1:-}" == "--show" || -z "${1:-}" ]]; then
  echo "=== Default Deployment Profiles ==="
  for host in "${ALL_HOSTS[@]}"; do
    current=$(get_default_profile "$host")
    echo "  ${host}: ${current:-<none>}"
  done
  exit 0
fi

PROFILE="$1"
parse_profile "$PROFILE" 2>/dev/null || {
  echo "❌ Unknown profile: $PROFILE" >&2
  echo "Available: ${ALL_PROFILES[*]}" >&2
  exit 1
}
HOST="$PROFILE_HOST"
CURRENT=$(get_default_profile "$HOST")

if [[ "$CURRENT" == "$PROFILE" ]]; then
  echo "✅ Default for $HOST is already '$PROFILE' — no change"
  exit 0
fi

# Edit DEFAULT_PROFILES in common.sh: replace the line for this host
if grep -q "\\[$HOST\\]=" "$COMMON_SH"; then
  sed -i "s|\\[$HOST\\]=.*|[$HOST]=\"$PROFILE\"|" "$COMMON_SH"
else
  # Host not in map yet — add it before the closing paren
  sed -i "/^declare -A DEFAULT_PROFILES=(/a\\  [$HOST]=\"$PROFILE\"" "$COMMON_SH"
fi

echo "✅ Default profile for $HOST: ${CURRENT:-<none>} → $PROFILE"
echo "   (Updated DEFAULT_PROFILES in common.sh)"
