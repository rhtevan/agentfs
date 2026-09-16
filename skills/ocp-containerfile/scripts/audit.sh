#!/usr/bin/env bash
# audit.sh — Lint a Containerfile against OpenShift best practices
# Usage: bash audit.sh [--mode legacy|userns|both] [--file <path>]
# Exit codes: 0 = all pass, 1 = failures found, 2 = usage error
set -euo pipefail

MODE="both"
FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --file)
      FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash audit.sh [--mode legacy|userns|both] [--file <path>]"
      echo "Modes: legacy (restricted-v2), userns (restricted-v3), both (default)"
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "Usage: bash audit.sh [--mode legacy|userns|both] [--file <path>]"
      exit 2
      ;;
  esac
done

if [[ ! "$MODE" =~ ^(legacy|userns|both)$ ]]; then
  echo "❌ Invalid mode: $MODE (must be legacy, userns, or both)"
  exit 2
fi

# Auto-detect Containerfile
if [[ -z "$FILE" ]]; then
  for candidate in Containerfile Dockerfile containerfile dockerfile; do
    if [[ -f "$candidate" ]]; then
      FILE="$candidate"
      break
    fi
  done
fi

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "❌ No Containerfile found. Use --file <path> or run from a directory containing a Containerfile."
  exit 2
fi

echo "🔍 Auditing: $FILE (mode: $MODE)"
echo "─────────────────────────────────────────"

PASS=0
FAIL=0
WARN=0

check() {
  local severity="$1" rule="$2" result="$3" detail="$4"
  if [[ "$result" == "pass" ]]; then
    echo "✅ $rule"
    PASS=$((PASS + 1))
  elif [[ "$result" == "fail" ]]; then
    echo "❌ $rule — $detail"
    FAIL=$((FAIL + 1))
  elif [[ "$result" == "warn" ]]; then
    echo "⚠️  $rule — $detail"
    WARN=$((WARN + 1))
  elif [[ "$result" == "skip" ]]; then
    echo "⏭️  $rule — $detail"
  fi
}

CONTENT=$(cat "$FILE")
# Strip comments for analysis
STRIPPED=$(echo "$CONTENT" | grep -v '^\s*#' || true)

# --- R1: Non-root USER directive ---
USER_LINES=$(echo "$STRIPPED" | grep -i '^\s*USER\s' || true)
if [[ -z "$USER_LINES" ]]; then
  check "R" "R1: USER directive present" "fail" "No USER directive found"
elif echo "$USER_LINES" | grep -qiE '^\s*USER\s+(root|0)\s*$'; then
  check "R" "R1: USER is non-root" "fail" "USER is root or 0"
else
  check "R" "R1: USER is non-root" "pass" ""
fi

# --- R2: Numeric UID ---
if [[ -n "$USER_LINES" ]]; then
  LAST_USER=$(echo "$USER_LINES" | tail -1 | awk '{print $2}' | cut -d: -f1)
  if [[ "$LAST_USER" =~ ^[0-9]+$ ]]; then
    check "R" "R2: USER is numeric UID" "pass" ""
  else
    check "R" "R2: USER is numeric UID" "fail" "USER '$LAST_USER' is not numeric — OpenShift cannot verify non-root"
  fi
fi

# --- R3: GID 0 permissions (legacy/both) ---
if [[ "$MODE" == "legacy" || "$MODE" == "both" ]]; then
  if echo "$STRIPPED" | grep -qE '(chgrp.*\b0\b|chmod.*g[+=]u|chown.*:0\b)'; then
    check "R" "R3: GID 0 permissions pattern" "pass" ""
  else
    if [[ "$MODE" == "both" ]]; then
      check "W" "R3: GID 0 permissions pattern" "warn" "Not found — needed for restricted-v2 compat"
    else
      check "R" "R3: GID 0 permissions pattern" "fail" "Not found — required for restricted-v2"
    fi
  fi
elif [[ "$MODE" == "userns" ]]; then
  check "S" "R3: GID 0 permissions pattern" "skip" "Not required under user namespaces"
fi

# --- R4: Non-privileged ports ---
EXPOSE_LINES=$(echo "$STRIPPED" | grep -iE '^\s*EXPOSE\s' || true)
if [[ -n "$EXPOSE_LINES" ]]; then
  PRIV_PORTS=$(echo "$EXPOSE_LINES" | grep -oE '\b[0-9]+\b' | awk '$1 < 1024' || true)
  if [[ -n "$PRIV_PORTS" ]]; then
    check "R" "R4: Non-privileged ports (>1024)" "fail" "Privileged port(s) found: $(echo $PRIV_PORTS | tr '\n' ' ')"
  else
    check "R" "R4: Non-privileged ports (>1024)" "pass" ""
  fi
else
  check "W" "R4: Non-privileged ports (>1024)" "warn" "No EXPOSE directive found"
fi

