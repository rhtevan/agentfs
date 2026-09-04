---
name: agentfs-setup
description: >
  setup agentfs, sync agentfs, update agentfs, verify agentfs
metadata:
  version: "5.5.0"
  tags: [agentfs, setup, scaffolding, guardrails, sync]
---

# AgentFS Setup

Scaffold the `.agents/` directory tree and seed foundational files for
AgentFS — a layered, agent-agnostic context structure that works across
AI coding agents.

## Overview

| Property         | Value                                                             |
| ---------------- | ----------------------------------------------------------------- |
| **Default scope** | `project`                                                         |
| **Scopes**       | `project` (per-repo context) · `lite` (minimal per-repo) · `user` (shared library) |
| **Scripts**      | `scaffold-dotagents.sh` · `seed-agents-md.sh` · `sync-agents-md.sh` · `verify-setup.sh` |
| **Design spec**  | [references/design-spec.md](./references/design-spec.md)          |

## Scope Definitions

AgentFS operates in two scopes. These definitions are canonical.

| Scope | Root Path | Resolves To | Purpose |
|-------|-----------|-------------|----------|
| **USER** | `~/.agents/` | `/home/<user>/.agents/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |
| **PROJECT** | `./.agents/` | `<repo-root>/.agents/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |

### What Lives Where

| Resource | USER (`~/.agents/`) | PROJECT (`./.agents/`) |
|----------|:-------------------:|:----------------------:|
| `skills/` | ✅ shared | ✅ project-specific |
| `knowledge/` | ✅ shared | ❌ never |
| `memories/` | ❌ never | ✅ per-agent |
| `profiles/` | ❌ never | ✅ multi-agent |
| `SOUL.md` | ❌ never | ✅ agent identity |
| `AGENTS.md` | ❌ never | ✅ (at repo root `./`) |
| `index.md` | ✅ | ✅ |
| `log.md` | ✅ | ✅ |

## Prerequisites: USER Scope Setup

Before running PROJECT scope, `~/.agents/` must exist. There are two
paths to set it up:

### Path A: Full Install (recommended)

Clone the published AgentFS repository directly into `~/.agents/`:

```bash
git clone https://github.com/rhtevan/agentfs.git ~/.agents
```

This gives the complete skill library, knowledge bundles, and
structural scaffolding — ready to use immediately.

### Path B: Minimal Install

For users who want a clean, empty `~/.agents/` and prefer to
cherry-pick skills selectively:

1. Clone the repo to a **staging location** (not `~/.agents/`):
   ```bash
   git clone https://github.com/rhtevan/agentfs.git ~/repos/agentfs
   ```
2. Make the staging location visible to the agent (e.g., add
   `~/repos/agentfs/skills/` to the agent's skill search paths
   — see the relevant agent setup skill for details).
3. Ask the agent to run this skill with USER scope:
   > *"Set up AgentFS in USER scope"*

   The agent loads this skill, recognises the USER scope hint, and
   scaffolds an empty `~/.agents/` with `skills/`, `knowledge/`,
   `index.md`, and `log.md`.
4. Cherry-pick specific skills using the `skill-merge` skill or
   manual copy.

### After USER Setup: Agent Configuration

Each agent needs its own setup to discover AgentFS context files:

| Agent | Setup Skill |
|-------|-------------|
| Goose | `goose-agentfs-setup` |
| Hermes | `hermes-agentfs-setup` |

## Usage

### PROJECT scope (default — run once per repo)

Ask the agent to run this skill in the target repo:

> *"Set up AgentFS for this project"*

Since PROJECT is the default scope, no additional scope hint is needed.
The agent runs the following scripts:

```bash
# 1. Scaffold .agents/ directory
bash ~/.agents/skills/agentfs-setup/scripts/scaffold-dotagents.sh --scope project

# 2. Create AGENTS.md at repo root
bash ~/.agents/skills/agentfs-setup/scripts/seed-agents-md.sh
```

Creates:
- `.agents/skills/` — project-scoped agent workflows
- `.agents/profiles/` — named agent profiles for multi-agent collaboration
- `.agents/memories/` — default agent's experiences and user model
- `.agents/SOUL.md` — default agent identity
- `.agents/index.md`, `log.md`
- `AGENTS.md` — workspace entry point with scope definitions, progressive
  loading (SOUL.md, knowledge index), and twelve structural rules

### USER scope (minimal install only)

Ask the agent to run this skill with a USER scope hint:

> *"Set up AgentFS in USER scope"*

