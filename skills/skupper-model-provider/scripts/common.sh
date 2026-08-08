#!/usr/bin/env bash
# common.sh — Shared variables and functions for skupper-model-provider
# Source this file from other scripts: source "$(dirname "$0")/common.sh"

set -euo pipefail

# ── Skupper Configuration ─────────────────────────────────────
NAMESPACE="model-provider-podman"
PLATFORM="podman"
ROUTER_IMAGE="quay.io/skupper/skupper-router:latest"
ROUTER_CONTAINER="${NAMESPACE}-skupper-router"

# ── Site Profiles ─────────────────────────────────────────────
# Format: HOST|ROLE|INTER_ROUTER_PORT|EDGE_PORT|ROUTING_KEY|MODEL_PORT
declare -A SITE_PROFILES=(
  [rhtevan-work]="interior|55671|45671|model-api-rhtevan-work|10000"
  [rhel-ai]="interior|8000|45671|model-api-rhel-ai|9000"
  [local]="interior-outbound|0|0|none|0"
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
  IFS='|' read -r _ _ _ routing_key model_port <<< "${SITE_PROFILES[$host]}"
  echo "$model_port"
}

alias_to_routing_key() {
  local alias="$1"
  local host
  host=$(alias_to_host "$alias") || return 1
  IFS='|' read -r _ _ _ routing_key _ <<< "${SITE_PROFILES[$host]}"
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

host_reachable() {
  local host="$1"
  [[ "$host" == "localhost" ]] && return 0
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" 'echo ok' &>/dev/null
}

run_on_host() {
  local host="$1"
  shift
  if [[ "$host" == "localhost" ]]; then
    eval "$@"
  else
    ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "$@" 2>/dev/null
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

fix_cert_perms() {
  local host="$1"
  local ns_dir
  ns_dir=$(skupper_ns_dir "$host")
  run_on_host "$host" "chmod -R o+r ${ns_dir}/runtime/certs/ 2>/dev/null" || true
}

start_router_container() {
  local host="$1"
  local ns_dir
  ns_dir=$(skupper_ns_dir "$host")

  # Stop/remove existing
  run_on_host "$host" "podman stop ${ROUTER_CONTAINER} 2>/dev/null; podman rm -f ${ROUTER_CONTAINER} 2>/dev/null" || true

  # Fix cert permissions
  fix_cert_perms "$host"

  # Get site ID
  local site_id
  site_id=$(run_on_host "$host" "grep -o 'SKUPPER_SITE_ID=[^ ]*' ${ns_dir}/runtime/router/env 2>/dev/null | cut -d= -f2" || echo "")
  [[ -z "$site_id" ]] && site_id=$(run_on_host "$host" "cat ${ns_dir}/runtime/state/site-id 2>/dev/null" || echo "auto")

  run_on_host "$host" "podman run -d \
    --name ${ROUTER_CONTAINER} \
    --network host \
    --tmpfs /tmp:rw,size=10M,mode=1777 \
    -v ${ns_dir}/runtime/router:/etc/skupper-router/config:Z \
    -v ${ns_dir}/runtime/certs:/etc/skupper-router/runtime/certs:Z \
    -e QDROUTERD_CONF=/etc/skupper-router/config/skrouterd.json \
    -e QDROUTERD_CONF_TYPE=json \
    -e QDROUTERD_HOME=/home/skrouterd \
    -e SSL_PROFILE_BASE_PATH=/etc/skupper-router \
    -e SKUPPER_SITE_ID=${site_id} \
    -e APPLICATION_NAME=skupper-router \
    ${ROUTER_IMAGE}"
}

check_router_status() {
  local host="$1"
  if ! host_reachable "$host"; then
    echo "unreachable"
    return 0
  fi
  local status
  status=$(run_on_host "$host" "podman ps --filter name=${ROUTER_CONTAINER} --format '{{.Status}}' 2>/dev/null")
  echo "${status:-not found}"
}
