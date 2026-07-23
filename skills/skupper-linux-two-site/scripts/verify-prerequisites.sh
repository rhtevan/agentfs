#!/usr/bin/env bash
# verify-prerequisites.sh — Check that skrouterd and skupper CLI are installed on both hosts
# Usage: bash verify-prerequisites.sh <REMOTE_SSH_HOST>
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <REMOTE_SSH_HOST>" >&2
  exit 2
fi

REMOTE_SSH_HOST="$1"
FAILED=0

echo "=== Checking localhost ==="

if command -v skrouterd &>/dev/null; then
  echo "✅ skrouterd: $(skrouterd --version)"
else
  echo "❌ skrouterd not found on localhost"
  FAILED=1
fi

if command -v skupper &>/dev/null; then
  echo "✅ skupper CLI: $(skupper version)"
else
  echo "❌ skupper CLI not found on localhost"
  FAILED=1
fi

echo ""
echo "=== Checking ${REMOTE_SSH_HOST} ==="

REMOTE_SKROUTERD=$(ssh "${REMOTE_SSH_HOST}" 'skrouterd --version 2>/dev/null' || true)
if [[ -n "$REMOTE_SKROUTERD" ]]; then
  echo "✅ skrouterd: ${REMOTE_SKROUTERD}"
else
  echo "❌ skrouterd not found on ${REMOTE_SSH_HOST}"
  FAILED=1
fi

REMOTE_SKUPPER=$(ssh "${REMOTE_SSH_HOST}" 'skupper version 2>/dev/null' || true)
if [[ -n "$REMOTE_SKUPPER" ]]; then
  echo "✅ skupper CLI: ${REMOTE_SKUPPER}"
else
  echo "❌ skupper CLI not found on ${REMOTE_SSH_HOST}"
  FAILED=1
fi

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "All prerequisites met ✅"
  exit 0
else
  echo "Some prerequisites are missing ❌"
  exit 1
fi
