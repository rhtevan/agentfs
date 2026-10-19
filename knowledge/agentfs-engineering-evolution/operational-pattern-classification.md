# Operational Pattern Classification

- **Type:** Reference
- **Status:** Active
- **Source:** Analysis of 61 AgentFS skills + 7 AGENTS.md rules

## Summary

Five distinct operational patterns classify how AgentFS skills demand the
agent to work. Each pattern has different cognitive load, failure modes,
and evolution strategies. Skills are classified by pattern to prioritize
MCACS improvements.

## The Five Patterns

### Pattern A — Single Script Execution

Run one script, report the result. Lowest cognitive demand.

**Examples:** crc-status, litellm-proxy-status, headroom-proxy-status,
agentflow-fuseki (start/stop/status), fedora-window-list, goose-cli-fix.

**14B failure risk:** Minimal. Should pass >95%.

### Pattern B — Multi-Step Scripted Workflow

Execute scripts in sequence, pass outputs between steps, handle conditional
branches and sub-skill delegation.

**Examples:** agentfs-git-push (9 steps with readme-audit sub-skill),
hosted-model-ctl (precheck → setup → start → test),
skupper-model-provider, dsh-setup.

**14B failure modes:** Scope confusion (wrong target), step skipping,
premature action (bypassing wait gates), wrong sub-skill dispatch.

### Pattern C — Prose-Only Semantic Analysis

Agent reads data, reasons about it, produces structured report. No scripts
to scaffold the process — pure prose orchestration.

**Examples:** agentfs-readme-audit, agentfs-violation-chk, agentfs-ctx-chk,
skill-eval (7-principle audit).

**14B failure modes:** Hallucinated scripts, fabricated data, wrong scope,
skipped data gathering. Most vulnerable pattern.

**Evolution strategy:** Extract data gathering into scripts. Delegate
bounded decisions to SDM endpoint. Agent orchestrates tool calls and
formats reports.

### Pattern D — Generative Content Creation

Agent produces new content conforming to a specification (YAML frontmatter,
markdown structure, code templates).

**Examples:** skill-gen, okf-bundle-gen, agentfs-archify (mermaid diagrams),
bash-completion-gen.

**14B failure modes:** Schema drift (wrong frontmatter fields), missing
required sections, inconsistent signal phrases, hallucinated file formats.

### Pattern E — Configuration from Template

Agent reads a defensive template, substitutes values, writes valid config.

**Examples:** goose-litellm-provider, goose-headroom-provider,
goose-maas-provider, hermes-litellm-provider, dsh-litellm-provider.

**14B failure modes:** Wrong field values, stale defaults from training
data overriding the template, mixing config formats, forgetting to quote
values.

## Skill Classification (61 skills)

| Pattern | Count | % of Total |
|---------|:-----:|:----------:|
| A — Single script | ~12 | 20% |
| B — Multi-step scripted | ~10 | 16% |
| C — Prose-only semantic | ~6 | 10% |
| D — Generative | ~5 | 8% |
| E — Configuration | ~7 | 11% |
| Mixed / uncategorized | ~21 | 34% |

Pattern C skills are 10% of the library but account for the highest-severity
failures on weaker models. These are the priority targets for MCACS evolution.

## Rule-Level Operations

The 7 AGENTS.md rules also impose operational patterns:

| Rule | Pattern | Cognitive Demand |
|------|---------|------------------|
| Signal Dispatch | search_nodes → load_skill → execute | Medium (chained tool calls) |
| Pre-Flight | State plan → conditional branching | Low (prose generation) |
| Post-Write | Run script per file → gate response | Low (script execution) |
| Session Canary | Read file → generate output format | Low but subject to generation prior conflict |
| Conflict Resolution | Detect state → articulate reasoning | Medium (self-monitoring) |
| Checkpoint | Conditional script → execute → cleanup | Low (script execution) |
| Scope Rules | Classify intent → route to location | Medium (classification) |
