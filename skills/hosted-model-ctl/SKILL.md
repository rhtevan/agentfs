---
name: hosted-model-ctl
description: >
  hosted model list, setup hosted model, start hosted model,
  stop hosted model, hosted model status, test hosted model,
  teardown hosted model, precheck hosted model
argument-hint: "hosted model list | hosted model start g350m | hosted model status g8b-128k"
compatibility: "podman, NVIDIA GPU with CDI, SSH access to remote hosts"
metadata:
  author: agentfs
  version: "5.2.0"
  tags: [granite, vllm, llama-cpp, inference, llm, podman, nvidia, gpu, model-serving, tool-calling, gguf, rhel-ai, 128k-context, hosted, self-hosted]
user-invocable: true
disable-model-invocation: false
writes-files: false
---

# Hosted Model Control

Deploy, manage, and test self-hosted IBM Granite model containers
on NVIDIA GPUs via Podman. All operations are implemented as
deterministic scripts.

## Host Profiles

| Profile | SSH Host | GPUs | Total VRAM | Model Port |
|---------|----------|------|:----------:|:----------:|
| **rhtevan-work** | `rhtevan-work` | 1× RTX A500 | 4 GB | 10000 |
| **rhel-ai** | `rhel-ai` | 4× NVIDIA L4 | 92 GB | 9000 |

## Model Registry

### rhtevan-work (port 10000)

| Alias | Model | Engine | Context |
|:-----:|-------|:------:|:-------:|
| `g350m` | granite-4.0-350m | vLLM FP16 | 2K |
| `g1b` | granite-4.0-1b | vLLM INT4 | 2K |
| `g8b` | granite-4.1-8b | llama.cpp Q4_K_M | 16K |

### rhel-ai (port 9000)

| Alias | Model | Engine | TP | Context |
|:-----:|-------|:------:|:--:|:-------:|
| `g30b-96k` | granite-4.1-30b | vLLM BF16 | 4 | 96K |
| `g8b-128k` | granite-4.1-8b | vLLM BF16 | 2 | 128K |

Defaults: `g350m` (rhtevan-work), `g8b-128k` (rhel-ai).

Full container details (images, flags, VRAM budgets) in
[references/memory-budget.md](./references/memory-budget.md).

## Container Details

| Setting | rhtevan-work (vLLM) | rhtevan-work (llama.cpp) | rhel-ai (InstructLab) |
|---------|--------------------|--------------------------|-----------------------|
| **Image** | `docker.io/vllm/vllm-openai:latest` | `ghcr.io/ggml-org/llama.cpp:server-cuda-b9994` | `registry.redhat.io/rhelai1/instructlab-nvidia-rhel9:1.5.0` |
| **Network** | `--network host` | `--network host` | `--net host` |
| **GPU** | `--device nvidia.com/gpu=all` | `--device nvidia.com/gpu=all` | `--device nvidia.com/gpu=all` |
| **Port** | 10000 | 10000 | 9000 |
| **Extra** | `--enforce-eager` | `--n-gpu-layers 18` | `--disable-custom-all-reduce --shm-size 10G` |

### rhel-ai Specifics

- **Home directory:** `/var/home/cloud-user`
- **HF cache mount:** `-v /var/home/cloud-user/.cache/huggingface:/opt/app-root/src/.cache/huggingface`
- **Entrypoint override:** `--entrypoint python3 <IMAGE> -m vllm.entrypoints.openai.api_server`
- **No `:Z`** on volume mounts (SELinux not enforcing)

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | List all model containers with status on both hosts | `scripts/list.sh` → table output |
| S2 | Pre-check host readiness (SSH, GPU, podman, CDI, images, disk) | `scripts/pre-check.sh HOST` → pass/fail report |
| S3 | Deploy model container by alias (idempotent) | `scripts/setup.sh ALIAS` → container created, API HTTP 200 |
| S4 | Start existing model container by alias (stops conflicting models on same port) | `scripts/start.sh ALIAS` → API HTTP 200 |
| S5a | Stop single model container by alias (others unaffected) | `scripts/stop.sh ALIAS` → target stopped, other models on other hosts **preserved** |
| S5b | Stop all model containers across both hosts | `scripts/stop.sh all` → all containers exited |
| S6 | Show status of specific model or all models | `scripts/status.sh [ALIAS]` → status report |
| S7 | Test running model (health, model ID, chat completion) | `scripts/test.sh ALIAS` → 4 tests pass |

## Operations

All operations are implemented as scripts in `scripts/`.
The agent runs scripts directly — no inline commands to interpret.

### 1. List

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/list.sh
```

Shows all model containers across both hosts with status icons.

### 2. Pre-Check

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/pre-check.sh rhtevan-work
bash ~/.agents/skills/hosted-model-ctl/scripts/pre-check.sh rhel-ai
```

Verifies SSH, GPU, podman, CDI, container images, HF cache, disk space.

### 3. Setup (Deploy)

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g350m
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g8b-128k
```

Idempotent: removes existing container, creates new one, waits for
API readiness. First run downloads model weights (may take 5-20 min).

### 4. Start

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/start.sh g350m
```

Starts an existing container. Automatically stops any other model
sharing the same port on the same host.

