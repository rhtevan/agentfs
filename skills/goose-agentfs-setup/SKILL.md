---
name: goose-agentfs-setup
description: >
  Configure Goose for full AgentFS compatibility by adding CLAUDE.md and
  other agent context files to CONTEXT_FILE_NAMES, so Goose automatically
  discovers and loads cross-agent context files alongside AGENTS.md.
  Also manages memory collision avoidance — installs persistent instruction
  overrides that prevent the Goose memory extension from hijacking AgentFS
  natural-language memory signals (remember, save, forget, etc.), routing
  them to the correct MEMORY.md file (default agent or named profile).
  Also manages global goosehints for progressive knowledge discovery —
  references ~/.agents/knowledge/index.md so Goose can find and load
  knowledge bundles on demand.
argument-hint: "Optionally specify which context files to add (e.g., CLAUDE.md, .cursorrules)"
compatibility: "Requires Goose with config.yaml support (v1.30+)"
metadata:
  author: agentfs
  version: "1.0"
  tags: [goose, agentfs, configuration, compatibility]
user-invocable: true
disable-model-invocation: false
---

# Goose AgentFS Setup

Configure Goose to discover and load cross-agent context files, making it
fully compatible with projects that use Claude Code (`CLAUDE.md`), Cursor
(`.cursorrules`), Windsurf (`.windsurfrules`), or GitHub Copilot conventions.

## Problem

Goose loads `AGENTS.md` and `.goosehints` by default. Many GitHub repos
include `CLAUDE.md` (the de facto standard from Claude Code) with valuable
project context that Goose silently ignores unless configured.

| Context File | Agent | Goose Default? |
|-------------|-------|:-:|
| `AGENTS.md` | AgentFS / Goose | ✅ |
| `.goosehints` | Goose | ✅ |
| `CLAUDE.md` | Claude Code | ❌ |
| `.cursorrules` | Cursor | ❌ |
| `.windsurfrules` | Windsurf | ❌ |
| `.github/copilot-instructions.md` | GitHub Copilot | ❌ |

Goose supports loading **any** context file via the `CONTEXT_FILE_NAMES`
configuration parameter — it just needs to be told which files to look for.

## What This Skill Does

Adds cross-agent context filenames to Goose's `CONTEXT_FILE_NAMES`
configuration in `~/.config/goose/config.yaml`, so Goose automatically
discovers and loads them from both global (`~/.config/goose/`) and
project-local directories (CWD + subdirectories).

### How Context File Loading Works in Goose

Goose's context file loading (`load_hints.rs`) does the following:

1. **Global hints**: Reads each configured filename from
   `~/.config/goose/<filename>`. When `AGENTS.md` is in the list, also
   reads `~/.agents/AGENTS.md`.
2. **Project hints**: Reads each configured filename from CWD up to the
   git root (or just CWD if not in a git repo).
3. **Subdirectory hints**: As the agent touches files in subdirectories,
   it discovers and loads configured filenames from those directories too.
4. **Import support**: All context files support `@file` imports for
   including referenced files inline.

All discovered content is concatenated into the system prompt.

## Prerequisites

- Goose installed with `config.yaml` support (v1.30+)
- Config file at `~/.config/goose/config.yaml`

## Usage

### Check Current Configuration

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --check
```

Shows current `CONTEXT_FILE_NAMES` and reports which cross-agent files
are missing from the configuration.

### Standard Setup (Recommended)

Adds `CLAUDE.md` to the context file list (the most common cross-agent
file found on GitHub):

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh
```

This sets `CONTEXT_FILE_NAMES` to:
```yaml
CONTEXT_FILE_NAMES:
  - .goosehints
  - AGENTS.md
  - CLAUDE.md
```

### Full Cross-Agent Setup

Adds all known cross-agent context files:

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --all
```

This sets `CONTEXT_FILE_NAMES` to:
```yaml
CONTEXT_FILE_NAMES:
  - .goosehints
  - AGENTS.md
  - CLAUDE.md
  - .cursorrules
  - .windsurfrules
```

### Custom Files

Add specific context files:

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --add CLAUDE.md .cursorrules
```

### Remove Files

Remove specific context files from the config:

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --remove .cursorrules
```

### Reset to Defaults

Restore Goose's default context file list:

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --reset
```

### List Supported Files

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --list
```

## Global Goosehints for Knowledge Discovery

AgentFS knowledge bundles live at `~/.agents/knowledge/` (USER-scoped).
To make Goose aware of available knowledge without context bloat, this
skill can set up a global `.goosehints` file at `~/.config/goose/.goosehints`
that references the knowledge index.

This enables **progressive loading**: Goose sees the knowledge index
path in every session, and can read it on-demand when a task would
benefit from accumulated knowledge. The agent then follows links from
the index to specific concept documents — loading only what's relevant.

### Check Global Goosehints

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --hints-check
```

Reports whether global `.goosehints` exists and whether it references
the knowledge index.

### Install Global Goosehints

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --hints-install
```

Creates or updates `~/.config/goose/.goosehints` with a reference to
`~/.agents/knowledge/index.md`. Preserves any existing content.

### Remove Knowledge Reference

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --hints-remove
```

