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
  # llama.cpp b12648 (44d50873, server-cuda 2026-11-23) pinned by digest — versioned
  # server-cuda-bNNNNN tags are no longer published. >= PR #26939: unsupported regex
  # in tool-schema "pattern" (\d \w \s \/) falls back to any-string instead of HTTP 400
  # "failed to parse grammar" (b9994 broke OLS / openshift-mcp-server tools).
  [g3b-16k]="rhtevan-work|model-g3b|ghcr.io/ggml-org/llama.cpp@sha256:f8e7c336e3660804f6bc35a4147dbfdf1ddae9b7c3c50d412fab49b323e28fea|llamacpp|ibm-granite/granite-3b|1|16384|10000|--parallel 1||Granite 3B Q4_K_M @16K|37 tok/s"

  # ── rhel-ai (4× NVIDIA L4, 88 GB GDDR6, 1200 GB/s) ──
  [g8b-spec-128k]="rhel-ai|model-granite-8b-spec|docker.io/vllm/vllm-openai:nightly|vllm-spec|ibm-granite/granite-4.2-8b|4|131072|9000|--enforce-eager --dtype bfloat16 --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser nemotron_v3|{SPEC_G8B_BF16}|Granite 4.2 8B BF16 + 3B BF16 draft TP=4 @128K|19-25 tok/s"
  [g8b-fp8-spec-128k]="rhel-ai|model-granite-8b-fp8-spec|docker.io/vllm/vllm-openai:nightly|vllm-spec|ibm-granite/granite-4.2-8b-fp8|4|131072|9000|--enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser nemotron_v3|{SPEC_G8B_FP8}|Granite 4.2 8B FP8 + 3B FP8 draft TP=4 @128K + CUDA graphs|58-79 tok/s"
  [qw14b-32k]="rhel-ai|model-qwen3-14b-32k|docker.io/vllm/vllm-openai:nightly|vllm|Qwen/Qwen3-14B-FP8|2|32768|9000|--enable-auto-tool-choice --tool-call-parser hermes --reasoning-parser qwen3||Qwen3 14B FP8 TP=2 @32K (GPU 0-1, no spec decode)|est. 25+ tok/s"
  [qw14b-40k]="rhel-ai|model-qwen3-14b-40k|docker.io/vllm/vllm-openai:nightly|vllm|Qwen/Qwen3-14B-FP8|4|40960|9000|--enable-auto-tool-choice --tool-call-parser hermes --reasoning-parser qwen3||Qwen3 14B FP8 TP=4 @40K (no spec decode)|est. 50+ tok/s"
  [d3-27b-8k]="rhel-ai|model-d3-27b-8k|docker.io/vllm/vllm-openai:nightly|vllm|vllm-sr/d3|2|8192|9001|--quantization fp8 --enforce-eager||D3 27B Decision Model FP8 TP=2 @8K (GPU 2-3)|~250-470ms/decision"
  [d3-27b-32k]="rhel-ai|model-d3-27b-32k|docker.io/vllm/vllm-openai:nightly|vllm|vllm-sr/d3|4|32768|9000|--quantization fp8 --language-model-only||D3 27B Decision Model FP8 TP=4 @32K — dedicated SDM (text-only, CUDA graphs)|1.2-9.8s/request, GT 120/122"
  [d3f-9b-32k]="rhel-ai|model-d3f-9b-32k|docker.io/vllm/vllm-openai:nightly|vllm|vllm-sr/d3-flash|1|32768|9001|--quantization fp8 --enforce-eager||D3-Flash 9B Decision Model FP8 @32K (GPU 2)|~190-315ms/decision"
)

# ── Speculative Decoding Configs ──────────────────────────────
# JSON configs for draft model speculation.
# Referenced by {PLACEHOLDER} in profile SPEC_CONFIG field.

declare -A SPEC_CONFIGS=(
  ["{SPEC_G8B_BF16}"]='{ "method": "draft_model", "model": "ibm-granite/granite-4.2-3b", "num_speculative_tokens": 5, "draft_tensor_parallel_size": 4 }'
  ["{SPEC_G8B_FP8}"]='{ "method": "draft_model", "model": "ibm-granite/granite-4.2-3b-fp8", "num_speculative_tokens": 5, "draft_tensor_parallel_size": 4 }'
  ["{SPEC_QW14B_FP8_TP2}"]='{ "method": "draft_model", "model": "Qwen/Qwen3-4B-FP8", "num_speculative_tokens": 5, "draft_tensor_parallel_size": 2 }'
  ["{SPEC_QW14B_FP8_TP4}"]='{ "method": "draft_model", "model": "Qwen/Qwen3-4B-FP8", "num_speculative_tokens": 5, "draft_tensor_parallel_size": 4 }'
)

