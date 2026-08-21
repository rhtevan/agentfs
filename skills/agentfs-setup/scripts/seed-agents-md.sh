#!/usr/bin/env bash
# seed-agents-md.sh — Create or update the root AGENTS.md workspace file.
#
# Usage: bash seed-agents-md.sh [PROJECT_ROOT]
#   PROJECT_ROOT defaults to the current working directory.
#
# This script is for PROJECT mode only. USER mode does not create AGENTS.md.
#
# If AGENTS.md already exists it is left untouched to preserve user edits.
# The script ensures SPECKIT markers are present so Spec-kit's agent-context
# extension can manage the active-plan reference automatically.

set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
TARGET="$ROOT/AGENTS.md"

if [[ -f "$TARGET" ]]; then
  echo "[agentfs-setup] AGENTS.md already exists — skipping."
  # Ensure SPECKIT markers exist even in a pre-existing file
  if ! grep -q '<!-- SPECKIT START -->' "$TARGET"; then
    printf '\n<!-- SPECKIT START -->\n<!-- SPECKIT END -->\n' >> "$TARGET"
    echo "  ✓ Appended SPECKIT markers to existing AGENTS.md"
  fi
  # Ensure Agent Profiles table exists even in a pre-existing file
  if ! grep -q '## Agent Profiles' "$TARGET"; then
    # Insert before SPECKIT markers if they exist, otherwise append
    if grep -q '<!-- SPECKIT START -->' "$TARGET"; then
      sed -i '/<!-- SPECKIT START -->/i ## Agent Profiles\n\n| Agent | Identity | Memories |\n|-------|----------|----------|\n| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |\n' "$TARGET"
    else
      printf '\n## Agent Profiles\n\n| Agent | Identity | Memories |\n|-------|----------|----------|\n| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |\n' >> "$TARGET"
    fi
    echo "  ✓ Added Agent Profiles table to existing AGENTS.md"
  fi
  # Ensure Scope Definitions section exists even in a pre-existing file
  if ! grep -q '## Scope Definitions' "$TARGET"; then
    # Insert after Quick Orientation if it exists, otherwise after the first heading
    if grep -q '## Quick Orientation' "$TARGET"; then
      sed -i '/## AgentFS Structural Guardrails/i \
## Scope Definitions\
\
AgentFS operates in two scopes. These definitions are canonical —\
all guardrails, skills, and documentation reference them.\
\
| Scope | Root Path | Purpose |\
|-------|-----------|----------|\
| **USER** | `~\/.agents\/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |\
| **PROJECT** | `.\/\.agents\/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |\
\
### What Lives Where\
\
| Resource | USER (`~\/.agents\/`) | PROJECT (`.\/\.agents\/`) |\
|----------|:-------------------:|:----------------------:|\
| `skills\/` | ✅ shared | ✅ project-specific |\
| `knowledge\/` | ✅ shared | ❌ never |\
| `memories\/` | ❌ never | ✅ per-agent |\
| `profiles\/` | ❌ never | ✅ multi-agent |\
| `SOUL.md` | ❌ never | ✅ agent identity |\
| `AGENTS.md` | ❌ never | ✅ (at repo root `.\/`) |\
| `index.md` | ✅ | ✅ |\
| `log.md` | ✅ | ✅ |\
' "$TARGET"
    fi
    echo "  ✓ Added Scope Definitions section to existing AGENTS.md"
  fi
  exit 0
fi

