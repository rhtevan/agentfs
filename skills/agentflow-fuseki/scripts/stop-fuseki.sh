#!/usr/bin/env bash
# stop-fuseki.sh — Stop the Fuseki systemd user service
# Usage: bash stop-fuseki.sh [--dry-run]
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

echo "══════════════════════════════════════════════════════"
echo "  Stopping Fuseki"
echo "══════════════════════════════════════════════════════"

# Check if service unit exists
if ! systemctl --user cat "${SERVICE}" &>/dev/null; then
    echo "  [~] Service unit not found. Nothing to stop."
    if $DRY_RUN; then
      echo ""
      echo "DRY_RUN_RESULT=CONVERGED"
    else
      echo "APPLY_RESULT=OK"
    fi
    exit 0
fi

# Check if running
if ! systemctl --user is-active "${SERVICE}" &>/dev/null; then
    echo "  [~] Fuseki is not running"
else
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Stop ${SERVICE}"
      CHANGES=$((CHANGES + 1))
    else
      echo "  [+] Stopping ${SERVICE}..."
      systemctl --user stop "${SERVICE}"
      echo "  [✓] Service stopped"
    fi
fi

# Disable auto-start on login
if systemctl --user is-enabled "${SERVICE}" &>/dev/null; then
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Disable ${SERVICE} auto-start"
      CHANGES=$((CHANGES + 1))
    else
      echo "  [+] Disabling ${SERVICE} auto-start..."
      systemctl --user disable "${SERVICE}"
      echo "  [✓] Service disabled (won't start on next login)"
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

# Verify port is released
sleep 2
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 \
    "http://localhost:${PORT}/\$/ping" 2>/dev/null) || true

if [[ "$HTTP_CODE" == "000" || -z "$HTTP_CODE" ]]; then
    echo "  [✓] Port ${PORT} is released"
else
    echo "  [!] Port ${PORT} still responding (HTTP ${HTTP_CODE})"
    echo "      Checking for lingering processes..."
    if pgrep -f fuseki-server &>/dev/null; then
        echo "      Killing lingering fuseki-server process..."
        pkill -f fuseki-server
        sleep 2
        echo "      [✓] Process killed"
    fi
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "APPLY_RESULT=OK"
else
  echo "APPLY_RESULT=PARTIAL"
fi
echo "══════════════════════════════════════════════════════"