# ── GPU Device Mapping ────────────────────────────────────────
# Profiles that use a GPU subset specify CUDA_VISIBLE_DEVICES here.
# If not listed, all GPUs are used (default).
declare -A GPU_DEVICES=(
  [qw14b-32k]="0,1"
  [d3-27b-8k]="2,3"
  [d3f-9b-32k]="2"
)

# ── Default Profiles ──────────────────────────────────────────
# One default profile per host. To change the default, edit this map.
declare -A DEFAULT_PROFILES=(
  [rhtevan-work]="g3b-16k"
  [rhel-ai]="d3-27b-32k"
)

# ── All Hosts ─────────────────────────────────────────────────
# Derived from DEPLOY_PROFILES — no separate list to maintain.
declare -a ALL_HOSTS=()
_seen_hosts=""
for _p in "${!DEPLOY_PROFILES[@]}"; do
  _h="${DEPLOY_PROFILES[$_p]%%|*}"
  if [[ ! " $_seen_hosts " == *" $_h "* ]]; then
    ALL_HOSTS+=("$_h")
    _seen_hosts="$_seen_hosts $_h"
  fi
done
unset _p _h _seen_hosts

# All profiles ordered for display
# ── Composite Profiles ─────────────────────────────────────────
# A composite profile deploys multiple containers simultaneously.
# Format: COMPOSITE_PROFILES[short_name]="profile1 profile2 ..."
# setup.sh deploys each sub-profile in order; stop.sh stops all.
# Sub-profiles must use different ports (port-based mutual exclusion).
declare -A COMPOSITE_PROFILES=(
  [qw14b+d3]="qw14b-32k d3-27b-8k"
)

# ── Container Environment Variables ───────────────────────────
# Extra environment variables passed via podman -e for specific profiles.
# setup.sh reads these and adds -e flags to the podman run command.
declare -A CONTAINER_ENV=(
  [d3-27b-8k]="PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True"
  [d3-27b-32k]="PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True"
)

ALL_PROFILES=(g350m-2k g3b-16k g8b-spec-128k g8b-fp8-spec-128k qw14b-32k qw14b-40k d3-27b-8k d3-27b-32k d3f-9b-32k qw14b+d3)

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
  # Live lookup: SSH to host, run `podman ps`, reverse-map running container → profile name.
  # No state file — ground truth is always the actual container state on the host.
  local host="$1"
  [[ "$host" == "localhost" ]] && host="rhtevan-work"

  if ! host_reachable "$host"; then
    echo ""
    return 0
  fi

  # Collect running container names from the host in one SSH call
  local running_containers
  running_containers=$(run_on_host "$host" \
    "podman ps --format '{{.Names}}' 2>/dev/null" || echo "")

  if [[ -z "$running_containers" ]]; then
    echo ""
    return 0
  fi

  # Reverse-map: find the profile whose CONTAINER is in the running list
  for profile in "${ALL_PROFILES[@]}"; do
    # Skip composite profiles — they are matched via their sub-profiles
    [[ -n "${COMPOSITE_PROFILES[$profile]:-}" ]] && continue
    parse_profile "$profile" 2>/dev/null || continue
    [[ "$PROFILE_HOST" != "$host" ]] && continue
    if echo "$running_containers" | grep -qx "$CONTAINER"; then
      echo "$profile"
      return 0
    fi
  done

  # Check composite profiles: active if ALL sub-profile containers are running
  for profile in "${ALL_PROFILES[@]}"; do
    [[ -z "${COMPOSITE_PROFILES[$profile]:-}" ]] && continue
    read -ra _subs <<< "${COMPOSITE_PROFILES[$profile]}"
    local all_up=true
    local composite_host=""
    for sub in "${_subs[@]}"; do
      parse_profile "$sub" 2>/dev/null || { all_up=false; break; }
      [[ -z "$composite_host" ]] && composite_host="$PROFILE_HOST"
      [[ "$PROFILE_HOST" != "$host" ]] && { all_up=false; break; }
      if ! echo "$running_containers" | grep -qx "$CONTAINER"; then
        all_up=false
        break
      fi
    done
    if [[ "$all_up" == "true" && -n "$composite_host" ]]; then
      echo "$profile"
      return 0
    fi
  done

  echo ""
}

