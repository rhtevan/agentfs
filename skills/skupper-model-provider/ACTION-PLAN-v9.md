# Skupper Model Provider v9.0.0 — Action Plan

Created: 2026-10-21

## Baseline (from CRC)

- Operator: v2.2.3-rh-1
- Router: 3.5.3-rh-1
- Controller: v2.2.3-rh-1
- Upstream targets: CLI 2.2.3, router 3.5.3, controller 2.2.3

## Site Names

| Site Name | Platform |
|-----------|----------|
| `local-ezhang` | Podman |
| `rhel-ai` | Podman |
| `rhtevan-work` | Podman |
| `crc-ezhang` | Kubernetes |

No aliases. One name per site, used everywhere.

## Link Naming: `link-<source-site>-<destination-site>`

| Link Name | From → To |
|-----------|-----------|
| `link-local-ezhang-rhel-ai` | local-ezhang → rhel-ai |
| `link-local-ezhang-rhtevan-work` | local-ezhang → rhtevan-work |
| `link-crc-ezhang-rhel-ai` | crc-ezhang → rhel-ai |
| `link-crc-ezhang-local-ezhang` | crc-ezhang → local-ezhang |

## Full Name Change Reference

| Resource Type | Old Name | New Name |
|--------------|----------|----------|
| Site | `hub-rhel-ai` | `rhel-ai` |
| Site | `hub-rhtevan-work` | `rhtevan-work` |
| Link (localhost→rhel-ai) | `link-hub-rhel-ai` | `link-local-ezhang-rhel-ai` |
| Link (localhost→rhtevan-work) | `link-hub-rhtevan-work` | `link-local-ezhang-rhtevan-work` |
| Link (CRC→rhel-ai) | `link-hub-rhel-ai` | `link-crc-ezhang-rhel-ai` |
| Link (CRC→localhost) | `link-local-ezhang` | `link-crc-ezhang-local-ezhang` |
| Secret (localhost→rhel-ai) | `link-hub-rhel-ai` | `link-local-ezhang-rhel-ai` |
| Secret (localhost→rhtevan-work) | `link-hub-rhtevan-work` | `link-local-ezhang-rhtevan-work` |
| Secret (CRC→rhel-ai) | `link-hub-rhel-ai` | `link-crc-ezhang-rhel-ai` |
| Secret (CRC→localhost) | `link-local-ezhang` | `link-crc-ezhang-local-ezhang` |
| Cert profile | `link-hub-rhel-ai-profile` | `link-local-ezhang-rhel-ai-profile` |
| Cert profile | `link-hub-rhtevan-work-profile` | `link-local-ezhang-rhtevan-work-profile` |
| RouterAccess (rhel-ai) | `hub-rhel-ai` | `rhel-ai` |
| RouterAccess (rhel-ai public) | `hub-rhel-ai-public` | `rhel-ai-public` |
| RouterAccess (rhtevan-work) | `hub-rhtevan-work` | `rhtevan-work` |
| RouterAccess (localhost) | `skupper-local` | `local-ezhang` |
| Client cert dir (rhel-ai) | `client-hub-rhel-ai-public` | `client-rhel-ai-public` |
| Client cert dir (rhtevan-work) | `client-hub-rhtevan-work` | `client-rhtevan-work` |

## Phases

### Phase 0: Pre-flight ✅ DONE

- CRC baseline queried
- Models verified running (qw14b-40k on rhel-ai, g3b on rhtevan-work)

### Phase 1: Skill Restructure (P6 Context Economy)

- [x] Create `references/` directory (DONE)
NOTE: All Phase 1 items below are DONE as of 2026-10-21 11:41
- [ ] Extract `references/architecture.md`
      - SKILL.md sections: "## Architecture" (lines 22-60), "## Host-Based Routing" (lines 62-73), "## Site Configuration" (lines 75-92)
- [ ] Extract `references/known-issues.md`
      - SKILL.md section: "## Known Issues & Workarounds" (lines 310-382) — entire table
