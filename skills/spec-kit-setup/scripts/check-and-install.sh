#!/usr/bin/env bash
# check-and-install.sh — Detect spec-kit (specify CLI), install or upgrade
# to the latest release from github/spec-kit.
#
# Usage: bash check-and-install.sh [--json] [--force] [--tag vX.Y.Z]
#
#   --json    Machine-readable JSON output
#   --force   Upgrade even if already at latest
#   --tag     Pin to a specific release tag instead of latest
#
# Exit codes:
#   0  Success (installed, upgraded, or already current)
#   1  Fatal error (no uv, no python3, network failure)
#   2  User-actionable issue (printed to stderr)

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────
JSON_MODE=false
FORCE=false
PIN_TAG=""
REPO="github/spec-kit"
REPO_URL="https://github.com/${REPO}.git"
PACKAGE_NAME="specify-cli"

# ── Parse args ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)  JSON_MODE=true; shift ;;
    --force) FORCE=true; shift ;;
    --tag)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "ERROR: --tag requires a value (e.g., --tag v0.11.8)" >&2
        exit 2
      fi
      PIN_TAG="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--json] [--force] [--tag vX.Y.Z]"
      exit 0 ;;
    *) echo "ERROR: Unknown option '$1'" >&2; exit 2 ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────
log()  { $JSON_MODE || echo "[spec-kit-setup] $*"; }
warn() { echo "[spec-kit-setup] WARNING: $*" >&2; }
die()  { echo "[spec-kit-setup] ERROR: $*" >&2; exit 1; }

json_result() {
  # $1=action  $2=version  $3=latest_tag  $4=message
  if $JSON_MODE; then
    python3 -c "
import json, sys
print(json.dumps({
    'action': sys.argv[1],
    'version': sys.argv[2],
    'latest_tag': sys.argv[3],
    'message': sys.argv[4]
}))" "$1" "$2" "$3" "$4"
  fi
}

# Parse the installed version from `specify version` output.
# Handles both old format (separate CLI Version + Template Version)
# and new format (single CLI Version that matches the release tag).
parse_specify_version() {
  local output="$1"
  local template_ver cli_ver

  # Try Template Version first (old format: ≤ v0.0.x CLI)
  template_ver=$(echo "$output" \
    | grep -i 'Template Version' \
    | sed -E 's/.*Template Version[[:space:]]+([0-9][0-9.]*).*/\1/' \
    | head -1) || true

  if [[ -n "$template_ver" ]]; then
    echo "$template_ver"
    return 0
  fi

  # Fall back to CLI Version (new format: CLI version IS the release version)
  cli_ver=$(echo "$output" \
    | grep -i 'CLI Version' \
    | sed -E 's/.*CLI Version[[:space:]]+([0-9][0-9.]*).*/\1/' \
    | head -1) || true

  echo "${cli_ver:-unknown}"
}

# ── Step 1: Locate uv ───────────────────────────────────────────────
find_uv() {
  # Priority: PATH → well-known locations → nix store
  if command -v uv &>/dev/null; then
    command -v uv
    return 0
  fi
  for candidate in \
    "$HOME/.hermes/bin/uv" \
    "$HOME/.local/bin/uv" \
    "$HOME/.cargo/bin/uv"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  # Search nix store (pick newest by modification time)
  local nix_uv
  nix_uv=$(find /nix/store -maxdepth 2 -name "uv" -type f -executable 2>/dev/null \
            | xargs -r ls -t 2>/dev/null | head -1) || true
  if [[ -n "$nix_uv" ]]; then
    echo "$nix_uv"
    return 0
  fi
  return 1
}

UV_BIN=""
if ! UV_BIN=$(find_uv); then
  die "uv not found. Install uv first: https://docs.astral.sh/uv/"
fi
UV_VERSION=$("$UV_BIN" --version 2>/dev/null || echo "unknown")
log "Using uv: $UV_BIN ($UV_VERSION)"

# ── Step 2: Check python3 ───────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  die "python3 not found. Python 3.11+ is required."
fi

# ── Step 3: Detect current installation ──────────────────────────────
INSTALLED=false
CURRENT_VERSION=""

