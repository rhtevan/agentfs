#!/usr/bin/env bash
# setup.sh — Set up LiteLLM proxy for Vertex AI with systemd
# Usage: bash setup.sh --project PROJECT --sa-key PATH [--regions R1,R2] [--prefer global|regional] [--host HOST] [--master-key-file PATH] [--port PORT] [--dry-run]
# Exit codes: 0 = success, 1 = failure, 2 = usage error
set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "litellm-vertex-ai-proxy" "4.1.0" 2>/dev/null || true

PROJECT=""
SA_KEY=""
REGIONS="global,us-east5"
PREFER="global"
HOST="127.0.0.1"
MASTER_KEY_FILE=""
PORT="4000"
DRY_RUN=false
FORCE=false

CONFIG_DIR="$HOME/.config/litellm"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/litellm-proxy.service"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT="$2"; shift 2 ;;
    --sa-key)   SA_KEY="$2"; shift 2 ;;
    --regions|--region) REGIONS="$2"; shift 2 ;;
    --prefer)   PREFER="$2"; shift 2 ;;
    --host)     HOST="$2"; shift 2 ;;
    --master-key-file) MASTER_KEY_FILE="$2"; shift 2 ;;
    --port)     PORT="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --force)    FORCE=true; shift ;;
    -h|--help)
      echo "Usage: bash setup.sh --project PROJECT --sa-key PATH [OPTIONS]"
      echo ""
      echo "Required:"
      echo "  --project PROJECT  GCP project ID"
      echo "  --sa-key  PATH     Path to service account key JSON"
      echo ""
      echo "Optional:"
      echo "  --regions R1,R2    Regions to probe (default: global,us-east5)"
      echo "  --prefer  MODE     global|regional: region used per model when both work (default: global)"
      echo "  --host    HOST     Bind address (default: 127.0.0.1, use 0.0.0.0 for container access)"
      echo "  --master-key-file PATH  File with LITELLM_MASTER_KEY=sk-... (required for a non-loopback --host)"
      echo "  --port    PORT     Proxy port (default: 4000)"
      echo "  --dry-run          Write to /tmp/litellm-setup-preview/ instead of live paths"
      echo "  --force            Overwrite even if proxy is currently healthy"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

# --- Validate inputs ---
if [[ -z "$PROJECT" ]]; then
  PROJECT=$(gcloud config get-value project 2>/dev/null || echo "${ANTHROPIC_VERTEX_PROJECT_ID:-}")
  if [[ -z "$PROJECT" ]]; then
    echo "❌ --project is required (or set via gcloud config)"
    exit 2
  fi
  echo "Auto-detected project: $PROJECT"
fi

# LiteLLM >= 1.110 refuses to start without a master key. Loopback: the
# proxy is reachable only from this host, so permit it unauthenticated
# (clients stay requires_auth: false). Any other bind address: require a
# key file, loaded via EnvironmentFile= so the key stays out of the unit.
case "$HOST" in
  127.0.0.1|localhost|::1) LOOPBACK=true ;;
  *) LOOPBACK=false ;;
esac
if [[ -n "$MASTER_KEY_FILE" ]]; then
  if [[ ! -f "$MASTER_KEY_FILE" ]] || ! grep -q '^LITELLM_MASTER_KEY=sk-' "$MASTER_KEY_FILE"; then
    echo "❌ --master-key-file must contain a line LITELLM_MASTER_KEY=sk-..."
    exit 2
  fi
elif [[ "$LOOPBACK" != true ]]; then
  echo "❌ --host $HOST is not loopback: the proxy would accept unauthenticated requests from the network."
  echo "   Create a key file:  umask 077; echo \"LITELLM_MASTER_KEY=sk-\$(openssl rand -hex 32)\" > ~/.config/litellm/master.env"
  echo "   Then re-run with:   --master-key-file ~/.config/litellm/master.env  (clients must send the key)"
  exit 2
fi

if [[ -z "$SA_KEY" ]]; then
  # Delegate to gcp-vertex-models/select-sa.sh — it filters to
  # type:service_account and rejects the default compute SA. A bare
  # `find ... | head -1` is NOT safe: legacy_credentials/ also holds
  # authorized_user ADC files, and alphabetical order can surface an
  # expired user credential ahead of the dedicated SA key.
  SELECT_SA="$HOME/.agents/skills/gcp-vertex-models/scripts/select-sa.sh"
  if [[ ! -x "$SELECT_SA" && ! -f "$SELECT_SA" ]]; then
    echo "❌ --sa-key is required (gcp-vertex-models/select-sa.sh not found)"
    exit 2
  fi
  SA_KEY=$(bash "$SELECT_SA" --project "$PROJECT" 2>/dev/null || echo "")
  if [[ -z "$SA_KEY" ]]; then
    echo "❌ --sa-key is required (no dedicated service account key auto-detected)"
    echo "   Run: bash $SELECT_SA --project $PROJECT"
    exit 2
  fi
  echo "Auto-detected SA key: $SA_KEY"
