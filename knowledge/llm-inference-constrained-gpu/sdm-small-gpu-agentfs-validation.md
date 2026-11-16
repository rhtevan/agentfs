---
title: "Hosting an SDM on a 4 GB GPU — AgentFS Usability Validation"
created: 2026-11-16
tags: [sdm, systemone, decision-model, d3-mini, qwen3, llama-cpp, vllm, rtx-a500, agentfs, validation]
evidence: "rhtevan-work (RTX A500 Laptop 4 GB) vs rhel-ai Qwen3-14B-FP8 (:9000). 20-question gold suite + 185 AgentFS evaluations per side (62 skills × quality/observable/operable + readme + agents-md). 2026-11-16."
---

# Hosting an SDM on a 4 GB GPU — AgentFS Usability Validation

**Verdict:** a 4 GB GPU cannot host a structured decision model (SDM) that
AgentFS can use. Small models pass generic decision benchmarks but fail on
AgentFS evidence. Use a 14B-class self-hosted model or a managed decision API,
and **gate any candidate with `~/.agents/scripts/sdm-validate.sh`** first.

## 1. Context Requirement (per question, not per request)

SystemOne runs **each question as its own sequence** (evidence + one
question). `input_tokens` grows exactly N× with question count (1q = 2,573;
3q = 7,719), but the context window only has to fit evidence + ONE question.

| AgentFS evidence | Tokens |
|------------------|-------:|
| Largest skill (`hermes-desktop-fixes` gather-skill-state) | ~2,800 |
| readme-alignment comparison | 2,542 |
| Median skill evidence | ~450 |

- **4K minimum, 8K recommended.** 3 × 2.8K = 8,512 tokens ran fine on an 8K server.
- Risks: operable trace JSONL is `cat`-ed with no size cap; the fallback path
  (no `gather-skill-state.sh`) sends raw SKILL.md + scripts (3K–10K+ tokens).
- llama.cpp extra constraint: the whole prompt must fit in **one
  `--ubatch-size` batch** for decision GGUFs, otherwise HTTP 500
  `input (N tokens) is too large to process. increase the physical batch size`.

## 2. Results on RTX A500 (4096 MiB, ~3.7 GiB usable)

CPU offload was rejected (latency + not a dedicated SDM). Only full-GPU
candidates were tried.

| Candidate | Server | Fit | Generic suite (20q) | AgentFS agreement vs 14B | Ground truth (trace_instrumentation) |
|-----------|--------|-----|:---:|:---:|:---:|
| Qwen3-14B-FP8 (baseline, rhel-ai) | vLLM | L4 | 20/20 | — | 56/61 |
| Qwen3-1.7B-FP8 (generic) | vLLM nightly | 3,511 MiB @8K | 16/20 (confident errors) | not run | — |
| d3-mini 4B Q4_K_S (decision-only) | llama.cpp | 3,655 MiB @8K | 19/20 | **69.7%** (603/865) | **9/61** |

d3-mini per-schema agreement: quality 81.6%, readme 76.5%, agents-md 83.3%,
operable 69.3%, observable 52.0%. On evidence that literally contains
`Trace instrumentation: true`, d3-mini leaned *no* in 14/20 cases (noul 0.06–0.67)
— this is comprehension failure, not a threshold artifact. Latency was also
worse (quality 9.5 s vs 5.1 s per skill).

**Lesson:** Decision Index / generic suites do **not** predict AgentFS
usability. Validate with real AgentFS evidence and verbatim-fact ground truth.

## 3. Deployment Gotchas Found

### vLLM nightly (0.34.0rc1.dev571) on Fedora
- Needs `--security-opt label=disable`, else `Failed to infer device type` /
  `No module named 'vllm._C'` (SELinux hides the GPU from torch).
- KV-cache sizing bug: committed 0.05–0.16 GiB KV despite ~1.1 GiB free →
  `ValueError: To serve at least one request ...`. Workaround:
  `--kv-cache-memory 1288490188` (explicit bytes). Qwen3-1.7B-FP8 @8K then gets
  11,200 KV tokens.

