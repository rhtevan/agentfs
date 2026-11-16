#!/usr/bin/env bash
# rotate-key.sh — Rotate (or create) the Corp provider's credentials secret
#
# Scoped to 'corp-models', the only OLS provider on a key-rotation cycle.
# Any other provider exits 1 unless --force-unmanaged-provider is passed.
#
# Usage:
#   rotate-key.sh corp-models [--from-keyring] [--create] [--dry-run]
#                             [--rotation-days N] [--context CONTEXT]
#
# Flags:
#   --from-keyring      Read the key from GNOME Keyring (service goose) instead
#                       of prompting. Only the single key named by the provider's
#                       keyring entry is read — never the whole blob.
#   --create            Allow creating the secret if it does not exist yet.
#                       Without it, a missing secret is an error.
#   --dry-run           Report current state and what would change. Writes nothing.
#   --rotation-days N   Expected rotation interval, stamped on the secret (default 30).
#   --stamp-only        Set crc-ols/rotation-days ONLY. Writes no credential,
#                       no reload. Requires --rotation-days N. Works on any
#                       provider. Leaves crc-ols/rotated-at untouched so the
#                       reported age stays truthful.
#   --force-unmanaged-provider
#                       Operate on a provider other than the rotation-managed
#                       one (corp-models). Required because no other OLS
#                       provider is on a rotation cycle — see the scope gate.
#   --context CONTEXT   oc context (default: $CRC_OC_CONTEXT or current).
#
# Exit codes: 0 = done / converged, 1 = failure, 2 = usage error
#
# The key is never printed, never placed in a shell variable that is echoed,
# and never written to the trace. It flows: source -> mktemp(600) -> oc -> shred.
#
# Annotations written (convention owned by this skill):
#   crc-ols/rotated-at     RFC3339 timestamp of the rotation
#   crc-ols/rotation-days  expected interval, used by list.sh to warn
set -euo pipefail

# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-ols" "3.5.0" 2>/dev/null || true

PROVIDER=""
FROM_KEYRING=false
ALLOW_CREATE=false
DRY_RUN=false
ROTATION_DAYS=30
OC_CONTEXT=""
KEYRING_SERVICE="goose"
KEYRING_FIELD="CUSTOM_CORP_API_KEY"
FORCE_OTHER=false
STAMP_ONLY=false
ROTATION_DAYS_SET=false

# Rotation is a maintenance activity scoped to the Corp provider, whose
# key the issuer cycles every 30 days. No other OLS provider on this
# cluster is on a rotation cycle: google-anthropic is a GCP
# service-account key (re-issued in IAM), and the skupper providers are
# lab tokens. Pointing this script at them is operator error, not a
# workflow, so it must be an explicit act rather than a default.
MANAGED_PROVIDER="corp-models"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-keyring)   FROM_KEYRING=true; shift ;;
    --create)         ALLOW_CREATE=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --rotation-days)  ROTATION_DAYS="${2:?}"; ROTATION_DAYS_SET=true; shift 2 ;;
    --stamp-only)     STAMP_ONLY=true; shift ;;
    --context)        OC_CONTEXT="--context $2"; shift 2 ;;
    --keyring-field)  KEYRING_FIELD="${2:?}"; shift 2 ;;
    --force-unmanaged-provider) FORCE_OTHER=true; shift ;;
    -h|--help)        sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)               echo "❌ Unknown option: $1" >&2; exit 2 ;;
    *)                PROVIDER="$1"; shift ;;
  esac
done

[[ -n "$PROVIDER" ]] || { echo "❌ PROVIDER is required. Usage: rotate-key.sh $MANAGED_PROVIDER [flags]" >&2; exit 2; }

# --stamp-only sets the rotation-policy annotation and nothing else. It
# never reads a key, never writes secret data, and never reloads the
# deployment, so it is safe on any provider and is exempt from the
# scope gate below. It is the supported way to put a non-corp
# credential under the countdown without touching the credential.
if $STAMP_ONLY; then
  $ROTATION_DAYS_SET || { echo "❌ --stamp-only requires --rotation-days N" >&2; exit 2; }
  $FROM_KEYRING && { echo "❌ --stamp-only cannot be combined with --from-keyring" >&2; exit 2; }
  $ALLOW_CREATE  && { echo "❌ --stamp-only cannot be combined with --create" >&2; exit 2; }
fi

