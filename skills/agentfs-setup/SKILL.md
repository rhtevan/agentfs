---
name: agentfs-setup
description: >
  setup agentfs, sync agentfs, update agentfs, verify agentfs
metadata:
  version: "4.19.0"
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
  loading (SOUL.md, knowledge index), and ten structural guardrails

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

The `seed-agents-md.sh` script creates `AGENTS.md` with ten guardrails
(reordered by usage frequency):

1. **Progressive Disclosure** — browse `index.md` before opening files
2. **Memory Scope & Signal Routing** — memories are PROJECT-only;
   decision table mapping NL signals to memory actions; graduation
   path to OKF; agent-specific overrides take priority
3. **Cross-Agent Context Discovery** — read CLAUDE.md, .cursorrules, etc.
4. **Skill Placement** — default to USER, PROJECT only when explicit
5. **Filesystem Integrity** — link integrity, log currency, content
   file currency, and index currency in a single guardrail
6. **Idempotency** — every skill and workflow must be idempotent
7. **Anti-Sycophancy** — refuse conflicting requests, log overrides
8. **Anti-Daydreaming** — ephemeral session canary name; spot-check
   for context drift; never persisted to AgentFS files
9. **Checkpoints & Resumability** — checkpoint before destructive ops
10. **Git Push Safety** — mandatory 5-step preflight before any
    `git push`: stop → scan → present report → wait for approval → push

## Layer Reference

| Layer | USER (`~/.agents/`) | PROJECT (`./.agents/`) |
|-------|-----------|---------------|
| Identity | — | `.agents/SOUL.md` |
| Profiles | — | `.agents/profiles/` |
| Capability | `~/.agents/skills/` | `.agents/skills/` |
| Knowledge | `~/.agents/knowledge/` | — |
| Memories | — | `.agents/memories/` |
| Workspace | — | `AGENTS.md` |

## Supporting Files

- `scripts/scaffold-dotagents.sh` → `load_skill(name: "agentfs-setup/scripts/scaffold-dotagents.sh")`
- `scripts/seed-agents-md.sh` → `load_skill(name: "agentfs-setup/scripts/seed-agents-md.sh")`
- `scripts/sync-agents-md.sh` → `load_skill(name: "agentfs-setup/scripts/sync-agents-md.sh")`
- `scripts/verify-setup.sh` → `load_skill(name: "agentfs-setup/scripts/verify-setup.sh")`
- `references/design-spec.md` → `load_skill(name: "agentfs-setup/references/design-spec.md")`

## Companion Skills

- **`agentfs-profile`** — Create named agent profiles under `.agents/profiles/`
- **`goose-agentfs-setup`** — Configure Goose's `CONTEXT_FILE_NAMES` for
  cross-agent context file discovery
- **`hermes-agentfs-setup`** — Configure Hermes's `skills.external_dirs`
  for AgentFS skill discovery


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