get_default_profile() {
  local host="$1"
  echo "${DEFAULT_PROFILES[$host]:-}"
}

list_profiles() {
  echo "Deployment Profiles:"
  printf "  %-22s %-12s %-65s %-15s %s\n" "PROFILE" "HOST" "DESCRIPTION" "SPEED" "STATUS"
  printf "  %-22s %-12s %-65s %-15s %s\n" "-------" "----" "-----------" "-----" "------"
  for profile in "${ALL_PROFILES[@]}"; do
    parse_profile "$profile" 2>/dev/null || continue
    local status=""
    [[ "$profile" == "${DEFAULT_PROFILES[$PROFILE_HOST]:-}" ]] && status="✅ default"
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
  local result rc=0
  # Anchored name filter (unanchored matched substrings of other names).
  # A podman failure is reported as unknown — never folded into "not found".
  result=$(run_on_host "$host" "podman ps -a --filter name=^${container}\$ --format '{{.Status}}'") || rc=$?
  if (( rc != 0 )); then
    echo "unknown (podman error, exit $rc)"
    return 0
  fi
  echo "${result:-not found}"
}

# ── Fail-closed host probe (7.14.0) ───────────────────────────
# probe_host HOST — one ssh call; fills PROBE_PS with lines
#   name|state|image|command        (podman ps -a --no-trunc)
# Returns 0 = probe succeeded (PROBE_PS may legitimately be empty)
#         3 = ssh failed (unreachable / auth)      → PROBE_ERR set
#         4 = podman failed on a reachable host    → PROBE_ERR set
# Unlike get_active_profile/run_on_host, a failure is NEVER reported as
# "nothing running". Dry-run and apply paths must use this probe.
PROBE_PS=""
PROBE_ERR=""
probe_host() {
  local host="$1" out rc=0 errf
  local cmd="podman ps -a --no-trunc --format '{{.Names}}|{{.State}}|{{.Image}}|{{.Command}}'"
  PROBE_PS=""; PROBE_ERR=""
  errf=$(mktemp)
  if [[ "$host" == "localhost" ]]; then
    out=$(eval "$cmd" 2>"$errf") || rc=$?
  else
    out=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "$cmd" 2>"$errf") || rc=$?
  fi
  PROBE_ERR=$(tail -3 "$errf" | tr '\n' ' ')
  rm -f "$errf"
  if (( rc == 0 )); then
    PROBE_PS="$out"; PROBE_ERR=""
    return 0
  fi
  if [[ "$host" != "localhost" ]] && (( rc == 255 )); then
    PROBE_ERR="ssh to $host failed: ${PROBE_ERR:-exit 255}"
    return 3
  fi
  PROBE_ERR="podman on $host failed (exit $rc): ${PROBE_ERR:-no stderr}"
  return 4
}

# probe_or_fail HOST DRY_RUN — run probe_host; on failure print the reason,
# emit DRY_RUN_RESULT=UNKNOWN when DRY_RUN=true, and exit 3 (no changes made).
probe_or_fail() {
  local host="$1" dry="${2:-false}" rc=0
  probe_host "$host" || rc=$?
  (( rc == 0 )) && return 0
  echo "❌ Cannot determine container state — $PROBE_ERR" >&2
  if [[ "$dry" == "true" ]]; then
    echo "DRY_RUN_RESULT=UNKNOWN"
    if (( rc == 3 )); then echo "DRY_RUN_REASON=host-unreachable"; else echo "DRY_RUN_REASON=podman-error"; fi
  else
    echo "   Aborting — no changes made." >&2
  fi
  exit 3
}

# probe_state NAME → running|exited|created|paused|...|absent (from PROBE_PS)
probe_state() {
  local s
  s=$(awk -F'|' -v n="$1" '$1==n {print $2; exit}' <<< "$PROBE_PS")
  echo "${s:-absent}"
}

# probe_field NAME N → field N of the PROBE_PS line (3=image, 4=command).
# Field 4 (command, last) is re-joined in case the command itself contains '|'.
probe_field() {
  awk -F'|' -v n="$1" -v f="$2" '$1==n { out=$f; if (f==4) for (i=5; i<=NF; i++) out=out "|" $i; print out; exit }' <<< "$PROBE_PS"
}

