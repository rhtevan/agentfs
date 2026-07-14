---
name: agentfs-ctx-chk
description: >-
  Audit the context engineering layers that load into an AI agent session
  for redundancy, ambiguity, conflicts, effectiveness, and cross-reference
  integrity. Produces a findings report with action plan, then optionally
  applies fixes to both project files and root-cause skill templates.
  Complements agentfs-eval (structural health) with context optimization.
metadata:
  version: "1.1"
  tags: [agentfs, context, audit, optimization, guardrails]
user-invocable: true
disable-model-invocation: false
---

# AgentFS Context Check

Audit the full stack of context that loads into an AI agent session and
identify redundancy, ambiguity, conflicts, effectiveness issues, and
stale cross-references. Optionally apply fixes.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.0 |
| **Trigger** | Explicit — user asks to audit/check context |
| **Scope** | Cross-layer: PROJECT `AGENTS.md` + USER `~/.agents/` + agent config + skills |
| **Dependencies** | `grep`, `wc`, `cat` — no external tools |
| **LLM required** | Yes — redundancy/ambiguity detection is semantic |
| **Companion** | `agentfs-eval` checks structural health; this skill checks context efficiency |

## When to Use

- **New project**: After running `agentfs-setup`, audit the generated
  AGENTS.md against global instructions for redundancy
- **Existing project**: Periodically check that accumulated context
  hasn't drifted, bloated, or developed contradictions
- **After guardrail changes**: When guardrails are renumbered, merged,
  or split, verify all cross-references are updated
- **After skill updates**: When skills reference guardrails by number,
  verify references are still correct

## How It Differs from `agentfs-eval`

| Dimension | `agentfs-eval` | `agentfs-ctx-chk` |
|-----------|---------------|--------------------|
| Question | "Is this workspace structurally healthy?" | "Is the loaded context well-engineered?" |
| Scope | Single project `.agents/` | Cross-layer (project + user + agent config) |
| Method | Deterministic scripts + LLM classification | LLM-driven semantic analysis |
| Output | Maturity report (L0–L5) | Findings report + action plan |
| Fixes | Reports issues | Reports AND optionally applies fixes |
| Blast radius | One project | Seed templates + skills + global config |

## Execution Steps

### Step 1: Inventory All Context Sources

Identify every file that loads into the agent's session context.
For each source, record: path, approximate size, loading mechanism.

**Auto-loaded sources** (always in context):

| Source | Typical Path | How Loaded |
|--------|-------------|------------|
| Project context file | `./AGENTS.md` | `CONTEXT_FILE_NAMES` auto-discovery |
| Project hints | `./.goosehints` | `CONTEXT_FILE_NAMES` auto-discovery |
| Global hints | `~/.config/goose/.goosehints` | Global hints loading |
| Global instructions | `~/.config/goose/instructions.md` | `GOOSE_MOIM_MESSAGE_FILE` |
| Extension instructions | Per enabled extension | Extension system |
| Skills listing | Names + descriptions from `~/.agents/skills/` | Skills extension |

**On-demand sources** (loaded when referenced):

| Source | Typical Path | How Loaded |
|--------|-------------|------------|
| Agent identity | `./.agents/SOUL.md` | Agent reads from Quick Orientation |
| Knowledge index | `~/.agents/knowledge/index.md` | Agent reads from Quick Orientation or global hints |
| Directory index | `./.agents/index.md` | Agent reads via Progressive Disclosure |
| Memory files | `./.agents/memories/MEMORY.md` | Agent reads on memory signal |

Read each auto-loaded source and note its size in lines.

### Directionality Rule (applies to ALL subsequent steps)

When divergence is found between USER-scope files (`~/.agents/`,
`~/.config/goose/`) and a PROJECT-scope file (`./AGENTS.md`,
`./.agents/`):

