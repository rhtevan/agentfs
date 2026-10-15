---
title: "Speculative Decoding: When It Hurts More Than It Helps"
created: 2026-10-15
tags: [speculative-decoding, vllm, gpu, l4, performance, bandwidth]
evidence: "Benchmarked on 4×L4 (Ada sm_89, 23 GB each). vLLM 0.32.0rc1, Qwen3-14B-FP8 target, Qwen3-4B-FP8 draft, TP=4, draft_tp=4, num_speculative_tokens=5."
---

# Speculative Decoding: When It Hurts More Than It Helps

Speculative decoding is widely recommended for accelerating LLM inference.
The premise: a small draft model proposes N tokens cheaply, the target model
verifies them in a single forward pass, and accepted tokens represent "free"
generation. In practice, the benefit depends entirely on the GPU's
compute-to-bandwidth ratio. On bandwidth-constrained GPUs, speculative
decoding can **reduce** throughput significantly.

## The Evidence

Benchmarked on rhel-ai (4× NVIDIA L4, 23 GB each, PCIe Gen4):

| Configuration | Engine | tok/s | Delta |
|---------------|--------|:-----:|:-----:|
| vLLM 0.27 + spec decode (Qwen3-4B draft) | V0 | 41.2 | baseline |
| vLLM 0.32 + spec decode (Qwen3-4B draft) | V1 | 32.5 | **-21%** |
| vLLM 0.32 + spec decode + `--max-num-batched-tokens 8192` | V1 | 32.5 | -21% (no improvement) |
| **vLLM 0.32, no spec decode** | **V1** | **51.3** | **+24%** |

Removing speculative decoding made the model **24% faster** than the
previous best (which used spec decode). The V1 engine's base model
performance improved over V0, but spec decode overhead more than
negated the gain.

### Spec Decode Acceptance Rate (vLLM 0.32)

| Position | Accepted / Drafted | Rate |
|:--------:|:-:|:-:|
| 0 | 2001 / 2522 | 79.3% |
| 1 | 1642 / 2522 | 65.1% |
| 2 | 1386 / 2522 | 55.0% |
| 3 | 1143 / 2522 | 45.3% |
| 4 | 973 / 2522 | 38.6% |
| **Overall** | **7145 / 12610** | **56.7%** |

Average 2.83 tokens accepted per draft cycle. Positions 3-4 waste
more compute than they save.

## Why Spec Decode Fails on Bandwidth-Bound GPUs

Speculative decoding is fundamentally a **compute-for-bandwidth trade**.
It works when you have excess compute capacity to burn on draft+verify
cycles and the verification step is genuinely cheaper than sequential
generation.

Three conditions must hold for spec decode to help:

### 1. Excess Compute Headroom

During autoregressive decode, the GPU reads all model weights from HBM
for each token. On bandwidth-constrained GPUs (L4: 300 GB/s per card),
the compute units are mostly idle — waiting for data, not doing math.
There's no "excess compute" to donate to a draft model.

On compute-rich GPUs (H100: 3.35 TB/s HBM3, plus NVLink), the
arithmetic units have spare cycles between memory fetches —
speculative drafting uses those spare cycles productively.

### 2. Cheap Verification

The theory says "verify N draft tokens in one forward pass = same
cost as 1 token." This is approximately true for single-GPU setups.
With TP=4 over PCIe, each forward pass incurs NCCL all-reduce
synchronization across all 4 GPUs. The verification pass pays the
same communication overhead as N sequential tokens — the "parallel
verify" advantage shrinks.

### 3. Draft Model Doesn't Compete for Bandwidth

The draft model (4B FP8) loads its own weights from HBM during each
draft step. On a shared TP=4 setup, this competes with the target
model for the same memory bus. The draft model's weight reads are
pure overhead — they don't displace target model reads, they add
to the total bandwidth demand.

With a **dedicated draft GPU** (or CPU-based drafting), this
competition disappears. But on L4s where VRAM is tight (23 GB),
there's no spare GPU to dedicate.

## The Generalized Rule

| GPU Class | Compute:BW Ratio | Interconnect | Native FP8 | Spec Decode Value |
|-----------|:-:|:-:|:-:|:-:|
| H100/H200 (Hopper) | High | NVLink | ✅ | ✅ High — excess compute to burn |
| A100 (Ampere) | Moderate | NVLink/PCIe | ❌ | ⚠️ Depends on model size and TP |
| L4/L40/A10 (Ada) | Low | PCIe only | ❌ | ❌ Overhead exceeds gain |
| Consumer (RTX 4090) | Moderate | Single GPU | ❌ | ⚠️ Can help at TP=1 (no all-reduce) |

### Decision Heuristic

Before enabling speculative decoding, check:

1. **Is decode bandwidth-bound?** Run without spec decode first.
   If GPU utilization during decode is <50%, you have compute headroom
   → spec decode may help.
2. **Is TP > 1?** Each additional TP rank adds all-reduce overhead
   to both draft and verify passes. TP≥4 on PCIe almost always
   makes spec decode net-negative.
3. **Does the GPU have native FP8?** Marlin weight-only FP8 (Ada/Ampere)
   means the draft model pays a dequant penalty. Native FP8 (Hopper+)
   means the draft model is genuinely cheap.
4. **Can the draft run on a separate device?** CPU drafting or a
   dedicated small GPU avoids bandwidth competition entirely.

## vLLM 0.32-Specific Issues

The V1 engine in vLLM 0.32 introduces additional spec decode overhead:

- **Scheduler auto-cap:** `max_num_scheduled_tokens` is automatically
  reduced to 2048 when spec decode is active. Increasing
  `--max-num-batched-tokens` changes the compile range but does not
  fully recover throughput.
- **CUDA graph interaction:** The decode pipeline's
  `compile_ranges_endpoints` is capped at the batched tokens value,
  limiting graph optimization scope.
- **V0→V1 migration:** The V0 engine (vLLM ≤0.27) handled spec decode
  differently — the same spec config that was net-positive on V0 can
  be net-negative on V1.

**Recommendation:** When upgrading vLLM, always re-benchmark with and
without spec decode. Do not assume prior spec decode gains carry over.

## Practical Impact

For our deployment (Qwen3-14B-FP8 on 4×L4):

| Metric | With Spec Decode | Without | Impact |
|--------|:---:|:---:|:---:|
| Content tok/s | 32.5 | 51.3 | **+58% faster** |
| TTFT | ~250ms | ~150ms | Faster (no draft warmup) |
| VRAM used | ~21.5 GB/GPU | ~21.1 GB/GPU | ~400 MB freed per GPU |
| Cold start | ~3.5 min | ~2 min | No draft compilation |
| Complexity | Draft model config, acceptance tuning | None | Simpler |

The 51.3 tok/s without spec decode represents efficient saturation of
the available memory bandwidth. There is no further optimization
available at the serving layer — the next speed improvement requires
either faster GPUs (more HBM bandwidth) or a smaller model.
