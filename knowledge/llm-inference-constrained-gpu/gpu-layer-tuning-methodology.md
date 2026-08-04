---
title: GPU Layer Tuning Methodology for llama.cpp
created: 2026-08-04
tags: [llama-cpp, gpu, vram, tuning, optimization]
---

# GPU Layer Tuning Methodology for llama.cpp

How to find the optimal `--n-gpu-layers` setting for llama.cpp when
working with limited GPU VRAM. More layers on GPU = faster inference,
but exceeding VRAM causes OOM.

## The Tradeoff

GPU VRAM is shared between:
1. **Model layers** — each offloaded layer consumes VRAM
2. **KV cache** — grows with context size (`--ctx-size`)
3. **Desktop compositor** — ~0.3 GB on a laptop with active display

Larger context windows require more KV cache, leaving fewer layers
for GPU offload.

## Tuning Procedure

1. **Start high** — set `--n-gpu-layers 999` (all layers)
2. **If OOM** — reduce by 5, retry
3. **If runs** — increase by 2-3, retry
4. **Converge** — find the maximum that starts reliably
5. **Benchmark** — run a standard prompt and record tok/s
6. **Document** — create a tuning table per context size

## Automated Benchmark Script

```bash
for NGL in 0 5 10 15 20 25 28; do
  echo "=== --n-gpu-layers $NGL ==="
  # Deploy, wait, test, capture speed
  podman rm -f model-test 2>/dev/null
  podman run -d --name model-test \
    --device nvidia.com/gpu=all \
    --security-opt=label=disable \
    --network host \
    -v ~/.cache/huggingface/gguf:/models:Z \
    <llama-cpp-image> \
    --model /models/<model>.gguf \
    --host 0.0.0.0 --port 8000 \
    --ctx-size <CTX> --threads <CORES> \
    --n-gpu-layers $NGL
  sleep 15
  # Check if running, send test prompt, record timings
done
```

## Example Results (granite-4.1-8b Q4_K_M, RTX A500 4 GB)

### Context 4,096

| GPU Layers | Prompt (tok/s) | Generation (tok/s) | Status |
|:----------:|:--------------:|:------------------:|:------:|
| 0 | 31.5 | 6.6 | ✅ |
| 5 | 32.9 | 6.9 | ✅ |
| 10 | 35.8 | 7.3 | ✅ |
| 15 | 41.5 | 7.1 | ✅ |
| 20 | 45.4 | 9.2 | ✅ |
| 22 | 51.8 | 9.7 | ✅ |
| **25** | **53.9** | **10.8** | ✅ **Optimal** |
| 28 | — | — | ❌ OOM |

### Context 16,384

| GPU Layers | Prompt (tok/s) | Generation (tok/s) | Status |
|:----------:|:--------------:|:------------------:|:------:|
| 15 | 41.8 | 8.5 | ✅ |
| **18** | **44.6** | **8.3** | ✅ **Optimal** |
| 20 | — | — | ❌ OOM |

## Key Observations

- **0 → optimal layers** gives ~64% generation speed improvement
- **Diminishing returns** at low layer counts (0→5 is small; 20→25 is large)
- **Context size inversely correlates** with max GPU layers
- **Generation speed matters most** — that's the interactive "typing" speed
- **~5+ tok/s** feels interactive; below ~2 tok/s feels painfully slow

## Source

Derived from systematic tuning of `granite-4.1-8b` Q4_K_M on NVIDIA
RTX A500 Laptop GPU (4 GB VRAM), i7-1370P (14 cores), 64 GB RAM.
