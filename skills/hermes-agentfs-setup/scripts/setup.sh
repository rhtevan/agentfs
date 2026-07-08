#!/usr/bin/env bash
# hermes-agentfs-setup — Configure Hermes Agent for AgentFS compatibility
#
# Makes Hermes discover AgentFS skills by adding skill directories to
# skills.external_dirs in ~/.hermes/config.yaml.
#
# Two scopes:
#   USER    — ~/.agents/skills  (shared across all projects)
#   PROJECT — $PWD/.agents/skills  (per-project, registered by absolute path)
#
# Usage:
#   bash setup.sh                  # USER scope setup
#   bash setup.sh --project        # Register current project's .agents/skills/
#   bash setup.sh --project /path  # Register a specific project's .agents/skills/
#   bash setup.sh --check          # Check all compatibility
#   bash setup.sh --undo           # Remove USER entry
#   bash setup.sh --undo-project   # Remove current project entry
#   bash setup.sh --undo-project /path  # Remove a specific project entry

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CONFIG="$HERMES_HOME/config.yaml"
AGENTS_SKILLS_USER="~/.agents/skills"
AGENTS_SKILLS_USER_EXPANDED="$HOME/.agents/skills"

# ── Colors ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
fail() { printf "${RED}✗${NC} %s\n" "$1"; }
info() { printf "${CYAN}ℹ${NC} %s\n" "$1"; }
hdr()  { printf "\n${BOLD}%s${NC}\n%s\n\n" "$1" "$(printf '=%.0s' $(seq 1 ${#1}))"; }

# ── Helpers ───────────────────────────────────────────────────────────────

config_exists() {
  [[ -f "$CONFIG" ]]
}

has_skills_section() {
  grep -q '^skills:' "$CONFIG" 2>/dev/null
}

has_external_dirs() {
  grep -q 'external_dirs:' "$CONFIG" 2>/dev/null
}

# Check if a specific path is already in external_dirs
path_in_external_dirs() {
  local check_path="$1"
  grep -A 50 'external_dirs:' "$CONFIG" 2>/dev/null \
    | sed '/^[^ ]/q' \
    | grep -qF "$check_path"
}

has_system_entry() {
  path_in_external_dirs "$AGENTS_SKILLS_USER" \
    || path_in_external_dirs "$AGENTS_SKILLS_USER_EXPANDED"
}

# Count skills in a directory
count_skills() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l
  else
    echo 0
  fi
}

# List all PROJECT paths currently in external_dirs (non-system entries)
list_project_entries() {
  if ! has_external_dirs; then return; fi
  grep -A 50 'external_dirs:' "$CONFIG" 2>/dev/null \
    | grep '^\s*-' \
    | sed 's/^\s*-\s*//' \
    | while IFS= read -r entry; do
        # Skip the USER entry
        if [[ "$entry" == "~/.agents/skills" ]] || [[ "$entry" == "$AGENTS_SKILLS_USER_EXPANDED" ]]; then
          continue
        fi
        # Only show entries that look like .agents/skills paths
        if [[ "$entry" == *".agents/skills"* ]]; then
          echo "$entry"
        fi
      done
}

# ── Config manipulation (Python for safe YAML handling) ───────────────────