Removes the knowledge index reference from global `.goosehints`,
preserving other content.

## Memory Signal Routing (Layer 2 — Goose-Specific)

When multiple memory systems are active (Goose Memory, Chat Recall, Cognee,
AgentFS), natural-language signals like "remember this" create ambiguity.
This skill implements **Layer 2** of the two-layer decision table architecture
defined in AGENTS.md Guardrail #2.

The memory routing override installs a **compact stub** in Goose's persistent
instructions (`~/.config/goose/instructions.md`) that:

- Lists the Goose memory tool names to detect at runtime
- When any memory tool is detected, directs the agent to load the full
  routing table from `references/memory-routing.md` (on-demand)
- When no Goose memory tool exists, falls through directly to AGENTS.md
  Guardrail #2 with MEMORY.md defaults

The full routing table in `references/memory-routing.md` contains:

- Priority-based decision table: **Cognee (1) > Memory (2) > Chat Recall (3)**
- Runtime resolution rules (tool existence = extension enabled)
- MEMORY.md fallthrough defaults (default agent vs named profile)
- Ambiguity resolution (ask user when "forget" is unclear)
- Routing announcement (state which system and why before executing)
- Session bridge pattern for legitimate cross-session use

### Check Memory Override Status

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --memory-check
```

Reports whether the override is installed and whether the memory
extension is enabled (collision risk).

### Install Memory Override

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --memory-install
```

Appends (or updates) the routing override block in persistent
instructions. Idempotent — safe to run multiple times.

### Remove Memory Override

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --memory-remove
```

Cleanly removes the override block, preserving all other persistent
instructions content.

## Important Notes

### Session Restart Required

Goose reads `CONTEXT_FILE_NAMES` at session startup. After running this
skill, **restart your Goose session** for the changes to take effect.

### Goose Already Reads `.claude/skills/`

Goose's skill discovery (`all_skill_dirs()`) already scans:
- `.agents/skills/`, `.goose/skills/`, `.claude/skills/` (project)
- `~/.agents/skills/`, `~/.claude/skills/` (global)

This skill does NOT affect skill discovery — only context file loading.
Skills in `.claude/skills/` are already visible to Goose out of the box.

### Environment Variable Override

`CONTEXT_FILE_NAMES` can also be set as an environment variable (JSON
array). The environment variable takes precedence over `config.yaml`:

```bash
export CONTEXT_FILE_NAMES='["AGENTS.md", ".goosehints", "CLAUDE.md"]'
```

This skill configures `config.yaml` (persistent) rather than environment
variables (session-scoped).

### Token Cost

Every context file adds tokens to the system prompt. Adding too many
large context files increases cost and may reduce performance. Only add
files that provide value for your workflow.

## Undo

```bash
# Reset to Goose defaults
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --reset

# Or remove specific files
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --remove CLAUDE.md
```

## How It Works

The script uses `python3` with `pyyaml` (or falls back to `sed`) to
read and update `~/.config/goose/config.yaml`. It:

1. Reads the current `CONTEXT_FILE_NAMES` value (or uses the Goose
   default `[".goosehints", "AGENTS.md"]` if not set)
2. Adds the requested filenames (deduplicating)
3. Writes the updated list back to `config.yaml`
4. Creates a timestamped backup before modifying

## Compatibility Matrix

| Feature | Before This Skill | After This Skill |
|---------|:-:|:-:|
| Goose reads `AGENTS.md` | ✅ | ✅ |
| Goose reads `.goosehints` | ✅ | ✅ |
| Goose reads `CLAUDE.md` | ❌ | ✅ |
| Goose reads `.cursorrules` | ❌ | ✅ (with `--all`) |
| Goose reads `.windsurfrules` | ❌ | ✅ (with `--all`) |
| Goose reads `.claude/skills/` | ✅ (native) | ✅ (native) |
| Goose reads `.agents/skills/` | ✅ (native) | ✅ (native) |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-14 19:17 | v1.4 — Moved full memory routing table to on-demand `references/memory-routing.md`; instructions.md stub now lists tool names to detect and loads full table only when memory tools are present; reduces auto-loaded context by ~57 lines per turn |
| 2026-07-10 16:14 | v1.3 — Replaced flat signal→action table with priority-based decision table supporting Cognee (pri 1), Memory (pri 2), Chat Recall (pri 3); added runtime resolution rule (check tool existence in available tools list); static table adapts to dynamic extension enable/disable; added ambiguity resolution and routing announcement rules; aligns with AGENTS.md Guardrail #9 two-layer architecture |
| 2026-07-09 01:42 | v1.2 — Added global goosehints for knowledge discovery: --hints-check, --hints-install, --hints-remove; progressive knowledge loading via plain reference to ~/.agents/knowledge/index.md |
| 2026-07-09 00:52 | v1.1 — Added memory collision avoidance: --memory-check, --memory-install, --memory-remove; routing override for Goose memory extension trigger words; profile-scoped MEMORY.md support for subagents |
| 2026-07-07 16:49 | v1.0 — Initial skill: --check, --add, --remove, --all, --reset, --list |
