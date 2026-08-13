# goose-agentfs-setup Changelog


| Updated | Change |
|---------|--------|
| 2026-07-14 19:17 | v1.4 — Moved full memory routing table to on-demand `references/memory-routing.md`; instructions.md stub now lists tool names to detect and loads full table only when memory tools are present; reduces auto-loaded context by ~57 lines per turn |
| 2026-07-10 16:14 | v1.3 — Replaced flat signal→action table with priority-based decision table supporting Cognee (pri 1), Memory (pri 2), Chat Recall (pri 3); added runtime resolution rule (check tool existence in available tools list); static table adapts to dynamic extension enable/disable; added ambiguity resolution and routing announcement rules; aligns with AGENTS.md Guardrail #9 two-layer architecture |
| 2026-07-09 01:42 | v1.2 — Added global goosehints for knowledge discovery: --hints-check, --hints-install, --hints-remove; progressive knowledge loading via plain reference to ~/.agents/knowledge/index.md |
| 2026-07-09 00:52 | v1.1 — Added memory collision avoidance: --memory-check, --memory-install, --memory-remove; routing override for Goose memory extension trigger words; profile-scoped MEMORY.md support for subagents |
| 2026-07-07 16:49 | v1.0 — Initial skill: --check, --add, --remove, --all, --reset, --list |
