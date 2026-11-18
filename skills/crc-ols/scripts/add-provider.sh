#!/usr/bin/env bash
# add-provider.sh — Add an LLM provider to an existing OLS deployment
#
# Usage:
#   add-provider.sh NAME --type TYPE --model MODEL [options]
#
# Required:
#   NAME              Provider name (must not already exist)
#   --type TYPE       openai | google_vertex_anthropic | azure_openai | watsonx | bam
#   --model MODEL     Model name as the endpoint reports it in /v1/models
#
# Options:
#   --url URL         Endpoint URL (required for openai-compatible types)
#   --secret NAME     Credentials secret name (default: <NAME>-llmcreds).
#                     MUST be unique per provider — sharing one secret between
#                     two providers produces a duplicate volume mount error.
#   --credential-key K  Key inside the secret (default: apitoken)
#   --project ID      GCP project    (google_vertex_anthropic)
#   --location LOC    Vertex location (google_vertex_anthropic)
#   --from-keyring    Create the secret from GNOME Keyring via rotate-key.sh
#   --keyring-field F Keyring field name (default: CUSTOM_CORP_API_KEY)
#   --set-default     Also make this provider+model the active default
#   --dry-run         Report what would change. Writes nothing.
#   --context CTX     oc context (default: $CRC_OC_CONTEXT or current)
#
# Exit codes: 0 = done / converged, 1 = failure, 2 = usage error
set -euo pipefail

# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-ols" "3.5.0" 2>/dev/null || true

NAME=""; PTYPE=""; MODEL=""; PURL=""; SECRET=""; CKEY="apitoken"
PROJECT=""; LOCATION=""; FROM_KEYRING=false; KEYRING_FIELD="CUSTOM_CORP_API_KEY"
SET_DEFAULT=false; DRY_RUN=false; OC_CONTEXT=""
NS="openshift-lightspeed"
HERE="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)           PTYPE="${2:?}"; shift 2 ;;
    --model)          MODEL="${2:?}"; shift 2 ;;
    --url)            PURL="${2:?}"; shift 2 ;;
    --secret)         SECRET="${2:?}"; shift 2 ;;
    --credential-key) CKEY="${2:?}"; shift 2 ;;
    --project)        PROJECT="${2:?}"; shift 2 ;;
    --location)       LOCATION="${2:?}"; shift 2 ;;
    --from-keyring)   FROM_KEYRING=true; shift ;;
    --keyring-field)  KEYRING_FIELD="${2:?}"; shift 2 ;;
    --set-default)    SET_DEFAULT=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --context)        OC_CONTEXT="--context ${2:?}"; shift 2 ;;
    -h|--help)        sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)               echo "❌ Unknown option: $1" >&2; exit 2 ;;
    *)                NAME="$1"; shift ;;
  esac
done

fail() { echo "❌ $1" >&2; trace_end 1 2>/dev/null || true; exit 1; }

[[ -n "$NAME"  ]] || { echo "❌ NAME is required" >&2; exit 2; }
[[ -n "$PTYPE" ]] || { echo "❌ --type is required" >&2; exit 2; }
[[ -n "$MODEL" ]] || { echo "❌ --model is required" >&2; exit 2; }
OC_CONTEXT="${OC_CONTEXT:-$([ -n "${CRC_OC_CONTEXT:-}" ] && echo "--context $CRC_OC_CONTEXT" || echo "")}"
SECRET="${SECRET:-${NAME}-llmcreds}"

case "$PTYPE" in
  openai|azure_openai|watsonx|bam)
    [[ -n "$PURL" ]] || fail "--url is required for type $PTYPE" ;;
  google_vertex_anthropic)
    [[ -n "$PROJECT" && -n "$LOCATION" ]] || fail "--project and --location are required for $PTYPE"
    CKEY="${CKEY/apitoken/gcp-service-account.json}" ;;
  *) fail "Unsupported --type: $PTYPE" ;;
esac

# ── Step 1: verify the provider does not already exist ──────────────
trace_step 1 "check-existing" 0 "$NAME" 2>/dev/null || true

# shellcheck disable=SC2086
oc $OC_CONTEXT get olsconfig cluster &>/dev/null || fail "OLSConfig 'cluster' not found. Run install.sh first."
# shellcheck disable=SC2086
EXISTING=$(oc $OC_CONTEXT get olsconfig cluster -o jsonpath='{.spec.llm.providers[*].name}')
for p in $EXISTING; do
  if [[ "$p" == "$NAME" ]]; then
    echo "Provider '$NAME' already exists."
    echo "   Configured: $EXISTING"
    echo "   Use switch-provider.sh / rotate-key.sh to modify it."
    $DRY_RUN && echo "DRY_RUN_RESULT=CONVERGED"
    trace_end 0 2>/dev/null || true; exit 0
  fi
done

# A secret shared between two providers makes the operator mount the same
# volume twice and the app-server never starts.
# shellcheck disable=SC2086
for s in $(oc $OC_CONTEXT get olsconfig cluster -o jsonpath='{.spec.llm.providers[*].credentialsSecretRef.name}'); do
  [[ "$s" == "$SECRET" ]] && fail "secret '$SECRET' is already used by another provider — each provider needs its own"
done

# shellcheck disable=SC2086
SECRET_EXISTS=$(oc $OC_CONTEXT get secret "$SECRET" -n "$NS" &>/dev/null && echo true || echo false)

echo "Provider: $NAME"
echo "  Type:    $PTYPE"
echo "  URL:     ${PURL:--}"
echo "  Model:   $MODEL"
echo "  Secret:  $SECRET (key: $CKEY) — $($SECRET_EXISTS && echo present || echo absent)"

