#!/usr/bin/env bash
# setup.sh — Check Hermes Desktop health on Linux; apply a fix only when a
# known problem is detected.
# Usage: setup.sh [--dry-run]
# Exit: 0 ok (dry-run always 0 + DRY_RUN_RESULT) · 1 failure · 2 usage
set -uo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "hermes-desktop-fixes" "4.0.0" 2>/dev/null || true

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '4p' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "❌ Unknown option: $arg"; exit 2 ;;
  esac
done

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
REPO="${HERMES_HOME}/hermes-agent"
APPS="${HOME}/.local/share/applications"
ENTRY="${APPS}/com.nousresearch.hermes.desktop"
LEGACY="${APPS}/hermes.desktop"
LAUNCHER="${HOME}/.local/bin/hermes"
REAL_BIN="${REPO}/.hermes/bin/hermes"
CHROMIUM_LOG="${HERMES_HOME}/logs/desktop-chromium.log"
PENDING=0
FAILED=0

do_or_plan() {  # $1 = description, rest = command
  local desc="$1"; shift
  PENDING=$((PENDING + 1))
  if $DRY_RUN; then
    echo "    → would: $desc"
  elif "$@"; then
    echo "    ✅ $desc"
  else
    echo "    ❌ failed: $desc"; FAILED=$((FAILED + 1))
  fi
}

echo "=== Hermes Desktop Fixes$($DRY_RUN && echo ' (dry-run)') ==="

# ── Step 1: Hermes installed ──────────────────────────────────
if [[ ! -x "$REAL_BIN" ]]; then
  echo "❌ Hermes not installed ($REAL_BIN missing) — run the hermes-install skill first"
  trace_step 1 "installed" 1 "" 2>/dev/null || true; trace_end 2>/dev/null || true
  exit 1
fi
echo "✅ Hermes installed: $REPO"
trace_step 1 "installed" 0 "" 2>/dev/null || true

# ── Step 2: Desktop entry (written by upstream) ───────────────
if [[ -f "$ENTRY" ]]; then
  if grep -q '^StartupWMClass=com.nousresearch.hermes$' "$ENTRY" && grep -q '^Exec=.*hermes desktop' "$ENTRY"; then
    echo "✅ Desktop entry: $ENTRY (app-id + Exec OK)"
  else
    echo "⚠️  Desktop entry has unexpected StartupWMClass/Exec — upstream rewrites it on next 'hermes desktop' launch"
  fi
else
  echo "ℹ️  Desktop entry not created yet — upstream writes it on the first 'hermes desktop' launch"
fi
if [[ -f "$LEGACY" ]] && ! grep -q '^NoDisplay=true' "$LEGACY"; then
  echo "⚠️  Visible legacy hermes.desktop (duplicate icon)"
  do_or_plan "remove visible legacy $LEGACY" rm -f "$LEGACY"
fi
trace_step 2 "desktop_entry" 0 "" 2>/dev/null || true

# ── Step 3: Leftovers from hermes-desktop-fixes v3.x ──────────
# v3 replaced the upstream launcher with a wrapper (hermes-env.sh, venv path)
# and patched server.py under skip-worktree. Both break current upstream.
if [[ -f "$LAUNCHER" ]] && grep -q -E 'hermes-env\.sh|venv/bin/hermes' "$LAUNCHER"; then
  echo "⚠️  ~/.local/bin/hermes is the old v3 wrapper"
  do_or_plan "restore upstream launcher shim → $REAL_BIN" \
    sh -c "printf '#!/bin/sh\nexec %s \"\$@\"\n' '$REAL_BIN' > '$LAUNCHER' && chmod +x '$LAUNCHER'"
fi
SKIPPED=$(git -C "$REPO" ls-files -v 2>/dev/null | awk '/^S /{print $2}')
if [[ -n "$SKIPPED" ]]; then
  echo "⚠️  skip-worktree files in checkout (old patches): $(echo $SKIPPED)"
  # shellcheck disable=SC2086
  do_or_plan "clear skip-worktree + restore upstream copies" \
    sh -c "cd '$REPO' && git update-index --no-skip-worktree $(echo $SKIPPED) && git checkout -- $(echo $SKIPPED)"
fi
if [[ -f "$REPO/.git/hooks/post-merge" ]] && grep -q 'hermes-apply-patches' "$REPO/.git/hooks/post-merge"; then
  do_or_plan "remove old post-merge hook" rm -f "$REPO/.git/hooks/post-merge"
fi
for f in hermes-env.sh hermes-apply-patches.sh hermes-revert-patches.sh hermes-check-patches.sh; do
  [[ -f "$HERMES_HOME/$f" ]] && do_or_plan "remove old $HERMES_HOME/$f" rm -f "$HERMES_HOME/$f"
done
trace_step 3 "v3_leftovers" 0 "" 2>/dev/null || true

# ── Step 4: GPU crash (Intel Arc + Wayland) ───────────────────
if [[ -f "$CHROMIUM_LOG" ]] && grep -q 'FATAL.*GPU process' "$CHROMIUM_LOG"; then
  if grep -A3 '^desktop:' "$HERMES_HOME/config.yaml" 2>/dev/null | grep -q -E 'disable_gpu: *(true|"?1"?)'; then
    echo "✅ GPU crash seen before; desktop.disable_gpu already true"
  else
    echo "⚠️  GPU process FATAL in $CHROMIUM_LOG"
    do_or_plan "hermes config set desktop.disable_gpu true" "$REAL_BIN" config set desktop.disable_gpu true
  fi
else
  echo "✅ No GPU crash in desktop-chromium.log"
fi
trace_step 4 "gpu" 0 "pending=${PENDING}" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────
echo
if $DRY_RUN; then
  if [[ $PENDING -eq 0 ]]; then
    echo "DRY_RUN_RESULT=CONVERGED"
    echo "✅ Hermes Desktop healthy — no fixes needed"
  else
    echo "DRY_RUN_RESULT=PENDING"
    echo "$PENDING fix(es) would be applied"
  fi
  trace_end 2>/dev/null || true
  exit 0
fi
trace_end 2>/dev/null || true
if [[ $FAILED -gt 0 ]]; then
  echo "APPLY_RESULT=FAILED ($FAILED of $PENDING)"
  exit 1
fi
echo "APPLY_RESULT=OK ($PENDING fix(es) applied)"
exit 0
