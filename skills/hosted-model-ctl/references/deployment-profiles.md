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
| qw14b-32k | rhel-ai | 70 | 30 | 16 | 55 | **40.3** | Gap analysis | Highest quality, leaves GPU 2-3 free |
| **qw14b-40k** ✅ | rhel-ai | 60 | 51 | 20 | 27 | **42.0** | Gap analysis | Best balance — default profile |
| qw14b+d3 | rhel-ai | 70 | 30 | 16 | 27 | **38.6** | Gap analysis | Composite: gen-ai + SOTA decisions |

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

### `qw14b-32k`

| Setting | Value |
|---------|-------|
| **Target model** | `Qwen/Qwen3-14B-FP8` (FP8, ~14 GB) |
| **Draft model** | None (spec decode disabled — see qw14b-40k note) |
| **Runtime** | vLLM 0.32 nightly (`docker.io/vllm/vllm-openai:nightly`) |
| **Container** | `model-qwen3-14b-32k` |
| **Port** | 9000 |
| **TP** | 2 (GPU 0 + GPU 1 only) |
| **Context** | 32,768 (32K) |
| **Speculative decoding** | ❌ Disabled |
| **CUDA graphs** | Enabled (no `--enforce-eager`) |
| **Speed** | **30.2 tok/s** (consistent across 6 benchmark runs) |
| **Quality** | ✅ Passes all 4 test.sh tests |
| **Decision endpoints** | ✅ `/v1/decisions`, `/v1/systemone` (NextTokenStrategy) |
| **VRAM** | ~21.9 GB / 23.0 GB per GPU (95.1%) |
| **GPU subset** | `CUDA_VISIBLE_DEVICES=0,1` — leaves GPU 2+3 free |
| **Tool calling** | ✅ qwen3 parser |
| **Cold start** | ~2 min (model cached, no draft compilation) |

**Why this profile:** Same 14B model on half the GPUs (2× L4, 600 GB/s).
30.2 tok/s is usable for agentic workloads. GPU 2+3 remain free for a
parallel decision model or other workload.

**Context rationale:** 32K = estimated effective context ceiling for 14B dense
standard attention. Allocating 64K or 128K wastes VRAM on KV cache the model
can't usefully attend to.

### `qw14b-40k` ✅ Default

| Setting | Value |
|---------|-------|
| **Target model** | `Qwen/Qwen3-14B-FP8` (FP8, ~14 GB) |
| **Draft model** | None (spec decode disabled — see note below) |
| **Runtime** | vLLM 0.32 nightly (`docker.io/vllm/vllm-openai:nightly`) |
| **Container** | `model-qwen3-14b-40k` |
| **Port** | 9000 |
| **TP** | 4 (all GPUs) |
| **Context** | 40,960 (40K — model hard limit: `max_position_embeddings=40960`) |
| **Speculative decoding** | ❌ Disabled (see below) |
| **CUDA graphs** | Enabled (no `--enforce-eager`) |
| **Speed** | **51.3 tok/s** (content and thinking, consistent) |
| **Quality** | ✅ Passes all 4 test.sh tests, correct on reasoning tasks |
| **Decision endpoints** | ✅ `/v1/decisions`, `/v1/systemone` (NextTokenStrategy) |
| **VRAM** | ~21.1 GB / 23.0 GB per GPU (91.7%) |
| **Tool calling** | ✅ qwen3 parser |
| **Cold start** | ~2 min (no draft model compilation) |

> **Why spec decode was removed (2026-10-15):** vLLM 0.32's V1 engine introduces
> significant overhead for speculative decoding on L4 GPUs (sm_89). Benchmarking
> showed spec decode *reduced* throughput by 36% (32.5 vs 51.3 tok/s) due to:
> (1) scheduler throttling (`max_num_scheduled_tokens=2048` auto-cap, not fully
> fixable with `--max-num-batched-tokens`), (2) draft model TP=4 communication
> overhead on a 4B model (each GPU slice is tiny), (3) 56.7% overall acceptance
> rate with positions 3-4 below 50%. Without spec decode, the base model on
> vLLM 0.32 is actually 24% *faster* than vLLM 0.27 with spec decode (51.3 vs
> 41.2 tok/s).