### 5. Stop

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh g350m
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh all
```

### 6. Status

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/status.sh          # all models
bash ~/.agents/skills/hosted-model-ctl/scripts/status.sh g8b-128k  # specific model + logs
```

### 7. Test

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/test.sh g350m
```

Runs 4 tests: container running, API health, model ID, chat completion.

### 8. Teardown (Remove)

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh g350m --remove    # stop + remove specific
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh all --remove      # stop + remove all
```

With `--remove`, stops and deletes the container(s). Use `setup.sh ALIAS`
to redeploy afterwards. Without `--remove`, containers are stopped but
preserved. Does NOT delete downloaded model weights from the HF cache.

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `scripts/list.sh` | Table with 5 models, status icons |
| T2 | S2 | `scripts/pre-check.sh rhtevan-work` | All checks pass |
| T3 | S3 | `scripts/setup.sh g350m` | Container created, HTTP 200 |
| T4 | S4 | `scripts/start.sh g350m` | HTTP 200, model ready |
| T5a | S5a | `scripts/stop.sh g350m` (g8b-128k running on rhel-ai) | g350m stopped, g8b-128k on rhel-ai **unaffected** |
| T5b | S5b | `scripts/stop.sh all` | All containers exited on both hosts |
| T6 | S6 | `scripts/status.sh g350m` | Status report with model details |
| T7 | S7 | `scripts/test.sh g350m` | 4/4 tests pass |
| T8 | S4 | `scripts/start.sh g8b-128k` | HTTP 200 on rhel-ai:9000 |
| T9 | S7 | `scripts/test.sh g8b-128k` | 4/4 tests pass |

## Gotchas

### Scoping Safety

- **`stop.sh ALIAS` is correctly scoped** — stops only the targeted container on its host. No shared infrastructure risk (unlike Skupper's local router which serves all routes). Each model container is independent.
- **`stop.sh all` iterates all aliases** — stops containers on both hosts. Unreachable hosts are skipped with a warning, not treated as errors.

### Fedora / rhtevan-work

- **No `nvidia-smi`** — use Python NVML script for GPU checks
- **SELinux volume mounts** — use `:Z` suffix on `-v` flags
- **Short-name resolution** — always use full image paths
- **`pasta` network** — use `--network host` to avoid port issues

### rhel-ai / InstructLab

- **HF cache path** — container uses `/opt/app-root/src/.cache/huggingface`
- **128K OOM on 30B** — max achievable is 98,304 tokens (~96K)
- **128K OOM on 8B tp=1** — needs `--tensor-parallel-size 2`
- **Custom allreduce** — `--disable-custom-all-reduce` for PCIe GPUs
- **Entrypoint** — override with `--entrypoint python3 ... -m vllm.entrypoints.openai.api_server`
- **No `:Z`** — omit SELinux relabeling on mounts

### vLLM General

- **bitsandbytes + `--dtype float16`** — omit `--dtype`, let vLLM auto-detect
- **CUDAGraph + bitsandbytes** — use `--enforce-eager`
- **Tool calling** — add `--enable-auto-tool-choice --tool-call-parser granite`

### llama.cpp

- **GPU layers** — 18 for 16K ctx, 25 for 4K ctx on 4 GB VRAM
- **GGUF download** — must be pre-downloaded
- **Image** — use `ghcr.io/ggml-org/llama.cpp:server-cuda-b9994`

### Cold Start Times

| Model | Weights | Start Time |
|-------|:-------:|:----------:|
| g350m | ~700 MB | ~30s |
| g1b | ~1.6 GB | ~2-3 min |
| g8b | ~5.3 GB | ~15s |
| g8b-128k | ~16 GB | ~3 min |
| g30b-96k | ~55 GB | ~17-20 min |

For detailed VRAM breakdowns, see
[references/memory-budget.md](./references/memory-budget.md).

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-12 | v5.2.0 — Split S5 into S5a (stop single alias, others unaffected) and S5b (stop all). Added negative assertion to T5a verifying models on other hosts are preserved. Added Scoping Safety gotcha. Prompted by skupper-model-provider v7.2.0 scoped-shutdown incident. |
| 2026-08-12 | v5.1.0 — Changed default rhel-ai model from `g30b-96k` to `g8b-128k`. Removed ambiguous bare signals (`model list/start/stop/status`); added `hosted model teardown`/`teardown hosted model` signals. Added teardown operation via `stop.sh --remove`. Clarified signal boundaries with `skupper-model-provider`. |
| 2026-08-08 | v5.0 — Complete rewrite: all operations as scripts; added Specification and Tests sections; compact tables; moved memory budgets to references/; proper heading hierarchy; applied skill-check 4 principles |
| 2026-08-08 | v4.0 — rhtevan-work port 8000→10000; consistent with Skupper listener |
| 2026-08-07 | v3.2 — rhel-ai port 8000→9000; port 8000 for Skupper |
| 2026-08-06 | v3.1 — Renamed local-model-ctl → hosted-model-ctl |
| 2026-08-06 | v3.0 — Added rhel-ai host profile, g30b-96k, g8b-128k |
| 2026-08-04 | v2.3 — Reverted g8b to 16K/18 GPU layers |
| 2026-08-04 | v2.0 — Multi-model support, llama.cpp engine |
| 2026-08-04 | v1.0 — Initial creation |
