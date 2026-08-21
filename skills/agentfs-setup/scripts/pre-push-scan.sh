#!/usr/bin/env bash
# pre-push-scan.sh — Pre-push security scan for git repositories.
#
# Usage: bash pre-push-scan.sh [--mode cached|unstaged]
#   --mode cached    Scan staged changes (default)
#   --mode unstaged  Scan unstaged changes
#
# Scans git diff output for secrets, hardcoded paths, username leakage,
# IP addresses, sensitive URLs, and PII. Outputs a structured report.
#
# Exit codes:
#   0 = all checks clean
#   1 = findings detected

set -euo pipefail

# ── Parse args ─────────────────────────────────────────────────────
MODE="cached"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    *) echo "Usage: bash pre-push-scan.sh [--mode cached|unstaged]"; exit 2 ;;
  esac
done

if [[ "$MODE" == "cached" ]]; then
  DIFF_CMD="git diff --cached"
else
  DIFF_CMD="git diff"
fi

# ── Get diff content ───────────────────────────────────────────────
DIFF_CONTENT=$($DIFF_CMD 2>/dev/null || true)
if [[ -z "$DIFF_CONTENT" ]]; then
  echo "No changes to scan (mode: $MODE)."
  exit 0
fi

# Only scan added lines (lines starting with +, excluding +++ headers)
ADDED_LINES=$(echo "$DIFF_CONTENT" | grep '^+' | grep -v '^+++' || true)
if [[ -z "$ADDED_LINES" ]]; then
  echo "No added lines to scan."
  exit 0
fi

# ── Gather system context ──────────────────────────────────────────
CURRENT_USER=$(whoami 2>/dev/null || echo "")
LOCAL_IPS=$(hostname -I 2>/dev/null || echo "")
SSH_HOSTS=""
if [[ -f "$HOME/.ssh/config" ]]; then
  SSH_HOSTS=$(grep -i '^\s*Host\b' "$HOME/.ssh/config" 2>/dev/null | awk '{for(i=2;i<=NF;i++) print $i}' | grep -v '[*?]' || true)
fi

FINDINGS=0
DETAILS=""

report_category() {
  local category="$1"
  local matches="$2"
  if [[ -n "$matches" ]]; then
    FINDINGS=$((FINDINGS + 1))
    DETAILS+="| $category | ⚠️  FOUND |\n"
    while IFS= read -r line; do
      DETAILS+="|  | \`${line:0:80}\` |\n"
    done <<< "$matches"
  else
    DETAILS+="| $category | ✅ Clean |\n"
  fi
}

# ── Category 1: Secrets / API keys ────────────────────────────────
SECRETS=$(echo "$ADDED_LINES" | grep -iE '(secret|api_key|apikey|password|passwd|bearer|authorization)\s*[:=]' || true)
report_category "Secrets / API keys" "$SECRETS"

# ── Category 2: Hardcoded user paths ──────────────────────────────
HARDCODED_PATHS=""
if [[ -n "$CURRENT_USER" ]]; then
  HARDCODED_PATHS=$(echo "$ADDED_LINES" | grep -E "(/home/$CURRENT_USER/|/Users/$CURRENT_USER/)" || true)
fi
report_category "Hardcoded user paths" "$HARDCODED_PATHS"

# ── Category 3: Username leakage ──────────────────────────────────
USERNAME_LEAKS=""
if [[ -n "$CURRENT_USER" ]]; then
  # Exclude path contexts — look for username in non-path positions
  USERNAME_LEAKS=$(echo "$ADDED_LINES" | grep -v "/home/$CURRENT_USER" | grep -v "/Users/$CURRENT_USER" | grep -w "$CURRENT_USER" || true)
fi
# Also check SSH host aliases
if [[ -n "$SSH_HOSTS" ]]; then
  while IFS= read -r host; do
    HOST_MATCHES=$(echo "$ADDED_LINES" | grep -w "$host" || true)
    if [[ -n "$HOST_MATCHES" ]]; then
      USERNAME_LEAKS+="$HOST_MATCHES"
    fi
  done <<< "$SSH_HOSTS"
fi
report_category "Username / SSH host leakage" "$USERNAME_LEAKS"

# ── Category 4: IP addresses ──────────────────────────────────────
# Check for local IPs and RFC 1918 addresses
IP_MATCHES=""
# Local IPs
if [[ -n "$LOCAL_IPS" ]]; then
  for ip in $LOCAL_IPS; do
    ESCAPED_IP=$(echo "$ip" | sed 's/\./\\./g')
    IP_HIT=$(echo "$ADDED_LINES" | grep -E "$ESCAPED_IP" || true)
    if [[ -n "$IP_HIT" ]]; then
      IP_MATCHES+="$IP_HIT"
    fi
  done
fi
# RFC 1918 addresses (site-specific, not common defaults like 127.0.0.1)
RFC1918=$(echo "$ADDED_LINES" | grep -oE '(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})' || true)
if [[ -n "$RFC1918" ]]; then
  IP_MATCHES+="$RFC1918"
