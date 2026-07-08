---
name: agentfs-setup
description: >
  Initialize the DotAgents (.agents/) directory structure in one of two modes:
  USER mode (root=~, shared skills and knowledge across projects and agents)
  or PROJECT mode (root=., per-project agent context with multi-agent
  collaboration support via profiles, shared skills/knowledge, and per-agent
  SOUL + memories). PROJECT mode is the default. USER mode creates only
  skills/ and knowledge/ — it MUST ignore 'with git' and 'with spec' signals
  even if present. PROJECT mode seeds SOUL.md, memories/USER.md, and
  memories/MEMORY.md for the default agent, and optionally initializes git
  and/or Spec-kit when signaled. Named agent profiles are created by the
  companion 'agentfs-profile' skill.
---

# Agent FS Setup

Set up the DotAgents directory structure (`.agents/`) in one of two modes.

## Idempotent Behavior

This skill is **idempotent**. If triggered against a directory that has
already been set up, it MUST NOT overwrite any existing files or content.
Instead, the agent should:

1. **Detect** that `.agents/` already exists at the target root.
2. **Skip creation phases** (Phases 0–4) — do NOT re-run scaffold,
   seed, or init scripts against an already-set-up directory.
3. **Run verify with `--fix`** — this validates the structure, checks
   link integrity, and repairs only what is missing without touching
   existing content:

```bash
# PROJECT mode (auto-detect git/spec from what exists on disk):
bash <skill-dir>/scripts/verify-setup.sh --mode project --fix <project-root>

# USER mode:
bash <skill-dir>/scripts/verify-setup.sh --mode user --fix <home-dir>
```

4. **Report** the results — show what passed, what was fixed, and what
   (if anything) still needs manual attention.

The `--fix` flag tells the verify script to create any missing
directories or seed files (using the same templates as the scaffold
script) **without overwriting** anything that already exists. Items
that were repaired are marked `← fixed` in the output.

### How the agent decides: fresh setup vs re-run

```
if .agents/ directory exists at target root:
    → Re-run mode: skip phases, run verify --fix, report
else:
    → Fresh setup: run phases 0–5 as documented below
```

| Aspect | USER mode | PROJECT mode (default) |
|--------|-------------|----------------------|
| Root directory | `~` (user home) | `.` (current directory / repo root) |
| Purpose | Shared skills & knowledge across projects and agents | Per-project agent context with multi-agent collaboration |
| Directories created | `skills/`, `knowledge/` | `profiles/`, `skills/`, `knowledge/`, `memories/` |
| Files created | `index.md`, `log.md` | `index.md`, `log.md`, `SOUL.md`, `memories/USER.md`, `memories/MEMORY.md` |
| Spec-kit | Not involved | Optional — auto-initialized when user signals "with spec" |
| Git | Not involved | Optional — auto-initialized when user signals "with git" |
| AGENTS.md | Not created | Created at repo root |

### Natural-Language Signals for Mode Selection

| Signal keywords | Mode selected |
|-----------------|---------------|
| "user mode", "in user mode", "for user" | USER mode (`--mode user`, root=`~`) |
| "shared skills", "global setup", "user-level", "across projects" | USER mode |
| "project mode", "in project mode", "for this project" | PROJECT mode (explicit) |
| *(no mode signal)* | **PROJECT mode** (default) |

If the user's prompt does not mention any mode keyword, default to
**PROJECT mode** in the current working directory. Only use USER mode
when the user explicitly signals it.

### Natural-Language Signals for Optional Features (PROJECT mode)

When the user's prompt includes wording that signals **git** or **spec-kit**,
the skill automatically includes those initialization steps:

| Signal keywords | What happens |
|-----------------|--------------|
| "with git", "init git", "include git", "and git" | Runs `init-git.sh` — initializes a git repo if not already present |
| "with spec", "with spec-kit", "init spec", "include spec-kit", "and spec" | Runs `init-speckit.sh` — presents agent selection, waits 15s, defaults to `goose` |
| Both signals together | Runs git init first, then Spec-kit init |
| No signal | Neither git nor Spec-kit is initialized (original behavior) |

