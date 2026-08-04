---
name: local-model-ctl
description: >
  Deploy, manage, and troubleshoot containerized LLM inference servers
  for IBM Granite models on NVIDIA GPUs with limited VRAM (4 GB).
  Supports multiple models (g350m, g1b, g8b) with automatic engine
  selection (vLLM for small models, llama.cpp for larger ones).
  Operations: list, pre-check, setup, test, status, start, stop.
  Works on localhost or any remote host with SSH connectivity.
argument-hint: "'model list', 'model start g8b on rhtevan-work', 'model status', 'model stop'"
compatibility: "Requires Podman, NVIDIA driver, nvidia-container-toolkit, CDI spec"
metadata:
  author: agentfs
  version: "2.1"
  tags: [granite, vllm, llama-cpp, inference, llm, podman, nvidia, gpu, model-serving, tool-calling, gguf]
  signals:
    - "model list"
    - "model setup"
    - "model start"
    - "model stop"
    - "model status"
    - "model test"
    - "model pre-check"
    - "deploy model"
    - "start model"
    - "stop model"
    - "start vllm"
    - "stop vllm"
    - "start llama"
    - "stop llama"
    - "granite start"
    - "granite stop"
    - "granite status"
user-invocable: true
disable-model-invocation: false
---

# Local Model Control

Operational procedures for deploying and managing containerized LLM
inference servers for IBM Granite models. Supports multiple models with
automatic engine selection based on model size and GPU constraints.
Designed for NVIDIA GPUs with limited VRAM (tested on RTX A500 Laptop
GPU with 4 GB VRAM).

## Target Host

All commands support **localhost** or a **remote host via SSH**. When a
remote host is specified, wrap commands with `ssh <host> '...'`.

- If user says "on rhtevan-work" or "on <hostname>", set `TARGET_HOST`
  to that hostname and prefix all shell commands with `ssh $TARGET_HOST`.
- If no host is specified, run locally.
- Commands that require `sudo` cannot be run remotely without a TTY —
  guide the user to run those manually.

---

## Supported Models

### Model Registry

| Alias | Model | Params | Engine | Quantization | Container Name | Container Image | VRAM Used | Context | Gen Speed |
|:-----:|-------|:------:|:------:|:------------:|:--------------:|-----------------|:---------:|:-------:|:---------:|
| **`g350m`** | `ibm-granite/granite-4.0-350m` | 0.35B | vLLM | FP16 (none) | `model-g350m` | `docker.io/vllm/vllm-openai:latest` | ~0.7 GiB | 2,048 | ~20 tok/s |
| **`g1b`** | `ibm-granite/granite-4.0-1b` | 1.63B | vLLM | bitsandbytes INT4 | `model-g1b` | `docker.io/vllm/vllm-openai:latest` | ~1.17 GiB | 2,048 | ~4 tok/s |
| **`g8b`** | `ibm-granite/granite-4.1-8b` | 8.79B | llama.cpp | GGUF Q4_K_M | `model-g8b` | `ghcr.io/ggml-org/llama.cpp:server-cuda-b9994` | ~2.5 GiB (18 layers) | 16,384 | ~8 tok/s |

**Default model: `g350m`**

When the user says `model start` without specifying a model alias,
use `g350m`.

### Container Naming Convention

Each model gets a **unique container name** based on its alias:
`model-<alias>` (e.g., `model-g350m`, `model-g1b`, `model-g8b`).

This allows:
- Multiple models to be deployed (containers exist) simultaneously
- Only one model running at a time (they share port 8000)
- True `start`/`stop` switching without redeployment
- Easy identification of which model a container holds

### Model Capabilities

| Capability | g350m | g1b | g8b |
|------------|:-----:|:---:|:---:|
| Chat / Instruction Following | ✅ | ✅ | ✅ |
| Tool / Function Calling | ✅ | ✅ | ✅ |
| RAG | ✅ | ✅ | ✅ |
| Code Generation | ✅ | ✅ | ✅ |
| Multilingual (12 languages) | ✅ | ✅ | ✅ |
| AgentFS Compatible (16K+ ctx) | ❌ (2K) | ❌ (2K) | ✅ (16K) |
| Quality | Basic | Good | **Best** |

