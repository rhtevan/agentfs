#!/usr/bin/env bash
# setup.sh — Deploy a deployment profile
# Usage: bash setup.sh PROFILE
# Idempotent: removes existing container before creating.
# All deployments go through profiles — no individual model aliases.

source "$(dirname "$0")/common.sh"

PROFILE="${1:-}"

if [[ -z "$PROFILE" ]]; then
  echo "Usage: setup.sh PROFILE" >&2
  echo "" >&2
  list_profiles >&2
  exit 1
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

# Check host reachable
if ! host_reachable "$PROFILE_HOST"; then
  echo "❌ Host $PROFILE_HOST is unreachable." >&2
  exit 1
fi

# Stop and remove existing container
run_on_host "$PROFILE_HOST" "podman stop $CONTAINER 2>/dev/null; podman rm -f $CONTAINER 2>/dev/null" || true

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

    run_on_host "$PROFILE_HOST" "podman run -d \
      --name $CONTAINER \
      --device nvidia.com/gpu=all \
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

# Set active profile
set_active_profile "$PROFILE_HOST" "$PROFILE"

# Determine wait time
case "$PROFILE" in
  g350m-2k)          WAIT=180 ;;
  g3b-16k)           WAIT=60 ;;
  g8b-spec-128k)     WAIT=600 ;;
  g8b-fp8-spec-128k) WAIT=600 ;;
  *)                 WAIT=300 ;;
esac

echo "First-run download may take longer. Waiting up to ${WAIT}s..."
wait_for_model "$PROFILE_HOST" "$PORT" "$WAIT"
