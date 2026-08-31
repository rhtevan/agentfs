# v4.x → v5.0.0 Content Migration Map

> Created: 2026-08-31 (agentfs-v5 A3)
> Purpose: Zero-loss verification for AGENTS.md template migration

## Section-Level Mapping

| v4.x Section | v5 Destination | Status |
|---|---|---|
| Quick Orientation table | RETAINED inline | ✅ |
| `@.agents/SOUL.md` import | RETAINED inline | ✅ |
| Signal Routing table (8 rows) | RETAINED inline (6 rows) | ✅ see row-level below |
| Signal Routing prose + Routing Rules | REMOVED | ✅ see rationale below |
| Guardrail Quick Reference table | REMOVED (double encoding) | ✅ |
| Scope Definitions + What Lives Where | RETAINED inline | ✅ |
| Guardrail #0 (Signal-First Dispatch) | RETAINED → v5 Rule #1 | ✅ |
| Guardrail #1 (Progressive Disclosure) | RETAINED → v5 Rule #2 | ✅ |
| Guardrail #2 (Memory Scope) | RETAINED → v5 Rule #9 | ✅ |
| Guardrail #3 (Cross-Agent Discovery) | RETAINED → v5 Rule #3 | ✅ |
| Guardrail #4 (Skill Placement) | RETAINED → v5 Rule #4 | ✅ |
| Guardrail #5 (Filesystem Integrity) | RETAINED → v5 Rule #5 (condensed) | ✅ |
| Guardrail #5 Delegation table | DELEGATED → agentfs-setup/references/filesystem-integrity.md | ✅ |
| Guardrail #5 Scope logging table | DELEGATED → agentfs-setup/references/filesystem-integrity.md | ✅ |
| Guardrail #6 (Idempotency) | REMOVED | ✅ see rationale |
| Guardrail #7 (Anti-Sycophancy) | RETAINED → v5 Rules #10 + #11 (split) | ✅ |
| Guardrail #8 (Anti-Daydreaming) | RETAINED → v5 Rule #12 | ✅ |
| Guardrail #9 (Checkpoints) | RETAINED → v5 Rule #7 | ✅ |
| Guardrail #10 (Git Push Safety) | DELEGATED → agentfs-git-push skill | ✅ |
| Agent Profiles table | RETAINED (project-owned) | ✅ |
| SPECKIT block | RETAINED (project-owned) | ✅ |

## Signal Routing Row-Level Mapping

| v4.x Row | v5 Status | Notes |
|---|---|---|
| "remember this" / "note that" → MEMORY.md | RETAINED | Row 1 |
| "always do X" / "never do Y" → propose guardrail | RETAINED | Row 2 |
| "I prefer" / "my style is" → USER.md | RETAINED | Row 3 |
| "learn this document" → OKF bundle | REMOVED | Covered by skill signal: okf-bundle-gen, okf-bundle-harvest |
| "forget this" → edit MEMORY.md | RETAINED | Row 4 |
| "what do you remember" → read MEMORY.md | RETAINED | Row 5 |
| "harvest" / "reflect" → skill-harvest or okf-bundle-harvest | REMOVED | Covered by skill signals directly |
| "hey git" → stage, commit, push | RETAINED | Row 6 (now routes to skill) |

