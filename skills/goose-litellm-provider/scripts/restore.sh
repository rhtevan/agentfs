#!/usr/bin/env bash
# restore.sh — Restore the RedHat custom provider for Goose
# Usage: bash restore.sh [--dry-run] [--default-model MODEL] [--fast-model MODEL] [--no-default]
#   --dry-run          Show changes, write nothing (DRY_RUN_RESULT=CONVERGED|PENDING)
#   --default-model M  providers.custom_redhat.model (default: strongest served model)
#   --fast-model M     fast_model in the provider JSON (default: claude-haiku-4-5)
#   --no-default       Do not touch providers.custom_redhat.model in config.yaml
# Env: LITELLM_URL (default http://127.0.0.1:4000), GOOSE_CONFIG_DIR (default ~/.config/goose)
# Models list: generated from live LiteLLM /model/info, ranked opus > sonnet > haiku, newest first.
# Never changes active_provider.
# Exit codes: 0 = success/converged, 1 = failure, 2 = usage error
set -euo pipefail

# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-litellm-provider" "1.11.0" 2>/dev/null || true

DRY_RUN=false
FAST_MODEL="claude-haiku-4-5"
DEFAULT_MODEL=""   # empty → strongest served model
SET_DEFAULT=true
LITELLM_URL="${LITELLM_URL:-http://127.0.0.1:4000}"
PROXY_MODELS="$HOME/.agents/skills/litellm-proxy-status/scripts/models.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true; shift ;;
    --fast-model)    FAST_MODEL="${2:?--fast-model needs a value}"; shift 2 ;;
    --default-model) DEFAULT_MODEL="${2:?--default-model needs a value}"; shift 2 ;;
    --no-default)    SET_DEFAULT=false; shift ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
PROVIDER_DIR="$GOOSE_CONFIG_DIR/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_redhat.json"
CONFIG_YAML="$GOOSE_CONFIG_DIR/config.yaml"

# --- Step 1: models from the live proxy (fallback: existing JSON) ---
trace_step 1 "discover_models" 0 "url=$LITELLM_URL" 2>/dev/null || true
MODELS_JSON="$(LITELLM_URL="$LITELLM_URL" PROVIDER_FILE="$PROVIDER_FILE" python3 - << 'PYEOF'
import json, os, sys, urllib.request
url = os.environ["LITELLM_URL"].rstrip("/") + "/model/info"
out = {}
try:
    for m in json.load(urllib.request.urlopen(url, timeout=10))["data"]:
        out[m["model_name"]] = (m.get("model_info") or {}).get("max_input_tokens") or 200000
    src = "live proxy"
except Exception:
    try:
        out = {m["name"]: m["context_limit"] for m in json.load(open(os.environ["PROVIDER_FILE"]))["models"]}
        src = "existing provider JSON (proxy unreachable)"
    except Exception:
        sys.exit(0)
def key(name):
    # opus > sonnet > haiku; within a family newest first (5-5 > 5 > 4-8 ...)
    p = name.split("-")
    fam = {"opus": 0, "sonnet": 1, "haiku": 2}.get(p[1] if len(p) > 1 else "", 9)
    try:
        ver = [int(x) for x in p[2:]]
    except ValueError:
        ver = []
    ver += [0] * (4 - len(ver))
    return (fam, [-v for v in ver], name)
models = [{"name": n, "context_limit": out[n], "input_token_cost": None, "output_token_cost": None,
           "currency": None, "supports_cache_control": None, "reasoning": False}
          for n in sorted(out, key=key)]
print(json.dumps(models, indent=4))
print("models source: " + src, file=sys.stderr)
PYEOF
)"
if [[ -z "$MODELS_JSON" ]]; then
  echo "❌ LiteLLM proxy unreachable at $LITELLM_URL and no existing provider JSON to reuse." >&2
  echo "   Start it: systemctl --user start litellm-proxy" >&2
  exit 1
fi
NAMES=$(python3 -c 'import json,sys; print("\n".join(m["name"] for m in json.loads(sys.stdin.read())))' <<< "$MODELS_JSON")
echo "Models (ranked): $(echo "$NAMES" | tr '\n' ' ')"