1. **USER scope is canonical.** The seed templates and skills under
   `~/.agents/` represent the optimized, authoritative structure.
   The guardrail numbering and naming in the seed template
   (`agentfs-setup/scripts/seed-agents-md.sh`) is the reference
   standard for all cross-reference checks.
2. **PROJECT scope is the fix target.** If a project's AGENTS.md has
   diverged from the seed template (extra guardrails, renumbered,
   renamed), the project file needs regeneration — NOT the template.
3. **Never modify USER-scope templates to match project drift.**
   A project that added guardrails or renumbered them is a local
   deviation. The audit should flag it as "project AGENTS.md
   diverged from canonical seed template" and recommend
   regeneration.
4. **Exception — explicit graduation.** Only update USER-scope
   templates when the user explicitly states that a project contains
   improvements that should be promoted upstream. Treat this as a
   graduation request requiring human approval.
5. **Cross-reference baseline.** When checking `Guardrail #N`
   references in skills and config files, verify against the **seed
   template** numbering — not against any individual project's
   AGENTS.md. Skills are USER-scoped and must reference the
   canonical structure.

### Step 2: Check Redundancy

For each rule or policy found in auto-loaded context, verify it
appears **exactly once** across all sources.

Common redundancy patterns:
- Same rule stated in multiple guardrails within AGENTS.md
- AGENTS.md guardrails restated in `~/.agents/index.md`
- Signal routing duplicated between AGENTS.md and agent instructions
- Skill placement rule repeated in guardrails AND routing rules
- Log scope rules in both log currency and index currency guardrails

For each redundancy, identify:
- The **canonical** location (where the rule should live)
- The **redundant** location(s) (where it should be removed or
  replaced with a cross-reference)

### Step 3: Check Ambiguity

Identify cases where two sources say similar but not identical things.

Common ambiguity patterns:
- Divergent format specifications (e.g., different timestamp formats)
- Placeholder inconsistency (`<username>` vs `<user>`)
- Unclear override precedence between context layers
- References to disabled extensions in routing tables

### Step 4: Check Conflicts

Identify direct contradictions between context sources.

Common conflict patterns:
- Opposite instructions in different files
- Scope contradictions
- Stale guardrail number cross-references after renumbering

### Step 5: Check Effectiveness

Assess whether context is concise, well-ordered, and token-efficient.

Check:
- **Total size** of auto-loaded context (flag if > 400 lines combined)
- **Guardrail ordering** — should follow usage frequency:
  1. Every-session-start rules (progressive disclosure, identity)
  2. Frequent-use rules (memory routing, skill placement)
  3. Occasional-use rules (filesystem integrity)
  4. Rare-but-critical rules (git push safety, checkpoints)
- **Dead context** — references to disabled features consuming tokens
- **Progressive loading** — verify SOUL.md and knowledge index are
  reachable from auto-loaded context (Quick Orientation or hints)
- **Missing on-demand paths** — important resources with no path
  from auto-loaded context

### Step 6: Check Cross-References

Verify all cross-references between files are accurate.

Scan for `Guardrail #N` references in:
- All `~/.agents/skills/*/SKILL.md` files
- All `~/.agents/skills/*/scripts/*.sh` files
- All `~/.agents/skills/*/references/*.md` files
- `~/.config/goose/instructions.md`

For each reference, verify:
- The number maps to the correct guardrail name in the AGENTS.md template
  (canonical source: `~/.agents/skills/agentfs-setup/scripts/seed-agents-md.sh`)
- Placeholder names are consistent (`<user>` everywhere, not `<username>`)

Command to find all references:
```bash
grep -rn 'Guardrail #[0-9]' ~/.agents/skills/*/SKILL.md \
  ~/.agents/skills/*/scripts/*.sh \
  ~/.agents/skills/*/references/*.md \
  ~/.config/goose/instructions.md 2>/dev/null \
  | grep -v 'Changelog\|changelog\|| 20'
```

