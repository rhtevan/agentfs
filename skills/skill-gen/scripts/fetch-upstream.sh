#!/usr/bin/env bash
# fetch-upstream.sh — Download and cache the Anthropic skill-creator
#
# Usage: bash fetch-upstream.sh [--force]
#
# Caches the complete upstream skill-creator file structure from
# https://github.com/anthropics/skills into .cache/upstream/.
# Re-fetches if cache is older than MAX_AGE_DAYS or --force is used.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$SKILL_DIR/.cache/upstream"
MARKER_FILE="$CACHE_DIR/.fetched"
MAX_AGE_DAYS=7
BASE_URL="https://raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator"

# File manifest — complete upstream structure
FILES=(
    "SKILL.md"
    "LICENSE.txt"
    "agents/analyzer.md"
    "agents/comparator.md"
    "agents/grader.md"
    "assets/eval_review.html"
    "eval-viewer/generate_review.py"
    "eval-viewer/viewer.html"
    "references/schemas.md"
    "scripts/__init__.py"
    "scripts/aggregate_benchmark.py"
    "scripts/generate_report.py"
    "scripts/improve_description.py"
    "scripts/package_skill.py"
    "scripts/quick_validate.py"
    "scripts/run_eval.py"
    "scripts/run_loop.py"
    "scripts/utils.py"
)

# --- Functions ---

need_fetch() {
    [[ "${1:-}" == "--force" ]] && return 0
    [[ ! -f "$MARKER_FILE" ]] && return 0

    local age
    if [[ "$(uname)" == "Darwin" ]]; then
        age=$(( ($(date +%s) - $(stat -f %m "$MARKER_FILE")) / 86400 ))
    else
        age=$(( ($(date +%s) - $(stat -c %Y "$MARKER_FILE")) / 86400 ))
    fi
    (( age >= MAX_AGE_DAYS ))
}

fetch_all() {
    echo "Fetching upstream skill-creator from anthropics/skills..."
    local failed=0

    for file in "${FILES[@]}"; do
        local dir
        dir=$(dirname "$file")
        mkdir -p "$CACHE_DIR/$dir"

        if curl -sL --fail "$BASE_URL/$file" -o "$CACHE_DIR/$file"; then
            echo "  ✓ $file"
        else
            echo "  ✗ $file (failed)"
            ((failed++))
        fi
    done

    if (( failed == 0 )); then
        date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKER_FILE"
        echo ""
        echo "Cached ${#FILES[@]} files to $CACHE_DIR"
        echo "Cache valid for $MAX_AGE_DAYS days. Use --force to re-fetch."
    else
        echo ""
        echo "WARNING: $failed file(s) failed to download."
        echo "Some advanced features may not work. Re-run with --force to retry."
    fi
}

# --- Main ---

if need_fetch "$@"; then
    fetch_all
else
    echo "Cache is fresh (< ${MAX_AGE_DAYS} days). Use --force to re-fetch."
    echo "Cache location: $CACHE_DIR"
fi
