#!/usr/bin/env bash
# setup-fuseki.sh — Install Apache Jena + Fuseki and configure as systemd user service
# Usage: bash setup-fuseki.sh [--dry-run] [--version VERSION]
# Idempotent: safe to run multiple times.
set -euo pipefail

# ══════════════════════════════════════════════════════
# Dry-run support
# ══════════════════════════════════════════════════════

DRY_RUN=false
CHANGES=0
ERRORS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
  esac
done

# Strip --dry-run/--check from positional args
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in --dry-run|--check) ;; *) POSITIONAL+=("$arg") ;; esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

apply() {
  local description="$1"; shift
  if $DRY_RUN; then
    echo "[dry-run] WOULD: $description"
    CHANGES=$((CHANGES + 1))
  else
    "$@"
  fi
}

# ══════════════════════════════════════════════════════
# Configuration
# ══════════════════════════════════════════════════════

JENA_VERSION="${1:-6.1.0}"
JENA_MIRROR="https://dlcdn.apache.org/jena/binaries"

INSTALL_DIR="${HOME}/.local/share"
JENA_DIR="${INSTALL_DIR}/apache-jena-${JENA_VERSION}"
FUSEKI_DIR="${INSTALL_DIR}/apache-jena-fuseki-${JENA_VERSION}"
JENA_LINK="${INSTALL_DIR}/apache-jena"
FUSEKI_LINK="${INSTALL_DIR}/apache-jena-fuseki"
DATA_DIR="${INSTALL_DIR}/fuseki-data"

SYSTEMD_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_DIR}/fuseki.service"

PASS=0
SKIP=0

info()  { echo "  [+] $*"; }
skip()  { echo "  [~] $* (already done)"; SKIP=$((SKIP + 1)); }
ok()    { echo "  [✓] $*"; PASS=$((PASS + 1)); }
fail()  { echo "  [✗] $*" >&2; exit 1; }

echo "══════════════════════════════════════════════════════"
echo "  Fuseki Setup — Apache Jena ${JENA_VERSION}"
echo "══════════════════════════════════════════════════════"
echo ""

# ══════════════════════════════════════════════════════
# Step 1: Check Java
# ══════════════════════════════════════════════════════

info "Checking Java..."
if ! command -v java &>/dev/null; then
    fail "Java not found. Install Java 17+ and try again."
fi

JAVA_VER=$(java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]\+\).*/\1/p')
if [[ -z "$JAVA_VER" ]]; then
    JAVA_VER=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
fi

if [[ "$JAVA_VER" -lt 17 ]]; then
    fail "Java ${JAVA_VER} found but 17+ required."
fi
ok "Java ${JAVA_VER} found"

# ══════════════════════════════════════════════════════
# Step 2: Download Jena CLI tools
# ══════════════════════════════════════════════════════

info "Checking Jena CLI tools..."
if [[ -d "$JENA_DIR" ]]; then
    skip "Jena ${JENA_VERSION} already installed at ${JENA_DIR}"
else
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Download and install Jena ${JENA_VERSION}"
      CHANGES=$((CHANGES + 1))
    else
      info "Downloading Apache Jena ${JENA_VERSION}..."
      wget -q "${JENA_MIRROR}/apache-jena-${JENA_VERSION}.tar.gz" \
          -O "${INSTALL_DIR}/apache-jena.tar.gz"
      tar xzf "${INSTALL_DIR}/apache-jena.tar.gz" -C "${INSTALL_DIR}"
      rm -f "${INSTALL_DIR}/apache-jena.tar.gz"
      ok "Jena CLI tools installed at ${JENA_DIR}"
    fi
fi

# Create stable symlink
if $DRY_RUN; then
  if [[ ! -L "${JENA_LINK}" ]] || [[ "$(readlink "${JENA_LINK}")" != "apache-jena-${JENA_VERSION}" ]]; then
    echo "[dry-run] WOULD: Create symlink ${JENA_LINK}"
    CHANGES=$((CHANGES + 1))
  else
    echo "[dry-run] NO CHANGE — Jena symlink already correct"
  fi
else
  ln -sfn "apache-jena-${JENA_VERSION}" "${JENA_LINK}"
  ok "Symlink: ${JENA_LINK} → apache-jena-${JENA_VERSION}"
fi

# ══════════════════════════════════════════════════════
# Step 3: Download Jena Fuseki
# ══════════════════════════════════════════════════════

info "Checking Jena Fuseki..."
if [[ -d "$FUSEKI_DIR" ]]; then
    skip "Fuseki ${JENA_VERSION} already installed at ${FUSEKI_DIR}"
else
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Download and install Fuseki ${JENA_VERSION}"
      CHANGES=$((CHANGES + 1))
    else
      info "Downloading Apache Jena Fuseki ${JENA_VERSION}..."
      wget -q "${JENA_MIRROR}/apache-jena-fuseki-${JENA_VERSION}.tar.gz" \
          -O "${INSTALL_DIR}/apache-jena-fuseki.tar.gz"
      tar xzf "${INSTALL_DIR}/apache-jena-fuseki.tar.gz" -C "${INSTALL_DIR}"
      rm -f "${INSTALL_DIR}/apache-jena-fuseki.tar.gz"
      ok "Fuseki installed at ${FUSEKI_DIR}"
    fi
