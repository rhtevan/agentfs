# agentfs-readme-audit Changelog

| Updated | Change |
|---------|--------|
| 2026-08-20 23:43 | v1.2.0 — Fix trigger logic: run audit whenever agentfs files (skills/, knowledge/, AGENTS.md) are staged — README.md no longer needs to be staged; audit compares existing README against staged changes to detect drift; pre-push-scan.sh Category 7 replaced with README_AUDIT_REQUIRED signal |
| 2026-08-20 22:47 | v1.1.0 — Fix trigger condition: skill runs only when README.md is staged AND staleness = Clean (not on staleness Clean alone); update flow diagram and Integration section |