These signals apply to **PROJECT mode only**. **USER mode MUST ignore
"with git" and "with spec" signals entirely** — even if the user includes
them. Git and Spec-kit are project-scoped concerns and have no place at
the system level. If the user asks for USER mode with these signals,
proceed with USER mode setup only and do not run `init-git.sh` or
`init-speckit.sh`.

For the full design specification, see
[references/design-spec.md](references/design-spec.md).

## Prompt Stacking Order

When an agent assembles its system prompt from `.agents/` resources:

```
1. SOUL.md           ← "Who am I?" — agent identity (human-authored)
2. AGENTS.md         ← "How does this project work?" — project rules (human-authored)
3. skills/           ← Available capabilities (shared across agents)
4. knowledge/        ← Domain context (shared across agents)
5. MEMORY.md         ← "What have I learned?" — project/env facts (agent-learned)
6. USER.md           ← "Who are they?" — user profile (agent-learned)
```

Items 1, 5, 6 are per-agent. Items 2, 3, 4 are shared across all agents.

## Prerequisites

- **USER mode**: No prerequisites beyond shell access.
- **PROJECT mode (base)**: No hard prerequisites — the skill scaffolds `.agents/` and `AGENTS.md`.
- **PROJECT mode + "with git"**: `git` must be installed on the system (but the repo doesn't need to be initialized yet — the skill does that).
- **PROJECT mode + "with spec"**: The `specify` CLI must be on PATH.
  Install with: `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@<tag>`
  Or use the `spec-kit-setup` skill to install/upgrade it first.

## USER Mode Setup

USER mode creates a lightweight `.agents/` tree under `~` as a shared
library of skills and knowledge visible across all projects and agents.

### What gets created

```text
~/
└── .agents/
    ├── index.md              # Directory listing (OKF entry point)
    ├── log.md                # Append-only activity tracker
    ├── skills/               # Shared Agent Skills (SKILL.md folders)
    │   └── index.md          # Skills directory
    └── knowledge/            # Shared knowledge base (OKF format)
        └── index.md          # Knowledge directory
```

**Not created in USER mode:** `SOUL.md`, `profiles/`, `memories/`.
These are agent-scoped or project-scoped concerns.

### Run

```bash
bash <skill-dir>/scripts/scaffold-dotagents.sh --mode user
```

The script is idempotent — it skips files that already exist.

### Git & Spec-kit

Not involved — **ever**. USER mode is purely a shared capability and
knowledge store. Git and Spec-kit are project-scoped tools and MUST NOT
be initialized at `~`. If the user's prompt includes "with git" or
"with spec" alongside a USER mode signal, **silently ignore those
signals** and proceed with USER mode setup only.

## PROJECT Mode Setup (default)

PROJECT mode creates the full `.agents/` tree under the current directory
(typically a git repo root) with all layers needed for multi-agent
collaboration: a default agent identity (SOUL.md), profiles for named
agents, shared skills and knowledge, per-agent memories, plus an
`AGENTS.md` entry point.

### What gets created

```text
./ (Repository Root)
├── AGENTS.md                     # Workspace entry point for coding agents
└── .agents/
    ├── index.md                  # Directory listing (OKF entry point)
    ├── log.md                    # Append-only activity tracker
    ├── SOUL.md                   # Default agent identity (human-authored)
    ├── profiles/                 # Named agent profiles (agentfs-profile skill)
    │   └── index.md              # Profile directory listing
    ├── skills/                   # Project-scoped Agent Skills (shared)
    │   └── index.md              # Skills directory
    ├── knowledge/                # Semantic context (OKF, shared)
    │   └── index.md
    └── memories/                 # Default agent's learned context
        ├── USER.md               # Default agent's model of the user
        └── MEMORY.md             # Default agent's learned project facts
```

### Phase 0 — Initialize git (optional, when "with git" signaled)

Only run this phase if the user's prompt signals git initialization.

```bash
bash <skill-dir>/scripts/init-git.sh <project-root>
```

Initializes a git repository if one doesn't already exist. Creates a
sensible `.gitignore` that excludes `.agents/memories/` (agent-managed
data shouldn't be version-controlled). Idempotent — skips if already
a repo.

### Phase 1 — Scaffold the .agents/ directory

```bash
bash <skill-dir>/scripts/scaffold-dotagents.sh --mode project
# or simply (PROJECT is the default):
bash <skill-dir>/scripts/scaffold-dotagents.sh
```

### Phase 2 — Create AGENTS.md

```bash
bash <skill-dir>/scripts/seed-agents-md.sh <project-root>
```

Creates `AGENTS.md` at the repository root with:
- Quick orientation table pointing to `.agents/`
- Operational guardrails (read constitution, use progressive disclosure)
- **Agent Profiles table** listing all registered agents with links to
  their SOUL.md and memories/ directory (starts with the `default` agent)
- `<!-- SPECKIT START -->` / `<!-- SPECKIT END -->` markers for Spec-kit's
  agent-context extension to manage (if Spec-kit is used later)

If `AGENTS.md` already exists, the script ensures both the SPECKIT markers
and the Agent Profiles table are present, leaving existing content untouched.

### Phase 3 — Rename the agent context file (optional)

If the repository already has an agent-specific context file (`CLAUDE.md`,
`COPILOT.md`, `GEMINI.md`, etc.) from a prior `specify init`, rename it
to the vendor-neutral `AGENTS.md`:

```bash
bash <skill-dir>/scripts/rename-agent-context.sh <project-root>
```

If `AGENTS.md` already exists, the agent file content is merged into it.

### Phase 4 — Initialize Spec-kit (optional, when "with spec" signaled)

Only run this phase if the user's prompt signals Spec-kit initialization.

The `init-speckit.sh` script supports two calling modes:

#### From an agent console (non-interactive — preferred)

Since agent tool runners (shell, automation_script) have no live stdin,
the agent must handle the user interaction itself:

1. **Get the agent list** — run `bash <skill-dir>/scripts/init-speckit.sh --list`
   to capture the numbered menu as plain text.
2. **Reproduce the full numbered list in your chat response** so the user
   can see it directly in the conversation — do NOT just reference the
   tool output, because on Goose Desktop the shell output is collapsed
   inside an "Output" panel and the user may not see it. Copy/paste the
   list into your reply and ask the user to pick a number or name
   (or accept the default `goose`).
3. **Call the script with `--agent`** once you have the answer:

```bash
bash <skill-dir>/scripts/init-speckit.sh --agent goose <project-root>
# or whatever the user chose:
bash <skill-dir>/scripts/init-speckit.sh --agent claude <project-root>
```

If the user doesn't respond or says "default", use `--agent goose`.

#### From a real terminal (interactive)

When run without `--agent`, the script displays the full numbered menu,
waits 15 seconds for input, and defaults to `goose` on timeout:

```bash
bash <skill-dir>/scripts/init-speckit.sh <project-root>
```

#### What the script does

1. Checks that `specify` CLI is available on PATH.
2. Validates the agent name against the known list of 37 integrations.
3. Runs `specify init <project-root> --force --integration <agent>`.

### Phase 5 — Verify

Pass `--with-git` and/or `--with-spec` **only** if those features were
actually requested during setup. Without them, the script only verifies
the base `.agents/` structure — it will NOT check for git or Spec-kit
even if they happen to exist on disk.

```bash
# Base project (no git/spec signals):
bash <skill-dir>/scripts/verify-setup.sh --mode project <project-root>

# With spec only:
bash <skill-dir>/scripts/verify-setup.sh --mode project --with-spec <project-root>

# With both git and spec:
bash <skill-dir>/scripts/verify-setup.sh --mode project --with-git --with-spec <project-root>
```

Add `--fix` to automatically repair missing files/directories without
overwriting existing content:

```bash
bash <skill-dir>/scripts/verify-setup.sh --mode project --fix <project-root>
```

The `--fix` flag also validates link integrity in `index.md` and checks
profile completeness for any existing named profiles.

All items should show `[✓]`. Items repaired by `--fix` show `← fixed`.

## Multi-Agent Collaboration (PROJECT mode)

PROJECT mode supports multiple agents working together on the same project.

### Shared layers (all agents see these)
- **`skills/`** — Project-scoped agent workflows
- **`knowledge/`** — Semantic context and domain knowledge
- **`AGENTS.md`** — Project rules and conventions

### Per-agent layers (scoped to each agent)
- **`SOUL.md`** — Agent identity and personality (human-authored)
- **`memories/USER.md`** — Agent's model of the user (agent-learned)
- **`memories/MEMORY.md`** — Agent's learned project/environment facts (agent-learned)

### The `profiles/` Directory

The `profiles/` directory serves two complementary purposes:

**1. Multi-Agent Collaboration Hub.**
Named agent profiles enable multiple AI agents to collaborate on the same
project while maintaining distinct identities and memory spaces. This
design is **compatible with Hermes Agent out of the box** — the file
structure (`SOUL.md`, `memories/USER.md`, `memories/MEMORY.md`) maps
directly to Hermes's own profile concept, requiring no adaptation.

**2. ROLE-Based Agent Specialization.**
Each profile is equivalent to defining a different **ROLE**. A profile
carries its own identity (`SOUL.md`), its own learned project memory
(`memories/MEMORY.md`), and its own user model (`memories/USER.md`).
Skills and knowledge remain shared. All profiles follow the **same
guardrails** defined in the project-root `AGENTS.md` — link integrity,
log currency, index currency, progressive disclosure, and skill
placement rules apply equally to every agent, regardless of which
profile it operates under. This ensures coherent, predictable behavior
across all collaborating agents.

### Default agent vs named profiles

The **default agent** uses files at the `.agents/` root:
- `.agents/SOUL.md`
- `.agents/memories/USER.md`
- `.agents/memories/MEMORY.md`

**Named agents** get their own profile under `.agents/profiles/<name>/`:
- `.agents/profiles/<name>/SOUL.md`
- `.agents/profiles/<name>/memories/USER.md`
- `.agents/profiles/<name>/memories/MEMORY.md`

Profiles are created by the companion **`agentfs-profile`** skill.

### Agent Profiles table in AGENTS.md

`AGENTS.md` includes an **Agent Profiles** table that serves as the
agent-agnostic registry of all profiles in the project. Any agent
reading `AGENTS.md` can discover all available profiles and navigate
to their identity and memory files:

```markdown
## Agent Profiles

| Agent | Identity | Memories |
|-------|----------|----------|
| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |
| hermes | [SOUL](./.agents/profiles/hermes/SOUL.md) | [memories/](./.agents/profiles/hermes/memories/MEMORY.md) |
| tester | [SOUL](./.agents/profiles/tester/SOUL.md) | [memories/](./.agents/profiles/tester/memories/MEMORY.md) |
```

Links use the `./` prefix to ensure dot-directories (`.agents/`) render
correctly as clickable links on GitHub and other markdown renderers.

- The `default` row is created by `seed-agents-md.sh` during initial setup.
- Named profile rows are appended automatically by `create-profile.sh`
  (from the `agentfs-profile` skill) when a new profile is created.
- The table is idempotent — duplicate registrations are detected and skipped.

## Spec-kit Integration (PROJECT mode, optional)

Spec-kit can be initialized as part of this skill's setup by signaling
"with spec" in your prompt. Alternatively, you can still run it manually
afterward:

```bash
specify init . --force --integration <agent>
```

The full list of supported integrations (37 agents):

> `agy`, `amp`, `auggie`, `bob`, `claude`, `cline`, `codebuddy`, `codex`,
> `copilot`, `cursor_agent`, `devin`, `firebender`, `forge`, `gemini`,
> `generic`, **`goose`** (default), `hermes`, `iflow`, `junie`, `kilocode`,
> `kimi`, `kiro_cli`, `lingma`, `omp`, `opencode`, `pi`, `qodercli`,
> `qwen`, `roo`, `rovodev`, `shai`, `tabnine`, `trae`, `vibe`, `windsurf`,
> `zcode`, `zed`

When using the integrated flow (`init-speckit.sh`):
- **In an agent console:** The agent retrieves the list (`--list`),
  reproduces it directly in the chat response (not just in the tool
  output), and calls the script with `--agent <name>` after the user
  picks.
- **In a real terminal:** The script shows an interactive menu, waits
  15 seconds, and defaults to `goose` on timeout.

This installs Spec-kit's own slash commands (e.g., `/speckit.plan`,
`/speckit.specify`) via the agent's native mechanism (skills, commands,
recipes) and manages its `specs/` directory at the repo root.

