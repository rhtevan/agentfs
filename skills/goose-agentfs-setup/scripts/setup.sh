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

Configure Goose CONTEXT_FILE_NAMES for cross-agent compatibility
and manage AgentFS memory collision avoidance.

Context File Options:
  (none)            Standard setup — add CLAUDE.md to context files
  --check           Show current configuration and gaps
  --add FILE...     Add specific file(s) to CONTEXT_FILE_NAMES
  --remove FILE..   Remove specific file(s) from CONTEXT_FILE_NAMES
  --all             Add all known cross-agent files
  --reset           Reset to Goose defaults (.goosehints, AGENTS.md)
  --list            List all known cross-agent context files

Knowledge Discovery (Global Goosehints):
  --hints-check     Check if global .goosehints has knowledge index reference
  --hints-install   Install/update knowledge index reference in global .goosehints
  --hints-remove    Remove knowledge index reference from global .goosehints

Memory Collision Avoidance:
  --memory-check    Check if memory routing override is installed
  --memory-install  Install/update memory routing override in persistent instructions
  --memory-remove   Remove memory routing override from persistent instructions

  --help            Show this help

Examples:
  setup.sh                           # Add CLAUDE.md (recommended)
  setup.sh --all                     # Add all cross-agent files
  setup.sh --add CLAUDE.md RULES.md  # Add specific files
  setup.sh --remove .cursorrules     # Remove a file
  setup.sh --check                   # Diagnostic report
  setup.sh --reset                   # Restore Goose defaults
  setup.sh --hints-check             # Check knowledge discovery setup
  setup.sh --hints-install           # Install knowledge index in global hints
  setup.sh --hints-remove            # Remove knowledge index from global hints
  setup.sh --memory-check            # Check memory override status
  setup.sh --memory-install          # Install memory collision avoidance
  setup.sh --memory-remove           # Remove memory collision avoidance
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

# --- Global Goosehints for Knowledge Discovery ---

GOOSE_GLOBAL_HINTS="${HOME}/.config/goose/.goosehints"
KNOWLEDGE_INDEX_REF="Knowledge index: ~/.agents/knowledge/index.md"
KNOWLEDGE_MARKER_START="## Knowledge Base"

do_hints_check() {
    echo "=== Global Goosehints Check ==="
    echo
    echo "Global hints file: $GOOSE_GLOBAL_HINTS"
    if [[ ! -f "$GOOSE_GLOBAL_HINTS" ]]; then
        warn "Global .goosehints does not exist"
        echo "Run 'setup.sh --hints-install' to create it."
        return
    fi

    info "Global .goosehints exists"
    echo

    if grep -qF "$KNOWLEDGE_INDEX_REF" "$GOOSE_GLOBAL_HINTS"; then
        info "Knowledge index reference is present"
    else
        warn "Knowledge index reference is NOT present"
        echo "Run 'setup.sh --hints-install' to add it."
    fi
    echo

    if [[ -f "$HOME/.agents/knowledge/index.md" ]]; then
        info "Knowledge index file exists at ~/.agents/knowledge/index.md"
    else
        warn "Knowledge index file not found at ~/.agents/knowledge/index.md"
        echo "  Run okf-bundle-gen or okf-bundle-harvest to create knowledge bundles."
    fi
}

do_hints_install() {
    mkdir -p "$(dirname "$GOOSE_GLOBAL_HINTS")"

    if [[ ! -f "$GOOSE_GLOBAL_HINTS" ]]; then
        cat > "$GOOSE_GLOBAL_HINTS" << 'EOF'
# Global Goose Hints

## Knowledge Base

Knowledge index: ~/.agents/knowledge/index.md
EOF
        info "Created $GOOSE_GLOBAL_HINTS with knowledge index reference."
    elif grep -qF "$KNOWLEDGE_INDEX_REF" "$GOOSE_GLOBAL_HINTS"; then
        info "Knowledge index reference already present in $GOOSE_GLOBAL_HINTS"
    elif grep -qF "$KNOWLEDGE_MARKER_START" "$GOOSE_GLOBAL_HINTS"; then
        # Section exists but reference is different — update it
        local tmpfile
        tmpfile=$(mktemp)
        python3 - "$GOOSE_GLOBAL_HINTS" "$tmpfile" <<'PYEOF'
import sys

src = sys.argv[1]
dst = sys.argv[2]
marker = "## Knowledge Base"
ref_line = "Knowledge index: ~/.agents/knowledge/index.md"

with open(src) as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    new_lines.append(lines[i])
    if lines[i].strip() == marker:
        # Skip old content until next heading or end
        i += 1
        while i < len(lines) and not lines[i].startswith('#'):
            i += 1
        new_lines.append('\n')
        new_lines.append(ref_line + '\n')
        new_lines.append('\n')
        continue
    i += 1

with open(dst, 'w') as f:
    f.writelines(new_lines)
PYEOF
        cp "$tmpfile" "$GOOSE_GLOBAL_HINTS"
        rm -f "$tmpfile"
        info "Updated knowledge index reference in $GOOSE_GLOBAL_HINTS"
    else
        # Append new section
        echo -e "\n## Knowledge Base\n\n$KNOWLEDGE_INDEX_REF" >> "$GOOSE_GLOBAL_HINTS"
        info "Appended knowledge index reference to $GOOSE_GLOBAL_HINTS"
    fi
    echo
    info "Knowledge discovery configured. Restart your Goose session to apply."
}