# probe_port_holders PORT [EXCLUDE] → running model-* containers whose command uses --port PORT
probe_port_holders() {
  local port="$1" exclude="${2:-}"
  awk -F'|' -v p=" --port $port " -v x="$exclude" \
    '$1 ~ /^model-/ && $2=="running" && $1!=x && index(" " $4 " ", p) {print $1}' <<< "$PROBE_PS"
}

# ── GPU mutual exclusion (7.15.0) ─────────────────────────────
# profile_gpus PROFILE → GPU subset from GPU_DEVICES (e.g. "2,3") or "all"
profile_gpus() { echo "${GPU_DEVICES[$1]:-all}"; }

# gpus_overlap A B → 0 when the GPU sets intersect ("all" overlaps everything)
gpus_overlap() {
  [[ "$1" == "all" || "$2" == "all" ]] && return 0
  local g
  for g in ${1//,/ }; do [[ ",$2," == *",$g,"* ]] && return 0; done
  return 1
}

# container_profile NAME → non-composite profile whose CONTAINER is NAME (empty if none).
# Reads DEPLOY_PROFILES directly so the caller's parsed-profile globals are not clobbered.
container_profile() {
  local p c
  for p in "${!DEPLOY_PROFILES[@]}"; do
    IFS='|' read -r _ c _ <<< "${DEPLOY_PROFILES[$p]}"
    [[ "$c" == "$1" ]] && { echo "$p"; return 0; }
  done
  return 0
}

# probe_gpu_holders PROFILE [EXCLUDE] → "name|gpus" for running model containers (from
# PROBE_PS) whose GPU set overlaps PROFILE's. A running non-profile container that serves
# a model (--model in its command) is assumed to hold all GPUs. Non-model containers
# (e.g. the Skupper router) are ignored.
probe_gpu_holders() {
  local mine name state cmd p theirs
  mine=$(profile_gpus "$1")
  while IFS='|' read -r name state _ cmd; do
    [[ "$name" == model-* && "$state" == "running" && "$name" != "${2:-}" ]] || continue
    p=$(container_profile "$name")
    if [[ -n "$p" ]]; then theirs=$(profile_gpus "$p")
    elif [[ " $cmd " == *" --model "* ]]; then theirs="all"
    else continue
    fi
    gpus_overlap "$mine" "$theirs" && echo "$name|$theirs"
  done <<< "$PROBE_PS"
  return 0
}

# api_model_ids HOST PORT → model ids served on HOST:PORT; returns 1 if the API does not answer
api_model_ids() {
  local host="$1" port="$2" body
  body=$(run_on_host "$host" "curl -s -m 5 -f http://127.0.0.1:${port}/v1/models") || return 1
  jq -r '.data[].id' <<< "$body" 2>/dev/null || return 1
}

# profile_drift — compare the parsed profile (globals) with the probed container.
# Prints one reason per line; empty output = container matches the profile spec.
profile_drift() {
  local state image cmd
  state=$(probe_state "$CONTAINER")
  if [[ "$state" == "absent" ]]; then echo "container $CONTAINER does not exist"; return 0; fi
  [[ "$state" != "running" ]] && echo "container $CONTAINER is $state (not running)"
  image=$(probe_field "$CONTAINER" 3)
  cmd=" $(probe_field "$CONTAINER" 4) "
  [[ "$image" != "$IMAGE" ]] && echo "image is $image (profile: $IMAGE)"
  [[ "$cmd" != *" --port $PORT "* ]] && echo "not started with --port $PORT"
  case "$ENGINE" in
    vllm|vllm-spec)
      [[ "$cmd" != *" --model $MODEL_ID "* ]] && echo "not serving --model $MODEL_ID"
      [[ "$cmd" != *" --tensor-parallel-size $TP "* ]] && echo "not started with --tensor-parallel-size $TP"
      [[ "$cmd" != *" --max-model-len $CONTEXT "* ]] && echo "not started with --max-model-len $CONTEXT"
      ;;
    llamacpp)
      [[ "$cmd" != *" --ctx-size $CONTEXT "* ]] && echo "not started with --ctx-size $CONTEXT"
      ;;
  esac
  [[ -n "$EXTRA" && "$cmd" != *" $EXTRA "* ]] && echo "extra flags differ (profile: $EXTRA)"
  return 0
}

