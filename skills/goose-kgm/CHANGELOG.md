# Changelog

| Updated | Change |
|---------|--------|
| 2026-11-20 00:26 | v1.8.5 — reindex-kgm.sh: atomic combined-index swap (temp file + rename) so running servers never read a partial index |
| 2026-11-20 00:18 | v1.8.4 — goose-kgm 1.8.4: manage_extensions and goose CLI paths live-tested; Known Issues section (one server per session, server lifetime follows session) |
| 2026-11-19 23:51 | v1.8.3 — setup-kgm.sh: env wrapper form, migrate legacy envs-only entry, drop symlink call; status-kgm.sh: config-form check + runtime MEMORY_FILE_PATH check per running server (replaces symlink health); reindex-kgm.sh: drop ensure-kgm-symlink call and stale 'Goose does not pass MEMORY_FILE_PATH' comment; SKILL.md: Index Path Delivery (RCA + path matrix), env wrapper config, post-setup restart/toggle instruction, runtime status rule, enabled semantics corrected; SKILL.md: mark manage_extensions and CLI rows as source-verified, not live-tested; ensure-kgm-symlink.sh removed (fallback could not create a missing file and its config.yaml grep gave false OK); root cause: goose 1.60.1 drops inline envs on the desktop ACP path, so the v1.8.2 premise was wrong; setup-kgm.sh: timestamped backup when .bak.pre-kgm already exists (no overwrite); status-kgm.sh: runtime check counts only node processes (pgrep -f self-match guard) |
| 2026-11-19 21:18 | v1.8.2 — ensure-kgm-symlink.sh: no false 'No server-memory package' warning when MEMORY_FILE_PATH is set (goose 1.60.1 passes it; symlink not needed); setup-kgm.sh: back up config.yaml (.bak.pre-kgm) before yaml.dump rewrite; symlink comment corrected for goose 1.60.1 |
| 2026-11-17 22:55 | v1.8.1 — F7: KGM names from agentfs-contract.sh; status-kgm reports tool-name mismatch |
| 2026-11-09 20:45 | v1.8.0 — Add --dry-run support with DRY_RUN_RESULT signals; Add --dry-run flag parsing; Wrap symlink mutations in dry-run guards; Add DRY_RUN_RESULT summary at end of script; Add --dry-run flag parsing; Add dry-run convergence check and DRY_RUN_RESULT signals |
| 2026-11-08 22:57 | v1.7.0 — Add Rules + trace + bump to 1.7.0; Add trace-lib.sh; Add trace-lib.sh; Add trace-lib.sh; Add trace-lib.sh; Add trace-lib.sh; Add trace-lib.sh; Add trace-lib.sh; Add trace-lib.sh; CNL restructure Operations to Step workflow format; Remove internal descriptions from operation steps |
| 2026-11-08 21:19 | v1.6.0 — Add anti-fabrication rules and CNL compliance for Observable qualification |
| 2026-11-05 19:31 | v1.5.0 — Add model-tier to frontmatter |
| 2026-10-22 21:48 | v1.5.0 — New script: self-healing symlink enforcement for MCP server memory.jsonl |
| 2026-09-24 20:46 | v1.4.0 — Document AgentSkill entity type, staleness guard, anti-pattern moved from AGENTS.md |
| 2026-09-24 19:24 | v1.3.0 — Separate knowledge/skills KGM indexes, merge into combined .kgm-index.jsonl |
| 2026-09-24 19:11 | v1.2.0 — setup-kgm.sh: symlink server-memory default memory.jsonl to managed .kgm-index.jsonl (workaround for envs not passed to MCP process) |
| 2026-09-16 08:55 | v1.1.0 — Session-scoped enable/disable via extension manager (not config.yaml); status checks session-level tool availability; added reindex/sync signal; documented sync model |
| 2026-08-31 15:59 | v1.0.1 — Added KGM entity schema reference doc and dual-format knowledge index parser (table + list) |
| 2026-08-31 15:45 | v1.0.0 — Initial creation — KGM lifecycle management (setup/teardown/enable/disable/status/reindex) |
