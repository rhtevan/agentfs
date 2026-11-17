#!/usr/bin/env bash
# stop.sh — Stop a deployment profile
# Usage: bash stop.sh [--dry-run] PROFILE [--remove]
#    or: bash stop.sh [--dry-run] all [--remove]
# --remove: also delete the container after stopping
#
# --dry-run (read-only, Rule 7):
#   DRY_RUN_RESULT=CONVERGED  probe succeeded and the container(s) are already stopped (absent with --remove)
#   DRY_RUN_RESULT=PENDING    apply would stop/remove containers (plan printed)
#   DRY_RUN_RESULT=UNKNOWN    a host could not be probed (exit 3) — do NOT treat as stopped
# Exit codes: 0 ok · 1 usage · 2 bad argument · 3 probe failed · other = podman stop/rm exit code

source "$(dirname "$0")/common.sh"

USAGE="stop.sh [--dry-run] PROFILE|all [--remove]"
parse_cli_args stop.sh "$USAGE" "--remove all" "$@"

# stop_one — act on the parsed profile (globals) using the current PROBE_PS.
# Dry-run: prints plan lines and sets NEEDS_CHANGE=true when apply would act.
NEEDS_CHANGE=false
stop_one() {
  local state rc out
  state=$(probe_state "$CONTAINER")
  if [[ "$state" == "running" || "$state" == "paused" ]]; then
    if $DRY_RUN; then
      echo "  - stop $CONTAINER on $PROFILE_HOST ($state)"; NEEDS_CHANGE=true
    else
      rc=0; out=$(run_on_host "$PROFILE_HOST" "podman stop $CONTAINER 2>&1") || rc=$?
      if (( rc != 0 )); then
        echo "❌ podman stop $CONTAINER failed on $PROFILE_HOST (exit $rc): $out" >&2
        exit "$rc"
      fi
      echo "  ✅ $CONTAINER stopped"
    fi
  elif ! $DRY_RUN && [[ "$PROFILE" != "all" ]]; then
    echo "⏭️  $CONTAINER not running ($state)"
  fi
  if [[ "$REMOVE" == "true" && "$state" != "absent" ]]; then
    if $DRY_RUN; then
      echo "  - remove $CONTAINER on $PROFILE_HOST"; NEEDS_CHANGE=true
    else
      rc=0; out=$(run_on_host "$PROFILE_HOST" "podman rm -f $CONTAINER 2>&1") || rc=$?
      if (( rc != 0 )); then
        echo "❌ podman rm $CONTAINER failed on $PROFILE_HOST (exit $rc): $out" >&2
        exit "$rc"
      fi
      echo "  🗑️  $CONTAINER removed"
    fi
  fi
  return 0
}

# ── Stop all ──────────────────────────────────────────────────
if [[ "$PROFILE" == "all" ]]; then
  if $DRY_RUN; then echo "Dry-run: stop all model containers"; else echo "Stopping all model containers..."; fi
  UNPROBED=()
  for host in "${ALL_HOSTS[@]}"; do
    rc=0; probe_host "$host" || rc=$?
    if (( rc != 0 )); then
      echo "  ⚠️  $PROBE_ERR — skipping $host (state NOT verified)" >&2
      UNPROBED+=("$host")
      continue
    fi
    for p in "${ALL_PROFILES[@]}"; do
      [[ -n "${COMPOSITE_PROFILES[$p]:-}" ]] && continue
      parse_profile "$p" 2>/dev/null || continue
      [[ "$PROFILE_HOST" != "$host" ]] && continue
      stop_one
    done
  done
  if $DRY_RUN; then
    if (( ${#UNPROBED[@]} > 0 )); then
      echo "DRY_RUN_RESULT=UNKNOWN"
      echo "DRY_RUN_REASON=unprobed-hosts:${UNPROBED[*]}"
      exit 3
    fi
    if $NEEDS_CHANGE; then echo "DRY_RUN_RESULT=PENDING"; else echo "DRY_RUN_RESULT=CONVERGED"; fi
    exit 0
  fi
  if (( ${#UNPROBED[@]} > 0 )); then
    echo "⚠️  Stopped on reachable hosts only — NOT verified: ${UNPROBED[*]}" >&2
    exit 3
  fi
  if [[ "$REMOVE" == "true" ]]; then echo "✅ All models stopped and removed"; else echo "✅ All models stopped"; fi
  exit 0
fi

# ── Composite profile handling ──────────────────────────────────
if [[ -n "${COMPOSITE_PROFILES[$PROFILE]:-}" ]]; then
  echo "=== Stop (composite): $PROFILE ==="
  read -ra SUB_PROFILES <<< "${COMPOSITE_PROFILES[$PROFILE]}"
  if $DRY_RUN; then
    # dry_run_composite runs sub-profiles without --remove; pass it through explicitly
    if [[ "$REMOVE" == "true" ]]; then
      agg=CONVERGED
      for sub in "${SUB_PROFILES[@]}"; do
        rc=0; out=$(bash "$(dirname "$0")/stop.sh" --dry-run "$sub" --remove 2>&1) || rc=$?
        printf '%s\n' "$out" | grep -v '^DRY_RUN_' || true
        r=$(grep -m1 '^DRY_RUN_RESULT=' <<< "$out" | cut -d= -f2 || true)
        case "$r" in CONVERGED) ;; PENDING) [[ $agg == CONVERGED ]] && agg=PENDING ;; *) agg=UNKNOWN ;; esac
      done
      echo "DRY_RUN_RESULT=$agg"; [[ $agg == UNKNOWN ]] && exit 3; exit 0
    fi
    dry_run_composite "$(dirname "$0")/stop.sh" "${SUB_PROFILES[@]}"
  fi
  for sub in "${SUB_PROFILES[@]}"; do
    echo ""
    echo "── Sub-profile: $sub ──"
    if [[ "$REMOVE" == "true" ]]; then
      bash "$(dirname "$0")/stop.sh" "$sub" --remove
    else
      bash "$(dirname "$0")/stop.sh" "$sub"
    fi
  done
  echo ""
  echo "✅ Composite profile '$PROFILE' stopped (${#SUB_PROFILES[@]} containers)"
  exit 0
fi

# ── Stop single profile ──────────────────────────────────────
parse_profile "$PROFILE"

if $DRY_RUN; then
  echo "Dry-run: stop profile $PROFILE ($PROFILE_DESC)"
else
  echo "Stopping profile: $PROFILE ($PROFILE_DESC)"
fi
echo "  Host: $PROFILE_HOST"
echo "  Container: $CONTAINER"

# Fail closed: an unprobeable host is never reported as "not running".
probe_or_fail "$PROFILE_HOST" "$DRY_RUN"

if $DRY_RUN; then
  echo "Plan (apply):"
  stop_one
  if $NEEDS_CHANGE; then
    echo "DRY_RUN_RESULT=PENDING"
  else
    echo "  (nothing — $CONTAINER is $(probe_state "$CONTAINER"))"
    echo "DRY_RUN_RESULT=CONVERGED"
  fi
  exit 0
fi

stop_one
echo "✅ Profile '$PROFILE' stopped on $PROFILE_HOST"
