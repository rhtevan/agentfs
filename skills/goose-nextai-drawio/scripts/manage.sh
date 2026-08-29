#!/usr/bin/env bash
# manage.sh — Setup, teardown, upgrade, and status for next-ai-draw-io MCP extension in Goose
# Usage: bash manage.sh <setup|teardown|upgrade|status>
set -euo pipefail

PACKAGE_NAME="@next-ai-drawio/mcp-server"
BIN_NAME="next-ai-drawio-mcp"
EXTENSION_KEY="nextaidrawio"
GOOSE_CONFIG="${HOME}/.config/goose/config.yaml"
NPM_PREFIX="${HOME}/.local/share/goose-nextai-drawio"

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }

check_node() {
    command -v node >/dev/null 2>&1 || die "Node.js not found. Install Node.js >= 18."
    local ver
    ver=$(node --version | sed 's/^v//')
    local major
    major=$(echo "$ver" | cut -d. -f1)
    if [ "$major" -lt 18 ]; then
        die "Node.js >= 18 required. Found: v${ver}"
    fi
    info "Node.js v${ver} — OK"
}

check_npm() {
    command -v npm >/dev/null 2>&1 || die "npm not found."
}

get_installed_version() {
    local pkg_json="${NPM_PREFIX}/node_modules/${PACKAGE_NAME}/package.json"
    if [ -f "$pkg_json" ]; then
        python3 -c "import json; print(json.load(open('${pkg_json}'))['version'])" 2>/dev/null || true
    fi
}

get_binary_path() {
    # npm --prefix puts .bin links in node_modules/.bin/
    local path="${NPM_PREFIX}/node_modules/.bin/${BIN_NAME}"
    if [ -x "$path" ]; then
        echo "$path"
        return
    fi
    # Fallback: resolve from package.json bin field via node
    local entry="${NPM_PREFIX}/node_modules/${PACKAGE_NAME}/dist/index.js"
    if [ -f "$entry" ]; then
        echo "$entry"
        return
    fi
    # Last resort: search PATH
    command -v "$BIN_NAME" 2>/dev/null || true
}

backup_config() {
    if [ -f "$GOOSE_CONFIG" ]; then
        local ts
        ts=$(date +%Y%m%d_%H%M%S)
        cp "$GOOSE_CONFIG" "${GOOSE_CONFIG}.bak.${ts}"
        info "Config backed up to ${GOOSE_CONFIG}.bak.${ts}"
    fi
}

extension_registered() {
    grep -q "^  ${EXTENSION_KEY}:" "$GOOSE_CONFIG" 2>/dev/null
}

extension_enabled() {
    # Check if the extension block has enabled: true
    sed -n "/^  ${EXTENSION_KEY}:/,/^  [a-z]/p" "$GOOSE_CONFIG" 2>/dev/null | grep -q "enabled: true"
}

# --- Operations ---

do_setup() {
    info "=== Setting up next-ai-draw-io MCP extension ==="

    check_node
    check_npm

    # Ensure prefix directory exists
    mkdir -p "${NPM_PREFIX}"

    # Check if already installed
    local current_ver
    current_ver=$(get_installed_version)
    if [ -n "$current_ver" ]; then
        info "Package already installed: ${PACKAGE_NAME}@${current_ver}"
    else
        info "Installing ${PACKAGE_NAME} to ${NPM_PREFIX}..."
        npm install --prefix "${NPM_PREFIX}" "${PACKAGE_NAME}@latest"
        current_ver=$(get_installed_version)
        info "Installed: ${PACKAGE_NAME}@${current_ver}"
    fi

    # Locate binary
    local bin_path
    bin_path=$(get_binary_path)
    if [ -z "$bin_path" ]; then
        die "Binary '${BIN_NAME}' not found after install. Check npm global bin directory is in PATH."
    fi
    info "Binary: ${bin_path}"

    # Check Goose config exists
    if [ ! -f "$GOOSE_CONFIG" ]; then
        die "Goose config not found at ${GOOSE_CONFIG}"
    fi

    # Check if already registered
    if extension_registered; then
        info "Extension '${EXTENSION_KEY}' already registered in Goose config."
        info "Updating binary path..."
        backup_config
        # Use python to safely update cmd/args for existing entry
        python3 << PYEOF2
import yaml

config_path = "${GOOSE_CONFIG}"
bin_path = "${bin_path}"

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

ext = config['extensions']['${EXTENSION_KEY}']
if bin_path.endswith('.js'):
    ext['cmd'] = 'node'
    ext['args'] = [bin_path]
else:
    ext['cmd'] = bin_path
    ext['args'] = []

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

print("INFO: Binary path updated")
PYEOF2
    else
        backup_config
        info "Adding extension to Goose config..."

        # Find the extensions: block and append after the last extension entry.
        # We insert before the first non-extension top-level key after extensions:.
        # Strategy: append the block right before the line that ends the extensions section.
        python3 << PYEOF
import yaml, sys, copy

config_path = "${GOOSE_CONFIG}"
bin_path = "${bin_path}"

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

if 'extensions' not in config or not isinstance(config.get('extensions'), dict):
    print("ERROR: No 'extensions' section in config", file=sys.stderr)
    sys.exit(1)

if '${EXTENSION_KEY}' in config['extensions']:
    print("INFO: Extension already exists, skipping")
    sys.exit(0)

# Determine cmd and args based on whether bin_path is a .js file or native binary
if bin_path.endswith('.js'):
    cmd = 'node'
    args = [bin_path]
else:
    cmd = bin_path
    args = []

config['extensions']['${EXTENSION_KEY}'] = {
    'enabled': False,
    'type': 'stdio',
    'name': 'Next AI Drawio',
    'description': 'AI-powered draw.io diagram generation with real-time browser preview via MCP',
    'cmd': cmd,
    'args': args,
    'envs': {},
    'env_keys': [],
    'timeout': 300,

}

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

print("INFO: Extension registered successfully")
PYEOF
    fi

    echo ""
    info "=== Setup complete ==="
    info "Package: ${PACKAGE_NAME}@${current_ver}"
    info "Binary:  ${bin_path}"
    info "Config:  ${GOOSE_CONFIG}"
    info ""
    info "The extension is registered but DISABLED by default."
    info "To activate: restart Goose, then enable 'nextaidrawio' in settings"
    info "or use manage_extensions tool."
    info ""
    info "NOTE: This extension adds ~1,600 tokens to every turn when enabled."
}

