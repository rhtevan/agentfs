#!/usr/bin/env bash
# set-default.sh — Set the default deployment profile for a host
# Usage:
#   bash set-default.sh PROFILE    — set PROFILE as default for its host
#   bash set-default.sh --show     — show current defaults for all hosts

source "$(dirname "$0")/common.sh"

if [[ "${1:-}" == "--show" || -z "${1:-}" ]]; then
  echo "=== Default Deployment Profiles ==="
  for host in rhtevan-work rhel-ai; do
    current=$(get_default_profile "$host")
    builtin_default=""
    case "$host" in
      rhtevan-work) builtin_default="$_BUILTIN_DEFAULT_RHTEVAN" ;;
      rhel-ai)      builtin_default="$_BUILTIN_DEFAULT_RHELAI" ;;
    esac
    override=""
    [[ -f "${PROFILE_STATE_DIR}/default-profile-${host}" ]] && override=" (overridden from ${builtin_default})"
    echo "  ${host}: ${current}${override}"
  done
  exit 0
fi

PROFILE="$1"
set_default_profile "$PROFILE"
