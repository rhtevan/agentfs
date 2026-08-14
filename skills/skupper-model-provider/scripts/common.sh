#!/usr/bin/env bash
# common.sh — Shared variables and functions for skupper-model-provider
# Source this file from other scripts: source "$(dirname "$0")/common.sh"

set -euo pipefail

# ── Load topology ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TOPOLOGY_FILE="${SKILL_DIR}/topology.env"

if [[ ! -f "$TOPOLOGY_FILE" ]]; then
  echo "❌ topology.env not found at: $TOPOLOGY_FILE"
  echo "   Copy topology.env.example → topology.env and fill in your values."
  exit 1
fi

# shellcheck source=../topology.env
source "$TOPOLOGY_FILE"

# ── Skupper Configuration ─────────────────────────────────────
NAMESPACE="model-provider-podman"
PLATFORM="podman"
ROUTER_IMAGE="quay.io/skupper/skupper-router:3.5.1"
ROUTER_CONTAINER="${NAMESPACE}-skupper-router"
CONTROLLER_SUFFIX="skupper-controller"

# ── CRC Configuration (built from topology.env) ──────────────
CRC_ENABLED="${CRC_ENABLED:-false}"
CRC_SITE_NAME="${CRC_SITE_NAME:-crc-site}"
CRC_NAMESPACE="${CRC_NAMESPACE:-model-provider-crc}"
CRC_OC_CONTEXT="${CRC_OC_CONTEXT:-crc-admin}"
CRC_LINK_TARGET="${CRC_LINK_TARGET:-rhel-ai}"
CRC_MODEL_PORT="${CRC_MODEL_PORT:-9000}"
CRC_ROUTING_KEY="${CRC_ROUTING_KEY:-model-api-rhel-ai}"
CRC_OBSERVER_ENABLED="${CRC_OBSERVER_ENABLED:-false}"

# ── Site Names (built from topology.env) ──────────────────────
declare -A SITE_NAMES=(
  [rhtevan-work]="hub-rhtevan-work"
  [rhel-ai]="hub-rhel-ai"
  [local]="${LOCAL_SITE_NAME}"
)
if [[ "$CRC_ENABLED" == "true" ]]; then
  SITE_NAMES[crc]="${CRC_SITE_NAME}"
fi

# ── Site Profiles (built from topology.env) ───────────────────
# Format: INTER_ROUTER_PORT|EDGE_PORT|ROUTING_KEY|MODEL_PORT|PUBLIC_HOST
declare -A SITE_PROFILES=(
  [rhtevan-work]="${RHTEVAN_WORK_INTER_ROUTER_PORT}|${RHTEVAN_WORK_EDGE_PORT}|${RHTEVAN_WORK_ROUTING_KEY}|${RHTEVAN_WORK_MODEL_PORT}|${RHTEVAN_WORK_PUBLIC_HOST}"
  [rhel-ai]="${RHEL_AI_INTER_ROUTER_PORT}|${RHEL_AI_EDGE_PORT}|${RHEL_AI_ROUTING_KEY}|${RHEL_AI_MODEL_PORT}|${RHEL_AI_PUBLIC_HOST}"
)

# ── Site SANs (built from topology.env) ───────────────────────
# Comma-separated → used in setup.sh for RouterAccess YAML
declare -A SITE_SANS=(
  [rhel-ai]="${RHEL_AI_SANS}"
  [rhtevan-work]="${RHTEVAN_WORK_SANS}"
)

# ── SSH Host Aliases (built from topology.env) ────────────────
declare -A SSH_HOSTS=(
  [rhel-ai]="${RHEL_AI_SSH_HOST}"
  [rhtevan-work]="${RHTEVAN_WORK_SSH_HOST}"
)

# ── Model Alias → Hub Routing ─────────────────────────────────
alias_to_host() {
  local alias="$1"
  case "$alias" in
    g350m|g1b|g8b)       echo "rhtevan-work" ;;
    g30b-96k|g30b)       echo "rhel-ai" ;;
    g8b-128k)            echo "rhel-ai" ;;
    *) echo "unknown"; return 1 ;;
  esac
}

