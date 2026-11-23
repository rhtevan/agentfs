#!/usr/bin/env bash
# upgrade.sh — Upgrade Skupper CLI + container images on podman sites
# Usage:
#   bash upgrade.sh                  — detect CRC baseline, upgrade all podman hosts
#   bash upgrade.sh --check          — show version comparison only, no changes
#   bash upgrade.sh --version 2.2.3  — override target version (skip CRC detection)
#
# CRC operator upgrades via OLM — this script does NOT touch CRC.
# Models are NOT stopped. Only Skupper infrastructure is affected.
#
# Upgrade flow:
#   1. Detect CRC baseline versions (CLI, router, controller)
#   2. Compare with current versions on each podman host
#   3. Download new CLI binary if needed
#   4. Pull new container images on each podman host
#   5. Recreate router + controller containers with new images
#
# Rollback: snapshot state before upgrade, restore on failure.

source "$(dirname "$0")/common.sh"

# ── Parse arguments ───────────────────────────────────────────
CHECK_ONLY=false
OVERRIDE_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --version) OVERRIDE_VERSION="$2"; shift 2 ;;
    *) echo "❌ Unknown argument: $1"; exit 1 ;;
  esac
done

echo "=== Skupper Model Provider — UPGRADE ==="
echo

# ── Phase 1: Detect CRC baseline ─────────────────────────────
echo "Phase 1: Detect CRC baseline"

if [[ -n "$OVERRIDE_VERSION" ]]; then
  TARGET_VERSION="$OVERRIDE_VERSION"
  echo "  ℹ️  Using override version: ${TARGET_VERSION}"
else
  if [[ "$CRC_ENABLED" != "true" ]]; then
    echo "  ❌ CRC not enabled and no --version specified."
    echo "     Use: bash upgrade.sh --version X.Y.Z"
    exit 1
  fi

  if ! crc_reachable; then
    echo "  ❌ CRC not reachable. Cannot detect baseline."
    echo "     Use: bash upgrade.sh --version X.Y.Z"
    exit 1
  fi

  # Detect operator version from CSV
  crc_csv_line=$(oc_crc get csv -n openshift-operators \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null \
    | grep '^skupper-operator\.' | head -1 || echo "")

  if [[ -z "$crc_csv_line" ]]; then
    echo "  ❌ Skupper operator not found on CRC"
    exit 1
  fi

  crc_csv_name=$(echo "$crc_csv_line" | awk '{print $1}')
  crc_csv_status=$(echo "$crc_csv_line" | awk '{print $2}')
  # Extract version: skupper-operator.v2.2.3-rh-1 → 2.2.3
  TARGET_VERSION=$(echo "$crc_csv_name" | sed 's/^skupper-operator\.v//' | sed 's/-rh-.*//')
  echo "  ✅ CRC operator: ${crc_csv_name} (${crc_csv_status})"
  echo "  ✅ Target version: ${TARGET_VERSION}"

  # Detect CRC router image version
  crc_router_image=$(oc_crc get pods -n "${CRC_NAMESPACE}" -l skupper.io/component=router \
    -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "unknown")
  echo "  ℹ️  CRC router image: ${crc_router_image}"
fi

# Derive image tags from target version
# Router image: versioned separately (skupper 2.2.3 and 2.2.4 both pin skupper-router:3.5.3).
#   Resolve the tag the target release pins in internal/images/images.go; override: SKUPPER_ROUTER_TAG.
# Controller image: quay.io/skupper/system-controller (not skupper-controller), same tag as the CLI.
TARGET_ROUTER_TAG="${SKUPPER_ROUTER_TAG:-}"
if [[ -z "$TARGET_ROUTER_TAG" ]]; then
  TARGET_ROUTER_TAG=$(curl -sfL --max-time 15 \
    "https://raw.githubusercontent.com/skupperproject/skupper/${TARGET_VERSION}/internal/images/images.go" \
    | grep -oP 'RouterImageName\s+string\s*=\s*"skupper-router:\K[^"]+' | head -1 || true)
