# Changelog — skill-eval

| Updated | Change |
|---------|--------|
| 2026-11-08 16:57 | v2.3.0 — Add tier-aware qoo-qualified computation; Update Step 10 with tier-aware qualification formula |
| 2026-11-05 19:31 | v2.2.0 — Add model-tier to frontmatter |
| 2026-10-31 22:28 | v2.2.0 — Add assess skill mode — chains score+eval into single comprehensive assessment; Bump metadata version to 2.2.0; Add Assess mode to Quick Dispatch; Add Assess Sequence — 11-step comprehensive assessment mode |
| 2026-10-31 20:37 | v2.1.0 — Step 8: added deterministic qoo-qualified formula — Tunable+ on quality, observable, operable.build; runtime exempt; Bump frontmatter version to 2.1.0; Rename: 'upgrade skill' → 'score skill' in ownership table |
| 2026-10-31 19:04 | v2.0.0 — skill-eval v2.0.0: QOO re-engineering — Tier 1 BMBT + Quality/Observable read + Tier 2 CECX runtime + eval skill dispatch + persist + consolidated report; Added --phase build flag to BMBT sdm-evaluate.sh call; Added model and trace fields to Step 8 persist — CECX scores are model-dependent |
| 2026-10-02 15:06 | v1.0.0 — New skill: skill-eval v1.0.0 — deterministic checks S01-S22 (P1-P7), LLM rubrics S23-S26. Refactored out of agentfs-eval R4. |

## 2026-10-31 v2.0.0

- **BREAKING:** New eval sequence — `hey eval skill` now runs full QOO evaluation (Tier 0 + Tier 1 + Tier 2)
- Added Quick Dispatch: `check skill` = Tier 0 only, `eval skill` = full eval
- Added Tier 1: BMBT build-time operable via `gather-skill-state.sh` + `sdm-evaluate.sh operable.yaml`
- Added Tier 1: Quality + Observable computed fresh for report (read-only, not persisted — owned by skill-gen)
- Added Tier 2: CECX runtime operable from `.traces/` JSONL via `sdm-evaluate.sh operable.yaml`
- Added Step 8: Persist `operable` section to `scores.yaml` (preserves quality/observable owned by skill-gen)
- Added Step 9: Consolidated report with QOO Summary table (all axes, per-axis bands)
- Added QOO Axis Ownership table documenting scores.yaml section ownership
- Kept Tier 0 unchanged: S01-S22 deterministic + S23-S26 LLM rubric

## 2026-10-02 v1.0.0

- Initial release: deterministic checks S01–S22 covering all 7 skill-gen principles
- LLM rubric checks S23–S26 for prose-to-script, duplicate procedures, prompt injection, logical sequence
- Two modes: single skill (`hey check skill <name>`) and all skills (`hey check all skills`)
- Refactored out of `agentfs-eval` R4 (skill-accuracy) — clean separation of concerns
