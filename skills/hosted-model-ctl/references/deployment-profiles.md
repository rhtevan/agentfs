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

## Fitting Scores

All profiles scored against the [Deployment Fitting Guide](../../../knowledge/deployment-fitting-guide/)
framework. Score = (Q × 0.30) + (S × 0.30) + (C × 0.30) + (Z × 0.10),
where Q=Quality, S=Speed, C=Context, Z=Size. Cloud baseline (Opus) = 100.

| Profile | Host | Q | S | C | Z | **Score** | Band | Key Trade-off |
|---------|------|:-:|:-:|:-:|:-:|:---------:|------|---------------|
| g350m-2k | rhtevan-work | 5 | 44 | 1 | 100 | **25.0** | Gap analysis | Too small for real tasks |
| g3b-16k | rhtevan-work | 30 | 37 | 7 | 100 | **32.2** | Gap analysis | Basic tasks only, fastest cold start |
| g8b-spec-128k | rhel-ai | 60 | 22 | 12 | 14 | **29.9** | Gap analysis | No FP8/CUDA graphs — use fp8 variant |
| g8b-fp8-spec-128k | rhel-ai | 60 | 50 | 12 | 27 | **39.3** | Gap analysis | Best speed, but 8B context degrades past 16-32K |
| qw14b-32k | rhel-ai | 70 | 24 | 16 | 55 | **38.0** | Gap analysis | Highest quality, leaves GPU 2-3 free |
| **qw14b-40k** ✅ | rhel-ai | 60 | 41 | 20 | 27 | **39.0** | Gap analysis | Best balance — default profile |

> **Reading the table:** All self-hosted profiles score in the "Gap analysis"
> band (25–50) by design — the cloud baseline (Opus at 200K context, ~100 tok/s)
> is intentionally out of reach. The value of self-hosting is sovereignty,
> offline capability, and cost — none of which the fitting score captures.
> Compare profiles *against each other*, not against 100.

For full score breakdowns, see [fitting-guide.md](./fitting-guide.md).
For benchmark data, see [benchmark-report.md](./benchmark-report.md).

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

**Why NOT Granite 4.2:** Deliberately kept on 4.1. Three reasons:
1. llama.cpp has no `--reasoning-parser` — 4.2 thinking tags leak into content
2. 4.2 GGUF is 145 MB larger → headroom drops to 0.14 GiB (OOM risk)
3. 3B model reasoning quality is marginal — not worth the latency cost

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

### `g8b-fp8-spec-128k`

| Setting | Value |
|---------|-------|
| **Target model** | `ibm-granite/granite-4.2-8b-fp8` (FP8, ~8 GB) |
| **Draft model** | `ibm-granite/granite-4.2-3b-fp8` (FP8, ~3 GB) |
| **Runtime** | vLLM nightly (`docker.io/vllm/vllm-openai:nightly`) |
| **Container** | `model-granite-8b-fp8-spec` |
| **Port** | 9000 |
| **TP** | 4 (both target and draft) |
| **Context** | 131,072 (128K) |
| **Speculative decoding** | `draft_model`, 5 speculative tokens |
| **CUDA graphs** | Enabled (no `--enforce-eager`) |
| **Speed** | **~50 tok/s total, ~47 tok/s content** (long gen); short responses have higher reasoning overhead |
| **Quality** | ✅ Passes all 7 benchmark tests |
| **VRAM** | ~21.6 GB / 21.95 GB per GPU (93.8%) |
| **GPU compute** | 97-100% during inference |
| **Tool calling** | ✅ qwen3_coder parser |
| **Reasoning parser** | nemotron_v3 (built-in chain-of-thought) |
| **Cold start** | ~5 min (includes CUDA graph compilation) |

**Why this profile:** Three optimizations stack multiplicatively:
1. FP8 quantization — halves weight reads
2. CUDA graphs — eliminates Python/framework overhead
3. Speculative decoding — multiple tokens verified per weight read

Granite 4.2 adds built-in reasoning. Quality is superior on complex
tasks (multi-step reasoning, code gen). Trade-off: short responses
have 70-80% reasoning overhead; long generation only 5%.
Requires max_tokens >= 8192 for code generation to avoid budget exhaustion.

### `g8b-spec-128k`

| Setting | Value |
|---------|-------|
| **Target model** | `ibm-granite/granite-4.2-8b` (BF16, ~16 GB) |
| **Draft model** | `ibm-granite/granite-4.2-3b` (BF16, ~6 GB) |
| **Runtime** | vLLM nightly |
| **Container** | `model-granite-8b-spec` |
| **Port** | 9000 |
| **TP** | 4 |
| **Context** | 131,072 (128K) |
| **Speculative decoding** | `draft_model`, 5 speculative tokens |
| **CUDA graphs** | Disabled (`--enforce-eager`) |
| **Speed** | **19-25 tok/s** |
| **Quality** | ✅ Passes all 7 benchmark tests |
| **Tool calling** | ✅ qwen3_coder parser |
| **Reasoning parser** | nemotron_v3 |
| **Cold start** | ~2-3 min |

**When to use:** If FP8 quantization causes quality issues for a specific
task, or if CUDA graph compilation overhead is problematic for frequent
restarts. Same architecture, safer precision.