### Engine Selection Logic

| Condition | Engine | Why |
|-----------|--------|-----|
| Model fits entirely on GPU (FP16 or INT4) | **vLLM** | Best throughput, full GPU acceleration |
| Model too large for GPU, needs CPU+GPU hybrid | **llama.cpp** | CPU-first with partial GPU offload |

---

## Container Details

### vLLM Containers (g350m, g1b)

| Setting | Value |
|---------|-------|
| **Container name** | `model-g350m` or `model-g1b` |
| **Image** | `docker.io/vllm/vllm-openai:latest` |
| **Network mode** | `--network host` |
| **GPU passthrough** | `--device nvidia.com/gpu=all` via CDI |
| **API port** | 8000 |

### llama.cpp Container (g8b)

| Setting | Value |
|---------|-------|
| **Container name** | `model-g8b` |
| **Image** | `ghcr.io/ggml-org/llama.cpp:server-cuda-b9994` |
| **Network mode** | `--network host` |
| **GPU passthrough** | `--device nvidia.com/gpu=all` via CDI |
| **API port** | 8000 |
| **GGUF file** | `~/.cache/huggingface/gguf/granite-4.1-8b-Q4_K_M.gguf` |

---

## Operations

### 1. List

Show all supported models and their configurations.

Print the **Model Registry** table above. Also check if any model
containers exist and indicate their status.

```bash
# Check for all model containers
podman ps -a --filter name=model-g350m --format "model-g350m: {{.Status}}" 2>/dev/null
podman ps -a --filter name=model-g1b --format "model-g1b: {{.Status}}" 2>/dev/null
podman ps -a --filter name=model-g8b --format "model-g8b: {{.Status}}" 2>/dev/null
```

### 2. Pre-Check

Verify the host meets all requirements before deployment.

```bash
# 2a. Check NVIDIA GPU and driver
lspci | grep -iE '3d|vga' | grep -i nvidia
ls -la /dev/nvidia*

# 2b. Check container runtime
which podman && podman --version

# 2c. Check NVIDIA Container Toolkit & CDI
nvidia-ctk cdi list
ls /etc/cdi/nvidia.yaml

# 2d. Check HuggingFace cache directory exists
mkdir -p ~/.cache/huggingface
mkdir -p ~/.cache/huggingface/gguf

# 2e. GPU passthrough test (no nvidia-smi on Fedora RPMFusion!)
# Use Python NVML script instead:
cat > /tmp/gpu_check.py << 'EOF'
import ctypes

nv = ctypes.CDLL("libnvidia-ml.so.1")
nv.nvmlInit()

count = ctypes.c_uint()
nv.nvmlDeviceGetCount(ctypes.byref(count))
print(f"GPU count: {count.value}")

handle = ctypes.c_void_p()
nv.nvmlDeviceGetHandleByIndex(0, ctypes.byref(handle))

name = ctypes.create_string_buffer(256)
nv.nvmlDeviceGetName(handle, name, 256)
print(f"GPU name: {name.value.decode()}")

class MemInfo(ctypes.Structure):
    _fields_ = [("total", ctypes.c_ulonglong), ("free", ctypes.c_ulonglong), ("used", ctypes.c_ulonglong)]

mi = MemInfo()
nv.nvmlDeviceGetMemoryInfo(handle, ctypes.byref(mi))
print(f"VRAM total: {mi.total / 1024**3:.1f} GB")
print(f"VRAM free:  {mi.free / 1024**3:.1f} GB")
print(f"VRAM used:  {mi.used / 1024**3:.1f} GB")

nv.nvmlShutdown()
print("GPU passthrough: OK")
EOF

podman run --rm \
  --device nvidia.com/gpu=all \
  --security-opt=label=disable \
  -v /tmp/gpu_check.py:/gpu_check.py:Z \
  nvcr.io/nvidia/cuda:12.6.0-base-ubuntu22.04 \
  bash -c "apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq python3 >/dev/null 2>&1 && python3 /gpu_check.py"

# 2f. Check GGUF model file for g8b
ls -lh ~/.cache/huggingface/gguf/granite-4.1-8b-Q4_K_M.gguf 2>/dev/null || echo "GGUF not downloaded yet"
```

