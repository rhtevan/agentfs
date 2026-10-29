# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## 2026-10-29 17:01
- QOO tidy-up E1: update Responsibility Matrix — AGENTS.md build-time includes Quality adapted + Operable BMBT (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-29 17:00
- QOO tidy-up B4: rename observation-schema-cecx.md → operable-runtime-cecx.md, update title and summary — CECX is runtime half of Operable axis

## 2026-10-29 16:59
- QOO tidy-up B3b: fix scores.yaml comment — adapted Quality + Operable (knowledge/agentfs-engineering-evolution/artifact-qoo-separation.md)
- QOO tidy-up B3a: fix QOO properties row — adapted schemas, Observable N/A (knowledge/agentfs-engineering-evolution/artifact-qoo-separation.md)
- QOO tidy-up B2b: rewrite AGENTS.md section — adapted schemas, BMBT applicable, quality N/A explained, scores history updated, fix Observable relationship (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-29 16:58
- QOO tidy-up B2a: update Three Universal Schemas table — Observable 4 dims, Operable BMBT+CECX (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-29 16:57
- QOO tidy-up B1: rewrite Observable Property section — Observable is sibling axis not property of Operable, add three-axis table, list 4 Observable dims (knowledge/agentfs-engineering-evolution/operable-skill-architecture.md)

## 2026-10-29 15:16
- Run 4 results: v7.6.0 Self-Contained Actions — frontier 100%, target 93% (knowledge/agentfs-engineering-evolution/benchmark-results.md)
- Add Tool Disambiguation Failure section — KGM vs filesystem routing on 14B (knowledge/llm-behavioral-properties/over-tooling.md)

## 2026-10-29 15:15
- New concept: Rule Trigger Classification — guard, inline constraint, effect taxonomy (knowledge/context-engineering/rule-trigger-classification.md)

## 2026-10-29 15:14
- New concept: No Forward Chaining — LLMs cannot re-evaluate rules after state changes (knowledge/llm-behavioral-properties/no-forward-chaining.md)

## 2026-10-28 21:46
- Mark Phase 5 dependency graph as COMPLETE — all 5.1-5.6 items done (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- Update success criteria table with Phase 5 scores (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- Mark Phase 5 status as COMPLETE (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-28 21:45
- Add AGENTS.md Non-Observable section with QOO model, responsibility matrix, and first baseline scores (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-28 21:40
- Add first baseline benchmark results (frontier 83%, target 76%, SDM operable 70.8) (knowledge/agentfs-engineering-evolution/artifact-qoo-separation.md)

## 2026-10-28 21:00
- Updated QOO properties row: AGENTS.md = Quality + Operable (Observable N/A) (knowledge/agentfs-engineering-evolution/artifact-qoo-separation.md)
- Removed baseline.yaml from directory structure and semantics, updated QOO property mapping (knowledge/agentfs-engineering-evolution/artifact-qoo-separation.md)
- Updated dependency graph and success criteria for Phase 5 (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-28 20:59
- Phase 5 AGENTS.md QOO plan added, Phase 4 updated (skill-eval re-engineering replaces skill-evolve), stale observations/index.json fixed (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-27 23:49
- implicit_assumptions: qoo-profile.yaml→SKILL.md specification tables (knowledge/agentfs-engineering-evolution/mcacs-principles-for-agentfs.md)
- Eliminated qoo-profile.yaml section, replaced with scores.yaml pipeline, updated eval phase table (knowledge/agentfs-engineering-evolution/observable-skill-design.md)
- QOO-qualified marker: qoo-profile.yaml→scores.yaml (knowledge/agentfs-engineering-evolution/benchmark-test-suite.md)
- Eliminated all qoo-profile.yaml references, updated to scores.yaml pipeline (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- Eliminated qoo-profile.yaml from directory structure and semantics (knowledge/agentfs-engineering-evolution/artifact-qoo-separation.md)

## 2026-10-27 23:45
- Schema rename: 8 references updated — operable→observable, observation→operable (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- Schema rename: operable→observable, observation→operable in tables, examples, cross-refs (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-27 22:05
- v6: full rule coverage results — R1,R2 solved, R3 0% both models, R4 60%, R7 40% (knowledge/agentfs-engineering-evolution/benchmark-results.md)

## 2026-10-27 21:36
- v5 clean suite (QOO-only): T3+T9 skill operability 90%, T1 100%, overall 93% (knowledge/agentfs-engineering-evolution/benchmark-results.md)

## 2026-10-27 21:29
- Removed T2,T5 from suite — not QOO-qualified. Suite is now T1+T3+T9 only. (knowledge/agentfs-engineering-evolution/benchmark-test-suite.md)

## 2026-10-27 21:23
- v4 results: EP4+EP5+EP7 no regression on frontier, 14B stochastic variance confirms T2 needs QOO conversion (knowledge/agentfs-engineering-evolution/benchmark-results.md)

## 2026-10-27 20:57
- Removed hardcoded CWD path (knowledge/agentfs-engineering-evolution/benchmark-results.md)
- Removed hardcoded CWD path (knowledge/agentfs-engineering-evolution/benchmark-test-suite.md)

## 2026-10-27 20:42
- Phase 3 COMPLETE: 100% skill operability achieved via QOO + R1 CNL fix (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- v3 results: skill operability 100% (20/20). Evolution journey from 40%→100% documented. (knowledge/agentfs-engineering-evolution/benchmark-results.md)

## 2026-10-27 19:26
- New: artifact QOO separation pattern — sub-artifact directory for independently-consumed outputs like AGENTS.md (knowledge/agentfs-engineering-evolution/artifact-qoo-separation.md)

## 2026-10-27 17:59
- Added principle 6: test targets must be QOO-qualified. Empirical evidence from crc-status 40%→80%. (knowledge/agentfs-engineering-evolution/benchmark-test-suite.md)
- Phase 3 updated: 85% after crc-status QOO conversion (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- T3 before/after: 40%→80% after QOO conversion. Skill operability 75%→85%. (knowledge/agentfs-engineering-evolution/benchmark-results.md)

## 2026-10-27 17:47
- Phase 3.3 updated: v2 harness 75% skill operability, 5 failure mode taxonomy (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- v2 results appended: 75% skill operability, 5 failure modes with MCACS attribution (knowledge/agentfs-engineering-evolution/benchmark-results.md)

## 2026-10-27 17:25
- v2 rewrite: KGM pre-flight gate, registered signal phrases, frontier-once protocol, T9 added, T2 prompt fixed, empirical results log (knowledge/agentfs-engineering-evolution/benchmark-test-suite.md)

## 2026-10-27 17:11
- Corrected: 2-round combined results — frontier 100%, 14B 79% (below 90%). Two failure modes identified. (knowledge/agentfs-engineering-evolution/benchmark-results.md)
- Phase 3.3 corrected: 79% not 91%. Two failure modes: T1 context loading (50%), T3 skill bypass (67%). (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-27 16:29
- New: stochastic benchmark results — frontier 12/12, 14B 11/12, per-pattern analysis (knowledge/agentfs-engineering-evolution/benchmark-results.md)
- Phase 3.1-3.3 results: frontier 100%, 14B 91%, benchmark harness complete (knowledge/agentfs-engineering-evolution/implementation-plan.md)

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
