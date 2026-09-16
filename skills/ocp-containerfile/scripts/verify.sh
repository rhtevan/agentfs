#!/usr/bin/env bash
# verify.sh — Verify a built container image against OpenShift constraints
# Usage: bash verify.sh <image-ref> [--mode legacy|userns|both]
# Exit codes: 0 = all pass, 1 = failures found, 2 = usage error
set -euo pipefail

IMAGE=""
MODE="both"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash verify.sh <image-ref> [--mode legacy|userns|both]"
      echo "Verifies a built image against OpenShift constraints using podman inspect."
      exit 0
      ;;
    *)
      if [[ -z "$IMAGE" ]]; then
        IMAGE="$1"
        shift
      else
        echo "❌ Unknown argument: $1"
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$IMAGE" ]]; then
  echo "❌ No image reference provided."
  echo "Usage: bash verify.sh <image-ref> [--mode legacy|userns|both]"
  exit 2
fi

if ! command -v podman &>/dev/null; then
  echo "❌ podman not found — required for image verification"
  exit 2
fi

echo "🔍 Verifying image: $IMAGE (mode: $MODE)"
echo "─────────────────────────────────────────"

PASS=0
FAIL=0
WARN=0

check() {
  local rule="$1" result="$2" detail="$3"
  if [[ "$result" == "pass" ]]; then
    echo "✅ $rule"
    ((PASS++))
  elif [[ "$result" == "fail" ]]; then
    echo "❌ $rule — $detail"
    ((FAIL++))
  elif [[ "$result" == "warn" ]]; then
    echo "⚠️  $rule — $detail"
    ((WARN++))
  fi
}

# Pull inspect data
INSPECT=$(podman inspect "$IMAGE" 2>/dev/null) || {
  echo "❌ Failed to inspect image: $IMAGE"
  echo "   Make sure the image exists locally (podman images) or pull it first."
  exit 1
}

# --- V1: USER is set and non-root ---
IMG_USER=$(echo "$INSPECT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('Config',{}).get('User',''))" 2>/dev/null || echo "")
if [[ -z "$IMG_USER" ]]; then
  check "V1: USER set in image" "fail" "No USER configured"
elif [[ "$IMG_USER" == "0" || "$IMG_USER" == "root" ]]; then
  if [[ "$MODE" == "userns" ]]; then
    check "V1: USER in image" "warn" "USER is $IMG_USER — safe with user namespaces but may fail certification"
  else
    check "V1: USER is non-root" "fail" "USER is $IMG_USER"
  fi
else
  check "V1: USER is non-root ($IMG_USER)" "pass" ""
fi

# --- V2: Required labels ---
REQUIRED_LABELS=("name" "vendor" "version" "release" "summary" "description")
LABELS_JSON=$(echo "$INSPECT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
labels = d[0].get('Config', {}).get('Labels', {}) or {}
for k, v in labels.items():
    print(f'{k}={v}')
" 2>/dev/null || echo "")

MISSING=()
for label in "${REQUIRED_LABELS[@]}"; do
  if ! echo "$LABELS_JSON" | grep -qiE "^${label}="; then
    MISSING+=("$label")
  fi
done
if [[ ${#MISSING[@]} -eq 0 ]]; then
  check "V2: Required certification labels" "pass" ""
else
  check "V2: Required certification labels" "fail" "Missing: ${MISSING[*]}"
fi

# --- V3: Layer count ---
LAYER_COUNT=$(echo "$INSPECT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
layers = d[0].get('RootFS', {}).get('Layers', [])
print(len(layers))
" 2>/dev/null || echo "0")

if [[ "$LAYER_COUNT" -ge 40 ]]; then
  check "V3: Layer count (<40)" "fail" "$LAYER_COUNT layers"
elif [[ "$LAYER_COUNT" -ge 30 ]]; then
  check "V3: Layer count (<40)" "warn" "$LAYER_COUNT layers — approaching limit"
else
  check "V3: Layer count (<40)" "pass" "$LAYER_COUNT layers"
fi

# --- V4: /licenses directory ---
LICENSE_CHECK=$(podman run --rm --entrypoint="" "$IMAGE" ls /licenses/ 2>/dev/null || echo "MISSING")
if [[ "$LICENSE_CHECK" == "MISSING" ]] || [[ -z "$LICENSE_CHECK" ]]; then
  check "V4: /licenses directory with content" "fail" "Directory missing or empty"
else
  check "V4: /licenses directory with content" "pass" ""
fi

# --- V5: Exposed ports ---
PORTS=$(echo "$INSPECT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
exposed = d[0].get('Config', {}).get('ExposedPorts', {}) or {}
for p in exposed:
    port_num = p.split('/')[0]
    print(port_num)
" 2>/dev/null || echo "")

if [[ -n "$PORTS" ]]; then
  PRIV=$(echo "$PORTS" | awk '$1 < 1024' || true)
  if [[ -n "$PRIV" ]]; then
    check "V5: Non-privileged ports" "fail" "Privileged port(s): $(echo $PRIV | tr '\n' ' ')"
  else
    check "V5: Non-privileged ports" "pass" ""
  fi
else
  check "V5: Non-privileged ports" "warn" "No ports exposed"
fi

# --- V6: Image size ---
SIZE_BYTES=$(echo "$INSPECT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d[0].get('Size', 0))
" 2>/dev/null || echo "0")
SIZE_MB=$((SIZE_BYTES / 1048576))
if [[ "$SIZE_MB" -gt 1000 ]]; then
  check "V6: Image size" "warn" "${SIZE_MB} MB — consider optimizing"
else
  check "V6: Image size (${SIZE_MB} MB)" "pass" ""
fi

# --- Summary ---
echo "─────────────────────────────────────────"
echo "Results: ✅ $PASS passed | ❌ $FAIL failed | ⚠️  $WARN warnings"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
