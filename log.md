# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## 2026-10-23 22:09
- G3 revised: universal QOO schemas, async on-demand evaluation, scores.yaml, qoo-profile.yaml, updated flow diagram (skills/agentfs-setup/references/design-spec.md)
- Revised: Phase 0 remaining items (0.7-0.11), QOO terminology, corrected Phase 1 items, qoo-profile.yaml in Phase 2, scores.yaml persistence, updated dependency graph (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- Updated Observable Property: universal schemas, async evaluation, scores.yaml, no per-skill schemas (knowledge/agentfs-engineering-evolution/operable-skill-architecture.md)
- Revised: universal observation schema, async-only evaluation, qoo-profile.yaml, scores.yaml persistence, two-tier evidence, QOO terminology (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-23 14:03
- Modified: ~/.agents/skills/skupper-model-provider/docs/van-topology.architecture.html — regenerated via archify deliver
- Modified: ~/.agents/skills/skupper-model-provider/docs/van-topology.architecture.json — updated site names, model, CRC listener labels

## 2026-10-23 14:02
- Modified: ~/.agents/skills/crc-ols/scripts/list.sh — naming convention alignment
- Modified: ~/.agents/skills/skupper-model-provider/scripts/test-model.sh — naming convention alignment
- Modified: ~/.agents/skills/skupper-model-provider/scripts/teardown.sh — naming convention alignment
- Modified: ~/.agents/skills/skupper-model-provider/scripts/down.sh — naming convention alignment
- Modified: ~/.agents/skills/skupper-model-provider/scripts/up.sh — naming convention alignment
- Modified: ~/.agents/skills/skupper-model-provider/scripts/setup.sh — naming convention alignment
- Modified: ~/.agents/skills/skupper-model-provider/scripts/common.sh — naming convention alignment

## 2026-10-23 13:49
- Comprehensive known issue report: connector status Not Matched on rhel-ai — root cause traced to missing ConfigMap from tmpfs workaround (skills/skupper-model-provider/references/known-issues.md)

## 2026-10-23 12:33
- Add connector status Not Matched bug (GitHub #2428, partial fix in v2.2.3) (skills/skupper-model-provider/references/known-issues.md)

## 2026-10-23 12:13
- v9.1.0 — Naming convention alignment: all Skupper resources renamed per references/naming-convention.md. Consolidated rhel-ai RouterAccess (2→1). Updated connectors, listeners, RouterAccess, CRC listeners, OLS URLs, and all script references. (skills/skupper-model-provider/scripts/status.sh)

## 2026-10-23 11:40
- New: Skupper VAN naming convention covering all resource types (skills/skupper-model-provider/references/naming-convention.md)
- Add cross-reference to naming convention (skills/skupper-model-provider/references/architecture.md)
- Add naming convention to references list (skills/skupper-model-provider/SKILL.md)
- Add naming convention to references list (skills/skupper-model-provider/SKILL.md)
- Add cross-reference to naming convention (skills/skupper-model-provider/references/architecture.md)
- New: Skupper VAN naming convention covering all resource types (skills/skupper-model-provider/references/naming-convention.md)

## 2026-10-22 22:00
- Fixed race condition: added flock serialization and mktemp unique temp files to prevent log history wipe during concurrent post-write calls (skills/agentfs-setup/scripts/merge-log-entry.sh)

## 2026-10-22 21:56
- Fixed merge-log-entry.sh race condition: added flock serialization and mktemp unique temp files. Prevents log history wipe when multiple post-write calls target the same log concurrently. (skills/agentfs-setup/scripts/merge-log-entry.sh)

## 2026-10-22 21:48
- New script: ensure-kgm-symlink.sh — self-healing symlink enforcement for MCP server memory.jsonl (skills/goose-kgm/scripts/ensure-kgm-symlink.sh)
- Refactored setup-kgm.sh to use ensure-kgm-symlink.sh shared script (skills/goose-kgm/scripts/setup-kgm.sh)
- Added ensure-kgm-symlink.sh call after reindex to self-heal broken symlinks (skills/goose-kgm/scripts/reindex-kgm.sh)
- Added symlink health check section to status-kgm.sh (skills/goose-kgm/scripts/status-kgm.sh)
- Bumped goose-kgm to v1.5.0 (skills/goose-kgm/SKILL.md)

## 2026-10-22 21:11
- Bumped version to 7.4.0; updated Structural Guardrails section to reflect re-engineered Pre-Flight rule (skills/agentfs-setup/SKILL.md)
- Bumped version to 7.4.0; updated Structural Guardrails section to reflect re-engineered Pre-Flight rule (skills/agentfs-setup/SKILL.md)
- Re-engineered Pre-Flight rule: two-tier specification-driven planning with Design Spec validation gate; added explicit rule scan instruction to Rules preamble; added condensed spec-driven rule to LITE template (skills/agentfs-setup/scripts/seed-agents-md.sh)

## 2026-10-22 20:20
- Updated implementation plan: Phase 0 complete with test results, learnings, bugs fixed. Phases 1-4 detailed with specific file paths, changes, and session resumption guide. (knowledge/agentfs-engineering-evolution/implementation-plan.md)

## 2026-10-22 20:07
- Phase 0.5/0.6: Created sdm-endpoint.md in skills/schemas/
- Phase 0.5/0.6: Created README.md in skills/schemas/
- Phase 0.5/0.6: Created operable.yaml in skills/schemas/
- Phase 0.5/0.6: Created quality.yaml in skills/schemas/
- Phase 0.5: Universal MCACS quality schema — 6 dimensions mapped to MCACS principles (skills/schemas/quality.yaml)
- Phase 0.4: Multi-dimension evaluator — processes quality/operable/observation schemas via SDM (scripts/sdm-evaluate.sh)
- Phase 0.3: Agent-agnostic trace capture library — trace_init, trace_step, trace_end (scripts/trace-lib.sh)
- Phase 0.2: SDM call script — single/batch decision calls via NextToken API (scripts/sdm-call.sh)

## 2026-10-22 19:56
- Corrected Section 17.7: NextToken supports score-type questions (skills/hosted-model-ctl/references/benchmark-report.md)
- Corrected score-type claim: NextToken also supports score questions (knowledge/llm-inference-constrained-gpu/d3-decision-model-deployment.md)
- Corrected Section 17.7: NextToken supports score-type questions (skills/hosted-model-ctl/references/benchmark-report.md)

## 2026-10-22 17:42
- Refined G3 to Observable Skill & Skill Evolution, added three-schema table, Observable Skill design cross-reference (skills/agentfs-setup/references/design-spec.md)
- Added Observable Property section with observation.yaml, trace_step, two-phase evaluation, schema locations (knowledge/agentfs-engineering-evolution/operable-skill-architecture.md)
- New concept: Implementation Plan — 5-phase plan from SDM foundation through maturity (knowledge/agentfs-engineering-evolution/implementation-plan.md)
- New concept: Observable Skill Design — agent-agnostic audit trail, two-phase observation, three schema types, score persistence (knowledge/agentfs-engineering-evolution/observable-skill-design.md)

## 2026-10-21 16:25
- Removed Networking category row — skupper-linux-two-site skill deleted, capability covered under Model Serving (README.md)

## 2026-10-21 16:18

- Removed skills/skupper-linux-two-site/ — superseded by skupper-model-provider; updated skills/index.md (61 → 60 skills)

## 2026-10-21 14:23
- v9.0.0: Updated diagram with new site/link naming convention (skills/skupper-model-provider/topology.env.example)
- v9.0.0: Extracted from SKILL.md — debugging procedures, cert chain checks (skills/skupper-model-provider/references/troubleshooting.md)
- v9.0.0: Extracted from SKILL.md — VAN topology, site config, link naming (skills/skupper-model-provider/references/architecture.md)
- v9.0.0: Extracted from SKILL.md — signal routing, scoping, partial availability (skills/skupper-model-provider/references/agent-orchestration.md)
- v9.0.0: Full action plan — all 8 phases completed (skills/skupper-model-provider/ACTION-PLAN-v9.md)

## 2026-10-21 14:14
- v9.0.0: Fix inject_inter_router_listener dynamic sslProfile, fix regenerate_local_server_cert to use issuers/ path (skills/skupper-model-provider/scripts/common.sh)
- v9.0.0: Add observer flow state and metrics population known issues (skills/skupper-model-provider/references/known-issues.md)
- v9.0.0: Add observer pod restart in Phase 7 after auto-restart patches (skills/skupper-model-provider/scripts/setup.sh)

## 2026-10-21 12:46
- v9.0.0: Complete — all 8 phases done. Site rename, link naming, upgrade 2.2.3, ad-hoc fix codification, skill-gen compliance, CRC rebuild, v2.2.3 regression verification (skills/skupper-model-provider/SKILL.md)

## 2026-10-21 12:23
- v9.0.0: New script — CRC baseline detection, CLI download, image pull, container recreation (skills/skupper-model-provider/scripts/upgrade.sh)
- v9.0.0: New CRC resource names, local link cleanup (skills/skupper-model-provider/scripts/teardown.sh)
- v9.0.0: New link names in Links/CRC sections (skills/skupper-model-provider/scripts/status.sh)
- v9.0.0: New CRC link names (skills/skupper-model-provider/scripts/down.sh)
- v9.0.0: New CRC link names, staleness detection on Pending links, inter-router listener guard (skills/skupper-model-provider/scripts/up.sh)
- v9.0.0: New site/link names, Phase 3b inter-router listener injection + SAN cert regeneration, CRC local link/listener setup (skills/skupper-model-provider/scripts/setup.sh)
- v9.0.0: New site names (drop hub- prefix), LINK_NAMES array, SKUPPER_ROUTER_VERSION env var, inter-router injection, SAN regeneration, CRC staleness detection helpers (skills/skupper-model-provider/scripts/common.sh)

## 2026-10-21 12:23
- v9.0.0: New script — CRC baseline detection, CLI download, image pull, container recreation (skills/skupper-model-provider/scripts/upgrade.sh)
- v9.0.0: New CRC resource names, local link cleanup (skills/skupper-model-provider/scripts/teardown.sh)
- v9.0.0: New link names in Links/CRC sections (skills/skupper-model-provider/scripts/status.sh)
- v9.0.0: New CRC link names (skills/skupper-model-provider/scripts/down.sh)
- v9.0.0: New CRC link names, staleness detection on Pending links, inter-router listener guard (skills/skupper-model-provider/scripts/up.sh)
- v9.0.0: New site/link names, Phase 3b inter-router listener injection + SAN cert regeneration, CRC local link/listener setup (skills/skupper-model-provider/scripts/setup.sh)
- v9.0.0: New site names (drop hub- prefix), LINK_NAMES array, SKUPPER_ROUTER_VERSION env var, inter-router injection, SAN regeneration, CRC staleness detection helpers (skills/skupper-model-provider/scripts/common.sh)

