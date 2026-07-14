# Context Audit Checklist

Systematic checklist for auditing the context engineering layers that
load into an AI agent session. Each section maps to a phase in the
skill's execution.

## Phase 1: Inventory

Identify every context source that loads into the agent's session.

| Source Type | Examples | How to Find |
|-------------|----------|-------------|
| Agent system prompt | Hardcoded by runtime | Not inspectable; note its existence |
| Extension instructions | Per enabled extension | List enabled extensions in config |
| Global persistent instructions | `~/.config/goose/instructions.md`, `GOOSE_MOIM_MESSAGE_FILE` | Check agent config file |
| Project context files | `AGENTS.md`, `.goosehints`, `CLAUDE.md` | Check `CONTEXT_FILE_NAMES` or equivalent |
| Agent identity | `.agents/SOUL.md` | Check Quick Orientation / project hints |
| Knowledge index | `~/.agents/knowledge/index.md` | Check global hints / Quick Orientation |
| Skills listing | Names + descriptions injected by skills extension | Check enabled extensions |
| USER-scope index | `~/.agents/index.md` | Check if it contains rules/guardrails |

For each source, record:
- File path
- Approximate size (lines / tokens)
- Loading mechanism (auto-loaded vs on-demand)
- Injection point (system prompt, turn context, user message)

## Directionality Rule (applies to ALL phases)

When divergence is found between USER-scope files (`~/.agents/`,
`~/.config/goose/`) and a PROJECT-scope file (`./AGENTS.md`,
`./.agents/`):

1. **USER scope is canonical.** The seed templates, skills, and config
   under `~/.agents/` represent the optimized, authoritative structure.
2. **PROJECT scope is the fix target.** If a project's AGENTS.md has
   diverged (extra guardrails, renumbered, renamed), flag it as
   "project diverged from canonical seed" — recommend regeneration.
3. **Never modify USER-scope templates to match project drift.**
4. **Cross-reference baseline.** Verify `Guardrail #N` references
   against the seed template (`seed-agents-md.sh`) numbering, NOT
   against any individual project's AGENTS.md.
5. **Exception:** Only update USER-scope when the user explicitly
   requests graduation of project improvements upstream.

## Phase 2: Redundancy Check

For each rule, policy, or instruction, verify it appears **exactly once**
across all loaded context sources.

### What to Look For

| Pattern | Example from real audit |
|---------|------------------------|
| Same rule stated N times across files | Memory routing defined in AGENTS.md #8, #9, AND instructions.md |
| Same rule restated within one file | Skill placement in both Guardrail #5 and Routing Rules |
| Guardrails duplicated at different scopes | `~/.agents/index.md` restating `AGENTS.md` guardrails |
| Scope/log rules repeated in multiple guardrails | Log scope in both Log Currency and Index Currency |

### Audit Procedure

1. Extract all imperative statements (MUST, NEVER, ALWAYS, default to)
   from each loaded file
2. Group by semantic intent
3. Flag any intent expressed more than once
4. For each duplicate, identify the canonical location and the
   redundant location(s)

## Phase 3: Ambiguity Check

Identify cases where two sources say similar but not identical things,
or where precedence between sources is unclear.

### What to Look For

| Pattern | Example from real audit |
|---------|------------------------|
| Divergent specifications | `index.md` says `YYYY-MM-DD`, AGENTS.md says `YYYY-MM-DD HH:MM` |
| Unclear override precedence | Which wins: instructions.md or AGENTS.md? |
| Placeholder inconsistency | `<username>` in one file, `<user>` in another |
| Dead references to disabled features | Routing table for extensions that are disabled |

### Audit Procedure

1. For each duplicated/similar rule found in Phase 2, compare wording
2. Check placeholder names for consistency across all files
3. Verify override hierarchy is documented (agent-specific > AGENTS.md > defaults)
4. Flag references to tools/extensions that are currently disabled

## Phase 4: Conflict Check

Identify direct contradictions between context sources.

### What to Look For

| Pattern | Example |
|---------|--------|
| Opposite instructions | File A says "always X", File B says "never X" |
| Scope contradictions | One source says memories are USER-scoped, another says PROJECT-only |
| Numbering mismatches | Cross-references to "Guardrail #13" when guardrails were renumbered to 9 |

### Audit Procedure

1. For each imperative statement, search for negating statements
2. Verify all guardrail cross-references point to the correct number
   and name