### llama.cpp (`server-cuda`) for decision GGUFs
- `llama-server` exposes native `POST /v1/systemone` for decision GGUFs
  (vllm-d3, clef, lfm2-d1, laya, openjev, pplx-decider, granite-switch);
  `/v1/models` reports `output_modalities: ['decisions']`.
- mmproj (vision) only loads with `--mmproj` — avoids the vision-encoder OOM seen
  with vLLM (see [d3-decision-model-deployment.md](./d3-decision-model-deployment.md)).
- `vllm-d3-mini-Q4_K_M` (3.71 GB) OOMs at ub ≥ 2048; only `-c 4096 -ub 1024`
  fits, which rejects 18/62 skills (ubatch rule above).
- `prithivMLmods/d3-mini-GGUF` **Q4_K_S** (2.92 GB) fits:
  `-c 8192 -b 4096 -ub 4096 -fa on -ngl 99` → 3,655 MiB.
- Pervasive Perplexity Decider GGUFs need protocol v3; stock llama-server is v1.

### Response shape difference (fixed in `sdm-evaluate.sh`)

| Field | vLLM `/v1/systemone` | llama.cpp `/v1/systemone` |
|-------|---------------------|---------------------------|
| noul answer | `noul`, `probabilities{yes,no}`, `confidence` | **`noul` only** |
| choice | probabilities + confidence | probabilities + confidence |
| `diagnostics` (label_mass, argmax_is_label) | present | **absent** |

Before the fix, negative-polarity booleans read `.probabilities.no // 0` and
every noul-only answer became *fail* (readme-alignment 0/17). Now:
`no = 1 - noul`, `confidence = max(noul, 1-noul)`, and a warning is logged when
diagnostics are missing.

## 4. Calibration vs the 0.7 Threshold

AgentFS boolean thresholds (pass ≥ 0.7, uncertain 0.3–0.7, fail < 0.3) were
tuned on near-0/1 outputs from Qwen3-14B. Calibrated/softened decision models
(D3, Jev) drift into the *uncertain* band (score 50). Compare **ground-truth
accuracy**, not just agreement, before concluding a calibrated model is worse.

## 5. Alternatives (System One ecosystem, Nov 2026)

Decision Index 0.4 (benchlm.ai): d3 27B 67.2 · Jev 1.14 60.2 · KnowLine-4B 56.0
(SGLang FP8 custom server) · Perplexity Decider Flash 55.1 · Cloudflare clef 54.9
· d3-flash 54.3 · d3-mini 50.0 · clef-flash 44.4 · d3-nano 34.3 · generic Qwen3-4B 31.3.

| Managed API | Price | Notes |
|-------------|-------|-------|
| TypeSafe Jev | $0.042/1M in, output free | SystemOne reference |
| Microsoft-Decision-1 | Azure Foundry preview | SystemOne body, 32K ctx |
| Cloudflare Workers AI Clef / Clef-Flash | $0.038/1M | 24K ctx |
| Liquid AI d1 hosted | free tier `d1:free` | `/decisions/v1/systemone` |
| OpenAI Decisions API | $0.10/1M | own `/v1/decisions` format (adapter needed) |
| GCP Vertex AI | — | no decision model |

## 6. Validation Procedure

```bash
# candidate must pass before changing SDM_ENDPOINT
~/.agents/scripts/sdm-validate.sh --candidate http://<host>:<port> \
  [--baseline http://localhost:9000] [--sample N] [--gate 0.90]
```

- Runs the same `sdm-evaluate.sh` calls as `score-all.sh` (quality, observable
  with evidence, operable build phase) on isolated schema copies — no
  `scores.yaml` / `observations` written.
- Gates: pass/fail agreement ≥ gate, ground-truth accuracy ≥ gate (verbatim
  facts `Trace instrumentation:` and `sdm_delegation:`), zero errors.
- Exit 0 PASS · 1 FAIL · 2 unreachable · 3 usage. Writes `summary.json`.

## Related

- [context-window-agentfs-requirements.md](./context-window-agentfs-requirements.md)
- [d3-decision-model-deployment.md](./d3-decision-model-deployment.md)
- [decision-api-request-patterns.md](./decision-api-request-patterns.md)
- `~/.agents/skills/schemas/sdm-endpoint.md` — AgentFS SDM contract