fi

if [[ ! -f "$SA_KEY" ]]; then
  echo "❌ SA key file not found: $SA_KEY"
  exit 1
fi

# Guard: systemd services cannot re-authenticate interactively, so a
# user ADC refresh token would expire and the proxy would fail silently.
# Only a service_account key is acceptable.
SA_KEY_TYPE=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('type',''))" \
  "$SA_KEY" 2>/dev/null || echo "")
if [[ "$SA_KEY_TYPE" != "service_account" ]]; then
  echo "❌ $SA_KEY is type '${SA_KEY_TYPE:-unparseable}', not 'service_account'."
  echo "   systemd cannot refresh user credentials — the proxy would fail when the token expires."
  exit 1
fi

# Resolve to absolute path
SA_KEY=$(realpath "$SA_KEY")

# Find litellm binary
LITELLM_BIN=$(which litellm 2>/dev/null || echo "")
if [[ -z "$LITELLM_BIN" ]]; then
  echo "❌ litellm not found. Install with: uv tool install 'litellm[proxy,google]'"
  exit 1
fi

# --- Safety check ---
if [[ "$DRY_RUN" == true ]]; then
  CONFIG_DIR="/tmp/litellm-setup-preview"
  CONFIG_FILE="$CONFIG_DIR/config.yaml"
  SERVICE_DIR="/tmp/litellm-setup-preview"
  SERVICE_FILE="$SERVICE_DIR/litellm-proxy.service"
  echo ""
  echo "🔍 DRY RUN — writing to $CONFIG_DIR/"
  echo ""
else
  # Check if proxy is currently healthy
  if curl -sf http://127.0.0.1:$PORT/health &>/dev/null && [[ "$FORCE" != true ]]; then
    echo "⚠️  LiteLLM proxy is currently healthy on port $PORT."
    echo "   Use --force to overwrite, or --dry-run to preview."
    exit 1
  fi
fi

# --- Discover models (gcp-vertex-models skill: SA auth, global + regional) ---
PROBE="${HOME}/.agents/skills/gcp-vertex-models/scripts/probe-models.sh"
if [[ ! -f "$PROBE" ]]; then
  echo "❌ Dependency missing: gcp-vertex-models skill ($PROBE)"
  exit 1
fi
PROBE_JSON="$(mktemp /tmp/litellm-probe.XXXXXX.json)"
trap 'rm -f "$PROBE_JSON"' EXIT

echo "Probing Vertex AI (regions: $REGIONS) ..."
set +e
bash "$PROBE" --project "$PROJECT" --credentials "$SA_KEY" \
  --regions "$REGIONS" --prefer "$PREFER" --format json --output "$PROBE_JSON" 2>/dev/null
PROBE_RC=$?
set -e
if [[ $PROBE_RC -ne 0 ]]; then
  echo "❌ Probe found no usable models (exit $PROBE_RC) for project $PROJECT"
  exit 1
fi

# Lines of "<model> <region>" for usable models only
mapfile -t MODEL_LINES < <(python3 -c '
import json, sys
for m in json.load(open(sys.argv[1]))["models"]:
    if m["region"]:
        print(m["model"], m["region"])
' "$PROBE_JSON")
MODELS=()
for line in "${MODEL_LINES[@]}"; do
  echo "  ✅ ${line% *}  (${line#* })"
  MODELS+=("${line% *}")
done

echo ""
echo "Found ${#MODELS[@]} model(s)"

# --- Generate config.yaml (explicit model_list, per-model region, no wildcard) ---
mkdir -p "$CONFIG_DIR"

# Backup existing config
if [[ -f "$CONFIG_FILE" && "$DRY_RUN" != true ]]; then
  BACKUP="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP"
  echo "📋 Config backup: $BACKUP"
fi

{
  echo "# Generated by litellm-vertex-ai-proxy/scripts/setup.sh from gcp-vertex-models probe"
  echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ) project=$PROJECT regions=$REGIONS"
  echo "model_list:"
  for line in "${MODEL_LINES[@]}"; do
    model="${line% *}"; region="${line#* }"
    printf '  - model_name: %s\n    litellm_params:\n      model: vertex_ai/%s\n      vertex_project: %s\n      vertex_location: %s\n\n' \
      "$model" "$model" "$PROJECT" "$region"
  done
  printf 'litellm_settings:\n  drop_params: true\n  request_timeout: 120\n'
  if [[ -z "$MASTER_KEY_FILE" ]]; then
    printf '\n# Loopback bind (--host %s): unauthenticated access is limited to this host.\ngeneral_settings:\n  dangerously_permit_weak_or_unset_master_key: true\n' "$HOST"
  fi
} > "$CONFIG_FILE"