fi
if [[ -z "$TARGET_ROUTER_TAG" ]]; then
  echo "  ❌ Cannot resolve the router tag pinned by skupper ${TARGET_VERSION} (offline?)."
  echo "     Re-run with SKUPPER_ROUTER_TAG=<tag> (see quay.io/skupper/skupper-router tags)."
  exit 1
fi
TARGET_ROUTER_IMAGE="quay.io/skupper/skupper-router:${TARGET_ROUTER_TAG}"
TARGET_CONTROLLER_IMAGE="quay.io/skupper/system-controller:${TARGET_VERSION}"
TARGET_CLI_VERSION="${TARGET_VERSION}"
echo "  Target CLI:        ${TARGET_CLI_VERSION}"
echo "  Target router:     ${TARGET_ROUTER_IMAGE}"
echo "  Target controller: ${TARGET_CONTROLLER_IMAGE}"
echo

# ── Phase 2: Version comparison ───────────────────────────────
echo "Phase 2: Version comparison"

NEEDS_UPGRADE=false

# Local CLI version
LOCAL_CLI=$(skupper version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "unknown")
echo "  Local CLI: ${LOCAL_CLI}"
if [[ "$LOCAL_CLI" != "$TARGET_CLI_VERSION" ]]; then
  echo "    → Needs upgrade: ${LOCAL_CLI} → ${TARGET_CLI_VERSION}"
  NEEDS_UPGRADE=true
else
  echo "    ✅ Up to date"
fi

# Check each podman host
ALL_HOSTS=(localhost "${HUB_SITES[@]}")
declare -A HOST_CLI_VERSION
declare -A HOST_ROUTER_VERSION
declare -A HOST_CONTROLLER_VERSION
declare -A HOST_NEEDS_UPGRADE

for host in "${ALL_HOSTS[@]}"; do
  if [[ "$host" != "localhost" ]] && ! host_reachable "$host"; then
    echo "  $host: ⚠️  unreachable — skipping"
    HOST_NEEDS_UPGRADE[$host]="skip"
    continue
  fi

  # CLI version
  host_cli=$(run_on_host "$host" "skupper version 2>/dev/null" | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "unknown")
  HOST_CLI_VERSION[$host]="$host_cli"

  # Router image version (from running container)
  host_router=$(run_on_host "$host" "podman inspect ${ROUTER_CONTAINER} --format '{{.Config.Image}}' 2>/dev/null" || echo "unknown")
  HOST_ROUTER_VERSION[$host]="$host_router"

  # Controller image version
  controller_name=$(get_controller_name "$host")
  host_controller=$(run_on_host "$host" "podman inspect ${controller_name} --format '{{.Config.Image}}' 2>/dev/null" || echo "unknown")
  HOST_CONTROLLER_VERSION[$host]="$host_controller"

  echo "  $host:"
  echo "    CLI:        ${host_cli}"
  echo "    Router:     ${host_router}"
  echo "    Controller: ${host_controller}"

  host_upgrade=false
  if [[ "$host_cli" != "$TARGET_CLI_VERSION" ]]; then
    echo "    → CLI needs upgrade"
    host_upgrade=true
  fi
  if [[ "$host_router" != *":${TARGET_ROUTER_TAG}" ]]; then
    echo "    → Router image needs upgrade"
    host_upgrade=true
  fi
  if [[ "$host_controller" != *"${TARGET_VERSION}"* ]]; then
    echo "    → Controller image needs upgrade"
    host_upgrade=true
  fi

  if [[ "$host_upgrade" == "true" ]]; then
    HOST_NEEDS_UPGRADE[$host]="yes"
    NEEDS_UPGRADE=true
  else
    HOST_NEEDS_UPGRADE[$host]="no"
    echo "    ✅ All up to date"
  fi
