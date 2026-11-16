# Changelog

| Updated | Change |
|---------|--------|
| 2026-11-16 14:54 | v2.1.1 — Troubleshooting row for the pre-7.9.3 confidence-float PII false positive; Troubleshooting row for the pre-7.9.3 confidence-float PII false positive. |
| 2026-11-16 14:14 | v2.1.0 — S3: scan covers the unpushed commit range, not just the index; Step 2: document auto/range modes, exit 2, and the mandatory Scan scope check; Troubleshooting: add false-CLEAN and exit-2 rows; Add T7: clean tree with unpushed secret must be caught, not reported as no-changes; Step 2: document pre-push-scan --mode auto|range, exit code 2, and the mandatory 'Scan scope:' check; S3 widened to the unpushed range; add T7 and two troubleshooting rows for the false-CLEAN case |
| 2026-11-08 22:19 | v2.1.0 — Add Rules section with anti-fabrication for Observable compliance; Bump version to 2.1.0; Add trace-lib.sh instrumentation; Add trace_step and trace_end |
| 2026-11-05 19:30 | v2.0.1 — Add model-tier to frontmatter |
| 2026-10-15 21:44 | v2.0.1 — Sync frontmatter version to match CHANGELOG latest (2.0.0 → 2.0.1) |
| 2026-09-29 21:46 | v2.0.1 — Step 6: explicit instruction to render tool output in response message |
| 2026-09-29 21:27 | v7.2.0 — v7.2.0 — rules consolidated 10→8, severity tags removed |
| 2026-09-28 11:33 | v2.0.0 — Skill Check overhaul: added scripts/resolve-target.sh (P1 — deterministic target resolution), opening paragraph, Specification table (S1–S9), Tests table (T1–T6), Error Handling table with idempotency declarations, Troubleshooting table, pre-push-scan.sh exit code contract, commit message guidance, user-invocable frontmatter fields |
| 2026-08-31 17:28 | v1.1.0 — Add Step 0 (Resolve Target): default to ~/.agents/ for bare "hey git"; confirm if CWD differs |
| 2026-08-31 15:40 | v1.0.0 — Initial creation — absorbs Git Push Safety workflow from AGENTS.md Guardrail #10 (v4.x) |