### `qw14b-32k` (full name: `qw14b-fp8-spec-32k`)

| Setting | Value |
|---------|-------|
| **Target model** | `Qwen/Qwen3-14B-FP8` (FP8, ~14 GB) |
| **Draft model** | `Qwen/Qwen3-4B-FP8` (FP8, ~4 GB) |
| **Runtime** | vLLM nightly (`docker.io/vllm/vllm-openai:nightly`) |
| **Container** | `model-qwen3-14b-32k` |
| **Port** | 9000 |
| **TP** | 2 (GPU 0 + GPU 1 only) |
| **Context** | 32,768 (32K) |
| **Speculative decoding** | `draft_model`, 5 speculative tokens |
| **CUDA graphs** | Enabled (no `--enforce-eager`) |
| **Speed** | **est. 25-35 tok/s** (pending benchmark) |
| **Quality** | Pending benchmark |
| **VRAM** | est. ~30 GB / 44 GB (2× L4, 68%) |
| **GPU subset** | `CUDA_VISIBLE_DEVICES=0,1` — leaves GPU 2+3 free |
| **Tool calling** | ✅ qwen3 parser |
| **Cold start** | est. ~10 min (first-run model download + CUDA graph compilation) |

**Why this profile:** Tests whether a 14B model with speculative decoding on
2× L4 delivers usable quality+speed. If viable, GPU 2+3 become available for
a parallel Decision model deployment (different port, concurrent operation).

**Context rationale:** 32K = estimated effective context ceiling for 14B dense
standard attention. Allocating 64K or 128K wastes VRAM on KV cache the model
can't usefully attend to.

### `qw14b-40k` (full name: `qw14b-fp8-spec-40k`) ✅ Default

| Setting | Value |
|---------|-------|
| **Target model** | `Qwen/Qwen3-14B-FP8` (FP8, ~14 GB) |
| **Draft model** | `Qwen/Qwen3-4B-FP8` (FP8, ~4 GB) |
| **Runtime** | vLLM nightly (`docker.io/vllm/vllm-openai:nightly`) |
| **Container** | `model-qwen3-14b-40k` |
| **Port** | 9000 |
| **TP** | 4 (all GPUs) |
| **Context** | 40,960 (40K — model hard limit: `max_position_embeddings=40960`) |
| **Speculative decoding** | `draft_model`, 5 speculative tokens |
| **CUDA graphs** | Enabled (no `--enforce-eager`) |
| **Speed** | **57.8 total / 41.2 content tok/s** |
| **Quality** | ✅ Passes all 7 benchmark tests |
| **VRAM** | ~21.5 GB / 23.0 GB per GPU (93.4%) |
| **Tool calling** | ✅ qwen3 parser |
| **Cold start** | ~3.5 min (CUDA graph compilation, model cached) |

**Why this profile:** Same model as qw14b-32k but with 2× the memory bandwidth
(1,200 GB/s vs 600 GB/s) and 40K context (model's `max_position_embeddings`
hard limit). Trades GPU availability (all 4 consumed) for 75% faster content
generation (41 vs 23.5 tok/s).

**Context rationale:** 40K is the Qwen3-14B architectural limit
(`max_position_embeddings=40960` in config.json, no RoPE scaling).
The original 64K target failed at deploy time — vLLM refuses to exceed this.

---

## Mutual Exclusion

All rhel-ai profiles share port 9000. Only one LLM profile can be active at a time.
Deploying a new profile automatically stops and removes the current one.

```
setup.sh g8b-fp8-spec-128k   → stops any running model on port 9000
setup.sh g8b-spec-128k        → stops g8b-fp8-spec, starts g8b-spec
setup.sh qw14b-32k            → stops g8b-spec, starts qw14b-32k (GPU 0-1 only)
setup.sh qw14b-40k            → stops qw14b-32k, starts qw14b-40k (all GPUs)
```

**GPU subset profiles:** `qw14b-32k` uses only GPU 0+1 via `CUDA_VISIBLE_DEVICES=0,1`.
GPU 2+3 remain free for a future Decision model deployment on a separate port
(parallel operation — not mutual exclusion with the LLM profile).

rhtevan-work profiles share port 10000 with the same exclusion rule.

---

## Speed Reference

| Profile | Host | GPUs | tok/s | vs Opus (~100) |
|---------|------|:---:|:---:|:---:|
| g350m-2k | rhtevan-work | 1× A500 | 44 | 44% (no quality) |
| **g3b-16k** | rhtevan-work | 1× A500 | **37** | 37% |
| g8b-spec-128k | rhel-ai | 4× L4 | 19-25 | 20-25% |
| **g8b-fp8-spec-128k** | rhel-ai | 4× L4 | **~50 total (~47 content)** | ~47% |
| qw14b-32k | rhel-ai | 2× L4 | 36.4 total (23.5 content) | 24% |
| **qw14b-40k** | rhel-ai | 4× L4 | **57.8 total (41.2 content)** | **41%** |

| Opus 4.6 | Cloud | — | ~100 | 100% |

For full benchmark details, see [benchmark-report.md](./benchmark-report.md).