done
echo

if [[ "$NEEDS_UPGRADE" == "false" ]]; then
  echo "✅ All podman sites already at target version ${TARGET_VERSION}."
  exit 0
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo "ℹ️  Check complete. Run without --check to perform upgrade."
  exit 0
fi

# ── Phase 3: Download CLI ─────────────────────────────────────
echo "Phase 3: Download Skupper CLI ${TARGET_CLI_VERSION}"

if [[ "$LOCAL_CLI" == "$TARGET_CLI_VERSION" ]]; then
  echo "  ✅ Local CLI already at ${TARGET_CLI_VERSION}"
else
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) CLI_ARCH="amd64" ;;
    aarch64) CLI_ARCH="arm64" ;;
    *) echo "  ❌ Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  CLI_URL="https://github.com/skupperproject/skupper/releases/download/${TARGET_CLI_VERSION}/skupper-cli-${TARGET_CLI_VERSION}-linux-${CLI_ARCH}.tgz"
  CLI_TMP=$(mktemp -d)
  echo "  → Downloading from ${CLI_URL}..."
  if curl -sL "$CLI_URL" -o "${CLI_TMP}/skupper.tgz"; then
    tar xzf "${CLI_TMP}/skupper.tgz" -C "${CLI_TMP}/"
    CLI_BIN=$(which skupper 2>/dev/null || echo "$HOME/.local/bin/skupper")
    CLI_DIR=$(dirname "$CLI_BIN")
    mkdir -p "$CLI_DIR"
    cp "${CLI_TMP}/skupper" "$CLI_BIN"
    chmod +x "$CLI_BIN"
    echo "  ✅ CLI installed to ${CLI_BIN}"
    # Verify
    new_cli_ver=$(skupper version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "unknown")
    echo "  ✅ CLI version: ${new_cli_ver}"
  else
    echo "  ❌ Failed to download CLI"
    exit 1
  fi
  rm -rf "$CLI_TMP"
fi

# Install CLI on remote hosts
for host in "${HUB_SITES[@]}"; do
  if [[ "${HOST_NEEDS_UPGRADE[$host]:-skip}" == "skip" ]]; then
    echo "  ⏭️  $host: skipped (unreachable)"
    continue
  fi
  if [[ "${HOST_CLI_VERSION[$host]}" == "$TARGET_CLI_VERSION" ]]; then
    echo "  ✅ $host CLI already at ${TARGET_CLI_VERSION}"
    continue
  fi

  echo "  → Installing CLI on $host..."
  # Determine remote architecture
  remote_arch=$(run_on_host "$host" "uname -m")
  case "$remote_arch" in
    x86_64) remote_cli_arch="amd64" ;;
    aarch64) remote_cli_arch="arm64" ;;
    *) echo "  ❌ $host: unsupported arch $remote_arch"; continue ;;
  esac

  remote_cli_url="https://github.com/skupperproject/skupper/releases/download/${TARGET_CLI_VERSION}/skupper-cli-${TARGET_CLI_VERSION}-linux-${remote_cli_arch}.tgz"
  ssh_target=$(ssh_host_for "$host")
  run_on_host "$host" "
    mkdir -p ~/.local/bin
    curl -sL '${remote_cli_url}' -o /tmp/skupper.tgz && \
    tar xzf /tmp/skupper.tgz -C /tmp/ && \
    cp /tmp/skupper ~/.local/bin/skupper && \
    chmod +x ~/.local/bin/skupper && \
    rm -f /tmp/skupper.tgz /tmp/skupper
  "
  remote_ver=$(run_on_host "$host" "~/.local/bin/skupper version 2>/dev/null" | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "unknown")
  echo "  ✅ $host CLI: ${remote_ver}"
done
echo

# ── Phase 4: Pull new images ──────────────────────────────────
echo "Phase 4: Pull container images"

