#!/usr/bin/env bash
# setup.sh — Deploy a deployment profile
# Usage: bash setup.sh [--dry-run] PROFILE
# Idempotent: removes existing container before creating.
# All deployments go through profiles — no individual model aliases.
#
# --dry-run (read-only, Rule 7): probes the host and prints one signal
#   DRY_RUN_RESULT=CONVERGED  container running, matches profile spec, API serves the model
#   DRY_RUN_RESULT=PENDING    apply would change something (plan printed)
#   DRY_RUN_RESULT=UNKNOWN    state could not be determined (exit 3) — do NOT apply
# Exit codes: 0 ok · 1 usage/precondition · 2 bad argument · 3 host/podman probe failed

source "$(dirname "$0")/common.sh"

parse_cli_args setup.sh "setup.sh [--dry-run] PROFILE" "" "$@"

# ── Composite profile handling ──────────────────────────────────
if [[ -n "${COMPOSITE_PROFILES[$PROFILE]:-}" ]]; then
  echo "=== Setup (composite): $PROFILE ==="
  read -ra SUB_PROFILES <<< "${COMPOSITE_PROFILES[$PROFILE]}"
  $DRY_RUN && dry_run_composite "$(dirname "$0")/setup.sh" "${SUB_PROFILES[@]}"
  # Resolve host from first sub-profile
  parse_profile "${SUB_PROFILES[0]}"
  COMPOSITE_HOST="$PROFILE_HOST"
  for sub in "${SUB_PROFILES[@]}"; do
    echo ""
    echo "── Sub-profile: $sub ──"
    bash "$(dirname "$0")/setup.sh" "$sub"
  done
  echo ""
  echo "✅ Composite profile '$PROFILE' deployed (${#SUB_PROFILES[@]} containers)"
  exit 0
fi

parse_profile "$PROFILE"

echo "=== Setup: $PROFILE ==="
echo "  Description: $PROFILE_DESC"
echo "  Host:        $PROFILE_HOST"
echo "  Model:       $MODEL_ID"
echo "  Container:   $CONTAINER"
echo "  Engine:      $ENGINE"
echo "  Image:       $IMAGE"
echo "  TP:          $TP"
echo "  Context:     $CONTEXT"
echo "  Port:        $PORT"
echo "  Speed:       $PROFILE_SPEED"
[[ -n "$EXTRA" ]] && echo "  Extra:       $EXTRA"
if [[ -n "$SPEC_CONFIG" ]]; then
  spec_json=$(resolve_spec_config "$SPEC_CONFIG")
  [[ -n "$spec_json" ]] && echo "  Spec:        $spec_json"
fi
echo

# Probe host state — fail closed: ssh or podman failure aborts (exit 3), no changes.
probe_or_fail "$PROFILE_HOST" "$DRY_RUN"

if $DRY_RUN; then
  drift=$(profile_drift)
  served=""
  if [[ -z "$drift" ]]; then
    if served=$(api_model_ids "$PROFILE_HOST" "$PORT"); then
      if [[ "$ENGINE" != "llamacpp" ]] && ! grep -qxF "$MODEL_ID" <<< "$served"; then
        drift="API on :$PORT serves '$(echo $served)', not $MODEL_ID"
      fi
    else
      drift="container running but API on :$PORT not answering /v1/models"
    fi
  fi
  if [[ -z "$drift" ]]; then
    echo "✅ $CONTAINER is running, matches the profile, API serves $(echo $served)"
    echo "DRY_RUN_RESULT=CONVERGED"
    exit 0
  fi
  echo "Not converged:"
  printf '%s\n' "$drift" | sed 's/^/  - /'
  echo "Plan (apply):"
  while read -r holder; do
    [[ -n "$holder" ]] && echo "  - stop + remove $holder (holds port $PORT)"
  done < <(probe_port_holders "$PORT" "$CONTAINER")
  state=$(probe_state "$CONTAINER")
  [[ "$state" != "absent" ]] && echo "  - remove existing $CONTAINER ($state)"
  echo "  - podman run $CONTAINER: $IMAGE --model $MODEL_ID TP=$TP ctx=$CONTEXT port=$PORT ${EXTRA}"
  echo "  - wait for /v1/models on $PROFILE_HOST:$PORT"
  echo "DRY_RUN_RESULT=PENDING"
  exit 0
fi

# Stop and remove any model container on this port (port-based mutual exclusion)
# Fixes: switching between profiles with different container names on the same port.
# Host-network containers don't use --publish, so we match by name prefix "model-".
run_on_host "$PROFILE_HOST" "
  for cid in \$(podman ps -q --filter name='^model-' 2>/dev/null); do
    cname=\$(podman inspect --format '{{.Name}}' \$cid 2>/dev/null)
    # Check if this container is using our port (grep the process args)
    if podman inspect --format '{{.Config.Cmd}}' \$cid 2>/dev/null | grep -q -- '--port ${PORT}'; then
      echo \"Stopping \$cname (port ${PORT})\"
      podman stop \$cid 2>/dev/null
      podman rm -f \$cid 2>/dev/null
    fi
  done
" || true
# Also stop by container name in case it exists but is not running
run_on_host "$PROFILE_HOST" "podman rm -f $CONTAINER 2>/dev/null" || true

# Create HF cache directory
case "$PROFILE_HOST" in
  rhel-ai)
    run_on_host "$PROFILE_HOST" "mkdir -p ~/.cache/huggingface"
    ;;
  rhtevan-work)
    run_on_host "$PROFILE_HOST" "mkdir -p ~/.cache/huggingface ~/.cache/huggingface/gguf"
    ;;
