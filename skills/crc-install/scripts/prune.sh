#!/usr/bin/env bash
# prune.sh — Remove what an install/upgrade left behind: old bundles, crc-<old> binaries, downloads.
# Usage: bash prune.sh [--dry-run]
# Exit: 0 pruned / nothing to prune · 1 refused (installed version not verified) or failure · 2 usage
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-install" "1.0.0" 2>/dev/null || true

DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
  *) echo "❌ Unknown option: $1"; exit 2 ;;
esac

echo "=== CRC — PRUNE ==="
# Rollback stays possible until this runs, so require the verify marker of the installed version.
if ! installed_version; then
  echo "❌ $CRC_BIN not installed — nothing to keep, use install.sh --uninstall instead"
  trace_step 1 "gate" 1 "no_binary" 2>/dev/null || true; trace_end 2>/dev/null || true; exit 1
fi
if [[ ! -f "$CRC_STATE_DIR/verified-$INST_VER" ]]; then
  echo "❌ crc $INST_VER not verified yet ($CRC_STATE_DIR/verified-$INST_VER missing)."
  echo "   Run install.sh first (its verify phase writes the marker). Rollback artifacts are kept."
  trace_step 1 "gate" 1 "unverified=$INST_VER" 2>/dev/null || true; trace_end 2>/dev/null || true; exit 1
fi
echo "  ✅ crc $INST_VER (OpenShift $INST_OCP) verified: $(cat "$CRC_STATE_DIR/verified-$INST_VER")"
trace_step 1 "gate" 0 "ver=$INST_VER" 2>/dev/null || true

# Collect candidates: bundles for other OpenShift versions, old binaries, download staging, stale markers.
CAND=()
while read -r b; do
  [[ -z "$b" ]] && continue
  [[ "$b" == *"_${INST_OCP}_"* || "$b" == *"_${INST_OCP}" ]] && continue
  CAND+=("$b")
done < <(cached_bundles)
while read -r b; do [[ -n "$b" ]] && CAND+=("$b"); done < <(old_binaries)
[[ -d "$CRC_STAGE_DIR" ]] && [[ -n "$(ls -A "$CRC_STAGE_DIR" 2>/dev/null)" ]] && CAND+=("$CRC_STAGE_DIR")
for m in "$CRC_STATE_DIR"/verified-*; do
  [[ -f "$m" && "$m" != "$CRC_STATE_DIR/verified-$INST_VER" ]] && CAND+=("$m")
done

if [[ ${#CAND[@]} -eq 0 ]]; then
  echo "  ✅ nothing to prune"
  [[ $DRY -eq 1 ]] && echo && echo "DRY_RUN_RESULT=CONVERGED"
  trace_step 2 "collect" 0 "n=0" 2>/dev/null || true; trace_end 2>/dev/null || true; exit 0
fi
BEFORE="$(free_gb "$HOME")"
for c in "${CAND[@]}"; do echo "  🗑️  $c ($(size_of "$c"))"; done
trace_step 2 "collect" 0 "n=${#CAND[@]}" 2>/dev/null || true

if [[ $DRY -eq 1 ]]; then
  echo "  Total: $(du -sch "${CAND[@]}" 2>/dev/null | tail -1 | awk '{print $1}')"
  echo; echo "DRY_RUN_RESULT=PENDING"; trace_end 2>/dev/null || true; exit 0
fi

FAIL=0
for c in "${CAND[@]}"; do
  if rm -rf -- "$c"; then echo "  ✅ removed $c"; else echo "  ❌ could not remove $c"; FAIL=1; fi
done
echo "  ℹ️  free on $HOME: ${BEFORE} GiB → $(free_gb "$HOME") GiB"
echo "  ℹ️  rollback now needs a fresh download: install.sh --version <old>"
trace_step 3 "remove" "$FAIL" "" 2>/dev/null || true
trace_end 2>/dev/null || true
exit "$FAIL"