The agent runs:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/scaffold-dotagents.sh --scope user
```

Creates an empty structural skeleton:
- `~/.agents/skills/` — shared agent workflows (initially empty)
- `~/.agents/knowledge/` — shared OKF knowledge bundles (initially empty)
- `~/.agents/index.md`, `log.md`

> **Note:** If you used Path A (full clone), this step is unnecessary —
> the clone already contains the complete structure.

### LITE scope (minimal project for small-context models)

LITE scope creates a minimal AgentFS for projects consumed by
small-context models (e.g., Granite 3B at 16K context). No skills,
profiles, or knowledge — only identity and memories.

**Scope auto-detection:** The scripts detect LITE scope automatically.
When a target directory is passed and it resolves to a different path
than CWD, the scripts infer LITE scope. The agent does NOT need to
decide — just pass the path. Examples:

| User says | What the agent runs |
|---|---|
| *"Set up AgentFS"* | `scaffold-dotagents.sh` (no path → PROJECT) |
| *"Set up AgentFS at ~/projects/foo"* | `scaffold-dotagents.sh ~/projects/foo` (auto-LITE) |
| *"Sync AgentFS at ~/projects/foo"* | `sync-agents-md.sh ~/projects/foo` (auto-LITE via metadata) |

The agent runs:

```bash
# Just pass the target directory — scope is auto-detected
bash ~/.agents/skills/agentfs-setup/scripts/scaffold-dotagents.sh <TARGET_DIR>
bash ~/.agents/skills/agentfs-setup/scripts/seed-agents-md.sh <TARGET_DIR>
```

The scripts compare `<TARGET_DIR>` against CWD. Different path → LITE.
Same path (or no path) → PROJECT.

Creates (LITE):
- `.agents/memories/` — default agent's experiences and user model
- `.agents/SOUL.md` — default agent identity
- `.agents/index.md`, `log.md`
- `AGENTS.md` — lite workspace entry point with 6 simplified rules
  (~850 tokens, no script dependencies)

**Not created:** `skills/`, `profiles/`, SPECKIT markers, Agent Profiles
table, Signal Routing, full guardrails.

**Lifecycle:** LITE projects are provisioned and maintained by
full-capability sessions (with skills extension), then consumed by
developer-only sessions. A lite session cannot sync or scaffold.

### Sync mode (update existing project AGENTS.md)

When a project's AGENTS.md was created by an older template version,
use sync to bring it up to date:

> *"sync agentfs"* or *"update agentfs"*

The agent runs:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/sync-agents-md.sh [PROJECT_DIR]
```

`sync-agents-md.sh` handles the full workflow:
1. Detects scope from `agentfs-scope:` metadata in existing AGENTS.md
   (defaults to `project` for pre-4.19.0 files without the stamp)
2. Reads current template version from `<!-- agentfs-template-version: X.Y -->`
3. Compares against installed template version in `SKILL.md`
4. If versions match — reports "already up to date" and exits
5. Extracts project-owned sections (PROJECT scope only):
   - Agent Profiles rows (excluding `default` — owned by template)
   - SPECKIT block content
6. Regenerates AGENTS.md from current template via `seed-agents-md.sh`
   with the detected scope (scope is preserved — never auto-switched)
7. Re-injects preserved rows using awk (idempotent, no duplicates)
8. Reports what changed

Sync works for both PROJECT and LITE scope projects. For LITE, there
are no profile rows or SPECKIT blocks to preserve — only the template
version and scope metadata are updated.

**Agent post-sync actions (REQUIRED):**

After `sync-agents-md.sh` completes, the agent MUST inspect the output
for a `⚠️  SOUL.md` warning. If detected, the agent MUST NOT present a
raw bash command to the user. Instead, the agent MUST:

1. **Inform** the user: explain that SOUL.md defines the agent's identity
   and that the Agentic SRE default is available.
2. **Ask** the user to choose one of:
   - **Apply default** — Agentic SRE identity, no questions asked
   - **Customise** — agent asks 2–3 targeted questions, then writes SOUL.md
   - **Skip** — leave SOUL.md empty for now
3. **Execute** the user's choice by running `author-soul.sh` directly:
   - Apply default: `bash author-soul.sh --path <SOUL_PATH> --non-interactive`
   - Customise: gather answers, then write SOUL.md directly (do NOT run
     interactive shell — instead collect answers in the conversation and
     use the write tool to produce the file)
   - Skip: acknowledge and move on
4. **Confirm** the result to the user once SOUL.md is written.

**Agent post-sync Rule re-read (REQUIRED):**

After sync completes (whether the template was upgraded or already
up-to-date), the agent MUST re-evaluate its operating rules against
the current AGENTS.md. Specifically:

1. If `search_nodes` (or equivalent KGM tools) are available in the
   session **and** the knowledge graph is empty, the agent MUST load
   entities from `~/.agents/knowledge/.kgm-index.jsonl` into the live
   graph. This applies even when KGM is `enabled: false` in
   `config.yaml` — session-level availability takes precedence over
   static config.
