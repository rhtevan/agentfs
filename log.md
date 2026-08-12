# Directory Update Log
<!-- Append-only. Newest entries at top. -->

## 2026-08-12 11:20
- skupper-model-provider v7.0.1: Clarified loose coupling semantics — agent semantically triggers `hosted-model-ctl` (no cross-script invocation)
- Stripped model container and e2e sections from `status.sh` (VAN-only)
- Added `skupper model provider status`/`check skupper model provider` signals
- Regenerated skills/index.md (48 skills)

## 2026-08-12 11:10
- skupper-model-provider v7.0.0: Decoupled model lifecycle from VAN scripts
  - `up.sh`/`down.sh` now manage Skupper infrastructure only (controllers + routers)
  - Model containers delegated to `hosted-model-ctl` at agent level (DRY + Loose Coupling)
  - Added Agent Orchestration section with signal routing, scoping rules, error handling
  - Updated signals, Specification (S1–S8), Tests (T1–T8), Relationship table
- hosted-model-ctl v5.1.0:
  - Changed default rhel-ai model from `g30b-96k` to `g8b-128k`
  - Removed ambiguous bare signals (`model list/start/stop/status`)
  - Added `hosted model teardown`/`teardown hosted model` signals
  - Added `stop.sh --remove` flag for container teardown
- Regenerated skills/index.md (48 skills)

## 2026-08-12 09:10
- skupper-model-provider v6.1.3: Fixed `down.sh` Phase 1 container filter to exclude router containers
- Regenerated skills/index.md (48 skills)

## 2026-08-12 09:04
- skupper-model-provider v6.1.2: Removed `[Install]`/`WantedBy=default.target` from systemd unit templates in `common.sh`
- Disabled skupper services on all 3 hosts to prevent auto-start on reboot with `Linger=yes`
- Updated SKILL.md: new known issue entry, updated auto-restart fix description, changelog, version bump
- Regenerated skills/index.md (48 skills)

## 2026-08-11 18:49
- skupper-model-provider v6.1.1: `down.sh all` now stops controllers on all 3 hosts (previously left running)
- Updated SKILL.md: version bump, script table, shutdown example, known issues table, changelog
- Regenerated skills/index.md (48 skills)

## 2026-08-11 18:28
- Sanitized POSTMORTEM.md: replaced site-specific hostnames (`bastion.g7cpg.*`) with `*.example.com`, IPs with placeholders, `local-ezhang` with `local-site`
- Sanitized SKILL.md changelog and log.md: replaced `local-ezhang` with `local-site`
- Regenerated USER skills index.md (48 skills)

## 2026-08-11 18:00
- skupper-model-provider v6.1.0: Extracted site-specific config (IPs, hostnames, SANs, usernames) from scripts to `topology.env`
- Created `topology.env.example` with placeholder values for safe git commit
- Added precheck capability (`setup.sh --check`): topology display + validation (podman, skupper, SSH, DNS, SANs, ports)
- Added signals: `skupper model precheck`, `skupper model topology`, `show skupper topology`
- Added `topology.env` and `.rollback/` patterns to `.gitignore`
- Updated SKILL.md architecture, site config, and operations sections to reference topology.env variables

## 2026-08-11 17:17
- skupper-model-provider v6.0.1: Added Tests section (T1–T7 mapped to S1–S7) per skill-check Principle 4 finding
- Regenerated USER skills index.md (48 skills)

## 2026-08-11 17:12
- Fixed skill-gen metadata.signals: added Skill Check mode triggers (skill check, check skill, scan skill, audit skill, verify skill quality) that were missing from YAML frontmatter — only existed in prose body text, invisible to signal routing
- Regenerated USER skills index.md (48 skills)

## 2026-08-11 16:57
- skupper-model-provider: Added POSTMORTEM.md documenting 9 root causes, architecture decisions, and lessons learned

## 2026-08-11 16:50
- skupper-model-provider v6.0: Complete refactor — separated setup.sh/teardown.sh (one-time infrastructure) from up.sh/down.sh (daily start/stop)
- New scripts: setup.sh (416 lines), teardown.sh (85 lines); refactored up.sh (179 lines), down.sh (107 lines), status.sh (127 lines), common.sh (319 lines)
- Added auto-restart patches for router + controller (start-watch.sh + Restart=on-failure) on all 3 hosts
- Fixed: unique site names (hub-rhel-ai, hub-rhtevan-work, local-site), podman 4.x /tmp workaround, cert perms, SANs on RouterAccess, manual link building
- VAN fully operational: localhost:9000 → granite-4.1-8b (rhel-ai), localhost:10000 → granite-4.0-350m (rhtevan-work)
- Regenerated USER skills index.md (48 skills)

## 2026-08-11 11:50
- Added Guardrail Type System to AgentFS: Gate 🚧, Rule ⚖️, Habit 🔄
- Updated `agentfs-setup/references/design-spec.md`: added type badges to guardrail list, added Guardrail Type System sub-section with rationale and Trigger/Invariant collapse analysis
- Updated `agentfs-setup/scripts/seed-agents-md.sh`: Type column in Quick Reference table, verb-chain Key Actions, type badges on all 10 headings, gate blockquotes on #5/#9/#10, template version 3.9→3.10
- Updated `agentfs-setup/SKILL.md` changelog with v3.10.0 entry
- Synced AGENTS.md in project `goofing-around` to template v3.10, re-injected project-owned profiles (verifier, watchdog)
- Fixed `skupper-model-provider/scripts/status.sh`: replaced `|| echo "0"` with `|| true` on pipefail-sensitive pipelines
- Updated `skupper-model-provider/SKILL.md` changelog with v5.1 entry

## 2026-08-11 10:40
- Fixed `skupper-model-provider/scripts/status.sh`: replaced `|| echo "0"` with `|| true` on `ss | grep | grep -c` pipelines to prevent `set -euo pipefail` abort and `0\n0` arithmetic parse errors
- Updated `skupper-model-provider/SKILL.md` changelog with v5.1 entry

## 2026-08-10 16:45

- Updated `litellm-vertex-ai-proxy` v3.0.0: extracted all inline execution code to 4 scripts (setup.sh, detect-sa.sh, test-sa.sh, probe-models.sh); SKILL.md reduced from 308→202 lines; added Gotcha #7; added T8–T11 tests; workflow 8→6 steps
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 16:25

- Added `<!-- Append-only. Newest entries at top. -->` comment anchor to `~/.agents/log.md` (was missing)
- Strengthened Guardrail #5 insertion anchor in AGENTS.md: added "read current file head before inserting" to prevent stale-context log misordering

## 2026-08-10 16:15

- Updated `skill-gen` v2.1.1: strengthened Gotchas from suggestion to requirement; added Gotchas section to SKILL.md template; added P1 checklist item for Gotchas/Known Issues
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 15:58

- Updated `skill-gen` v2.1.0: P1 inline code boundary guidance — reference vs execution code distinction; added checklist item
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 15:50

- Updated `litellm-vertex-ai-proxy` v2.0.0: updated model list; documented us-east5 as explicit region; added scripts/verify.sh (11 checks) and scripts/probe-models.sh (model discovery); added Specification and Tests; added SA key safety warning; fixed frontmatter
- Updated `goose-litellm-provider` v1.6.0: removed sonnet-4-5; fixed context_limits (opus/sonnet: 1M, haiku: 200k)
- Updated `hermes-litellm-provider` v2.2.0: removed sonnet-4-5 from reference config
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 15:26

- Updated `goose-litellm-provider` v1.5.0: added claude-haiku-4-5 to models; changed fast_model to claude-haiku-4-5; updated Vertex AI region from global to us-east5
- Updated `hermes-litellm-provider` v2.1.0: added claude-haiku-4-5 to reference config; updated region note
- Updated LiteLLM proxy config: all 4 models pinned to us-east5
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 14:10

- Updated `hermes-litellm-provider` v2.0.0: rewrote to match live Hermes config schema; added scripts/verify.sh and scripts/restore.sh; added Specification and Tests; removed hardcoded dummy api_key; documented hermes model persistence bug
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 12:55

- Updated `goose-litellm-provider` v1.4.0: removed pyyaml dependency from verify.sh (replaced with awk); consolidated Steps 1-2 into single pre-flight check; renumbered steps (6→5)
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 12:02