do_hints_remove() {
    if [[ ! -f "$GOOSE_GLOBAL_HINTS" ]]; then
        warn "No global .goosehints file found at $GOOSE_GLOBAL_HINTS"
        return
    fi

    if ! grep -qF "$KNOWLEDGE_INDEX_REF" "$GOOSE_GLOBAL_HINTS" && \
       ! grep -qF "$KNOWLEDGE_MARKER_START" "$GOOSE_GLOBAL_HINTS"; then
        warn "No knowledge index reference found in $GOOSE_GLOBAL_HINTS"
        return
    fi

    local tmpfile
    tmpfile=$(mktemp)
    python3 - "$GOOSE_GLOBAL_HINTS" "$tmpfile" <<'PYEOF'
import sys

src = sys.argv[1]
dst = sys.argv[2]
marker = "## Knowledge Base"

with open(src) as f:
    content = f.read()

idx = content.find(marker)
if idx < 0:
    with open(dst, 'w') as f:
        f.write(content)
else:
    before = content[:idx].rstrip()
    # Find next heading after the marker
    rest = content[idx + len(marker):]
    next_heading = -1
    for i, ch in enumerate(rest):
        if ch == '#' and (i == 0 or rest[i-1] == '\n'):
            next_heading = i
            break
    if next_heading >= 0:
        after = rest[next_heading:].lstrip()
        result = before + '\n\n' + after if before else after
    else:
        result = before
    with open(dst, 'w') as f:
        f.write(result.strip() + '\n')
PYEOF
    cp "$tmpfile" "$GOOSE_GLOBAL_HINTS"
    rm -f "$tmpfile"

    # Remove file if empty
    if [[ ! -s "$GOOSE_GLOBAL_HINTS" ]] || [[ "$(cat "$GOOSE_GLOBAL_HINTS" | tr -d '[:space:]')" == "" ]]; then
        rm -f "$GOOSE_GLOBAL_HINTS"
        info "Removed empty $GOOSE_GLOBAL_HINTS"
    else
        info "Removed knowledge index reference from $GOOSE_GLOBAL_HINTS"
    fi
    echo
    info "Restart your Goose session to apply."
}

# --- Memory Collision Avoidance ---

# The persistent instructions block that prevents the Goose memory extension
# from hijacking AgentFS natural-language memory signals.
MEMORY_MARKER_START="## Memory Routing Override (AgentFS)"
MEMORY_MARKER_END="## End Memory Routing Override"

MEMORY_INSTRUCTIONS='## Memory Routing Override (AgentFS)

This section defines Goose-specific memory signal routing. It OVERRIDES the
agent-agnostic decision table in AGENTS.md Guardrail #9 when a matching tool
exists in the current session.

### Runtime Resolution Rule

This table is STATIC — it lists all possible routes regardless of which
extensions are currently enabled. Resolve dynamically at runtime:

1. For each matching signal, check the "Tool to Check" column
2. If that tool EXISTS in your current available tools list, use it
3. If the tool DOES NOT exist (extension disabled), skip that row and
   try the next priority
4. If NO Goose-specific tool matches, fall through to AGENTS.md
   Guardrail #9 (Memory Signal Routing)

Tool existence = extension enabled. Goose only injects tools into the
session when their parent extension is active.

### Goose Memory Signal Decision Table

