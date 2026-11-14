#!/usr/bin/env bash
# setup.sh — Set the goose native gcp_vertex_ai default model (and GCP_LOCATION)
# from gcp-vertex-models, after a live goose test.
# Usage: bash setup.sh [--apply] [--model M] [--family opus|sonnet|haiku]
#                      [--region R] [--activate] [--skip-test]
# Default = dry run (prints DRY_RUN_RESULT=CONVERGED|PENDING).
# Exit codes: 0 = ok/converged, 1 = failure, 2 = usage error
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-gcp-provider" "1.0.0" 2>/dev/null || true

CONFIG="${GOOSE_CONFIG:-$HOME/.config/goose/config.yaml}"
VM="${HOME}/.agents/skills/gcp-vertex-models/scripts/models.sh"
APPLY=false; MODEL=""; FAMILY=""; REGION=""; ACTIVATE=false; SKIP_TEST=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)     APPLY=true; shift ;;
    --model)     MODEL="${2:?}"; shift 2 ;;
    --family)    FAMILY="${2:?}"; shift 2 ;;
    --region)    REGION="${2:?}"; shift 2 ;;
    --activate)  ACTIVATE=true; shift ;;
    --skip-test) SKIP_TEST=true; shift ;;
    -h|--help)   sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$CONFIG" ]] || { echo "❌ goose config not found: $CONFIG"; exit 1; }
[[ -f "$VM" ]] || { echo "❌ Dependency missing: gcp-vertex-models skill ($VM)"; exit 1; }

# --- Current state (line-level parse; config.yaml is also rewritten by goose Desktop) ---
cur() { python3 - "$CONFIG" "$1" <<'PYEOF'
import sys, re
lines = open(sys.argv[1]).read().split("\n"); key = sys.argv[2]
if key == "model":
    blk = False
    for l in lines:
        if re.match(r"^  gcp_vertex_ai:\s*$", l): blk = True; continue
        if blk and not l.startswith("    "): break
        if blk and re.match(r"^    model:", l): print(l.split(":", 1)[1].strip().strip("'\"")); break
else:
    for l in lines:
        if re.match(rf"^{key}:", l): print(l.split(":", 1)[1].strip().strip("'\"")); break
PYEOF
}
CUR_MODEL=$(cur model); CUR_LOC=$(cur GCP_LOCATION); CUR_PROJ=$(cur GCP_PROJECT_ID); CUR_ACTIVE=$(cur active_provider)
TARGET_LOC="${REGION:-${CUR_LOC:-global}}"
echo "Current: model=${CUR_MODEL:-<unset>} GCP_LOCATION=${CUR_LOC:-<unset>} GCP_PROJECT_ID=${CUR_PROJ:-<unset>} active_provider=${CUR_ACTIVE:-<unset>}"

# --- Preconditions goose gcp_vertex_ai needs ---
FAIL=0
[[ -n "$CUR_PROJ" ]] || { echo "❌ GCP_PROJECT_ID not set in $CONFIG"; FAIL=1; }
if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" || ! -f "${GOOGLE_APPLICATION_CREDENTIALS:-/nonexistent}" ]]; then
  echo "❌ GOOGLE_APPLICATION_CREDENTIALS unset or missing in this shell (goose reads it from the process env, not ~/.config/goose/.env)"; FAIL=1
fi
DESKTOP="$HOME/.local/share/applications/Goose.desktop"
if [[ -f "$DESKTOP" ]] && ! grep -q '^Exec=.*GOOGLE_APPLICATION_CREDENTIALS=' "$DESKTOP"; then
  echo "⚠️  $DESKTOP Exec line lacks GOOGLE_APPLICATION_CREDENTIALS — Desktop will fall back to user ADC"
fi
[[ $FAIL -eq 0 ]] || exit 1
trace_step 1 "preconditions" 0 "loc=$TARGET_LOC" 2>/dev/null || true

# --- Pick the model: explicit, else strongest usable in the target region ---
if [[ -z "$MODEL" ]]; then
  set +e
  PICK=$(bash "$VM" default --region "$TARGET_LOC" ${FAMILY:+--family "$FAMILY"} 2>/tmp/goose-gcp-rank.$$)
  rc=$?
  set -e
  cat /tmp/goose-gcp-rank.$$ | sed 's/^/  /'; rm -f /tmp/goose-gcp-rank.$$
  if [[ $rc -ne 0 || -z "$PICK" ]]; then
    echo "❌ No model from gcp-vertex-models for region $TARGET_LOC — run: refresh vertex models"; exit 1
  fi
  MODEL="${PICK%% *}"
else
  # Explicit model must have returned 200 in the target region (if the cache knows it)
  if ! bash "$VM" list --json 2>/dev/null | python3 -c '
import sys,json
d=json.load(sys.stdin); m,r=sys.argv[1],sys.argv[2]
hit=[x for x in d["models"] if x["model"]==m]
sys.exit(0 if not hit or hit[0]["regions"].get(r)==200 else 1)' "$MODEL" "$TARGET_LOC"; then
    echo "❌ $MODEL did not return 200 in $TARGET_LOC in the last probe (vertex model list)"; exit 1
  fi
