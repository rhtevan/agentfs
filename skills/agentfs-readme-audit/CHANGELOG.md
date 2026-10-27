# agentfs-readme-audit Changelog

| Updated | Change |
|---------|--------|
| 2026-10-27 13:12 | v3.0.1 — v3.0.1: prohibition on direct README reading, absolute paths, stronger imperative, temp file pattern |
| 2026-10-27 11:53 | v3.0.0 — New script: deterministic state gathering for README audit — replaces Steps 0-2, trace-instrumented, dual scope support |
| 2026-09-16 12:11 | v2.1.0 — Added D9/P8 Coverage Gaps dimension — non-blocking signal for unmentioned content |
| 2026-09-11 10:51 | v2.0.0 — Add PROJECT scope support: Step 0 scope resolution from git repo root; PROJECT-specific audit dimensions (P1–P7) replacing USER-only D1–D8; dual report format; graceful skip when no PROJECT README exists; "What This Skill Does NOT Do" updated to remove USER-only limitation |
| 2026-08-20 23:43 | v1.2.0 — Fix trigger logic: run audit whenever agentfs files (skills/, knowledge/, AGENTS.md) are staged — README.md no longer needs to be staged; audit compares existing README against staged changes to detect drift; pre-push-scan.sh Category 7 replaced with README_AUDIT_REQUIRED signal |
| 2026-08-20 22:47 | v1.1.0 — Fix trigger condition: skill runs only when README.md is staged AND staleness = Clean (not on staleness Clean alone); update flow diagram and Integration section |