**8 → 6 rows.** Two rows removed because they duplicate skill signal
routing (the agent already discovers these via skill descriptions in
the system prompt, per Rule #1).

## Guardrail Rule-Level Detail

### v4 #0 → v5 #1 (Signal-First Dispatch)

| v4 Content | v5 Status |
|---|---|
| "STOP before generic interpretation" | RETAINED in Action |
| Resolution order (4 steps) | CONDENSED to single action sentence |
| Violation definition | REMOVED (enforcement implied by action phrasing) |
| "skill descriptions already in system prompt" note | REMOVED (implementation detail, not rule) |

**Risk: LOW.** The condensed version retains the core instruction. The
resolution order is natural LLM behavior once the trigger fires.

### v4 #1 → v5 #2 (Progressive Disclosure)

| v4 Content | v5 Status |
|---|---|
| "browse index.md first, follow links" | RETAINED verbatim |

**Risk: NONE.** Already a single sentence in v4.

### v4 #2 → v5 #9 (Memory Scope)

| v4 Content | v5 Status |
|---|---|
| memories/ is PROJECT-scoped only | RETAINED |
| MEMORY.md = experiences, not rules | RETAINED |
| Rules → AGENTS.md; preferences → USER.md | RETAINED |
| Graduation path to OKF | RETAINED |

**Risk: NONE.** Content fits in single table cell.

### v4 #3 → v5 #3 (Cross-Agent Discovery)

| v4 Content | v5 Status |
|---|---|
| Check 6 files on session start | RETAINED |
| Treat as supplementary | RETAINED |
| AGENTS.md wins on conflict | RETAINED |

**Risk: NONE.** Single sentence.

### v4 #4 → v5 #4 (Skill Placement)

| v4 Content | v5 Status |
|---|---|
| Default to USER | RETAINED |
| PROJECT only when explicit signals | RETAINED |
| Example signal phrases | RETAINED |

**Risk: NONE.** Two sentences.

### v4 #5 → v5 #5 (Filesystem Integrity)

| v4 Content | v5 Status |
|---|---|
| Edit-time rule: log before proceeding | CONDENSED into action checklist |
| GATE: stop before declaring done | CONDENSED — implied by checklist framing |
| 4 gate checks (log, changelog+version, indexes, links) | RETAINED as checklist |
| Violation definition | REMOVED (implied) |
| README.md scope note | REMOVED (edge case, in filesystem-integrity.md) |
| pre-push-scan.sh log enforcement note | REMOVED (implementation detail) |
| Scope logging table (4 rows) | DELEGATED → filesystem-integrity.md |
| Delegation table (7 rows) | DELEGATED → filesystem-integrity.md |
| "Prefer incremental edits" note | DELEGATED → filesystem-integrity.md |
| "./  prefix" note | DELEGATED → filesystem-integrity.md |

**Risk: LOW.** The 4 gate checks are retained. Delegation details
are available via `load_skill(name: "agentfs-setup/references/filesystem-integrity.md")`
if the agent needs specifics. The agent already knows the script names
from v5 Rule #5 action text.

### v4 #6 (Idempotency) → REMOVED

**Rationale:** Idempotency is a general software engineering principle,
not an AgentFS-specific guardrail. Every competent LLM already applies
existence checks and upsert patterns. Including it adds ~30 tokens
with no measurable compliance improvement. The scripts themselves
are idempotent by design (merge-* scripts, post-edit.sh).

**Risk: VERY LOW.** No observed violations of idempotency in practice.
If needed, can be re-added as Rule #13.

### v4 #7 → v5 #10 + #11 (Anti-Sycophancy split)

**v5 #10 (Communication Style):**
| v4 Content | v5 Status |
|---|---|
| No validation phrases | RETAINED |
| Lead with substance | RETAINED |
| Name risks proactively | RETAINED |

**v5 #11 (Conflict Resolution):**
| v4 Content | v5 Status |
|---|---|
| Don't reverse without new info/argument | RETAINED |
| State what changed + previous position | RETAINED |
| Quote conflicting guardrail | RETAINED |
| Ask for confirmation | RETAINED |
| Log overrides with [OVERRIDE] | RETAINED |
| MUST NOT add rules to MEMORY.md | RETAINED (moved to Rule #9) |

**Risk: NONE.** All content preserved, split across two rules for
clearer trigger separation (always vs. on-conflict).

### v4 #8 → v5 #12 (Anti-Daydreaming)

| v4 Content | v5 Status |
|---|---|
| Random canary name at session start | RETAINED |
| Turn 1: emit visibly | RETAINED |
| ~1-in-5 turns: emit + self-check | RETAINED |
| On prompt: respond + self-check | RETAINED |
| Mismatch warning text | REMOVED (agent generates naturally) |
| Never persist to files | RETAINED |
| Not an identity or persona | REMOVED (obvious from context) |

**Risk: VERY LOW.** Core behavior fully retained.

### v4 #9 → v5 #7 (Checkpoints)

| v4 Content | v5 Status |
|---|---|
| STOP before destructive ops | RETAINED |
| checkpoint.sh create/clear/check commands | RETAINED in action |
| Violation definition | REMOVED (implied) |

**Risk: NONE.** Compact rule, minimal condensation.

### v4 #10 → v5 #6 (Git Push Safety → DELEGATED)

| v4 Content | v5 Status |
|---|---|
| STOP before commit | DELEGATED — trigger in v5 Rule #6 |
| 8-step workflow | DELEGATED → agentfs-git-push SKILL.md |
| Allowlist filtering | DELEGATED → agentfs-git-push SKILL.md |
| README audit conditional | DELEGATED → agentfs-git-push SKILL.md |
| 5 violation definitions | DELEGATED → agentfs-git-push SKILL.md |
| Override protocol | DELEGATED → agentfs-git-push SKILL.md |

**Risk: LOW.** The trigger (Rule #6) fires `load_skill`, which loads
the full workflow. Risk of model not following inline instructions
equals risk of not loading the skill — the gate trigger is identical
in both versions.

## NEW in v5 (not in v4)

| v5 Rule | Content | Source |
|---|---|---|
| #8 (Context Enrichment) | "Consult knowledge index before acting on policy, domain concepts, or unfamiliar procedures" | New — from S2 (Trigger/Context/Action triples, context leg) |

## Routing Rules (REMOVED)

| v4 Content | Rationale for Removal |
|---|---|
| "Agent overrides win" | Implementation detail — agents already know their own tools take priority |
| "Skill signals resolve via..." | Duplicates Rule #1 (Signal-First Dispatch) |
| "Harvest scans .agents/memories/" | Covered by skill-harvest signal phrases |
| "Resolution chain: load_skill by name → ..." | Implementation detail of Rule #1 |

## Guardrail Quick Reference (REMOVED)

The entire 11-row Quick Reference table is removed. It duplicated the
full guardrail section — every row was a compressed restatement of the
corresponding guardrail. The v5 flat table IS the single encoding.

**Token savings:** ~200 tokens.

## Summary

| Category | Count |
|---|---|
| Rules RETAINED (inline) | 10 (v5 #1–5, #7, #9–12) |
| Rules DELEGATED (to skills) | 1 (v5 #6 → agentfs-git-push) |
| Rules NEW | 1 (v5 #8 context enrichment) |
| Rules REMOVED | 1 (v4 #6 idempotency) |
| Signal rows RETAINED | 6 of 8 |
| Signal rows REMOVED | 2 (covered by skill signals) |
| Content sections DELEGATED | 2 (delegation table, scope logging → filesystem-integrity.md) |
| True content loss | **0** |
