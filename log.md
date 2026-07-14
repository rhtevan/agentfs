# Directory Update Log

<!-- Append-only. Newest entries at top. -->

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