echo "✅ Config written: $CONFIG_FILE"

# --- Generate systemd service ---
mkdir -p "$SERVICE_DIR"

# Backup existing service
if [[ -f "$SERVICE_FILE" && "$DRY_RUN" != true ]]; then
  BACKUP="${SERVICE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$SERVICE_FILE" "$BACKUP"
  echo "📋 Service backup: $BACKUP"
fi

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=LiteLLM Proxy - OpenAI-compatible gateway to Vertex AI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=GOOGLE_APPLICATION_CREDENTIALS=$SA_KEY${MASTER_KEY_FILE:+
EnvironmentFile=$(realpath "$MASTER_KEY_FILE")}
ExecStart=$LITELLM_BIN --config $HOME/.config/litellm/config.yaml --host $HOST --port $PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

echo "✅ Service written: $SERVICE_FILE"

# --- Start service (skip for dry-run) ---
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "🔍 DRY RUN complete. Review generated files:"
  echo "   $CONFIG_FILE"
  echo "   $SERVICE_FILE"
  echo ""
  echo "   diff $CONFIG_FILE ~/.config/litellm/config.yaml"
  echo "   diff $SERVICE_FILE ~/.config/systemd/user/litellm-proxy.service"
  # Convergence = same model/region set and same service unit (header comments ignored)
  LIVE_CFG="$HOME/.config/litellm/config.yaml"; LIVE_SVC="$HOME/.config/systemd/user/litellm-proxy.service"
  pairs() { [[ -f "$1" ]] && awk '/model: vertex_ai\//{sub("vertex_ai/","",$2); m=$2} /vertex_location:/{print m, $2}' "$1" | sort; }
  # 4.1.0: settings (litellm_settings/general_settings) count too: a model-only
  # comparison reported CONVERGED while the live config lacked general_settings.
  settings() { [[ -f "$1" ]] && sed -n '/^litellm_settings:/,$p' "$1" | grep -v '^\s*#' | grep -v '^\s*$'; }
  if [[ "$(pairs "$CONFIG_FILE")" == "$(pairs "$LIVE_CFG")" ]] && [[ "$(settings "$CONFIG_FILE")" == "$(settings "$LIVE_CFG")" ]] \
     && diff -q "$SERVICE_FILE" "$LIVE_SVC" >/dev/null 2>&1; then
    echo ""; echo "DRY_RUN_RESULT=CONVERGED"
  else
    echo ""; echo "Model/region changes (- live, + generated):"
    diff <(pairs "$LIVE_CFG") <(pairs "$CONFIG_FILE") | grep '^[<>]' | sed 's/^</  -/; s/^>/  +/' || true
    [[ "$(settings "$CONFIG_FILE")" == "$(settings "$LIVE_CFG")" ]] || echo "  config settings differ (litellm_settings/general_settings)"
    diff -q "$SERVICE_FILE" "$LIVE_SVC" >/dev/null 2>&1 || echo "  service unit differs"
    echo "DRY_RUN_RESULT=PENDING"
  fi
  exit 0
fi

# Enable linger, reload, enable, restart
loginctl enable-linger "$(whoami)" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable litellm-proxy.service
systemctl --user restart litellm-proxy.service

echo ""
echo "Waiting for proxy to start..."
sleep 4

if systemctl --user is-active litellm-proxy &>/dev/null; then
  echo "✅ litellm-proxy is active"
else
  echo "❌ litellm-proxy failed to start"
  echo "   Check: journalctl --user -u litellm-proxy --no-pager -n 20"
  exit 1
fi

# Quick health check
HEALTH=$(curl -sf "http://127.0.0.1:$PORT/health" 2>/dev/null || echo '{}')
HEALTHY=$(echo "$HEALTH" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("healthy_count",0))' 2>/dev/null || echo "0")

if [[ "$HEALTHY" -ge 1 ]]; then
  echo "✅ Proxy healthy ($HEALTHY endpoint(s))"
else
  echo "❌ Proxy not healthy yet — may need a few more seconds"
  echo "   Check: curl http://127.0.0.1:$PORT/health"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Setup complete"
echo "  Models: ${MODELS[*]}"
echo "  Config: $HOME/.config/litellm/config.yaml"
echo "  Port:   $PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