do_teardown() {
    info "=== Tearing down next-ai-draw-io MCP extension ==="

    # Remove from config
    if [ -f "$GOOSE_CONFIG" ] && extension_registered; then
        backup_config
        info "Removing extension from Goose config..."
        python3 << PYEOF
import yaml

config_path = "${GOOSE_CONFIG}"

with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

if 'extensions' in config and '${EXTENSION_KEY}' in config['extensions']:
    del config['extensions']['${EXTENSION_KEY}']
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    print("INFO: Extension removed from config")
else:
    print("INFO: Extension not found in config, nothing to remove")
PYEOF
    else
        info "Extension not registered in config, skipping."
    fi

    # Uninstall package
    local current_ver
    current_ver=$(get_installed_version)
    if [ -n "$current_ver" ]; then
        info "Uninstalling ${PACKAGE_NAME}..."
        rm -rf "${NPM_PREFIX}"
        info "Package uninstalled (removed ${NPM_PREFIX})."
    else
        info "Package not installed, skipping."
    fi

    echo ""
    info "=== Teardown complete ==="
    info "Restart Goose for changes to take effect."
}

do_upgrade() {
    info "=== Upgrading next-ai-draw-io MCP extension ==="

    check_node
    check_npm

    local old_ver
    old_ver=$(get_installed_version)
    if [ -z "$old_ver" ]; then
        die "Package not installed. Run 'setup' first."
    fi
    info "Current version: ${old_ver}"

    info "Upgrading ${PACKAGE_NAME}..."
    npm install --prefix "${NPM_PREFIX}" "${PACKAGE_NAME}@latest"

    local new_ver
    new_ver=$(get_installed_version)
    info "New version: ${new_ver}"

    if [ "$old_ver" = "$new_ver" ]; then
        info "Already at latest version."
    else
        info "Upgraded: ${old_ver} → ${new_ver}"
    fi

    # Verify binary path still valid in config
    if [ -f "$GOOSE_CONFIG" ] && extension_registered; then
        local bin_path
        bin_path=$(get_binary_path)
        if [ -n "$bin_path" ]; then
            info "Binary path: ${bin_path} — OK"
        else
            warn "Binary not found after upgrade. Re-run setup to fix config."
        fi
    fi

    echo ""
    info "=== Upgrade complete ==="
    info "Restart Goose if the extension is currently active."
}

do_status() {
    info "=== next-ai-draw-io MCP extension status ==="
    echo ""

    # Package status
    local ver
    ver=$(get_installed_version)
    if [ -n "$ver" ]; then
        echo "Package:    INSTALLED (${PACKAGE_NAME}@${ver})"
    else
        echo "Package:    NOT INSTALLED"
    fi

    # Binary status
    local bin_path
    bin_path=$(get_binary_path)
    if [ -n "$bin_path" ]; then
        echo "Binary:     ${bin_path}"
    else
        echo "Binary:     NOT FOUND"
    fi

    # Config status
    if [ ! -f "$GOOSE_CONFIG" ]; then
        echo "Config:     NOT FOUND (${GOOSE_CONFIG})"
    elif extension_registered; then
        if extension_enabled; then
            echo "Registered: YES (ENABLED)"
            echo "            ⚠️  ~1,600 tokens added to every turn"
        else
            echo "Registered: YES (disabled)"
        fi
    else
        echo "Registered: NO"
    fi
}

# --- Main ---

case "${1:-}" in
    setup)    do_setup ;;
    teardown) do_teardown ;;
    upgrade)  do_upgrade ;;
    status)   do_status ;;
    *)
        echo "Usage: bash $0 <setup|teardown|upgrade|status>"
        exit 2
        ;;
esac
