#!/usr/bin/env bash
# setup.sh — Deploy (create) a model container
# Usage: bash setup.sh ALIAS
# Idempotent: removes existing container before creating.

source "$(dirname "$0")/common.sh"

ALIAS="${1:?Usage: setup.sh ALIAS}"
parse_model "$ALIAS"

echo "=== Setup: $ALIAS ==="
echo "  Model:     $MODEL_ID"
echo "  Container: $CONTAINER"
echo "  Host:      $HOST"
echo "  Port:      $PORT"
echo "  Engine:    $ENGINE"
echo "  Image:     $IMAGE"
echo

# Stop and remove existing container
run_on_host "$HOST" "podman stop $CONTAINER 2>/dev/null; podman rm -f $CONTAINER 2>/dev/null" || true

# Create HF cache directory
case "$HOST" in
  rhel-ai)
    run_on_host "$HOST" "mkdir -p ~/.cache/huggingface"
    ;;
  rhtevan-work)
    run_on_host "$HOST" "mkdir -p ~/.cache/huggingface ~/.cache/huggingface/gguf"
    ;;
esac

# Deploy based on engine type
case "$ENGINE" in
  vllm)
    run_on_host "$HOST" "podman run -d \
      --name $CONTAINER \
      --device nvidia.com/gpu=all \
      --security-opt=label=disable \
      --network host \
      -v ~/.cache/huggingface:/root/.cache/huggingface:Z \
      $IMAGE \
      --model $MODEL_ID \
      --dtype float16 \
      --gpu-memory-utilization 0.95 \
      --max-model-len $CONTEXT \
      --enforce-eager \
      --host 0.0.0.0 \
      --port $PORT \
      --enable-auto-tool-choice \
      --tool-call-parser granite"
    ;;

  vllm-bnb)
    run_on_host "$HOST" "podman run -d \
      --name $CONTAINER \
      --device nvidia.com/gpu=all \
      --security-opt=label=disable \
      --network host \
      -v ~/.cache/huggingface:/root/.cache/huggingface:Z \
      $IMAGE \
      --model $MODEL_ID \
      --quantization bitsandbytes \
      --load-format bitsandbytes \
      --gpu-memory-utilization 0.95 \
      --max-model-len $CONTEXT \
      --enforce-eager \
      --host 0.0.0.0 \
      --port $PORT \
      --enable-auto-tool-choice \
      --tool-call-parser granite"
    ;;

  llamacpp)
    # Check GGUF file exists
    local gguf_file="granite-4.1-8b-Q4_K_M.gguf"
    local gguf_path="~/.cache/huggingface/gguf/$gguf_file"
    run_on_host "$HOST" "test -f $gguf_path" || {
      echo "Downloading $gguf_file (~5.35 GB)..."
      run_on_host "$HOST" "curl -L -o $gguf_path \
        'https://huggingface.co/ibm-granite/granite-4.1-8b-GGUF/resolve/main/$gguf_file'"
    }
    run_on_host "$HOST" "podman run -d \
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
      --n-gpu-layers 18"
    ;;

  vllm-ilab)
    local hf_cache
    case "$HOST" in
      rhel-ai) hf_cache="/var/home/cloud-user/.cache/huggingface" ;;
      *)       hf_cache="$HOME/.cache/huggingface" ;;
    esac
    run_on_host "$HOST" "podman run -d \
      --name $CONTAINER \
      --device nvidia.com/gpu=all \
      --security-opt label=disable \
      --net host \
      --shm-size 10G \
      --pids-limit -1 \
      -v ${hf_cache}:/opt/app-root/src/.cache/huggingface \
      --entrypoint python3 \
      $IMAGE \
      -m vllm.entrypoints.openai.api_server \
      --host 0.0.0.0 --port $PORT \
      --model $MODEL_ID \
      --tensor-parallel-size $TP \
      --max-model-len $CONTEXT \
      --gpu-memory-utilization 0.95 \
      --trust-remote-code \
      --disable-custom-all-reduce \
      --dtype bfloat16"
    ;;

  *)
    echo "❌ Unknown engine: $ENGINE" >&2
    exit 2
    ;;
esac

echo "✅ Container $CONTAINER created on $HOST"

# Determine wait time
case "$ALIAS" in
  g350m|g1b)   WAIT=180 ;;
  g8b)         WAIT=30 ;;
  g8b-128k)    WAIT=480 ;;
  g30b-96k)    WAIT=1200 ;;
  *)           WAIT=120 ;;
esac

echo "First-run download may take longer. Waiting up to ${WAIT}s..."
wait_for_model "$HOST" "$PORT" "$WAIT"
