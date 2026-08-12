#!/usr/bin/env bash
# common.sh — Shared variables and functions for hosted-model-ctl
# Source this file from other scripts: source "$(dirname "$0")/common.sh"

set -euo pipefail

# ── Model Registry ────────────────────────────────────────────
# Format: ALIAS|MODEL_ID|ENGINE|CONTAINER_NAME|IMAGE|HOST|PORT|TP|CONTEXT|EXTRA_FLAGS

declare -A MODEL_REGISTRY=(
  [g350m]="ibm-granite/granite-4.0-350m|vllm|model-g350m|docker.io/vllm/vllm-openai:latest|rhtevan-work|10000|1|2048|"
  [g1b]="ibm-granite/granite-4.0-1b|vllm-bnb|model-g1b|docker.io/vllm/vllm-openai:latest|rhtevan-work|10000|1|2048|"
  [g8b]="ibm-granite/granite-4.1-8b|llamacpp|model-g8b|ghcr.io/ggml-org/llama.cpp:server-cuda-b9994|rhtevan-work|10000|1|16384|"
  [g8b-128k]="ibm-granite/granite-4.1-8b|vllm-ilab|model-granite-4.1-8b|registry.redhat.io/rhelai1/instructlab-nvidia-rhel9:1.5.0|rhel-ai|9000|2|131072|"
  [g30b-96k]="ibm-granite/granite-4.1-30b|vllm-ilab|model-granite-4.1-30b|registry.redhat.io/rhelai1/instructlab-nvidia-rhel9:1.5.0|rhel-ai|9000|4|98304|"
)

# Default models per host
DEFAULT_MODEL_RHTEVAN="g350m"
DEFAULT_MODEL_RHELAI="g8b-128k"

# ── Helper Functions ──────────────────────────────────────────

parse_model() {
  local alias="$1"
  local entry="${MODEL_REGISTRY[$alias]:-}"
  if [[ -z "$entry" ]]; then
    echo "ERROR: Unknown model alias '$alias'" >&2
    echo "Available: ${!MODEL_REGISTRY[*]}" >&2
    return 1
  fi
  IFS='|' read -r MODEL_ID ENGINE CONTAINER IMAGE HOST PORT TP CONTEXT EXTRA <<< "$entry"
  export MODEL_ID ENGINE CONTAINER IMAGE HOST PORT TP CONTEXT EXTRA
}

run_on_host() {
  local host="$1"
  shift
  if [[ "$host" == "localhost" ]]; then
    eval "$@"
  else
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "$@" 2>/dev/null
  fi
}

# Check if a remote host is reachable via SSH
host_reachable() {
  local host="$1"
  if [[ "$host" == "localhost" ]]; then
    return 0
  fi
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" 'echo ok' &>/dev/null
}

list_aliases() {
  echo "Available models:"
  printf "  %-12s %-35s %-12s %s\n" "ALIAS" "MODEL" "HOST" "PORT"
  printf "  %-12s %-35s %-12s %s\n" "-----" "-----" "----" "----"
  for alias in g350m g1b g8b g8b-128k g30b-96k; do
    parse_model "$alias" 2>/dev/null || continue
    printf "  %-12s %-35s %-12s %s\n" "$alias" "$MODEL_ID" "$HOST" "$PORT"
  done
}

check_container_status() {
  local host="$1"
  local container="$2"
  if ! host_reachable "$host"; then
    echo "unknown (host unreachable)"
    return 0
  fi
  local result
  result=$(run_on_host "$host" "podman ps -a --filter name=$container --format '{{.Status}}' 2>/dev/null")
  echo "${result:-not found}"
}

wait_for_model() {
  local host="$1"
  local port="$2"
  local max_wait="${3:-300}"
  local interval=15
  local elapsed=0

  echo "Waiting for model on ${host}:${port} (max ${max_wait}s)..."
  while (( elapsed < max_wait )); do
    local code
    code=$(run_on_host "$host" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${port}/v1/models 2>/dev/null" || echo "000")
    if [[ "$code" == "200" ]]; then
      echo "✅ Model ready on ${host}:${port} (${elapsed}s)"
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  echo "❌ Timeout waiting for model on ${host}:${port}" >&2
  return 1
}
