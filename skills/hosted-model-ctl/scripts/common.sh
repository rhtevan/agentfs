#!/usr/bin/env bash
# common.sh — Shared variables and functions for hosted-model-ctl
# Source this file from other scripts: source "$(dirname "$0")/common.sh"

set -euo pipefail

# ── Deployment Profiles ───────────────────────────────────────
# Profiles are the ONLY deployment unit. No individual model aliases.
# One profile active per host at a time (mutual exclusion).
# Naming: <model>-<context> (e.g., g8b-fp8-spec-128k)
#
# Format: HOST|CONTAINER|IMAGE|ENGINE|MODEL_ID|TP|CONTEXT|PORT|EXTRA|SPEC_CONFIG|DESCRIPTION|SPEED
#
# Engines:
#   llamacpp   — llama.cpp GGUF server
#   vllm       — Upstream vLLM nightly (standard inference)
#   vllm-spec  — Upstream vLLM nightly with speculative decoding

declare -A DEPLOY_PROFILES=(
  # ── rhtevan-work (1× RTX A500, 4 GB GDDR6, 128 GB/s) ──
  [g350m-2k]="rhtevan-work|model-g350m|docker.io/vllm/vllm-openai:latest|vllm|ibm-granite/granite-4.0-350m|1|2048|10000|--enforce-eager||Granite 4.0 350M FP16 @2K|44 tok/s (no quality)"
  [g3b-16k]="rhtevan-work|model-g3b|ghcr.io/ggml-org/llama.cpp:server-cuda-b9994|llamacpp|ibm-granite/granite-3b|1|16384|10000|--parallel 1||Granite 3B Q4_K_M @16K|37 tok/s"

  # ── rhel-ai (4× NVIDIA L4, 88 GB GDDR6, 1200 GB/s) ──
  [g8b-spec-128k]="rhel-ai|model-granite-8b-spec|docker.io/vllm/vllm-openai:nightly|vllm-spec|ibm-granite/granite-4.2-8b|4|131072|9000|--enforce-eager --dtype bfloat16 --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser nemotron_v3|{SPEC_G8B_BF16}|Granite 4.2 8B BF16 + 3B BF16 draft TP=4 @128K|19-25 tok/s"
  [g8b-fp8-spec-128k]="rhel-ai|model-granite-8b-fp8-spec|docker.io/vllm/vllm-openai:nightly|vllm-spec|ibm-granite/granite-4.2-8b-fp8|4|131072|9000|--enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser nemotron_v3|{SPEC_G8B_FP8}|Granite 4.2 8B FP8 + 3B FP8 draft TP=4 @128K + CUDA graphs|58-79 tok/s"
)

# ── Speculative Decoding Configs ──────────────────────────────
# JSON configs for draft model speculation.
# Referenced by {PLACEHOLDER} in profile SPEC_CONFIG field.

declare -A SPEC_CONFIGS=(
  ["{SPEC_G8B_BF16}"]='{ "method": "draft_model", "model": "ibm-granite/granite-4.2-3b", "num_speculative_tokens": 5, "draft_tensor_parallel_size": 4 }'
  ["{SPEC_G8B_FP8}"]='{ "method": "draft_model", "model": "ibm-granite/granite-4.2-3b-fp8", "num_speculative_tokens": 5, "draft_tensor_parallel_size": 4 }'
)

# Default profiles per host
DEFAULT_PROFILE_RHTEVAN="g3b-16k"
DEFAULT_PROFILE_RHELAI="g8b-fp8-spec-128k"

# All profiles ordered for display
ALL_PROFILES=(g350m-2k g3b-16k g8b-spec-128k g8b-fp8-spec-128k)

# Profile state directory
PROFILE_STATE_DIR="${HOME}/.hosted-model-ctl"

# ── Helper Functions ──────────────────────────────────────────

parse_profile() {
  local profile="$1"
  local entry="${DEPLOY_PROFILES[$profile]:-}"
  if [[ -z "$entry" ]]; then
    echo "ERROR: Unknown profile '$profile'" >&2
    echo "Available: ${ALL_PROFILES[*]}" >&2
    return 1
  fi
  IFS='|' read -r PROFILE_HOST CONTAINER IMAGE ENGINE MODEL_ID TP CONTEXT PORT EXTRA SPEC_CONFIG PROFILE_DESC PROFILE_SPEED <<< "$entry"
  export PROFILE_HOST CONTAINER IMAGE ENGINE MODEL_ID TP CONTEXT PORT EXTRA SPEC_CONFIG PROFILE_DESC PROFILE_SPEED
}

# Resolve speculative config placeholder
resolve_spec_config() {
  local placeholder="$1"
  if [[ -n "$placeholder" && -n "${SPEC_CONFIGS[$placeholder]:-}" ]]; then
    echo "${SPEC_CONFIGS[$placeholder]}"
  else
    echo ""
  fi
}

get_active_profile() {
  local host="$1"
  local state_file="${PROFILE_STATE_DIR}/active-profile-${host}"
  [[ "$host" == "localhost" ]] && state_file="${PROFILE_STATE_DIR}/active-profile-rhtevan-work"
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo ""
  fi
}

set_active_profile() {
  local host="$1"
  local profile="$2"
  mkdir -p "${PROFILE_STATE_DIR}"
  local state_file="${PROFILE_STATE_DIR}/active-profile-${host}"
  [[ "$host" == "localhost" ]] && state_file="${PROFILE_STATE_DIR}/active-profile-rhtevan-work"
  echo "$profile" > "$state_file"
}

clear_active_profile() {
  local host="$1"
  local state_file="${PROFILE_STATE_DIR}/active-profile-${host}"
  [[ "$host" == "localhost" ]] && state_file="${PROFILE_STATE_DIR}/active-profile-rhtevan-work"
  rm -f "$state_file"
}

get_default_profile() {
  local host="$1"
  case "$host" in
    rhtevan-work) echo "$DEFAULT_PROFILE_RHTEVAN" ;;
    rhel-ai)      echo "$DEFAULT_PROFILE_RHELAI" ;;
    *)            echo "" ;;
  esac
}

list_profiles() {
  echo "Deployment Profiles:"
  printf "  %-22s %-12s %-65s %-15s %s\n" "PROFILE" "HOST" "DESCRIPTION" "SPEED" "STATUS"
  printf "  %-22s %-12s %-65s %-15s %s\n" "-------" "----" "-----------" "-----" "------"
  for profile in "${ALL_PROFILES[@]}"; do
    parse_profile "$profile" 2>/dev/null || continue
    local status=""
    [[ "$profile" == "$DEFAULT_PROFILE_RHTEVAN" || "$profile" == "$DEFAULT_PROFILE_RHELAI" ]] && status="✅ default"
    local active
    active=$(get_active_profile "$PROFILE_HOST")
    [[ "$active" == "$profile" ]] && status="🟢 active"
    printf "  %-22s %-12s %-65s %-15s %s\n" "$profile" "$PROFILE_HOST" "$PROFILE_DESC" "$PROFILE_SPEED" "$status"
  done
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

host_reachable() {
  local host="$1"
  if [[ "$host" == "localhost" ]]; then
    return 0
  fi
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" 'echo ok' &>/dev/null
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
