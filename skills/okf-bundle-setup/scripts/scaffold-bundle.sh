#!/usr/bin/env bash
# scaffold-bundle.sh — Create the OKF skeleton (index.md + log.md) at a path.
#
# Usage: bash scaffold-bundle.sh <BUNDLE_ROOT>
#   BUNDLE_ROOT: directory to scaffold (created if missing).
#
# Idempotent — never overwrites existing files.
# README absorption — if a README.* exists and index.md does not, the
# README body (frontmatter stripped) becomes index.md and the original
# README is removed.

set -euo pipefail

BUNDLE_ROOT="${1:?Usage: scaffold-bundle.sh <BUNDLE_ROOT>}"
BUNDLE_ROOT="$(cd "$BUNDLE_ROOT" 2>/dev/null && pwd || (mkdir -p "$BUNDLE_ROOT" && cd "$BUNDLE_ROOT" && pwd))"
TODAY="$(date '+%Y-%m-%d %H:%M')"
NOW="$(date -Iseconds)"

echo "[okf-bundle-setup] Scaffolding OKF bundle at $BUNDLE_ROOT"

# ── Phase 1: Normalize directory name to lowercase kebab-case ────────
DIRNAME="$(basename "$BUNDLE_ROOT")"
PARENT="$(dirname "$BUNDLE_ROOT")"
KEBAB_NAME="$(echo "$DIRNAME" | tr '[:upper:]' '[:lower:]' | \
  sed 's/[_ ]/-/g; s/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//' | \
  cut -c1-25)"

if [[ "$KEBAB_NAME" != "$DIRNAME" && -n "$KEBAB_NAME" ]]; then
  NEW_ROOT="$PARENT/$KEBAB_NAME"
  if [[ -e "$NEW_ROOT" && "$NEW_ROOT" != "$BUNDLE_ROOT" ]]; then
    echo "  ⚠ Cannot rename '$DIRNAME' → '$KEBAB_NAME' (target already exists)"
  else
    echo "  ↳ Renaming '$DIRNAME' → '$KEBAB_NAME' (lowercase kebab-case)"
    mv "$BUNDLE_ROOT" "$NEW_ROOT"
    BUNDLE_ROOT="$NEW_ROOT"
  fi
fi

# ── Phase 3b: Absorb README into index.md ────────────────────────────
# Find any README variant (case-insensitive) at the bundle root.
README_FILE=""
for candidate in "$BUNDLE_ROOT"/README.md "$BUNDLE_ROOT"/readme.md \
                 "$BUNDLE_ROOT"/Readme.md "$BUNDLE_ROOT"/README.txt \
                 "$BUNDLE_ROOT"/readme.txt "$BUNDLE_ROOT"/README.rst \
                 "$BUNDLE_ROOT"/readme.rst "$BUNDLE_ROOT"/README; do
  if [[ -f "$candidate" ]]; then
    README_FILE="$candidate"
    break
  fi
done

# ── index.md (OKF §6 — directory listing, NO frontmatter) ───────────
if [[ ! -f "$BUNDLE_ROOT/index.md" ]]; then
  if [[ -n "$README_FILE" ]]; then
    # Absorb README into index.md — strip YAML frontmatter if present.
    README_NAME="$(basename "$README_FILE")"
    echo "  ↳ Absorbing $README_NAME into index.md"
    # Strip leading YAML frontmatter (--- delimited block at start of file)
    awk '
      BEGIN { in_fm=0; past_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { in_fm=0; past_fm=1; next }
      in_fm { next }
      { print }
    ' "$README_FILE" > "$BUNDLE_ROOT/index.md"
    rm -f "$README_FILE"
    echo "  ✓ index.md created (absorbed from $README_NAME)"
  else
    DIRNAME="$(basename "$BUNDLE_ROOT")"
    # Title-case the directory name for the heading
    TITLE="$(echo "$DIRNAME" | sed 's/-/ /g; s/\b\(.\)/\u\1/g')"
    cat > "$BUNDLE_ROOT/index.md" << EOF
# ${TITLE}

<!-- OKF index — no YAML frontmatter. Update after adding concepts. -->

<!-- Example entries:
* [Concept Title](concept.md) - Short description of the concept
* [Subdirectory](subdir/index.md) - Short description of the subdirectory
-->
EOF
    echo "  ✓ index.md created"
  fi
else
  # index.md exists — if a README also exists, warn and remove it.
  if [[ -n "$README_FILE" ]]; then
    README_NAME="$(basename "$README_FILE")"
    echo "  ⚠ index.md already exists — removing duplicate $README_NAME"
    rm -f "$README_FILE"
  else
    echo "  · index.md already exists — skipped"
  fi
fi

# ── log.md (OKF §7 — chronological update log) ──────────────────────
if [[ ! -f "$BUNDLE_ROOT/log.md" ]]; then
  cat > "$BUNDLE_ROOT/log.md" << EOF
# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## ${TODAY}

- Created OKF knowledge bundle structure.
EOF
  echo "  ✓ log.md created"
else
  echo "  · log.md already exists — skipped"
fi

echo "[okf-bundle-setup] Scaffold complete at $BUNDLE_ROOT"