# dry_run_composite SCRIPT SUB... — run SCRIPT --dry-run per sub-profile and
# aggregate: any UNKNOWN → UNKNOWN (exit 3); any PENDING → PENDING; else CONVERGED.
dry_run_composite() {
  local script="$1"; shift
  local agg="CONVERGED" sub out rc r
  for sub in "$@"; do
    echo ""
    echo "── Sub-profile: $sub ──"
    rc=0
    out=$(bash "$script" --dry-run "$sub" 2>&1) || rc=$?
    printf '%s\n' "$out" | grep -v '^DRY_RUN_' || true
    r=$(grep -m1 '^DRY_RUN_RESULT=' <<< "$out" | cut -d= -f2 || true)
    echo "  → $sub: ${r:-NO SIGNAL (exit $rc)}"
    case "$r" in
      CONVERGED) ;;
      PENDING) [[ "$agg" == "CONVERGED" ]] && agg="PENDING" ;;
      *) agg="UNKNOWN" ;;
    esac
  done
  echo ""
  echo "DRY_RUN_RESULT=$agg"
  [[ "$agg" == "UNKNOWN" ]] && exit 3
  exit 0
}

# parse_cli_args NAME "USAGE" "EXTRA_FLAGS" "$@" — shared strict argument parser.
# Sets PROFILE, DRY_RUN, REMOVE. Unknown options or a second positional → exit 2.
parse_cli_args() {
  local name="$1" usage="$2" extra="$3"; shift 3
  PROFILE=""; DRY_RUN=false; REMOVE=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --remove)
        if [[ " $extra " == *" --remove "* ]]; then REMOVE=true
        else echo "❌ $name: unknown option '$1'" >&2; echo "Usage: $usage" >&2; exit 2; fi ;;
      -h|--help) echo "Usage: $usage"; exit 0 ;;
      -*) echo "❌ $name: unknown option '$1'" >&2; echo "Usage: $usage" >&2; exit 2 ;;
      *)
        if [[ -n "$PROFILE" ]]; then
          echo "❌ $name: unexpected argument '$1' (profile already '$PROFILE')" >&2
          echo "Usage: $usage" >&2; exit 2
        fi
        PROFILE="$1" ;;
    esac
    shift
  done
  if [[ -z "$PROFILE" ]]; then
    echo "Usage: $usage" >&2; echo "" >&2; list_profiles >&2; exit 1
  fi
  if [[ "$PROFILE" != "all" || " $extra " != *" all "* ]] \
     && [[ -z "${DEPLOY_PROFILES[$PROFILE]:-}" && -z "${COMPOSITE_PROFILES[$PROFILE]:-}" ]]; then
    echo "❌ $name: unknown profile '$PROFILE'" >&2
    echo "Available: ${ALL_PROFILES[*]}" >&2; exit 2
  fi
  return 0
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
    code=$(run_on_host "$host" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${port}/v1/models 2>/dev/null" || echo "000")
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

# Check that deployment-profiles.md ✅ Default markers match persistent state
check_doc_alignment() {
  local doc
  doc="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../references/deployment-profiles.md"
  [[ -f "$doc" ]] || return 0  # no doc to check

  local drift=0
  for host in "${ALL_HOSTS[@]}"; do
    local configured_default
    configured_default=$(get_default_profile "$host")
    [[ -z "$configured_default" ]] && continue

    # Find which profile has ✅ Default under the host's section
    # Section header: ## Profiles — <host>
    # Profile header: ### `profile-name` ... ✅ Default
    local in_section=false
    local doc_default=""
    while IFS= read -r line; do
      if [[ "$line" =~ ^##\ Profiles\ —\  ]]; then
        if [[ "$line" == *"$host"* ]]; then
          in_section=true
        else
          $in_section && break  # left our section
        fi
      fi
      if $in_section && [[ "$line" =~ ^###\ \` ]] && [[ "$line" == *"✅ Default"* ]]; then
        # Extract profile name from ### `profile-name`
        doc_default=$(echo "$line" | sed "s/^### \`//" | sed "s/\`.*//" )
      fi
    done < "$doc"

    if [[ -n "$doc_default" && "$doc_default" != "$configured_default" ]]; then
      echo "  ⚠️  Doc drift ($host): deployment-profiles.md says default is '$doc_default', common.sh says '$configured_default'"
      drift=1
    elif [[ -z "$doc_default" ]]; then
      echo "  ⚠️  Doc drift ($host): no ✅ Default marker found in deployment-profiles.md (configured default: $configured_default)"
      drift=1
    fi
  done
  return $drift
}