fi
echo "Target:  model=$MODEL GCP_LOCATION=$TARGET_LOC$($ACTIVATE && echo " active_provider=gcp_vertex_ai")"
trace_step 2 "pick" 0 "$MODEL $TARGET_LOC" 2>/dev/null || true

# --- Convergence ---
if [[ "$CUR_MODEL" == "$MODEL" && "$CUR_LOC" == "$TARGET_LOC" ]] && { ! $ACTIVATE || [[ "$CUR_ACTIVE" == gcp_vertex_ai ]]; }; then
  echo "DRY_RUN_RESULT=CONVERGED"
  echo "✅ goose gcp_vertex_ai already set to $MODEL ($TARGET_LOC)"
  trace_end 2>/dev/null || true; exit 0
fi
echo "Changes:"
[[ "$CUR_MODEL" != "$MODEL" ]] && echo "  providers.gcp_vertex_ai.model: ${CUR_MODEL:-<unset>} → $MODEL"
[[ "$CUR_LOC" != "$TARGET_LOC" ]] && echo "  GCP_LOCATION: ${CUR_LOC:-<unset>} → $TARGET_LOC"
$ACTIVATE && [[ "$CUR_ACTIVE" != gcp_vertex_ai ]] && echo "  active_provider: ${CUR_ACTIVE:-<unset>} → gcp_vertex_ai"
if ! $APPLY; then
  echo "DRY_RUN_RESULT=PENDING"
  echo "ℹ️  Re-run with --apply to test and write"
  trace_end 2>/dev/null || true; exit 0
fi

# --- Live test before writing (GCP_LOCATION env override = target region) ---
if ! $SKIP_TEST; then
  OUT=$(cd /tmp && GCP_LOCATION="$TARGET_LOC" timeout 180 goose run --provider gcp_vertex_ai --model "$MODEL" \
          --no-session -q -t "Reply with exactly: OK" 2>&1 | tail -3) || true
  if ! grep -q 'OK' <<<"$OUT"; then
    echo "❌ goose test failed for $MODEL ($TARGET_LOC) — config NOT changed"; echo "$OUT" | sed 's/^/  /'
    trace_step 3 "test" 1 "$MODEL" 2>/dev/null || true; trace_end 2>/dev/null || true; exit 1
  fi
  echo "✅ goose run --provider gcp_vertex_ai --model $MODEL → OK"
fi
trace_step 3 "test" 0 "$MODEL" 2>/dev/null || true

# --- Write: backup, then edit only the target lines (re-read right before writing) ---
BACKUP="$CONFIG.bak.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG" "$BACKUP"
python3 - "$CONFIG" "$MODEL" "$TARGET_LOC" "$ACTIVATE" <<'PYEOF'
import sys, re, os
p, model, loc, activate = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"
L = open(p).read().split("\n")
blk = False; m_done = loc_done = act_done = False; prov_idx = None; blk_idx = None
for i, l in enumerate(L):
    if re.match(r"^providers:\s*$", l): prov_idx = i
    if re.match(r"^  gcp_vertex_ai:\s*$", l): blk = True; blk_idx = i; continue
    if blk and not l.startswith("    "): blk = False
    if blk and re.match(r"^    model:", l): L[i] = f"    model: {model}"; m_done = True
    if re.match(r"^GCP_LOCATION:", l): L[i] = f"GCP_LOCATION: {loc}"; loc_done = True
    if activate and re.match(r"^active_provider:", l): L[i] = "active_provider: gcp_vertex_ai"; act_done = True
if not m_done:
    if blk_idx is not None:
        L.insert(blk_idx + 1, f"    model: {model}")
    else:
        if prov_idx is None:
            L.append("providers:"); prov_idx = len(L) - 1
        L[prov_idx + 1:prov_idx + 1] = ["  gcp_vertex_ai:", "    enabled: true", f"    model: {model}", "    configured: true"]
if not loc_done:
    L.insert(0, f"GCP_LOCATION: {loc}")
if activate and not act_done:
    L.append("active_provider: gcp_vertex_ai")
tmp = p + ".tmp"
open(tmp, "w").write("\n".join(L))
os.replace(tmp, p)
PYEOF
NEW_MODEL=$(cur model); NEW_LOC=$(cur GCP_LOCATION)
if [[ "$NEW_MODEL" != "$MODEL" || "$NEW_LOC" != "$TARGET_LOC" ]]; then
  cp "$BACKUP" "$CONFIG"
  echo "❌ Post-write check failed (model=$NEW_MODEL loc=$NEW_LOC) — backup restored"; exit 1
fi
echo "✅ Updated $CONFIG (backup: $BACKUP)"
echo "ℹ️  Goose Desktop: restart it, or pick GCP Vertex AI → type '$MODEL' in the model switcher"
echo "   (the built-in picker list is compiled into goose and does not show newer models)"
trace_step 4 "write" 0 "$MODEL $TARGET_LOC" 2>/dev/null || true
trace_end 2>/dev/null || true
