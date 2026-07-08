#!/usr/bin/env bash
# scan-files.sh — Inventory all files and directories under a bundle root.
#
# Usage: bash scan-files.sh <BUNDLE_ROOT>
#
# Outputs a structured report grouped by category that the agent can use
# to decide on semantic naming, concept-doc creation, and asset placement.

set -euo pipefail

BUNDLE_ROOT="${1:?Usage: scan-files.sh <BUNDLE_ROOT>}"
BUNDLE_ROOT="$(cd "$BUNDLE_ROOT" && pwd)"

echo "═══════════════════════════════════════════════════════════════"
echo "  OKF Bundle Scan Report"
echo "  Root: $BUNDLE_ROOT"
echo "  Date: $(date -Iseconds)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── Count totals ─────────────────────────────────────────────────────
# Exclude hidden directories (.venv, .git, etc.) from all scans
FIND_PRUNE=(-name '.*' -prune -o)
TOTAL_FILES=$(find "$BUNDLE_ROOT" "${FIND_PRUNE[@]}" -type f -print | wc -l)
TOTAL_DIRS=$(find "$BUNDLE_ROOT" -mindepth 1 "${FIND_PRUNE[@]}" -type d -print | wc -l)

echo "Summary: $TOTAL_FILES file(s), $TOTAL_DIRS subdirectory(ies)"
echo ""

if [[ "$TOTAL_FILES" -eq 0 && "$TOTAL_DIRS" -eq 0 ]]; then
  echo "  (empty directory)"
  exit 0
fi

# ── Helper: list files by extension pattern ──────────────────────────
list_category() {
  local label="$1"
  shift
  local patterns=("$@")
  local found=0
  local tmpfile
  tmpfile=$(mktemp)

  for pat in "${patterns[@]}"; do
    find "$BUNDLE_ROOT" -name '.*' -prune -o -type f -iname "$pat" -printf "  %P  (%s bytes)\n" >> "$tmpfile" 2>/dev/null || true
  done

  if [[ -s "$tmpfile" ]]; then
    echo "── $label ──"
    sort "$tmpfile"
    found=$(wc -l < "$tmpfile")
    echo "  ($found file(s))"
    echo ""
  fi

  rm -f "$tmpfile"
}

# ── OKF infrastructure files ────────────────────────────────────────
echo "── OKF Infrastructure ──"
for name in index.md log.md; do
  if [[ -f "$BUNDLE_ROOT/$name" ]]; then
    echo "  ✓ $name (exists)"
  else
    echo "  ✗ $name (missing)"
  fi
done
echo ""

# ── Markdown files (potential concepts) ──────────────────────────────
echo "── Markdown Files ──"
find "$BUNDLE_ROOT" -name '.*' -prune -o -type f -iname "*.md" \
  ! -name "index.md" ! -name "log.md" \
  -printf "  %P  (%s bytes)\n" 2>/dev/null | sort
MD_COUNT=$(find "$BUNDLE_ROOT" -name '.*' -prune -o -type f -iname "*.md" \
  ! -name "index.md" ! -name "log.md" -print 2>/dev/null | wc -l)
echo "  ($MD_COUNT concept-candidate file(s))"
echo ""

# ── Category scans ───────────────────────────────────────────────────
list_category "Data Files" "*.csv" "*.tsv" "*.jsonl" "*.ndjson" "*.parquet" "*.avro" "*.orc" "*.xls" "*.xlsx"
list_category "Schema / Definition Files" "*.sql" "*.ddl" "*.proto" "*.avsc" "*.graphql" "*.gql"
list_category "API / Contract Files" "*.openapi.yaml" "*.openapi.json" "*.swagger.*" "*.wsdl" "*.raml"
list_category "JSON Files" "*.json"
list_category "YAML / TOML / Config Files" "*.yaml" "*.yml" "*.toml" "*.ini" "*.cfg" "*.conf" "*.env" "*.properties"
list_category "Images / Diagrams" "*.png" "*.jpg" "*.jpeg" "*.gif" "*.svg" "*.webp" "*.bmp" "*.ico" "*.drawio" "*.mermaid"
list_category "Documents" "*.pdf" "*.docx" "*.doc" "*.pptx" "*.ppt" "*.odt" "*.rtf"
list_category "Plain Text / Reference" "*.txt" "*.rst" "*.adoc" "*.log"
list_category "Code — Python" "*.py" "*.pyi" "*.ipynb"
list_category "Code — JavaScript / TypeScript" "*.js" "*.ts" "*.jsx" "*.tsx" "*.mjs" "*.cjs"
list_category "Code — Shell" "*.sh" "*.bash" "*.zsh" "*.fish"
list_category "Code — Other" "*.java" "*.go" "*.rs" "*.rb" "*.c" "*.cpp" "*.h" "*.hpp" "*.cs" "*.swift" "*.kt" "*.scala" "*.r" "*.R" "*.jl" "*.lua" "*.pl" "*.pm"
list_category "HTML / Web" "*.html" "*.htm" "*.css" "*.scss" "*.less"
list_category "Archives" "*.zip" "*.tar" "*.gz" "*.bz2" "*.xz" "*.7z" "*.rar"
list_category "Binary / Other" "*.bin" "*.dat" "*.db" "*.sqlite" "*.pickle" "*.pkl" "*.model" "*.pt" "*.onnx" "*.h5"

# ── Subdirectories ───────────────────────────────────────────────────
echo "── Subdirectories ──"
if [[ "$TOTAL_DIRS" -gt 0 ]]; then
  find "$BUNDLE_ROOT" -mindepth 1 -maxdepth 1 -name '.*' -prune -o -type d -printf "  %P/\n" | sort
  echo ""
  echo "  Nested tree (depth 3):"
  # Use find-based tree since `tree` might not be installed
  find "$BUNDLE_ROOT" -mindepth 1 -name '.*' -prune -o -type d -printf "  %P/\n" 2>/dev/null | sort | head -50
else
  echo "  (none)"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "  Scan complete."
echo "═══════════════════════════════════════════════════════════════"