if command -v specify &>/dev/null; then
  INSTALLED=true
  VERSION_OUTPUT=$(specify version 2>/dev/null || true)
  CURRENT_VERSION=$(parse_specify_version "$VERSION_OUTPUT")
  log "Installed: specify v${CURRENT_VERSION}"
else
  log "spec-kit (specify CLI) is not installed."
fi

# ── Step 4: Determine target version ─────────────────────────────────
LATEST_TAG=""
if [[ -n "$PIN_TAG" ]]; then
  LATEST_TAG="$PIN_TAG"
  log "Pinned to tag: $LATEST_TAG"
else
  log "Fetching latest release from github.com/${REPO}..."
  LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null) || true
  if [[ -z "$LATEST_TAG" ]]; then
    warn "Could not fetch latest release tag from GitHub API."
    if $INSTALLED; then
      log "Keeping current installation."
      json_result "current" "$CURRENT_VERSION" "unknown" \
        "Could not reach GitHub API; keeping current installation"
      exit 0
    else
      die "Cannot determine version to install and no existing installation found."
    fi
  fi
  log "Latest release: $LATEST_TAG"
fi

# Strip leading 'v' for bare version comparison
LATEST_VERSION="${LATEST_TAG#v}"

# ── Step 5: Decide action ────────────────────────────────────────────
ACTION=""
if ! $INSTALLED; then
  ACTION="install"
elif $FORCE; then
  ACTION="upgrade"
  log "Force flag set — reinstalling regardless of version."
elif [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
  ACTION="current"
  log "Already at latest version ($LATEST_VERSION). Nothing to do."
  json_result "current" "$CURRENT_VERSION" "$LATEST_TAG" \
    "Already at latest version"
  exit 0
else
  ACTION="upgrade"
  log "Upgrade available: v${CURRENT_VERSION} → ${LATEST_TAG}"
fi

# ── Step 6: Install or upgrade ───────────────────────────────────────
DISPLAY_ACTION="Installing"
[[ "$ACTION" == "upgrade" ]] && DISPLAY_ACTION="Upgrading"
log "${DISPLAY_ACTION} specify-cli from ${REPO_URL}@${LATEST_TAG}..."

INSTALL_CMD=(
  "$UV_BIN" tool install "$PACKAGE_NAME"
  --force
  --from "git+${REPO_URL}@${LATEST_TAG}"
)

if "${INSTALL_CMD[@]}" 2>&1; then
  log "${DISPLAY_ACTION%ing}ed successfully."
else
  EXIT_CODE=$?
  warn "uv tool install exited with code $EXIT_CODE"
  warn "Command was: ${INSTALL_CMD[*]}"
  json_result "error" "${CURRENT_VERSION:-none}" "$LATEST_TAG" \
    "uv tool install failed with exit code $EXIT_CODE"
  exit 1
fi

# ── Step 7: Verify installation ──────────────────────────────────────
# specify may not be on PATH yet if this is a fresh install
SPECIFY_BIN=""
if command -v specify &>/dev/null; then
  SPECIFY_BIN="specify"
elif [[ -x "$HOME/.local/bin/specify" ]]; then
  SPECIFY_BIN="$HOME/.local/bin/specify"
else
  warn "specify binary not found on PATH after install."
  warn "Add to your shell: export PATH=\"\$HOME/.local/bin:\$PATH\""
  json_result "$ACTION" "unknown" "$LATEST_TAG" \
    "${DISPLAY_ACTION%ing}ed but specify not found on PATH"
  exit 0
fi

NEW_VERSION_OUTPUT=$("$SPECIFY_BIN" version 2>/dev/null || true)
NEW_VERSION=$(parse_specify_version "$NEW_VERSION_OUTPUT")

log "Verified: specify v${NEW_VERSION}"

if [[ "$ACTION" == "install" ]]; then
  MSG="Fresh install of specify v${NEW_VERSION}"
else
  MSG="Upgraded from v${CURRENT_VERSION} to v${NEW_VERSION}"
fi

log "$MSG"

json_result "$ACTION" "$NEW_VERSION" "$LATEST_TAG" "$MSG"

# ── Step 8: Show quick-start hint ────────────────────────────────────
if ! $JSON_MODE; then
  echo ""
  echo "  Quick start:"
  echo "    specify init <project> --integration <agent>"
  echo "    specify version"
  echo "    specify check"
  echo ""
fi