alias_to_local_port() {
  local alias="$1"
  local host
  host=$(alias_to_host "$alias") || return 1
  IFS='|' read -r _ _ _ model_port _ <<< "${SITE_PROFILES[$host]}"
  echo "$model_port"
}

alias_to_routing_key() {
  local alias="$1"
  local host
  host=$(alias_to_host "$alias") || return 1
  IFS='|' read -r _ _ routing_key _ _ <<< "${SITE_PROFILES[$host]}"
  echo "$routing_key"
}

alias_to_container() {
  local alias="$1"
  case "$alias" in
    g350m)    echo "model-g350m" ;;
    g1b)      echo "model-g1b" ;;
    g8b)      echo "model-g8b" ;;
    g30b-96k|g30b) echo "model-granite-4.1-30b" ;;
    g8b-128k) echo "model-granite-4.1-8b" ;;
    *) echo "unknown"; return 1 ;;
  esac
}

# ── Helper Functions ──────────────────────────────────────────

ssh_host_for() {
  local host="$1"
  echo "${SSH_HOSTS[$host]:-$host}"
}

host_reachable() {
  local host="$1"
  [[ "$host" == "localhost" ]] && return 0
  local ssh_target
  ssh_target=$(ssh_host_for "$host")
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" 'echo ok' &>/dev/null
}

run_on_host() {
  local host="$1"
  shift
  if [[ "$host" == "localhost" ]]; then
    eval "$@"
  else
    local ssh_target
    ssh_target=$(ssh_host_for "$host")
    ssh -o ConnectTimeout=10 -o BatchMode=yes "$ssh_target" "$@" 2>/dev/null
  fi
}

skupper_ns_dir() {
  local host="$1"
  if [[ "$host" == "localhost" ]]; then
    echo "$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
  else
    run_on_host "$host" "echo \$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
  fi
}

get_controller_name() {
  local host="$1"
  if [[ "$host" == "localhost" ]]; then
    local user
    user=$(whoami)
    echo "${user}-${CONTROLLER_SUFFIX}"
  else
    local user
    user=$(run_on_host "$host" 'whoami')
    echo "${user}-${CONTROLLER_SUFFIX}"
  fi
}

fix_cert_perms() {
  local host="$1"
  local ns_dir
  ns_dir=$(skupper_ns_dir "$host")
  run_on_host "$host" "chmod -R o+r ${ns_dir}/runtime/certs/ 2>/dev/null" || true
}

get_site_id() {
  local host="$1"
  local site_name="$2"
  local ns_dir
  ns_dir=$(skupper_ns_dir "$host")
  run_on_host "$host" "grep 'uid:' ${ns_dir}/runtime/resources/Site-${site_name}.yaml 2>/dev/null | awk '{print \$2}'" || echo ""
}

check_router_status() {
  local host="$1"
  if ! host_reachable "$host"; then
    echo "unreachable"
    return 0
  fi
  local status
  status=$(run_on_host "$host" "podman ps --filter name=${ROUTER_CONTAINER} --format '{{.Status}}'" 2>/dev/null || echo "")
  echo "${status:-not found}"
}

check_controller_status() {
  local host="$1"
  local controller
  controller=$(get_controller_name "$host")
  if ! host_reachable "$host"; then
    echo "unreachable"
    return 0
  fi
  local status
  status=$(run_on_host "$host" "podman ps --filter name=${controller} --format '{{.Status}}'" 2>/dev/null || echo "")
  echo "${status:-not found}"
}

# ── Platform detection ────────────────────────────────────────
site_platform() {
  local host="$1"
  case "$host" in
    crc) echo "kubernetes" ;;
    *)   echo "podman" ;;
  esac
}

# ── CRC helpers ───────────────────────────────────────────────
# All CRC operations use explicit --context to avoid hitting the
# wrong cluster when multiple kubeconfigs/contexts are present.
oc_crc() {
  oc --context="${CRC_OC_CONTEXT}" "$@"
}

