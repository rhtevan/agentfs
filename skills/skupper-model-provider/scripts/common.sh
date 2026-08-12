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

# ── Site Names (built from topology.env) ──────────────────────
declare -A SITE_NAMES=(
  [rhtevan-work]="hub-rhtevan-work"
  [rhel-ai]="hub-rhel-ai"
  [local]="${LOCAL_SITE_NAME}"
)

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

  cat << TOPO

Skupper VAN — 3-site interior mesh

LOCAL: ${LOCAL_SITE_NAME} (localhost)
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
STOP_MARKER="/tmp/skupper-model-provider-podman-stopping"

rm -f "${STOP_MARKER}"
trap 'touch ${STOP_MARKER}; exit 0' SIGTERM

podman start "${ROUTER}"

podman wait --condition=stopped "${ROUTER}" &
wait $!

if [ -f "${STOP_MARKER}" ]; then
    rm -f "${STOP_MARKER}"
    exit 0
fi

RC=$(podman inspect "${ROUTER}" --format '{{.State.ExitCode}}' 2>/dev/null || echo "1")
if [ "${RC}" != "0" ]; then
    echo "Router crashed with exit code ${RC}, signaling failure for restart" >&2
    exit 1
fi
exit 0
WATCHSCRIPT

  run_on_host "$host" "cat > ${ns_dir}/internal/scripts/start-watch.sh << 'EOF'
${script_content}
EOF
chmod +x ${ns_dir}/internal/scripts/start-watch.sh"

  # Patch systemd unit
  local uid_num home_dir
  uid_num=$(run_on_host "$host" 'id -u')
  home_dir=$(run_on_host "$host" 'echo $HOME')

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
STOP_MARKER=\"/tmp/skupper-controller-stopping\"
rm -f \"\${STOP_MARKER}\"
trap 'touch \${STOP_MARKER}; exit 0' SIGTERM
podman start \"\${CONTAINER}\"
podman wait --condition=stopped \"\${CONTAINER}\" &
wait \$!
if [ -f \"\${STOP_MARKER}\" ]; then
    rm -f \"\${STOP_MARKER}\"
    exit 0
fi
RC=\$(podman inspect \"\${CONTAINER}\" --format '{{.State.ExitCode}}' 2>/dev/null || echo \"1\")
if [ \"\${RC}\" != \"0\" ]; then
    echo \"Controller crashed with exit code \${RC}, signaling failure for restart\" >&2
    exit 1
fi
exit 0
EOF
chmod +x ~/.local/share/skupper/system-controller/internal/scripts/start-watch.sh"

  # Patch systemd unit
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
EOF
systemctl --user daemon-reload"
}
