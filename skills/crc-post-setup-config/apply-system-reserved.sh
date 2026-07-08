#!/bin/bash
# apply-system-reserved.sh
# Override CRC's default kubelet system-reserved resources via a MachineConfig.
#
# CRC ships a MachineConfig (99-node-sizing-for-crc) that writes
# /etc/node-sizing-enabled.env with low defaults (350Mi memory).
# At boot, kubelet-auto-node-size.service reads that file and generates
# /etc/node-sizing.env, which the kubelet uses for --system-reserved flags.
#
# This script creates a higher-priority MachineConfig (99-z-crc-system-reserved-override)
# that overrides /etc/node-sizing-enabled.env with larger values.
# Because "99-z-..." sorts after "99-node-sizing-for-crc", it wins during rendering.
#
# The change persists across CRC restarts (crc stop/start) and MCO reconciliation.
# It does NOT persist across crc delete — re-run this skill after cluster recreation.
#
# Safe to run repeatedly — oc apply is idempotent.

set -euo pipefail

DESIRED_MEMORY="1Gi"
DESIRED_CPU="500m"
DESIRED_ES="1Gi"

echo "Checking for existing system-reserved override MachineConfig..."

EXISTING=$(oc get mc 99-z-crc-system-reserved-override -o jsonpath='{.metadata.name}' 2>/dev/null || true)

if [ -n "$EXISTING" ]; then
    # Decode the current content to check if values already match
    CURRENT=$(oc get mc 99-z-crc-system-reserved-override -o json 2>/dev/null | python3 -c "
import json, sys, base64
mc = json.load(sys.stdin)
src = mc['spec']['config']['storage']['files'][0]['contents']['source']
print(base64.b64decode(src.split(',',1)[1]).decode())
" 2>/dev/null || true)

    if echo "$CURRENT" | grep -q "SYSTEM_RESERVED_MEMORY=${DESIRED_MEMORY}" && \
       echo "$CURRENT" | grep -q "SYSTEM_RESERVED_CPU=${DESIRED_CPU}" && \
       echo "$CURRENT" | grep -q "SYSTEM_RESERVED_ES=${DESIRED_ES}"; then
        echo "✅ MachineConfig already exists with desired values. Nothing to do."
        exit 0
    fi
fi

echo "Creating/updating system-reserved override MachineConfig..."

# Build the file content and base64-encode it
CONTENT="NODE_SIZING_ENABLED=false
SYSTEM_RESERVED_MEMORY=${DESIRED_MEMORY}
SYSTEM_RESERVED_CPU=${DESIRED_CPU}
SYSTEM_RESERVED_ES=${DESIRED_ES}
"
B64=$(echo -n "$CONTENT" | base64 -w0)

cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-z-crc-system-reserved-override
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,${B64}
        mode: 0420
        overwrite: true
        path: /etc/node-sizing-enabled.env
EOF

echo ""
echo "✅ MachineConfig 99-z-crc-system-reserved-override applied"
echo ""
echo "Settings (override /etc/node-sizing-enabled.env):"
echo "  SYSTEM_RESERVED_MEMORY: ${DESIRED_MEMORY}  (CRC default: 350Mi)"
echo "  SYSTEM_RESERVED_CPU:    ${DESIRED_CPU}   (CRC default: 200m)"
echo "  SYSTEM_RESERVED_ES:     ${DESIRED_ES}  (CRC default: 350Mi)"
echo ""
echo "The MCO will render a new config. On CRC, a restart (crc stop && crc start)"
echo "is needed for the node to pick up the new rendered MachineConfig."
echo "After restart the SystemMemoryExceedsReservation alert will not fire."