for host in "${ALL_HOSTS[@]}"; do
  if [[ "${HOST_NEEDS_UPGRADE[$host]:-skip}" == "skip" ]]; then
    echo "  ⏭️  $host: skipped (unreachable)"
    continue
  fi
  if [[ "${HOST_NEEDS_UPGRADE[$host]}" == "no" ]]; then
    echo "  ✅ $host: images already current"
    continue
  fi

  echo "  → Pulling images on $host..."
  run_on_host "$host" "podman pull ${TARGET_ROUTER_IMAGE}" || {
    echo "  ❌ $host: failed to pull router image"
    continue
  }
  run_on_host "$host" "podman pull ${TARGET_CONTROLLER_IMAGE}" || {
    echo "  ❌ $host: failed to pull controller image"
    continue
  }
  echo "  ✅ $host: images pulled"
done
echo

# ── Phase 5: Stop + recreate containers ───────────────────────
echo "Phase 5: Stop + recreate containers"
UPGRADE_FAILED_HOSTS=()
echo "  ⚠️  Models are NOT stopped — only Skupper infrastructure."
echo

for host in "${ALL_HOSTS[@]}"; do
  if [[ "${HOST_NEEDS_UPGRADE[$host]:-skip}" == "skip" ]]; then
    echo "  ⏭️  $host: skipped (unreachable)"
    continue
  fi
  if [[ "${HOST_NEEDS_UPGRADE[$host]}" == "no" ]]; then
    echo "  ✅ $host: already at target version"
    continue
  fi

  echo "  → Upgrading $host..."

  # Stop router + controller
  if [[ "$host" == "localhost" ]]; then
    systemctl --user stop "skupper-${NAMESPACE}.service" 2>/dev/null || true
    systemctl --user stop skupper-controller.service 2>/dev/null || true
  else
    run_on_host "$host" "systemctl --user stop skupper-${NAMESPACE}.service 2>/dev/null; systemctl --user stop skupper-controller.service 2>/dev/null" || true
  fi
  # Extra safety for tmpfs-workaround hosts
  if needs_tmpfs_workaround "$host"; then
    run_on_host "$host" "podman stop ${ROUTER_CONTAINER} 2>/dev/null" || true
  fi

  # Remove old containers (keep volumes/data)
  run_on_host "$host" "podman rm -f ${ROUTER_CONTAINER} 2>/dev/null" || true
  controller_name=$(get_controller_name "$host")
  run_on_host "$host" "podman rm -f ${controller_name} 2>/dev/null" || true

  # Controller: 'system install' recreates the container with the new CLI's
  # system-controller image (systemd only starts an existing container).
  out=$(run_on_host "$host" "skupper --platform podman system install --reload-type auto 2>&1"); rc=$?
  echo "$out" | tail -1 | sed 's/^/     /'
  if [[ $rc -ne 0 ]]; then
    echo "  ❌ $host: skupper system install failed (rc=$rc) — router/controller are down"
    UPGRADE_FAILED_HOSTS+=("$host"); continue
  fi

  # Router: 'system reload' rebuilds it from input/resources and keeps
  # runtime/issuers (CA unchanged → existing links + the CRC secret stay valid).
  # 'system start' refuses an existing namespace ("namespace already exists").
  # A string port in an injected listener breaks the reload → normalize first.
  if [[ "$host" == "localhost" && "$CRC_ENABLED" == "true" && -n "${LOCAL_INTER_ROUTER_PORT:-}" ]]; then
    inject_inter_router_listener >/dev/null || true
  fi
  out=$(run_on_host "$host" "skupper --platform podman system reload -n ${NAMESPACE} 2>&1"); rc=$?
  echo "$out" | grep -vE 'WARN certificate will not be overwritten' | tail -2 | sed 's/^/     /'
  if [[ $rc -ne 0 ]]; then
    echo "  ❌ $host: skupper system reload failed (rc=$rc) — namespace restored by skupper; router is down"
    UPGRADE_FAILED_HOSTS+=("$host"); continue
  fi
  # reload re-renders skrouterd.json → re-add the Phase 3b fallback listener (int port)
  if [[ "$host" == "localhost" && "$CRC_ENABLED" == "true" && -n "${LOCAL_INTER_ROUTER_PORT:-}" ]]; then
    inject_inter_router_listener >/dev/null || true
  fi

  # Recreate router with tmpfs workaround if needed
  if needs_tmpfs_workaround "$host"; then
    fix_cert_perms "$host"
    recreate_router_with_tmpfs "$host"
    sleep 3
  fi

  # 'system install' rewrote the units → re-apply the setup.sh Phase 5 patches.
  install_router_auto_restart "$host"
  install_controller_auto_restart "$host"
  # Router first, controller after it is up: a controller whose router restarts
  # under it can stop publishing flow records (CRC then drops the site and its
  # listener shows "No matching connectors").
  run_on_host "$host" "systemctl --user restart skupper-${NAMESPACE}.service 2>/dev/null" || true
  sleep 5
  run_on_host "$host" "systemctl --user restart skupper-controller.service 2>/dev/null" || true

  echo "  ✅ $host: upgraded"
