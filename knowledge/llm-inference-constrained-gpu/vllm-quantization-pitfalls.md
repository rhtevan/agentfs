---
title: vLLM Quantization Pitfalls
created: 2026-08-04
tags: [vllm, quantization, bitsandbytes, gptq, oom, tool-calling]
---

# vLLM Quantization Pitfalls

Failure modes and solutions encountered when using quantization with
vLLM on constrained GPUs.

## bitsandbytes + Explicit `--dtype` = Garbage Output

**Problem:** Combining `--quantization bitsandbytes --load-format
bitsandbytes` with an explicit `--dtype float16` produces garbled
output (e.g., `!!!!!!!!!!!!!!` or random characters).

**Root cause:** dtype conflict between bitsandbytes' internal
representation and the explicitly requested dtype.

**Fix:** Omit `--dtype` entirely — let vLLM auto-detect:

```bash
# ❌ Produces garbage
--model granite-4.0-1b --quantization bitsandbytes --dtype float16

# ✅ Works correctly
--model granite-4.0-1b --quantization bitsandbytes --load-format bitsandbytes
```

## GPTQ Models Fail on Hybrid Architectures

**Problem:** Community GPTQ quantizations (e.g., `ModelCloud/Granite-4.0-H-1B-GPTQMODEL-W4A16`)
fail during weight loading with `KeyError: 'layers.0.mamba.in_proj.g_idx'`
on hybrid architectures like `GraniteMoeHybrid`.

**Root cause:** The GPTQ quantization doesn't account for non-standard
layers (Mamba blocks in the hybrid architecture). The Marlin kernel
expects weight keys that don't exist in the quantized checkpoint.

**Fix:** Use bitsandbytes on-the-fly quantization instead of
pre-quantized GPTQ models for hybrid architectures:

```bash
# ❌ GPTQ fails on hybrid arch
--model ModelCloud/Granite-4.0-H-1B-GPTQMODEL-W4A16

# ✅ bitsandbytes works
--model ibm-granite/granite-4.0-1b --quantization bitsandbytes --load-format bitsandbytes
```

## CUDAGraph Incompatible with bitsandbytes

**Problem:** vLLM's CUDAGraph compilation fails when used with
bitsandbytes quantization.

**Fix:** Disable CUDAGraph with `--enforce-eager`:

```bash
--quantization bitsandbytes --load-format bitsandbytes --enforce-eager
```

## Tool Calling Not Enabled by Default

**Problem:** Sending a request with `tools` parameter returns:
`"auto" tool choice requires --enable-auto-tool-choice and
--tool-call-parser to be set`

**Fix:** Add tool calling flags at startup:

```bash
--enable-auto-tool-choice --tool-call-parser granite
```

The `--tool-call-parser` value must match the model family:
- Granite models: `granite`
- LLaMA models: `llama3_json`
- Mistral models: `mistral`
- Hermes models: `hermes`

## CPU Offloading Fails on Small GPUs

**Problem:** `--cpu-offload-gb N` causes OOM because vLLM loads the
full model onto the GPU first, then moves layers to CPU. If the model
doesn't fit on the GPU even momentarily, the process crashes.

**Example:** `granite-4.1-8b` (17.6 GB FP16) with `--cpu-offload-gb 14`
fails on a 4 GB GPU — tried to allocate 200 MiB with only 77 MiB free.

**Fix:** For models that don't fit on GPU, use llama.cpp instead.
llama.cpp loads to CPU first, then offloads selected layers to GPU:

```bash
# ❌ vLLM CPU offload — fails on small GPU
vllm --model granite-4.1-8b --cpu-offload-gb 14

# ✅ llama.cpp GPU offload — works
llama-server --model granite-4.1-8b.gguf --n-gpu-layers 18
```

See [vllm-vs-llamacpp-gpu-philosophy.md](./vllm-vs-llamacpp-gpu-philosophy.md)
for the full architectural comparison.

## FP16 OOM Without Quantization

**Problem:** Running `granite-4.0-1b` (1.63B params) at FP16 without
quantization uses 3.07 GiB for weights alone, leaving no room for
KV cache on a 4 GB GPU. The engine OOMs during KV cache allocation.

**Fix:** Use bitsandbytes INT4 quantization to compress weights from
~3.3 GiB to ~1.17 GiB:

```bash
# ❌ OOM — no room for KV cache
--model granite-4.0-1b --dtype float16

# ✅ Fits with room for 1.92 GiB KV cache
--model granite-4.0-1b --quantization bitsandbytes --load-format bitsandbytes
```

## Source

Derived from deploying multiple Granite models on NVIDIA RTX A500
(4 GB VRAM) with vLLM v0.26.0.
