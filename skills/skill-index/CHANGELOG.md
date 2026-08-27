# skill-index Changelog


| Updated | Change |
|---------|--------|
| 2026-08-26 22:24 | v— — Terminology: mode → scope. Added LITE scope guard note where applicable. |
| 2026-08-16 16:22 | v4.0.0 — Replaced 180-line procedural prose with invocation of canonical `regen-skill-index.py` script (DRY with `post-edit.sh`). SKILL.md 175→57 lines. |
| 2026-08-13 12:35 | v3.0.0 — Breaking: index columns changed from `Skill \| Tags \| Signals \| Updated` to `Skill \| Tags \| Description \| Updated`; Description column populated from `description` frontmatter field (signal phrases) instead of `metadata.signals`; removed `metadata.signals` extraction code (state machine parser); added Step 5 to warn on legacy `metadata.signals` field; updated verification checklist |
| 2026-08-06 20:58 | v2.4.0 — Fixed signals extraction bug: replaced fragile metadata block regex (`((?:[ \t]+.*(?:\n|$))*)`) with line-by-line state machine parser; regex silently failed due to Python `$` escaping causing zero-length match on `metadata:` block, resulting in empty Signals columns; new approach correctly handles signals at any position including last field before `---` |
| 2026-08-04 23:52 | v2.3.0 — Added `metadata.version` presence validation; emits warning for skills missing `metadata.version`; references canonical schema (`skill-gen/references/skill-schema.md`) |
| 2026-08-04 19:20 | v2.2 — Documented two implementation bugs: (1) metadata block regex must use `(?:\n|$)` not just `\n` to capture last-line signals before closing `---`; (2) table generation must not embed trailing `\n` in lines list elements to avoid blank-row between header and data |
| 2026-08-04 19:10 | v2.1 — Clarified that signals MUST be extracted from `metadata.signals` (nested), NOT top-level `signals` — the YAML nesting matters; previous ambiguity caused empty Signals columns during index generation |
| 2026-07-27 18:25 | v2.0 — Removed Description column from generated index (already in built-in skills listing; avoids token duplication); Signals column now primary discovery mechanism; every skill MUST have signals |
| 2026-07-27 17:15 | v1.9 — Added Signals column to generated index; extract `metadata.signals` from YAML frontmatter; supports signal-based skill discovery for non-obvious intent routing |
| 2026-07-14 14:56 | v1.8 — Added name-directory consistency validation (step 4): warns when `name` field doesn't match directory name per Agent Skills open standard (agentskills.io/specification). Added verification check. Fixed step numbering. |
| 2026-07-13 13:30 | v1.7 — Added Tags column to generated index; extract `metadata.tags` from YAML frontmatter; supports tag-based skill discovery for Guardrail #9 fallback routing |
| 2026-07-08 22:42 | v1.6 — Clarified multi-line YAML scalar handling (description: > requires collecting indented continuation lines; sed cannot do this); improved fallback to skip table/rule/blockquote lines |
| 2026-07-01 00:07 | v1.5 — Generated index now shows total skill count in summary line (`> N skills \| Sorted by…`) |
| 2026-06-30 23:36 | v1.4 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 23:31 | v1.3 — Renamed column `Added` → `Updated`; timestamp precision `YYYY-MM-DD HH:MM` |
| 2026-06-30 23:16 | v1.2 — Renamed `Date` column to `Added`; added `> Sorted by reverse chronological order` header to generated index; aligns with Index Currency guardrail (AGENTS.md §6) |
| 2026-06-30 16:46 | v1.1 — Added skill location selection: default to USER (`~/.agents/skills/`), PROJECT (`./.agents/skills/`) only when user explicitly signals project scope |
| 2026-06-25 22:52 | v1.0 — Initial skill: scan, extract metadata, generate index.md |
