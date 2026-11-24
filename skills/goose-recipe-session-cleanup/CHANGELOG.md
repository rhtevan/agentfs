# goose-recipe-session-cleanup Changelog

| Updated | Change |
|---------|--------|
| 2026-11-24 12:40 | v3.2.2 — delete.sh 1.1.0: child tables discovered from the schema (thread_messages no longer exists; crashed with 'no such table'); version 3.2.2 (delete.sh schema fix) |
| 2026-11-17 22:20 | v3.2.1 — F4: delete thread_messages and session_tags too (FK cascade is off; left orphan rows) |
| 2026-11-09 10:49 | v3.2.0 — New script: scan Goose sessions DB by category (recipe/terminal/hidden/desktop) with date filter and trace instrumentation; New script: delete Goose sessions by category with --recipe/--terminal/--hidden/--desktop/--all flags, date filter, tracked session protection |
| 2026-11-08 22:50 | v3.1.0 — Add Rules + trace |
| 2026-11-05 19:31 | v3.0.0 — Add model-tier to frontmatter |


| Date | Change |
|------|--------|
| 2026-07-30 | v3.0 — Desktop sessions now eligible for cleanup on explicit request; added ③ Hidden to deletable categories; added `SKIP_TRACKED` safety default for projects.json sessions; signal routing table for category selection; "clean all sessions" support |
| 2026-07-30 | v2.1 — Fixed SQL alias bugs in scan script; split `date_filter` / `date_filter_s` for joined vs non-joined queries |
| 2026-07-30 | v2.0 — Report shows 4 distinct sections; added optional `before_date` filter; configurable deletion flags; VACUUM only on bulk deletes |
| 2026-07-30 | v1.1 — Rewrote for SQLite DB storage (sessions.db), not .jsonl files; added terminal session cleanup; added usage_ledger cleanup; added VACUUM |
| 2026-07-30 | v1.0 — Initial creation (assumed .jsonl file storage) |
