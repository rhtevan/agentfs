#!/usr/bin/env bash
#
# system-md-gen.sh — Generate custom Goose system.md with AGENTS.md at primacy zone
#
# Injects AGENTS.md content into Goose's system.md template, positioning it
# at the primacy zone (after identity, before extensions) for improved
# attention with weaker models. Also writes SOUL.md into MOIM persistent
# instructions for recency-peak reinforcement.
#
# Usage:
#   system-md-gen.sh [--check|--generate|--drift-check|--reset]
#
# Sync signal: hey sync goose agentfs
#
# Architecture:
#   Layer 1: Custom system.md  → primacy zone (system role)
#   Layer 3: AGENTS.md on disk → dead zone fallback (agent-agnostic)
#   SOUL.md: MOIM instructions → recency peak (user role, per-turn)

set -euo pipefail

# --- Paths ---
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR="${SKILL_DIR}/artifacts"
BASE_TEMPLATE="${ARTIFACTS_DIR}/system.md.base"
BASE_META="${ARTIFACTS_DIR}/system.md.base.meta"
CUSTOM_SYSTEM_MD="${HOME}/.config/goose/prompts/system.md"
MOIM_FILE="${HOME}/.config/goose/instructions.md"
GOOSE_CONFIG="${HOME}/.config/goose/config.yaml"

# --- Injection markers (Jinja2 comments — invisible in rendered output) ---
MARKER_BEGIN="{# AGENTFS:BEGIN #}"
MARKER_END="{# AGENTFS:END #}"
SOUL_MARKER_BEGIN="<!-- AGENTFS-SOUL:BEGIN -->"
SOUL_MARKER_END="<!-- AGENTFS-SOUL:END -->"

# --- GitHub URL pattern for fetching default templates by tag ---
GITHUB_RAW_URL="https://raw.githubusercontent.com/aaif-goose/goose/refs/tags"
SYSTEM_MD_PATH="crates/goose/src/prompts/system.md"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[system-md-gen]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[system-md-gen]${NC} ⚠️  $*"; }
log_error() { echo -e "${RED}[system-md-gen]${NC} ❌ $*"; }

# --- Helpers ---

get_installed_version() {
    goose --version 2>/dev/null | tr -d ' ' || echo "unknown"
}

get_pinned_version() {
    grep "^goose_version:" "$BASE_META" 2>/dev/null | awk '{print $2}' || echo "unknown"
}

get_pinned_sha256() {
    grep "^sha256:" "$BASE_META" 2>/dev/null | awk '{print $2}' || echo ""
}

fetch_default_template() {
    local version="$1"
    curl -sf --max-time 15 \
        "${GITHUB_RAW_URL}/v${version}/${SYSTEM_MD_PATH}" 2>/dev/null
}

find_agents_md() {
    # Search CWD for AGENTS.md (same as where Goose would find it)
    if [ -f "./AGENTS.md" ]; then
        echo "./AGENTS.md"
    else
        echo ""
    fi
}

find_soul_md() {
    # Search CWD for .agents/SOUL.md
    if [ -f "./.agents/SOUL.md" ]; then
        echo "./.agents/SOUL.md"
    else
        echo ""
    fi
}

# --- Drift Check ---

drift_check() {
    local installed pinned
    installed=$(get_installed_version)
    pinned=$(get_pinned_version)

    if [ "$installed" = "unknown" ]; then
        log_warn "Could not detect installed Goose version"
        return 0
    fi

    if [ "$installed" = "$pinned" ]; then
        log_info "Base template matches Goose v${installed} ✅"
        return 0
    fi

    log_warn "Version mismatch: pinned v${pinned}, installed v${installed}"

    # Fetch new default
    local new_default
    new_default=$(fetch_default_template "$installed")

    if [ -z "$new_default" ]; then
        log_warn "Could not fetch default template for v${installed} — continuing with pinned base"
        return 0
    fi

    # Compare against pinned base
    local current_base
    current_base=$(cat "$BASE_TEMPLATE")

    if [ "$new_default" = "$current_base" ]; then
        log_info "Template content unchanged between v${pinned} and v${installed}"
        # Update version in meta only
        update_meta "$installed"
        return 0
    fi

    # Content differs — check if injection point is intact
    local identity_line="goose is being developed as an open-source software project."
    local moim_line="{% if moim_system_prompt_block is defined %}"

    if echo "$new_default" | grep -qF "$identity_line" && \
       echo "$new_default" | grep -qF "$moim_line"; then
        log_info "Injection point intact — auto-updating base to v${installed}"
        echo "$new_default" > "$BASE_TEMPLATE"
        update_meta "$installed"
        return 0
    else
        log_error "STRUCTURAL CHANGE in Goose v${installed} system.md"
        log_error "Injection point (identity lines or MOIM block) has changed."
        log_error "Manual review required. Diff:"
        diff "$BASE_TEMPLATE" <(echo "$new_default") || true
        return 1
    fi
}

