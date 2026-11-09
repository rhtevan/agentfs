#!/usr/bin/env bash
# fix-projects-json.sh — Diagnose and repair Goose projects.json parse errors
#
# Checks for malformed JSON in the project tracker file and repairs
# common issues (extra trailing braces, truncation).
#
# Usage: fix-projects-json.sh [--dry-run]
#
# Exit codes:
#   0 — File is valid JSON (or was repaired successfully)
#   1 — File not found or repair failed

set -euo pipefail

# Trace instrumentation for Observable scoring
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-cli-fix" "1.2.0" 2>/dev/null || true

PROJECTS_FILE="$HOME/.local/share/goose/projects.json"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "Goose projects.json Repair"
echo "══════════════════════════"

# Step 1: Check file exists
if [[ ! -f "$PROJECTS_FILE" ]]; then
  echo "❌ File not found: $PROJECTS_FILE"
  echo "   Creating empty project tracker..."
  if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p "$(dirname "$PROJECTS_FILE")"
    echo '{"projects": {}}' > "$PROJECTS_FILE"
    echo "✅ Created empty projects.json"
  else
    echo "   [DRY RUN] Would create empty projects.json"
  fi
  exit 0
fi

echo "File: $PROJECTS_FILE"
echo "Size: $(wc -c < "$PROJECTS_FILE") bytes"
echo ""

# Step 2: Validate JSON
echo "1. Validating JSON..."
trace_step 1 "diagnose_json" 0 "file=$PROJECTS_FILE" 2>/dev/null || true
if python3 -m json.tool "$PROJECTS_FILE" > /dev/null 2>&1; then
  echo "   ✅ Valid JSON — no repair needed"
  trace_end 2>/dev/null || true
  exit 0
fi

echo "   ❌ Invalid JSON detected"
echo ""

# Step 3: Diagnose common issues
echo "2. Diagnosing..."

# Count braces
OPEN_BRACES=$(grep -o '{' "$PROJECTS_FILE" | wc -l)
CLOSE_BRACES=$(grep -o '}' "$PROJECTS_FILE" | wc -l)
echo "   Open braces:  $OPEN_BRACES"
echo "   Close braces: $CLOSE_BRACES"

if [[ "$CLOSE_BRACES" -gt "$OPEN_BRACES" ]]; then
  EXTRA=$((CLOSE_BRACES - OPEN_BRACES))
  echo "   Issue: $EXTRA extra closing brace(s) at end of file"
  echo ""

  # Step 4: Repair by removing trailing extra braces
  echo "3. Repairing..."
  if [[ "$DRY_RUN" == "false" ]]; then
    # Remove trailing whitespace and extra closing braces
    python3 -c "
import json, re
with open('$PROJECTS_FILE', 'r') as f:
    content = f.read()
# Strip trailing whitespace and extra closing braces
content = content.rstrip()
while content.count('}') > content.count('{'):
    content = content.rstrip()
    if content.endswith('}'):
        content = content[:-1]
content = content.rstrip()
# Validate
try:
    data = json.loads(content)
    with open('$PROJECTS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    print('   ✅ Repaired successfully')
except json.JSONDecodeError as e:
    print(f'   ❌ Repair failed: {e}')
    exit(1)
"
  else
    echo "   [DRY RUN] Would remove $EXTRA extra closing brace(s)"
  fi
elif [[ "$OPEN_BRACES" -gt "$CLOSE_BRACES" ]]; then
  echo "   Issue: Truncated file (missing closing braces)"
  echo ""
  echo "3. Resetting to empty tracker..."
  if [[ "$DRY_RUN" == "false" ]]; then
    echo '{"projects": {}}' > "$PROJECTS_FILE"
    echo "   ✅ Reset to empty projects.json"
  else
    echo "   [DRY RUN] Would reset to empty projects.json"
  fi
else
  echo "   Issue: Brace count matches but JSON is invalid"
  echo "   Possible: duplicate keys, invalid characters, or encoding issue"
  echo ""
  echo "3. Resetting to empty tracker..."
  if [[ "$DRY_RUN" == "false" ]]; then
    echo '{"projects": {}}' > "$PROJECTS_FILE"
    echo "   ✅ Reset to empty projects.json (Goose will repopulate)"
  else
    echo "   [DRY RUN] Would reset to empty projects.json"
  fi
fi

# Step 5: Final validation
echo ""
echo "4. Final validation..."
if python3 -m json.tool "$PROJECTS_FILE" > /dev/null 2>&1; then
  PROJECTS=$(python3 -c "import json; print(len(json.load(open('$PROJECTS_FILE')).get('projects',{})))")
  echo "   ✅ Valid JSON — $PROJECTS project(s) in tracker"
  trace_step 2 "validate_json" 0 "projects=$PROJECTS" 2>/dev/null || true
  trace_end 2>/dev/null || true
else
  echo "   ❌ Still invalid — manual inspection required"
  trace_step 2 "validate_json" 1 "still_invalid" 2>/dev/null || true
  trace_end 2>/dev/null || true
  exit 1
fi
