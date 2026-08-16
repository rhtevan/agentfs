#!/usr/bin/env bash
# post-edit.sh — Mechanical post-edit checks for AgentFS files.
#
# Run after editing any file under .agents/ (either scope).
# Handles the fragile/deterministic steps; agent handles contextual
# steps (log entries, CHANGELOG entries) separately.
#
# Usage: bash post-edit.sh [--user] [--project] [--all]
#   --user     Check USER scope (~/.agents/) only
#   --project  Check PROJECT scope (./.agents/) only
#   --all      Check both scopes (default)
#
# What it does:
#   1. Regenerate skills/index.md (if skills exist in scope)
#   2. Validate log.md comment-line anchors
#   3. Report results
#
# Exit codes:
#   0 = all checks passed
#   1 = issues found (reported on stdout)

set -euo pipefail

# ── Parse args ─────────────────────────────────────────────────────
CHECK_USER=false
CHECK_PROJECT=false

case "${1:-}" in
  --user)    CHECK_USER=true ;;
  --project) CHECK_PROJECT=true ;;
  --all|'')  CHECK_USER=true; CHECK_PROJECT=true ;;
  *) echo "Usage: bash post-edit.sh [--user] [--project] [--all]"; exit 1 ;;
esac

ISSUES=0
ACTIONS=0

info()  { echo "  ✅ $*"; }
warn()  { echo "  ⚠️  $*"; ISSUES=$((ISSUES + 1)); }
action() { echo "  🔧 $*"; ACTIONS=$((ACTIONS + 1)); }

# ── Skills index regeneration ──────────────────────────────────────
# Implements skill-index logic: scan for SKILL.md, extract metadata,
# generate index.md sorted by reverse chronological order.
regen_skills_index() {
  local skills_root="$1"
  local scope_label="$2"

  if [[ ! -d "$skills_root" ]]; then
    return
  fi

  # Count skills
  local skill_count=0
  for d in "$skills_root"/*/; do
    [[ -f "${d}SKILL.md" ]] && skill_count=$((skill_count + 1))
  done

  if [[ $skill_count -eq 0 ]]; then
    return
  fi

  echo "[$scope_label] Regenerating skills/index.md ($skill_count skills)..."

  python3 - "$skills_root" <<'PYEOF'
import os, re, sys, datetime

skills_root = sys.argv[1]
entries = []
warnings = []

for d in sorted(os.listdir(skills_root)):
    skill_dir = os.path.join(skills_root, d)
    skill_file = os.path.join(skill_dir, 'SKILL.md')
    if not os.path.isdir(skill_dir) or not os.path.isfile(skill_file):
        continue

    with open(skill_file, 'r') as f:
        content = f.read()

    name = d
    description = ''
    tags = ''

    if content.startswith('---'):
        parts = content.split('---', 2)
        if len(parts) >= 3:
            fm = parts[1]

            # Name
            m = re.search(r'^name:\s*["\']?(.+?)["\']?\s*$', fm, re.M)
            if m:
                fname = m.group(1).strip()
                if fname != d:
                    warnings.append(f'WARNING: name mismatch — dir=[{d}] name=[{fname}]')
                name = fname
            else:
                warnings.append(f'WARNING: missing name field — dir=[{d}]')

            # Description (multi-line scalar support)
            m = re.search(r'^description:\s*([>|][-]?)\s*$', fm, re.M)
            if m:
                start = m.end()
                lines = []
                for line in fm[start:].split('\n'):
                    if line and (line[0] == ' ' or line[0] == '\t'):
                        lines.append(line.strip())
                    elif line.strip() == '':
                        continue
                    else:
                        break
                description = ' '.join(lines)
            else:
                m = re.search(r'^description:\s*["\']?(.+?)["\']?\s*$', fm, re.M)
                if m:
                    description = m.group(1).strip()

            # Tags
            m = re.search(r'tags:\s*\[([^\]]+)\]', fm)
            if m:
                tags = ', '.join(t.strip().strip('"\'') for t in m.group(1).split(','))

            # Version check
            m = re.search(r'^\s*version:\s*', fm, re.M)
            if not m:
                warnings.append(f'WARNING: missing metadata.version — dir=[{d}]')

            # Legacy signals check
            if re.search(r'^\s*signals:', fm, re.M):
                warnings.append(f'WARNING: legacy metadata.signals found — dir=[{d}]')
    else:
        for line in content.split('\n'):
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('|') or \
               line.startswith('---') or line.startswith('>'):
                continue
            description = line
            break

    mtime = os.stat(skill_file).st_mtime
    ts = datetime.datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')
    entries.append((ts, d, name, tags, description))

# Sort newest first
entries.sort(key=lambda e: e[0], reverse=True)

# Generate index.md
lines = [
    '# Skills Index', '',
    f'> {len(entries)} skills | Sorted by reverse chronological order (newest first).', '',
    '| Skill | Tags | Description | Updated |',
    '|-------|------|-------------|---------|',
]
for ts, d, name, tags, desc in entries:
    lines.append(f'| [{name}](./{d}/SKILL.md) | {tags} | {desc} | {ts} |')

index_path = os.path.join(skills_root, 'index.md')
with open(index_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f'  ✅ Indexed {len(entries)} skills → {index_path}')
for w in warnings:
    print(f'  ⚠️  {w}')

sys.exit(1 if warnings else 0)
PYEOF

  local rc=$?
  if [[ $rc -ne 0 ]]; then
    ISSUES=$((ISSUES + 1))
  fi
}

# ── Log.md comment-line validation ─────────────────────────────────
check_log_anchor() {
  local log_file="$1"
  local scope_label="$2"

  if [[ ! -f "$log_file" ]]; then
    return
  fi

  # Check for comment line
  if ! head -3 "$log_file" | grep -q '<!-- Append-only'; then
    warn "[$scope_label] $log_file missing comment-line anchor"
  else
    info "[$scope_label] $log_file has comment-line anchor"
  fi
}

# ── Main ───────────────────────────────────────────────────────────
echo "=== AgentFS Post-Edit Check ==="
echo

if $CHECK_USER; then
  USER_ROOT="${HOME}/.agents"
  if [[ -d "$USER_ROOT" ]]; then
    echo "[USER] Checking ~/.agents/"
    regen_skills_index "$USER_ROOT/skills" "USER"
    check_log_anchor "$USER_ROOT/log.md" "USER"
    check_log_anchor "$USER_ROOT/knowledge/log.md" "USER/knowledge"
    echo
  fi
fi

if $CHECK_PROJECT; then
  PROJECT_ROOT="./.agents"
  if [[ -d "$PROJECT_ROOT" ]]; then
    echo "[PROJECT] Checking ./.agents/"
    regen_skills_index "$PROJECT_ROOT/skills" "PROJECT"
    check_log_anchor "./.agents/log.md" "PROJECT"
    echo
  fi
fi

# ── Summary ────────────────────────────────────────────────────────
echo "=== Summary ==="
if [[ $ISSUES -eq 0 ]]; then
  echo "  ✅ All checks passed."
else
  echo "  ⚠️  $ISSUES issue(s) found."
fi
echo
echo "Reminder: Log entries (log.md, CHANGELOG.md) require agent judgment — not automated."

exit $( [[ $ISSUES -eq 0 ]] && echo 0 || echo 1 )