update_meta() {
    local version="$1"
    local sha256
    sha256=$(sha256sum "$BASE_TEMPLATE" | cut -d' ' -f1)
    cat > "$BASE_META" << EOF
goose_version: ${version}
pinned_date: $(date +%Y-%m-%d)
source_url: ${GITHUB_RAW_URL}/v${version}/${SYSTEM_MD_PATH}
sha256: ${sha256}
EOF
}

# --- Generate Custom system.md ---

generate_system_md() {
    local agents_md_path soul_md_path

    agents_md_path=$(find_agents_md)
    if [ -z "$agents_md_path" ]; then
        log_error "No AGENTS.md found in CWD ($(pwd))"
        return 1
    fi

    soul_md_path=$(find_soul_md)

    # Read base template
    if [ ! -f "$BASE_TEMPLATE" ]; then
        log_error "Base template not found: ${BASE_TEMPLATE}"
        return 1
    fi
    local base
    base=$(cat "$BASE_TEMPLATE")

    # Read AGENTS.md content as-is
    # SOUL.md read instruction kept (belt-and-suspenders with MOIM delivery)
    local agents_content
    agents_content=$(cat "$agents_md_path")

    # Split base at injection point: after identity, before MOIM block
    local identity_end="goose is being developed as an open-source software project."
    local moim_start="{% if moim_system_prompt_block is defined %}"

    # Build custom template
    local before_injection after_injection
    before_injection=$(echo "$base" | sed -n "1,/${identity_end}/p")
    after_injection=$(echo "$base" | sed -n "/${moim_start}/,\$p")

    # Ensure prompts directory exists
    mkdir -p "$(dirname "$CUSTOM_SYSTEM_MD")"

    # Write custom system.md
    {
        echo "$before_injection"
        echo ""
        echo "$MARKER_BEGIN"
        echo "$agents_content"
        echo "$MARKER_END"
        echo ""
        echo "$after_injection"
    } > "$CUSTOM_SYSTEM_MD"

    log_info "Generated ${CUSTOM_SYSTEM_MD}"
    log_info "  AGENTS.md: ${agents_md_path} ($(wc -c < "$agents_md_path") bytes)"
    log_info "  Base: Goose v$(get_pinned_version)"

    # Write SOUL.md to MOIM (with overwrite protection)
    if [ -n "$soul_md_path" ]; then
        # Check if a non-default profile is currently active
        if [ -f "$MOIM_FILE" ] && grep -qF "$SOUL_MARKER_BEGIN" "$MOIM_FILE"; then
            local current_title
            current_title=$(awk -v begin="$SOUL_MARKER_BEGIN" -v end="$SOUL_MARKER_END" '
                $0 == begin { capture=1; next }
                $0 == end   { capture=0 }
                capture && /^# / { print; exit }
            ' "$MOIM_FILE" | sed 's/^# *//')
            local default_title
            default_title=$(grep -m1 "^#" "$soul_md_path" 2>/dev/null | sed 's/^# *//')

            if [ -n "$current_title" ] && [ "$current_title" != "$default_title" ]; then
                log_warn "Non-default profile active: '${current_title}'"
                log_warn "Overwriting with default: '${default_title}'"
                log_warn "Re-activate profile after sync if needed"
            fi
        fi
        write_soul_to_moim "$soul_md_path"
    else
        log_warn "No .agents/SOUL.md found — MOIM SOUL section not updated"
    fi
}

# --- Write SOUL.md to MOIM persistent instructions ---

write_soul_to_moim() {
    local soul_path="$1"
    local soul_content
    soul_content=$(cat "$soul_path")

    if [ ! -f "$MOIM_FILE" ]; then
        # Create new file with just the SOUL section
        {
            echo "$SOUL_MARKER_BEGIN"
            echo "$soul_content"
            echo "$SOUL_MARKER_END"
        } > "$MOIM_FILE"
        log_info "Created ${MOIM_FILE} with SOUL.md content"
        return
    fi

    # File exists — update or insert marked section
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
        log_info "Updated SOUL section in ${MOIM_FILE}"
    else
        # Append new section
        {
            echo ""
            echo "$SOUL_MARKER_BEGIN"
            echo "$soul_content"
            echo "$SOUL_MARKER_END"
        } >> "$MOIM_FILE"
        log_info "Appended SOUL section to ${MOIM_FILE}"
    fi
}

# --- Check ---

check_status() {
    echo ""
    echo "=== Goose AgentFS System Prompt Status ==="
    echo ""

    # Custom system.md
    if [ -f "$CUSTOM_SYSTEM_MD" ]; then
        if grep -qF "$MARKER_BEGIN" "$CUSTOM_SYSTEM_MD"; then
            log_info "Custom system.md: ACTIVE ($(wc -c < "$CUSTOM_SYSTEM_MD") bytes)"
        else
            log_warn "Custom system.md exists but has no AGENTFS injection markers"
        fi
    else
        log_info "Custom system.md: not installed (using Goose default)"
    fi

    # Base template
    if [ -f "$BASE_TEMPLATE" ]; then
        log_info "Pinned base: Goose v$(get_pinned_version)"
    else
        log_warn "No pinned base template found"
    fi

    # Installed Goose version
    local installed
    installed=$(get_installed_version)
    log_info "Installed Goose: v${installed}"

    # Drift
    local pinned
    pinned=$(get_pinned_version)
    if [ "$installed" != "$pinned" ] && [ "$installed" != "unknown" ]; then
        log_warn "Version drift: pinned v${pinned} ≠ installed v${installed}"
    fi

    # MOIM SOUL
    if [ -f "$MOIM_FILE" ] && grep -qF "$SOUL_MARKER_BEGIN" "$MOIM_FILE"; then
        log_info "MOIM SOUL section: present"
    else
        log_info "MOIM SOUL section: not installed"
    fi

    # CONTEXT_FILE_NAMES
    if [ -f "$GOOSE_CONFIG" ]; then
        if grep -q "AGENTS.md" "$GOOSE_CONFIG" 2>/dev/null; then
            local in_context
            in_context=$(python3 -c "
import yaml
with open('$GOOSE_CONFIG') as f:
    cfg = yaml.safe_load(f)
names = cfg.get('CONTEXT_FILE_NAMES', [])
print('yes' if 'AGENTS.md' in names else 'no')
" 2>/dev/null || echo "unknown")
            if [ "$in_context" = "yes" ]; then
                log_warn "AGENTS.md still in CONTEXT_FILE_NAMES (will double-load)"
            fi
        fi
    fi

    echo ""
}

# --- Reset ---

reset_system_md() {
    if [ -f "$CUSTOM_SYSTEM_MD" ]; then
        rm "$CUSTOM_SYSTEM_MD"
        log_info "Removed custom system.md — Goose will use built-in default"
    else
        log_info "No custom system.md to remove"
    fi
}

# --- Main ---

case "${1:-}" in
    --check)
        check_status
        ;;
    --drift-check)
        drift_check
        ;;
    --generate)
        drift_check && generate_system_md
        ;;
    --reset)
        reset_system_md
        ;;
    "")
        # Default: full sync (drift check + generate)
        drift_check && generate_system_md
        ;;
    *)
        echo "Usage: system-md-gen.sh [--check|--generate|--drift-check|--reset]"
        exit 1
        ;;
esac
