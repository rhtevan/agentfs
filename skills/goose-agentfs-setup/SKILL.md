---
name: goose-agentfs-setup
description: >
  configure goose agentfs, goose context files, goose agentfs, sync goose agentfs, activate profile
argument-hint: "Optionally specify which context files to add (e.g., CLAUDE.md, .cursorrules)"
compatibility: "Requires Goose with config.yaml support (v1.30+)"
metadata:
  author: agentfs
  version: "1.7.0"
  model-tier: T2
  tags: [goose, agentfs, configuration, compatibility, system-prompt]
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
defined in the Signal Dispatch rule in AGENTS.md.

The memory routing override installs a **compact stub** in Goose's persistent
instructions (`~/.config/goose/instructions.md`) that:

- Lists the Goose memory tool names to detect at runtime
- When any memory tool is detected, directs the agent to load the full
  routing table from `references/memory-routing.md` (on-demand)
- When no Goose memory tool exists, falls through directly to AGENTS.md
  Signal Dispatch rule with MEMORY.md defaults

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


## Plugin Management

AgentFS v6.0.0 introduced the `signal-dispatch` plugin
(`~/.agents/plugins/signal-dispatch/`) which uses Goose lifecycle hooks
to deterministically enforce the `hey` signal dispatch prefix. This skill
provides commands to verify and inspect plugin status.

### Check Plugin Health

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --plugin-check
```

Verifies:
- Plugin directory and files exist
- `plugin.json` and `hooks.json` are valid JSON
- Hook scripts are present and executable
- `jq` is available (required dependency)
- Plugin is not in Goose's `disabledPlugins` list

### List Discovered Plugins

```bash
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --plugin-list
```

Lists all plugins discovered from `~/.agents/plugins/` (USER scope)
and `./.agents/plugins/` (PROJECT scope) with name, version, hooks
status, and enabled/disabled state.

## System Prompt Optimization (Primacy Zone)

AgentFS rules in AGENTS.md normally land in the "dead zone" of Goose's system
prompt (after skills and extensions, where attention decays). This feature
promotes AGENTS.md rules to the **primacy zone** (right after Goose identity,
before extensions) via a custom `system.md` template.

SOUL.md identity is delivered separately by the **tom (Top Of Mind) extension**,
which reads `instructions.md` and injects its content into `<turn-context>`
every turn (**recency peak**). The tom extension must be enabled — without it,
SOUL content never reaches the model and weaker models will confabulate identity.

### Architecture

```
System prompt (system role — read once at session start):
  Position 0%:     Goose identity (2 lines)
  Position 1-40%:  AGENTS.md rules (primacy zone) ← custom system.md
  Position 40%:    Turn Context explanation ({% raw %}{{ moim_system_prompt_block }}{% endraw %})
  Position 40-80%: Extensions
  Position 80%:    Response Guidelines

Per-turn user message (recency peak — every turn):
  <turn-context>
    current-time, working-directory
    SOUL.md content ← tom extension reads instructions.md
    turn-budget (when applicable)
  </turn-context>
```

### Dependencies

| Extension | Required | Purpose |
|-----------|:--------:|---------|
| **tom** (Top Of Mind) | ✅ | Reads `instructions.md`, injects SOUL into `<turn-context>` per turn |
| **KGM** (Knowledge Graph Memory) | ✅ | Signal dispatch skill/knowledge lookup via `search_nodes` |
| **signal-dispatch** plugin | ✅ | Deterministic `hey` prefix enforcement via lifecycle hooks |

### Sync Signal

```
hey sync goose agentfs
```

Runs the full sync: first delegates to `agentfs-setup` (`sync-agents-md.sh`)
to ensure the project AGENTS.md is current against the template source of
truth (`seed-agents-md.sh`), then drift-checks the pinned Goose system.md
base template, generates custom `~/.config/goose/prompts/system.md` with
the up-to-date AGENTS.md at the primacy zone, and writes SOUL.md to MOIM
persistent instructions.

### Commands

```bash
# Check current status
bash ~/.agents/skills/goose-agentfs-setup/scripts/system-md-gen.sh --check

# Generate custom system.md + MOIM SOUL (with drift check)
bash ~/.agents/skills/goose-agentfs-setup/scripts/system-md-gen.sh

# Drift check only
bash ~/.agents/skills/goose-agentfs-setup/scripts/system-md-gen.sh --drift-check

# Reset to Goose default (remove custom system.md)
bash ~/.agents/skills/goose-agentfs-setup/scripts/system-md-gen.sh --reset
```

### One-Time Setup

Remove AGENTS.md from `CONTEXT_FILE_NAMES` to prevent double-loading:

```yaml
# ~/.config/goose/config.yaml
CONTEXT_FILE_NAMES:
  - .goosehints
  # AGENTS.md removed — now in custom system.md
```

### Profile-Scoped SOUL

Switch agent identity in-session by overwriting the MOIM SOUL section.
Takes effect on the next turn (MOIM re-reads `instructions.md` every turn).

Profile SOULs **overwrite** (not merge with) the default SOUL. Each profile
SOUL should be self-contained, inheriting desired principles from the default
at authoring time (copy-then-customize pattern).

**Signal:**

```
hey activate profile <name>      Switch to named profile
hey activate profile default     Restore project default SOUL
```

**Commands:**

```bash
# Activate a profile
bash ~/.agents/skills/goose-agentfs-setup/scripts/activate-profile.sh sre

# Restore default
bash ~/.agents/skills/goose-agentfs-setup/scripts/activate-profile.sh default

# List available profiles
bash ~/.agents/skills/goose-agentfs-setup/scripts/activate-profile.sh --list

# Show current SOUL
bash ~/.agents/skills/goose-agentfs-setup/scripts/activate-profile.sh --current
```

**Behavior:**

- Profile SOUL overwrites the `<!-- AGENTFS-SOUL -->` section in `instructions.md`
- Change is **global** — affects all active Goose sessions
- `hey sync goose agentfs` restores default SOUL (with warning if profile was active)
- Desktop sessions always use whatever SOUL is in `instructions.md`

**Pre-session isolation (env var):**

For parallel sessions with different profiles, use `GOOSE_MOIM_MESSAGE_TEXT`
(takes precedence over `instructions.md`, per-process scope):

```bash
# Terminal 1 — SRE
GOOSE_MOIM_MESSAGE_TEXT=$(cat .agents/profiles/sre/SOUL.md) goose session

# Terminal 2 — Developer
GOOSE_MOIM_MESSAGE_TEXT=$(cat .agents/profiles/developer/SOUL.md) goose session
```

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