- Updated `skill-gen` v2.0.0: added Principle 5 (Security & Trust Boundary) with 6-item checklist; "Four Principles" → "Five Principles"; added "Real Expertise" anti-pattern and Gotchas guidance to Step 1; added "loose steps → instructions, fragile steps → code" aphorism to Agent-as-Orchestrator; updated Skill Check Procedure to 9 steps
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 11:23

- Updated `skill-gen` v1.9.0: strengthened P1 to "Accuracy, Consistency & Testability (Code-First)" — skills as prescriptive SOPs verified by execution; code-first for accuracy, consistency, conciseness, testability; added could-be-script 🟡 flag and knowledge-extraction checklist items; moved Concise from P3 to P1; renamed P3 to "Traceable & Well-Formatted"
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-10 10:38

- Updated `goose-litellm-provider` v1.3.0: set fast_model to claude-sonnet-4-6; added Model Selection Architecture section; added scripts/verify.sh and scripts/restore.sh; added Specification and Tests sections; consolidated workflow steps; added defensive template warning; normalized changelog versions
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-08 14:59

- Complete rewrite of `hosted-model-ctl` v5.0: 7 operational scripts, Specification, Tests, compact tables (659→229 lines)
- Complete rewrite of `skupper-model-provider` v5.0: 5 scripts (up/down/status/test/common), podman platform, interior mode (334→194 lines)
- Complete rewrite of `goose-skupper-provider` v4.0: 3 scripts (setup/teardown/test), JSON schema enforcement (127→126 lines)
- Updated `skill-gen` v1.8: Skill Check mode with 4 principles (Accuracy, Currency, Concise, Verifiable Spec)
- Fixed model ID: granite-4.1-8b-instruct → granite-4.1-8b in PROVIDER.md
- All scripts syntax-verified and live-tested
- Regenerated `skills/index.md` (48 skills)
## 2026-08-08 12:15

- Created OKF knowledge bundle `skupper-vllm-deployment` with 5 concept documents
- Added bundle to `~/.agents/knowledge/index.md`

## 2026-08-08 10:55

- Updated `agentfs-setup` v3.8→v3.9: added "Never improvise when a skill exists" routing rule; added "Backup untracked files" to Guardrail #9
- Synced `AGENTS.md` to template v3.9
- Updated `skill-gen` v1.5→v1.6: added "Defensive file templates" writing guidance
- Updated `skill-gen/references/skill-schema.md` v1.0→v1.1: added `writes-files` optional field
- Regenerated `skills/index.md` (48 skills)
## 2026-08-08 10:09

- Fixed `goose-skupper-provider/PROVIDER.md` v3.0→v3.1: added schema warning, templated JSON placeholders; root cause: agent bypassed skill and wrote invalid custom_skupper.json with non-Goose fields
- Fixed `custom_skupper.json` to use correct Goose custom provider schema
- Regenerated `skills/index.md` (48 skills)
## 2026-08-08 01:43

- Updated `skupper-model-provider/SKILL.md` v3.0→v4.0: complete rewrite for interior mode (not edge), podman platform (not linux/systemd), routing keys `model-api-rhtevan-work` and `model-api-rhel-ai`, ports 10000 (rhtevan-work) and 9000 (rhel-ai), inter-router links on 55671 and 8000, documented podman gotchas
- Updated `hosted-model-ctl/SKILL.md` v3.2→v4.0: rhtevan-work model port 8000→10000, updated all container commands and test commands
- Updated `goose-skupper-provider/SKILL.md` v2.0→v3.0 and `PROVIDER.md`: port 8000→10000 for rhtevan-work, routing key `model-api-rhtevan-work`
- Regenerated `skills/index.md` (48 skills)
- Deployed full Skupper VAN interior mesh: localhost (outbound only) ↔ rhtevan-work:55671 ↔ rhel-ai:8000, all podman platform with official skupper-router:3.5.2 image
- Recreated rhtevan-work model containers (g350m, g1b, g8b) on port 10000
- Masked old linux-platform skupper-model-provider.service on rhel-ai

## 2026-08-07 00:38

- Updated `goose-skupper-provider/SKILL.md` v1.2→v2.0: model-to-port routing table (8000 for rhtevan-work, 9000 for rhel-ai), default g350m, signal parsing for model alias
- Updated `goose-skupper-provider/PROVIDER.md` v1.1→v2.0: multi-port base_url, added g30b-96k and g8b-128k to model reference
- Updated `skupper-model-provider/SKILL.md` v2.0→v3.0: two routing keys (model-api, model-api-rhel-ai), two local ports (8000, 9000), rhel-ai edge port 8000 (AWS 45671 blocked), multi-hub architecture
- Updated `hosted-model-ctl/SKILL.md` v3.1→v3.2: rhel-ai models serve on port 9000 (was 8000), port 8000 reserved for Skupper edge on rhel-ai
- Regenerated `skills/index.md` (48 skills)

## 2026-08-06 21:14

- Renamed `local-model-ctl` → `hosted-model-ctl`: directory, SKILL.md name, description, signals (`hosted model *` patterns), tags (`hosted`, `self-hosted`), version 3.0→3.1
- Updated `skupper-model-provider/SKILL.md`: all 5 references to `local-model-ctl` → `hosted-model-ctl`
- Regenerated `skills/index.md` (48 skills)

## 2026-08-06 21:03

- Updated `goose-skupper-provider/SKILL.md` v1.1→v1.2: Added recreate capability (teardown + setup); useful when remote model changes
- Regenerated `skills/index.md` (48 skills)

## 2026-08-06 20:58

- Fixed `skill-index/SKILL.md` v2.3→v2.4: Replaced fragile metadata block regex with line-by-line state machine for signals extraction; added inline bracket format support; signals now correctly populate for all 48 skills (was 4/48)
- Updated `local-model-ctl/SKILL.md`: All rhel-ai models now use port 8000 (single endpoint, one model at a time)
- Updated `skupper-model-provider/SKILL.md`: Model alias auto-routes to remote host; single localhost:8000 endpoint; "bring up"/"shutdown" invocation patterns; added signals
- Regenerated `skills/index.md` (48 skills, 48 with signals)

## 2026-08-06 20:04

- Updated `local-model-ctl/SKILL.md` v2.3→v3.0: Added rhel-ai host profile (4× NVIDIA L4, 92 GB VRAM); added g30b-96k (Granite 4.1 30B, BF16, tp=4, 96K context) and g8b-128k (Granite 4.1 8B, BF16, tp=2, 128K context) models; InstructLab container image support; rhel-ai-specific gotchas and memory budgets
- Updated `skupper-model-provider/SKILL.md` v1.2→v2.0: Added rhel-ai as supported remote host; updated model selection prompts, container check commands, and prerequisites for multi-host support
- Regenerated `skills/index.md` (48 skills)

## 2026-08-04 23:58

- Migrated all 48 skills to canonical frontmatter schema (`skill-gen/references/skill-schema.md`):
  - 14 skills: moved `version:` from top-level into `metadata:` block
  - 19 skills: added `metadata.version` (extracted from changelog)
  - 13 skills: normalized version format to quoted 3-part semver
  - 2 skills: removed YAML `changelog:` from frontmatter (goose-desktop-env-fix, goose-skupper-provider)
  - 1 skill: restructured non-standard frontmatter (goose-skupper-provider: added `description:`, wrapped tags/signals in `metadata:`)
  - 1 skill: added missing `## Changelog` Markdown section (goose-skupper-provider)
- Result: 48/48 skills now have `metadata.version` as quoted 3-part semver

## 2026-08-04 23:52

- Created `skills/skill-gen/references/skill-schema.md` — canonical SKILL.md frontmatter schema (single source of truth for version location, format, changelog rules)
- Updated `skills/skill-gen/SKILL.md` v1.5.0 — template uses quoted 3-part semver (`"1.0.0"`); post-creation checklist requires `metadata.version`; writing guidance references schema doc
- Updated `skills/skill-harvest/SKILL.md` v1.1.0 — scaffolded template uses `"1.0.0"` with `metadata.signals`; quality checklist references canonical schema
- Updated `skills/skill-index/SKILL.md` v2.3.0 — added `metadata.version` presence validation warning; references canonical schema

## 2026-08-04 22:20