add_external_dir() {
  local new_path="$1"
  local backup="${CONFIG}.agentfs-backup.$(date '+%Y%m%d-%H%M%S')"
  cp "$CONFIG" "$backup"
  info "Config backup: $backup"

  python3 << PYEOF
import sys

config_path = '$CONFIG'
new_entry = '    - $new_path'

with open(config_path, 'r') as f:
    lines = f.readlines()

# Check if already present
for line in lines:
    if '$new_path' in line and line.strip().startswith('- '):
        print('ALREADY_PRESENT')
        sys.exit(0)

# Find the skills: section
in_skills = False
has_external_dirs = False
insert_idx = None

for i, line in enumerate(lines):
    stripped = line.rstrip()

    # Detect skills: section
    if stripped == 'skills:':
        in_skills = True
        continue

    # If we're in skills: and hit another top-level key, stop
    if in_skills and stripped and not stripped[0].isspace():
        # No external_dirs found — insert before this line
        if not has_external_dirs:
            insert_idx = i
        in_skills = False
        break

    if in_skills and 'external_dirs:' in stripped:
        has_external_dirs = True
        # Find the last list item after external_dirs
        j = i + 1
        while j < len(lines) and lines[j].strip().startswith('- '):
            j += 1
        insert_idx = j

if insert_idx is None and in_skills and not has_external_dirs:
    # skills: was the last section — append at end
    insert_idx = len(lines)

if insert_idx is None and not has_external_dirs and in_skills is False:
    # No skills: section at all — should not happen if has_skills_section passed
    print('ERROR: Could not find skills: section', file=sys.stderr)
    sys.exit(1)

if not has_external_dirs:
    # Insert external_dirs: header + entry
    lines.insert(insert_idx, '  external_dirs:\n')
    lines.insert(insert_idx + 1, new_entry + '\n')
else:
    lines.insert(insert_idx, new_entry + '\n')

with open(config_path, 'w') as f:
    f.writelines(lines)

print('INSERTED')
PYEOF
}

remove_external_dir() {
  local rm_path="$1"
  local backup="${CONFIG}.agentfs-undo.$(date '+%Y%m%d-%H%M%S')"
  cp "$CONFIG" "$backup"
  info "Config backup: $backup"

  python3 << PYEOF
config_path = '$CONFIG'
rm_path = '$rm_path'

with open(config_path, 'r') as f:
    lines = f.readlines()

out = []
for line in lines:
    if rm_path in line and line.strip().startswith('- '):
        continue
    out.append(line)

with open(config_path, 'w') as f:
    f.writelines(out)

print('REMOVED')
PYEOF
}

# ── Check ─────────────────────────────────────────────────────────────────

do_check() {
  local issues=0

  hdr "AgentFS Compatibility Check for Hermes Agent"

  # 1. Hermes installed
  if [[ -d "$HERMES_HOME" ]]; then
    ok "Hermes home exists: $HERMES_HOME"
  else
    fail "Hermes home not found: $HERMES_HOME"
    issues=$((issues + 1))
  fi

  # 2. Config exists
  if config_exists; then
    ok "Config file exists: $CONFIG"
  else
    fail "Config file not found: $CONFIG"
    issues=$((issues + 1))
    printf "\nFound %d issue(s).\n" "$issues"
    return 0
  fi

  # 3. skills section
  if has_skills_section; then
    ok "skills: section exists in config"
  else
    warn "No skills: section in config (will be created by setup)"
    issues=$((issues + 1))
  fi

  # 4. external_dirs
  if has_external_dirs; then
    ok "skills.external_dirs is configured"
  else
    warn "skills.external_dirs not configured (will be added by setup)"
    issues=$((issues + 1))
  fi

  # ── USER scope ──
  printf "\n  ${BOLD}USER scope${NC} (~/.agents/skills/)\n\n"

  if has_system_entry; then
    ok "~/.agents/skills is in external_dirs"
  else
    fail "~/.agents/skills is NOT in external_dirs"
    issues=$((issues + 1))
  fi

  if [[ -d "$AGENTS_SKILLS_USER_EXPANDED" ]]; then
    local sys_count
    sys_count=$(count_skills "$AGENTS_SKILLS_USER_EXPANDED")
    ok "~/.agents/skills/ exists ($sys_count skills found)"
  else
    warn "~/.agents/skills/ directory does not exist yet"
    issues=$((issues + 1))
  fi

  # ── PROJECT scope ──
  printf "\n  ${BOLD}PROJECT scope${NC} (.agents/skills/ in CWD)\n\n"

  local cwd_skills
  cwd_skills="$(pwd)/.agents/skills"

  if [[ -d "$cwd_skills" ]]; then
    local proj_count
    proj_count=$(count_skills "$cwd_skills")
    ok ".agents/skills/ exists in CWD ($proj_count skills found)"

    if path_in_external_dirs "$cwd_skills"; then
      ok "CWD .agents/skills/ is registered in external_dirs"
    else
      warn "CWD .agents/skills/ is NOT registered — run: setup.sh --project"
      issues=$((issues + 1))
    fi
  else
    info "No .agents/skills/ in CWD (no PROJECT skills to register)"
  fi

  # ── Registered PROJECT paths ──
  local projects
  projects=$(list_project_entries)
  if [[ -n "$projects" ]]; then
    printf "\n  ${BOLD}Registered PROJECT paths${NC}\n\n"
    while IFS= read -r p; do
      local expanded
      expanded=$(eval echo "$p" 2>/dev/null || echo "$p")
      if [[ -d "$expanded" ]]; then
        local pc
        pc=$(count_skills "$expanded")
        ok "$p ($pc skills)"
      else
        warn "$p (directory not found)"
      fi
    done <<< "$projects"
  fi

  # ── AGENTS.md (informational) ──
  printf "\n  ${BOLD}AGENTS.md${NC}\n\n"
  info "Hermes loads AGENTS.md from CWD natively (priority #2) — no setup needed"

  printf "\n"
  if [[ "$issues" -eq 0 ]]; then
    ok "All checks passed — Hermes is AgentFS-compatible"
  else
    warn "Found $issues issue(s) — run the appropriate setup command to fix"
  fi
}

