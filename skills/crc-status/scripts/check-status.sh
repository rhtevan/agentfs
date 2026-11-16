#!/bin/bash
# check-status.sh — Deterministic CRC status gathering
#
# Gathers CRC cluster state, resource usage, and optional banner status.
# All output is pre-computed facts for model consumption.
#
# Usage:
#   check-status.sh
#
# Exit codes:
#   0 — Status gathered successfully (cluster may be stopped — that's valid data)
#   1 — crc CLI not found
#
# Output: Structured facts on stdout. Model reads this output.
#         Model does NOT run crc commands directly.

# --- Source trace-lib if available ---
TRACE_LIB="$HOME/.agents/scripts/trace-lib.sh"
if [[ -f "$TRACE_LIB" ]]; then
  source "$TRACE_LIB"
  trace_init "crc-status" "check-status"
fi

# --- Step 1: Verify prerequisites ---
if ! command -v crc &>/dev/null; then
  echo "ERROR: crc CLI not found. Install OpenShift Local first."
  [[ "$(type -t trace_end)" == "function" ]] && trace_end 1
  exit 1
fi

[[ "$(type -t trace_step)" == "function" ]] && trace_step 1 "check-crc-status"

# --- Step 2: Gather CRC status ---
CRC_OUTPUT=$(crc status 2>&1)
CRC_EXIT=$?

# Parse fields from crc status output
CRC_VM_STATE=$(echo "$CRC_OUTPUT" | grep -i 'crc vm:' | sed 's/.*: *//' | tr -d '[:space:]' || echo "unknown")
OPENSHIFT_STATE=$(echo "$CRC_OUTPUT" | grep -i 'openshift:' | head -1 | sed 's/.*: *//' || echo "unknown")
DISK_USAGE=$(echo "$CRC_OUTPUT" | grep -i 'disk usage:' | sed 's/.*: *//' || echo "unknown")
CACHE_USAGE=$(echo "$CRC_OUTPUT" | grep -i 'cache usage:' | sed 's/.*: *//' || echo "unknown")
CACHE_DIR=$(echo "$CRC_OUTPUT" | grep -i 'cache directory:' | sed 's/.*: *//' || echo "unknown")

# Determine if cluster is running
CLUSTER_RUNNING=false
if echo "$CRC_VM_STATE" | grep -qi 'running'; then
  CLUSTER_RUNNING=true
fi

[[ "$(type -t trace_step)" == "function" ]] && trace_step 2 "parse-status"

# --- Step 3: If running, gather extended info ---
CREDENTIALS=""
BANNER_EXISTS="unknown"
BANNER_NAME=""

if [[ "$CLUSTER_RUNNING" == "true" ]] && command -v oc &>/dev/null; then
  [[ "$(type -t trace_step)" == "function" ]] && trace_step 3 "gather-extended"

  # Get credentials
  CREDENTIALS=$(crc console --credentials 2>&1 || echo "ERROR: could not retrieve credentials")

  # Check banner
  BANNER_OUTPUT=$(oc get consolenotification security-notice 2>/dev/null)
  if [[ -n "$BANNER_OUTPUT" ]] && echo "$BANNER_OUTPUT" | grep -q 'security-notice'; then
    BANNER_EXISTS="yes"
    BANNER_NAME="security-notice"
  else
    BANNER_EXISTS="no"
  fi
fi

# --- Output: structured facts ---
cat <<FACTS
=== CRC Status Report ===
crc_cli_found: yes
crc_exit_code: $CRC_EXIT
crc_vm_state: $CRC_VM_STATE
openshift_state: $OPENSHIFT_STATE
disk_usage: $DISK_USAGE
cache_usage: $CACHE_USAGE
cache_directory: $CACHE_DIR
cluster_running: $CLUSTER_RUNNING
FACTS

if [[ "$CLUSTER_RUNNING" == "true" ]]; then
  cat <<EXTENDED
oc_cli_found: $(command -v oc &>/dev/null && echo "yes" || echo "no")
credentials: $CREDENTIALS
banner_exists: $BANNER_EXISTS
banner_name: $BANNER_NAME
EXTENDED

  # --- OLS credential rotation reminder ---
  # Cheap, read-only: annotations only. No in-pod exec, no network. The full
  # probe (incl. live auth) lives in crc-ols `ols credential status`.
  if oc get olsconfig cluster &>/dev/null; then
    OLS_WARN=$(oc get secret -n openshift-lightspeed -o json 2>/dev/null | python3 -c "
import json,sys
from datetime import datetime,timezone
try: items=json.load(sys.stdin).get('items',[])
except Exception: sys.exit(0)
now=datetime.now(timezone.utc)
for it in items:
    m=it.get('metadata',{}); a=m.get('annotations') or {}
    d=a.get('crc-ols/rotation-days')
    if not d: continue
    # Fall back to creationTimestamp when the secret carries a policy
    # but was never rotated through rotate-key.sh (--stamp-only sets
    # rotation-days alone, deliberately leaving rotated-at unset so the
    # real age is preserved). Requiring both annotations silently
    # skipped those secrets and disagreed with crc-ols list.sh.
    r=a.get('crc-ols/rotated-at') or m.get('creationTimestamp')
    if not r: continue
    try:
        age=(now-datetime.fromisoformat(r.replace('Z','+00:00'))).total_seconds()//86400
        left=int(d)-int(age)
    except Exception: continue
    if left < 0:   print(f\"{m['name']}: OVERDUE by {-left}d\")
    elif left <= 7: print(f\"{m['name']}: expires in {left}d\")
" 2>/dev/null)
    if [[ -n "$OLS_WARN" ]]; then
      echo "ols_credential_rotation_due: |"
      echo "$OLS_WARN" | sed 's/^/  /'
      # corp-llmcreds is the only secret rotate-key.sh will act on; any
      # other secret listed here is on a review interval, not a
      # rotation cycle, and must be handled at its own provider.
      if echo "$OLS_WARN" | grep -q '^corp-llmcreds:'; then
        echo "  action: bash ~/.agents/skills/crc-ols/scripts/rotate-key.sh corp-models --from-keyring"
      else
        echo "  action: review at the credential's own provider — rotate-key.sh only manages corp-models"
      fi
    else
      echo "ols_credential_rotation_due: none"
    fi
  fi
else
  cat <<STOPPED
--- CLUSTER IS STOPPED ---
No extended checks performed. Steps 3-6 require a running cluster.
Do NOT attempt to start CRC. Report the status above and stop.
STOPPED
fi

echo "=== End Report ==="

[[ "$(type -t trace_end)" == "function" ]] && trace_end 0
exit 0
