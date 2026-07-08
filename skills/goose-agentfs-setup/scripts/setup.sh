#!/usr/bin/env bash
#
# goose-agentfs-setup — Configure Goose CONTEXT_FILE_NAMES for cross-agent compatibility
#
# Usage:
#   setup.sh [--check|--add FILE...|--remove FILE...|--all|--reset|--list|--help]
#
# Default (no flags): adds CLAUDE.md to CONTEXT_FILE_NAMES

set -euo pipefail

# --- Configuration ---
GOOSE_CONFIG="${GOOSE_CONFIG:-${HOME}/.config/goose/config.yaml}"

# Goose built-in defaults (from load_hints.rs)
DEFAULT_FILES=(.goosehints AGENTS.md)

# Known cross-agent context files
ALL_CROSS_AGENT_FILES=(CLAUDE.md .cursorrules .windsurfrules)

# Standard setup adds just CLAUDE.md (most common)
STANDARD_FILES=(CLAUDE.md)

# --- Helpers ---
info()  { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m⚠\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
Usage: setup.sh [OPTIONS]

Configure Goose CONTEXT_FILE_NAMES for cross-agent compatibility.

Options:
  (none)          Standard setup — add CLAUDE.md to context files
  --check         Show current configuration and gaps
  --add FILE...   Add specific file(s) to CONTEXT_FILE_NAMES
  --remove FILE.. Remove specific file(s) from CONTEXT_FILE_NAMES
  --all           Add all known cross-agent files (CLAUDE.md, .cursorrules, .windsurfrules)
  --reset         Reset to Goose defaults (.goosehints, AGENTS.md)
  --list          List all known cross-agent context files
  --help          Show this help

Examples:
  setup.sh                           # Add CLAUDE.md (recommended)
  setup.sh --all                     # Add all cross-agent files
  setup.sh --add CLAUDE.md RULES.md  # Add specific files
  setup.sh --remove .cursorrules     # Remove a file
  setup.sh --check                   # Diagnostic report
  setup.sh --reset                   # Restore Goose defaults
EOF
}

# --- Config reading/writing ---

