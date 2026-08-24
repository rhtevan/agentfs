#!/usr/bin/env bash
# install-desktop.sh — Create DSH launcher, systemd service, .desktop file
# Usage: bash install-desktop.sh
set -euo pipefail

DSH_DIR="$HOME/.local/share/dsh"
LAUNCHER="$HOME/.local/bin/dsh-launcher"
DESKTOP_FILE="$HOME/.local/share/applications/dsh.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_FILE="$ICON_DIR/dsh.png"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DSH_PORT=3080
SERVICE_NAME="dsh.service"
SERVICE_FILE="$HOME/.config/systemd/user/$SERVICE_NAME"

# --- Preflight ---
if [[ ! -x "$DSH_DIR/node_modules/.bin/dsh" ]]; then
  echo "❌ DSH not installed. Run install.sh first." >&2
  exit 1
fi

if ! command -v google-chrome &>/dev/null; then
  echo "❌ Google Chrome not found. Install it first." >&2
  exit 1
fi

# --- Create systemd user service ---
mkdir -p "$(dirname "$SERVICE_FILE")"
cat > "$SERVICE_FILE" << SVCEOF
[Unit]
Description=DeepSeek Harness Backend
After=network.target

[Service]
Type=exec
WorkingDirectory=$DSH_DIR

# Explicit PATH — excludes Goose hermit wrappers
Environment=PATH=$HOME/.local/share/pnpm:$DSH_DIR/node_modules/.bin:/usr/local/bin:/usr/bin:/bin
Environment=LITELLM_VERTEX_AI_API_KEY=sk-litellm-local-no-auth
Environment=DSH_TELEMETRY_MODE=DISABLED
Environment=HOME=$HOME

ExecStart=$DSH_DIR/node_modules/.bin/dsh web --no-open

Restart=no
TimeoutStartSec=30
TimeoutStopSec=10

# Resource limits
MemoryMax=512M
CPUQuota=50%

[Install]
WantedBy=default.target
SVCEOF

systemctl --user daemon-reload
echo "✅ Systemd service written to $SERVICE_FILE"

# --- Create launcher wrapper ---
mkdir -p "$(dirname "$LAUNCHER")"
cat > "$LAUNCHER" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# dsh-launcher — Start DSH backend (systemd) + Chrome app-mode window
# Stops backend automatically when all browser connections close.
set -euo pipefail

DSH_PORT=3080
DSH_URL="http://127.0.0.1:$DSH_PORT"
IDLE_GRACE=3        # polls (×5s = 15s) with no connections before stopping
SERVICE="dsh.service"

# --- Start backend via systemd ---
if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
  echo "ℹ️  DSH backend already running"
else
  echo "🚀 Starting DSH backend..."
  systemctl --user start "$SERVICE"

  # Wait for port to be ready
  echo -n "⏳ Waiting for port $DSH_PORT"
  for i in $(seq 1 30); do
    if curl -s --connect-timeout 1 "$DSH_URL" >/dev/null 2>&1; then
      echo " ✅"
      break
    fi
    echo -n "."
    sleep 0.5
  done

  if ! curl -s --connect-timeout 2 "$DSH_URL" >/dev/null 2>&1; then
    echo " ❌"
    echo "Backend failed to start. Check: journalctl --user -u $SERVICE" >&2
    exit 1
  fi
fi

# --- Launch Chrome app window ---
echo "🌐 Opening DSH in Chrome..."
google-chrome \
  --app="$DSH_URL" \
  --class="dsh" \
  --new-window \
  2>/dev/null

# Chrome --app merges into existing session and returns immediately.
# Monitor active TCP connections to detect when user closes the window.
echo "🔍 Monitoring connections — backend will stop when browser disconnects."

idle_count=0
while true; do
  sleep 5

  # Check if backend is still running
  if ! systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
    echo "ℹ️  Backend already stopped"
    break
  fi

  # Count established connections to DSH port (excludes LISTEN)
  conn_count=$(ss -tn state established "( sport = :$DSH_PORT )" 2>/dev/null | tail -n +2 | wc -l)

  if [[ "$conn_count" -gt 0 ]]; then
    idle_count=0
  else
    idle_count=$((idle_count + 1)) || true
    if [[ $idle_count -ge $IDLE_GRACE ]]; then
      echo "👋 No browser connections for $((IDLE_GRACE * 5))s — stopping backend"
      systemctl --user stop "$SERVICE"
      break
    fi
  fi
done

echo "✅ DSH shutdown complete"
LAUNCHER_EOF

chmod +x "$LAUNCHER"
echo "✅ Launcher written to $LAUNCHER"

# --- Generate icon ---
mkdir -p "$ICON_DIR"
if [[ -f "$SKILL_DIR/assets/dsh.png" ]]; then
  # Install to multiple hicolor sizes
  for size in 48 128 256 1024; do
    target_dir="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$target_dir"
    if command -v magick &>/dev/null; then
      magick "$SKILL_DIR/assets/dsh.png" -resize "${size}x${size}" "$target_dir/dsh.png"
    else
      cp "$SKILL_DIR/assets/dsh.png" "$target_dir/dsh.png"
    fi
  done
  echo "✅ Icon installed to hicolor sizes"
else
  if command -v convert &>/dev/null; then
    convert -size 256x256 xc:"#4A6CF7" \
      -gravity center -pointsize 96 -fill white \
      -font Helvetica-Bold -annotate 0 "DSH" \
      "$ICON_FILE" 2>/dev/null && echo "✅ Placeholder icon generated" || true
  fi
  if [[ ! -f "$ICON_FILE" ]]; then
    echo "⚠️  No icon available. Desktop entry will use a generic icon."
    ICON_FILE="utilities-terminal"
  fi
fi

# Update icon cache
if command -v gtk-update-icon-cache &>/dev/null; then
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

# --- Create .desktop file ---
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=DeepSeek Harness
Comment=DeepSeek Harness — Agentic AI Harness (WebUI)
GenericName=AI Agent Harness
Exec=$LAUNCHER
Icon=$ICON_FILE
Type=Application
StartupNotify=true
StartupWMClass=chrome-127.0.0.1__-Default
Categories=Development;ArtificialIntelligence;
Keywords=deepseek;dsh;agent;harness;ai;
EOF

echo "✅ Desktop file written to $DESKTOP_FILE"

# Update desktop database
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
  echo "✅ Desktop database updated"
fi

echo ""
echo "🎉 DSH desktop launcher installed!"
echo "   Launch from GNOME: search 'DeepSeek Harness'"
echo "   Launch from terminal: dsh-launcher"
echo "   Service control: systemctl --user start|stop|status dsh"
echo "   Logs: journalctl --user -u dsh"
