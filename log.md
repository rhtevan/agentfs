# Directory Update Log

<!-- Append-only. Newest entries at top. -->

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

