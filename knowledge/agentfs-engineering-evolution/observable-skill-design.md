---
title: Observable Skill Design
parent: agentfs-engineering-evolution
created: 2026-10-22
tags: [observable-skill, SDM, evaluation, trace, schemas, architecture]
---

# Observable Skill Design

- **Type:** Pattern
- **Status:** Active
- **Source:** Session analysis — designing SDM-integrated skill observation
  with minimal execution impact and efficient score persistence

## Summary

An Observable Skill carries its own evaluation criteria (observation
schema) and produces structured execution traces that are scored by
SDM post-execution. Observation adds zero latency to the user
experience. Scores persist per-skill for consumption by `skill-evolve`.

## Core Design Decisions

### 1. Agent-Agnostic Audit Trail

**Decision:** Scripts self-report execution traces via `trace_step()`
function. The LLM does not capture the trace — the deterministic
scripts do.

**Rationale:**

| Approach | Pros | Cons |
|----------|------|------|
| Harness-dependent (Goose sessions) | Already exists. Full fidelity. | Goose-locked. No skill semantics. Large files. Schema may change. |
| Agent-agnostic (script self-report) | Portable across agents. Skill-level semantics. Lightweight. Zero LLM involvement. | Must build trace_step(). |

AgentFS is agent-independent. Locking observation to Goose contradicts
this principle. Scripts already run identically across agents — making
them the trace source ensures portability.

**Implementation:**

```bash
# Sourced by any skill script
trace_step() {
  local step="$1" action="$2" exit_code="$3" detail="$4"
  local trace_file="${AGENTFS_TRACE:-/tmp/agentfs-trace-$$.jsonl}"
  printf '{"ts":"%s","step":%d,"action":"%s","exit":%d,"detail":"%s"}\n' \
    "$(date -Iseconds)" "$step" "$action" "$exit_code" "$detail" \
    >> "$trace_file"
}
```

The LLM's only job: set `AGENTFS_TRACE` env var before the first
script, pass it to `sdm-evaluate.sh` at the end. Two instructions.

### 2. Two-Phase Observation (Zero Execution Impact)

**Decision:** Separate execution from evaluation. SDM is never called
during skill execution. It is called after.

**Phase 1 — Execute (zero SDM calls):**
- LLM orchestrates skill. Scripts run. Structured output produced.
- Scripts write trace lines via `trace_step()`.
- Result delivered to user immediately.

**Phase 2 — Evaluate (post-execution):**
- Trace + observation schema fed to `sdm-evaluate.sh`.
- SDM scores each dimension. CECX record produced.
- Scores persisted to `observations/index.json`.

**Rationale:** Every SDM call adds latency and a failure point. If
evaluation fails, the user still has their result. The operator model
never waits for SDM.

### 3. Evaluation Trigger — Two Modes

**Decision:** No event bus or task queue. Two lightweight modes.

**Mode A — Inline tail-call (default for interactive sessions):**

The last step in the SKILL.md workflow runs evaluation:

```
Step N:   Present the report to the user.
Step N+1: Run the evaluation script.

    bash sdm-evaluate.sh "$AGENTFS_TRACE" observation.yaml
```

The user sees the report during streaming. Evaluation runs as the
next tool call — same turn, after user-visible content. ~500ms
additional turn time. Zero additional infrastructure.

**Mode B — Deferred batch (for recipe/batch runs):**

Trace files accumulate in `~/.agents/.traces/`. Evaluated by:
- Manual: `bash ~/.agents/scripts/evaluate-pending.sh`
- Git pre-push hook: evaluate pending traces before push, so scores
  commit alongside skill changes.
- Cron (optional): periodic cadence.

Git pre-push is the most natural fit — piggybacks on existing
`pre-push-scan.sh` pipeline. Scores land in `index.json` before
push, so any machine that pulls the repo gets the latest scores.

### 4. Three Schema Types — Universal and Per-Skill

**Decision:** Quality and Operable schemas are universal (one copy,
centrally maintained). Observation schema is per-skill.

| Schema | Scope | Location | Created By | Used By |
|--------|-------|----------|-----------|---------|
| Quality | Universal | `~/.agents/skills/schemas/quality.yaml` | Human or frontier model, once | `skill-check`, `skill-evolve` |
| Operable | Universal | `~/.agents/skills/schemas/operable.yaml` | Human or frontier model, once | `skill-check`, `skill-evolve` |
| Observation | Per-skill | `<skill>/observation.yaml` | Frontier model via `skill-gen` | `sdm-evaluate.sh`, `skill-evolve` |

**Rationale:**

*Quality (MCACS):* "Does this skill have Script Coverage ≥80%?" is
the same question for every skill. MCACS principles are universal
engineering criteria. Per-skill copies would drift and create
maintenance burden (61 files vs 1).

*Operable:* "Does this skill have scripts/, observation.yaml, CNL
compliance?" is the same structural check for every skill. The
Operable Skill architecture is a universal contract.

*Observation:* "Did the agent resolve the correct scope?" is specific
to `readme-audit`. "Did the agent report CRC VM state?" is specific
to `crc-status`. Execution correctness is inherently skill-specific.
Each skill carries its own "unit tests."

### 5. Unified Schema Format

All three schema types share one format. Only `schema-type` and
`evidence_source` differ.