Command to find placeholder inconsistencies:
```bash
grep -rn '<username>' ~/.agents/skills/ ~/.config/goose/ 2>/dev/null \
  | grep -v node_modules | grep -v python3 | grep -v cache/pkg
```

### Step 7: Assess Root Causes

For every finding, determine whether it's a local symptom or a
systemic issue in a skill template.

| If the issue is in... | The root cause is likely... | Fix direction |
|----------------------|---------------------------|---------------|
| Project `AGENTS.md` diverged from seed | Project was modified after generation | **Regenerate project** from seed template — do NOT update seed |
| Project `AGENTS.md` missing seed content | Seed was updated after project was created | **Regenerate project** from seed template |
| `~/.agents/index.md` | `agentfs-setup/scripts/scaffold-dotagents.sh` | Fix scaffold script, then regenerate index |
| Global `instructions.md` | `goose-agentfs-setup/scripts/setup.sh` | Fix setup script, then regenerate instructions |
| Skill guardrail cross-refs vs seed | Individual skill SKILL.md files | Fix skill to match seed numbering |
| Skill guardrail cross-refs vs project | Project diverged from seed | **Fix project** — skill refs are correct against seed |

> **Key principle:** USER scope (`~/.agents/`, `~/.config/goose/`) is
> the gold standard. Project files are generated artifacts. When they
> diverge, the project is wrong, not the template. Never fix only the
> symptom — but also never "fix" the template to match a drifted project.

### Step 8: Produce Report

Present findings in this structure:

```markdown
# Context Audit Report

## Inventory
| # | Source | Path | Lines | Loading |

## Findings

### 🔴 REDUNDANCY
R1: [description] — canonical: [location], redundant: [location(s)]

### 🟡 AMBIGUITY
A1: [description] — sources: [locations]

### 🟢 CONFLICTS
(None found — or list)

### 🔵 EFFECTIVENESS
E1: [description] — impact: [token cost / ordering / dead context]

### 🟣 CROSS-REFERENCES
X1: [stale reference] → [correct reference]

## Summary Scorecard
| Dimension | Score | Key Issue |
|-----------|-------|-----------|
| Redundancy | 🔴/🟡/🟢 | ... |
| Ambiguity | 🔴/🟡/🟢 | ... |
| Conflicts | 🔴/🟡/🟢 | ... |
| Effectiveness | 🔴/🟡/🟢 | ... |
| Cross-refs | 🔴/🟡/🟢 | ... |

## Top N Actions (prioritized)
1. [action] — [files affected] — [root cause fix]
```

### Step 9: Apply Fixes (Optional)

If the user approves the action plan:

1. Apply fixes to project files (AGENTS.md, .goosehints, etc.)
2. Apply root-cause fixes to skill templates and scripts
3. Update all stale cross-references in affected skills
4. Update `log.md` at both USER and PROJECT scope as appropriate
5. Regenerate `skills/index.md` if any SKILL.md was modified

## Detailed Checklist

See [references/checklist.md](./references/checklist.md) for the
full audit checklist with patterns and examples from real audits.

## Example Prompts

> "Run context audit"
> "Check context for redundancy"
> "Audit my AGENTS.md context stack"
> "Context sanity check"

## Companion Skills

- **`agentfs-eval`** — Structural health assessment (maturity L0–L5)
- **`agentfs-setup`** — Scaffolds the AGENTS.md template this skill audits
- **`goose-agentfs-setup`** — Manages Goose-specific config this skill checks
- **`skill-index`** — Regenerates skill index after cross-reference fixes

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-14 18:34 | v1.1 — Added Directionality Rule between Steps 1–2: USER scope is canonical, PROJECT scope is fix target; updated Step 7 root cause table with Fix Direction column; updated references/checklist.md Phase 7 with matching changes |
| 2026-07-14 18:12 | v1.0 — Initial design from first context audit session; 8-phase methodology (inventory, redundancy, ambiguity, conflicts, effectiveness, cross-references, root causes, report) |