# Read current CONTEXT_FILE_NAMES from config.yaml
# Returns one filename per line, or the defaults if not configured
read_current_files() {
    if [[ ! -f "$GOOSE_CONFIG" ]]; then
        printf '%s\n' "${DEFAULT_FILES[@]}"
        return
    fi

    # Try python3 + pyyaml first (most reliable)
    if python3 -c 'import yaml' 2>/dev/null; then
        local result
        result=$(python3 -c "
import yaml, sys
with open('$GOOSE_CONFIG') as f:
    cfg = yaml.safe_load(f) or {}
files = cfg.get('CONTEXT_FILE_NAMES')
if files and isinstance(files, list):
    for f in files:
        print(f)
else:
    # Not configured — return empty to signal defaults
    sys.exit(1)
" 2>/dev/null) && echo "$result" && return
    fi

    # Fallback: grep-based extraction
    if grep -q '^CONTEXT_FILE_NAMES:' "$GOOSE_CONFIG" 2>/dev/null; then
        # Read YAML list items after the key
        sed -n '/^CONTEXT_FILE_NAMES:/,/^[^ ]/{ /^  *- /{ s/^  *- *//; s/ *$//; p; } }' "$GOOSE_CONFIG"
        return
    fi

    # Not configured — use defaults
    printf '%s\n' "${DEFAULT_FILES[@]}"
}

# Write CONTEXT_FILE_NAMES to config.yaml
# Args: filenames (one per argument)
write_files() {
    local files=("$@")

    if [[ ! -f "$GOOSE_CONFIG" ]]; then
        error "Goose config not found at $GOOSE_CONFIG"
        error "Run 'goose configure' first or create the file manually."
        exit 1
    fi

    # Create backup
    local backup="${GOOSE_CONFIG}.bak.$(date +%s)"
    cp "$GOOSE_CONFIG" "$backup"

    if python3 -c 'import yaml' 2>/dev/null; then
        # Write filenames to a temp file to avoid quoting issues in heredoc
        local tmplist
        tmplist=$(mktemp)
        printf '%s\n' "${files[@]}" > "$tmplist"

        python3 - "$GOOSE_CONFIG" "$tmplist" <<'PYEOF'
import yaml, sys

config_path = sys.argv[1]
list_path = sys.argv[2]

with open(list_path) as f:
    new_files = [line.strip() for line in f if line.strip()]

with open(config_path) as f:
    cfg = yaml.safe_load(f) or {}

cfg['CONTEXT_FILE_NAMES'] = new_files

with open(config_path, 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
PYEOF
        rm -f "$tmplist"
    else
        # Fallback: sed-based approach
        # Remove existing CONTEXT_FILE_NAMES block
        sed -i '/^CONTEXT_FILE_NAMES:/,/^[^ ]/{/^CONTEXT_FILE_NAMES:/d; /^  *- /d;}' "$GOOSE_CONFIG"
        # Append new config
        {
            echo "CONTEXT_FILE_NAMES:"
            for f in "${files[@]}"; do
                echo "  - $f"
            done
        } >> "$GOOSE_CONFIG"
    fi

    info "Backup saved to $backup"
}

# --- Actions ---

do_check() {
    echo "=== Goose AgentFS Compatibility Check ==="
    echo
    echo "Config file: $GOOSE_CONFIG"
    [[ -f "$GOOSE_CONFIG" ]] && echo "Status: Found" || { echo "Status: NOT FOUND"; return; }
    echo

    echo "Current CONTEXT_FILE_NAMES:"
    local current_files
    mapfile -t current_files < <(read_current_files)
    for f in "${current_files[@]}"; do
        echo "  ✓ $f"
    done
    echo

    echo "Cross-agent compatibility:"
    local missing=0
    for cross in "${ALL_CROSS_AGENT_FILES[@]}"; do
        local found=false
        for cur in "${current_files[@]}"; do
            [[ "$cur" == "$cross" ]] && found=true && break
        done
        if $found; then
            info "$cross — configured"
        else
            warn "$cross — NOT configured"
            missing=$((missing + 1))
        fi
    done
    echo

    if [[ $missing -eq 0 ]]; then
        info "Full cross-agent compatibility configured!"
    else
        echo "Run 'setup.sh' to add CLAUDE.md, or 'setup.sh --all' for full compatibility."
    fi
    echo

    echo "Goose native skill discovery (always active, no config needed):"
    for d in '.agents/skills/' '.goose/skills/' '.claude/skills/' '~/.agents/skills/' '~/.claude/skills/'; do
        echo "  ✓ $d"
    done
}

do_add() {
    local add_files=("$@")
    [[ ${#add_files[@]} -eq 0 ]] && { error "No files specified. Use --add FILE..."; exit 1; }

    local current_files
    mapfile -t current_files < <(read_current_files)

    # Merge: current + new (dedup)
    local merged=("${current_files[@]}")
    for new_f in "${add_files[@]}"; do
        local exists=false
        for cur in "${current_files[@]}"; do
            [[ "$cur" == "$new_f" ]] && exists=true && break
        done
        if $exists; then
            warn "$new_f — already configured, skipping"
        else
            merged+=("$new_f")
            info "$new_f — adding"
        fi
    done

    write_files "${merged[@]}"
    echo
    info "CONTEXT_FILE_NAMES updated. Restart your Goose session to apply."
    echo
    echo "New configuration:"
    for f in "${merged[@]}"; do
        echo "  - $f"
    done
}

do_remove() {
    local remove_files=("$@")
    [[ ${#remove_files[@]} -eq 0 ]] && { error "No files specified. Use --remove FILE..."; exit 1; }

    local current_files
    mapfile -t current_files < <(read_current_files)

    # Filter out removed files
    local kept=()
    for cur in "${current_files[@]}"; do
        local should_remove=false
        for rm_f in "${remove_files[@]}"; do
            [[ "$cur" == "$rm_f" ]] && should_remove=true && break
        done
        if $should_remove; then
            info "$cur — removing"
        else
            kept+=("$cur")
        fi
    done

    if [[ ${#kept[@]} -eq 0 ]]; then
        error "Cannot remove all context files. At least one must remain."
        error "Use --reset to restore defaults instead."
        exit 1
    fi

    write_files "${kept[@]}"
    echo
    info "CONTEXT_FILE_NAMES updated. Restart your Goose session to apply."
    echo
    echo "New configuration:"
    for f in "${kept[@]}"; do
        echo "  - $f"
    done
}

do_all() {
    do_add "${ALL_CROSS_AGENT_FILES[@]}"
}

do_reset() {
    write_files "${DEFAULT_FILES[@]}"
    echo
    info "CONTEXT_FILE_NAMES reset to Goose defaults. Restart your session to apply."
    echo
    echo "Configuration:"
    for f in "${DEFAULT_FILES[@]}"; do
        echo "  - $f"
    done
}

do_list() {
    echo "Known cross-agent context files:"
    echo
    printf '  %-35s %s\n' "File" "Agent"
    printf '  %-35s %s\n' "----" "-----"
    printf '  %-35s %s\n' ".goosehints" "Goose (default)"
    printf '  %-35s %s\n' "AGENTS.md" "AgentFS / Goose (default)"
    printf '  %-35s %s\n' "CLAUDE.md" "Claude Code"
    printf '  %-35s %s\n' ".cursorrules" "Cursor"
    printf '  %-35s %s\n' ".windsurfrules" "Windsurf"
    printf '  %-35s %s\n' ".github/copilot-instructions.md" "GitHub Copilot (path-based, not via CONTEXT_FILE_NAMES)"
    echo
    echo "Note: .github/copilot-instructions.md uses a path-based convention that"
    echo "doesn't map to CONTEXT_FILE_NAMES. Reference it via @-import in AGENTS.md."
}

# --- Main ---

case "${1:-}" in
    --check)    do_check ;;
    --add)      shift; do_add "$@" ;;
    --remove)   shift; do_remove "$@" ;;
    --all)      do_all ;;
    --reset)    do_reset ;;
    --list)     do_list ;;
    --help|-h)  usage ;;
    "")         do_add "${STANDARD_FILES[@]}" ;;
    *)          error "Unknown option: $1"; usage; exit 1 ;;
esac