# --- R5: UBI base image ---
FROM_LINES=$(echo "$STRIPPED" | grep -iE '^\s*FROM\s' || true)
if echo "$FROM_LINES" | grep -qiE '(ubi[0-9]|rhel[0-9]|registry\.(access\.)?redhat\.(com|io))'; then
  check "R" "R5: UBI/RHEL base image" "pass" ""
else
  FINAL_FROM=$(echo "$FROM_LINES" | tail -1)
  check "R" "R5: UBI/RHEL base image" "fail" "Final stage base: $FINAL_FROM"
fi

# --- R6: Required labels ---
REQUIRED_LABELS=("name" "vendor" "version" "release" "summary" "description")
MISSING_LABELS=()
for label in "${REQUIRED_LABELS[@]}"; do
  if ! echo "$STRIPPED" | grep -qiE "(LABEL|label).*\b${label}\b\s*[=]"; then
    # Also check for label on its own line in multi-line LABEL
    if ! echo "$STRIPPED" | grep -qiE "^\s*${label}\s*[=]"; then
      MISSING_LABELS+=("$label")
    fi
  fi
done
if [[ ${#MISSING_LABELS[@]} -eq 0 ]]; then
  check "R" "R6: Required certification labels" "pass" ""
else
  check "R" "R6: Required certification labels" "fail" "Missing: ${MISSING_LABELS[*]}"
fi

# --- R7: /licenses directory ---
if echo "$STRIPPED" | grep -qiE '(/licenses|/licenses/)'; then
  check "R" "R7: /licenses directory" "pass" ""
else
  check "R" "R7: /licenses directory" "fail" "No /licenses directory creation or COPY found"
fi

# --- R8: Layer count estimate ---
LAYER_COUNT=$(echo "$STRIPPED" | grep -ciE '^\s*(FROM|RUN|COPY|ADD)\s' || echo "0")
if [[ "$LAYER_COUNT" -ge 40 ]]; then
  check "R" "R8: Layer count (<40)" "fail" "Estimated $LAYER_COUNT layer instructions"
elif [[ "$LAYER_COUNT" -ge 30 ]]; then
  check "W" "R8: Layer count (<40)" "warn" "Estimated $LAYER_COUNT layer instructions — approaching limit"
else
  check "R" "R8: Layer count (<40)" "pass" "Estimated $LAYER_COUNT layer instructions"
fi

# --- R9: Package cache cleanup ---
if echo "$STRIPPED" | grep -qiE '(dnf|microdnf|yum)\s+install'; then
  if echo "$STRIPPED" | grep -qiE '(dnf|microdnf|yum)\s+(clean\s+all|clean)'; then
    # Check if install and clean are in the same RUN (rough heuristic)
    check "R" "R9: Package cache cleanup" "pass" ""
  else
    check "R" "R9: Package cache cleanup" "fail" "Package install found without clean in the Containerfile"
  fi
else
  check "S" "R9: Package cache cleanup" "skip" "No package installation detected"
fi

# --- R10: Multi-stage build ---
FROM_COUNT=$(echo "$STRIPPED" | grep -ciE '^\s*FROM\s' || echo "0")
if [[ "$FROM_COUNT" -ge 2 ]]; then
  check "R" "R10: Multi-stage build" "pass" "$FROM_COUNT stages detected"
else
  check "W" "R10: Multi-stage build" "warn" "Single-stage build — consider multi-stage for smaller images"
fi

# --- R11: Entrypoint exec form ---
EP_LINES=$(echo "$STRIPPED" | grep -iE '^\s*ENTRYPOINT\s' || true)
if [[ -n "$EP_LINES" ]]; then
  if echo "$EP_LINES" | grep -qE '^\s*ENTRYPOINT\s*\['; then
    check "R" "R11: ENTRYPOINT exec form" "pass" ""
  else
    check "W" "R11: ENTRYPOINT exec form" "warn" "Shell form detected — signals won't reach PID 1"
  fi
else
  CMD_LINES=$(echo "$STRIPPED" | grep -iE '^\s*CMD\s' || true)
  if [[ -n "$CMD_LINES" ]]; then
    check "W" "R11: ENTRYPOINT exec form" "warn" "No ENTRYPOINT — using CMD only"
  else
    check "W" "R11: ENTRYPOINT exec form" "warn" "No ENTRYPOINT or CMD found"
  fi
fi

# --- R12: RPM modification check (heuristic) ---
if echo "$STRIPPED" | grep -qiE 'RUN\s+.*sed\s+-i.*(/etc/|/usr/)'; then
  check "W" "R12: No RPM file modifications" "warn" "Possible in-place edit of RPM-owned file detected"
else
  check "R" "R12: No RPM file modifications" "pass" ""
fi

# --- Summary ---
echo "─────────────────────────────────────────"
echo "Results: ✅ $PASS passed | ❌ $FAIL failed | ⚠️  $WARN warnings"
echo "Mode: $MODE"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
