---
type: Behavioral Property
title: Partial Completion
description: Model completes most but not all steps in a multi-step procedure
tags: [llm, behavioral, partial, laziness, shortcutting, completion]
timestamp: 2026-09-10T18:03:00-04:00
---

# Partial Completion (Laziness / Shortcutting)

## Property

The model completes the primary functional steps of a procedure
but skips secondary steps — typically those related to
documentation, verification, or cleanup. It takes the fastest
path to a working result rather than the correct path through
all prescribed steps.

## Observable Symptoms

- Does 3 of 5 checklist items then responds
- Skips changelog or version bump after creating a skill
- Creates scripts but doesn't chmod +x
- Writes SKILL.md but skips frontmatter validation
- Runs tests but doesn't log results
- Creates files but skips post-write chain

## Variants

### Format Drift

Gradually deviates from established formatting conventions over
a session. Early outputs follow the pattern precisely; later
outputs introduce shortcuts (e.g., dropping bullet prefixes,
mixing table vs heading formats, omitting section headers).

### Scope Conflation

Defaults to the most familiar pattern rather than evaluating
criteria. Example: always choosing USER scope for skills because
that's the historically dominant pattern, without evaluating
whether PROJECT scope is more appropriate.

## AgentFS Mitigations

| Mitigation | Location | Mechanism |
|-----------|----------|-----------|
| Mandatory Skill Check | skill-gen Post-Creation Checklist | P1–P7 gate — all must pass before proceeding |
| Rule 13 before-response gate | AGENTS.md | "Do not respond until complete" |
| `post-edit.sh` index regen | agentfs-setup | Forces frontmatter re-scan, catches metadata drift |
| Scope criteria table | skill-gen Step 2 | Decision framework replaces default-to-familiar |
| Error Contract (P7) | skill-gen | Prescribed agent behavior per exit code — no improvisation |

## Effectiveness

Process gates (Skill Check, Rule 13) are effective when the agent
is in "skill creation" mode. They fail during mode switches —
when the agent transitions from "creating" to "debugging" to
"testing" within the same session, the checklist context is lost.
Drift detection (`post-edit.sh`) provides the catch net.
