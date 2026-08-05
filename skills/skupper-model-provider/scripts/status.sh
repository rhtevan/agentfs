#!/usr/bin/env bash
# status.sh — Check the status of all Skupper Model Provider components
# Usage: bash status.sh <NAMESPACE> <REMOTE_SSH_HOST>
#
# Architecture: Local=edge, Remote=interior/hub + model runtime.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <NAMESPACE> <REMOTE_SSH_HOST>" >&2
  exit 2
fi

NAMESPACE="$1"
REMOTE_SSH_HOST="$2"
MODEL_PORT=8000

echo "══════════════════════════════════════════════════════════"
echo "Skupper Model Provider — Status"
echo "══════════════════════════════════════════════════════════"

# ---- Skupper Sites ----
echo ""
echo "── Skupper Sites ──"
REMOTE_SVC=$(ssh "${REMOTE_SSH_HOST}" "systemctl --user is-active skupper-${NAMESPACE}.service 2>/dev/null || echo inactive")
LOCAL_SVC=$(systemctl --user is-active "skupper-${NAMESPACE}.service" 2>/dev/null || echo "inactive")

if [[ "$REMOTE_SVC" == "active" ]]; then
  echo "✅ Remote (interior): active"
else
  echo "⬚  Remote (interior): ${REMOTE_SVC}"
fi

if [[ "$LOCAL_SVC" == "active" ]]; then
  echo "✅ Local (edge):      active"
else
  echo "⬚  Local (edge):      ${LOCAL_SVC}"
fi

# ---- Inter-site Link ----
echo ""
echo "── Inter-site Link ──"
LINK_ESTAB=$(ss -tnp 2>/dev/null | { grep 45671 || true; } | { grep ESTAB || true; } | wc -l)
if [[ "$LINK_ESTAB" -gt 0 ]]; then
  echo "✅ Link: ${LINK_ESTAB} ESTAB connections on port 45671"
else
  echo "⬚  Link: no established connections on port 45671"
fi

# ---- Model Runtime on Remote ----
echo ""
echo "── Model Runtime (${REMOTE_SSH_HOST}) ──"
for ALIAS in g350m g1b g8b; do
  CONTAINER="model-${ALIAS}"
  STATUS=$(ssh "${REMOTE_SSH_HOST}" "podman ps -a --filter name=${CONTAINER} --format '{{.Status}}' 2>/dev/null" || true)
  if [[ -z "$STATUS" ]]; then
    continue  # Container doesn't exist, skip
  fi
  RUNNING=$(echo "$STATUS" | { grep -c '^Up' || true; })
  if [[ "$RUNNING" -gt 0 ]]; then
    echo "✅ ${CONTAINER}: ${STATUS}"
  else
    echo "⬚  ${CONTAINER}: ${STATUS}"
  fi
done

# Remote API check
REMOTE_API=$(ssh "${REMOTE_SSH_HOST}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${MODEL_PORT}/v1/models 2>/dev/null" || echo "000")
if [[ "$REMOTE_API" == "200" ]]; then
  REMOTE_MODEL=$(ssh "${REMOTE_SSH_HOST}" "curl -s http://localhost:${MODEL_PORT}/v1/models" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "unknown")
  echo "✅ Remote API:  HTTP 200 — model: ${REMOTE_MODEL}"
else
  echo "⬚  Remote API:  HTTP ${REMOTE_API}"
fi

# ---- Local Listener ----
echo ""
echo "── Local Endpoint ──"
LISTENER_PORT=$(ss -tlnp 2>/dev/null | { grep ":${MODEL_PORT} " || true; } | head -1)
if [[ -n "$LISTENER_PORT" ]]; then
  echo "✅ Port ${MODEL_PORT}: listening"
else
  echo "⬚  Port ${MODEL_PORT}: not listening"
fi

# Local API check (through Skupper)
LOCAL_API=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${MODEL_PORT}/v1/models" 2>/dev/null || echo "000")
if [[ "$LOCAL_API" == "200" ]]; then
  LOCAL_MODEL=$(curl -s "http://localhost:${MODEL_PORT}/v1/models" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "unknown")
  echo "✅ Local API:   HTTP 200 — model: ${LOCAL_MODEL} (via Skupper VAN)"
else
  echo "⬚  Local API:   HTTP ${LOCAL_API}"
fi

echo ""