# ── Scope gate: rotation is for the managed provider only ───────────
# Runs before any cluster read so a mistyped or unintended provider
# never reaches the secret-write path.
if [[ "$PROVIDER" != "$MANAGED_PROVIDER" ]] && ! $FORCE_OTHER && ! $STAMP_ONLY; then
  echo "❌ '$PROVIDER' is not the rotation-managed provider." >&2
  echo "" >&2
  echo "   Only '$MANAGED_PROVIDER' is on a key-rotation cycle (30 days)." >&2
  echo "   The other OLS providers are not:" >&2
  echo "     google-anthropic       GCP service-account key — re-issue in IAM" >&2
  echo "     skupper-model-*        lab tokens — no rotation cycle" >&2
  echo "" >&2
  echo "   This guard exists because rotating a provider that is not on a" >&2
  echo "   cycle replaces a working credential with a typed string." >&2
  echo "   If you genuinely need to, re-run with --force-unmanaged-provider." >&2
  trace_end 1 2>/dev/null || true; exit 1
fi
OC_CONTEXT="${OC_CONTEXT:-$([ -n "${CRC_OC_CONTEXT:-}" ] && echo "--context $CRC_OC_CONTEXT" || echo "")}"
NS="openshift-lightspeed"

cleanup() { [[ -n "${KEYFILE:-}" && -f "${KEYFILE:-}" ]] && shred -u "$KEYFILE" 2>/dev/null || true; }
trap cleanup EXIT

# ── Step 1: resolve the provider from the CRD (never hardcode) ──────
trace_step 1 "resolve-provider" 0 "$PROVIDER" 2>/dev/null || true

# shellcheck disable=SC2086
if ! oc $OC_CONTEXT get olsconfig cluster &>/dev/null; then
  echo "❌ OLSConfig 'cluster' not found. Is OLS installed?" >&2
  trace_end 1 2>/dev/null || true; exit 1
fi

# shellcheck disable=SC2086
IDX=$(oc $OC_CONTEXT get olsconfig cluster -o json \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i,p in enumerate(d['spec']['llm']['providers']):
    if p['name']=='$PROVIDER': print(i); break
else: sys.exit(1)
" 2>/dev/null) || {
  echo "❌ Provider '$PROVIDER' not found in OLSConfig." >&2
  # shellcheck disable=SC2086
  echo "   Configured: $(oc $OC_CONTEXT get olsconfig cluster -o jsonpath='{.spec.llm.providers[*].name}')" >&2
  trace_end 1 2>/dev/null || true; exit 1
}

# shellcheck disable=SC2086
read -r SECRET_NAME CRED_KEY PURL PMODEL PTYPE < <(oc $OC_CONTEXT get olsconfig cluster -o json \
  | python3 -c "
import json,sys
p=json.load(sys.stdin)['spec']['llm']['providers'][$IDX]
models=p.get('models') or [{}]
print(p['credentialsSecretRef']['name'],
      p.get('credentialKey','apitoken'),
      p.get('url','-'),
      models[0].get('name','-'),
      p.get('type','-'))
")

echo "Provider: $PROVIDER"
echo "  Secret:  $SECRET_NAME (key: $CRED_KEY)"
echo "  URL:     $PURL"
echo "  Model:   $PMODEL"
echo "  Type:    $PTYPE"

# ── Guard: this script rotates BEARER TOKENS only ───────────────────
#
# A google_vertex_anthropic provider's credential is a GCP service
# account JSON key (type/client_email/private_key), not a token. It
# cannot be validated with a bearer-token call, it is not replaced by
# pasting a string, and it does not expire on a calendar — it is
# revoked and re-issued in GCP IAM. Overwriting it with a typed string
# would destroy a working credential and break the provider.
#
# Refuse rather than mangle. --force-non-bearer exists only so a future
# bearer-style provider that happens to lack a url is not blocked; it
# still refuses outright for known JSON-credential provider types.
# --stamp-only writes no credential, so the bearer-token restriction
# does not apply to it: annotating a GCP service-account secret with a
# review interval is legitimate and harmless.
case "$($STAMP_ONLY && echo skip || echo "$PTYPE")" in
  google_vertex_anthropic|watsonx)
    echo "" >&2
    echo "❌ Provider type '$PTYPE' does not use a bearer token." >&2
    echo "   Secret '$SECRET_NAME' holds key '$CRED_KEY', which is a structured" >&2
    echo "   credential (service-account JSON), not a rotatable API key." >&2
    echo "" >&2
    echo "   Rotating it here would overwrite a working credential with a" >&2
    echo "   typed string. Re-issue the credential at the provider instead:" >&2
    echo "     GCP:     create a new key for the service account in IAM," >&2
    echo "              then: oc set data secret/$SECRET_NAME -n $NS \\" >&2
    echo "                      --from-file=$CRED_KEY=<new-key.json>" >&2
    echo "" >&2
    trace_end 1 2>/dev/null || true; exit 1 ;;