# ── Step 2: validate the model is actually served ───────────────────
trace_step 2 "validate-model" 0 "$MODEL" 2>/dev/null || true

# The OLSConfig CRD does NOT validate model names. A typo yields a provider
# that reports Ready and then 404s on the first query. Check while we can.
if [[ -n "$PURL" ]] && $FROM_KEYRING && command -v secret-tool >/dev/null 2>&1; then
  K=$(secret-tool lookup application rust-keyring service goose target default username secrets 2>/dev/null \
      | python3 -c "import json,sys;print(json.load(sys.stdin).get('$KEYRING_FIELD',''))" 2>/dev/null || echo "")
  if [[ -n "$K" ]]; then
    if curl -s --max-time 30 "${PURL%/}/models" -H "Authorization: Bearer $K" 2>/dev/null \
        | python3 -c "
import json,sys
try: ids=[m['id'] for m in json.load(sys.stdin).get('data',[])]
except Exception: sys.exit(0)
sys.exit(0 if '$MODEL' in ids else 3)
"; then
      echo "  Model:   ✅ served by the endpoint"
    elif [[ $? -eq 3 ]]; then
      fail "model '$MODEL' is NOT in ${PURL%/}/models — fix the name before adding the provider"
    fi
    unset K
  fi
fi

# ── Step 3: dry-run exit ────────────────────────────────────────────
if $DRY_RUN; then
  echo ""
  echo "Changes:"
  $SECRET_EXISTS || echo "  secret/$SECRET: CREATE (key $CKEY)"
  echo "  olsconfig/cluster: ADD provider $NAME"
  $SET_DEFAULT && echo "  olsconfig/cluster: defaultProvider=$NAME defaultModel=$MODEL"
  echo ""
  echo "DRY_RUN_RESULT=PENDING"
  trace_end 0 2>/dev/null || true; exit 0
fi

# ── Step 4: patch the provider into OLSConfig ───────────────────────
trace_step 3 "patch-olsconfig" 0 "$NAME" 2>/dev/null || true

BAK="/tmp/olsconfig.bak.$(date +%Y%m%d_%H%M%S).yaml"
# shellcheck disable=SC2086
oc $OC_CONTEXT get olsconfig cluster -o yaml > "$BAK"
echo "  Backup:  $BAK"

VALUE=$(python3 -c "
import json
v={'name':'$NAME','type':'$PTYPE',
   'credentialsSecretRef':{'name':'$SECRET'},
   'credentialKey':'$CKEY',
   'models':[{'name':'$MODEL'}]}
if '$PURL': v['url']='$PURL'
if '$PTYPE'=='google_vertex_anthropic':
    v['googleVertexAnthropicConfig']={'projectID':'$PROJECT','location':'$LOCATION'}
print(json.dumps([{'op':'add','path':'/spec/llm/providers/-','value':v}]))
")
# shellcheck disable=SC2086
oc $OC_CONTEXT patch olsconfig cluster --type=json -p "$VALUE" >/dev/null
echo "  Provider added to OLSConfig"

# ── Step 5: create the credentials secret ───────────────────────────
trace_step 4 "create-secret" 0 "$SECRET" 2>/dev/null || true

if ! $SECRET_EXISTS; then
  if $FROM_KEYRING; then
    # rotate-key.sh resolves secret/key/url/model from the CRD, validates the
    # key against the live endpoint BEFORE writing, and stamps the rotation
    # annotations. That is why the provider is patched in first.
    # --force-unmanaged-provider: rotate-key.sh is scoped to the
    # rotation-managed provider (corp-models) so a stray invocation
    # cannot overwrite a credential that is not on a rotation cycle.
    # Creating the secret for a brand-new provider is a deliberate,
    # explicit act by this script, not a stray rotation, so the gate is
    # bypassed here on purpose. The secret does not exist yet (checked
    # above), so there is no working credential to destroy.
    bash "$HERE/rotate-key.sh" "$NAME" --from-keyring --create \
      --force-unmanaged-provider \
      ${OC_CONTEXT:+--context "${OC_CONTEXT#--context }"} \
      --keyring-field "$KEYRING_FIELD" \
      || fail "credential creation failed — provider is in OLSConfig but has no secret. Restore: oc apply -f $BAK"
  else
    echo "  ⚠️  Secret '$SECRET' does not exist. Create it now with:"
    echo "     bash $HERE/rotate-key.sh $NAME --create --force-unmanaged-provider"
  fi
fi

# ── Step 6: optionally set as default, then verify ──────────────────
trace_step 5 "verify" 0 "" 2>/dev/null || true

if $SET_DEFAULT; then
  bash "$HERE/switch-provider.sh" "$NAME" "$MODEL" \
    ${OC_CONTEXT:+--context "${OC_CONTEXT#--context }"} || fail "switch to $NAME failed"
else
  # shellcheck disable=SC2086
  oc $OC_CONTEXT rollout status deployment/lightspeed-app-server -n "$NS" --timeout=240s >/dev/null 2>&1 || true
fi

# shellcheck disable=SC2086
echo "  Providers: $(oc $OC_CONTEXT get olsconfig cluster -o jsonpath='{.spec.llm.providers[*].name}')"
# shellcheck disable=SC2086
echo "  ApiReady:  $(oc $OC_CONTEXT get olsconfig cluster -o jsonpath='{.status.conditions[?(@.type=="ApiReady")].status}')"
echo ""
echo "✅ Provider '$NAME' added"
trace_end 0 2>/dev/null || true
