#!/usr/bin/env bash
# verify.sh — Read-only checks for goose native gcp_vertex_ai (spec S1–S5).
# Usage: bash verify.sh [--live]   (--live also runs one goose chat; costs a few tokens)
# Exit codes: 0 = all pass, 1 = one or more failed
set -uo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-gcp-provider" "1.0.0" 2>/dev/null || true

CONFIG="${GOOSE_CONFIG:-$HOME/.config/goose/config.yaml}"
VM="${HOME}/.agents/skills/gcp-vertex-models/scripts/models.sh"
DESKTOP="$HOME/.local/share/applications/Goose.desktop"
LIVE=false; [[ "${1:-}" == "--live" ]] && LIVE=true
PASS=0; FAIL=0; STEP=0
check() {
  STEP=$((STEP + 1))
  if [[ "$2" == PASS ]]; then echo "✅ $1"; PASS=$((PASS + 1)); trace_step "$STEP" "check" 0 "$1" 2>/dev/null || true
  else echo "❌ $1"; FAIL=$((FAIL + 1)); trace_step "$STEP" "check" 1 "$1" 2>/dev/null || true; fi
}
val() { awk -v k="$1" '$1==k":"{print $2; exit}' "$CONFIG" | tr -d "'\""; }
MODEL=$(awk '/^  gcp_vertex_ai:/{b=1;next} b&&!/^    /{exit} b&&/^    model:/{print $2;exit}' "$CONFIG")
LOC=$(val GCP_LOCATION); PROJ=$(val GCP_PROJECT_ID)

# S1 config keys
[[ -n "$PROJ" ]] && check "S1a: GCP_PROJECT_ID set ($PROJ)" PASS || check "S1a: GCP_PROJECT_ID set" FAIL
[[ -n "$LOC" ]] && check "S1b: GCP_LOCATION set ($LOC)" PASS || check "S1b: GCP_LOCATION set" FAIL
[[ -n "$MODEL" ]] && check "S1c: providers.gcp_vertex_ai.model set ($MODEL)" PASS || check "S1c: providers.gcp_vertex_ai.model set" FAIL

# S2 credentials (CLI env + Desktop launcher)
if [[ -f "${GOOGLE_APPLICATION_CREDENTIALS:-/nonexistent}" ]] && grep -q '"type": *"service_account"' "$GOOGLE_APPLICATION_CREDENTIALS"; then
  check "S2a: GOOGLE_APPLICATION_CREDENTIALS → service_account key" PASS
else check "S2a: GOOGLE_APPLICATION_CREDENTIALS → service_account key (unset/missing in this shell)" FAIL; fi
if [[ ! -f "$DESKTOP" ]]; then check "S2b: Goose.desktop launcher (not installed — skipped)" PASS
elif grep -q '^Exec=.*GOOGLE_APPLICATION_CREDENTIALS=' "$DESKTOP"; then check "S2b: Goose.desktop Exec passes GOOGLE_APPLICATION_CREDENTIALS" PASS
else check "S2b: Goose.desktop Exec passes GOOGLE_APPLICATION_CREDENTIALS" FAIL; fi

# S3 configured model is usable in the configured region (last probe)
if [[ -n "$MODEL" && -n "$LOC" ]] && bash "$VM" list --json 2>/dev/null | python3 -c '
import sys,json
d=json.load(sys.stdin); m,r=sys.argv[1],sys.argv[2]
hit=[x for x in d["models"] if x["model"]==m]
sys.exit(0 if hit and hit[0]["regions"].get(r)==200 else 1)' "$MODEL" "$LOC"; then
  check "S3: $MODEL returned 200 in $LOC (vertex model list)" PASS
else check "S3: $MODEL usable in ${LOC:-?} per last probe (refresh vertex models?)" FAIL; fi

# S4 informational: is it the strongest?
BEST=$(bash "$VM" default --region "${LOC:-global}" 2>/dev/null | awk '{print $1}')
if [[ -n "$BEST" && "$BEST" == "$MODEL" ]]; then check "S4: configured model is the strongest usable ($BEST)" PASS
else echo "ℹ️  S4: strongest usable is ${BEST:-?}; configured is ${MODEL:-?} (informational)"; fi

# S5 live chat
if $LIVE; then
  OUT=$(cd /tmp && timeout 180 goose run --provider gcp_vertex_ai --no-session -q -t "Reply with exactly: OK" 2>&1 | tail -2)
  grep -q OK <<<"$OUT" && check "S5: goose run --provider gcp_vertex_ai (config default) → OK" PASS || check "S5: goose live chat ($OUT)" FAIL
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
trace_end 2>/dev/null || true
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
