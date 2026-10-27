# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## 2026-10-27 14:53
- Added anti-pattern: frontier model implicit assumptions — CWD assumption, misattribution, mitigation for skill-gen (knowledge/agentfs-engineering-evolution/mcacs-principles-for-agentfs.md)

## 2026-10-27 13:41
- Phase 2.5 PASS: corrected misattribution — script bug not model gap. Both scopes pass on 14B v3.0.1. (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-27 13:12
- Phase 2.5: v3.0.1 retest results — 4 runs, 1 partial pass, root cause refined to model behavioral gap (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-27 13:01
- Updated Phase 2.5 with validation results, Phase 3.1 with goose run decision (not recipe), dependency graph with current status (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-26 15:52
- Phase 0 complete: all 12 items delivered and tested (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-26 15:41
- Added item 0.12 token cost tracking (complete) to Phase 0 deliverables (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-26 15:40
- New reference concept: analysis of Red Hat AI Tokenomics article alignment with QOO architecture — direct echoes, new ideas (gateway, showback, volume multiplier), convergence insight (knowledge/agentfs-engineering-evolution/tokenomics-alignment.md)

## 2026-10-23 22:09
- Revised: Phase 0 remaining items (0.7-0.11), QOO terminology, corrected Phase 1 items, qoo-profile.yaml in Phase 2, scores.yaml persistence, updated dependency graph (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- Updated Observable Property: universal schemas, async evaluation, scores.yaml, no per-skill schemas (knowledge/agentfs-engineering-evolution/operable-skill-architecture.md)
- Revised: universal observation schema, async-only evaluation, qoo-profile.yaml, scores.yaml persistence, two-tier evidence, QOO terminology (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-22 20:20
- Updated implementation plan: Phase 0 complete with test results, learnings, bugs fixed. Phases 1-4 detailed with specific file paths, changes, and session resumption guide. (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-22 19:56
- Corrected score-type claim: NextToken also supports score questions (knowledge/llm-inference-constrained-gpu/d3-decision-model-deployment.md)

## 2026-10-22 17:42
- Added Observable Property section with observation.yaml, trace_step, two-phase evaluation, schema locations (knowledge/agentfs-engineering-evolution/operable-skill-architecture.md)
- New concept: Implementation Plan — 5-phase plan from SDM foundation through maturity (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- New concept: Observable Skill Design — agent-agnostic audit trail, two-phase observation, three schema types, score persistence (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-19 11:40
- New concept: Operable Skill Architecture — four-layer anatomy and Author/Operate/Evolve lifecycle (knowledge/agentfs-engineering-evolution/operable-skill-architecture.md)
- New concept: CECX observation schema — four traits for scoring skill executions, aligned with QSCZ deployment fitting (knowledge/agentfs-engineering-evolution/observation-schema-cecx.md)

## 2026-10-19 10:05
- Rename MCASC → MCACS (knowledge/context-engineering/cnl-authoring-for-weak-models.md)
- Rename MCASC → MCACS (knowledge/agentfs-engineering-evolution/sdm-integration-for-agentfs.md)
- Rename MCASC → MCACS (knowledge/agentfs-engineering-evolution/benchmark-test-suite.md)
- Rename MCASC → MCACS (knowledge/agentfs-engineering-evolution/operational-pattern-classification.md)
- Rename MCASC → MCACS (knowledge/agentfs-engineering-evolution/mcacs-measurement-framework.md)

## 2026-10-19 09:52
- Rename MCASC → MCACS (knowledge/agentfs-engineering-evolution/mcacs-principles-for-agentfs.md)

## 2026-10-16 20:07
- Added v7.3.7 full template rewrite results (knowledge/context-engineering/cnl-authoring-for-weak-models.md)
- Initial concept: sdm-integration-for-agentfs.md
- Initial concept: benchmark-test-suite.md
- Initial concept: operational-pattern-classification.md
- Initial concept: mcasc-measurement-framework.md
- Initial concept: mcasc-principles-for-agentfs.md

## 2026-10-15 22:58
- New concept: generation prior conflict — pretraining priors override system prompt rules (knowledge/context-engineering/generation-prior-conflict.md)
- New concept: CNL authoring rules for weak models — ASD-STE100 principles applied to agent instructions (knowledge/context-engineering/cnl-authoring-for-weak-models.md)
- New concept: assistant prefix continuation framing — empirical finding on Qwen3-14B (knowledge/context-engineering/assistant-prefix-continuation.md)

## 2026-10-15 22:57
- New concept: Goose message role mapping — how goose maps to OpenAI API roles, monolithic system prompt structure (knowledge/context-engineering/goose-message-role-mapping.md)

## 2026-10-15 19:54
- New concept: D3 decision model deployment on L4 — CUDA graph OOM, FP8 KV crash, optimization, NextToken vs SDM (knowledge/llm-inference-constrained-gpu/d3-decision-model-deployment.md)

## 2026-10-15 15:28
- New concept: speculative decoding tradeoffs — when it hurts on bandwidth-bound GPUs (L4 benchmark evidence, vLLM V1 issues) (knowledge/llm-inference-constrained-gpu/speculative-decoding-tradeoffs.md)

## 2026-10-15 10:27
- New concept: sizing rules of thumb for context and parameters (knowledge/deployment-fitting-guide/sizing-guidance.md)

## 2026-10-14 16:28
- New concept: Weighted scoring formula 0.30/0.30/0.30/0.10 with interpretation bands (knowledge/deployment-fitting-guide/weighted-scoring.md)
- New concept: Class-specific baselines - Gen AI (Opus) vs Decision (Jev) (knowledge/deployment-fitting-guide/class-baselines.md)
- New concept: 4x4 SUV positioning analogy for deployment traits (knowledge/deployment-fitting-guide/suv-model.md)
- New concept: The 4 deployment traits - Quality, Speed, Context, Size with correlations (knowledge/deployment-fitting-guide/four-traits.md)

## 2026-10-02 22:29
- New concept: confabulation-under-audit — model fabricates retroactive justifications for non-compliance. Evidence from Granite 8B canary audit. (knowledge/llm-behavioral-properties/confabulation-under-audit.md)

## 2026-09-29 21:27
- v7.2.0 — rules consolidated 10→8, severity tags removed (knowledge/context-engineering/rule-ordering-by-frequency.md)

## 2026-09-29 19:05
- New concept in context-engineering bundle (knowledge/context-engineering/rule-ordering-by-frequency.md)
- New concept in context-engineering bundle (knowledge/context-engineering/jit-reminder-recency-pattern.md)
- New concept in context-engineering bundle (knowledge/context-engineering/moim-persistent-instructions-reality.md)
- New concept in context-engineering bundle (knowledge/context-engineering/instruction-override-semantics.md)
- New concept in context-engineering bundle (knowledge/context-engineering/llm-context-layer-model.md)

## 2026-09-24 21:21

- New knowledge bundle: KGM-Based Skill Dispatch (5 concepts) (knowledge/agentfs-kgm-skill-dispatch/architecture.md)

## 2026-09-16 11:49

- Test log entry (knowledge/ocp-containerfile/base-images-ubi.md)

## 2026-09-16 11:37
- OCP Containerfile knowledge bundle (ocp-containerfile/index.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/uid-model-restricted-v2.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/uid-model-user-namespaces.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/scc-and-security-context.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/file-permissions-gid0.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/base-images-ubi.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/image-metadata-labels.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/layer-optimization.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/runtime-constraints.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/certification-requirements.md)
- OCP Containerfile knowledge bundle (ocp-containerfile/s2i-compatibility.md)

## 2026-09-10 21:32

- Added Pre-Flight Checklist as primary mitigation; restructured effectiveness section with preventive/detective/corrective layers

## 2026-09-10 18:05

- Created llm-behavioral-properties bundle: 5 concepts (sycophancy, multi-turn-discipline-decay, partial-completion, improvised-recovery, hallucinated-confidence). OKF v0.1 conformant.

## 2026-08-26 12:14

- Created knowledge bundle goose-desktop-operations with 2 concept documents (toolshim-and-tool-calls.md, custom-provider-schema.md). Moved GOOSE_TOOLSHIM incident from skupper-vllm-deployment/agentfs-process-lessons.md to new bundle. Updated root index.md.

## 2026-08-08 12:19

- Created OKF knowledge bundle `skupper-vllm-deployment` with 5 concept documents (postmortem)
- Added bundle entry to `index.md`

## 2026-08-04 15:58

- Created knowledge bundle `llm-inference-constrained-gpu` with 6 concept documents
- `vllm-vs-llamacpp-gpu-philosophy.md` — GPU-first vs CPU-first inference architecture
- `containerized-inference-pattern.md` — Reusable pattern for GPU-accelerated container serving
- `gpu-layer-tuning-methodology.md` — Systematic tuning of llama.cpp GPU layers on limited VRAM
- `context-window-agentfs-requirements.md` — Minimum context window for AgentFS compatibility
- `fedora-nvidia-container-gotchas.md` — Fedora RPMFusion + Podman + NVIDIA pitfalls
- `vllm-quantization-pitfalls.md` — vLLM quantization failure modes and solutions
- Updated `~/.agents/knowledge/index.md` with new bundle entry

## 2026-07-22 19:06

- **Update**: Merged new knowledge into `skupper-v2-concepts/` — 6 created, 3 indexes updated. New sub-bundles: migration/, platform-details/.

## 2026-07-22 15:41

- **Update**: Merged new knowledge into `skupper-v2-concepts/` — 0 created, 2 updated (application-tls.md, router-access.md).
- **Update**: Updated security/index.md descriptions.

## 2026-07-20 17:24

- **Creation**: Added session sub-bundle `skupper-v2-concepts/` with 11 concept documents across 4 sub-bundles (core-concepts, security, advanced-features, operations).
- **Update**: Updated root index.md with new entry.

## 2026-07-09 02:02

- **Update**: Audited index.md files — root index.md updated with 4 missing sub-bundle entries (agentfs-claude-compat, headroom-openai-compression-analysis, rca-labeled-dataset, telecom-gnn-rca)

## 2026-07-08 09:57

- **Distill**: Rewrote `agentfs-claude-compat/claude-compat-analysis.md` — extracted cross-agent compatibility matrix and bridging patterns from 330-line session notes (now 112 lines)
- **Distill**: Rewrote `headroom-openai-compression-analysis/problem-analysis.md` — generalized to reusable concept about OpenAI endpoint format blocking proxy compression (85→57 lines)
- **Distill**: Rewrote `headroom-openai-compression-analysis/configuration-history.md` — replaced raw systemd config changelog with flag reference table (124→51 lines)
- **Distill**: Rewrote `headroom-openai-compression-analysis/options-assessment.md` — converted from open options list to decided architecture record with reusable decision framework (135→58 lines)
- **Update**: Updated `headroom-openai-compression-analysis/index.md` with distilled titles and descriptions

## 2026-07-08 09:45

- **Reorganize**: Moved root-level `claude-compat-analysis.md` into new sub-bundle `agentfs-claude-compat/` — bundle root must contain only infrastructure files and sub-bundle directories
- **Update**: Rebuilt root `index.md` with corrected sub-bundle entry

## 2026-07-08 09:23

- **Merge**: Copied root-level concept `claude-compat-analysis.md` from `app/playground/goofing-around`.
- **Update**: Updated root index.md with new entry for claude-compat-analysis.

## 2026-07-08 08:54

- Created knowledge bundle `headroom-openai-compression-analysis` with 3 concept documents: problem-analysis, configuration-history, options-assessment
- Updated `index.md` with new bundle entry

## 2026-06-25
- **Merge**: Copied bundle `rca-labeled-dataset/` from `app/playground/`.
- **Update**: Updated root index.md with new entry for rca-labeled-dataset.
- **Merge**: Copied bundle `telecom-gnn-rca/` from `app/playground/`.
- **Update**: Updated root index.md with new entry for telecom-gnn-rca.
- **Initialization**: Created OKF knowledge bundle structure.