# --- Step 2: default + fast model ---
trace_step 2 "pick_models" 0 "" 2>/dev/null || true
PROXY_UP=false
curl -sf --max-time 5 "$LITELLM_URL/v1/models" >/dev/null 2>&1 && PROXY_UP=true
if $SET_DEFAULT && ! $PROXY_UP; then
  # Cannot confirm what is served or chat-test a new default → leave the model line alone
  SET_DEFAULT=false
  DEFAULT_MODEL="${DEFAULT_MODEL:-$(echo "$NAMES" | head -1)}"
  echo "ℹ️  Proxy unreachable — default model not managed this run (providers.custom_redhat.model left as is)"
elif [[ -z "$DEFAULT_MODEL" ]]; then
  CAND=""
  if [[ -f "$PROXY_MODELS" ]] && CAND=$(bash "$PROXY_MODELS" default --url "$LITELLM_URL" 2>/dev/null) \
     && grep -qx "$CAND" <<< "$NAMES"; then
    DEFAULT_MODEL="$CAND"
  else
    DEFAULT_MODEL=$(echo "$NAMES" | head -1)
    echo "⚠️  litellm-proxy-status models.sh unavailable — using first ranked model"
  fi
  echo "Default model (strongest served): $DEFAULT_MODEL"
elif ! grep -qx "$DEFAULT_MODEL" <<< "$NAMES"; then
  echo "❌ Default model '$DEFAULT_MODEL' is not served by the proxy." >&2
  exit 1
else
  echo "Default model (requested): $DEFAULT_MODEL"
fi
if ! grep -qx "$FAST_MODEL" <<< "$NAMES"; then
  echo "❌ Fast model '$FAST_MODEL' is not served by the proxy — pick one with --fast-model." >&2
  exit 1
fi

# --- Step 3: compare with current state ---
trace_step 3 "plan" 0 "dry_run=$DRY_RUN" 2>/dev/null || true
TARGET_JSON="$(MODELS_JSON="$MODELS_JSON" FAST="$FAST_MODEL" python3 - << 'PYEOF'
import json, os
print(json.dumps({
  "name": "custom_redhat", "engine": "openai", "display_name": "RedHat",
  "description": "Local LiteLLM proxy to Vertex AI (Claude models; list generated from the live proxy)",
  "api_key_env": "", "base_url": "http://host.containers.internal:4000",
  "models": json.loads(os.environ["MODELS_JSON"]),
  "headers": None, "timeout_seconds": 600, "supports_streaming": True, "requires_auth": False,
  "catalog_provider_id": None, "base_path": None, "env_vars": None, "dynamic_models": None,
  "skip_canonical_filtering": False, "model_doc_link": None, "setup_steps": [],
  "fast_model": os.environ["FAST"], "preserves_thinking": True}, indent=2))
PYEOF
)"
JSON_SAME=false
if [[ -f "$PROVIDER_FILE" ]] && python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])) == json.loads(sys.argv[2]) else 1)' "$PROVIDER_FILE" "$TARGET_JSON" 2>/dev/null; then
  JSON_SAME=true
fi

