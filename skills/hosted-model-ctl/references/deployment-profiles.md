# Deployment Profiles

> All model deployments use profiles. No individual model aliases.
> One profile active per host at a time (mutual exclusion).
> Naming convention: `<model>-<context>` (e.g., `g8b-fp8-spec-128k`)

---

## Hardware

| Host | GPUs | VRAM/GPU | Bandwidth/GPU | Total Bandwidth | Memory Type |
|------|------|:---:|:---:|:---:|:---:|
| **rhtevan-work** | 1× NVIDIA RTX A500 | 4 GB | 128 GB/s | 128 GB/s | GDDR6 |
| **rhel-ai** | 4× NVIDIA L4 | 21.95 GB | 300 GB/s | 1,200 GB/s | GDDR6 |

---

## Profiles — rhtevan-work

### `g3b-16k` ✅ Default

| Setting | Value |
|---------|-------|
| **Model** | `ibm-granite/granite-3b` (Q4_K_M GGUF, version auto-detected) |
| **Runtime** | llama.cpp (`ghcr.io/ggml-org/llama.cpp:server-cuda-b9994`) |
| **Container** | `model-g3b` |
| **Port** | 10000 |
| **TP** | 1 |
| **Context** | 16,384 (16K) |
| **Quantization** | Q4_K_M (~2.1 GB) |
| **Slots** | 1 (single-user) |
| **Speed** | **37 tok/s** |
| **Quality** | ✅ Passes all 7 benchmark tests |
| **VRAM** | ~3.4 GB / 4 GB (85%) |
| **Cold start** | ~15s |

**Why default:** Best speed-to-quality ratio on this hardware. 5.7× faster
than Granite 8B on the same GPU. 16K context is the VRAM ceiling.

### `g350m-2k`

| Setting | Value |
|---------|-------|
| **Model** | `ibm-granite/granite-4.0-350m` (FP16) |
| **Runtime** | vLLM (`docker.io/vllm/vllm-openai:latest`) |
| **Container** | `model-g350m` |
| **Port** | 10000 |
| **TP** | 1 |
| **Context** | 2,048 (2K) |
| **Quantization** | FP16 (~0.7 GB) |
| **Speed** | **44 tok/s** |
| **Quality** | ❌ Cannot complete benchmark tests — too small for real tasks |
| **VRAM** | ~1.5 GB / 4 GB |
| **Cold start** | ~30s |

**When to use:** Speed-only testing, latency measurements, API integration
testing where output quality doesn't matter.

---

## Profiles — rhel-ai

### `g8b-fp8-spec-128k` ✅ Default

| Setting | Value |
|---------|-------|
| **Target model** | `ibm-granite/granite-4.1-8b-fp8` (FP8, ~8 GB) |
| **Draft model** | `ibm-granite/granite-4.1-3b-fp8` (FP8, ~3 GB) |
| **Runtime** | vLLM nightly (`docker.io/vllm/vllm-openai:nightly`) |
| **Container** | `model-granite-8b-fp8-spec` |
| **Port** | 9000 |
| **TP** | 4 (both target and draft) |
| **Context** | 131,072 (128K) |
| **Speculative decoding** | `draft_model`, 5 speculative tokens |
| **CUDA graphs** | Enabled (no `--enforce-eager`) |
| **Speed** | **58-79 tok/s** (task dependent) |
| **Quality** | ✅ Passes all 7 benchmark tests |
| **VRAM** | ~21.6 GB / 21.95 GB per GPU (93.8%) |
| **GPU compute** | 97-100% during inference |
| **Tool calling** | ✅ hermes parser |
| **Cold start** | ~5 min (includes CUDA graph compilation) |

**Why default:** Three optimizations stack multiplicatively:
1. FP8 quantization — halves weight reads
2. CUDA graphs — eliminates Python/framework overhead
3. Speculative decoding — multiple tokens verified per weight read

Achieves 58-79% of Opus 4.6 cloud speed while fully self-hosted.

### `g8b-spec-128k`

| Setting | Value |
|---------|-------|
| **Target model** | `ibm-granite/granite-4.1-8b` (BF16, ~16 GB) |
| **Draft model** | `ibm-granite/granite-4.1-3b` (BF16, ~6 GB) |
| **Runtime** | vLLM nightly |
| **Container** | `model-granite-8b-spec` |
| **Port** | 9000 |
| **TP** | 4 |
| **Context** | 131,072 (128K) |
| **Speculative decoding** | `draft_model`, 5 speculative tokens |
| **CUDA graphs** | Disabled (`--enforce-eager`) |
| **Speed** | **19-25 tok/s** |
| **Quality** | ✅ Passes all 7 benchmark tests |
| **Tool calling** | ✅ hermes parser |
| **Cold start** | ~2-3 min |

**When to use:** If FP8 quantization causes quality issues for a specific
task, or if CUDA graph compilation overhead is problematic for frequent
restarts. Same architecture, safer precision.

---

## Mutual Exclusion

All rhel-ai profiles share port 9000. Only one can be active at a time.
Deploying a new profile automatically stops and removes the current one.

```
setup.sh g8b-fp8-spec-128k   → stops any running model on port 9000
setup.sh g8b-spec-128k        → stops g8b-fp8-spec, starts g8b-spec
setup.sh g8b-fp8-spec-128k   → stops g8b-spec, restarts g8b-fp8-spec
```

rhtevan-work profiles share port 10000 with the same exclusion rule.

---

## Speed Reference

| Profile | Host | tok/s | vs Opus (~100) |
|---------|------|:---:|:---:|
| g350m-2k | rhtevan-work | 44 | 44% (no quality) |
| **g3b-16k** | rhtevan-work | **37** | 37% |
| g8b-spec-128k | rhel-ai | 19-25 | 20-25% |
| **g8b-fp8-spec-128k** | rhel-ai | **58-79** | 58-79% |

| Opus 4.6 | Cloud | ~100 | 100% |

For full benchmark details, see [benchmark-report.md](./benchmark-report.md).
