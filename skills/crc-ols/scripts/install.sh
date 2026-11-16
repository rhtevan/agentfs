#!/usr/bin/env bash
# install.sh — Install OpenShift Lightspeed on CRC and bootstrap the first provider
#
# Usage:
#   install.sh [--dry-run] [--context CONTEXT]
#              [--project ID] [--location LOC] [--model NAME] [--sa-key PATH]
#              [--skip-provider] [--timeout SECONDS]
#
# Flags:
#   --dry-run          Report what would change. Writes nothing. Emits
#                      DRY_RUN_RESULT=CONVERGED|PENDING.
#   --context CTX      oc context (default: $CRC_OC_CONTEXT or current).
#   --project ID       GCP project. Default: resolved from the gcp-vertex-models
#                      probe cache — never a placeholder.
#   --location LOC     Vertex location. Default: resolved from the probe cache.
#   --model NAME       Vertex model. Default: highest-ranked available model
#                      from the probe cache (opus > sonnet > haiku, newest first).
#   --sa-key PATH      GCP SA key. Default: gcp-vertex-models/select-sa.sh.
#   --skip-provider    Install the operator only. Do not create OLSConfig.
#   --timeout SECONDS  Per-wait timeout (default 600).
#
# Exit codes: 0 = done / converged, 1 = failure, 2 = usage error
#
# SAFETY: this script never mutates an existing OLSConfig. If one is present it
# reports converged and exits 0. Use add-provider / switch-provider / rotate-key
# to change a live deployment.
set -euo pipefail

# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-ols" "3.5.0" 2>/dev/null || true

DRY_RUN=false
OC_CONTEXT=""
PROJECT=""
LOCATION=""
MODEL=""
SA_KEY=""
SKIP_PROVIDER=false
TIMEOUT=600
NS="openshift-lightspeed"
GVM="${HOME}/.agents/skills/gcp-vertex-models/scripts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=true; shift ;;
    --context)       OC_CONTEXT="--context ${2:?}"; shift 2 ;;
    --project)       PROJECT="${2:?}"; shift 2 ;;
    --location)      LOCATION="${2:?}"; shift 2 ;;
    --model)         MODEL="${2:?}"; shift 2 ;;
    --sa-key)        SA_KEY="${2:?}"; shift 2 ;;
    --skip-provider) SKIP_PROVIDER=true; shift ;;
    --timeout)       TIMEOUT="${2:?}"; shift 2 ;;
    -h|--help)       sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               echo "❌ Unknown option: $1" >&2; exit 2 ;;
  esac
done

OC_CONTEXT="${OC_CONTEXT:-$([ -n "${CRC_OC_CONTEXT:-}" ] && echo "--context $CRC_OC_CONTEXT" || echo "")}"

PLAN=()        # human-readable list of pending changes
plan() { PLAN+=("$1"); }

fail() { echo "❌ $1" >&2; trace_end 1 2>/dev/null || true; exit 1; }

# ── Step 1: preflight ───────────────────────────────────────────────
trace_step 1 "preflight" 0 "" 2>/dev/null || true

command -v oc >/dev/null 2>&1 || fail "oc not found in PATH"
# shellcheck disable=SC2086
oc $OC_CONTEXT whoami >/dev/null 2>&1 \
  || fail "oc is not authenticated. Start CRC and log in as kubeadmin."
# shellcheck disable=SC2086
WHO=$(oc $OC_CONTEXT whoami)
echo "Cluster:  $(oc $OC_CONTEXT whoami --show-server 2>/dev/null) (user: $WHO)"

# ── Step 2: Phase 0 — resolve provider settings (no placeholders) ───
trace_step 2 "resolve-settings" 0 "" 2>/dev/null || true

