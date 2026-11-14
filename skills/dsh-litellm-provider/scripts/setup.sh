#!/usr/bin/env bash
# setup.sh — Configure DSH with the local LiteLLM proxy provider
# Usage: bash setup.sh [--dry-run] [--default-model MODEL] [--no-default] [--force-default]
#   --dry-run          Show changes, write nothing (DRY_RUN_RESULT=CONVERGED|PENDING)
#   --default-model M  DSH default model (default: strongest served model)
#   --no-default       Do not touch the agent-default-model section
#   --force-default    Set agent-default-model even if it points at another provider
# Env: DSH_HOME (default ~/.dsh), LITELLM_URL (default http://127.0.0.1:4000)
# Exit codes: 0 = ok/converged, 1 = failure, 2 = usage error
#
# Writes two blocks in $DSH_HOME/settings.yaml, line-level (other lines kept):
#   llm-pi-ai.providers.litellm-vertex-ai  — models = live /v1/models, ranked
#   agent-default-model                    — {provider: litellm-vertex-ai, model: M}
# DSH serves only the models listed in settings.yaml (no runtime discovery).
set -euo pipefail

# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "dsh-litellm-provider" "1.2.0" 2>/dev/null || true

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
SETTINGS="$DSH_HOME/settings.yaml"
LITELLM_URL="${LITELLM_URL:-http://127.0.0.1:4000}"
PROVIDER_ID="litellm-vertex-ai"
PROXY_MODELS="$HOME/.agents/skills/litellm-proxy-status/scripts/models.sh"
RANKER="$HOME/.agents/skills/gcp-vertex-models/scripts/models.sh"

DRY_RUN=false
DEFAULT_MODEL=""
SET_DEFAULT=true
FORCE_DEFAULT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --default-model) DEFAULT_MODEL="${2:?--default-model needs a value}"; shift 2 ;;
    --no-default) SET_DEFAULT=false; shift ;;
    --force-default) FORCE_DEFAULT=true; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- Step 1: LiteLLM proxy reachable ---
trace_step 1 "check_proxy" 0 "url=$LITELLM_URL" 2>/dev/null || true
if ! curl -s --connect-timeout 3 "$LITELLM_URL/health" >/dev/null 2>&1; then
  echo "❌ LiteLLM proxy not reachable at $LITELLM_URL" >&2
  echo "   Start it first (see skill: litellm-vertex-ai-proxy)" >&2
  exit 1
fi
echo "✅ LiteLLM proxy is healthy ($LITELLM_URL)"

