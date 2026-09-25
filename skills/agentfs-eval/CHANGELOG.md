# agentfs-eval Changelog


| Updated | Change |
|---------|--------|
| 2026-09-25 01:46 | v1.5.7 — Update template-check.sh: 17 rules, A5 checks Rule 7 instead of Rule 8 |
| 2026-09-25 00:22 | v1.5.6 — B1 test: use 'check headroom status' (no CLI-name collision); document command-shape ambiguity |
| 2026-09-24 22:50 | v1.5.5 — Resilient session cleanup: trap EXIT handler, per-session cleanup fn, orphan sweep on updated_at, DB timeout=5s |
| 2026-09-24 22:13 | v1.5.4 — Exit 0 always + anti-loop warning — prevents weaker models from re-running eval in a loop |
| 2026-09-24 21:14 | v1.5.3 — Update assertion docs: A2 Scopes before Rules, A4 context lookup fallback, A5 search_nodes + load_skill, remove stale A6 |
| 2026-09-24 19:24 | v1.5.2 — SQLite-based test session cleanup instead of goose session remove |
| 2026-09-24 17:25 | v1.5.1 — Fix double-run bug: capture output from single run instead of running checks twice |
| 2026-09-24 17:17 | v1.5.0 — template-eval.sh reads AGENT_SESSION_ID to detect provider/model from current session. Zero args required. Fallback chain: session metadata → config.yaml |
| 2026-09-24 16:51 | v1.4.0 — template-eval.sh accepts --provider/--model args, falls back to config.yaml. Quick Dispatch passes session provider/model. |
| 2026-09-24 16:05 | v1.3.0 — Rename agents-md-* scripts to template-*, add template-eval.sh zero-arg wrapper, add merge-score-entry.sh, simplify Quick Dispatch |
| 2026-09-24 13:03 | v1.2.0 — Add agents-md-check.sh: deterministic AGENTS.md template quality assertions (A1-A9) |
| 2026-08-26 21:34 | v1.1.0 — Added LITE scope awareness: skips skills/profiles L1 checks for LITE projects. |
| 2026-07-13 15:38 | v1.0 — Initial design: three-layer eval (structural, behavioral, semantic), maturity levels L0–L5, explicit trigger only, fresh session recommendation |
