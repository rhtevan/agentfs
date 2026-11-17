#!/usr/bin/env bash
# start.sh — Start a deployment profile
# Usage: bash start.sh [--dry-run] PROFILE
# Starts an existing (stopped) container for the given profile.
# Enforces mutual exclusion — stops other profiles on same host/port.
#
# --dry-run (read-only, Rule 7):
#   DRY_RUN_RESULT=CONVERGED  container running and API serves the model
#   DRY_RUN_RESULT=PENDING    apply would start/stop containers or wait for the API (plan printed)
#   DRY_RUN_RESULT=UNKNOWN    state could not be determined (exit 3) — do NOT apply
# Exit codes: 0 ok · 1 usage/precondition (container missing) · 2 bad argument · 3 probe failed

source "$(dirname "$0")/common.sh"

parse_cli_args start.sh "start.sh [--dry-run] PROFILE" "" "$@"

# ── Composite profile handling ──────────────────────────────────
if [[ -n "${COMPOSITE_PROFILES[$PROFILE]:-}" ]]; then
  echo "=== Start (composite): $PROFILE ==="
  read -ra SUB_PROFILES <<< "${COMPOSITE_PROFILES[$PROFILE]}"
  $DRY_RUN && dry_run_composite "$(dirname "$0")/start.sh" "${SUB_PROFILES[@]}"
  parse_profile "${SUB_PROFILES[0]}"
  COMPOSITE_HOST="$PROFILE_HOST"
  for sub in "${SUB_PROFILES[@]}"; do
    echo ""
    echo "── Sub-profile: $sub ──"
    bash "$(dirname "$0")/start.sh" "$sub"
  done
  echo ""
  echo "✅ Composite profile '$PROFILE' started (${#SUB_PROFILES[@]} containers)"
  exit 0
fi

parse_profile "$PROFILE"

echo "=== Start: $PROFILE ==="
echo "  $PROFILE_DESC ($PROFILE_SPEED)"
echo "  Host: $PROFILE_HOST"
echo "  Container: $CONTAINER"
echo "  Port: $PORT"
echo

# Probe host state — fail closed (exit 3, no changes) on ssh/podman failure.
probe_or_fail "$PROFILE_HOST" "$DRY_RUN"

state=$(probe_state "$CONTAINER")
if [[ "$state" == "absent" ]]; then
  echo "❌ Container $CONTAINER not found on $PROFILE_HOST." >&2
  echo "   Run: setup.sh $PROFILE" >&2
  exit 1
fi

# Running containers that hold our port (other profiles on same host+port)
mapfile -t HOLDERS < <(probe_port_holders "$PORT" "$CONTAINER")

if $DRY_RUN; then
  if [[ "$state" == "running" ]]; then
    if served=$(api_model_ids "$PROFILE_HOST" "$PORT") \
       && { [[ "$ENGINE" == "llamacpp" ]] || grep -qxF "$MODEL_ID" <<< "$served"; }; then
      echo "✅ $CONTAINER is running and the API serves $(echo $served)"
      echo "DRY_RUN_RESULT=CONVERGED"
      exit 0
    fi
    echo "Plan (apply):"
    echo "  - $CONTAINER is running but /v1/models on :$PORT does not serve $MODEL_ID yet — wait for it"
  else
    echo "Plan (apply):"
    for h in "${HOLDERS[@]}"; do [[ -n "$h" ]] && echo "  - stop $h (holds port $PORT)"; done
    echo "  - podman start $CONTAINER (currently $state)"
    echo "  - wait for /v1/models on $PROFILE_HOST:$PORT"
  fi
  echo "DRY_RUN_RESULT=PENDING"
  exit 0
fi

if [[ "$state" == "running" ]]; then
  echo "✅ $CONTAINER is already running"
else
  # Mutual exclusion: stop other containers holding the same host+port
  for h in "${HOLDERS[@]}"; do
    [[ -z "$h" ]] && continue
    echo "  Stopping conflicting $h on port $PORT..."
    stop_rc=0
    stop_out=$(run_on_host "$PROFILE_HOST" "podman stop $h 2>&1") || stop_rc=$?
    if (( stop_rc != 0 )); then
      echo "❌ podman stop $h failed (exit $stop_rc): $stop_out" >&2
      exit "$stop_rc"
    fi
  done

  # run_on_host discards remote stderr (2>/dev/null on ssh). Merge podman's
  # stderr into stdout on the remote side so the real error is surfaced.
  start_rc=0
  start_out=$(run_on_host "$PROFILE_HOST" "podman start $CONTAINER 2>&1") || start_rc=$?
  if (( start_rc != 0 )); then
    echo "❌ podman start failed on $PROFILE_HOST (exit $start_rc):" >&2
    printf '%s\n' "$start_out" | sed 's/^/   /' >&2
    echo "   Diagnose host GPU/driver/CDI state: bash $(dirname "$0")/pre-check.sh $PROFILE_HOST" >&2
    exit "$start_rc"
  fi
  echo "✅ $CONTAINER started on $PROFILE_HOST"
fi

case "$PROFILE" in
  g350m-2k)          WAIT=180 ;;
  g3b-16k)           WAIT=60 ;;
  g8b-spec-128k)     WAIT=600 ;;
  g8b-fp8-spec-128k) WAIT=600 ;;
  *)                 WAIT=300 ;;
esac

wait_for_model "$PROFILE_HOST" "$PORT" "$WAIT"