esac

# Deploy based on engine type
case "$ENGINE" in
  vllm|vllm-spec)
    # Upstream vLLM
    hf_cache=""
    vol_suffix=""
    case "$PROFILE_HOST" in
      rhel-ai)
        hf_cache="/var/home/cloud-user/.cache/huggingface"
        ;;
      rhtevan-work)
        hf_cache="\$HOME/.cache/huggingface"
        vol_suffix=":Z"
        ;;
      *)
        hf_cache="\$HOME/.cache/huggingface"
        vol_suffix=":Z"
        ;;
    esac

    # Build speculative decoding flag for vllm-spec engine
    spec_flag=""
    if [[ "$ENGINE" == "vllm-spec" && -n "$SPEC_CONFIG" ]]; then
      spec_json=$(resolve_spec_config "$SPEC_CONFIG")
      if [[ -n "$spec_json" ]]; then
        spec_flag="--speculative-config '${spec_json}'"
      else
        echo "⚠️  No spec config found for '$SPEC_CONFIG', deploying without speculation" >&2
      fi
    fi

    # GPU device selection: subset or all
    gpu_devices="${GPU_DEVICES[$PROFILE]:-}"
    device_flag="--device nvidia.com/gpu=all"
    env_flag=""
    if [[ -n "$gpu_devices" ]]; then
      device_flag="--device nvidia.com/gpu=all"
      env_flag="-e CUDA_VISIBLE_DEVICES=$gpu_devices"
      echo "  GPUs:        $gpu_devices (subset)"
    fi

    # Per-profile environment variables (e.g., PYTORCH_CUDA_ALLOC_CONF)
    container_env="${CONTAINER_ENV[$PROFILE]:-}"
    if [[ -n "$container_env" ]]; then
      env_flag="$env_flag -e $container_env"
      echo "  Env:         $container_env"
    fi

    run_on_host "$PROFILE_HOST" "podman run -d \
      --name $CONTAINER \
      $device_flag \
      $env_flag \
      --security-opt label=disable \
      --net host \
      --shm-size 10G \
      --pids-limit -1 \
      -v ${hf_cache}:/root/.cache/huggingface${vol_suffix} \
      $IMAGE \
      --model $MODEL_ID \
      --tensor-parallel-size $TP \
      --max-model-len $CONTEXT \
      --gpu-memory-utilization 0.95 \
      --disable-custom-all-reduce \
      --host 0.0.0.0 \
      --port $PORT \
      $EXTRA \
      $spec_flag"
    ;;

  llamacpp)
    # Determine GGUF filename from model ID
    case "$MODEL_ID" in
      *granite*3b*)
        # Version-agnostic: detect available GGUF on the host
        # Prefer 4.1 over 4.2 for llama.cpp: 4.2 reasoning tokens leak
        # into content (llama.cpp has no reasoning parser), 4.2 GGUF is
        # 145 MB larger (0.14 GiB headroom on 4 GB GPU), and 3B reasoning
        # quality is marginal. Decision: 2026-09-01.
        gguf_file=""
        gpu_layers=99
        for candidate in granite-4.1-3b-Q4_K_M.gguf granite-4.2-3b-Q4_K_M.gguf; do
          if run_on_host "$PROFILE_HOST" "test -f ~/.cache/huggingface/gguf/$candidate" 2>/dev/null; then
            gguf_file="$candidate"
            break
          fi
        done
        if [[ -z "$gguf_file" ]]; then
          echo "❌ No granite 3B GGUF found on $PROFILE_HOST" >&2
          exit 2
        fi
        echo "  GGUF: $gguf_file"
        ;;
      *)
        echo "❌ Unknown llamacpp model: $MODEL_ID" >&2
        exit 2
        ;;
    esac

    gguf_path="~/.cache/huggingface/gguf/$gguf_file"

    # Download GGUF if needed
    run_on_host "$PROFILE_HOST" "test -f $gguf_path" || {
      echo "Downloading $gguf_file..."
      run_on_host "$PROFILE_HOST" "curl -L -o $gguf_path \
        'https://huggingface.co/${gguf_repo}/resolve/main/$gguf_file'"
    }

    run_on_host "$PROFILE_HOST" "podman run -d \
      --name $CONTAINER \
      --device nvidia.com/gpu=all \
      --security-opt=label=disable \
      --network host \
      -v ~/.cache/huggingface/gguf:/models:Z \
      $IMAGE \
      --model /models/$gguf_file \
      --host 0.0.0.0 \
      --port $PORT \
      --ctx-size $CONTEXT \
      --threads 14 \
      --n-gpu-layers $gpu_layers \
      $EXTRA"
    ;;

  *)
    echo "❌ Unknown engine: $ENGINE" >&2
    exit 2
    ;;
esac

echo "✅ Container $CONTAINER created on $PROFILE_HOST"

# Determine wait time
case "$PROFILE" in
  g350m-2k)          WAIT=180 ;;
  g3b-16k)           WAIT=60 ;;
  g8b-spec-128k)     WAIT=600 ;;
  g8b-fp8-spec-128k) WAIT=600 ;;
  qw14b-32k)         WAIT=900 ;;
  qw14b-40k)         WAIT=900 ;;
  *)                 WAIT=300 ;;
esac

echo "First-run download may take longer. Waiting up to ${WAIT}s..."
wait_for_model "$PROFILE_HOST" "$PORT" "$WAIT"