esac

# ── Step 2: current secret state + age ──────────────────────────────
trace_step 2 "inspect-secret" 0 "$SECRET_NAME" 2>/dev/null || true

SECRET_EXISTS=true
# shellcheck disable=SC2086
oc $OC_CONTEXT get secret "$SECRET_NAME" -n "$NS" &>/dev/null || SECRET_EXISTS=false

if $SECRET_EXISTS; then
  # shellcheck disable=SC2086
  read -r CREATED ROTATED RDAYS < <(oc $OC_CONTEXT get secret "$SECRET_NAME" -n "$NS" -o json \
    | python3 -c "
import json,sys
m=json.load(sys.stdin)['metadata']
a=m.get('annotations') or {}
print(m['creationTimestamp'],
      a.get('crc-ols/rotated-at','-'),
      a.get('crc-ols/rotation-days','-'))
")
  REF="${ROTATED}"; SRC="rotated-at"
  if [[ "$REF" == "-" ]]; then REF="$CREATED"; SRC="creationTimestamp (never rotated by this skill)"; fi
  AGE_DAYS=$(python3 -c "
from datetime import datetime,timezone
t=datetime.fromisoformat('$REF'.replace('Z','+00:00'))
print(int((datetime.now(timezone.utc)-t).total_seconds()//86400))
")
  # Do NOT invent a policy. A secret with no crc-ols/rotation-days
  # annotation has no rotation policy; printing the script's own
  # --rotation-days default as "limit Nd" fabricates a deadline the
  # operator never set and makes an unmanaged credential look managed.
  if [[ "$RDAYS" == "-" ]]; then
    LEFT=""
    echo "  Age:     ${AGE_DAYS}d (from $SRC), no rotation policy set"
  else
    LIMIT="$RDAYS"
    LEFT=$(( LIMIT - AGE_DAYS ))
    echo "  Age:     ${AGE_DAYS}d (from $SRC), limit ${LIMIT}d, ${LEFT}d remaining"
  fi
else
  echo "  Age:     secret does not exist"
  if ! $ALLOW_CREATE; then
    echo "❌ Secret '$SECRET_NAME' not found. Pass --create to create it." >&2
    trace_end 1 2>/dev/null || true; exit 1
  fi
fi

# ── Step 3a: --stamp-only — annotate the policy and stop ────────────
# Sets crc-ols/rotation-days ONLY. It deliberately does NOT set
# crc-ols/rotated-at: the key is not being rotated, and stamping
# rotated-at=now would reset the age of a credential that is in fact
# months old, hiding exactly what the countdown exists to surface.
# list.sh falls back to creationTimestamp when rotated-at is absent,
# so the age stays truthful.
if $STAMP_ONLY; then
  $SECRET_EXISTS || { echo "❌ Secret '$SECRET_NAME' does not exist — nothing to stamp." >&2
                      trace_end 1 2>/dev/null || true; exit 1; }
  if [[ "$RDAYS" == "$ROTATION_DAYS" ]]; then
    echo ""
    echo "Changes: none (crc-ols/rotation-days already $ROTATION_DAYS)"
    $DRY_RUN && echo "DRY_RUN_RESULT=CONVERGED"
    trace_end 0 2>/dev/null || true; exit 0
  fi
  echo ""
  echo "Changes:"
  echo "  secret/$SECRET_NAME crc-ols/rotation-days: ${RDAYS} -> ${ROTATION_DAYS}"
  echo "  (credential NOT touched; crc-ols/rotated-at left as '${ROTATED}')"
  if $DRY_RUN; then
    echo ""
    echo "DRY_RUN_RESULT=PENDING"
    trace_end 0 2>/dev/null || true; exit 0
  fi
  # shellcheck disable=SC2086
  oc $OC_CONTEXT annotate secret "$SECRET_NAME" -n "$NS" --overwrite \
    "crc-ols/rotation-days=$ROTATION_DAYS" >/dev/null
  echo "  Stamped: crc-ols/rotation-days=$ROTATION_DAYS"
  echo ""
  echo "✅ Rotation policy set for $PROVIDER (age still measured from $SRC)"
  trace_end 0 2>/dev/null || true; exit 0
fi

# ── Step 3: dry run stops here ──────────────────────────────────────
if $DRY_RUN; then
  echo ""
  # CONVERGED must mean "nothing to do". Listing pending changes and
  # then printing CONVERGED is a contradiction: a caller following the
  # Dry-Run Gate would skip the apply while changes were still pending.
  # The secret exists and is inside its stamped rotation window => no
  # action. Anything else => report the changes and PENDING.
  if $SECRET_EXISTS && [[ "$RDAYS" != "-" ]] && [[ "${LEFT:-0}" -gt 0 ]]; then
    echo "Changes: none (secret exists, ${LEFT}d left of the ${RDAYS}d policy)"
    echo ""
    echo "DRY_RUN_RESULT=CONVERGED"
  else
    echo "Changes:"
    if $SECRET_EXISTS; then
      echo "  secret/$SECRET_NAME data.$CRED_KEY: <rotated>"
      echo "  secret/$SECRET_NAME crc-ols/rotated-at: ${ROTATED} -> <now>"
      echo "  secret/$SECRET_NAME crc-ols/rotation-days: ${RDAYS} -> ${ROTATION_DAYS}"
    else
      echo "  secret/$SECRET_NAME: CREATE with key $CRED_KEY"
    fi
    echo "  deployment/lightspeed-app-server: force-reload annotation"
    echo ""
    echo "DRY_RUN_RESULT=PENDING"
  fi
  trace_end 0 2>/dev/null || true; exit 0
fi

# ── Step 4: source the key ──────────────────────────────────────────
trace_step 3 "source-key" 0 "$($FROM_KEYRING && echo keyring || echo prompt)" 2>/dev/null || true

KEYFILE=$(mktemp); chmod 600 "$KEYFILE"

if $FROM_KEYRING; then
  command -v secret-tool >/dev/null 2>&1 || {
    echo "❌ secret-tool not found (libsecret). Cannot read the keyring." >&2
    trace_end 1 2>/dev/null || true; exit 1; }
  if ! secret-tool lookup service "$KEYRING_SERVICE" 2>/dev/null \
      | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
v=d.get('$KEYRING_FIELD')
if not v: sys.exit(1)
sys.stdout.write(v)
" > "$KEYFILE" 2>/dev/null || [[ ! -s "$KEYFILE" ]]; then
    echo "❌ $KEYRING_FIELD not found in GNOME Keyring (service $KEYRING_SERVICE)." >&2
    echo "   Store it first: bash ~/.agents/skills/goose-corp-provider/scripts/store-key.sh" >&2
    trace_end 1 2>/dev/null || true; exit 1
  fi
  echo "  Key:     sourced from GNOME Keyring ($KEYRING_FIELD, $(wc -c < "$KEYFILE") chars)"
else
  read -rsp "Enter API key for $PROVIDER: " _K; echo
  printf '%s' "$_K" > "$KEYFILE"; unset _K
  [[ -s "$KEYFILE" ]] || { echo "❌ No key provided." >&2; trace_end 1 2>/dev/null || true; exit 1; }
fi

# ── Step 5: validate BEFORE writing anything ────────────────────────
trace_step 4 "validate-key" 0 "$PURL" 2>/dev/null || true

if [[ "$PURL" == "-" || "$PURL" != http* ]]; then
  echo "⚠️  Provider has no HTTP url (type may be non-openai) — skipping pre-flight validation."
else
  echo -n "  Validating against $PURL ... "
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 60 \
    "${PURL%/}/chat/completions" \
    -H "Authorization: Bearer $(cat "$KEYFILE")" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$PMODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}" \
    2>/dev/null || echo "000")
  case "$HTTP" in
    200) echo "✅ HTTP 200" ;;
    401|403) echo "❌ HTTP $HTTP — key rejected. Secret NOT modified." >&2
             trace_end 1 2>/dev/null || true; exit 1 ;;
    000) echo "❌ endpoint unreachable (VPN?). Secret NOT modified." >&2
         trace_end 1 2>/dev/null || true; exit 1 ;;
    *)   echo "❌ HTTP $HTTP — unexpected. Secret NOT modified." >&2
         trace_end 1 2>/dev/null || true; exit 1 ;;
  esac