2. This addresses a bootstrap ordering problem: when syncing from an
   older template version, the rules that mandate KGM loading (e.g.,
   Rule #1's `search_nodes` clause) only exist *after* the sync
   completes, so the agent must re-read to pick them up.

### Verification

The agent can verify the setup by running:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/verify-setup.sh [--scope user|project|lite] [--fix] [ROOT_DIR]
```

Checks all expected files/directories exist. Scope-specific:
- **PROJECT**: verifies skills/, profiles/, Scope Definitions, SPECKIT markers
- **LITE**: verifies memories/ present, skills/ and profiles/ absent,
  `agentfs-scope: lite` in AGENTS.md metadata
- **USER**: verifies skills/, knowledge/, excludes PROJECT-only files

With `--fix`, creates missing directories and seed files without
overwriting existing content.

## Structural Guardrails (in AGENTS.md)

The `seed-agents-md.sh` script creates `AGENTS.md` with twelve rules
as Trigger/Action pairs:

1. **Signal-First Dispatch** — scan skill descriptions before generic interpretation
2. **Progressive Disclosure** — browse `index.md` before opening files
3. **Cross-Agent Context Discovery** — read CLAUDE.md, .cursorrules, etc.
4. **Skill Placement** — default to USER, PROJECT only when explicit
5. **Filesystem Integrity** — log, changelog, index, link checks
6. **Git Push Safety** — `load_skill(name: "agentfs-git-push")`
7. **Checkpoints** — checkpoint before destructive ops
8. **Context Enrichment** — consult knowledge index before acting on policy/domain
9. **Memory Scope** — PROJECT-only; experiences not rules; graduation to OKF
10. **Communication Style** — no sycophancy, lead with substance, name risks
11. **Conflict Resolution** — don't reverse without new info, quote rules, log overrides
12. **Anti-Daydreaming** — ephemeral session canary name; never persisted

## Layer Reference

| Layer | USER (`~/.agents/`) | PROJECT (`./.agents/`) |
|-------|-----------|---------------|
| Identity | — | `.agents/SOUL.md` |
| Profiles | — | `.agents/profiles/` |
| Capability | `~/.agents/skills/` | `.agents/skills/` |
| Knowledge | `~/.agents/knowledge/` | — |
| Memories | — | `.agents/memories/` |
| Workspace | — | `AGENTS.md` |

## Script Input/Output Conventions

### `merge-log-entry.sh`

Writes an entry verbatim under a timestamped heading in `log.md`.
The entry text MUST be bullet-prefixed using `- `. For multi-item
entries under one heading, pass multiple bullet lines separated by
`\n`:

```bash
# Single entry
bash merge-log-entry.sh ~/.agents/log.md "- Updated README.md skill categories"

# Multi-line entry
bash merge-log-entry.sh ~/.agents/log.md "- Added SoC principle to skill-gen\n- Fixed merge-log-entry.sh comment"
```

### `merge-changelog-entry.sh`

Writes a version entry to a skill's `CHANGELOG.md`. Pass the version
without the `v` prefix — the script adds it:

```bash
bash merge-changelog-entry.sh ~/.agents/skills/my-skill/CHANGELOG.md "1.1.0" "Added new feature"
```

## Supporting Files

- `scripts/scaffold-dotagents.sh` → `load_skill(name: "agentfs-setup/scripts/scaffold-dotagents.sh")`
- `scripts/seed-agents-md.sh` → `load_skill(name: "agentfs-setup/scripts/seed-agents-md.sh")`
- `scripts/sync-agents-md.sh` → `load_skill(name: "agentfs-setup/scripts/sync-agents-md.sh")`
- `scripts/verify-setup.sh` → `load_skill(name: "agentfs-setup/scripts/verify-setup.sh")`
- `references/design-spec.md` → `load_skill(name: "agentfs-setup/references/design-spec.md")`
- `references/filesystem-integrity.md` → `load_skill(name: "agentfs-setup/references/filesystem-integrity.md")`

## KGM Integration (optional)

When the `goose-kgm` skill is installed and KGM is enabled in Goose
config, `post-edit.sh` automatically reindexes the KGM JSONL from
OKF knowledge bundles. This keeps the KGM search index in sync with
knowledge content changes. See `load_skill(name: "goose-kgm")` for
lifecycle management.

## Companion Skills

- **`goose-kgm`** — KG Memory extension lifecycle (setup/teardown/enable/disable/reindex)
- **`agentfs-profile`** — Create named agent profiles under `.agents/profiles/`
- **`goose-agentfs-setup`** — Configure Goose's `CONTEXT_FILE_NAMES` for
  cross-agent context file discovery
- **`hermes-agentfs-setup`** — Configure Hermes's `skills.external_dirs`
  for AgentFS skill discovery


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
