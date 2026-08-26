---
name: hosted-model-ctl
description: >
  hosted model list, setup hosted model, start hosted model,
  stop hosted model, hosted model status, test hosted model,
  teardown hosted model, precheck hosted model,
  model hosting report, hosting machine report
argument-hint: "hosted model list | hosted model report | setup g8b-fp8-spec-128k | hosted model status"
compatibility: "podman, NVIDIA GPU with CDI, SSH access to remote hosts"
metadata:
  author: agentfs
  version: "7.4.0"
  tags: [granite, vllm, llama-cpp, inference, llm, podman, nvidia, gpu, model-serving, tool-calling, gguf, rhel-ai, speculative-decoding, fp8, self-hosted]
user-invocable: true
disable-model-invocation: false
writes-files: false
---

# Hosted Model Control

Deploy, manage, and test self-hosted LLM model containers
on NVIDIA GPUs via Podman. All deployments use **profiles** —
curated, VRAM-validated configurations. No individual model aliases.

## Hardware

| Host | SSH | GPUs | VRAM | Bandwidth | Port |
|------|-----|------|:----:|:---------:|:----:|
| **rhtevan-work** | `rhtevan-work` | 1× RTX A500 | 4 GB | 128 GB/s | 10000 |
| **rhel-ai** | `rhel-ai` | 4× NVIDIA L4 | 88 GB | 1,200 GB/s | 9000 |

## Deployment Profiles

One profile active per host at a time (mutual exclusion).
All profiles on the same host share a port — deploying a new profile
automatically stops the current one.

Full details in [references/deployment-profiles.md](./references/deployment-profiles.md).

### rhtevan-work (port 10000)

| Profile | Model | Engine | Context | Speed | Default |
|---------|-------|:------:|:-------:|:-----:|:-------:|
| **`g3b-16k`** | Granite 3B Q4_K_M | llama.cpp | 16K | 37 tok/s | ✅ |
| `g350m-2k` | Granite 4.0 350M FP16 | vLLM | 2K | 44 tok/s | |

### rhel-ai (port 9000)

| Profile | Model | Engine | TP | Context | Speed | Default |
|---------|-------|:------:|:--:|:-------:|:-----:|:-------:|
| **`g8b-fp8-spec-128k`** | Granite 8B FP8 + 3B FP8 draft | vLLM spec | 4 | 128K | **58-79 tok/s** | ✅ |
| `g8b-spec-128k` | Granite 8B BF16 + 3B BF16 draft | vLLM spec | 4 | 128K | 19-25 tok/s | |

### Speculative Decoding

The `g8b-spec-*` profiles use draft model speculation:
a Granite 3B model generates candidate tokens, then the 8B target
verifies them in a single forward pass — converting wasted GPU compute
into useful token verification (2-6× speedup).

- **g8b-fp8-spec-128k**: FP8 weights + CUDA graphs (**recommended**, ~70 tok/s)
- **g8b-spec-128k**: BF16 weights + `--enforce-eager` (safe fallback, ~20 tok/s)

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | List all profiles with container status | `scripts/list.sh` → table output |
| S2 | Pre-check host readiness | `scripts/pre-check.sh HOST` → pass/fail report |
| S3 | Deploy profile (idempotent) | `scripts/setup.sh PROFILE` → container created, API HTTP 200 |
| S4 | Start existing profile (mutual exclusion) | `scripts/start.sh PROFILE` → running |
| S5a | Stop profile | `scripts/stop.sh PROFILE` → stopped, state cleared |
| S5b | Stop all containers across both hosts | `scripts/stop.sh all` → all exited |
| S6 | Show status (includes active profile) | `scripts/status.sh [PROFILE]` → status report |
| S7 | Test running model | `scripts/test.sh PROFILE` → 4 tests pass |
| S8 | Generate platform report | `scripts/report.sh [HOST]` → markdown report |

## Operations

All operations are deterministic scripts in `scripts/`.
Every command takes a **profile name**, not a model alias.

### 1. List

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/list.sh
```

### 2. Pre-Check

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/pre-check.sh rhtevan-work
bash ~/.agents/skills/hosted-model-ctl/scripts/pre-check.sh rhel-ai
```

### 3. Setup (Deploy)

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g3b-16k
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g8b-fp8-spec-128k
```

Idempotent: removes existing container, creates new one, waits for
API readiness. First run downloads model weights (may take 5-20 min).

### 4. Start

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/start.sh g3b-16k
bash ~/.agents/skills/hosted-model-ctl/scripts/start.sh g8b-fp8-spec-128k
```

### 5. Stop

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh g3b-16k
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh g8b-fp8-spec-128k
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh all
```

### 6. Status

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/status.sh
bash ~/.agents/skills/hosted-model-ctl/scripts/status.sh g8b-fp8-spec-128k
```

### 7. Test

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/test.sh g8b-fp8-spec-128k
```

### 8. Report

> **Agent instruction — MANDATORY RENDERING:** Run the script, then
> copy-paste entire stdout into your response verbatim.

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/report.sh
bash ~/.agents/skills/hosted-model-ctl/scripts/report.sh rhel-ai
```

### 9. Teardown

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh g3b-16k --remove
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh all --remove
```

## Gotchas

### Speculative Decoding

- vLLM requires `draft_tensor_parallel_size` == target `tensor_parallel_size`
- CUDA graphs add ~10 GB/GPU — works with FP8 (small weights), fails with large models
- FP8 halves weight reads → ~2× faster decode
- `--enforce-eager` disables CUDA graphs (safe but slower)

### Memory Bandwidth = Token Speed

```
tok/s ≈ Total GPU Bandwidth (GB/s) ÷ Model Weights (GB) × efficiency
```

Both hosts use GDDR6 (not HBM). Memory bandwidth is the bottleneck.
Speculative decoding is the primary software lever to overcome this.

### Cold Start Times

| Profile | Weights | Start Time |
|---------|:-------:|:----------:|
| g350m-2k | ~0.7 GB | ~30s |
| g3b-16k | ~2 GB | ~15s |
| g8b-spec-128k | ~16 GB + ~6 GB draft | ~2-3 min |
| g8b-fp8-spec-128k | ~8 GB + ~3 GB draft | ~5 min (CUDA graph compilation) |

For benchmarks, see [references/benchmark-report.md](./references/benchmark-report.md).
For VRAM budgets, see [references/memory-budget.md](./references/memory-budget.md).

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