if ! $SKIP_PROVIDER; then
  if [[ -z "$PROJECT" || -z "$LOCATION" || -z "$MODEL" ]]; then
    if [[ ! -f "$GVM/models.sh" ]]; then
      fail "gcp-vertex-models not found at $GVM — pass --project/--location/--model explicitly"
    fi
    # models.sh default prints "<model> <region>" on stdout; diagnostics go to stderr.
    if RESOLVED=$(bash "$GVM/models.sh" default 2>/dev/null) && [[ -n "$RESOLVED" ]]; then
      read -r D_MODEL D_REGION <<<"$RESOLVED"
      [[ -z "$MODEL"    ]] && MODEL="$D_MODEL"
      [[ -z "$LOCATION" ]] && LOCATION="$D_REGION"
    fi
    if [[ -z "$PROJECT" ]]; then
      CACHE="${GCP_VERTEX_MODELS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/gcp-vertex-models/models.json}"
      PROJECT=$(python3 -c "
import json,sys
try: print(json.load(open('$CACHE')).get('project',''))
except Exception: pass
" 2>/dev/null || echo "")
    fi
  fi

  [[ -n "$PROJECT"  ]] || fail "Could not resolve GCP project. Run 'refresh vertex models' or pass --project."
  [[ -n "$LOCATION" ]] || fail "Could not resolve Vertex location. Run 'refresh vertex models' or pass --location."
  [[ -n "$MODEL"    ]] || fail "Could not resolve Vertex model. Run 'refresh vertex models' or pass --model."

  # A placeholder reaching the cluster produces a provider that is Ready but
  # 404s at query time. Refuse rather than install something broken.
  case "$PROJECT$LOCATION$MODEL" in
    *YOUR_*|*CHANGEME*|*\<*) fail "Placeholder value in project/location/model — refusing to install" ;;
  esac

  if [[ -z "$SA_KEY" ]]; then
    [[ -f "$GVM/select-sa.sh" ]] || fail "select-sa.sh not found at $GVM — pass --sa-key"
    SA_KEY=$(bash "$GVM/select-sa.sh" --project "$PROJECT" 2>/dev/null || echo "")
    [[ -n "$SA_KEY" ]] || fail "No dedicated service-account key found. Run: bash $GVM/detect-sa.sh"
  fi
  [[ -f "$SA_KEY" ]] || fail "SA key file not found: $SA_KEY"
  SA_TYPE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('type',''))" "$SA_KEY" 2>/dev/null || echo "")
  [[ "$SA_TYPE" == "service_account" ]] \
    || fail "$SA_KEY is type '${SA_TYPE:-unparseable}', not 'service_account'"

  echo "Provider: google-anthropic (google_vertex_anthropic)"
  echo "  Project:  $PROJECT"
  echo "  Location: $LOCATION"
  echo "  Model:    $MODEL"
  echo "  SA key:   $SA_KEY"
fi

# ── Step 3: observe current state ───────────────────────────────────
trace_step 3 "observe" 0 "" 2>/dev/null || true

# shellcheck disable=SC2086
HAS_NS=$(oc $OC_CONTEXT get namespace "$NS" &>/dev/null && echo true || echo false)
# OLM permits exactly ONE OperatorGroup per namespace; a second one puts every
# operator in the namespace into a failed state. Detect ANY OperatorGroup, not
# one by name.
# shellcheck disable=SC2086
HAS_OG=$($HAS_NS && [[ -n "$(oc $OC_CONTEXT get operatorgroup -n "$NS" -o name 2>/dev/null)" ]] && echo true || echo false)
# shellcheck disable=SC2086
HAS_SUB=$($HAS_NS && oc $OC_CONTEXT get subscription lightspeed-operator -n "$NS" &>/dev/null && echo true || echo false)
# shellcheck disable=SC2086
CSV_PHASE=$($HAS_NS && oc $OC_CONTEXT get csv -n "$NS" -o jsonpath='{.items[?(@.spec.displayName=="OpenShift Lightspeed Operator")].status.phase}' 2>/dev/null || echo "")
# The operator reads metrics-client-ca from openshift-monitoring, NOT from $NS.
# shellcheck disable=SC2086
HAS_METRICS_CA=$(oc $OC_CONTEXT get configmap metrics-client-ca -n openshift-monitoring &>/dev/null && echo true || echo false)
# shellcheck disable=SC2086
HAS_SECRET=$(oc $OC_CONTEXT get secret llmcreds -n "$NS" &>/dev/null && echo true || echo false)
# shellcheck disable=SC2086
HAS_OLSCONFIG=$(oc $OC_CONTEXT get olsconfig cluster &>/dev/null && echo true || echo false)

