---
name: hosted-model-ctl
description: >
  list hosted model, setup hosted model, start hosted model,
  stop hosted model, hosted model status, test hosted model,
  teardown hosted model, precheck hosted model,
  set default profile, hosted model report, hosting machine report,
  score deployment, deployment fitting, fitting guide
argument-hint: "list hosted model | hosted model status | start hosted model | set default profile on rhel-ai | score deployment"
compatibility: "podman, NVIDIA GPU with CDI, SSH access to remote hosts"
metadata:
  author: agentfs
  version: "7.17.0"
  model-tier: T3
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

### rhel-ai (port 9000; D3 sidecars 9001)

| Profile | Model | Engine | TP | Context | Port | Speed | Default |
|---------|-------|:------:|:--:|:-------:|:----:|:-----:|:-------:|
| **`d3-27b-32k`** | D3 27B Decision Model FP8 — dedicated SDM | vLLM | 4 | 32K | 9000 | 1.2-9.8 s/request | ✅ |
| `g8b-fp8-spec-128k` | Granite 4.2 8B FP8 + 3B FP8 draft | vLLM spec | 4 | 128K | 9000 | 58-79 tok/s | |
| `g8b-spec-128k` | Granite 4.2 8B BF16 + 3B BF16 draft | vLLM spec | 4 | 128K | 9000 | 19-25 tok/s | |
| `qw14b-32k` | Qwen3 14B FP8 (GPU 0-1) | vLLM | 2 | 32K | 9000 | est. 25+ tok/s | |
| `qw14b-40k` | Qwen3 14B FP8 | vLLM | 4 | 40K | 9000 | est. 50+ tok/s | |
| `d3-27b-8k` | D3 27B Decision Model FP8 (GPU 2-3) | vLLM | 2 | 8K | 9001 | 250-470 ms/decision | |
| `d3f-9b-32k` | D3-Flash 9B Decision Model FP8 (GPU 2) | vLLM | 1 | 32K | 9001 | 190-315 ms/decision | |
| `qw14b+d3` | Composite: `qw14b-32k` + `d3-27b-8k` | — | 2+2 | — | 9000+9001 | — | |

Source of truth: `DEPLOY_PROFILES` / `DEFAULT_PROFILES` in
`scripts/common.sh`. `d3-27b-32k` serves the AgentFS SDM endpoint
(`SDM_ENDPOINT`, default `http://localhost:9000` via the Skupper
listener). The 9001 profiles need skupper-model-provider's optional
decision route (`RHEL_AI_DECISION_ROUTING_KEY`/`RHEL_AI_DECISION_PORT`).

### Site Switch — `RHEL_AI_ENABLED`

hosted-model-ctl honours skupper-model-provider's switch. Resolution:
environment, then `skupper-model-provider/topology.env`, then `true`.
With `RHEL_AI_ENABLED=false`, rhel-ai is dropped from `list.sh`,
`set-default.sh --show`, `stop.sh all` and `report.sh all`; any
rhel-ai profile, `pre-check.sh rhel-ai` or `report.sh rhel-ai` exits
2 with "Host 'rhel-ai' is disabled" before any SSH. Re-enable by
setting `"true"` in `topology.env` (see skupper-model-provider).

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
| S5c | Read-only preview of setup/start/stop (Rule 7) | `--dry-run` → `DRY_RUN_RESULT=CONVERGED\|PENDING`, or `UNKNOWN` + exit 3 when the host cannot be probed |
| S6 | Show status (includes active profile) | `scripts/status.sh [PROFILE]` → status report |
| S7 | Test running model | `scripts/test.sh PROFILE` → 4 tests pass |
| S8 | Generate platform report | `scripts/report.sh [HOST]` → markdown report |
| S9 | Set default profile for a host | `scripts/set-default.sh PROFILE` → persisted, shown in list/status |
| S10 | Honour site switch `RHEL_AI_ENABLED` | `RHEL_AI_ENABLED=false` → `start.sh --dry-run d3-27b-32k` exits 2 "disabled", no SSH; `list.sh --names-only` omits rhel-ai |

## Operations

All operations are deterministic scripts in `scripts/`.
Every command takes a **profile name**, not a model alias.

### Dry-Run Contract (setup / start / stop)

`setup.sh`, `start.sh` and `stop.sh` accept `--dry-run` (Rule 7). The agent MUST
run the `--dry-run` form first and read the signal line:

| Signal | Exit | Meaning | Agent action |
|--------|:----:|---------|--------------|
| `DRY_RUN_RESULT=CONVERGED` | 0 | Verified on the host: container running, matches the profile (image, model, TP, context, port, extra flags) and `/v1/models` serves the model (stop: container already stopped/absent) | Report "already configured"; skip apply |
| `DRY_RUN_RESULT=PENDING` | 0 | Apply would change something; plan is printed | Run the same command without `--dry-run` |
| `DRY_RUN_RESULT=UNKNOWN` + `DRY_RUN_REASON=host-unreachable\|podman-error` | 3 | Host state could not be read | Stop and report. Never treat as CONVERGED |

Fail-closed: an ssh or podman failure is never reported as "not running".
The apply path aborts with exit 3 and makes no changes when the probe fails.
Unknown options or a second profile argument exit 2 (no silent ignore).

Mutual exclusion (setup/start): containers on the **same port** are stopped
(setup also removes them); containers on **overlapping GPUs** are stopped, not removed.
GPU sets come from `GPU_DEVICES` (profiles without an entry use all GPUs); an unknown
running container that serves a model is assumed to hold all GPUs. The dry-run plan
lists every conflict. Composite sub-plans are each computed from the current host state.

Exit codes: `0` ok · `1` usage/precondition · `2` bad argument · `3` probe failed.

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
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh --dry-run g3b-16k
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g3b-16k
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g8b-fp8-spec-128k
```

Idempotent: removes existing container, creates new one, waits for
API readiness. First run downloads model weights (may take 5-20 min).

### 4. Start

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/start.sh --dry-run g3b-16k
bash ~/.agents/skills/hosted-model-ctl/scripts/start.sh g3b-16k
bash ~/.agents/skills/hosted-model-ctl/scripts/start.sh g8b-fp8-spec-128k
```

### 5. Stop

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/stop.sh --dry-run g3b-16k
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

### 9. Set Default Profile

```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/set-default.sh --show
bash ~/.agents/skills/hosted-model-ctl/scripts/set-default.sh g8b-spec-128k
```

Persists the default profile for a host. The profile resolves to its
host automatically. Overrides the builtin default. Affects which
profile `start.sh` and `stop.sh` use when called without a specific
profile (e.g., from `skupper-model-provider` delegation).

### 10. Teardown

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

### Granite 4.2 Reasoning Overhead

- 4.2 models emit chain-of-thought reasoning by default (nemotron_v3 parser)
- Short responses: 70-80% of tokens are invisible reasoning
- Long generation: only 5% reasoning overhead
- Code generation requires max_tokens >= 8192 to avoid budget exhaustion
- Tool-call parser changed from `hermes` to `qwen3_coder`
- To disable thinking: set `chat_template_kwargs.enable_thinking: false`
- **rhtevan-work stays on 4.1:** llama.cpp has no reasoning parser (tags leak),
  4.2 GGUF is 145 MB larger (OOM risk on 4 GB), 3B reasoning quality is marginal

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
For deployment fitting scores, see [references/fitting-guide.md](./references/fitting-guide.md).

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