CUR_MODEL=""; HAS_ENTRY=false
if [[ -f "$CONFIG_YAML" ]]; then
  CUR_MODEL=$(CFG="$CONFIG_YAML" python3 -c '
import os, yaml
p = ((yaml.safe_load(open(os.environ["CFG"])) or {}).get("providers") or {}).get("custom_redhat")
print("__NONE__" if p is None else (p.get("model") or ""))')
  [[ "$CUR_MODEL" != "__NONE__" ]] && HAS_ENTRY=true
  [[ "$CUR_MODEL" == "__NONE__" ]] && CUR_MODEL=""
fi
echo "Current: providers.custom_redhat.model=${CUR_MODEL:-<unset>}  active_provider=$(grep -m1 '^active_provider:' "$CONFIG_YAML" 2>/dev/null | awk '{print $2}' || true)"

CHANGES=()
$JSON_SAME || CHANGES+=("$( [[ -f "$PROVIDER_FILE" ]] && echo update || echo create ) $PROVIDER_FILE ($(echo "$NAMES" | wc -l) models, fast_model $FAST_MODEL)")
DEFAULT_PENDING=false
if $SET_DEFAULT && $HAS_ENTRY && [[ "$CUR_MODEL" != "$DEFAULT_MODEL" ]]; then
  CHANGES+=("providers.custom_redhat.model: ${CUR_MODEL:-<unset>} → $DEFAULT_MODEL")
  DEFAULT_PENDING=true
fi

if [[ ${#CHANGES[@]} -eq 0 ]]; then
  echo "DRY_RUN_RESULT=CONVERGED"
  echo "✅ custom_redhat already matches the proxy$($SET_DEFAULT && $HAS_ENTRY && echo " (default $DEFAULT_MODEL)"). No changes needed."
  $HAS_ENTRY || echo "⚠️  config.yaml has no custom_redhat entry — see SKILL.md Reference Configuration."
  exit 0
fi
echo "Changes:"
printf '  %s\n' "${CHANGES[@]}"
if $DRY_RUN; then
  echo "DRY_RUN_RESULT=PENDING"
  exit 0
fi

# --- Step 4: apply ---
trace_step 4 "apply" 0 "" 2>/dev/null || true
STAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$PROVIDER_DIR"

if $DEFAULT_PENDING; then
  # Live check through the proxy before pointing goose at the model
  if ! curl -sf -m 90 "$LITELLM_URL/v1/chat/completions" -H 'Content-Type: application/json' \
       -d "{\"model\":\"$DEFAULT_MODEL\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"Reply OK\"}]}" >/dev/null; then
    echo "❌ $DEFAULT_MODEL failed a chat test through $LITELLM_URL — nothing written." >&2
    exit 1
  fi
  echo "✅ Chat test via proxy: $DEFAULT_MODEL → OK"
fi

if ! $JSON_SAME; then
  [[ -f "$PROVIDER_FILE" ]] && cp -p "$PROVIDER_FILE" "$PROVIDER_FILE.bak.$STAMP" && echo "📋 Backup: $PROVIDER_FILE.bak.$STAMP"
  printf '%s\n' "$TARGET_JSON" > "$PROVIDER_FILE.tmp"
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PROVIDER_FILE.tmp" || { rm -f "$PROVIDER_FILE.tmp"; echo "❌ generated JSON invalid" >&2; exit 1; }
  mv "$PROVIDER_FILE.tmp" "$PROVIDER_FILE"
  echo "✅ Provider JSON written: $PROVIDER_FILE"
fi

if $DEFAULT_PENDING; then
  # Line-level edit of providers.custom_redhat.model only; config re-read right before
  # writing (Goose Desktop may rewrite config.yaml), backup + post-check.
  cp -p "$CONFIG_YAML" "$CONFIG_YAML.bak.$STAMP"
  echo "📋 Backup: $CONFIG_YAML.bak.$STAMP"
  CFG="$CONFIG_YAML" DM="$DEFAULT_MODEL" python3 - << 'PYEOF' || { cp -p "$CONFIG_YAML.bak.$STAMP" "$CONFIG_YAML"; echo "❌ config edit failed — backup restored" >&2; exit 1; }
import os, re, shutil, sys, yaml
path, dm = os.environ["CFG"], os.environ["DM"]
text = open(path).read()
before = yaml.safe_load(text)
lines = text.splitlines(keepends=True)
pi = next(i for i, l in enumerate(lines) if l.rstrip("\n") == "providers:")
ci = next(i for i in range(pi + 1, len(lines)) if re.match(r"^  custom_redhat:\s*$", lines[i]))
done = False
for j in range(ci + 1, len(lines)):
    l = lines[j]
    if l.strip() and len(l) - len(l.lstrip(" ")) <= 2:
        break
    m = re.match(r"^(    model:)\s*\S.*$", l.rstrip("\n"))
    if m:
        lines[j] = "%s %s\n" % (m.group(1), dm); done = True; break
if not done:
    lines.insert(ci + 1, "    model: %s\n" % dm)
new_text = "".join(lines)
after = yaml.safe_load(new_text)
exp = before; exp["providers"]["custom_redhat"]["model"] = dm
if after != exp:
    print("❌ post-check: unexpected change", file=sys.stderr); sys.exit(1)
tmp = path + ".tmp"; open(tmp, "w").write(new_text); shutil.copymode(path, tmp); os.replace(tmp, path)
print("✅ config.yaml: providers.custom_redhat.model = %s" % dm)
PYEOF
fi

echo ""
echo "Default model (config.yaml): $DEFAULT_MODEL$($SET_DEFAULT || echo " (not applied this run)")"
echo "Fast model (provider JSON):  $FAST_MODEL"
echo "ℹ️  Goose Desktop: restart it, or pick RedHat via the Recent entry / type '$DEFAULT_MODEL' (Desktop guesses claude-sonnet-4-6 on a provider switch — gotcha #1)"
trace_end 2>/dev/null || true