**If NVIDIA Container Toolkit is missing** (requires sudo — guide user):

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
  | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null
sudo dnf install -y nvidia-container-toolkit
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

### 3. Setup (Deploy)

Deploy a model. Accepts an optional model alias parameter.

**Usage:** `model setup [g350m|g1b|g8b]` — defaults to `g350m`.

Before deploying, stop any running model (port 8000 conflict) and
remove the target container if it already exists:

```bash
# Stop any running model containers (they share port 8000)
podman stop model-g350m 2>/dev/null; podman stop model-g1b 2>/dev/null; podman stop model-g8b 2>/dev/null

# Remove the specific container being deployed
podman rm -f model-<ALIAS> 2>/dev/null

mkdir -p ~/.cache/huggingface
mkdir -p ~/.cache/huggingface/gguf
```

#### g350m (default)

```bash
podman run -d \
  --name model-g350m \
  --device nvidia.com/gpu=all \
  --security-opt=label=disable \
  --network host \
  -v ~/.cache/huggingface:/root/.cache/huggingface:Z \
  docker.io/vllm/vllm-openai:latest \
  --model ibm-granite/granite-4.0-350m \
  --dtype float16 \
  --gpu-memory-utilization 0.95 \
  --max-model-len 2048 \
  --enforce-eager \
  --host 0.0.0.0 \
  --port 8000 \
  --enable-auto-tool-choice \
  --tool-call-parser granite
```

#### g1b

```bash
podman run -d \
  --name model-g1b \
  --device nvidia.com/gpu=all \
  --security-opt=label=disable \
  --network host \
  -v ~/.cache/huggingface:/root/.cache/huggingface:Z \
  docker.io/vllm/vllm-openai:latest \
  --model ibm-granite/granite-4.0-1b \
  --quantization bitsandbytes \
  --load-format bitsandbytes \
  --gpu-memory-utilization 0.95 \
  --max-model-len 2048 \
  --enforce-eager \
  --host 0.0.0.0 \
  --port 8000 \
  --enable-auto-tool-choice \
  --tool-call-parser granite
```

#### g8b

**First-time setup** — download the GGUF file (~5.35 GB) if not cached:

```bash
if [ ! -f ~/.cache/huggingface/gguf/granite-4.1-8b-Q4_K_M.gguf ]; then
  echo "Downloading granite-4.1-8b Q4_K_M GGUF (~5.35 GB)..."
  curl -L -o ~/.cache/huggingface/gguf/granite-4.1-8b-Q4_K_M.gguf \
    "https://huggingface.co/ibm-granite/granite-4.1-8b-GGUF/resolve/main/granite-4.1-8b-Q4_K_M.gguf"
fi
```

Then deploy:

```bash
podman run -d \
  --name model-g8b \
  --device nvidia.com/gpu=all \
  --security-opt=label=disable \
  --network host \
  -v ~/.cache/huggingface/gguf:/models:Z \
  ghcr.io/ggml-org/llama.cpp:server-cuda-b9994 \
  --model /models/granite-4.1-8b-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8000 \
  --ctx-size 16384 \
  --threads 14 \
  --n-gpu-layers 18
```

**Wait for startup:**
- vLLM models (g350m, g1b): ~2-3 minutes. Watch for `Application startup complete.`
- llama.cpp (g8b): ~15-30 seconds. Watch for `listening on http://0.0.0.0:8000`

### 4. Test

Verify the deployment is working correctly.

#### For vLLM models (g350m, g1b)