crc_reachable() {
  [[ "$CRC_ENABLED" != "true" ]] && return 1
  oc_crc whoami &>/dev/null
}

crc_site_status() {
  oc_crc get site "${CRC_SITE_NAME}" -n "${CRC_NAMESPACE}" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "not found"
}

crc_link_status() {
  oc_crc get link link-hub-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "not found"
}

crc_listener_status() {
  oc_crc get listener model-listener-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "not found"
}

crc_link_name() {
  local target="${CRC_LINK_TARGET}"
  echo "link-hub-${SITE_NAMES[$target]}"
}

crc_listener_name() {
  echo "model-listener-${CRC_LINK_TARGET}"
}

crc_observer_route_url() {
  oc_crc get route -n "${CRC_NAMESPACE}" -l app.kubernetes.io/name=network-observer \
    -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "not found"
}

# ── SAN helper (converts comma-separated → YAML list) ────────
sans_to_yaml() {
  local sans_csv="$1"
  local indent="${2:-    }"
  IFS=',' read -ra entries <<< "$sans_csv"
  for entry in "${entries[@]}"; do
    entry=$(echo "$entry" | xargs)  # trim whitespace
    echo "${indent}- \"${entry}\""
  done
}

# ── Precheck: topology validation ─────────────────────────────
precheck_topology() {
  local errors=0
  local warnings=0

  # Disable errexit inside precheck — arithmetic ((var++)) returns 1
  # when var was 0, which triggers set -e. We handle errors manually.
  set +e

  # Read values for display
  local ra_host="${RHEL_AI_PUBLIC_HOST}"
  local ra_port="${RHEL_AI_INTER_ROUTER_PORT}"
  local ra_lport="${RHEL_AI_MODEL_PORT}"
  local ra_rkey="${RHEL_AI_ROUTING_KEY}"
  local ra_sans="${RHEL_AI_SANS}"
  local rw_host="${RHTEVAN_WORK_PUBLIC_HOST}"
  local rw_port="${RHTEVAN_WORK_INTER_ROUTER_PORT}"
  local rw_lport="${RHTEVAN_WORK_MODEL_PORT}"
  local rw_rkey="${RHTEVAN_WORK_ROUTING_KEY}"
  local rw_sans="${RHTEVAN_WORK_SANS}"

  # Format SANs with comma-space for readability
  local ra_sans_fmt="${ra_sans//,/, }"
  local rw_sans_fmt="${rw_sans//,/, }"

  # Build CRC section if enabled
  local crc_section=""
  if [[ "$CRC_ENABLED" == "true" ]]; then
    local crc_target_host_d crc_target_port_d
    IFS='|' read -r crc_target_port_d _ _ _ crc_target_host_d <<< "${SITE_PROFILES[$CRC_LINK_TARGET]}"
    crc_section="

CRC: ${CRC_SITE_NAME} (kubernetes, ${CRC_NAMESPACE})
  └── link → hub-${CRC_LINK_TARGET}
        host:  ${crc_target_host_d}
        port:  ${crc_target_port_d} (AMQPS)
        Listener :${CRC_MODEL_PORT} ← ${CRC_ROUTING_KEY}
        Service: model-listener-${CRC_LINK_TARGET}.${CRC_NAMESPACE}:${CRC_MODEL_PORT}"
    local site_count="4-site"
  else
    local site_count="3-site"
  fi

  cat << TOPO

Skupper VAN — ${site_count} interior mesh

LOCAL: ${LOCAL_SITE_NAME} (localhost, podman)
  ├── link → hub-rhel-ai
  │     host:  ${ra_host}
  │     port:  ${ra_port} (AMQPS)
  │     SANs:  ${ra_sans_fmt}
  │     Listener :${ra_lport} ← ${ra_rkey}
  │
  └── link → hub-rhtevan-work
        host:  ${rw_host}
        port:  ${rw_port} (AMQPS)
        SANs:  ${rw_sans_fmt}
        Listener :${rw_lport} ← ${rw_rkey}
${crc_section}

  PUBLIC_HOST = routable address the local router connects to via AMQPS
  SANS        = TLS cert Subject Alternative Names; must include every
                hostname/IP clients use to reach the hub, or TLS fails

TOPO

  # ── Validation ────────────────────────────────────────────────
  echo "Validating topology..."
  echo

  # 1. Podman
  if podman info &>/dev/null; then
    echo "  ✅ Podman: running"
  else
    echo "  ❌ Podman: not running or not installed"
    ((errors++))
  fi

  # 2. Skupper CLI
  if command -v skupper &>/dev/null; then
    echo "  ✅ Skupper CLI: $(skupper version 2>/dev/null || echo 'available')"
  else
    echo "  ❌ Skupper CLI: not found"
    ((errors++))
  fi

  # 3. SSH reachability
  for site in rhel-ai rhtevan-work; do
    local ssh_target
    ssh_target=$(ssh_host_for "$site")
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" 'echo ok' &>/dev/null; then
      echo "  ✅ SSH $site ($ssh_target): reachable"
    else
      echo "  ❌ SSH $site ($ssh_target): unreachable"
      ((errors++))
    fi
  done

  # 4. PUBLIC_HOST resolution
  for site in rhel-ai rhtevan-work; do
    local pub_host
    [[ "$site" == "rhel-ai" ]] && pub_host="$RHEL_AI_PUBLIC_HOST" || pub_host="$RHTEVAN_WORK_PUBLIC_HOST"
    if getent hosts "$pub_host" &>/dev/null; then
      echo "  ✅ DNS $site ($pub_host): resolves"
    else
      # Might be a raw IP — check if it's a valid IP
      if [[ "$pub_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  ✅ Host $site ($pub_host): IP address (no DNS needed)"
      else
        echo "  ⚠️  DNS $site ($pub_host): does not resolve"
        ((warnings++))
      fi
    fi
  done

  # 5. SANs include PUBLIC_HOST
  for site in rhel-ai rhtevan-work; do
    local pub_host sans
    if [[ "$site" == "rhel-ai" ]]; then
      pub_host="$RHEL_AI_PUBLIC_HOST"
      sans="$RHEL_AI_SANS"
    else
      pub_host="$RHTEVAN_WORK_PUBLIC_HOST"
      sans="$RHTEVAN_WORK_SANS"
    fi
    if echo ",$sans," | grep -qF ",$pub_host,"; then
      echo "  ✅ SANs $site: includes PUBLIC_HOST ($pub_host)"
    else
      echo "  ❌ SANs $site: missing PUBLIC_HOST ($pub_host) — TLS will fail"
      echo "       Current SANs: $sans"
      ((errors++))
    fi
  done

  # 6. Local ports available
  for site in rhel-ai rhtevan-work; do
    local lport
    [[ "$site" == "rhel-ai" ]] && lport="$RHEL_AI_MODEL_PORT" || lport="$RHTEVAN_WORK_MODEL_PORT"
    if ss -tlnp 2>/dev/null | grep -q ":${lport} "; then
      echo "  ⚠️  Port $lport ($site listener): already in use"
      ((warnings++))
    else
      echo "  ✅ Port $lport ($site listener): available"
    fi
  done

  # 7. CRC checks (if enabled)
  if [[ "$CRC_ENABLED" == "true" ]]; then
    echo
    echo "  CRC site (${CRC_SITE_NAME}):" 

    # CRC context authentication
    if oc --context="${CRC_OC_CONTEXT}" whoami &>/dev/null; then
      local crc_user
      crc_user=$(oc --context="${CRC_OC_CONTEXT}" whoami 2>/dev/null)
      echo "  ✅ CRC context (${CRC_OC_CONTEXT}): authenticated as ${crc_user}"
    else
      echo "  ❌ CRC context (${CRC_OC_CONTEXT}): not authenticated"
      echo "       Run: oc login -u kubeadmin -p kubeadmin https://api.crc.testing:6443"
      ((errors++))
    fi

    # CRC → hub TCP reachability
    local crc_target_host crc_target_port
    IFS='|' read -r crc_target_port _ _ _ crc_target_host <<< "${SITE_PROFILES[$CRC_LINK_TARGET]}"
    if oc --context="${CRC_OC_CONTEXT}" run skupper-precheck-tcp --rm -i --restart=Never \
         --image=registry.access.redhat.com/ubi9/ubi-minimal \
         -- bash -c "timeout 5 bash -c \"echo > /dev/tcp/${crc_target_host}/${crc_target_port}\"" &>/dev/null; then
      echo "  ✅ CRC → ${CRC_LINK_TARGET} (${crc_target_host}:${crc_target_port}): reachable"
    else
      echo "  ⚠️  CRC → ${CRC_LINK_TARGET} (${crc_target_host}:${crc_target_port}): unreachable (hub may not be up yet)"
      ((warnings++))
    fi

    # Operator catalog
    if oc --context="${CRC_OC_CONTEXT}" get packagemanifest skupper-operator &>/dev/null; then
      echo "  ✅ Skupper operator: available in catalog"
    else
      echo "  ❌ Skupper operator: not found in catalog"
      ((errors++))
    fi
  fi

  echo
  # Re-enable errexit
  set -e

  if [[ $errors -gt 0 ]]; then
    echo "❌ Precheck FAILED: $errors error(s), $warnings warning(s)"
    echo "   Fix the errors above before running setup."
    return 1
  elif [[ $warnings -gt 0 ]]; then
    echo "⚠️  Precheck PASSED with $warnings warning(s)"
    return 0
  else
    echo "✅ Precheck PASSED: all checks OK"
    return 0
  fi
}

# ── Podman 4.x /tmp workaround (rhel-ai only) ────────────────
# On rhel-ai (podman 4.9.4, bootc immutable OS), the rootless
# namespace mapping makes /tmp read-only for uid 10000 inside
# the container. skrouterd's launch.sh copies config to /tmp
# and runs expandvars.py — both fail without writable /tmp.
# Fix: --tmpfs /tmp:rw,size=10M,mode=1777
# Also need: -e SSL_PROFILE_BASE_PATH=/etc/skupper-router
# Also need: chmod -R o+r on certs (files created 640)
needs_tmpfs_workaround() {
  local host="$1"
  [[ "$host" == "rhel-ai" ]]
}

recreate_router_with_tmpfs() {
  local host="$1"
  local ns_dir site_id
  ns_dir=$(skupper_ns_dir "$host")
  local site_name="${SITE_NAMES[$host]}"
  site_id=$(get_site_id "$host" "$site_name")

  fix_cert_perms "$host"

  run_on_host "$host" "podman stop ${ROUTER_CONTAINER} 2>/dev/null; podman rm -f ${ROUTER_CONTAINER} 2>/dev/null" || true

  run_on_host "$host" "podman run -d \
    --name ${ROUTER_CONTAINER} \
    --tmpfs /tmp:rw,size=10M,mode=1777 \
    -v ${ns_dir}/runtime/router:/etc/skupper-router/config:Z \
    -v ${ns_dir}/runtime/certs:/etc/skupper-router/runtime/certs:Z \
    -p 55671:55671 -p 45671:45671 -p 8000:8000 \
    -e QDROUTERD_CONF_TYPE=json \
    -e QDROUTERD_CONF=/etc/skupper-router/config/skrouterd.json \
    -e APPLICATION_NAME=skupper-router \
    -e SKUPPER_SITE_ID=${site_id} \
    -e SSL_PROFILE_BASE_PATH=/etc/skupper-router \
    --label application=skupper-v2 \
    --label skupper.io/site-id=${site_id} \
    --label skupper.io/v2-component=router \
    ${ROUTER_IMAGE}"
}

# ── Auto-restart patch ────────────────────────────────────────
# Skupper's generated systemd units use RemainAfterExit=yes which
# means systemd doesn't monitor the container process. If the
# router or controller crashes, nobody restarts it.
# Fix: start-watch.sh blocks on `podman wait`, checks exit code,
# exits non-zero on crash → Restart=on-failure triggers restart.

install_router_auto_restart() {
  local host="$1"
  local ns_dir
  ns_dir=$(skupper_ns_dir "$host")

  # Write start-watch.sh
  local script_content
  read -r -d '' script_content << 'WATCHSCRIPT' || true
#!/usr/bin/env bash
set -euo pipefail

ROUTER="model-provider-podman-skupper-router"

podman start "${ROUTER}"
RC=$(podman wait --condition=stopped "${ROUTER}")
exit "${RC}"
WATCHSCRIPT

  run_on_host "$host" "cat > ${ns_dir}/internal/scripts/start-watch.sh << 'EOF'
${script_content}
EOF
chmod +x ${ns_dir}/internal/scripts/start-watch.sh"

  # Patch systemd unit
  local uid_num home_dir
  uid_num=$(run_on_host "$host" 'id -u')
  home_dir=$(run_on_host "$host" 'echo $HOME')

  # Remove stale enable symlink left by 'skupper system start'
  # (it creates default.target.wants/ symlinks that survive unit rewrites)
  run_on_host "$host" "systemctl --user disable skupper-${NAMESPACE}.service 2>/dev/null || true"

  run_on_host "$host" "cat > ~/.config/systemd/user/skupper-${NAMESPACE}.service << EOF
[Unit]
Description=skupper-${NAMESPACE}.service
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/run/user/${uid_num}/containers

[Service]
TimeoutStopSec=70
ExecStart=/bin/bash ${ns_dir}/internal/scripts/start-watch.sh
ExecStop=/bin/bash ${ns_dir}/internal/scripts/stop.sh
Type=simple
Restart=on-failure
RestartSec=5
SuccessExitStatus=SIGTERM
EOF
systemctl --user daemon-reload"
}

install_controller_auto_restart() {
  local host="$1"
  local controller
  controller=$(get_controller_name "$host")
  local uid_num home_dir
  uid_num=$(run_on_host "$host" 'id -u')
  home_dir=$(run_on_host "$host" 'echo $HOME')

  # Write start-watch.sh for controller
  run_on_host "$host" "mkdir -p ~/.local/share/skupper/system-controller/internal/scripts
  cat > ~/.local/share/skupper/system-controller/internal/scripts/start-watch.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
CONTAINER=\"${controller}\"
podman start \"\${CONTAINER}\"
RC=\$(podman wait --condition=stopped \"\${CONTAINER}\")
exit \"\${RC}\"
EOF
chmod +x ~/.local/share/skupper/system-controller/internal/scripts/start-watch.sh"

  # Patch systemd unit
  # Remove stale enable symlink left by 'skupper system start'
  run_on_host "$host" "systemctl --user disable skupper-controller.service 2>/dev/null || true"

  run_on_host "$host" "cat > ~/.config/systemd/user/skupper-controller.service << EOF
[Unit]
Description=skupper-controller
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/run/user/${uid_num}/containers
RequiresMountsFor=/run/user/${uid_num}/podman/podman.sock
RequiresMountsFor=${home_dir}/.local/share/skupper

[Service]
TimeoutStopSec=70
Environment=\"CONTAINER_ENDPOINT=unix:///var/run/podman.sock\"
Environment=\"CONTAINER_ENGINE=podman\"
Environment=\"SKUPPER_OUTPUT_PATH=${home_dir}/.local/share/skupper\"
Environment=\"SKUPPER_SYSTEM_RELOAD_TYPE=auto\"
ExecStart=/bin/bash ${home_dir}/.local/share/skupper/system-controller/internal/scripts/start-watch.sh
ExecStop=/bin/bash ${home_dir}/.local/share/skupper/system-controller/internal/scripts/stop.sh
Type=simple
Restart=on-failure
RestartSec=5
SuccessExitStatus=SIGTERM
EOF
systemctl --user daemon-reload"
}