- [ ] Extract `references/agent-orchestration.md`
      - SKILL.md sections: "## Agent Orchestration" (lines 105-196) — all subsections: Site Roles, Signal Routing Rules, Scoping Rules, Name Resolution, Error Handling, Partial Availability, Startup Order, Shutdown Order
- [ ] Extract `references/troubleshooting.md`
      - Link to POSTMORTEM.md, add debugging procedures from session discoveries
- [ ] Slim SKILL.md to ≤300 lines
      - KEEP: frontmatter, opening paragraph, "## Script Separation" table, "## Operations" section, "## Specification" table, "## Tests" table, "## Prerequisites", "## Relationship to Other Skills", "## Changelog"
      - ADD: "## References" section linking to all 4 reference files
      - ADD: "## Error Handling" table (P7)
      - ADD: "## Troubleshooting" table (P7)
      - REPLACE: Architecture/Host-Based Routing/Site Config with one-line ref link
      - REPLACE: Agent Orchestration with one-line ref link
      - REPLACE: Known Issues with one-line ref link

### Phase 2: Script Updates ✅ DONE

- [x] Rename sites in `topology.env.example` and `common.sh`
- [x] Rename links: `link-<src>-<dst>` convention in `common.sh` (LINK_NAMES array)
- [x] Remove all short aliases from `common.sh` (no aliases, single vocabulary)
- [x] Update `setup.sh` — new site/link names, Phase 3b inter-router+SAN, CRC local link setup
- [x] Update `up.sh` — new CRC link names, staleness detection, inter-router guard
- [x] Update `down.sh` — new CRC link names
- [x] Update `status.sh` — new link names in Links/CRC sections
- [x] Update `teardown.sh` — new CRC resource names, local link cleanup
- [x] Add inter-router listener injection to `setup.sh` Phase 3b
- [x] Add server cert SAN regeneration to `setup.sh` Phase 3b
- [x] Add CRC link secret staleness detection to `up.sh` (CA fingerprint comparison)
- [x] Add inter-router listener guard to `up.sh` CRC phase
- [x] Create `upgrade.sh` (372 lines — CRC baseline detection, CLI download, image pull, container recreation)
- [x] Remove hardcoded router image version (now uses SKUPPER_ROUTER_VERSION env var, default 3.5.3)
- [x] Add helper functions to `common.sh`: inject_inter_router_listener, regenerate_local_server_cert, check_crc_link_staleness
- [x] test-model.sh — no changes needed (uses host-based routing, not link names)

### Phase 3: Skill-Gen Compliance (P1–P7) ✅ DONE

- [x] Error Handling table — present (done in Phase 1)
- [x] Troubleshooting table — present (done in Phase 1)
- [x] Signal phrases — 13 phrases, all Command/Query pattern, concise, non-redundant, complete
- [x] S12 (upgrade) in Spec table — present (done in Phase 1)
- [x] Upgrade test case T12 — present (done in Phase 1)
- [x] Single vocabulary audit — no mixed terms, no "hub" remnants, "provider" consistent
- [x] One instruction per sentence — no compound instructions found
- [x] Fixed: `writes-files: false` → `true`
- [x] Fixed: SKILL.md examples used `crc-ezhang`/`local-ezhang` but scripts accept `crc`/`localhost`
- [x] Known Issues — kept in references/known-issues.md (32 entries, actively referenced by scripts; not ready for graduation to knowledge bundle — still evolving with v2.2.3 testing)

### Phase 4: Stop Skupper Infra (models untouched) ✅ DONE

- [x] Stop all podman sites via systemctl (not down.sh — avoids model stop)
- [x] Delete CRC links (old names: link-hub-rhel-ai, link-local-ezhang)
- [x] Models verified still running (qwen3-14b-40k on rhel-ai, g3b on rhtevan-work)

### Phase 5: Upgrade Skupper ✅ DONE