**Key design decision:** We do NOT redirect `specs/` into `.agents/specs/`.
Spec-kit manages `specs/` at the repo root through its own machinery
(`feature.json`, `create-new-feature.sh`, command templates). Trying to
override these paths adds fragile overrides that break on Spec-kit upgrades.
Instead, `.agents/` and `specs/` coexist as sibling directories:

```text
./ (Repository Root)
├── AGENTS.md
├── .agents/           ← DotAgents (this skill)
│   ├── SOUL.md
│   ├── profiles/
│   ├── skills/
│   ├── knowledge/
│   └── memories/
├── .specify/          ← Spec-kit engine (managed by specify CLI)
│   └── ...
└── specs/             ← Spec-kit output (managed by specify CLI)
    └── ...
```

The `AGENTS.md` file carries `<!-- SPECKIT START/END -->` markers so
Spec-kit's agent-context extension can auto-update the plan reference.
The `.agents/index.md` links to `specs/` for discoverability.

## Maintaining the Layers

These layers are managed independently after setup:

- **SOUL** (PROJECT only) — Edit `.agents/SOUL.md` to define the default
  agent's identity. Named agents have their own SOUL in their profile.
- **Profiles** (PROJECT only) — Use the `agentfs-profile` skill to
  create named agent profiles under `.agents/profiles/`. The script
  auto-updates `profiles/index.md` with links to both SOUL.md and
  memories/, plus a timestamp. Entries are sorted newest-first.
