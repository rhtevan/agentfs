# agentfs-setup Changelog


| Updated | Change |
|---------|--------|
| 2026-08-16 13:26 | v3.14.0 — Moved `merge-log-entry.sh` from `okf-bundle-gen` to `agentfs-setup` (foundational skill owns shared utilities). Updated 17 references across 6 skills. Removed Root Log Format subsection from Guardrail #5 (mechanics now in script). Updated delegation table: root logs use `merge-log-entry.sh`, skills index uses `post-edit.sh`. Template version 3.13→3.14. |
| 2026-08-15 11:57 | v3.13.0 — Added `post-edit.sh` script: automates fragile post-edit steps (skills index regeneration, log.md anchor validation). Guardrail #5 STOP block now references `post-edit.sh` instead of delegation table. Quick Reference row updated. Follows skill-gen principle: loose steps → instructions, fragile steps → code. |
| 2026-08-14 19:40 | v3.12.0 — Removed Post-Edit Completeness subsection from Guardrail #5 (redundant with delegation table). STOP block moved to top as one-liner. 64→45 lines. Template version 3.11→3.12. |
| 2026-08-14 19:19 | v3.11.0 — Rewrote Guardrail #5 (Filesystem Integrity): replaced 4 subsections (Link Integrity, Log & Changelog Currency, Index Currency, Post-Edit Completeness) with 4 focused sections (Editing Rules, Log & Index Delegation table, Root Log Format, Post-Edit Gate). Added delegation table mapping every log/index file to its owning skill and update method. Removed 26 lines of redundancy. Updated Quick Reference row. Template version 3.10→3.11. |
| 2026-08-12 22:55 | v3.10.1 — Guardrail #5 (Log & Changelog Currency): added 24-hour format hint with `date` command to ISO 8601 timestamp rule. Index Currency: consolidated `skill-index` requirement into the MUST-stay-current bullet (removed separate bullet); explicit `load_skill(name: "skill-index")` call-out. |
| 2026-08-11 11:48 | v3.10.0 — Added Guardrail Type System (Gate 🚧, Rule ⚖️, Habit 🔄): Type column in Quick Reference table with verb-chain Key Actions; type badges on all 10 guardrail headings; gate blockquote notices on #5 (Filesystem Integrity), #9 (Checkpoints), #10 (Git Push Safety); design-spec updated with type rationale and Trigger/Invariant collapse analysis; template version 3.9→3.10 |
| 2026-08-08 10:55 | v3.9.0 — Added "Never improvise when a skill exists" routing rule; added "Backup untracked files" to Guardrail #9 (Checkpoints); template version 3.8→3.9 |
| 2026-08-04 19:40 | v3.8.1 — Strengthened Index Currency guardrail in AGENTS.md template: explicitly prohibits ad-hoc scripts for index generation; requires `load_skill` and following `skill-index` instructions |
| 2026-07-31 21:42 | v3.8 — Added Guardrail #8 Anti-Daydreaming (ephemeral session canary name for context-drift detection); renumbered Checkpoints → #9, Git Push Safety → #10; clarified Index Currency trigger to include metadata-only changes; updated design-spec and all cross-references |
| 2026-07-27 17:10 | v3.7 — Added `metadata.signals` frontmatter field spec to design-spec; slimmed Signal Routing table to LLM-direct + ambiguous routes only (11→9 rows); added skill discovery note for signal-routed intents; added template version stamp (`<!-- agentfs-template-version: X.Y -->`); added `--sync` mode for updating existing AGENTS.md from latest template; added project-owned section markers; added `metadata.signals` to SKILL.md frontmatter |
| 2026-07-15 16:50 | v3.6 — Added Guardrail Quick Reference table after Signal Routing: one-line scannable checklist with anchor links to detailed guardrail sections; promotes post-edit discipline and all 9 guardrails to high-attention position |
| 2026-07-15 15:00 | v3.5 — AGENTS.md template: promoted Signal Routing to standalone section after Quick Orientation (was under Guardrail #2); renamed Guardrail #2 to "Memory Scope"; added "hey git" signal; added Post-Edit Completeness sub-section to Guardrail #5; added log insertion anchor rule; changed knowledge index link to backtick format (no more `[blocked]` in renderers) |
| 2026-07-14 19:26 | v3.4 — AGENTS.md template compacted 277→207 lines (25%): removed Resolves To column and Rule of Thumb blockquote from Scope Definitions; dropped Executor/Scope columns from routing table; collapsed Skill Resolution Chain; merged Content File Currency into Log & Changelog Currency; replaced Git Push Safety verbose template with compact 5-step list; updated sed insertion block for Scope Definitions |
| 2026-07-14 17:49 | v3.3 — AGENTS.md template consolidated from 13 to 9 guardrails (reordered by usage frequency): merged Memory Scope + Signal Routing into #2, merged Link/Log/Changelog/Index integrity into #5 (Filesystem Integrity); Quick Orientation now includes SOUL.md and knowledge index for agent-agnostic progressive loading; removed redundant skill-placement and log-scope restatements |
| 2026-07-14 15:22 | v3.2 — AGENTS.md template now includes thirteen guardrails (was nine): added #10 Idempotency, #11 Checkpoints & Resumability, #12 Anti-Sycophancy, #13 Git Push Safety (mandatory 5-step preflight before any git push) |
| 2026-07-13 15:44 | v3.1 — Git init now runs by default in PROJECT mode (calls init-git.sh at project root); .gitignore no longer excludes .agents/memories/ (full audit trail); updated for agentfs-eval compatibility |
| 2026-07-10 18:07 | v3.0 — PROJECT is now the default mode; added canonical Scope Definitions section; documented two USER setup paths (full clone vs minimal install); added Prerequisites section; AGENTS.md template now includes Scope Definitions; nine guardrails (was eight) |
| 2026-07-08 13:38 | v2.10 — Recreated SKILL.md after accidental deletion; reflects memory redesign (knowledge USER-only, memories PROJECT-only, 8 guardrails, updated layer reference) |
| 2026-07-07 16:52 | v2.9 — Added Cross-Agent Context Discovery guardrail (§7) to AGENTS.md template |
| 2026-06-30 23:49 | v2.7 — Expanded guardrail §2: explicit USER/PROJECT/sub-bundle scope; mandatory skill/concept change logging |
| 2026-06-30 23:36 | v2.6 — Changelog tables now use `Updated` header and `YYYY-MM-DD HH:MM` timestamps |
| 2026-06-30 23:31 | v2.5 — Renamed index column `Added` → `Updated`; timestamp precision `YYYY-MM-DD HH:MM` |
| 2026-06-30 23:16 | v2.4 — Added Index Currency guardrail (§6); expanded Profiles Layer |
| 2026-06-30 18:30 | v2.3 — Added `profiles/index.md`; fixed link targets |
| 2026-06-30 17:30 | v2.2 — Idempotent re-run verify `--fix` mode |
| 2026-06-30 15:30 | v2.1 — Added Agent Profiles table to AGENTS.md |
| 2026-06-30 14:00 | v2.0 — Renamed modes; `memory/` → `memories/`; `roles/` → `profiles/`; added SOUL.md, USER.md, MEMORY.md |
| 2026-06-26 22:00 | v1.1 — Added optional git/spec-kit init; verify script |
| 2026-06-26 14:00 | v1.0 — Initial design: USER/PROJECT dual-mode |