- Reverted `local-model-ctl` to v2.3 — g8b back to 16K/18 GPU layers (32K too slow for Goose prompt processing)
- Recreated `model-g8b` container on rhtevan-work with `--ctx-size 16384 --n-gpu-layers 18 -v ...:/models:ro,z`
- Updated `custom_skupper.json` context_limit to 16384
- Validated: 3/3 model tests passed via Skupper VAN

## 2026-08-04 20:24

- Updated `local-model-ctl` to v2.2 — g8b context increased from 16K to 32K, GPU layers reduced from 18 to 12, SELinux volume mount fix
- Recreated `model-g8b` container on rhtevan-work with `--ctx-size 32768 --n-gpu-layers 12`
- Updated `skupper-linux-two-site` to v2.0 — swapped site roles: localhost=edge, remote=interior/hub
- Updated `skupper-model-provider` to v1.1 — same role swap, firewall check moved to remote host
- Validated skupper-linux-two-site: create → link → nc test ✅ → teardown ✅

## 2026-08-04 19:37

- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh` § Index Currency guardrail: strengthened `skill-index` mandate — explicitly prohibits ad-hoc scripts for index generation; requires `load_skill` and following skill instructions

## 2026-08-04 19:33

- Updated `skills/goose-skupper-provider/SKILL.md` to v1.1.0 — added setup/teardown capabilities with setup as default
- Rewrote `skills/goose-skupper-provider/PROVIDER.md` — merged original loaded-skill reference config into PROVIDER.md; added full Teardown section (remove custom_skupper.json + config.yaml entry)
- Regenerated `skills/index.md`

## 2026-08-04 19:20
- Updated `skill-index` skill (v2.1→v2.2): documented metadata block regex last-line bug fix (`(?:\n|$)`) and table generation blank-line bug fix
- Regenerated `~/.agents/skills/index.md` — all 48/48 skills now have signals populated

## 2026-08-04 19:16
- Created skill `goose-skupper-provider` at `~/.agents/skills/goose-skupper-provider/SKILL.md` — Goose custom provider for Skupper VAN model endpoint (localhost:8000)
- Created `~/.config/goose/custom_providers/custom_skupper.json` — Skupper provider definition
- Added `custom_skupper` provider entry to `~/.config/goose/config.yaml`
- Updated terminology in `skupper-model-provider` (v1.1→v1.2): local=edge, remote=hub/interior
- Updated terminology in `skupper-linux-two-site` (v2.0→v2.1): replaced my-hub/my-edge examples with neutral placeholders
- Regenerated `~/.agents/skills/index.md` (48 skills)

## 2026-08-04 19:05
- Fixed missing `signals` in `skills/spec-kit-setup/SKILL.md` frontmatter — added 5 signal phrases
- Regenerated `skills/index.md` (48 skills) — spec-kit-setup Signals column now populated

## 2026-08-04 19:00

- Fixed `fuseki` skill v1.1: stop script now disables auto-start (`systemctl --user disable`); start script re-enables it. Prevents Fuseki from restarting on login after explicit stop.
- Updated `skills/fuseki/scripts/stop-fuseki.sh` — added disable step after stop
- Updated `skills/fuseki/scripts/start-fuseki.sh` — added enable step before start
- Updated `skills/fuseki/SKILL.md` changelog

## 2026-08-04 18:35

- Updated `skupper-linux-two-site` to v2.0 — swapped site roles: localhost=edge (outbound, no firewall needed), remote=interior/hub (accepts inbound links)
- Updated `skupper-model-provider` to v1.1 — same role swap, all scripts rewritten
- Updated `link-sites.sh`, `test-nc.sh`, `teardown.sh` in skupper-linux-two-site
- Updated `up.sh`, `down.sh`, `status.sh` in skupper-model-provider
- Validated skupper-linux-two-site with full cycle: create sites → link → nc test ✅ → teardown ✅
- Regenerated `~/.agents/skills/index.md`

## 2026-08-04 17:38

- Created `skupper-model-provider` skill under `~/.agents/skills/skupper-model-provider/`
- Scripts: `up.sh`, `down.sh`, `test-model.sh`, `status.sh`
- Replaces `skupper-linux-two-site` with integrated model runtime lifecycle
- Idempotent up/down with full Skupper VAN + model runtime management
- Regenerated `~/.agents/skills/index.md` (47 skills)

## 2026-08-04 15:58

- Harvested knowledge bundle `llm-inference-constrained-gpu` at `~/.agents/knowledge/llm-inference-constrained-gpu/`
- 6 concept documents: vLLM vs llama.cpp philosophy, containerized inference pattern, GPU layer tuning, AgentFS context requirements, Fedora NVIDIA gotchas, vLLM quantization pitfalls
- Updated `~/.agents/knowledge/index.md` and `~/.agents/knowledge/log.md`

## 2026-08-04 15:36

- Updated `local-model-ctl` to v2.1 — model-specific container names (`model-g350m`, `model-g1b`, `model-g8b`)
- Enables true start/stop switching without redeployment
- Renamed live container on rhtevan-work: `llama-granite` → `model-g8b`

## 2026-08-04 15:19

- Renamed skill `granite-4.0-1b-model-ctl` → `local-model-ctl` (v2.0)
- Added multi-model support: g350m (default), g1b, g8b with automatic engine selection
- Added llama.cpp engine support for g8b (GGUF Q4_K_M, hybrid CPU+GPU offload)
- Added `list` operation to show all supported models
- Added model alias parameter to `start` and `setup` operations
- Captured GPU layer tuning data (4K ctx → 25 layers, 16K ctx → 18 layers)
- Removed old `granite-4.0-1b-model-ctl` skill directory
- Regenerated `~/.agents/skills/index.md` (46 skills)

## 2026-08-04 12:46

- Created skill `granite-4.0-1b-model-ctl` at `~/.agents/skills/granite-4.0-1b-model-ctl/SKILL.md`
- Skill provides pre-check, setup, test, status, start, stop operations for containerized vLLM + Granite 4.0-1B inference server
- Captures all lessons learned from deployment session on rhtevan-work (Fedora/RPMFusion nvidia-smi absence, Podman pasta networking, bitsandbytes quantization, dtype auto-detect, tool calling flags)
- Regenerated `~/.agents/skills/index.md` (46 skills)

## 2026-07-31 21:57

- Updated Index Currency sub-guardrail in seed-agents-md.sh template: clarified that metadata-only changes also trigger index regeneration
- Regenerated skills/index.md (45 skills)

## 2026-07-31 21:52

- Updated seed-agents-md.sh template script: added Guardrail #8 Anti-Daydreaming section, renumbered #9/#10, updated Quick Reference table, bumped template version to 3.8
- Bumped SKILL.md Version property from 3.7 to 3.8

## 2026-07-31 21:44

- Added Guardrail #8 Anti-Daydreaming to agentfs-setup skill (SKILL.md + design-spec.md) and README.md
- Renumbered Checkpoints → #9, Git Push Safety → #10 across all files
- Updated guardrail count from 9 to 10 in SKILL.md, design-spec.md, README.md
- Added v3.8 changelog entries to SKILL.md and design-spec.md

## 2026-07-30 14:14

- Updated `goose-recipe-session-cleanup` to v3.0 — Desktop sessions now eligible for cleanup on explicit request; Hidden sessions deletable; added `SKIP_TRACKED` safety for projects.json sessions; signal routing table for category selection; "clean all sessions" support
- Regenerated `~/.agents/skills/index.md` (45 skills)

## 2026-07-30 13:54

- Updated `goose-recipe-session-cleanup` to v2.0 — report now shows 4 distinct sections (Recipe, Terminal, Hidden, Desktop reference); added optional `before_date` filter for targeted cleanup; improved deletion script with configurable flags; VACUUM only on bulk deletes
- Regenerated `~/.agents/skills/index.md` (45 skills)

## 2026-07-30 13:39

- Created USER skill `goose-recipe-session-cleanup` at `~/.agents/skills/goose-recipe-session-cleanup/SKILL.md`
- Identifies and removes orphaned session records from ad-hoc `goose session run --recipe` commands in SQLite DB
- Regenerated `~/.agents/skills/index.md` (44 → 45 skills)

## 2026-07-29 10:28

- Created USER skill `fedora-dns-cache` at `~/.agents/skills/fedora-dns-cache/`
- Added `SKILL.md` and `scripts/setup.sh` for systemd-resolved stale DNS caching
- Regenerated `~/.agents/skills/index.md` (44 skills)

## 2026-07-28 16:45

- Updated `hermes-desktop-fixes/SKILL.md`: v2.1 — added fix #4 (duplicate taskbar icon on Fedora/GNOME Wayland, `StartupWMClass` case mismatch); renumbered electron-builder fix to #5; added `.desktop` file to "Files outside git" table
- Regenerated `~/.agents/skills/index.md` (43 skills)

## 2026-07-27 18:40

- Added `metadata.signals` to all 43 skills (38 new, 5 existing)
- Updated `skill-gen/SKILL.md`: v1.4 — added `metadata.signals` to template and post-creation checklist, concise description guidance
- Updated `skill-index/SKILL.md`: v2.0 — removed Description column, Signals is primary discovery column
- Regenerated `~/.agents/skills/index.md` with new format (no Description, with Signals)
- Updated `design-spec.md`: v3.7 — signal routing architecture, template versioning, `--sync`, README sync rule
- Updated `seed-agents-md.sh`: added Skills index to Quick Orientation, Skill signal resolution routing rule, README sync in Post-Edit step 4
- Updated `README.md`: skills frontmatter schema, signal routing flow, template versioning, README sync rule, 43 skills count

## 2026-07-27 17:20

- Updated `agentfs-setup` SKILL.md: v3.7 — added `metadata.signals` frontmatter field, `--sync` mode, template version stamping, project-owned section markers
- Updated `agentfs-setup/references/design-spec.md`: added SKILL.md Frontmatter Schema section with `metadata.signals` field spec
- Updated `agentfs-setup/scripts/seed-agents-md.sh`: slimmed Signal Routing table (11→9 rows), added template version stamp, added project-owned marker, added skill discovery note
- Updated `skill-index` SKILL.md: v1.9 — added Signals column extraction and display
- Added `metadata.signals` to: `agentfs-setup`, `agentfs-eval`, `agentfs-ctx-chk`, `skill-harvest`, `okf-bundle-harvest`
- Regenerated `~/.agents/skills/index.md` with Signals column (43 skills, 5 with signals)

## 2026-07-27 15:49

- Updated `seed-agents-md.sh` template: refined "hey git" signal row — shortened keywords to `"hey git", "git"`, clarified route as `cd ~/.agents` (or explicit path), stage, commit, trigger Guardrail #9

## 2026-07-27 15:10
- Created skill: fuseki — Install and manage Apache Jena Fuseki as a systemd user service
- Scripts: setup-fuseki.sh, start-fuseki.sh, stop-fuseki.sh, status-fuseki.sh
- Regenerated skills/index.md (43 skills)


## 2026-07-22 23:51

- Merged `## Modes` into `## Directory Structure` — eliminated terminology
  duplication ("scope" vs "mode"); Directory Structure now shows both USER
  and PROJECT scope trees with a Scope Boundaries note; replaced remaining
  "mode" references with "scope" in Getting Started
