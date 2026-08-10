#!/usr/bin/env bash
# setup.sh — Set up LiteLLM proxy for Vertex AI with systemd
# Usage: bash setup.sh --project PROJECT --sa-key PATH [--region REGION] [--port PORT] [--dry-run]
# Exit codes: 0 = success, 1 = failure, 2 = usage error
set -euo pipefail

PROJECT=""
SA_KEY=""
REGION="us-east5"
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
    --region)   REGION="$2"; shift 2 ;;
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
      echo "  --region  REGION   Vertex AI region (default: us-east5)"
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
  PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
  if [[ -z "$PROJECT" ]]; then
    echo "❌ --project is required (or set via gcloud config)"
    exit 2
  fi
  echo "Auto-detected project: $PROJECT"
fi

if [[ -z "$SA_KEY" ]]; then
  SA_KEY=$(find ~/.config/gcloud/legacy_credentials -name "adc.json" 2>/dev/null | head -1 || echo "")
  if [[ -z "$SA_KEY" ]]; then
    echo "❌ --sa-key is required (no SA key auto-detected)"
    exit 2
  fi
  echo "Auto-detected SA key: $SA_KEY"
fi

if [[ ! -f "$SA_KEY" ]]; then
  echo "❌ SA key file not found: $SA_KEY"
  exit 1
fi

# Resolve to absolute path
SA_KEY=$(realpath "$SA_KEY")

# Find litellm binary
LITELLM_BIN=$(which litellm 2>/dev/null || echo "")
if [[ -z "$LITELLM_BIN" ]]; then
  echo "❌ litellm not found. Install with: uv tool install 'litellm[proxy]'"
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

# --- Discover models ---
echo "Discovering models on $REGION..."
TOKEN=$(gcloud auth print-access-token 2>/dev/null || echo "")
if [[ -z "$TOKEN" ]]; then
  echo "❌ Could not get access token. Run 'gcloud auth login' first."
  exit 1
fi

URL_BASE="https://${REGION}-aiplatform.googleapis.com/v1/projects/$PROJECT/locations/$REGION/publishers/anthropic/models"
MODELS=()

for model in claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-5 claude-sonnet-4-5 claude-opus-4-7 claude-opus-4-8 claude-opus-5 claude-sonnet-5; do
  RESP=$(curl -sf -w "%{http_code}" -o /dev/null \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$URL_BASE/$model:rawPredict" \
    -d '{"anthropic_version":"vertex-2023-10-16","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' 2>/dev/null || echo "000")
  if [[ "$RESP" == "200" ]]; then
    echo "  ✅ $model"
    MODELS+=("$model")
  fi
done

if [[ ${#MODELS[@]} -eq 0 ]]; then
  echo "❌ No models available on $REGION for project $PROJECT"
  exit 1
fi

echo ""
echo "Found ${#MODELS[@]} model(s)"

# --- Generate config.yaml ---
mkdir -p "$CONFIG_DIR"

# Backup existing config
if [[ -f "$CONFIG_FILE" && "$DRY_RUN" != true ]]; then
  BACKUP="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP"
  echo "📋 Config backup: $BACKUP"
fi

cat > "$CONFIG_FILE" << 'HEADER'
model_list:
HEADER

for model in "${MODELS[@]}"; do
  cat >> "$CONFIG_FILE" << EOF
  - model_name: $model
    litellm_params:
      model: vertex_ai/$model
      vertex_project: $PROJECT
      vertex_location: $REGION

EOF
done

cat >> "$CONFIG_FILE" << 'FOOTER'
litellm_settings:
  drop_params: true
  request_timeout: 120
FOOTER

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
Environment=GOOGLE_APPLICATION_CREDENTIALS=$SA_KEY
ExecStart=$LITELLM_BIN --config $HOME/.config/litellm/config.yaml --host 127.0.0.1 --port $PORT
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