echo ""
echo "Current state:"
echo "  namespace $NS:        $($HAS_NS && echo present || echo absent)"
echo "  operatorgroup:        $($HAS_OG && echo present || echo absent)"
echo "  subscription:         $($HAS_SUB && echo present || echo absent)"
echo "  operator CSV:         ${CSV_PHASE:-absent}"
echo "  metrics-client-ca cm: $($HAS_METRICS_CA && echo present || echo absent) (ns openshift-monitoring)"
echo "  secret llmcreds:      $($HAS_SECRET && echo present || echo absent)"
echo "  OLSConfig cluster:    $($HAS_OLSCONFIG && echo present || echo absent)"

$HAS_NS           || plan "namespace/$NS: CREATE"
$HAS_OG           || plan "operatorgroup/openshift-lightspeed-operator: CREATE"
$HAS_SUB          || plan "subscription/lightspeed-operator: CREATE (channel stable, redhat-operators)"
[[ "$CSV_PHASE" == "Succeeded" ]] || plan "operator CSV: WAIT for Succeeded (currently ${CSV_PHASE:-absent})"
$HAS_METRICS_CA   || plan "configmap/metrics-client-ca: CREATE in openshift-monitoring (CRC fix, key client-ca.crt)"
if ! $SKIP_PROVIDER; then
  $HAS_SECRET     || plan "secret/llmcreds: CREATE from $SA_KEY"
  $HAS_OLSCONFIG  || plan "olsconfig/cluster: CREATE (google-anthropic, $MODEL, maxIterations 20)"
fi