fi

# ── Step 6: back up the existing secret, then write ─────────────────
trace_step 5 "write-secret" 0 "$SECRET_NAME" 2>/dev/null || true

STAMP=$(date +%Y%m%d_%H%M%S)
if $SECRET_EXISTS; then
  BAK="/tmp/${SECRET_NAME}.bak.${STAMP}.yaml"
  # shellcheck disable=SC2086
  (umask 077; oc $OC_CONTEXT get secret "$SECRET_NAME" -n "$NS" -o yaml > "$BAK")
  echo "  Backup:  $BAK (mode 600)"
  echo "           ⚠️  contains the PREVIOUS live key. Destroy it once the new"
  echo "               key is confirmed working:  shred -u $BAK"
  # shellcheck disable=SC2086
  oc $OC_CONTEXT set data secret/"$SECRET_NAME" -n "$NS" --from-file="$CRED_KEY=$KEYFILE" >/dev/null
  echo "  Secret:  updated"
else
  # shellcheck disable=SC2086
  oc $OC_CONTEXT create secret generic "$SECRET_NAME" -n "$NS" --from-file="$CRED_KEY=$KEYFILE" >/dev/null
  echo "  Secret:  created"
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# shellcheck disable=SC2086
oc $OC_CONTEXT annotate secret "$SECRET_NAME" -n "$NS" --overwrite \
  "crc-ols/rotated-at=$NOW" "crc-ols/rotation-days=$ROTATION_DAYS" >/dev/null
