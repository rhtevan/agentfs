#!/usr/bin/env bash
# validate-and-install.sh — Validate and install a bash completion script
# Usage: validate-and-install.sh <completion-file> <command-name> [--check]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "bash-completion-gen" "1.0.0" 2>/dev/null || true

COMPLETION_FILE="${1:-}"
COMMAND_NAME="${2:-}"
CHECK_ONLY=false

for arg in "$@"; do
  [[ "$arg" == "--check" ]] && CHECK_ONLY=true
done

if [[ -z "$COMPLETION_FILE" || -z "$COMMAND_NAME" ]]; then
  echo "Usage: validate-and-install.sh <completion-file> <command-name> [--check]"
  echo "  <completion-file>  Path to the generated bash completion script"
  echo "  <command-name>     The CLI command being completed"
  echo "  --check            Validate only, do not install"
  exit 1
fi

INSTALL_DIR="${HOME}/.local/share/bash-completion/completions"
FUNC_NAME="_$(echo "$COMMAND_NAME" | tr '-' '_')"

# ── Step 1: Check file exists ────────────────────────────────────────────
trace_step 1 "check_file_exists" 0 "file=${COMPLETION_FILE}" 2>/dev/null || true

if [[ ! -f "$COMPLETION_FILE" ]]; then
  echo "✗ Completion file not found: $COMPLETION_FILE"
  exit 1
fi
echo "✓ File exists: $COMPLETION_FILE ($(wc -l < "$COMPLETION_FILE") lines)"

# ── Step 2: Syntax validation ────────────────────────────────────────────
trace_step 2 "syntax_validation" 0 "func=${FUNC_NAME}" 2>/dev/null || true

if bash -n "$COMPLETION_FILE" 2>/dev/null; then
  echo "✓ Syntax check passed (bash -n)"
else
  echo "✗ Syntax errors detected"
  bash -n "$COMPLETION_FILE"
  exit 1
fi

# ── Step 3: Function load validation ─────────────────────────────────────
trace_step 3 "function_load" 0 "func=${FUNC_NAME}" 2>/dev/null || true

if bash -c "source '$COMPLETION_FILE' && type $FUNC_NAME >/dev/null 2>&1"; then
  echo "✓ Function $FUNC_NAME loads successfully"
else
  echo "✗ Function $FUNC_NAME not found after sourcing"
  echo "  Expected function name: $FUNC_NAME"
  echo "  Hint: bash completion functions use underscore prefix, hyphens→underscores"
  exit 1
fi

# ── Step 4: Check complete registration ──────────────────────────────────
trace_step 4 "complete_registration" 0 "command=${COMMAND_NAME}" 2>/dev/null || true

if grep -q "complete.*-F.*$FUNC_NAME.*$COMMAND_NAME" "$COMPLETION_FILE"; then
  echo "✓ complete -F registration found for $COMMAND_NAME"
else
  echo "⚠ No 'complete -F $FUNC_NAME $COMMAND_NAME' line found"
  echo "  The completion may not activate automatically"
fi

# ── Step 5: Content validation against command ───────────────────────────
trace_step 5 "content_validation" 0 "command=${COMMAND_NAME}" 2>/dev/null || true

if command -v "$COMMAND_NAME" >/dev/null 2>&1; then
  echo "✓ Command '$COMMAND_NAME' found in PATH"
  # Extract subcommands from the completion script
  subcommands=$(grep -oP "compgen -W '[^']+'" "$COMPLETION_FILE" | head -1 | sed "s/compgen -W '//;s/'//")
  if [[ -n "$subcommands" ]]; then
    word_count=$(echo "$subcommands" | wc -w)
    echo "  Completion covers ~${word_count} top-level completions"
  fi
else
  echo "⚠ Command '$COMMAND_NAME' not found in PATH — cannot validate content"
fi

# ── Step 6: Check for existing completion ────────────────────────────────
trace_step 6 "check_existing" 0 "dir=${INSTALL_DIR}" 2>/dev/null || true

EXISTING="${INSTALL_DIR}/${COMMAND_NAME}"
SYSTEM_EXISTING="/etc/bash_completion.d/${COMMAND_NAME}"

if [[ -f "$EXISTING" ]]; then
  echo "⚠ Existing user completion found: $EXISTING"
  existing_lines=$(wc -l < "$EXISTING")
  new_lines=$(wc -l < "$COMPLETION_FILE")
  echo "  Existing: ${existing_lines} lines, New: ${new_lines} lines"
elif [[ -f "$SYSTEM_EXISTING" ]]; then
  echo "ℹ System completion exists: $SYSTEM_EXISTING (user install will override)"
fi

if $CHECK_ONLY; then
  echo ""
  echo "── Check-only mode. No installation performed. ──"
  trace_end 2>/dev/null || true
  exit 0
fi

# ── Step 7: Install ──────────────────────────────────────────────────────
trace_step 7 "install" 0 "dest=${INSTALL_DIR}/${COMMAND_NAME}" 2>/dev/null || true

mkdir -p "$INSTALL_DIR"
cp "$COMPLETION_FILE" "${INSTALL_DIR}/${COMMAND_NAME}"
echo "✓ Installed to ${INSTALL_DIR}/${COMMAND_NAME}"
echo "  Completion will auto-load in new bash sessions"

trace_end 2>/dev/null || true
echo ""
echo "✅ Validation and installation complete for '$COMMAND_NAME'"