- **Skills** — Create Agent Skills folders under `.agents/skills/` with
  `SKILL.md` + optional bundled resources. Shared across all agents.
  **Always run the `skill-index` skill** (not manual edits) to
  regenerate `skills/index.md` when adding, renaming, modifying, or
  removing skills — in both USER (`~/.agents/skills/`) and PROJECT
  (`./.agents/skills/`) scopes. This is mandatory regardless of the
  agent's current working directory.
- **Knowledge** — Add OKF concept files under `.agents/knowledge/` with
  YAML frontmatter containing a `type` field. Update `knowledge/index.md`.
  Shared across all agents.
- **Memories** (PROJECT only) — Agents update `memories/USER.md` and
  `memories/MEMORY.md` proactively during conversations.
- **Log** — Append activity entries to `.agents/log.md` under the current
  ISO 8601 timestamp heading (`## YYYY-MM-DD HH:MM`) after significant
  actions.
- **Index** — Update `.agents/index.md` when adding new layers or categories.
  Update `skills/index.md` and `profiles/index.md` per the Index Currency
  guardrail (AGENTS.md §6).

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-07 16:52 | v2.9 — Added Cross-Agent Context Discovery guardrail (§7) to AGENTS.md template; instructs agents to discover and load CLAUDE.md, .cursorrules, .windsurfrules, and .github/copilot-instructions.md as supplementary project guidelines |
| 2026-07-07 16:04 | v2.8 — Added guardrails §6 bullets: mandatory `skill-index` skill invocation (not manual edits) for skills/index.md regeneration; mandatory `log.md` scope-aware updates; updated AGENTS.md template and live AGENTS.md; clarified skill-index requirement in Maintaining the Layers section |
| 2026-06-30 23:49 | v2.7 — Expanded guardrail §2 (Log Currency): explicit USER/PROJECT/sub-bundle scope; mandatory logging on skill/concept changes; standardized `log.md` format (title `# Directory Update Log`, comment, `- ` entries); updated scaffold and verify log seeds |
| 2026-06-30 23:36 | v2.6 — Guardrail §3 (Content File Currency) now requires `YYYY-MM-DD HH:MM` timestamps in Changelog tables; all existing changelog entries updated to include HH:MM |
| 2026-06-30 23:31 | v2.5 — Renamed index column `Added` → `Updated`; increased timestamp precision to `YYYY-MM-DD HH:MM` across all index.md seeds, log.md seeds, and script `date` calls; updated guardrails §2 and §6 to use timestamp headings |
| 2026-06-30 23:16 | v2.4 — Added Index Currency guardrail (§6) to AGENTS.md template; profiles/index.md schema now has Identity + Memories + Updated columns sorted newest-first; skills/index.md uses Updated column sorted newest-first; expanded profiles/ narrative with dual-purpose (multi-agent hub + ROLE-based specialization) and Hermes OOTB compatibility; updated Maintaining the Layers section |
| 2026-06-30 18:30 | v2.3 — Added `profiles/index.md`; all `profiles/` links now point to `profiles/index.md`; all `memories/` links now point to `memories/MEMORY.md`; verify checks `profiles/index.md` existence |
| 2026-06-30 17:45 | v2.2.1 — All mutating scripts (`seed-agents-md.sh`, `init-speckit.sh`, `rename-agent-context.sh`) now append entries to `.agents/log.md` per the Log Currency guardrail |
| 2026-06-30 17:30 | v2.2 — Idempotent re-run: agent detects existing `.agents/` and skips creation phases; `verify-setup.sh --fix` repairs missing files/dirs without overwriting; link integrity checks; profile completeness checks; `skills/index.md` seeded instead of `.gitkeep` |
| 2026-06-30 16:30 | v2.1.2 — Fixed `index.md` link convention: all relative links now use `./` prefix (e.g., `./log.md`, `./skills/index.md`) for consistent rendering across GitHub, VS Code, and other markdown viewers |
| 2026-06-30 16:00 | v2.1.1 — Fixed `rename-agent-context.sh` sed bug: replaced `sed -i c\` (breaks on multi-line content with regex metacharacters) with `awk` block replacement for SPECKIT marker merging |
| 2026-06-30 15:30 | v2.1 — Added Agent Profiles table to AGENTS.md; `seed-agents-md.sh` creates default row and retrofits existing files; `create-profile.sh` auto-registers new profiles |
| 2026-06-30 14:00 | v2.0 — Renamed SYSTEM → USER mode; `memory/` → `memories/`; `roles/` → `profiles/`; added SOUL.md, USER.md, MEMORY.md; removed constitution.md (Spec-kit owns it); multi-agent collaboration design; prompt stacking order; `agentfs-profile` companion skill |
| 2026-06-26 22:00 | v1.1 — Optional git/spec-kit init; verify opt-in flags; index.md link fix; bash arithmetic bug fix |
| 2026-06-26 14:00 | v1.0 — Initial design: USER/PROJECT dual-mode, Spec-kit coexistence |