# ── Setup (USER) ────────────────────────────────────────────────────────

do_setup_system() {
  hdr "AgentFS USER Setup for Hermes Agent"

  if ! config_exists; then
    fail "Config file not found: $CONFIG"
    fail "Is Hermes Agent installed?"
    exit 1
  fi

  if has_system_entry; then
    ok "Already configured — ~/.agents/skills is in external_dirs"
    info "Run with --check to verify full compatibility"
    return 0
  fi

  # Ensure skills: section exists
  if ! has_skills_section; then
    printf "\nskills:\n  external_dirs:\n    - ~/.agents/skills\n" >> "$CONFIG"
    ok "Created skills: section with external_dirs"
  else
    add_external_dir "~/.agents/skills"
    ok "Added ~/.agents/skills to skills.external_dirs"
  fi

  # Ensure directory exists
  if [[ ! -d "$AGENTS_SKILLS_USER_EXPANDED" ]]; then
    mkdir -p "$AGENTS_SKILLS_USER_EXPANDED"
    ok "Created ~/.agents/skills/ directory"
  fi

  printf "\n"
  ok "USER setup complete — Hermes will discover AgentFS USER skills"
  info "Restart Hermes to pick up the new skills"
}

# ── Setup (PROJECT) ───────────────────────────────────────────────────────

do_setup_project() {
  local project_dir="${1:-$(pwd)}"

  # Resolve to absolute path
  project_dir="$(cd "$project_dir" 2>/dev/null && pwd)" || {
    fail "Directory not found: $1"
    exit 1
  }

  local project_skills="$project_dir/.agents/skills"

  hdr "AgentFS PROJECT Setup for Hermes Agent"

  if ! config_exists; then
    fail "Config file not found: $CONFIG"
    exit 1
  fi

  info "Project: $project_dir"

  # Check if .agents/skills/ exists
  if [[ ! -d "$project_skills" ]]; then
    warn "$project_skills does not exist"
    info "Creating it now..."
    mkdir -p "$project_skills"
    ok "Created $project_skills"
  fi

  # Check if already registered
  if path_in_external_dirs "$project_skills"; then
    ok "Already registered — $project_skills is in external_dirs"
    return 0
  fi

  # Ensure skills: section exists
  if ! has_skills_section; then
    printf "\nskills:\n  external_dirs:\n    - %s\n" "$project_skills" >> "$CONFIG"
    ok "Created skills: section with project path"
  else
    add_external_dir "$project_skills"
    ok "Added $project_skills to external_dirs"
  fi

  printf "\n"
  ok "PROJECT setup complete"
  info "Hermes will discover skills from: $project_skills"
  info "Restart Hermes to pick up the new skills"
  warn "This is a per-project registration — run again in each project that has .agents/skills/"
}