# ── Step 4: dry-run exit ────────────────────────────────────────────
if $DRY_RUN; then
  echo ""
  if [[ ${#PLAN[@]} -eq 0 ]]; then
    echo "Changes: none"
    echo ""
    echo "DRY_RUN_RESULT=CONVERGED"
  else
    echo "Changes:"
    for p in "${PLAN[@]}"; do echo "  $p"; done
    echo ""
    echo "DRY_RUN_RESULT=PENDING"
  fi
  trace_end 0 2>/dev/null || true; exit 0
fi

if [[ ${#PLAN[@]} -eq 0 ]]; then
  echo ""
  echo "✅ Already installed — nothing to do."
  trace_end 0 2>/dev/null || true; exit 0
fi

# ── Step 5: operator ────────────────────────────────────────────────
trace_step 4 "install-operator" 0 "" 2>/dev/null || true
echo ""

if ! $HAS_NS; then
  # shellcheck disable=SC2086
  oc $OC_CONTEXT create namespace "$NS" >/dev/null
  echo "  ✅ namespace/$NS created"
fi

if ! $HAS_OG; then
  # shellcheck disable=SC2086
  oc $OC_CONTEXT apply -f - >/dev/null <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-lightspeed-operator
  namespace: $NS
spec:
  targetNamespaces:
  - $NS
EOF
  echo "  ✅ operatorgroup created"
fi

if ! $HAS_SUB; then
  # shellcheck disable=SC2086
  oc $OC_CONTEXT apply -f - >/dev/null <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lightspeed-operator
  namespace: $NS
spec:
  channel: stable
  installPlanApproval: Automatic
  name: lightspeed-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  echo "  ✅ subscription created"
fi

if [[ "$CSV_PHASE" != "Succeeded" ]]; then
  echo -n "  ⏳ waiting for operator CSV to reach Succeeded (timeout ${TIMEOUT}s) ... "
  DEADLINE=$(( $(date +%s) + TIMEOUT ))
  while [[ $(date +%s) -lt $DEADLINE ]]; do
    # shellcheck disable=SC2086
    P=$(oc $OC_CONTEXT get csv -n "$NS" \
        -o jsonpath='{.items[?(@.spec.displayName=="OpenShift Lightspeed Operator")].status.phase}' 2>/dev/null || echo "")
    [[ "$P" == "Succeeded" ]] && break
    sleep 10
  done
  [[ "${P:-}" == "Succeeded" ]] || fail "operator CSV did not reach Succeeded (last: ${P:-none})"
  echo "✅"
fi

# ── Step 6: CRC fix — metrics-client-ca ─────────────────────────────
trace_step 5 "metrics-client-ca" 0 "" 2>/dev/null || true

if ! $HAS_METRICS_CA; then
  # CRC disables the monitoring stack, so openshift-monitoring/metrics-client-ca
  # is missing and the operator crashes. Rebuild it from the kube-apiserver CA.
  TMPCA=$(mktemp); trap 'rm -f "$TMPCA"' EXIT
  # shellcheck disable=SC2086
  oc $OC_CONTEXT get configmap client-ca -n openshift-kube-apiserver \
    -o jsonpath='{.data.ca-bundle\.crt}' > "$TMPCA" 2>/dev/null || true
  [[ -s "$TMPCA" ]] || fail "could not read client-ca/ca-bundle.crt from openshift-kube-apiserver"
  # Destination namespace is openshift-monitoring, and the key MUST be
  # client-ca.crt — any other key leaves the operator stuck.
  # shellcheck disable=SC2086
  oc $OC_CONTEXT create configmap metrics-client-ca \
    --from-file=client-ca.crt="$TMPCA" -n openshift-monitoring >/dev/null
  rm -f "$TMPCA"
  echo "  ✅ configmap/metrics-client-ca created in openshift-monitoring (key client-ca.crt)"
fi

$SKIP_PROVIDER && { echo ""; echo "✅ Operator installed (--skip-provider)."; trace_end 0 2>/dev/null || true; exit 0; }

# ── Step 7: credentials secret ──────────────────────────────────────
trace_step 6 "create-secret" 0 "llmcreds" 2>/dev/null || true

if ! $HAS_SECRET; then
  # shellcheck disable=SC2086
  oc $OC_CONTEXT create secret generic llmcreds \
    --from-file=gcp-service-account.json="$SA_KEY" -n "$NS" >/dev/null
  echo "  ✅ secret/llmcreds created"
fi

# ── Step 8: OLSConfig ───────────────────────────────────────────────
trace_step 7 "create-olsconfig" 0 "$MODEL" 2>/dev/null || true

if $HAS_OLSCONFIG; then
  echo "  ⏭️  OLSConfig already exists — not modified (use switch-provider.sh / add-provider)"
else
  # shellcheck disable=SC2086
  oc $OC_CONTEXT apply -f - >/dev/null <<EOF
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
spec:
  llm:
    providers:
    - name: google-anthropic
      type: google_vertex_anthropic
      credentialsSecretRef:
        name: llmcreds
      credentialKey: gcp-service-account.json
      googleVertexAnthropicConfig:
        projectID: $PROJECT
        location: $LOCATION
      models:
      - name: $MODEL
  ols:
    defaultModel: $MODEL
    defaultProvider: google-anthropic
    maxIterations: 20
EOF
  echo "  ✅ olsconfig/cluster created"
fi

# ── Step 9: verify ──────────────────────────────────────────────────
trace_step 8 "verify" 0 "" 2>/dev/null || true

echo -n "  ⏳ waiting for lightspeed-app-server rollout ... "
# shellcheck disable=SC2086
if oc $OC_CONTEXT rollout status deployment/lightspeed-app-server -n "$NS" --timeout="${TIMEOUT}s" >/dev/null 2>&1; then
  echo "✅"
else
  echo "⚠️  not complete — check: oc get pods -n $NS"
fi

# shellcheck disable=SC2086
API_READY=$(oc $OC_CONTEXT get olsconfig cluster \
  -o jsonpath='{.status.conditions[?(@.type=="ApiReady")].status}' 2>/dev/null || echo "")
echo "  ApiReady: ${API_READY:-unknown}"

echo ""
echo "✅ Install complete. Next: bash $(dirname "$0")/list.sh"
trace_end 0 2>/dev/null || true