fi
report_category "IP addresses" "$IP_MATCHES"

# ── Category 5: Sensitive URLs ────────────────────────────────────
SENSITIVE_URLS=$(echo "$ADDED_LINES" | grep -iE '(https?://(localhost|internal|intranet|staging|dev\.|corp\.|private))' || true)
report_category "Sensitive URLs" "$SENSITIVE_URLS"

# ── Category 6: PII ───────────────────────────────────────────────
# Email addresses
EMAIL_MATCHES=$(echo "$ADDED_LINES" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' || true)
# Phone numbers (common formats)
PHONE_MATCHES=$(echo "$ADDED_LINES" | grep -oE '(\+?1?[-. ]?\(?[0-9]{3}\)?[-. ]?[0-9]{3}[-. ]?[0-9]{4})' || true)
PII=""
[[ -n "$EMAIL_MATCHES" ]] && PII+="$EMAIL_MATCHES"
[[ -n "$PHONE_MATCHES" ]] && PII+="${PII:+\n}$PHONE_MATCHES"
report_category "PII (email, phone)" "$PII"

# ── Category 7: README Staleness ──────────────────────────────────
CHANGED_FILES=$($DIFF_CMD --name-only 2>/dev/null || true)
README_STALE=""
if echo "$CHANGED_FILES" | grep -qE '(skills/|knowledge/|AGENTS\.md|guardrail)'; then
  # Check if README.md is also being updated in this commit
  if ! echo "$CHANGED_FILES" | grep -qE '^README\.md$'; then
    README_STALE="skills/knowledge changed but README.md not updated"
  fi
fi
if [[ -n "$README_STALE" ]]; then
  FINDINGS=$((FINDINGS + 1))
  DETAILS+="| README staleness | ⚠️  STALE — $README_STALE |\n"
else
  DETAILS+="| README staleness | ✅ Clean |\n"
fi

# ── Category 8: Log Coverage ───────────────────────────────────────
# Check that edited scopes have a same-day log.md entry
TODAY=$(date '+%Y-%m-%d')
LOG_GAPS=""

# USER scope: any file under the repo root changed (we're in ~/.agents)
USER_SCOPE_EDITS=$(echo "$CHANGED_FILES" | grep -vE '^log\.md$' | head -1 || true)
if [[ -n "$USER_SCOPE_EDITS" ]]; then
  # Check if log.md has a today entry
  if [[ -f "log.md" ]]; then
    if ! grep -q "^## $TODAY" log.md; then
      LOG_GAPS="Edited files in scope but log.md has no entry for $TODAY"
    fi
  else
    LOG_GAPS="Edited files in scope but log.md does not exist"
  fi
fi

if [[ -n "$LOG_GAPS" ]]; then
  FINDINGS=$((FINDINGS + 1))
  DETAILS+="| Log coverage (G#5) | ⚠️  GAP — $LOG_GAPS |\n"
else
  DETAILS+="| Log coverage (G#5) | ✅ Clean |\n"
fi

# ── Category 9: CHANGELOG Coverage ────────────────────────────────
# Check that staged SKILL.md files have a same-day CHANGELOG.md entry
CHANGELOG_GAPS=""
STAGED_SKILL_MDS=$(echo "$CHANGED_FILES" | grep 'SKILL\.md$' || true)
if [[ -n "$STAGED_SKILL_MDS" ]]; then
  while IFS= read -r skill_md; do
    SKILL_DIR=$(dirname "$skill_md")
    CHANGELOG="$SKILL_DIR/CHANGELOG.md"
    if [[ ! -f "$CHANGELOG" ]]; then
      CHANGELOG_GAPS+="$SKILL_DIR: CHANGELOG.md missing; "
    elif ! grep -q "^| $TODAY" "$CHANGELOG" 2>/dev/null; then
      CHANGELOG_GAPS+="$SKILL_DIR: no entry for $TODAY; "
    fi
  done <<< "$STAGED_SKILL_MDS"
fi

if [[ -n "$CHANGELOG_GAPS" ]]; then
  FINDINGS=$((FINDINGS + 1))
  DETAILS+="| CHANGELOG coverage (G#5) | ⚠️  GAP — ${CHANGELOG_GAPS%; } |\n"
else
  DETAILS+="| CHANGELOG coverage (G#5) | ✅ Clean |\n"
fi

# ── Output Report ──────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       Pre-Push Security Report               ║"
echo "╠══════════════════════════════════════════════╣"
echo ""
echo "| Category | Status |"
echo "|----------|--------|"
echo -e "$DETAILS"

if [[ $FINDINGS -eq 0 ]]; then
  echo ""
  echo "✅ Verdict: ALL CLEAN — no sensitive content detected."
else
  echo ""
  echo "⚠️  Verdict: $FINDINGS category/categories with findings. Review before pushing."
fi



echo ""
if [[ $FINDINGS -gt 0 ]]; then
  exit 1
fi
exit 0