| Pri | Signal / Keyword | Intent | Tool to Check | Route To (Tool Call) | Extension |
|---|---|---|---|---|---|
| 1 | "remember this document", "learn this", "ingest this", "add to knowledge" | Knowledge graph ingestion | cognee__remember | cognee__remember(data, dataset_name) | Cognee |
| 1 | "remember for this session only", "session note" | Session-scoped fast cache | cognee__remember | cognee__remember(data, session_id) | Cognee |
| 1 | "remember this", "note that", "save this", "keep in mind" | Store persistent memory (fact/observation) | cognee__remember | cognee__remember(data, dataset_name) | Cognee |
| 1 | "what do you know about X", "what connections exist", "search knowledge" | Knowledge graph query | cognee__recall | cognee__recall(query) | Cognee |
| 1 | "forget dataset", "clear knowledge base" | Delete knowledge graph data | cognee__forget | cognee__forget(dataset) | Cognee |
| 1 | "forget this", "remove that note" | Remove specific memory | cognee__forget | cognee__forget(dataset) | Cognee |
| 2 | "remember this", "note that", "save this", "keep in mind" | Store persistent memory | memory__remember_memory | memory__remember_memory(category, data, tags, is_global) | Memory |
| 2 | "retrieve my notes about", "what did I save about" | Retrieve stored memories | memory__retrieve_memories | memory__retrieve_memories(category, is_global) | Memory |
| 2 | "forget this memory", "remove memory about" | Remove specific memory | memory__remove_specific_memory | memory__remove_specific_memory(category, content, is_global) | Memory |
| 2 | "forget all memories", "clear all notes" | Bulk memory delete | memory__remove_memory_category | memory__remove_memory_category(category="*", is_global) | Memory |
| 3 | "what did we discuss", "last time we talked about", "previous session" | Past conversation search | chatrecall | chatrecall(query) | Chat Recall |
| 3 | "load session", "show me session X" | Session summary | chatrecall | chatrecall(session_id) | Chat Recall |

### Priority Rationale

| Priority | Extension | Rationale |
|---|---|---|
| 1 (highest) | Cognee | Knowledge graph with semantic search — subsumes Memory when enabled |
| 2 | Memory | Simple persistent .txt storage — fallback when Cognee unavailable |
| 3 | Chat Recall | Past session search — unique capability, no storage overlap |

When Cognee is enabled, it effectively renders the Memory extension redundant
for storage signals. This is intentional — Cognee provides a superset of
Memory capabilities. Users who enable Cognee should consider disabling Memory.

### Which MEMORY.md to use (AGENTS.md fallthrough)

When no Goose-specific tool matches and signals fall through to AGENTS.md:
- Default agent: ./.agents/memories/MEMORY.md
- Named profile (subagent): ./.agents/profiles/<name>/memories/MEMORY.md
- If operating as a subagent under a named profile, ALWAYS use that profile MEMORY.md

### Ambiguity Resolution

When "forget" intent is ambiguous and lacks a clear object (dataset, memory,
note), ask the user: "Do you want me to forget a specific saved memory,
clear a knowledge base dataset, or just disregard what was just said?"

