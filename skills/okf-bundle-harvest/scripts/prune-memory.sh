#!/usr/bin/env bash
# prune-memory.sh — Remove a graduated entry from a MEMORY.md file.
#
# Usage: bash prune-memory.sh <MEMORY_FILE> <ENTRY_CONTENT>
#
# Finds the §-delimited entry in MEMORY_FILE whose content matches
# ENTRY_CONTENT (substring match, trimmed), removes it, and writes
# the file back. Creates a timestamped backup before modifying.
#
# Exit codes:
#   0 — Entry found and removed
#   1 — Entry not found (no modification)
#   2 — Usage error or file not found

set -euo pipefail

MEMORY_FILE="${1:?Usage: prune-memory.sh <MEMORY_FILE> <ENTRY_CONTENT>}"
ENTRY_CONTENT="${2:?Usage: prune-memory.sh <MEMORY_FILE> <ENTRY_CONTENT>}"

if [[ ! -f "$MEMORY_FILE" ]]; then
  echo "ERROR: File not found: $MEMORY_FILE" >&2
  exit 2
fi

# Check write permission
if [[ ! -w "$MEMORY_FILE" ]]; then
  echo "ERROR: File is not writable: $MEMORY_FILE" >&2
  echo "SKIP: Cannot prune from read-only file. Remove manually." >&2
  exit 2
fi

# Create backup
BACKUP="${MEMORY_FILE}.bak.$(date +%s)"
cp "$MEMORY_FILE" "$BACKUP"

# Trim whitespace from search content for matching
SEARCH_CONTENT="$(echo "$ENTRY_CONTENT" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"

if [[ -z "$SEARCH_CONTENT" ]]; then
  echo "ERROR: Empty entry content provided" >&2
  exit 2
fi

# Use python3 for reliable §-delimited entry removal
python3 - "$MEMORY_FILE" "$SEARCH_CONTENT" <<'PYEOF'
import sys
import os

memory_file = sys.argv[1]
search_content = sys.argv[2].strip()

with open(memory_file, 'r') as f:
    content = f.read()

# Split on § delimiter
parts = content.split('§')

if len(parts) <= 1:
    # No § delimiters — try line-based matching
    lines = content.splitlines(keepends=True)
    new_lines = []
    found = False
    for line in lines:
        stripped = line.strip()
        if search_content in stripped and not found:
            found = True
            continue  # Skip this line
        new_lines.append(line)
    if not found:
        print(f"NOT FOUND: No entry matching: {search_content[:60]}...")
        sys.exit(1)
    with open(memory_file, 'w') as f:
        f.write(''.join(new_lines))
    print(f"PRUNED (line-based): Removed entry matching: {search_content[:60]}...")
    sys.exit(0)

# §-delimited processing
found = False
new_parts = []
for i, part in enumerate(parts):
    trimmed = part.strip()
    if search_content in trimmed and not found:
        found = True
        continue  # Skip this entry
    new_parts.append(part)

if not found:
    print(f"NOT FOUND: No entry matching: {search_content[:60]}...")
    sys.exit(1)

# Reconstruct with § delimiters
# The first part (before any §) is kept as-is (may be header/preamble)
if len(new_parts) == 0:
    # All entries removed — leave empty file with newline
    result = "\n"
elif len(new_parts) == 1:
    result = new_parts[0]
else:
    # Rejoin: first part is preamble, rest are §-prefixed entries
    result = new_parts[0]
    for part in new_parts[1:]:
        # Only add § if the part has content
        if part.strip():
            result += '§' + part
        elif part:  # Preserve whitespace-only parts
            result += part

# Clean up: remove trailing empty § markers, ensure file ends with newline
result = result.rstrip()
if result:
    result += '\n'

with open(memory_file, 'w') as f:
    f.write(result)

print(f"PRUNED: Removed entry matching: {search_content[:60]}...")
print(f"  Source: {memory_file}")
sys.exit(0)
PYEOF