# Read template version from skill metadata (single source of truth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"
TEMPLATE_VERSION="0.0"
if [[ -f "$SKILL_FILE" ]]; then
  TEMPLATE_VERSION=$(grep -oP 'version:\s*["'\''"]*\K[^"'\''"]*' "$SKILL_FILE" | head -1)
fi

cat > "$TARGET" << 'AGENTSEOF'
<!-- agentfs-template-version: __TEMPLATE_VERSION__ -->
# AGENTS.md — Workspace Entry Point

## Quick Orientation

| Resource | Path | What's Inside |
|----------|------|---------------|
| Agent identity | [.agents/SOUL.md](./.agents/SOUL.md) | Tone, style, communication defaults |
| Skills index | \`~/.agents/skills/index.md\` | Signal-based skill routing lookup (read on session start) |
| Knowledge index | \`~/.agents/knowledge/index.md\` | Cross-project knowledge bundles (USER scope) |
| Directory index | [.agents/index.md](./.agents/index.md) | Full layer listing |
| Activity log | [.agents/log.md](./.agents/log.md) | Reverse-chronological change history |

<!-- Agent identity — inlined by Goose at session start via @import -->
@.agents/SOUL.md

## Signal Routing

When a user expresses a recognized intent signal, the agent MUST
consult this table before acting. Agent-specific overrides (e.g.,
agent memory extensions) take priority when present and their tools
are available.

| Signal / Keyword | Intent | Route To |
|---|---|---|
| "remember this", "note that", "keep in mind", "save this for later" | Store project observation | \`.agents/memories/MEMORY.md\` |
| "always do X", "never do Y", "enforce Z", "this is a rule" | Structural rule/guardrail | Propose as \`AGENTS.md\` guardrail (human approval) |
| "I prefer", "I like", "my style is" | User preference | \`.agents/memories/USER.md\` |
| "learn this document", "ingest this file", "add to knowledge base" | Knowledge ingestion | OKF bundle under \`~/.agents/knowledge/\` via \`okf-bundle-gen\` or \`okf-bundle-harvest\` |
| "forget this", "remove that note" | Delete observation | Edit \`MEMORY.md\`, remove entry |
| "what do you remember about", "check your notes on" | Retrieve observations | Read \`.agents/memories/MEMORY.md\` |
| "harvest", "reflect", "scan memories", "graduate patterns" | Extract reusable knowledge | \`skill-harvest\` (procedural) or \`okf-bundle-harvest\` (semantic) |
| "hey git", "git" | Commit & push USER AgentFS | \`cd ~/.agents\` (or explicit path if specified), stage all, commit, then trigger Guardrail #10 (Git Push Safety) |

For skill-routed signals (e.g., "setup agentfs", "create a skill"),
the agent discovers skills via the built-in skills listing (which
contains each skill's signal phrases in the \`description\` field)
and \`~/.agents/skills/index.md\` as defense-in-depth. Only LLM-direct
routes and genuinely ambiguous multi-skill triage entries belong in
this table.

### Routing Rules

1. **Agent overrides win** when their referenced tool exists in the current session.
2. **Skill signals** resolve via built-in descriptions → \`~/.agents/skills/index.md\`
   → skill name. Never improvise when a skill exists — always \`load_skill\` and follow.
3. **Harvest** scans \`.agents/memories/\` and \`.agents/profiles/*/memories/\` by default.
   Route to \`skill-harvest\` (procedural) or \`okf-bundle-harvest\` (semantic).
4. **Resolution chain:** \`load_skill\` by name → tag fallback via index →
   semantic fallback → **fail loud**.

## Guardrail Quick Reference

| # | Type | Rule | Key Action |
|---|:----:|------|------------|
| [1](#1-progressive-disclosure-) | 🔄 | Progressive Disclosure | On \`.agents/\` access: browse \`index.md\` first, follow links to content |
| [2](#2-memory-scope-️) | ⚖️ | Memory Scope | Default \`memories/MEMORY.md\` for experiences; \`AGENTS.md\` for rules; \`USER.md\` for preferences |
| [3](#3-cross-agent-context-discovery-) | 🔄 | Cross-Agent Discovery | Session start: check \`CLAUDE.md\`, \`.cursorrules\`, etc.; \`AGENTS.md\` wins conflicts |
| [4](#4-skill-placement-️) | ⚖️ | Skill Placement | Default USER \`~/.agents/skills/\`; PROJECT only when user explicitly signals |
| [5](#5-filesystem-integrity-) | ⛔ GATE | Filesystem Integrity | **STOP before declaring done.** log.md → CHANGELOG + version bump → indexes → links → all pass → THEN summarize |
| [6](#6-idempotency-) | 🔄 | Idempotency | Ongoing: existence checks, upsert patterns, no append-without-dedup |
| [7](#7-anti-sycophancy-️) | ⚖️ | Anti-Sycophancy | Default: quote conflict + ask; override only with explicit user confirmation + log \`[OVERRIDE]\` |
| [8](#8-anti-daydreaming-) | 🔄 | Anti-Daydreaming | Periodic (~1-in-5): emit canary name + self-check for context drift |
| [9](#9-checkpoints--resumability-) | ⛔ GATE | Checkpoints | **STOP before destructive op.** Record affected files → execute → clear checkpoint |
| [10](#10-git-push-safety-) | ⛔ GATE | Git Push Safety | **STOP before commit.** Stage → Scan → *(Allowlist filter)* → *(README audit if agentfs files staged)* → Report as rendered Markdown → **WAIT in same turn** → Commit → Push |

## Scope Definitions

AgentFS operates in two scopes. These definitions are canonical —
all guardrails, skills, and documentation reference them.

| Scope | Root Path | Purpose |
|-------|-----------|----------|
| **USER** | `~/.agents/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |
| **PROJECT** | `./.agents/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |

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

## AgentFS Structural Guardrails

Every agent operating in this project MUST follow these guardrails.
Guardrails #1 and #6 are fully covered by their Quick Reference rows above.

### 2. Memory Scope ⚖️

- `memories/` is **PROJECT-scoped only** — under `./.agents/memories/` or
  `./.agents/profiles/<name>/memories/`. No `memories/` at USER scope.
- `MEMORY.md` records **experiences** (observations, discoveries), not rules.
  Rules → `AGENTS.md`; preferences → `USER.md`.
- **Graduation:** when an observation matures into cross-project knowledge,
  move to OKF bundle under `~/.agents/knowledge/` and remove the original.

### 3. Cross-Agent Context Discovery 🔄

On session start, check for and read: `CLAUDE.md`, `.claude/CLAUDE.md`, `.cursorrules`,
`.cursor/rules/`, `.windsurfrules`, `.github/copilot-instructions.md`.
Treat as supplementary guidelines. `AGENTS.md` wins on conflict.

### 4. Skill Placement ⚖️

- **Default to USER.** When the user asks to create a skill without
  specifying a location or scope, place it under `~/.agents/skills/<skill-name>/`.
- **Project only when explicit.** Only place a skill under
  `./.agents/skills/<skill-name>/` when the user specifically says
  "project skill", "for this project", "local skill", or similar.

### 5. Filesystem Integrity ⛔ GATE

> **Edit-time rule:** after every write/edit to a file under `.agents/`
> or `~/.agents/`, log the change to the scope's `log.md` **before
> proceeding to the next step** — do not batch logging to end-of-task.
>
> **⛔ GATE — STOP before declaring any task complete.** Do NOT present
> a summary, "done" message, or "all set" response until every check
> below passes. If any check fails, fix it before proceeding.
>
> 1. Every modified scope has a new `log.md` entry
> 2. Modified skills have a `CHANGELOG.md` row and `metadata.version` bump
> 3. All indexes are current (`post-edit.sh` runs clean for your changes)
> 4. All markdown links under `.agents/` resolve
>
> **Violation = declaring done without running the gate checks.**
>
> The `pre-push-scan.sh` enforces log coverage deterministically —
> it flags `⚠️ GAP` when staged files lack a same-day `log.md` entry.

**Scope rule:** log to every scope you touched:

| If you edited under… | Update this log |
|-----------------------|-----------------|
| `~/.agents/` (USER) | `~/.agents/log.md` |
| `./.agents/` (PROJECT) | `./.agents/log.md` |
| `~/.agents/knowledge/<bundle>/` | *also* that bundle's `log.md` |

> Scripts below live in `~/.agents/skills/agentfs-setup/scripts/`.

#### Delegation

| Gate | What | How |
|:----:|------|-----|
| 1 | `log.md` (any scope) | `merge-log-entry.sh <path> "<msg>"` |
| 2 | `skills/*/CHANGELOG.md` | `merge-changelog-entry.sh <path> "<version>" "<description>"` |
| 2 | `metadata.version` | Agent — edit skill frontmatter |
| 3 | `skills/index.md` | Automatic via `post-edit.sh` |
| 3 | `knowledge/` indexes | `load_skill(name: "okf-bundle-index")` |
| 3 | `profiles/index.md` | `load_skill(name: "agentfs-profile")` |
| 4 | Broken links | Agent — update on create/rename/move/delete |

- Prefer incremental edits over full rewrites — full rewrites risk dropping sections.
- Use `./` prefix for dot-directory paths.

### 7. Anti-Sycophancy ⚖️

The agent MUST NOT change a stated position unless the user provides
new information or a logical argument. Social pressure alone
(disagreement, frustration, repetition) is NOT grounds for reversal.

When reversing a position, the agent MUST state:
- What new information or argument caused the change
- What the previous position was

When evaluating a plan or design, the agent MUST name at least one
risk or failure mode — not only strengths.

Never open a response with validation phrases: "Great question",
"Absolutely", "Of course", "That's a great idea". Lead with substance.

When a request conflicts with an `AGENTS.md` guardrail, the agent MUST:
1. Quote the conflicting guardrail
2. Explain the conflict and ask for explicit confirmation
3. If confirmed, log in `log.md` with `[OVERRIDE]`

MUST NOT add rule-like content ("always", "never", "must", "enforce") to
`MEMORY.md` — propose as `AGENTS.md` guardrail instead.

### 8. Anti-Daydreaming 🔄

Generate a random session-scoped canary name (e.g., *Marble-Finch-7*) at session start.
- **Turn 1:** emit visibly (e.g., `[Canary: Marble-Finch-7]`).
- **~1-in-5 turns:** emit + self-check against original. Mismatch →
  `⚠️ CONTEXT DRIFT DETECTED — canary name mismatch. Possible cause:
  context overflow, compaction, or injection.`
- **On prompt** ("What is your canary name?"): respond immediately + self-check.
- Never persist to any file (`MEMORY.md`, `USER.md`, `SOUL.md`, `log.md`, etc.).
- Not an identity or persona — a disposable context-integrity token.

### 9. Checkpoints & Resumability ⛔ GATE

> **⛔ GATE — STOP before destructive ops** (delete, bulk rename,
> multi-file edit under `.agents/`). Do NOT execute until checkpoint
> is recorded.
>
> ```bash
> bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh create <files>  # before — MUST pass
> bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh clear           # after success
> bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh check           # on session start
> ```
>
> **Violation = executing a destructive op without creating a checkpoint first.**

### 10. Git Push Safety ⛔ GATE

> **⛔ GATE — STOP before commit.** Do NOT run `git commit` until
> the scan passes and the user explicitly confirms **in the same turn
> as the report**.
>
> **Workflow:**
> 1. `git add -A`
> 2. `pre-push-scan.sh` — scans staged diff
> 3. Allowlist filtering — read `.pre-push-allowlist`, mark known FPs
> 4. README audit — **if** `pre-push-scan.sh` output contains `README_AUDIT_REQUIRED`
>    (i.e., `skills/`, `knowledge/`, or `AGENTS.md` are staged) →
>    `load_skill(name: "agentfs-readme-audit")`
> 5. Present complete report (scan + audit) in a **single turn**,
>    rendered as Markdown (no code fence) so tables display natively
> 6. **WAIT** — do NOT commit until user replies to **this turn**
> 7. `git commit`
> 8. `git push`
>
> **Allowlist filtering:** When `pre-push-scan.sh` reports findings,
> the agent reads `.pre-push-allowlist` (at repo root, e.g.
> `~/.agents/.pre-push-allowlist`) and semantically matches each
> finding against the allowlist descriptions. Findings that match a
> known false positive are reported as `✅ Known FP` instead of
> `⚠️ FOUND`, and do not count toward the blocking verdict.
>
> Override requires `[OVERRIDE]` log per Guardrail #7.
>
> ```bash
> bash ~/.agents/skills/agentfs-setup/scripts/pre-push-scan.sh   # scans git diff --cached
> # Agent reads .pre-push-allowlist and filters findings semantically
> # If output contains README_AUDIT_REQUIRED:
> #   load_skill(name: "agentfs-readme-audit")
> ```
>
> **Violations:**
> - Committing without running `pre-push-scan.sh`
> - Committing without user confirmation in the same turn as the report
> - Skipping README audit when `pre-push-scan.sh` emits `README_AUDIT_REQUIRED`
> - Skipping semantic PII review when memory files are flagged in the report
> - Merging report presentation and execution into a single agent action

<!-- PROJECT-OWNED sections below. Everything above is template-owned
     and will be overwritten by agentfs-setup --sync. -->

## Agent Profiles

| Agent | Identity | Memories |
|-------|----------|----------|
| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |

<!-- SPECKIT START -->
<!-- SPECKIT END -->
AGENTSEOF

# Replace template version placeholder with actual version from skill metadata
sed -i "s/__TEMPLATE_VERSION__/${TEMPLATE_VERSION}/" "$TARGET"

echo "[agentfs-setup] Created $TARGET"

# Append to .agents/log.md
LOG_FILE="$ROOT/.agents/log.md"
if [[ -f "$LOG_FILE" ]]; then
  TODAY=$(date '+%Y-%m-%d %H:%M')
  ENTRY="- Created AGENTS.md at project root."
  if grep -q "^## $TODAY" "$LOG_FILE"; then
    sed -i "/^## $TODAY$/a\\$ENTRY" "$LOG_FILE"
  else
    sed -i "3a\\\\n## $TODAY\\n\\n$ENTRY" "$LOG_FILE"
  fi
fi
