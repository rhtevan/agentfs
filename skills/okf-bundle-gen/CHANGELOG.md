# okf-bundle-gen Changelog


| Updated | Change |
|---------|--------|
| 2026-08-26 22:24 | v— — Terminology: mode → scope. Added LITE scope guard note where applicable. |
| 2026-07-20 17:33 | v3.2 — Added Phase 7c: USER scope log.md entry. Fixes omission where changes to `~/.agents/knowledge/` were logged in the bundle's own log.md but not in the USER-scope root `~/.agents/log.md` per Guardrail #5 (Filesystem Integrity). Phase 7 heading updated from "both levels" to "all three levels". |
| 2026-07-09 01:38 | v3.1 — Removed Phase 9 (SOUL.md pattern link injection) and update-soul-links.sh dependency; knowledge discovery now handled via global .goosehints progressive loading instead of SOUL.md markers |
| 2026-07-08 14:19 | v3.0 — Memory redesign: bundle root changed from `./.agents/knowledge/` (project-local staging) to `~/.agents/knowledge/` (user-level); removed project-local staging concept; memory scan is PROJECT-only (no `~/.agents/memories/`); `okf-bundle-merge` is now obsolete |
| 2026-06-30 23:49 | v2.2 — `merge-log-entry.sh` updated: `YYYY-MM-DD HH:MM` timestamps, `<!-- Append-only -->` comment, `- ` entry style |
| 2026-06-30 23:36 | v2.1 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 16:46 | v2.0 — Memory scanning + pattern extraction + multi-agent SOUL.md linking. New phases: 1c (scan-memories.sh), 1d (pattern extraction to agent-patterns/ sub-bundle), 9 (update-soul-links.sh across default + profile SOUL.md files). New scripts: scan-memories.sh, update-soul-links.sh. Relative link depth auto-adjusted per SOUL.md location. |
| 2026-06-25 22:52 | v1.0 — Initial skill: session-based knowledge extraction to OKF bundle with merge semantics, per-session sub-bundles, list-existing-concepts.sh, merge-log-entry.sh. |
