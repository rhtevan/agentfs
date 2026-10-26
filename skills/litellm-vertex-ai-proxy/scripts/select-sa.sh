#!/usr/bin/env bash
# select-sa.sh — Select the best GCP service account key for Vertex AI
# Usage: bash select-sa.sh [--project PROJECT] [--sa-email EMAIL]
# Output: Prints the path to the selected SA key file (stdout)
# Exit codes: 0 = key selected, 1 = no suitable key found
# Non-interactive — no prompts, deterministic selection
#
# Selection logic:
#   1. Scan ~/.config/gcloud/legacy_credentials/*/adc.json
#   2. Filter to type: service_account
#   3. Reject default compute SA (*-compute@developer.gserviceaccount.com)
#   4. If --sa-email specified, select that exact SA
#   5. If --project specified, prefer SAs whose email contains the project name
#   6. If one dedicated SA remains → print path, exit 0
#   7. If multiple → list all, exit 1 (caller must specify --sa-email)
#   8. If none → exit 1
set -euo pipefail

PROJECT=""
SA_EMAIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT="$2"; shift 2 ;;
    --sa-email) SA_EMAIL="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash select-sa.sh [--project PROJECT] [--sa-email EMAIL]" >&2
      echo "  --project PROJECT  Prefer SAs associated with this GCP project" >&2
      echo "  --sa-email EMAIL   Select a specific SA by email" >&2
      echo "" >&2
      echo "Prints the selected key file path to stdout." >&2
      echo "Exit 1 if no suitable key found or ambiguous." >&2
      exit 0
      ;;
    *) echo "❌ Unknown option: $1" >&2; exit 2 ;;
  esac
done

CRED_DIR="$HOME/.config/gcloud/legacy_credentials"
if [[ ! -d "$CRED_DIR" ]]; then
  echo "❌ No credentials directory: $CRED_DIR" >&2
  exit 1
fi

# Collect all SA key files
declare -a CANDIDATES=()
declare -a CANDIDATE_EMAILS=()
declare -a REJECTED=()

for keyfile in $(find "$CRED_DIR" -name "adc.json" 2>/dev/null | sort); do
  # Parse key metadata
  eval "$(python3 -c "
import json, sys
try:
    with open('$keyfile') as f:
        d = json.load(f)
    t = d.get('type', '')
    e = d.get('client_email', '')
    print(f'KEY_TYPE=\"{t}\"')
    print(f'KEY_EMAIL=\"{e}\"')
except:
    print('KEY_TYPE=\"\"')
    print('KEY_EMAIL=\"\"')
" 2>/dev/null)" || continue

  # Skip non-service-account types (authorized_user, etc.)
  [[ "$KEY_TYPE" != "service_account" ]] && continue

  # Reject default compute SA
  if [[ "$KEY_EMAIL" == *-compute@developer.gserviceaccount.com ]]; then
    REJECTED+=("$KEY_EMAIL")
    continue
  fi

  # If --sa-email specified, match exactly
  if [[ -n "$SA_EMAIL" ]]; then
    if [[ "$KEY_EMAIL" == "$SA_EMAIL" ]]; then
      echo "$keyfile"
      exit 0
    fi
    continue
  fi

  CANDIDATES+=("$keyfile")
  CANDIDATE_EMAILS+=("$KEY_EMAIL")
done

# --sa-email was specified but not found
if [[ -n "$SA_EMAIL" ]]; then
  echo "❌ No key file found for SA: $SA_EMAIL" >&2
  exit 1
fi

# No candidates at all
if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  echo "❌ No dedicated service account keys found." >&2
  if [[ ${#REJECTED[@]} -gt 0 ]]; then
    echo "   Rejected (default compute SA — over-privileged):" >&2
    for r in "${REJECTED[@]}"; do
      echo "     - $r" >&2
    done
    echo "   Create a dedicated SA with roles/aiplatform.user instead." >&2
  fi
  exit 1
fi

# If --project specified, narrow to SAs whose email contains the project name
if [[ -n "$PROJECT" && ${#CANDIDATES[@]} -gt 1 ]]; then
  declare -a FILTERED=()
  declare -a FILTERED_EMAILS=()
  for i in "${!CANDIDATES[@]}"; do
    if [[ "${CANDIDATE_EMAILS[$i]}" == *"$PROJECT"* ]]; then
      FILTERED+=("${CANDIDATES[$i]}")
      FILTERED_EMAILS+=("${CANDIDATE_EMAILS[$i]}")
    fi
  done
  if [[ ${#FILTERED[@]} -gt 0 ]]; then
    CANDIDATES=("${FILTERED[@]}")
    CANDIDATE_EMAILS=("${FILTERED_EMAILS[@]}")
  fi
fi

# Exactly one candidate — select it
if [[ ${#CANDIDATES[@]} -eq 1 ]]; then
  echo "${CANDIDATES[0]}"
  exit 0
fi

# Multiple candidates — ambiguous, caller must specify
echo "❌ Multiple dedicated service accounts found. Specify --sa-email:" >&2
for i in "${!CANDIDATES[@]}"; do
  echo "   ${CANDIDATE_EMAILS[$i]}" >&2
  echo "     ${CANDIDATES[$i]}" >&2
done
exit 1