- [x] Download CLI 2.2.3 on all 3 hosts (GitHub releases)
- [x] Verified `skupper version` = 2.2.3 on localhost, rhel-ai, rhtevan-work
- [x] Fixed upgrade.sh: controller image is `system-controller` not `skupper-controller`
- [x] Note: Images will be pulled by `skupper system start` in Phase 6 (CLI manages image refs)

### Phase 6: Teardown + Rebuild ✅ DONE

- [x] Remove old namespaces on all podman hosts (containers + namespace dirs)
- [x] Delete old CRC resources (site, links, secrets, listeners)
- [x] Rebuild rhel-ai site (with tmpfs workaround, Interior mode confirmed)
- [x] Rebuild rhtevan-work site (Interior mode confirmed)
- [x] Rebuild local-ezhang site with RouterAccess (inter-router on :55672)
- [x] Create links: link-local-ezhang-rhel-ai (Ready), link-local-ezhang-rhtevan-work (Ready)
- [x] Create CRC site, links, listeners — all Ready
- [x] E2E verified: HTTP 200 on :9000 (Qwen3-14B-FP8), :10000 (granite-4.1-3b)
- [x] Linger enabled on all hosts
- [x] Note: setup.sh Phase 3b needs fix — RouterAccess must be created BEFORE inter-router injection; cert regen needs to use issuers/ path

### Phase 7: Post-Upgrade Verification ✅ DONE

- [x] All CLI versions aligned at 2.2.3
- [x] CRC operator: skupper-operator.v2.2.3-rh-1
- [x] Controller images: system-controller:2.2.3 on all hosts
- [x] Router images: skupper-router:3.5.3 on rhel-ai (tmpfs), CLI-managed on others
- [x] **v2.2.3 DOES handle RouterAccess inter-router role natively** ✅ — listener created without manual injection
- [x] **v2.2.3 DOES honor subjectAlternativeNames** ✅ — cert includes host.crc.testing, 192.168.127.254
- [x] Observer site names: still show suffixes (rhel-ai-1792600731-269607018) in link remote-site field — podman platform limitation persists
- [x] E2E: both models accessible via localhost and CRC
- [x] Decision: keep workaround code in scripts as FALLBACK — v2.2.3 handles it natively but older versions may not

### Phase 8: Finalize ✅ DONE

- [x] Skill-gen P1-P7 audit — all passed (2 critical fixed, 1 advisory accepted)
- [x] CHANGELOG.md — v9.0.0 entry with full description
- [x] SKILL.md version — 9.0.0
- [x] Known-issues updated — v2.2.3 fixes for inter-router and SANs documented
- [x] setup.sh fixed — RouterAccess created before system start; Phase 3b as verify+fallback
- [x] common.sh fixed — inject uses dynamic sslProfile; cert regen uses issuers/ path
- [x] Skill index regenerated — 61 skills indexed
- [x] KGM registered — skill:skupper-model-provider entity created
- [x] Post-write completed

## Ad Hoc Fixes to Codify

| Fix | Script | Details |
|-----|--------|---------|
| Inter-router listener on localhost:55672 | `setup.sh` Phase 3 + `up.sh` guard | Controller ignores `inter-router` role in RouterAccess. Inject into skrouterd.json. Re-test on 2.2.3. |
| Server cert SANs (host.crc.testing, 192.168.127.254) | `setup.sh` Phase 3 + `up.sh` guard | Controller doesn't honor subjectAlternativeNames. Regenerate with openssl. Re-test on 2.2.3. |
| CRC link secret refresh on cert change | `up.sh` CRC phase | Compare CA fingerprints on Pending links, not just on `not found`. Delete + recreate + restart pod. |
| CRC operator version detection | `status.sh` | ✅ Already fixed v8.17.2 — prefix match. |
| `normal` role in RouterAccess | All scripts | Never include — controller rejects it. Only `inter-router` or `edge`. |