# --- Step 2: Discover + rank models ---
trace_step 2 "discover_models" 0 "" 2>/dev/null || true
MODEL_IDS=$(curl -s "$LITELLM_URL/v1/models" 2>/dev/null | python3 -c "
import sys, json
for m in sorted(json.load(sys.stdin).get('data', []), key=lambda x: x['id']):
    print(m['id'])
" 2>/dev/null || true)
if [[ -z "$MODEL_IDS" ]]; then
  echo "❌ No models found at $LITELLM_URL/v1/models" >&2
  exit 1
fi
if [[ -f "$RANKER" ]]; then
  RANKED=$(printf '%s\n' "$MODEL_IDS" | bash "$RANKER" rank 2>/dev/null || true)
  # rank drops unknown families; keep them at the end
  [[ -n "$RANKED" ]] && MODEL_IDS=$(printf '%s\n%s\n' "$RANKED" "$MODEL_IDS" | awk 'NF && !s[$0]++')
fi
echo "   Live models (ranked): $(echo "$MODEL_IDS" | tr '\n' ' ')"

# --- Step 3: Default model ---
trace_step 3 "default_model" 0 "" 2>/dev/null || true
if [[ -z "$DEFAULT_MODEL" ]]; then
  [[ -f "$PROXY_MODELS" ]] && DEFAULT_MODEL=$(bash "$PROXY_MODELS" default --url "$LITELLM_URL" 2>/dev/null || true)
  if [[ -z "$DEFAULT_MODEL" ]]; then
    DEFAULT_MODEL=$(echo "$MODEL_IDS" | head -1)
    echo "⚠️  litellm-proxy-status models.sh unavailable — using first ranked model"
  fi
  echo "   Default model (strongest served): $DEFAULT_MODEL"
elif ! echo "$MODEL_IDS" | grep -qx "$DEFAULT_MODEL"; then
  echo "❌ Default model '$DEFAULT_MODEL' is not served by the proxy." >&2
  exit 1
else
  echo "   Default model (requested): $DEFAULT_MODEL"
fi

# --- Step 4: Compute + apply ---
trace_step 4 "apply" 0 "dry_run=$DRY_RUN" 2>/dev/null || true
mkdir -p "$DSH_HOME"
[[ -f "$SETTINGS" ]] || : > "$SETTINGS"

set +e
SETTINGS="$SETTINGS" PROV="$PROVIDER_ID" URL="$LITELLM_URL/v1" MODELS="$MODEL_IDS" DM="$DEFAULT_MODEL" \
SET_DEFAULT="$SET_DEFAULT" FORCE_DEFAULT="$FORCE_DEFAULT" DRY_RUN="$DRY_RUN" python3 << 'PYEOF'
import os, sys, shutil, time, yaml
path, prov, url, dm = os.environ["SETTINGS"], os.environ["PROV"], os.environ["URL"], os.environ["DM"]
models = [m for m in os.environ["MODELS"].split("\n") if m]
set_default = os.environ["SET_DEFAULT"] == "true"
force = os.environ["FORCE_DEFAULT"] == "true"
dry = os.environ["DRY_RUN"] == "true"

text = open(path).read()
cur = yaml.safe_load(text) or {}
cur_prov = ((cur.get("llm-pi-ai") or {}).get("providers") or {}).get(prov) or {}
cur_def = cur.get("agent-default-model") or {}

target_prov = {"apiKeyEnv": "LITELLM_VERTEX_AI_API_KEY", "api": "openai-completions", "baseURL": url,
               "compat": {"supportsDeveloperRole": False, "maxTokensField": "max_tokens"},
               "models": [{"id": m, "input": ["text", "image"]} for m in models]}
target_def = {"provider": prov, "model": dm}
if cur_def.get("reasoningEffort"):
    target_def["reasoningEffort"] = cur_def["reasoningEffort"]

changes = []
if cur_prov != target_prov:
    cur_ids = [m.get("id") for m in cur_prov.get("models") or []]
    add = [m for m in models if m not in cur_ids]; gone = [m for m in cur_ids if m not in models]
    changes.append("provider %s: models %d → %d (add: %s; remove: %s)%s" % (
        prov, len(cur_ids), len(models), " ".join(add) or "-", " ".join(gone) or "-",
        "" if (add or gone) else " [order/fields]"))
do_default = set_default
if set_default and cur_def.get("provider") not in (None, prov) and not force:
    print("ℹ️  agent-default-model points at provider '%s' — left unchanged (use --force-default)" % cur_def.get("provider"))
    do_default = False
if do_default and cur_def != target_def:
    changes.append("agent-default-model: %s/%s → %s/%s" % (cur_def.get("provider"), cur_def.get("model"), prov, dm))

print("Current default: %s/%s" % (cur_def.get("provider"), cur_def.get("model")))
if not changes:
    print("DRY_RUN_RESULT=CONVERGED")
    print("✅ DSH already lists the live models%s. No changes needed." % (
        " with default %s" % dm if do_default else " (default model not managed)"))
    sys.exit(0)
print("Changes:")
for c in changes:
    print("  " + c)
if dry:
    print("DRY_RUN_RESULT=PENDING")
    sys.exit(0)

# ---- line-level block replacement ----
lines = text.splitlines(keepends=True)
if lines and not lines[-1].endswith("\n"):
    lines[-1] += "\n"

def end_of(i, indent):
    j = i + 1
    while j < len(lines):
        l = lines[j]
        if l.strip() and not l.lstrip().startswith("#") and len(l) - len(l.lstrip(" ")) <= indent:
            break
        j += 1
    return j

def find(start, stop, exact):
    return next((i for i in range(start, stop) if lines[i].rstrip("\n") == exact), None)

prov_blk = ("    %s:\n      apiKeyEnv: LITELLM_VERTEX_AI_API_KEY\n      api: openai-completions\n"
            "      baseURL: %s\n      compat:\n        supportsDeveloperRole: false\n"
            "        maxTokensField: max_tokens\n      models:\n" % (prov, url)
            + "".join("        - id: %s\n          input: [ text, image ]\n" % m for m in models))

if cur_prov != target_prov:
    li = find(0, len(lines), "llm-pi-ai:")
    if li is None:
        lines += ["llm-pi-ai:\n", "  providers:\n", prov_blk]
    else:
        le = end_of(li, 0)
        pi = find(li + 1, le, "  providers:")
        if pi is None:
            lines[le:le] = ["  providers:\n", prov_blk]
        else:
            ci = find(pi + 1, end_of(pi, 2), "    %s:" % prov)
            if ci is None:
                lines.insert(pi + 1, prov_blk)
            else:
                lines[ci:end_of(ci, 4)] = [prov_blk]

if do_default and cur_def != target_def:
    def_blk = "agent-default-model:\n  provider: %s\n  model: %s\n" % (prov, dm)
    if "reasoningEffort" in target_def:
        def_blk += "  reasoningEffort: %s\n" % target_def["reasoningEffort"]
    di = find(0, len(lines), "agent-default-model:")
    if di is None:
        lines.append(def_blk)
    else:
        lines[di:end_of(di, 0)] = [def_blk]

new_text = "".join(lines)
new = yaml.safe_load(new_text) or {}
ok = ((new.get("llm-pi-ai") or {}).get("providers") or {}).get(prov) == target_prov
if do_default:
    ok = ok and new.get("agent-default-model") == target_def
for k in set(cur) | set(new):
    if k in ("llm-pi-ai", "agent-default-model"):
        continue
    if cur.get(k) != new.get(k):
        ok = False; print("❌ unexpected change in top-level key: %s" % k)
cp = dict(((cur.get("llm-pi-ai") or {}).get("providers") or {})); cp.pop(prov, None)
np = dict(((new.get("llm-pi-ai") or {}).get("providers") or {})); np.pop(prov, None)
if cp != np:
    ok = False; print("❌ unexpected change in other llm-pi-ai providers")
if not do_default and cur.get("agent-default-model") != new.get("agent-default-model"):
    ok = False; print("❌ agent-default-model changed unexpectedly")
if not ok:
    print("❌ post-check failed — settings not written")
    sys.exit(1)

if text:
    backup = "%s.bak.%s" % (path, time.strftime("%Y%m%d_%H%M%S"))
    shutil.copy2(path, backup)
    print("📋 Backup: %s" % backup)
tmp = path + ".tmp"
open(tmp, "w").write(new_text)
shutil.copymode(path, tmp)
os.replace(tmp, path)
print("✅ Updated %s" % path)
PYEOF
RC=$?
set -e
[[ $RC -ne 0 ]] && exit 1
$DRY_RUN && exit 0

# DSH requires a non-empty apiKeyEnv even for this unauthenticated proxy. The
# value comes from the DSH launcher (dsh-setup install-desktop.sh sets
# LITELLM_VERTEX_AI_API_KEY=sk-litellm-local-no-auth); exporting it here has no effect.
echo ""
echo "🎉 DSH provider $PROVIDER_ID: $(echo "$MODEL_IDS" | wc -l) models, default $DEFAULT_MODEL"
echo "   Restart DSH if it is running to pick up the provider model list."
trace_end 2>/dev/null || true