- Final section order: Scope Definitions → Getting Started → Directory
  Structure → Structural Guardrails → Memory Architecture → Skill Design
  Principles → Evaluation → License

## 2026-07-22 23:37

- Reordered `README.md` top-level sections; promoted `## Skill Design
  Principles` from subsection under Skills (#### to ###); moved after
  Memory Architecture

## 2026-07-22 23:13

- Updated `README.md` — Memory Architecture: added Working Memory as a
  first-class memory type (runtime-managed, SESSION-scoped); added Memory
  Lifecycle vertical ASCII diagram showing auto-load → on-demand capture →
  on-demand graduation flow; all transitions human-gated by design; MEMORY.md
  is NOT auto-loaded but readable on-demand for recall or graduation (Option B);
  documented what gets loaded at session start (auto-load, first-use, on-demand
  tiers); acknowledged external systems (Hindsite, Cognee) as accelerators
- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh` — Signal Routing:
  added "reflect" keyword row, routed to harvest triage (skill-harvest or
  okf-bundle-harvest)

## 2026-07-22 21:49

- Updated `agentfs-setup` skill template Guardrail #9 — added README Staleness Check (soft gate, step 4) to pre-push flow

## 2026-07-22 21:34

- Updated USER skill `skupper-linux-two-site` to v1.3 — replaced environment-specific examples (ezhang-work, rhtevan-work) with generic placeholders (my-hub, my-edge)
- Updated `agentfs-setup` skill template Guardrail #9 — expanded scan patterns: username leakage, SSH host aliases, local IPs, PII (email, phone, real names)
- Updated project `./AGENTS.md` Guardrail #9 with same expanded scan patterns

## 2026-07-22 21:22

- Updated USER skill `skupper-linux-two-site` to v1.2 — added Invocation Example section
- Created knowledge bundle `agentfs-skill-patterns` at `~/.agents/knowledge/agentfs-skill-patterns/`
- Added concept doc `parameter-binding-pattern.md` — reusable pattern for multi-parameter skill binding
- Updated `~/.agents/knowledge/index.md` with new bundle entry

## 2026-07-22 21:11

- Updated USER skill `skupper-linux-two-site` to v1.1
- Added structured `parameters:` block in YAML frontmatter with `binding-cues` for semantic argument resolution
- Added `argument-hint` with CLI-style usage syntax
- Added Agent Binding Rules section: cue matching, missing-param prompts, default application, confirmation flow, script argument mapping table
- Regenerated `~/.agents/skills/index.md` (42 skills)

## 2026-07-22 19:57

- Created USER skill `skupper-linux-two-site` at `~/.agents/skills/skupper-linux-two-site/`
- SKILL.md: Two-site Skupper V2 Linux/systemd setup with parameterized site names, IPs, namespace
- Scripts: verify-prerequisites.sh, create-site.sh, link-sites.sh, test-nc.sh, teardown.sh
- Regenerated `~/.agents/skills/index.md` (42 skills)

## 2026-07-22 19:06

* **Update**: Updated `knowledge/skupper-v2-concepts/` — added migration (V1→V2), platform-details (Linux architecture, site bundles, multi-site, skrouterd install), and firewall rules. 6 new concept docs, 2 new sub-bundles.

## 2026-07-22 15:41

* **Update**: Updated `knowledge/skupper-v2-concepts/security/` — added TLS passthrough, inter-router mTLS enforcement, and link port documentation to existing concepts.

## 2026-07-20 17:36

* **Update**: Regenerated `skills/index.md` (41 skills) — okf-bundle-gen timestamp updated to 2026-07-20 17:33 after v3.2 edit.

## 2026-07-20 17:33

* **Update**: Updated `skills/okf-bundle-gen/SKILL.md` v3.1→v3.2: Added Phase 7c (USER scope log.md entry) to fix Guardrail #5 compliance gap.

## 2026-07-20 17:31

* **Creation**: Generated OKF knowledge bundle `knowledge/skupper-v2-concepts/` with 11 concept documents across 4 sub-bundles (core-concepts, security, advanced-features, operations).
* **Update**: Updated `knowledge/index.md` with new bundle entry.

## 2026-07-16 11:12
- Created skill `crc-aap-demo-config` at `~/.agents/skills/crc-aap-demo-config/SKILL.md` — clone aap-demo repo, pre-flight checks against local CRC, apply protective config to prevent preset/resource override
- Regenerated `~/.agents/skills/index.md` (41 skills)

## 2026-07-15 16:50

- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: added Guardrail Quick Reference table to AGENTS.md seed template
- Updated `skills/agentfs-setup/SKILL.md` v3.5→v3.6: documented Guardrail Quick Reference addition

## 2026-07-15 15:18

- Updated `skills/agentfs-setup/SKILL.md` v3.4→v3.5: documented all seed template changes (Signal Routing promotion, Memory Scope rename, "hey git" signal, Post-Edit Completeness, log insertion anchor, knowledge index backtick fix)
- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: knowledge index link changed to backtick format

## 2026-07-15 15:00

- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: moved Signal Routing section to top (after Quick Orientation); removed duplicate at bottom; added log insertion anchor rule to Guardrail #5

## 2026-07-15 14:45

- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: restructured Signal Routing as standalone section after guardrails; renamed Guardrail #2 to "Memory Scope"; added "hey git" signal

## 2026-07-15 14:10

- Fixed `skills/litellm-vertex-ai-proxy/SKILL.md`: added `metadata.tags` alongside vendor-nested `metadata.hermes.tags` so index generator can discover tags
- Regenerated `skills/index.md`

## 2026-07-15 13:57

- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: added Post-Edit Completeness sub-section to Guardrail #5 in AGENTS.md seed template
- Updated `skills/goose-desktop-env-fix/SKILL.md`: restored rendered Changelog section at bottom of file (was dropped during v1.2 rewrite)

## 2026-07-15 13:00

- Updated `skills/goose-desktop-env-fix/SKILL.md` v1.1→v1.2: changed devbox shellenv guard from exported `__DEVBOX_SHELLENV_LOADED` to shell-local `__devbox_shellenv_done` — fixes `refresh-global` alias missing in `devbox shell` sessions while preserving fork-bomb protection

## 2026-07-14 19:26

- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh` — compacted AGENTS.md template from 277→207 lines (25%): removed Resolves To column, dropped Executor/Scope columns from routing table, collapsed Skill Resolution Chain, merged Content File/Log Currency, replaced verbose Git Push Safety with 5-step list; updated sed insertion block
- Updated `skills/agentfs-setup/SKILL.md` v3.3→v3.4 — documented compaction
- Regenerated `skills/index.md` — 40 skills

## 2026-07-14 19:18

- Created `skills/goose-agentfs-setup/references/memory-routing.md` — full Goose memory routing table moved to on-demand reference file (74 lines)
- Updated `skills/goose-agentfs-setup/scripts/setup.sh` — replaced 76-line inline MEMORY_INSTRUCTIONS with 19-line compact stub that directs agent to load `references/memory-routing.md` on-demand
- Updated `skills/goose-agentfs-setup/SKILL.md` v1.3→v1.4 — documented on-demand memory routing architecture
- Updated `~/.config/goose/instructions.md` — 89→32 lines; replaced full memory routing table with compact stub referencing on-demand file

## 2026-07-14 18:35

- Updated `skills/agentfs-ctx-chk/SKILL.md` v1.0→v1.1: added Directionality Rule (USER scope is canonical, PROJECT is fix target); updated Step 7 root cause table with Fix Direction column
- Updated `skills/agentfs-ctx-chk/references/checklist.md` v1.1: added Directionality Rule section before Phase 2; updated Phase 7 Decision Table

## 2026-07-14 18:14
- Created `skills/agentfs-ctx-chk/SKILL.md` v1.0 — context engineering audit skill: 8-phase methodology (inventory, redundancy, ambiguity, conflicts, effectiveness, cross-references, root causes, report+fix)
- Created `skills/agentfs-ctx-chk/references/checklist.md` — detailed audit checklist with patterns from first real audit
- Updated `skills/goose-setup/SKILL.md`: `<username>`→`<user>` (2 occurrences)
- Updated `skills/skill-harvest/SKILL.md`: `<username>`→`<user>` (1 occurrence)
- Regenerated `skills/index.md` — 40 skills indexed

## 2026-07-14 17:49
- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: AGENTS.md template consolidated from 13 to 9 guardrails; Quick Orientation now includes SOUL.md and knowledge index rows for agent-agnostic progressive loading
- Updated `skills/agentfs-setup/SKILL.md` v3.2→v3.3: guardrail list and description updated to 9 guardrails
- Updated `skills/agentfs-setup/references/design-spec.md`: guardrail list updated, eval-driven guardrails section renumbered
- Updated `skills/goose-agentfs-setup/SKILL.md`: Guardrail #9→#2 cross-references
- Updated `skills/goose-agentfs-setup/scripts/setup.sh`: Guardrail #9→#2 cross-references
- Updated `skills/okf-bundle-harvest/SKILL.md`: Guardrail #8→#2 cross-references
- Updated `skills/skill-gen/SKILL.md`: Guardrail #10→#6, #6→#5 cross-references
- Updated `skills/skill-harvest/SKILL.md`: Guardrail #8→#2 cross-references; `<username>`→`<user>` placeholder
- Updated `skills/goose-setup/SKILL.md`: `<username>`→`<user>` placeholder (2 occurrences)
- Removed guardrails section from `index.md` — replaced with pointer to project-level `AGENTS.md`

## 2026-07-14 15:48

- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: added entry relevancy rule to Guardrail #2 (Log Currency) in template
- Removed 4 cross-scope log entries that described PROJECT-scope changes (project AGENTS.md, project MEMORY.md)

## 2026-07-14 15:22

- Updated `skills/agentfs-setup/SKILL.md` v3.1→v3.2: AGENTS.md template now includes thirteen guardrails (added #10–#13)
- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh`: added guardrails #10–#13 to heredoc template

## 2026-07-14 14:56

- Updated `skills/skill-index/SKILL.md` v1.7→v1.8: added name-directory consistency validation step and verification check per Agent Skills open standard

## 2026-07-14 14:51

- Fixed `skills/crc-ols/SKILL.md` `name` field: `openshift-lightspeed-crc` → `crc-ols` to match directory name per Agent Skills open standard
- Fixed `skills/agentfs-eval/SKILL.md` frontmatter: moved `name` and `description` to top-level (were nested under `metadata:`)
- Updated `skills/skill-gen/SKILL.md` v1.2→v1.3: added "Name consistency" check to post-creation checklist enforcing directory-name match rule
- Regenerated `skills/index.md` (39 skills, 0 empty names)

## 2026-07-14 13:55

- Updated `skills/crc-ols/SKILL.md` v2.0→v2.1: credential security hardening — replaced `--from-literal` with file-based secret creation, added security warnings and 401 troubleshooting guidance. Validated full add-provider + switch-default workflow against live MaaS LiteLLM endpoint.
- Regenerated `skills/index.md` (39 skills)

## 2026-07-13 17:06

- Updated `skills/goose-setup/SKILL.md` v1.3→v1.4: strengthened Git Push Safety from bullet list to 5-step procedural checklist

## 2026-07-13 16:44

- Added `LICENSE` file: Apache License 2.0
- Updated `README.md`: replaced placeholder license disclaimer with Apache 2.0 boilerplate and link to LICENSE file

## 2026-07-13 16:11

- Updated `README.md`: added "Skill Design Principles" section (non-interactive scripts, agent-as-orchestrator pattern, business process modeling) between Skills and Knowledge subsections
- Updated `skills/skill-gen/SKILL.md` v1.1→v1.2: added "Skill Design Principles" section before Simple Mode with same three principles

## 2026-07-13 15:46
- Created `agentfs-eval` skill — three-layer maturity assessment (structural, behavioral, semantic) with L0–L5 maturity levels
- Created `scripts/agentfs-check.sh` (Layer 1: 7 structural assertions)
- Created `scripts/agentfs-behavior.sh` (Layer 2: 5 behavioral assertions)
- Created `rubrics/` directory with 4 semantic rubrics (memory-classification, reference-verification, sycophancy-detection, skill-accuracy)
- Created `templates/report.md` (eval output format)
- Created `references/design-decisions.md` (design rationale from design session)
- Updated `agentfs-setup` — scaffold-dotagents.sh now calls init-git.sh in PROJECT mode by default
- Updated `agentfs-setup/scripts/init-git.sh` — .gitignore no longer excludes .agents/memories/
- Updated `agentfs-setup/references/design-spec.md` — added Evaluation section, guardrails #10–12, git audit infrastructure
- Updated `README.md` — added Evaluation section with three-layer model, maturity levels, design decisions

## 2026-07-13 13:45
- Backfilled `metadata.tags` for 21 skills that were missing tags (including adding YAML frontmatter to `hermes-headroom-provider`)
- Regenerated `skills/index.md` — 38 skills, all with tags
- Added mandatory tags guardrail to Guardrail #6 in AGENTS.md and `agentfs-setup` seed template
- Updated `skill-gen` SKILL.md post-creation checklist — frontmatter validation now explains tags requirement and links to Guardrail #6

## 2026-07-13 13:33
- Updated `skill-index` SKILL.md v1.7 — added Tags column extraction from `metadata.tags` frontmatter; updated index template, verification checklist, and changelog
- Regenerated `skills/index.md` with Tags column — 38 skills indexed (17 with tags, 21 without)
- Updated `agentfs-setup/scripts/seed-agents-md.sh` — added skill resolution chain routing rule; renamed `skill-creator` → `skill-gen` in decision table

## 2026-07-13 11:20
- Renamed `skills/skill-creator/` → `skills/skill-gen/` for naming consistency with `okf-bundle-gen`, `bash-completion-gen`
- Updated SKILL.md: name, title, all internal path references, changelog (v1.1)
- Regenerated `skills/index.md`

## 2026-07-13 10:49

- Created `bash-completion-gen` skill under USER scope (`~/.agents/skills/bash-completion-gen/SKILL.md`) — generates bash completion scripts for any CLI command via systematic subcommand/option discovery, build, and validation
- Regenerated `~/.agents/skills/index.md` — 38 skills indexed

## 2026-07-10 18:08

- `agentfs-setup` v3.0 — PROJECT is now the default mode; added canonical Scope Definitions section (USER=`~/.agents/`, PROJECT=`./.agents/`) to SKILL.md, AGENTS.md template, design-spec, and README; documented two USER setup paths (full clone vs minimal install); added Prerequisites section; nine guardrails (was eight); verify-setup.sh now checks for Scope Definitions in AGENTS.md; all user-facing instructions now say "ask your agent to run the skill" instead of directing users to execute bash scripts; Path B (minimal install) references the skill with USER scope hint; README reordered: Scope Definitions → Getting Started → Directory Structure → Modes → Guardrails → Memory Architecture
- Updated `README.md` — Scope Definitions and Getting Started moved to top; all instructions agent-centric (not bash-centric); step 3 needs no scope hint since PROJECT is default


## 2026-07-10 17:05

- Created `skill-creator` proxy skill — two modes (simple scaffold + advanced Anthropic upstream), AgentFS post-creation checklist, agent compatibility notes, fetch-upstream.sh for caching complete upstream file structure
- Updated AGENTS.md Guardrail #9 decision table — "create a skill" row now routes to `skill-creator` skill instead of LLM intrinsic
- Updated `agentfs-setup` seed template — same Guardrail #9 update

## 2026-07-10 16:15

- Updated `goose-agentfs-setup` skill (`scripts/setup.sh`) — replaced flat signal→action memory override with priority-based decision table: Cognee (pri 1) > Memory (pri 2) > Chat Recall (pri 3); runtime resolution via tool existence check; aligns with AGENTS.md Guardrail #9 Layer 2
- Updated `goose-agentfs-setup` SKILL.md — rewrote Memory Collision Avoidance section as Memory Signal Routing (Layer 2); added v1.3 changelog entry

## 2026-07-10 16:10

- Added Guardrail #9 (Memory Signal Routing) to `agentfs-setup` skill seed template (`scripts/seed-agents-md.sh`)
- Updated `agentfs-setup` design spec (`references/design-spec.md`) — v2.11: guardrail count 8→9, added §9 description and changelog entry
- Updated `README.md` — guardrail count 8→9, added Memory Signal Routing section under Memory Architecture with two-layer decision table architecture

## 2026-07-09 20:07

- Skill Harvest: Created crc-ctl skill v1.0 from 3 MEMORY.md entries (goofing-around project)

## 2026-07-09 19:55

- Created skill-harvest skill v1.0 — procedural memory-to-skill graduation (complements okf-bundle-harvest)

## 2026-07-09 19:41

- Updated okf-bundle-harvest SKILL.md v1.2 — added system/environment-specific non-graduation criterion

## 2026-07-09 17:43

- Added Memory Architecture section to ~/.agents/README.md
## 2026-07-09 02:09
- Updated `okf-bundle-index/scripts/rebuild-index.sh` — sub-bundle entries now include descriptions extracted from their `index.md` (first paragraph after heading, truncated to 120 chars)
- Updated `okf-bundle-index/SKILL.md` v1.3 — documented sub-bundle description extraction
- Rebuilt `~/.agents/knowledge/index.md` with sub-bundle descriptions

## 2026-07-09 01:55
- Updated `okf-bundle-index/SKILL.md` changelog — added v1.2 entry for default path fix
- Updated `okf-bundle-setup/SKILL.md` changelog — added v1.1 entry for default path fix

## 2026-07-09 01:43
- Updated USER skill `goose-agentfs-setup` v1.2: added global goosehints for knowledge discovery (--hints-check, --hints-install, --hints-remove)
- Updated USER skill `okf-bundle-gen` v3.1: removed Phase 9 (SOUL.md pattern link injection), removed `update-soul-links.sh` script
- Updated USER skill `okf-bundle-harvest` v1.1: removed Phase 9 (SOUL.md update), removed `update-soul-links.sh` dependency
- Created `~/.config/goose/.goosehints` with knowledge index reference for progressive loading
- Reverted `SOUL.md` from `CONTEXT_FILE_NAMES` (knowledge discovery now via global goosehints)
- Regenerated `~/.agents/skills/index.md` — 34 skills indexed

## 2026-07-09 00:56
- Created USER skill `okf-bundle-harvest`: multi-project memory-to-knowledge distillation with graduation criteria, MEMORY.md pruning, OKF-compliant output
- Created `~/.agents/skills/okf-bundle-harvest/scripts/prune-memory.sh` — removes graduated §-delimited entries from MEMORY.md
- Created `~/.agents/skills/okf-bundle-harvest/scripts/harvest-summary.sh` — cross-project harvest candidate analysis
- Updated USER skill `goose-agentfs-setup` v1.1: added memory collision avoidance (--memory-check, --memory-install, --memory-remove)
- Regenerated `~/.agents/skills/index.md` — 34 skills indexed

## 2026-07-08 23:39

- Updated `README.md`: removed `knowledge/` from PROJECT mode tree, added scope notes (knowledge=USER-only, memories=PROJECT-only), expanded guardrails list from 4→8, updated skill count 31→33, clarified knowledge path in Getting Started
- Updated `skills/agentfs-setup/references/design-spec.md`: clarified prompt stacking item 4 (knowledge is USER-scoped, shared across projects)

## 2026-07-08 23:23

- Regenerated `~/.agents/skills/index.md` — 33 skills indexed (completing workflow from stuck session `20260709_21`)

## 2026-07-08 23:17

- Updated `~/.agents/skills/goose-desktop-env-fix/SKILL.md` to v1.1: added root cause #4 (devbox fork bomb), detailed analysis section, updated .bashrc example with recursion guard, added verification checklist items, updated tags

## 2026-07-08 22:42

- Updated `~/.agents/skills/skill-index/SKILL.md` to v1.6: clarified multi-line YAML scalar handling and improved fallback description extraction
- Regenerated `~/.agents/skills/index.md` (33 skills) — all descriptions now correctly populated

## 2026-07-08 22:34

- Updated `~/.config/goose/instructions.md`: added Path Hygiene guardrail (never use explicit home directory paths)
- Updated `~/.agents/skills/goose-setup/SKILL.md` to v1.3: added Path Hygiene to example instructions and changelog

## 2026-07-08 22:26

- Created `~/.agents/skills/goose-desktop-env-fix/SKILL.md` v1.0: captures the full Goose Desktop shell environment fix (goose-shell wrapper, .desktop entry, environment.d, bashrc restructuring)
- Regenerated `~/.agents/skills/index.md` (33 skills)

## 2026-07-08 22:16

- Updated `~/.agents/skills/goose-setup/SKILL.md` to v1.2: removed obsolete Tool Discovery instructions (replaced by goose-shell wrapper fix), updated description and examples
- Regenerated `~/.agents/skills/index.md` (32 skills)

## 2026-07-08 18:06

- Fixed broken OKF spec links in `README.md` and `skills/okf-bundle-setup/references/okf-spec-summary.md` — now point to `https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md`

## 2026-07-08 17:49

- Updated `skills/goose-setup/SKILL.md` — v1.1: added Git Push Safety guardrail
- Updated `~/.config/goose/instructions.md` — added Git Push Safety section
## 2026-07-08 17:41

- Created `skills/goose-setup/SKILL.md` — new skill for configuring Goose global persistent instructions and tool discovery
- Regenerated `skills/index.md` — 32 skills indexed
- Created `~/.config/goose/instructions.md` — persistent instructions file for cross-session tool discovery
- Added `GOOSE_MOIM_MESSAGE_FILE` to `~/.config/goose/config.yaml`
## 2026-07-08 14:34

- Deleted `okf-bundle-merge` skill — obsolete since okf-bundle-gen now writes directly to `~/.agents/knowledge/`
- Regenerated `skills/index.md` (31 skills)
## 2026-07-08 14:19

- Modified `okf-bundle-gen/SKILL.md`: v3.0 — bundle root changed to `~/.agents/knowledge/` (user-level), removed project-local staging, SOUL.md links use absolute paths, memory scan PROJECT-only
- Modified `okf-bundle-merge/SKILL.md`: marked **OBSOLETE** — no longer needed since okf-bundle-gen writes directly to user-level knowledge

## 2026-07-08 13:38

- Recreated `agentfs-setup/SKILL.md` — was missing; reflects v2.10 with memory redesign (8 guardrails, knowledge USER-only, memories PROJECT-only)
- Modified `agentfs-setup/scripts/seed-agents-md.sh`: added guardrail §8 (Memory Scope) with NL-signal routing and graduation path
- Modified `agentfs-setup/scripts/verify-setup.sh`: knowledge checks USER-only, MEMORY.md template updated to "Project Experiences", PROJECT mode checks for stale knowledge/
- Modified `agentfs-setup/scripts/scaffold-dotagents.sh`: knowledge/ USER-only, MEMORY.md "Experiences" template (done in prior session)
- Modified `agentfs-setup/references/design-spec.md`: removed knowledge from PROJECT tree, 8 guardrails, updated layer descriptions
- Modified `agentfs-profile/SKILL.md`: v1.8 — updated description, removed knowledge references
- Modified `agentfs-profile/scripts/create-profile.sh`: MEMORY.md template updated to "Project Experiences" with scope/NL-signal guidance

## 2026-07-08 10:11

* **Memory**: Added OKF non-concept type guideline to user-level MEMORY.md — distinguishes concept bundles from reference dataset bundles, documents valid use of Dataset/Script/Ground Truth types for companion data metadata
## 2026-07-08 09:46

* **Memory**: Added two OKF guidelines to user-level MEMORY.md — (1) keep bundle roots clean of concept files, (2) distill true concepts rather than raw documentation
* **Reorganize**: Moved `claude-compat-analysis.md` from user-global knowledge root into sub-bundle `agentfs-claude-compat/`
## 2026-07-08 08:54

- Created knowledge bundle `knowledge/headroom-openai-compression-analysis/` with 3 concept documents: problem-analysis (root cause of zero compression), configuration-history (v1→v2 timeline), options-assessment (4 options, recommended passthrough + watch)
- Updated `knowledge/index.md` and `knowledge/log.md`
## 2026-07-07 16:52

- Created new skill `goose-agentfs-setup` — configures Goose CONTEXT_FILE_NAMES for cross-agent context file discovery (CLAUDE.md, .cursorrules, .windsurfrules)
- Updated `agentfs-setup` skill v2.9 — added Cross-Agent Context Discovery guardrail (§7) to AGENTS.md template in `seed-agents-md.sh`
## 2026-07-07 16:08

- Updated `skills/headroom-litellm-proxy/SKILL.md` to v1.1 — removed `--lossless`, added `--target-ratio 0.5` and `--intercept-tool-results`; added Compression Tuning section, Flags NOT to Use section, expanded health/stats verification and troubleshooting
- Regenerated `skills/index.md` via `skill-index` (31 skills)
## 2026-07-07 16:04

- Updated `skills/agentfs-setup/SKILL.md` to v2.8 — added guardrails §6 bullets: mandatory `skill-index` invocation, scope-aware `log.md` updates; clarified skill-index requirement in Maintaining the Layers section
- Updated `skills/agentfs-setup/scripts/seed-agents-md.sh` AGENTS.md template with new §6 guardrail bullets

- Regenerated `skills/index.md` via `skill-index` (31 skills)
## 2026-07-07 15:58

- Created `memories/MEMORY.md` at USER level (`~/.agents/memories/`) with cross-project agent workflow guardrail: always run `skill-index` after modifying any skill
- Regenerated `skills/index.md` via `skill-index` skill (31 skills indexed)
## 2026-07-07 15:54

- Updated `skills/headroom-proxy-status/SKILL.md` to v1.1 — added Kompress ML, target ratio, uncompressed reasons to report format; expanded compression stats extraction fields; added compression troubleshooting section; removed `--lossless` from key flags example
- Updated `skills/index.md` timestamp for headroom-proxy-status
## 2026-07-07 00:00
- Removed USER skill `claude-skills-link` — redundant; Goose natively scans `.claude/skills/` at both project and global scope
- Regenerated `~/.agents/skills/index.md` — 31 skills indexed
## 2026-07-06 23:28
- Updated `skills/claude-skills-link/SKILL.md` — confirmed v2.0 (no content change); verified skill execution with CWD test: symlink creation, idempotency, stale cleanup, and PROJECT skill index generation all pass
## 2026-07-06 22:01
- Created USER skill `hermes-headroom-provider` at `~/.agents/skills/hermes-headroom-provider/SKILL.md` — configure Hermes Agent to use the local Headroom proxy as its custom LLM provider
- Regenerated `~/.agents/skills/index.md` — 31 skills indexed
## 2026-07-06 21:48
- Created skill `headroom-litellm-proxy` at `~/.agents/skills/headroom-litellm-proxy/SKILL.md` — Headroom installation and systemd setup chained to LiteLLM
- Refactored skill `goose-headroom-provider` (v2.0) — now covers Goose custom provider config only; installation/systemd content moved to `headroom-litellm-proxy`
- Regenerated `~/.agents/skills/index.md` — 30 skills indexed
## 2026-07-06 21:39
- Created skill `goose-headroom-provider` at `~/.agents/skills/goose-headroom-provider/SKILL.md` — configure Goose to use the Headroom context-optimization proxy as a custom provider
- Regenerated `~/.agents/skills/index.md` — 29 skills indexed
## 2026-07-06 21:32
- Created skill `headroom-proxy-status` at `~/.agents/skills/headroom-proxy-status/SKILL.md` — check health, config, and runtime status of the local Headroom context-optimization proxy
- Regenerated `~/.agents/skills/index.md` — 28 skills indexed
## 2026-07-06 20:06

- Updated `skills/goose-maas-provider/SKILL.md` to v1.3 — Goose Desktop v1.41 is incompatible with MaaS for tool-calling tasks (fails under all tested configurations: streaming on/off, toolshim on/off); CLI with `GOOSE_TOOLSHIM: true` is the only working approach; updated Desktop section, troubleshooting
## 2026-07-06 20:00

- Updated `skills/goose-maas-provider/SKILL.md` to v1.2 — added `GOOSE_TOOLSHIM: true` as required config (smaller models strip namespace prefixes from tool names); added `supports_streaming: false` as required for Desktop (streaming responses lost due to goose Desktop bug); documented Desktop vs CLI behavioral differences; updated checklist, troubleshooting, recovery
## 2026-07-06 19:39

- Updated `skills/goose-maas-provider/SKILL.md` to v1.1 — reasoning models (`gpt-oss-120b`, `qwen3-14b`, `deepseek-r1-*`) are fundamentally incompatible with Goose v1.41 streaming parser; changed default model to `llama-scout-17b`; added model compatibility matrix; updated recovery script, checklist, troubleshooting
## 2026-07-06 19:25

- Created `skills/goose-maas-provider/SKILL.md` v1.0 — new dedicated skill for MaaS (remote LiteLLM) provider setup; covers API key keyring storage, critical reasoning model fixes (`reasoning: false`, `preserves_thinking: false`), documented failure modes with evidence from real sessions, diagnostic tests, recovery script
- Updated `skills/goose-litellm-provider/SKILL.md` to v1.2 — removed all MaaS-related content (moved to `goose-maas-provider`); restored as local-proxy-only skill; updated description, tags, and `related_skills` to reference new skill
- Updated `skills/index.md` — added `goose-maas-provider`, bumped count to 27, refreshed `goose-litellm-provider` description
## 2026-07-06 19:14

- Updated `skills/goose-litellm-provider/SKILL.md` to v1.1 — added MaaS remote provider configuration, reasoning model gotcha (`reasoning: true` for thinking models), API key GNOME Keyring storage, available model discovery, expanded troubleshooting and recovery procedures
- Updated `skills/index.md` — refreshed description and timestamp for goose-litellm-provider
## 2026-07-06 18:04

- Created `skills/goose-litellm-provider/SKILL.md` v1.0 — skill to configure Goose with local LiteLLM proxy as 'RedHat' custom provider, includes reference JSON, config.yaml entries, recovery script, and troubleshooting
- Updated `skills/index.md` — added `goose-litellm-provider` entry, bumped count to 26
## 2026-07-06 14:38

- Updated `skills/litellm-vertex-ai-proxy/SKILL.md` v1.1 — made agent-agnostic by removing Hermes-specific Step 8, updated description and troubleshooting
- Updated `skills/index.md` — refreshed description for `litellm-vertex-ai-proxy`
## 2026-07-06 12:27
- Updated `agentfs-setup` skill to fully align all scripts, flags, and documentation from the legacy 'SYSTEM' terminology to 'USER' mode.
## 2026-07-06 11:37

- Strengthened guardrail §6 (Index Currency) in `AGENTS.md` and `seed-agents-md.sh`: `skills/index.md` must now be regenerated after any content modification to skill files (SKILL.md, scripts, references), not just structural changes (create/rename/move/delete)
## 2026-07-06 11:31

- Renamed AgentFS mode label `SYSTEM` → `USER` across all skills, scripts, design specs, AGENTS.md, and seed templates
- Updated script variable names: `AGENTS_SKILLS_SYSTEM` → `AGENTS_SKILLS_USER`, `AGENTS_SKILLS_SYSTEM_EXPANDED` → `AGENTS_SKILLS_USER_EXPANDED`
- Preserved `SYSTEM_RESERVED_*` kubelet variables in `crc-post-setup-config` (unrelated to AgentFS modes)
- Historical `log.md` entries left unchanged per append-only guardrail
## 2026-07-06 11:18

- Renamed `agent-fs-profile` → `agentfs-profile` and `agent-fs-setup` → `agentfs-setup` for consistent `agentfs` naming
- Renamed 6 skills to replace `-configuration` suffix with `-config`: `crc-coo-config`, `crc-nad-dynamic-plugin-config`, `crc-nmstate-config`, `crc-noo-config`, `crc-ovn-frr-metallb-config`, `crc-post-setup-config`
- Updated all internal references across SKILL.md files, scripts, index.md, and project-level files
## 2026-07-06 11:00

- Updated `hermes-agentfs-setup` to v1.1 — added PROJECT scope support (`--project`, `--undo-project`, `--list`)
- PROJECT scope registers a project's `.agents/skills/` as an absolute path in `skills.external_dirs` (per-project action)
- Regenerated `skills/index.md` (25 skills)
## 2026-07-06 10:54

- Created `hermes-agentfs-setup` skill — configures Hermes Agent to discover AgentFS SYSTEM skills from `~/.agents/skills/` via `skills.external_dirs`
- Includes `scripts/setup.sh` with `--check`, `--undo`, and idempotent setup modes
- Regenerated `skills/index.md` (25 skills) with Python-based YAML frontmatter parser to fix folded-scalar description truncation
## 2026-07-01 00:07

- Added total count to `skills/index.md` and `profiles/index.md` summary lines (e.g., `> 24 skills | Sorted by…`).
- Updated `scaffold-dotagents.sh`, `verify-setup.sh`, `create-profile.sh`, and `skill-index/SKILL.md` to emit/maintain the count.
- Regenerated `~/.agents/skills/index.md` (24 skills).
## 2026-07-01 00:00

- Added missing YAML frontmatter (name + description) to `crc-ovn-frr-metallb-config/SKILL.md`; was the only skill without frontmatter, causing empty description in `skills/index.md`.
- Regenerated `skills/index.md`.
## 2026-06-30 23:54

- Added `## Changelog` section to 19 SYSTEM skills that were missing it; all 24 skills now have consistent `| Updated | Change |` tables with `YYYY-MM-DD HH:MM` timestamps.
## 2026-06-30 23:49

- Expanded guardrail §2 (Log Currency): explicit SYSTEM/PROJECT/sub-bundle scope coverage; mandatory logging when skills or concept files change; standardized `log.md` format (title, comment, heading precision, entry style).
- Fixed `okf-bundle-setup/scripts/scaffold-bundle.sh` and `okf-bundle-gen/scripts/merge-log-entry.sh` to use `YYYY-MM-DD HH:MM` timestamps, `<!-- Append-only -->` comment, and `- ` entry style.
- Standardized this file to use consistent format.
## 2026-06-30 23:36

- Updated guardrail §3 (Content File Currency): Changelog tables now require `YYYY-MM-DD HH:MM` timestamps and `Updated` column header.
- Updated Changelog tables in 6 files: `agentfs-setup/SKILL.md`, `agentfs-setup/references/design-spec.md`, `agentfs-profile/SKILL.md`, `skill-index/SKILL.md`, `skill-merge/SKILL.md`, `okf-bundle-gen/SKILL.md`.
## 2026-06-30 23:31

- Renamed index column `Added` → `Updated` across all `skills/index.md` and `profiles/index.md` templates and live files.
- Increased timestamp precision to `YYYY-MM-DD HH:MM` in all index.md seeds, log.md seeds, and script `date` calls.
- Updated guardrails §2 and §6 to use timestamp headings.
- Regenerated `~/.agents/skills/index.md` (30 skills, `Updated` column, `YYYY-MM-DD HH:MM`).
## 2026-06-30 23:16

- Added Index Currency guardrail (§6) to AGENTS.md template in `seed-agents-md.sh`.
- Updated `profiles/index.md` schema: Identity + Memories + Updated columns, sorted newest-first.
- Updated `skills/index.md` schema: Updated column, sorted newest-first.
- Expanded `profiles/` narrative in `agentfs-setup/SKILL.md` and `design-spec.md` with dual-purpose (multi-agent hub + ROLE-based specialization) and Hermes OOTB compatibility.
- Updated `create-profile.sh` to insert entries newest-first with memories link.
- Reinforced mandatory `skills/index.md` update in `skill-merge/SKILL.md`.
- Regenerated `~/.agents/skills/index.md`.
## 2026-06-30 18:30

- Added `profiles/index.md` to scaffold and verify scripts; all `profiles/` links now point to `profiles/index.md`; all `memories/` links now point to `memories/MEMORY.md`.
## 2026-06-30 17:45

- All mutating scripts (`seed-agents-md.sh`, `init-speckit.sh`, `rename-agent-context.sh`) now append entries to `.agents/log.md` per the Log Currency guardrail.
## 2026-06-30 17:30

- Idempotent re-run: agent detects existing `.agents/` and skips creation phases; `verify-setup.sh --fix` repairs missing files/dirs without overwriting; link integrity checks; profile completeness checks; `skills/index.md` seeded instead of `.gitkeep`.
## 2026-06-30 16:30

- Fixed `index.md` link convention: all relative links now use `./` prefix for consistent rendering across GitHub, VS Code, and other markdown viewers.
## 2026-06-30 16:00

- Fixed `rename-agent-context.sh` sed bug: replaced `sed -i c\` with `awk` block replacement for SPECKIT marker merging.
## 2026-06-30 15:30

- Added Agent Profiles table to AGENTS.md; `seed-agents-md.sh` creates default row and retrofits existing files; `create-profile.sh` auto-registers new profiles.
## 2026-06-30 14:00

- v2.0 redesign of `agentfs-setup`: USER → SYSTEM mode rename; `memory/` → `memories/`; `roles/` → `profiles/`; added SOUL.md, USER.md, MEMORY.md; removed constitution.md (Spec-kit owns it); multi-agent collaboration design; prompt stacking order.
- Created companion skill `agentfs-profile`: scaffolds named agent profiles under `.agents/profiles/` with SOUL.md + memories/.
## 2026-06-26 22:00

- Fixed `verify-setup.sh` to use opt-in `--with-git` / `--with-spec` flags instead of auto-detecting git/spec-kit on disk.
## 2026-06-26 14:00

- Initialized .agents/ directory structure (mode: system).


