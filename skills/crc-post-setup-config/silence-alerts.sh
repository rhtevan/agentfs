#!/bin/bash
# silence-alerts.sh
# Silence noisy alerts that are expected/irrelevant on a CRC dev cluster.
#
# Alertmanager silences are stored in-memory / PVC and do NOT survive
# crc delete && crc start, so this must be re-run after cluster recreation.
#
# Safe to run repeatedly — existing active silences for the same matchers
# are detected and skipped.

set -euo pipefail

# ── configuration ──────────────────────────────────────────────────────
# Each entry: "alertname|comment"
SILENCES=(
  "AlertmanagerReceiversNotConfigured|CRC dev cluster — no receivers needed"
)

# Silence duration: 1 year from now
STARTS_AT=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
ENDS_AT=$(date -u -d "+1 year" +"%Y-%m-%dT%H:%M:%S.000Z")
CREATED_BY="goose"
# ──────────────────────────────────────────────────────────────────────

echo "Checking Alertmanager silences..."

# Fetch existing active silences once
EXISTING=$(oc exec -n openshift-monitoring alertmanager-main-0 -c alertmanager -- \
  curl -s 'http://localhost:9093/api/v2/silences' 2>/dev/null)

for entry in "${SILENCES[@]}"; do
  ALERT_NAME="${entry%%|*}"
  COMMENT="${entry##*|}"

  # Check if an active silence already exists for this alertname
  ALREADY=$(echo "$EXISTING" | python3 -c "
import json, sys
for s in json.load(sys.stdin):
    if s['status']['state'] == 'active':
        for m in s['matchers']:
            if m['name'] == 'alertname' and m['value'] == '${ALERT_NAME}':
                print(s['id'])
                break
" 2>/dev/null || true)

  if [ -n "$ALREADY" ]; then
    echo "✅ ${ALERT_NAME}: already silenced (ID: ${ALREADY})"
    continue
  fi

  echo "Creating silence for ${ALERT_NAME}..."

  PAYLOAD=$(cat <<EOJSON
{
  "matchers": [
    {"name": "alertname", "value": "${ALERT_NAME}", "isRegex": false}
  ],
  "startsAt": "${STARTS_AT}",
  "endsAt": "${ENDS_AT}",
  "createdBy": "${CREATED_BY}",
  "comment": "${COMMENT}"
}
EOJSON
)

  RESULT=$(oc exec -n openshift-monitoring alertmanager-main-0 -c alertmanager -- \
    curl -s -X POST 'http://localhost:9093/api/v2/silences' \
    -H 'Content-Type: application/json' \
    -d "${PAYLOAD}" 2>/dev/null)

  SID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('silenceID','FAILED'))" 2>/dev/null || echo "FAILED")

  if [ "$SID" = "FAILED" ]; then
    echo "❌ ${ALERT_NAME}: failed to create silence"
    echo "   Response: ${RESULT}"
  else
    echo "✅ ${ALERT_NAME}: silenced (ID: ${SID}, expires: ${ENDS_AT})"
  fi
done

echo ""
echo "Done."