# ── Undo (USER) ────────────────────────────────────────────────────────

do_undo_system() {
  hdr "Undo AgentFS USER Setup"

  if ! config_exists; then
    fail "Config file not found: $CONFIG"
    exit 1
  fi

  if ! has_system_entry; then
    ok "Nothing to undo — ~/.agents/skills is not in external_dirs"
    return 0
  fi

  remove_external_dir "~/.agents/skills"
  ok "Removed ~/.agents/skills from external_dirs"
}

# ── Undo (PROJECT) ───────────────────────────────────────────────────────

do_undo_project() {
  local project_dir="${1:-$(pwd)}"

  project_dir="$(cd "$project_dir" 2>/dev/null && pwd)" || {
    fail "Directory not found: $1"
    exit 1
  }

  local project_skills="$project_dir/.agents/skills"

  hdr "Undo AgentFS PROJECT Setup"

  if ! config_exists; then
    fail "Config file not found: $CONFIG"
    exit 1
  fi

  if ! path_in_external_dirs "$project_skills"; then
    ok "Nothing to undo — $project_skills is not in external_dirs"
    return 0
  fi

  remove_external_dir "$project_skills"
  ok "Removed $project_skills from external_dirs"
}

# ── List ──────────────────────────────────────────────────────────────────

do_list() {
  hdr "Registered AgentFS Paths in Hermes"

  if ! config_exists; then
    fail "Config file not found"
    exit 1
  fi

  # USER
  printf "  ${BOLD}USER${NC}\n"
  if has_system_entry; then
    ok "~/.agents/skills ($(count_skills "$AGENTS_SKILLS_USER_EXPANDED") skills)"
  else
    fail "~/.agents/skills — not registered"
  fi

  # PROJECT
  local projects
  projects=$(list_project_entries)
  if [[ -n "$projects" ]]; then
    printf "\n  ${BOLD}PROJECT${NC}\n"
    while IFS= read -r p; do
      if [[ -d "$p" ]]; then
        ok "$p ($(count_skills "$p") skills)"
      else
        warn "$p (not found)"
      fi
    done <<< "$projects"
  else
    printf "\n  ${BOLD}PROJECT${NC}\n"
    info "No project paths registered"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────

case "${1:-}" in
  --check|-c)
    do_check
    ;;
  --project|-p)
    do_setup_project "${2:-}"
    ;;
  --undo|-u)
    do_undo_system
    ;;
  --undo-project|-up)
    do_undo_project "${2:-}"
    ;;
  --list|-l)
    do_list
    ;;
  --help|-h)
    printf "Usage: %s [COMMAND]\n\n" "$(basename "$0")"
    printf "  ${BOLD}USER scope${NC} (~/.agents/skills — shared across projects)\n"
    printf "    (no args)                Run USER setup\n"
    printf "    --undo                   Remove USER entry\n\n"
    printf "  ${BOLD}PROJECT scope${NC} (.agents/skills — per-project)\n"
    printf "    --project [path]         Register CWD (or path) project skills\n"
    printf "    --undo-project [path]    Remove CWD (or path) project entry\n\n"
    printf "  ${BOLD}Diagnostics${NC}\n"
    printf "    --check                  Verify AgentFS compatibility\n"
    printf "    --list                   List all registered AgentFS paths\n"
    printf "    --help                   Show this help\n"
    ;;
  *)
    do_setup_system
    ;;
esac
