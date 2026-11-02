#!/usr/bin/env bash
#
# activate-profile.sh — Switch agent profile by writing SOUL.md to MOIM
#
# Overwrites the AGENTFS-SOUL section in ~/.config/goose/instructions.md
# with the specified profile's SOUL.md. Takes effect on the next turn
# (MOIM re-reads the file every turn).
#
# Usage:
#   activate-profile.sh <profile>       Activate a named profile
#   activate-profile.sh default         Restore project default SOUL
#   activate-profile.sh --list          List available profiles
#   activate-profile.sh --current       Show currently active SOUL
#
# Signal: hey activate profile <name>

set -euo pipefail

MOIM_FILE="${HOME}/.config/goose/instructions.md"
SOUL_MARKER_BEGIN="<!-- AGENTFS-SOUL:BEGIN -->"
SOUL_MARKER_END="<!-- AGENTFS-SOUL:END -->"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[activate-profile]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[activate-profile]${NC} ⚠️  $*"; }
log_error() { echo -e "${RED}[activate-profile]${NC} ❌ $*"; }

# --- Find SOUL.md for a profile ---

resolve_soul_path() {
    local profile="$1"

    if [ "$profile" = "default" ]; then
        # Project default SOUL
        if [ -f "./.agents/SOUL.md" ]; then
            echo "./.agents/SOUL.md"
        else
            echo ""
        fi
    else
        # Named profile SOUL
        local path="./.agents/profiles/${profile}/SOUL.md"
        if [ -f "$path" ]; then
            echo "$path"
        else
            echo ""
        fi
    fi
}

# --- List available profiles ---

list_profiles() {
    echo ""
    echo "Available profiles:"
    echo ""

    # Default
    if [ -f "./.agents/SOUL.md" ]; then
        local default_title
        default_title=$(grep -m1 "^#" ./.agents/SOUL.md 2>/dev/null | sed 's/^# *//')
        echo -e "  ${CYAN}default${NC}  — ${default_title:-Project default}"
    fi

    # Named profiles
    if [ -d "./.agents/profiles" ]; then
        for dir in ./.agents/profiles/*/; do
            [ -d "$dir" ] || continue
            local name
            name=$(basename "$dir")
            local soul_path="${dir}SOUL.md"
            if [ -f "$soul_path" ]; then
                local title
                title=$(grep -m1 "^#" "$soul_path" 2>/dev/null | sed 's/^# *//')
                echo -e "  ${CYAN}${name}${NC}  — ${title:-No title}"
            else
                echo -e "  ${YELLOW}${name}${NC}  — (no SOUL.md)"
            fi
        done
    fi

    echo ""
}

# --- Show current SOUL ---

show_current() {
    if [ ! -f "$MOIM_FILE" ]; then
        log_info "No MOIM file — no SOUL active"
        return
    fi

    if ! grep -qF "$SOUL_MARKER_BEGIN" "$MOIM_FILE"; then
        log_info "No AGENTFS-SOUL section in MOIM"
        return
    fi

    # Extract current SOUL title
    local title
    title=$(awk -v begin="$SOUL_MARKER_BEGIN" -v end="$SOUL_MARKER_END" '
        $0 == begin { capture=1; next }
        $0 == end   { capture=0 }
        capture && /^# / { print; exit }
    ' "$MOIM_FILE" | sed 's/^# *//')

    if [ -n "$title" ]; then
        log_info "Current SOUL: ${title}"
    else
        log_info "SOUL section present but no title found"
    fi
}

# --- Write SOUL to MOIM ---

write_soul() {
    local soul_path="$1"
    local soul_content
    soul_content=$(cat "$soul_path")

    if [ ! -f "$MOIM_FILE" ]; then
        # Create new file
        {
            echo "$SOUL_MARKER_BEGIN"
            echo "$soul_content"
            echo "$SOUL_MARKER_END"
        } > "$MOIM_FILE"
        return
    fi

    if grep -qF "$SOUL_MARKER_BEGIN" "$MOIM_FILE"; then
        # Replace existing section
        local tmpfile
        tmpfile=$(mktemp)
        awk -v begin="$SOUL_MARKER_BEGIN" -v end="$SOUL_MARKER_END" -v content="$soul_content" '
            $0 == begin { print; print content; skip=1; next }
            $0 == end   { print; skip=0; next }
            !skip       { print }
        ' "$MOIM_FILE" > "$tmpfile"
        mv "$tmpfile" "$MOIM_FILE"
    else
        # Append new section
        {
            echo ""
            echo "$SOUL_MARKER_BEGIN"
            echo "$soul_content"
            echo "$SOUL_MARKER_END"
        } >> "$MOIM_FILE"
    fi
}

# --- Main ---

profile="${1:-}"

case "$profile" in
    --list|-l)
        list_profiles
        exit 0
        ;;
    --current|-c)
        show_current
        exit 0
        ;;
    --help|-h)
        echo "Usage: activate-profile.sh <profile|default|--list|--current>"
        echo ""
        echo "  <profile>   Activate named profile (reads .agents/profiles/<name>/SOUL.md)"
        echo "  default     Restore project default SOUL (.agents/SOUL.md)"
        echo "  --list      List available profiles"
        echo "  --current   Show currently active SOUL"
        exit 0
        ;;
    "")
        log_error "Profile name required"
        echo ""
        echo "Usage: activate-profile.sh <profile|default|--list|--current>"
        list_profiles
        exit 1
        ;;
esac

# Resolve SOUL.md path
soul_path=$(resolve_soul_path "$profile")

if [ -z "$soul_path" ]; then
    log_error "Profile not found: ${profile}"
    list_profiles
    exit 1
fi

# Write to MOIM
write_soul "$soul_path"

# Report
local_title=$(grep -m1 "^#" "$soul_path" 2>/dev/null | sed 's/^# *//')
log_info "Activated: ${profile} (${local_title:-no title})"
log_info "Takes effect on next turn (MOIM re-reads every turn)"

# Warn about multi-session impact
log_warn "This affects ALL active Goose sessions (instructions.md is global)"