```bash
# API check
curl -s http://localhost:8000/v1/models | python3 -m json.tool

# Chat test
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "MODEL_NAME", "messages": [{"role": "user", "content": "Hello! What can you do?"}], "max_tokens": 150}' \
  | python3 -m json.tool

# Tool calling test
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "MODEL_NAME", "messages": [{"role": "user", "content": "What is the weather in London?"}], "tools": [{"type": "function", "function": {"name": "get_weather", "description": "Get weather", "parameters": {"type": "object", "properties": {"location": {"type": "string"}}, "required": ["location"]}}}], "max_tokens": 200}' \
  | python3 -m json.tool
```

Replace `MODEL_NAME` with:
- g350m: `ibm-granite/granite-4.0-350m`
- g1b: `ibm-granite/granite-4.0-1b`

#### For llama.cpp (g8b)

```bash
# API check
curl -s http://localhost:8000/v1/models | python3 -m json.tool

# Chat test
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "/models/granite-4.1-8b-Q4_K_M.gguf", "messages": [{"role": "user", "content": "Hello! What can you do?"}], "max_tokens": 150}' \
  | python3 -m json.tool

# Tool calling test
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "/models/granite-4.1-8b-Q4_K_M.gguf", "messages": [{"role": "user", "content": "What is the weather in London?"}], "tools": [{"type": "function", "function": {"name": "get_weather", "description": "Get weather", "parameters": {"type": "object", "properties": {"location": {"type": "string"}}, "required": ["location"]}}}], "max_tokens": 200}' \
  | python3 -m json.tool
```

### 5. Status

Check the current state of any deployed model.

```bash
# Check all model containers
podman ps -a --filter name=model-g350m --format "model-g350m: {{.Status}}" 2>/dev/null
podman ps -a --filter name=model-g1b --format "model-g1b: {{.Status}}" 2>/dev/null
podman ps -a --filter name=model-g8b --format "model-g8b: {{.Status}}" 2>/dev/null

# Logs for the running container
for c in model-g350m model-g1b model-g8b; do
  podman logs --tail 5 $c 2>/dev/null && echo "--- $c logs above ---"
done
```

### 6. Start

Start a previously stopped container. Accepts an optional model alias.

**Usage:** `model start [g350m|g1b|g8b]` — defaults to `g350m`.

**Important:** Only one model can run at a time (they share port 8000).
Stop any running model before starting a different one.

```bash
# Stop all running model containers first
podman stop model-g350m 2>/dev/null
podman stop model-g1b 2>/dev/null
podman stop model-g8b 2>/dev/null

# Start the desired model
podman start model-<ALIAS>
```

Replace `<ALIAS>` with `g350m`, `g1b`, or `g8b`.

If the container doesn't exist (never set up), run the **Setup**
procedure instead.

### 7. Stop

Stop the running container. Optionally specify which model to stop.

**Usage:** `model stop [g350m|g1b|g8b]` — if no alias, stops all.

```bash
# Stop a specific model
podman stop model-<ALIAS>

# Or stop all
podman stop model-g350m 2>/dev/null
podman stop model-g1b 2>/dev/null
podman stop model-g8b 2>/dev/null
```

To stop and remove a specific model:

```bash
podman rm -f model-<ALIAS>
```

To remove all model containers:

```bash
podman rm -f model-g350m 2>/dev/null
podman rm -f model-g1b 2>/dev/null
podman rm -f model-g8b 2>/dev/null
```

---

## Lessons Learned & Gotchas

These are critical findings from real-world deployment. Follow them
to avoid common failures.

### Fedora-Specific

| Issue | Detail | Workaround |
|-------|--------|------------|
| **No `nvidia-smi`** | RPMFusion NVIDIA packages don't include `nvidia-smi` | Use Python NVML script (`libnvidia-ml.so.1`) for GPU verification |
| **CUDA toolkit not needed** | Container bundles its own CUDA runtime | Only need host NVIDIA driver + nvidia-container-toolkit |

### Podman-Specific