done
# Wait for containers before verifying (up to 60 s per host)
for host in "${ALL_HOSTS[@]}"; do
  [[ "${HOST_NEEDS_UPGRADE[$host]:-skip}" == "yes" ]] || continue
  controller_name=$(get_controller_name "$host")
  for _ in $(seq 1 12); do
    run_on_host "$host" "podman container exists ${ROUTER_CONTAINER} && podman container exists ${controller_name}" && break
    sleep 5
  done
done
echo

# ── Phase 6: Verify ───────────────────────────────────────────
echo "Phase 6: Verify"

UPGRADE_OK=true
[[ ${#UPGRADE_FAILED_HOSTS[@]} -gt 0 ]] && { echo "  ❌ Phase 5 failed on: ${UPGRADE_FAILED_HOSTS[*]}"; UPGRADE_OK=false; }
for host in "${ALL_HOSTS[@]}"; do
  if [[ "${HOST_NEEDS_UPGRADE[$host]:-skip}" == "skip" ]]; then
    echo "  ⏭️  $host: skipped"
    continue
  fi

  # Check CLI
  new_cli=$(run_on_host "$host" "skupper version 2>/dev/null" | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "unknown")

  # Check router image
  new_router=$(run_on_host "$host" "podman inspect ${ROUTER_CONTAINER} --format '{{.Config.Image}}' 2>/dev/null" || echo "unknown")

  # Check controller image
  controller_name=$(get_controller_name "$host")
  new_controller=$(run_on_host "$host" "podman inspect ${controller_name} --format '{{.Config.Image}}' 2>/dev/null" || echo "unknown")

  echo "  $host:"
  echo "    CLI:        ${new_cli}"
  echo "    Router:     ${new_router}"
  echo "    Controller: ${new_controller}"

  if [[ "$new_cli" != "$TARGET_CLI_VERSION" ]]; then
    echo "    ❌ CLI version mismatch"
    UPGRADE_OK=false
  fi
  if [[ "$new_router" != *":${TARGET_ROUTER_TAG}" ]]; then
    echo "    ❌ Router image mismatch"
    UPGRADE_OK=false
  fi
  if [[ "$new_controller" != *"${TARGET_VERSION}"* ]]; then
    echo "    ❌ Controller image mismatch"
    UPGRADE_OK=false
  fi
done
echo

if [[ "$UPGRADE_OK" == "true" ]]; then
  echo "✅ Upgrade complete. All podman sites at version ${TARGET_VERSION}."
  echo "   CRC operator manages its own versions via OLM."
  echo "   Run: bash status.sh  — to verify full VAN health"
else
  echo "⚠️  Upgrade completed with errors. Check output above."
fi