**Why this profile:** Same model as qw14b-32k but with 2× the memory bandwidth
(1,200 GB/s vs 600 GB/s) and 40K context (model's `max_position_embeddings`
hard limit). Trades GPU availability (all 4 consumed) for 118% faster generation
(51.3 vs 23.5 tok/s).

**Context rationale:** 40K is the Qwen3-14B architectural limit
(`max_position_embeddings=40960` in config.json, no RoPE scaling).
The original 64K target failed at deploy time — vLLM refuses to exceed this.

### `qw14b+d3` (full name: `qw14b-fp8-32k+d3-27b-fp8-8k`)

Composite deployment profile — two containers, two ports, all 4 GPUs.

| Component | Gen-AI (qw14b-32k) | Decision (d3-27b-8k) |
|-----------|:---:|:---:|
| **Model** | `Qwen/Qwen3-14B-FP8` | `vllm-sr/d3` (Decision 3.0, 27B) |
| **Port** | 9000 | 9001 |
| **TP** | 2 (GPU 0-1) | 2 (GPU 2-3) |
| **Context** | 32K | 8K |
| **Quantization** | FP8 (model checkpoint) | FP8 (on-the-fly) |
| **CUDA graphs** | Enabled | ❌ Disabled (`--enforce-eager`) |
| **Speed** | 30.2 tok/s | ~250-470ms per decision request |
| **Decision API** | ✅ NextTokenStrategy (`/v1/decisions`) | ✅ Native (`/v1/systemone`) |
| **Decision Index** | ~45-52 (estimated, logit reading) | 66.26 (SOTA) |
| **VRAM** | 22.1 GB / 23.0 GB per GPU | 20.8 GB / 23.0 GB per GPU |
| **Cold start** | ~2 min | ~2.5 min |
| **Env vars** | — | `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` |

```
GPU 0: qw14b-32k  (22.1 GB) — gen-ai + NextToken decisions, port 9000
GPU 1: qw14b-32k  (22.1 GB) — gen-ai + NextToken decisions, port 9000
GPU 2: d3-27b-8k  (20.8 GB) — D3 SOTA decisions, port 9001
GPU 3: d3-27b-8k  (20.8 GB) — D3 SOTA decisions, port 9001
```

**Why this profile:** Combines a capable gen-ai model with the highest-accuracy
open decision model. The gen-ai side also serves decisions via NextTokenStrategy
for low-latency use cases (~170ms). The D3 side provides SOTA accuracy (66.26
Decision Index) for high-stakes decision workloads (~250-470ms). Both coexist
on the same Skupper VAN link, multiplexed by routing key.

> **Why `--enforce-eager` on D3:** The Qwen3.5 GDN architecture's vision encoder
> requires 18.4 GB for CUDA graph capture workspace — a fixed allocation that
> cannot be reduced via context, batch, or memory utilization tuning. On L4 GPUs
> (23 GB), this exceeds available VRAM after model weights (13 GB). See
> [speculative-decoding-tradeoffs.md](../../../../knowledge/llm-inference-constrained-gpu/speculative-decoding-tradeoffs.md)
> and the D3 deployment knowledge concept for full analysis.

> **Why 8K context on D3:** Reducing from 32K to 8K improved latency from ~490ms
> to ~250ms on short requests. Decision inputs rarely exceed 8K tokens. The model
> supports 262K natively (Qwen3.5 backbone).

---

## Mutual Exclusion

All rhel-ai profiles share port 9000. Only one profile can be active at a time.
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
| qw14b-32k | rhel-ai | 2× L4 | **30.2** (no spec decode) | **30%** |
| **qw14b-40k** | rhel-ai | 4× L4 | **51.3** (no spec decode) | **51%** |
| qw14b+d3 | rhel-ai | 2+2 L4 | 30.2 gen + ~300ms decisions | 30% gen |

| Opus 4.6 | Cloud | — | ~100 | 100% |

For full benchmark details, see [benchmark-report.md](./benchmark-report.md).