When routing a memory signal, briefly state which system you are routing to
and why (e.g., "Routing to Cognee remember because cognee__remember is
available") before executing.

### Session bridge pattern

The primary legitimate use of the Goose memory extension alongside AgentFS is as
a session bridge: temporarily stash critical context so it survives into a new
session, then at session start, retrieve the stashed content and commit it to
the appropriate MEMORY.md file. After committing, clear the stashed entries from
the Goose memory store.

## End Memory Routing Override'

GOOSE_INSTRUCTIONS="${GOOSE_MOIM_MESSAGE_FILE:-${HOME}/.config/goose/instructions.md}"

do_memory_check() {
    echo "=== Memory Collision Avoidance Check ==="
    echo
    echo "Instructions file: $GOOSE_INSTRUCTIONS"
    if [[ ! -f "$GOOSE_INSTRUCTIONS" ]]; then
        echo "Status: NOT FOUND"
        echo
        warn "No persistent instructions file. Run 'setup.sh --memory-install' to create."
        return
    fi

    if grep -qF "$MEMORY_MARKER_START" "$GOOSE_INSTRUCTIONS"; then
        info "Memory routing override is INSTALLED"
    else
        warn "Memory routing override is NOT installed"
        echo "Run 'setup.sh --memory-install' to add it."
    fi
    echo

    # Check if memory extension is enabled
    if grep -A2 'memory:' "$GOOSE_CONFIG" 2>/dev/null | grep -q 'enabled: true'; then
        warn "Goose memory extension is ENABLED — collision risk exists"
        echo "  The routing override in persistent instructions will redirect"
        echo "  natural-language signals to AgentFS MEMORY.md."
    else
        info "Goose memory extension is DISABLED — no collision risk"
    fi
}

do_memory_install() {
    if [[ ! -f "$GOOSE_INSTRUCTIONS" ]]; then
        # Create the file with the override block
        mkdir -p "$(dirname "$GOOSE_INSTRUCTIONS")"
        echo -e "$MEMORY_INSTRUCTIONS" > "$GOOSE_INSTRUCTIONS"
        info "Created $GOOSE_INSTRUCTIONS with memory routing override."
    elif grep -qF "$MEMORY_MARKER_START" "$GOOSE_INSTRUCTIONS"; then
        # Replace existing block
        local tmpfile
        tmpfile=$(mktemp)
        python3 - "$GOOSE_INSTRUCTIONS" "$tmpfile" <<'PYEOF'
import sys

src = sys.argv[1]
dst = sys.argv[2]
start_marker = "## Memory Routing Override (AgentFS)"
end_marker = "## End Memory Routing Override"

with open(src) as f:
    content = f.read()

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)
if start_idx >= 0 and end_idx >= 0:
    end_idx = end_idx + len(end_marker)
    # Preserve content before and after
    before = content[:start_idx].rstrip()
    after = content[end_idx:].lstrip()
    with open(dst, 'w') as f:
        f.write(before)
    # Signal to caller to append new block + after content
    with open(dst + '.after', 'w') as f:
        f.write(after)
else:
    # No markers found, write original
    with open(dst, 'w') as f:
        f.write(content)
PYEOF
        if [[ -f "${tmpfile}.after" ]]; then
            local after_content
            after_content=$(cat "${tmpfile}.after")
            {
                cat "$tmpfile"
                [[ -s "$tmpfile" ]] && echo -e "\n"
                echo -e "$MEMORY_INSTRUCTIONS"
                [[ -n "$after_content" ]] && echo -e "\n$after_content"
            } > "$GOOSE_INSTRUCTIONS"
            rm -f "$tmpfile" "${tmpfile}.after"
        else
            rm -f "$tmpfile"
        fi
        info "Updated memory routing override in $GOOSE_INSTRUCTIONS"
    else
        # Append to existing file
        echo -e "\n\n$MEMORY_INSTRUCTIONS" >> "$GOOSE_INSTRUCTIONS"
        info "Appended memory routing override to $GOOSE_INSTRUCTIONS"
    fi
    echo
    info "Memory collision avoidance installed. Restart your Goose session to apply."
}

do_memory_remove() {
    if [[ ! -f "$GOOSE_INSTRUCTIONS" ]]; then
        warn "No persistent instructions file found at $GOOSE_INSTRUCTIONS"
        return
    fi

    if ! grep -qF "$MEMORY_MARKER_START" "$GOOSE_INSTRUCTIONS"; then
        warn "No memory routing override found in $GOOSE_INSTRUCTIONS"
        return
    fi

    local tmpfile
    tmpfile=$(mktemp)
    python3 - "$GOOSE_INSTRUCTIONS" "$tmpfile" <<'PYEOF'
import sys

src = sys.argv[1]
dst = sys.argv[2]
start_marker = "## Memory Routing Override (AgentFS)"
end_marker = "## End Memory Routing Override"

with open(src) as f:
    content = f.read()

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)
if start_idx >= 0 and end_idx >= 0:
    end_idx = end_idx + len(end_marker)
    before = content[:start_idx].rstrip()
    after = content[end_idx:].lstrip()
    result = before
    if after:
        result = result + "\n\n" + after if result else after
    with open(dst, 'w') as f:
        f.write(result.strip() + "\n")
else:
    with open(dst, 'w') as f:
        f.write(content)
PYEOF
    cp "$tmpfile" "$GOOSE_INSTRUCTIONS"
    rm -f "$tmpfile"
    info "Removed memory routing override from $GOOSE_INSTRUCTIONS"
    echo
    info "Restart your Goose session to apply."
}

# --- Main ---

case "${1:-}" in
    --check)           do_check ;;
    --add)             shift; do_add "$@" ;;
    --remove)          shift; do_remove "$@" ;;
    --all)             do_all ;;
    --reset)           do_reset ;;
    --list)            do_list ;;
    --hints-check)    do_hints_check ;;
    --hints-install)   do_hints_install ;;
    --hints-remove)    do_hints_remove ;;
    --memory-check)    do_memory_check ;;
    --memory-install)  do_memory_install ;;
    --memory-remove)   do_memory_remove ;;
    --help|-h)         usage ;;
    "")                do_add "${STANDARD_FILES[@]}" ;;
    *)                 error "Unknown option: $1"; usage; exit 1 ;;
esac