echo "  Stamped: crc-ols/rotated-at=$NOW crc-ols/rotation-days=$ROTATION_DAYS"

# ── Step 7: force OLS to reload, wait for Ready ─────────────────────
trace_step 6 "force-reload" 0 "" 2>/dev/null || true

# shellcheck disable=SC2086
oc $OC_CONTEXT patch deployment lightspeed-app-server -n "$NS" --type=merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"ols.openshift.io/force-reload\":\"$NOW\"}}}}}" >/dev/null
echo -n "  Reload:  waiting for rollout ... "
# shellcheck disable=SC2086
if oc $OC_CONTEXT rollout status deployment/lightspeed-app-server -n "$NS" --timeout=180s >/dev/null 2>&1; then
  echo "✅"
else
  echo "⚠️  rollout did not complete in 180s — check: oc get pods -n $NS"
fi

# ── Step 8: verify from inside the pod (key never leaves the cluster)
trace_step 7 "verify-in-pod" 0 "" 2>/dev/null || true

if [[ "$PURL" == http* ]]; then
  echo -n "  Verify:  in-pod probe ... "
  # Probe chat/completions, NOT /models — /models is frequently
  # unauthenticated (verified on the Corp endpoint 2026-11-16: a garbage
  # bearer token returns 200 from /models and 401 from chat/completions),
  # so a 200 from /models would be a meaningless confirmation.
  # shellcheck disable=SC2086
  POD_HTTP=$(oc $OC_CONTEXT exec deployment/lightspeed-app-server -n "$NS" \
    -c lightspeed-service-api -- bash -c \
    "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
       -H \"Authorization: Bearer \$(cat /etc/apikeys/$SECRET_NAME/$CRED_KEY 2>/dev/null || cat /app-root/.credentials/$CRED_KEY 2>/dev/null)\" \
       -H 'Content-Type: application/json' \
       -d '{\"model\":\"$PMODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}' \
       ${PURL%/}/chat/completions" 2>/dev/null || echo "000")
  if [[ "$POD_HTTP" == "200" ]]; then
    echo "✅ HTTP 200 (inference accepted)"
  else
    echo "⚠️  HTTP $POD_HTTP — mount path may differ; check 'ols credential status'"
  fi
fi

echo ""
echo "✅ Rotation complete for $PROVIDER"
if [[ -n "${BAK:-}" && -f "${BAK:-}" ]]; then
  echo "⚠️  Secret backup still on disk with the OLD key: $BAK"
  echo "    Destroy it now that rotation succeeded:  shred -u $BAK"
fi
trace_end 0 2>/dev/null || true
