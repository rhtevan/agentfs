# MCASC Measurement Framework

- **Type:** Convention
- **Status:** Active
- **Source:** Session analysis — quantifying MCASC principles for AgentFS

## Summary

Quantitative metrics for each MCASC principle, organized at three measurement
levels (component, integration, system). The system-level metric — Operator
Success Rate — is the ultimate measure of evolution success.

## Per-Principle Metrics

### Modularity

| Metric | Definition | Target |
|--------|-----------|--------|
| Inference Hop Count | Reasoning steps from `load_skill` to correct output without a script checkpoint | ≤2 hops between checkpoints |
| Script Coverage Ratio | % of skill action steps backed by a script vs. prose-only | ≥80% for skills with >3 steps |

### Cohesion

| Metric | Definition | Target |
|--------|-----------|--------|
| Change Scatter | Files touched per logical change (tracked via changelog) | ≤3 files per change |
| Concern Count | Distinct responsibility types in one SKILL.md (data gathering, scope resolution, semantic analysis, user interaction, file mutation) | ≤2 types per module |

### Abstraction

| Metric | Definition | Target |
|--------|-----------|--------|
| Interface Opacity | Does SKILL.md reference script internals (variable names, intermediate files) or only inputs/outputs? | No internal references |
| Operator Success Rate | % correct executions by a non-frontier model | ≥90% on 14B-class |

### Separation of Concerns

| Metric | Definition | Target |
|--------|-----------|--------|
| Accidental Complexity Ratio | % of SKILL.md lines dedicated to HOW (shell commands, file paths) vs. WHAT (decisions, judgments) | ≤20% accidental |
| Cross-Concern Dependency | Steps where correctness depends on agent reasoning across different concern types | Zero cross-concern agent reasoning |

### Coupling

| Metric | Definition | Target |
|--------|-----------|--------|
| Model Portability Score | Count of model-capability assumptions (multi-hop chains, inline code extraction, implicit scope reasoning) | ≤2 assumptions per skill |
| Skill Independence | Does modifying skill A require changes in skill B? | Zero cross-skill dependencies |

## Three Measurement Levels

### Level 1 — Per-Skill (Component)

Measured during skill creation (Post-Creation Checklist) and skill audit:
Inference Hop Count, Script Coverage, Concern Count, Accidental Complexity
Ratio, Interface Opacity, Model Portability Score.

### Level 2 — Cross-Skill (Integration)

Measured during pre-push or periodic audit:
Change Scatter, Skill Independence, Cross-Concern Dependency.

### Level 3 — System (AgentFS-wide)

Measured empirically via benchmark test suite:
Operator Success Rate, Rule adherence rate across model tiers.

## Failure Attribution

When a benchmark test fails, classify the root cause:

| Failure Pattern | Root Cause Principle |
|-----------------|---------------------|
| Agent fabricated a script | Abstraction (leaky interface) |
| Agent executed wrong scope | Cohesion (scope resolution not co-located) |
| Agent skipped a step | Modularity (too many hops without checkpoint) |
| Agent mixed data gathering with analysis | Separation of Concerns |
| Agent can't operate without frontier reasoning | Coupling (model-capability coupling) |