```yaml
schema-version: "1.0"
schema-type: quality | operable | observation
skill: <skill-name>           # omitted for universal schemas
dimensions:
  - name: <string>
    question: <string>         # what SDM evaluates
    evidence_source: <string>  # where to find evidence
    metric: boolean | count | ratio
    target: <string>           # pass threshold
    weight: <float>            # for aggregate scoring (optional)
    choices: [<string>]        # for SDM classification (optional)
    applies_to: [<pattern>]    # conditional applicability (optional)
```

One evaluation script (`sdm-evaluate.sh`) handles all three by
switching evidence extraction based on `schema-type`:
- `quality` / `operable` → evidence from skill source files
- `observation` → evidence from execution trace

### 6. Schema Location

**Decision:** Universal schemas at `~/.agents/skills/schemas/`, not
`~/.agents/schemas/`.

**Rationale:** These schemas are exclusively about skills — skill
quality, skill operability. They have no meaning outside the skill
context. Co-locating with `skills/` follows cohesion: things that
relate to the same concern belong together.

### 7. Score Persistence

**Decision:** Per-skill `observations/` directory, gitignored, with
`index.json` summary.

```
~/.agents/skills/readme-audit/
├── observations/                          ← gitignored
│   ├── index.json                         ← summary for skill-evolve
│   └── 2026-10-22T17-00.json              ← individual CECX record
```

**`index.json` structure** (what `skill-evolve` reads):

```json
{
  "skill": "readme-audit",
  "current_version": "2.1.0",
  "schema_versions": {
    "quality": "1.0",
    "operable": "1.0",
    "observation": "1.0"
  },
  "total_executions": 12,
  "by_model": {
    "claude-sonnet-4": {
      "executions": 5,
      "avg_score": 96.2,
      "band": "Operable",
      "lowest_trait": "efficiency",
      "lowest_dimension": "dimension_coverage"
    },
    "qwen3-14b-fp8": {
      "executions": 7,
      "avg_score": 68.4,
      "band": "Re-engineer",
      "lowest_trait": "correctness",
      "lowest_dimension": "verdict_accuracy",
      "mcacs_attribution": "Cohesion"
    }
  },
  "trend": [
    {"version": "2.0.0", "model": "qwen3-14b-fp8", "score": 62.1},
    {"version": "2.1.0", "model": "qwen3-14b-fp8", "score": 68.4}
  ],
  "evolution_candidates": [
    {
      "trait": "correctness",
      "dimension": "verdict_accuracy",
      "mcacs": "Cohesion",
      "direction": "Extract scope resolution to gather-state.sh"
    }
  ]
}
```

**Gitignore rule:** `observations/` are derived artifacts — generated
from execution, not authored. Machine-local. Different machines with
different models produce different records. The `observation.yaml`
(authored criteria) IS committed. Results are not.

**Schema versioning:** `index.json` records which schema versions
scores were computed against. When `quality.yaml` is updated (v1.0
→ v1.1), `skill-evolve` sees the mismatch and triggers re-audit.

## Revised Skill Directory Structure

```
~/.agents/skills/
├── schemas/                         ← universal (committed)
│   ├── quality.yaml                 ← MCACS quality standard
│   └── operable.yaml                ← structural compliance
├── index.md
├── readme-audit/
│   ├── SKILL.md                     ← muscle (CNL prose)
│   ├── CHANGELOG.md
│   ├── observation.yaml             ← per-skill execution criteria
│   ├── scripts/                     ← bones (deterministic)
│   │   ├── gather-state.sh
│   │   └── common.sh               ← includes trace_step()
│   └── observations/                ← results (gitignored)
│       ├── index.json
│       └── 2026-10-22T17-00.json
```

## Evaluation Flow — All Three Schemas

```
skill-check (auditing readme-audit):
  1. Read ~/.agents/skills/schemas/quality.yaml
  2. Read ~/.agents/skills/schemas/operable.yaml
  3. Read readme-audit/SKILL.md + scripts/
  4. SDM call per quality dimension → quality score
  5. SDM call per operable dimension → compliance score
  6. Report: MCACS quality + Operable compliance

sdm-evaluate.sh (scoring an execution):
  1. Read readme-audit/observation.yaml
  2. Read execution trace (AGENTFS_TRACE)
  3. SDM call per observation dimension → CECX scores
  4. Write record to observations/
  5. Update observations/index.json

skill-evolve (improving readme-audit):
  1. Read observations/index.json     ← execution trends
  2. Read schemas/quality.yaml        ← what quality means
  3. Read schemas/operable.yaml       ← what compliant means
  4. Read observation.yaml            ← what correct means
  5. Cross-reference: which quality/operable gaps cause failures?
  6. Produce upgrade spec → feed back to skill-gen
```

## SDM Endpoint

SDM endpoint is resolved via environment variable:

```bash
SDM_ENDPOINT="${SDM_ENDPOINT:-http://localhost:9001}"
```

Two deployment options:
- **Shared:** Same endpoint as LLM at `localhost:9000` (if model
  serves both generative and decision APIs)
- **Dedicated:** Separate endpoint at `localhost:9001` (recommended
  for isolation)

API compatibility: OpenAI-compatible Decision API or SystemOne API.
Concrete API schema to be specified in Phase 0.1 implementation.

## Relationship to Existing Concepts

- **Operable Skill Architecture:** Observable is a property of an
  Operable Skill — the skill carries self-evaluation criteria.
- **CECX Observation Schema:** CECX scoring formula consumes the
  observation results. CECX is the aggregation method; observation
  schema is the per-dimension definition.
- **SDM Integration:** SDM Pattern 2 (evaluation engine) is
  implemented through this observation design.
- **MCACS Measurement:** Quality schema dimensions map directly to
  MCACS per-principle metrics.
