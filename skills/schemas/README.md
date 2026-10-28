# Skill Evaluation Schemas

Unified schema format for evaluating AgentFS skills across three
concerns: design quality, structural compliance, and execution
correctness.

## Schema Types

| Type | Scope | File | Evaluates | When |
|------|-------|------|-----------|------|
| **quality** | Universal | `quality.yaml` | Skill design against MCACS principles | Build-time audit |
| **observable** | Universal | `observable.yaml` | Build-time observability — instrumentation, traces, CNL, anti-fabrication | Build-time audit |
| **operable** | Universal | `operable.yaml` | Runtime execution correctness from trace evidence (CECX) | Run-time evaluation |

## Unified Format

```yaml
schema-version: "1.0"
schema-type: quality | observable | operable
skill: <skill-name>             # omitted for universal schemas
description: >
  Human-readable purpose of this schema.

dimensions:
  - name: <string>              # unique dimension identifier
    question: <string>          # what SDM evaluates (natural language)
    evidence_source: <string>   # where to find evidence
    metric: boolean | count | ratio | choice
    target: <string>            # pass threshold (e.g., ">= 0.80", "<= 2", "true")
    weight: <float>             # relative weight for aggregate scoring (default: 1.0)
    choices: [<string>]         # for choice metrics: possible values
    applies_to: [<pattern>]     # conditional: only evaluate for these skill patterns
    mcacs: <string>             # for quality schemas: which MCACS principle
```

## Field Reference

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `schema-version` | string | Schema format version (currently "1.0") |
| `schema-type` | enum | One of: `quality`, `observable`, `operable` |
| `dimensions` | array | List of evaluation dimensions |
| `dimensions[].name` | string | Unique identifier for the dimension |
| `dimensions[].question` | string | Natural language question for SDM |
| `dimensions[].metric` | enum | Measurement type: `boolean`, `count`, `ratio`, `choice` |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `skill` | string | Inferred from directory | Skill name (omitted for universal schemas) |
| `description` | string | — | Human-readable purpose |
| `dimensions[].evidence_source` | string | — | Hint for evidence extraction |
| `dimensions[].target` | string | — | Pass threshold expression |
| `dimensions[].weight` | float | 1.0 | Relative weight in aggregate score |
| `dimensions[].choices` | array | — | Valid values for choice metrics |
| `dimensions[].applies_to` | array | all | Skill patterns this dimension applies to |
| `dimensions[].mcacs` | string | — | MCACS principle (quality schemas only) |

## Metric Types

### boolean

Yes/No evaluation. SDM returns a probability.

- **SDM question type:** `predicate`
- **Pass:** probability ≥ 0.7
- **Fail:** probability < 0.3
- **Uncertain:** 0.3–0.7
- **Target format:** `"true"` or `"false"`

### count

Numeric count. SDM returns a score on an ordinal scale.

- **SDM question type:** `score` with levels 0–5+
- **Target format:** `"<= N"` or `">= N"` (e.g., `"<= 2"`)

### ratio

Percentage or proportion. SDM returns a score on a percentage scale.

- **SDM question type:** `score` with levels 0-20%, 20-40%, etc.
- **Target format:** `">= 0.80"` or `"<= 0.20"`

### choice

Classification into one of several options.

- **SDM question type:** `choice`
- **Requires:** `choices` field with valid values
- **Target format:** expected value (e.g., `"aligned"`)

## Evidence Sources

`sdm-evaluate.sh` extracts evidence differently based on `schema-type`:

| Schema Type | Target Argument | Evidence Extraction |
|-------------|-----------------|---------------------|
| `quality` | Skill directory path | SKILL.md content + scripts/ listing + directory structure |
| `observable` | Skill directory path | SKILL.md content + scripts/ listing + directory structure |
| `operable` | Trace file path (JSONL) | Full trace content from `trace-lib.sh` output |

## Scoring

### Per-Dimension

Each dimension produces a score (0–100) and a pass/fail verdict
based on the target threshold.

### Aggregate

Weighted average of all dimension scores:

```
aggregate = sum(score_i × weight_i) / sum(weight_i)
```

### Interpretation Bands

| Score | Band | Meaning |
|:-----:|------|---------|
| 90–100 | Operable | Meets standard. No changes needed. |
| 75–89 | Tunable | Specific gaps identified. Targeted upgrade. |
| 50–74 | Re-engineer | Multiple gaps. MCACS analysis needed. |
| < 50 | Redesign | Fundamental mismatch. Rebuild required. |

## Tools

| Script | Purpose |
|--------|---------|
| `~/.agents/scripts/sdm-call.sh` | Single SDM decision call |
| `~/.agents/scripts/sdm-evaluate.sh` | Multi-dimension evaluation against any schema |
| `~/.agents/scripts/trace-lib.sh` | Agent-agnostic execution trace capture |

## SDM Endpoint

See [sdm-endpoint.md](./sdm-endpoint.md) for API reference.

## Versioning

Schema files are version-controlled. When a schema is updated (e.g.,
`quality.yaml` v1.0 → v1.1), evaluation records carry the schema
version they were scored against. `skill-evolve` detects version
mismatches and triggers re-evaluation.

## Directory Layout

```
~/.agents/
├── scripts/
│   ├── sdm-call.sh              ← single decision call
│   ├── sdm-evaluate.sh          ← multi-dimension evaluator
│   └── trace-lib.sh             ← trace capture library
│
├── .traces/                      ← gitignored, trace JSONL files
│   ├── .gitignore
│   └── <skill>-<timestamp>.jsonl
│
└── skills/
    ├── schemas/                  ← universal schemas (this directory)
    │   ├── README.md             ← this file
    │   ├── sdm-endpoint.md       ← API reference
    │   ├── quality.yaml          ← MCACS quality standard
    │   ├── observable.yaml        ← build-time observability
    │   └── operable.yaml         ← runtime execution correctness
    │
    └── <skill-name>/
        ├── SKILL.md
        ├── scores.yaml            ← objective QOO scores (SDM-evaluated)
        ├── scores.yaml            ← evaluation history (committed)
        └── scripts/
```