3. Check that scope assignments are consistent across all files

## Phase 5: Effectiveness Check

Assess whether the loaded context is concise, well-ordered, and
token-efficient.

### What to Look For

| Pattern | Example from real audit |
|---------|------------------------|
| Excessive size | AGENTS.md at 366 lines / ~7K tokens for every turn |
| Poor ordering | Rarely-used guardrails listed before frequently-used ones |
| Dead context | Session bridge pattern for a disabled extension |
| Missing progressive loading | SOUL.md not reachable from any auto-loaded file |
| Missing knowledge loading | Knowledge index not reachable from any auto-loaded file |

### Ordering Principle

Guardrails and instructions should be ordered by **usage frequency**:
1. Things checked every session start (progressive disclosure, identity)
2. Things used frequently during work (memory routing, skill placement)
3. Things used occasionally (filesystem integrity rules)
4. Things used rarely but critically (git push safety, checkpoints)

### Audit Procedure

1. Measure total lines/tokens per auto-loaded source
2. Identify any content that could be moved to on-demand loading
3. Check guardrail ordering against usage frequency
4. Verify SOUL.md and knowledge index are reachable from auto-loaded context
5. Flag dead context (references to disabled features that consume tokens)

## Phase 6: Cross-Reference Integrity

Verify that all cross-references between context sources are accurate.

### What to Look For

| Pattern | Example from real audit |
|---------|------------------------|
| Stale guardrail numbers | Skills referencing "Guardrail #8" after renumbering |
| Stale guardrail names | Reference says "Memory Scope" but guardrail renamed to "Memory Scope & Signal Routing" |
| Broken skill references | Decision table names a skill that doesn't exist |
| Placeholder inconsistency | `<username>` vs `<user>` across files |

### Audit Procedure

1. Extract all `Guardrail #N` references from all skills and config files
2. Verify each maps to the correct guardrail name in AGENTS.md
3. Check all skill names in decision tables against `~/.agents/skills/index.md`
4. Verify placeholder consistency across all files

## Phase 7: Root Cause Assessment

For every finding, determine whether the fix is local (this project
only) or systemic (requires updating seed templates/skills).

### Decision Table

| Finding Location | Root Cause | Fix Direction |
|-----------------|------------|---------------|
| Project `AGENTS.md` diverged from seed | Project was modified after generation | **Regenerate project** from seed — do NOT update seed |
| Project `AGENTS.md` missing seed content | Seed updated after project creation | **Regenerate project** from seed |
| Global `instructions.md` | `goose-agentfs-setup/scripts/setup.sh` | Fix setup script, then regenerate instructions |
| `~/.agents/index.md` | `agentfs-setup/scripts/scaffold-dotagents.sh` | Fix scaffold script, then regenerate index |
| Skill cross-refs don't match seed | Individual skill files | Fix skill to match seed numbering |
| Skill cross-refs don't match project | Project diverged from seed | **Fix project** — skill refs are correct against seed |
| Placeholder inconsistency | All files using the placeholder | Fix in all files + templates |

### Key Principle

> **USER scope is the gold standard.** The seed templates and skills
> under `~/.agents/` are the optimized, authoritative structure.
> Project files are generated artifacts. When they diverge, the
> project is wrong, not the template. Never "fix" the template to
> match a drifted project.

## Phase 8: Report & Action Plan

Produce a structured findings report:

```markdown
# Context Audit Report

## Inventory
| # | Source | Path | Size | Loading |

## Findings

### 🔴 REDUNDANCY
| ID | Description | Canonical Location | Redundant Location(s) | Recommendation |

### 🟡 AMBIGUITY
| ID | Description | Sources | Recommendation |

### 🟢 CONFLICTS
| ID | Description | Sources | Recommendation |

### 🔵 EFFECTIVENESS
| ID | Description | Impact | Recommendation |

### 🟣 CROSS-REFERENCES
| ID | Description | Stale Reference | Correct Reference |

## Summary Scorecard
| Dimension | Score | Key Issue |

## Action Plan
| Priority | Action | Files Affected | Root Cause Fix |
```

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-14 18:34 | v1.1 — Added Directionality Rule section before Phase 2; updated Phase 7 Decision Table with Fix Direction column and USER-scope-is-canonical principle |
| 2026-07-14 18:12 | v1.0 — Initial checklist from first context audit session |
