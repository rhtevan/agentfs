# SDM Integration for AgentFS

- **Type:** Pattern
- **Status:** Active
- **Source:** Session analysis — Semantic Decision Model as MCACS implementation

## Summary

The Semantic Decision Model (SDM), aka SystemOne API, is a zero-shot
request-response endpoint that makes bounded semantic judgments. It integrates
into AgentFS in two patterns: as a skill runtime component (lowering cognitive
load) and as an evaluation engine (turning qualitative judgments into
quantitative metrics).

## What SDM Is

A decision service that takes evidence and a criterion, applies semantic
understanding, and returns a judgment. Zero-shot, stateless, request-response.
No conversation history, no multi-turn reasoning. One question, one answer.

## Pattern 1 — SDM as Skill Runtime

For prose-heavy skills (Pattern C: agentfs-readme-audit, violation-chk,
ctx-chk, skill-eval), the agent currently performs both data gathering AND
semantic judgment in one reasoning chain. SDM splits this:

```
Before:
  Agent (14B) → load_skill → read prose → gather data → reason about N dimensions → report
  (5+ inference hops, all in one model's context, all qualitative)

After:
  gather-state.sh → structured evidence (deterministic)
  For each dimension:
    SDM call: evidence + criterion → decision + confidence
  Agent (14B) → collects SDM responses → formats report
  (2 hops: run script, format results. Agent orchestrates, SDM judges.)
```

The agent's job shrinks from "reason about everything" to "call tools, format
output." This converts Pattern C (prose-only semantic, high failure rate) into
Pattern A (single script execution, >95% success rate).

### Integration Options

**Script-callable:** Skill scripts call SDM endpoint via curl internally.
Agent runs one wrapper script, reads structured output.

```bash
# Inside scripts/evaluate-readme.sh
for dim in D1 D2 D3 D4 D5 D6 D7 D8 D9; do
  evidence=$(gather_evidence "$dim")
  result=$(curl -s "$SDM_ENDPOINT/decide" -d "{\"evidence\": \"$evidence\", ...}")
  echo "$dim|$(echo $result | jq -r '.decision')|$(echo $result | jq -r '.reason')"
done
```

**MCP server:** SDM exposed as tool calls. Agent calls `sdm_evaluate`
directly within its tool-calling flow. Cleaner for Pattern 1 because it
stays within the agent's context — no shell indirection.

```
Agent calls: sdm_evaluate(dimension="D1", evidence="README says 58, actual 61")
→ {"decision": "DRIFT", "confidence": 0.95, "reason": "count mismatch"}
```

Both are valid. Script approach is simpler. MCP approach integrates better
with the agent's tool-calling pattern.

## Pattern 2 — SDM as Evaluation Engine

For the benchmark test suite (T1–T8), SDM replaces human scoring:

```
Run T1 on Qwen3-14B → capture response
SDM call: evidence=response, criterion="starts with 🐦 word-word"
→ {"pass": true/false, "confidence": 0.99}
```

Each test case's pass criteria becomes a SDM decision request. Scoring is
repeatable, objective, and independent of the model under test.

This solves the evaluation bootstrap problem: you don't need a frontier model
to judge a mid-range model's output. SDM makes bounded, single-criterion
judgments — a fundamentally simpler task than the original skill execution.

## How SDM Implements MCACS

| Principle | How SDM Implements It |
|-----------|----------------------|
| Modularity | Each SDM call is an independent, testable module (one decision per call) |
| Cohesion | Each request bundles evidence + question + criteria — everything the decision needs, nothing extra |
| Separation of Concerns | Data gathering (script) → judgment (SDM) → orchestration (agent) — three components, three concerns |
| Abstraction | Agent does not know how SDM makes decisions. Interface: evidence in, decision out. |
| Coupling | Agent decoupled from reasoning capability for judgment. 14B model orchestrates SDM calls without performing the judgment itself. |

## Applicability

SDM is most valuable for:
- **Pattern C skills** (prose-only semantic analysis) — converts to Pattern A
- **Benchmark evaluation** (T1–T8 scoring) — objective, automated grading
- **Any skill step requiring bounded semantic judgment** — where the question
  is well-defined and the evidence is pre-gathered

SDM is NOT needed for:
- Pattern A skills (single script) — already deterministic
- Pattern B skills (multi-step scripted) — scripts already provide checkpoints
- Pattern D skills (generative) — creative output is the LLM's core job
- Pattern E skills (configuration) — template substitution is deterministic
