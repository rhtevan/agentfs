#!/usr/bin/env bash
# start-fuseki.sh — Start the Fuseki systemd user service and verify health
# Usage: bash start-fuseki.sh [--dry-run]
set -euo pipefail

DRY_RUN=false
CHANGES=0
ERRORS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
  esac
done

SERVICE="fuseki.service"
PORT=3030
MAX_WAIT=30

echo "══════════════════════════════════════════════════════"
echo "  Starting Fuseki"
echo "══════════════════════════════════════════════════════"

# Check if service unit exists
if ! systemctl --user cat "${SERVICE}" &>/dev/null; then
    echo "  [✗] Service unit not found. Run 'fuseki setup' first." >&2
    exit 1
fi

# Ensure service is enabled for auto-start on login
if ! systemctl --user is-enabled "${SERVICE}" &>/dev/null; then
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Enable ${SERVICE} for auto-start"
      CHANGES=$((CHANGES + 1))
    else
      echo "  [+] Enabling ${SERVICE} for auto-start..."
      systemctl --user enable "${SERVICE}"
    fi
fi

# Check if already running
if systemctl --user is-active "${SERVICE}" &>/dev/null; then
    echo "  [~] Fuseki is already running"
else
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Start ${SERVICE}"
      CHANGES=$((CHANGES + 1))
    else
      echo "  [+] Starting ${SERVICE}..."
      systemctl --user start "${SERVICE}"
    fi
fi

if $DRY_RUN; then
  echo ""
  if [[ $CHANGES -eq 0 ]]; then
    echo "DRY_RUN_RESULT=CONVERGED"
  else
    echo "DRY_RUN_RESULT=PENDING"
  fi
  echo "Changes: ${CHANGES}"
  exit 0
fi

# Wait for health
echo "  [+] Waiting for Fuseki to become healthy..."
elapsed=0
while [[ $elapsed -lt $MAX_WAIT ]]; do
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 \
        "http://localhost:${PORT}/\$/ping" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
    echo -n "."
done
echo ""

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "  [✗] Fuseki failed to start within ${MAX_WAIT}s" >&2
    echo "" >&2
    echo "  Checking journal logs:" >&2
    systemctl --user status "${SERVICE}" --no-pager 2>&1 | tail -10 >&2
    ERRORS=$((ERRORS + 1))
fi

# Report status
if [[ $ERRORS -eq 0 ]]; then
  echo "  [✓] Fuseki is running"
  echo ""
  echo "  Endpoint:  http://localhost:${PORT}"
  echo "  Web UI:    http://localhost:${PORT}/#/"
  echo ""

  # List datasets if any
  DATASETS=$(curl -s "http://localhost:${PORT}/\$/datasets" 2>/dev/null \
      | jq -r '.datasets[]."ds.name" // empty' 2>/dev/null || true)

  if [[ -n "$DATASETS" ]]; then
      echo "  Datasets:"
      while IFS= read -r ds; do
          echo "    - ${ds}"
      done <<< "$DATASETS"
  else
      echo "  Datasets: (none — create one via the Web UI or API)"
  fi
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "APPLY_RESULT=OK"
else
  echo "APPLY_RESULT=PARTIAL"
fi
echo "══════════════════════════════════════════════════════"
