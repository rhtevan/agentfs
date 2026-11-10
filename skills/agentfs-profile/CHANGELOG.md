# agentfs-profile Changelog


| Updated | Change |
|---------|--------|
| 2026-11-09 20:31 | v1.12.0 — Added Rules, Workflow CNL Steps 1-2 (create/recipe), Output Contract; Add --dry-run flag parsing and strip from positional args; Add --dry-run pre-check block with DRY_RUN_RESULT signals; Add DRY_RUN/CHANGES/ERRORS variables; Add --dry-run/--check to arg parser; Add dry-run exit block with DRY_RUN_RESULT signal before file write |
| 2026-11-08 22:37 | v1.11.0 — Add Rules, bump to 1.11.0; Add trace-lib.sh; Add trace-lib.sh |
| 2026-11-05 19:30 | v1.10.0 — Add model-tier to frontmatter |
| 2026-08-26 21:34 | v1.10.0 — Added LITE scope guard: create-profile.sh refuses in LITE scope projects. Standardized terminology: mode → scope. |
| 2026-08-20 00:00 | v1.9.0 — Refactor create-profile.sh to delegate SOUL authoring to author-soul.sh; add recipe.yaml placeholder generation with SOUL content + identity override header; add output/ directory; add gen-profile-recipe.sh for on-demand task recipe generation |
| 2026-07-08 13:38 | v1.8 — Updated MEMORY.md template to "Project Experiences" with scope/NL-signal guidance; removed `.agents/knowledge/` references (knowledge is USER-scoped) |
| 2026-07-01 00:07 | v1.7 — `create-profile.sh` now updates profile count in `profiles/index.md` summary line |
| 2026-06-30 23:36 | v1.6 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 23:31 | v1.5 — Renamed index column `Added` → `Updated`; timestamp precision `YYYY-MM-DD HH:MM`; log.md entries use timestamp headings |
| 2026-06-30 23:16 | v1.4 — `profiles/index.md` schema now has Identity + Memories + Updated columns; entries inserted newest-first (reverse chronological); `create-profile.sh` updated to match; After Creation section expanded |
| 2026-06-30 18:30 | v1.3 — `create-profile.sh` registers profiles in `profiles/index.md`; `memories/` links now point to `memories/MEMORY.md` |
| 2026-06-30 17:45 | v1.2 — `create-profile.sh` now appends to `.agents/log.md` per the Log Currency guardrail |
| 2026-06-30 15:30 | v1.1 — Auto-register profiles in AGENTS.md Agent Profiles table; idempotent duplicate detection |
| 2026-06-30 14:00 | v1.0 — Initial skill: create named agent profiles with SOUL.md + memories/ |
