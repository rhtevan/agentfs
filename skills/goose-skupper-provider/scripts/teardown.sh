#!/usr/bin/env bash
# teardown.sh — Remove Goose Skupper provider configuration
# Usage: bash teardown.sh

set -euo pipefail

PROVIDER_JSON="$HOME/.config/goose/custom_providers/custom_skupper.json"
CONFIG_YAML="$HOME/.config/goose/config.yaml"

echo "=== Goose Skupper Provider — Teardown ==="
echo

# ── Step 1: Check current state ───────────────────────────────
echo "Step 1: Check current state"
if [[ -f "$PROVIDER_JSON" ]]; then
  echo "  Found: $PROVIDER_JSON"
  python3 -c "
import json
with open('$PROVIDER_JSON') as f:
    d = json.load(f)
print(f'    model: {d[\"models\"][0][\"name\"]}')
print(f'    port:  {d[\"base_url\"]}')
" 2>/dev/null || echo "    (could not parse)"
else
  echo "  No custom_skupper.json found"
fi

if grep -q 'custom_skupper:' "$CONFIG_YAML" 2>/dev/null; then
  echo "  Found in config.yaml:"
  grep -A3 'custom_skupper:' "$CONFIG_YAML" | sed 's/^/    /'
else
  echo "  Not found in config.yaml"
fi
echo

# ── Step 2: Backup and remove JSON ────────────────────────────
echo "Step 2: Remove custom provider JSON"
if [[ -f "$PROVIDER_JSON" ]]; then
  BACKUP="${PROVIDER_JSON}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$PROVIDER_JSON" "$BACKUP"
  rm -f "$PROVIDER_JSON"
  echo "  ✅ Removed (backed up to $(basename $BACKUP))"
else
  echo "  (nothing to remove)"
fi
echo

# ── Step 3: Remove config.yaml entry ──────────────────────────
echo "Step 3: Remove config.yaml entry"
if grep -q 'custom_skupper:' "$CONFIG_YAML" 2>/dev/null; then
  BACKUP="${CONFIG_YAML}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_YAML" "$BACKUP"
  
  # Check if it's the active provider
  ACTIVE=$(grep 'active_provider:' "$CONFIG_YAML" | awk '{print $2}' || echo "")
  if [[ "$ACTIVE" == "custom_skupper" ]]; then
    echo "  ⚠️  custom_skupper is the active provider"
    echo "  Removing active_provider setting — you'll need to configure a new one."
    sed -i '/active_provider: custom_skupper/d' "$CONFIG_YAML"
  fi
  
  # Remove the provider block (4 lines: key + enabled + model + configured)
  sed -i '/^  custom_skupper:/,/^  [a-z]/{/^  custom_skupper:/d; /enabled:/d; /model:/d; /configured:/d}' "$CONFIG_YAML"
  
  echo "  ✅ Removed from config.yaml (backed up)"
else
  echo "  (nothing to remove)"
fi
echo

# ── Step 4: Verify ────────────────────────────────────────────
echo "Step 4: Verify"
[[ ! -f "$PROVIDER_JSON" ]] && echo "  ✅ JSON removed" || echo "  ❌ JSON still exists"
grep -c 'custom_skupper' "$CONFIG_YAML" 2>/dev/null | {
  read count
  [[ "$count" == "0" ]] && echo "  ✅ config.yaml clean" || echo "  ❌ Still $count references in config.yaml"
}
echo

echo "✅ Goose Skupper Provider teardown complete"