| Issue | Detail | Workaround |
|-------|--------|------------|
| **Short-name resolution fails** | Podman enforces short-name resolution, fails without TTY | Always use full image path: `docker.io/...` or `ghcr.io/...` |
| **`pasta` network breaks port forwarding** | Default Podman network mode causes `Connection reset by peer` | Use `--network host` |
| **Missing cache directory** | `~/.cache/huggingface` may not exist | `mkdir -p` before running |
| **SELinux volume mounts** | Volume mounts need `:Z` suffix on Fedora/RHEL | Use `-v path:path:Z` |

### vLLM-Specific (g350m, g1b)

| Issue | Detail | Workaround |
|-------|--------|------------|
| **FP16 OOM on 4 GB GPU** | `granite-4.0-1b` at FP16 uses 3.07 GiB, no room for KV cache | Use `--quantization bitsandbytes --load-format bitsandbytes` |
| **`--dtype float16` + bitsandbytes = garbage** | Explicitly setting dtype causes garbled output | Omit `--dtype` — let vLLM auto-detect |
| **GPTQ models may fail** | Community GPTQ quants can have `KeyError` on hybrid architectures | Use bitsandbytes instead |
| **Tool calling needs flags** | Not enabled by default | Add `--enable-auto-tool-choice --tool-call-parser granite` |
| **CUDAGraph + bitsandbytes incompatible** | CUDAGraph compilation fails with quantized models | Use `--enforce-eager` |
| **CPU offloading fails on small GPUs** | vLLM loads full model to GPU before offloading | Use llama.cpp for models that don't fit |

### llama.cpp-Specific (g8b)

| Issue | Detail | Workaround |
|-------|--------|------------|
| **`--n-gpu-layers 999` OOM** | Tries to put all layers on GPU | Use `--n-gpu-layers 18` for 16K ctx |
| **Old images lack Granite support** | `ghcr.io/ggerganov/llama.cpp:server-cuda` doesn't exist | Use `ghcr.io/ggml-org/llama.cpp:server-cuda-b9994` (ggml-org, with build tag) |
| **Larger context = fewer GPU layers** | KV cache competes with model layers for VRAM | 4K ctx → 25 layers, 16K ctx → 18 layers |
| **GGUF must be pre-downloaded** | llama.cpp doesn't auto-download from HuggingFace | Pre-download with `curl -L -o ... .gguf` |

### GPU Layer Tuning (g8b, 4 GB VRAM)

| Context Size | Max GPU Layers | Prompt Speed | Gen Speed |
|:------------:|:--------------:|:------------:|:---------:|
| 4,096 | 25 | 53.9 tok/s | 10.8 tok/s |
| 16,384 | 18 | 44.6 tok/s | 8.3 tok/s |

### Memory Budget (4 GB VRAM)

#### vLLM — g1b (bitsandbytes INT4)

| Component | Usage |
|-----------|-------|
| Model weights | ~1.17 GiB |
| Peak activation | ~0.36 GiB |
| KV cache | ~1.92 GiB |
| **Total** | ~3.5 / 3.68 GiB |

#### llama.cpp — g8b (GGUF Q4_K_M, 18 GPU layers)

| Component | Usage |
|-----------|-------|
| 18 GPU layers | ~2.5 GiB |
| KV cache (16K ctx) | ~1.0 GiB |
| CPU: remaining layers + overhead | ~5 GiB system RAM |
| **GPU Total** | ~3.5 / 3.68 GiB |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-08-04 | v2.1 — Model-specific container names (`model-g350m`, `model-g1b`, `model-g8b`); enables true start/stop switching without redeployment; multiple models can be deployed simultaneously (only one running at a time on port 8000) |
| 2026-08-04 | v2.0 — Renamed from `granite-4.0-1b-model-ctl` to `local-model-ctl`; added multi-model support (g350m, g1b, g8b); added llama.cpp engine for g8b; added `list` operation; added model alias parameter to start/setup; GPU layer tuning data |
| 2026-08-04 | v1.0 — Initial creation as `granite-4.0-1b-model-ctl` from deployment session on rhtevan-work |