fi

# Create stable symlink
if $DRY_RUN; then
  if [[ ! -L "${FUSEKI_LINK}" ]] || [[ "$(readlink "${FUSEKI_LINK}")" != "apache-jena-fuseki-${JENA_VERSION}" ]]; then
    echo "[dry-run] WOULD: Create symlink ${FUSEKI_LINK}"
    CHANGES=$((CHANGES + 1))
  else
    echo "[dry-run] NO CHANGE — Fuseki symlink already correct"
  fi
else
  ln -sfn "apache-jena-fuseki-${JENA_VERSION}" "${FUSEKI_LINK}"
  ok "Symlink: ${FUSEKI_LINK} → apache-jena-fuseki-${JENA_VERSION}"
fi

# ══════════════════════════════════════════════════════
# Step 4: Create data directory
# ══════════════════════════════════════════════════════

if [[ -d "$DATA_DIR" ]]; then
    skip "Data directory already exists: ${DATA_DIR}"
else
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Create data directory ${DATA_DIR}"
      CHANGES=$((CHANGES + 1))
    else
      mkdir -p "$DATA_DIR"
      ok "Created data directory: ${DATA_DIR}"
    fi
fi

# ══════════════════════════════════════════════════════
# Step 5: Add to PATH via .bashrc
# ══════════════════════════════════════════════════════

info "Checking PATH configuration..."
if grep -q 'apache-jena' "${HOME}/.bashrc" 2>/dev/null; then
    skip "Jena PATH entries already in .bashrc"
else
    if $DRY_RUN; then
      echo "[dry-run] WOULD: Add JENA_HOME, FUSEKI_HOME, PATH to .bashrc"
      CHANGES=$((CHANGES + 1))
    else
      cat >> "${HOME}/.bashrc" << 'BASHRC_EOF'

# Apache Jena (managed by fuseki skill)
export JENA_HOME="${HOME}/.local/share/apache-jena"
export FUSEKI_HOME="${HOME}/.local/share/apache-jena-fuseki"
export PATH="${JENA_HOME}/bin:${FUSEKI_HOME}:${PATH}"
BASHRC_EOF
      ok "Added JENA_HOME, FUSEKI_HOME, and PATH to .bashrc"
    fi
fi

# ══════════════════════════════════════════════════════
# Step 6: Install systemd user service
# ══════════════════════════════════════════════════════

info "Configuring systemd user service..."

if $DRY_RUN; then
  if [[ ! -f "${SERVICE_FILE}" ]]; then
    echo "[dry-run] WOULD: Create systemd unit ${SERVICE_FILE}"
    CHANGES=$((CHANGES + 1))
  else
    echo "[dry-run] NO CHANGE — systemd unit already exists"
  fi
  echo "[dry-run] WOULD: Reload systemd and enable fuseki.service"
  CHANGES=$((CHANGES + 1))
else
  mkdir -p "${SYSTEMD_DIR}"

  # Always write the service file (idempotent — overwrites with same content)
  cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Apache Jena Fuseki SPARQL Server
After=network.target

[Service]
Type=simple
Environment=JAVA_HOME=$(dirname $(dirname $(readlink -f $(command -v java))))
Environment=FUSEKI_HOME=${FUSEKI_LINK}
Environment=FUSEKI_BASE=${DATA_DIR}
ExecStart=${FUSEKI_LINK}/fuseki-server --update --port=3030
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

  ok "Wrote systemd unit: ${SERVICE_FILE}"

  # Reload systemd and enable (but don't start)
  systemctl --user daemon-reload
  systemctl --user enable fuseki.service 2>/dev/null
  ok "Service enabled (will not auto-start until 'fuseki start')"
fi

# ══════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════

echo ""
if $DRY_RUN; then
  echo "══════════════════════════════════════════════════════"
  if [[ $CHANGES -eq 0 ]]; then
    echo "  DRY_RUN_RESULT=CONVERGED"
  else
    echo "  DRY_RUN_RESULT=PENDING"
  fi
  echo "  Changes: ${CHANGES}"
  echo "══════════════════════════════════════════════════════"
else
  echo "══════════════════════════════════════════════════════"
  if [[ $ERRORS -eq 0 ]]; then
    echo "  APPLY_RESULT=OK"
  else
    echo "  APPLY_RESULT=PARTIAL"
  fi
  echo "  Setup Complete: ${PASS} done, ${SKIP} skipped"
  echo "══════════════════════════════════════════════════════"
  echo ""
  echo "  Jena CLI:  ${JENA_LINK}/bin/"
  echo "  Fuseki:    ${FUSEKI_LINK}/"
  echo "  Data:      ${DATA_DIR}/"
  echo "  Service:   ${SERVICE_FILE}"
  echo ""
  echo "  Next: run 'fuseki start' or:"
  echo "    systemctl --user start fuseki"
  echo "══════════════════════════════════════════════════════"
fi
