---
name: skill-harvest
description: >
  Harvest procedural knowledge from MEMORY.md files across one or more
  projects and distill them into reusable USER-scoped skills under
  ~/.agents/skills/. Scans default agent and named profile memories,
  identifies procedural graduation candidates (repeatable workflows,
  multi-step SOPs, routine workarounds), scaffolds new skills, and
  removes graduated entries from source MEMORY.md files. Complements
  okf-bundle-harvest which handles declarative/semantic knowledge.
argument-hint: "Optionally specify project paths: 'harvest skills from ~/projects/foo and ~/projects/bar'"
compatibility: "Requires AgentFS setup (agentfs-setup skill) with MEMORY.md files"
metadata:
  author: agentfs
  version: "1.0"
  tags: [agentfs, skills, memory, procedural, graduation, harvest]
user-invocable: true
disable-model-invocation: false
---

# Skill Harvest — Memory-to-Skill Distillation

Harvest procedural knowledge from project-scoped `MEMORY.md` files and
distill them into reusable skills under `~/.agents/skills/`.

This skill completes the **graduation path** defined in AgentFS
Guardrail #8, targeting **procedural memory** — the counterpart to
`okf-bundle-harvest` which handles declarative/semantic knowledge.

> When episodic memories accumulate into repeatable action sequences,
> graduate them into skills — idempotent, executable workflows that
> any agent can load and follow.

## How It Relates to Other Harvest Skills

| Aspect | `okf-bundle-harvest` | `skill-harvest` |
|--------|---------------------|------------------|
| **Target memory type** | Semantic (concepts, patterns) | Procedural (workflows, SOPs) |
| **Output format** | OKF concept documents (.md) | SKILL.md + scripts/ |
| **Output location** | `~/.agents/knowledge/` | `~/.agents/skills/` |
| **Graduation signal** | "This is a generalizable truth" | "This is a repeatable action sequence" |
| **Scope** | USER only (knowledge) | USER by default (skills) |
| **Idempotency** | N/A (documents) | Preferred (scripts) |

## Prerequisites

- At least one project with AgentFS set up (`.agents/` directory)
- MEMORY.md files with accumulated entries
- Write access to `~/.agents/skills/`
- The `okf-bundle-gen` skill must be available (scanner script reused)

## Fixed Configuration

| Setting | Value |
|---------|-------|
| Default output root | `~/.agents/skills/` |
| Skill format | SKILL.md + scripts/ + references/ |
| Entry delimiter | `§` (or timestamp-headed sections) |

---

## Usage

### Harvest from current project

> harvest skills from project memories

Scans `./.agents/memories/` and `./.agents/profiles/*/memories/` in
the current working directory.

### Harvest from specific projects

> harvest skills from ~/projects/foo and ~/projects/bar

Scans the `.agents/` directory in each specified project root.

### Harvest from all known projects

> harvest skills from all my projects

The agent should ask the user to provide project paths, or scan
common locations if the user confirms.

---

## Procedure

Execute these phases **in order**.

### Phase 1 — Determine scope and scan memories

#### 1a. Identify project roots to scan

Based on user input, determine which project roots to scan:

- **Current project** (default): use `$(pwd)`
- **Explicit list**: user provides paths like `~/projects/foo`
- **Multiple projects**: iterate over each provided path

For each project root, verify `.agents/` exists:

```bash
for project in "${PROJECT_ROOTS[@]}"; do
  if [[ ! -d "$project/.agents" ]]; then
    echo "SKIP: $project — no .agents/ directory"
    continue
  fi
done
```

#### 1b. Scan all MEMORY.md files

For each valid project root, run the memory scanner:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/scan-memories.sh "$project/.agents"
```

Collect the output, tagging each entry with its **source project path**
and **source file** for traceability.

#### 1c. Aggregate and deduplicate

Combine entries from all scanned projects into a single inventory.
Note procedural clusters — groups of entries that describe steps in
a related workflow.

### Phase 2 — Identify procedural graduation candidates

Analyze the aggregated entries to find **procedural knowledge** worth
graduating into skills. Not every memory entry is procedural — filter
for action-oriented content.

#### Procedural graduation criteria

An entry (or group of related entries) qualifies for skill graduation
when it meets **at least one** of these conditions:

| Criterion | Signal | Example |
|-----------|--------|----------|
| **Multi-step workflow** | Entry describes ≥2 sequential steps | "After CRC starts, run oc login, then silence alerts, then enable monitoring" |
| **Cross-project recurrence** | Same procedure appears in ≥2 projects | "Always run `go mod tidy` before commit" found in project-A and project-B |
| **Workaround-turned-routine** | A fix or workaround that became standard practice | "Fix console banner by deleting consolenotification CR" |
| **Command composition** | Multiple commands that are always run together | "Run lint, then test, then build in that order" |
| **Setup/teardown pattern** | Repeatable environment setup or cleanup | "Start CRC, login, configure monitoring, silence alerts" |
| **Abstraction potential** | Multiple concrete entries can be combined into a parameterized workflow | "Deploy operator X" + "Deploy operator Y" → generic operator deploy skill |

#### Non-graduation criteria (keep as memory)

Do NOT graduate entries that are:

- **Single atomic commands**: "Run `make test`" — too simple for a skill
- **Declarative/conceptual**: "eBPF needs CAP_BPF on kernel ≥5.8" — this
  is semantic knowledge, route to `okf-bundle-harvest` instead
- **System/environment-specific**: "Use `crcstart` on this machine" —
  tied to a specific host unless it can be abstracted into a
  parameterized script
- **Ephemeral**: "CI workaround for this sprint" — temporary
- **Already a skill**: Check existing skills under `~/.agents/skills/`
  to avoid duplication
- **Project-specific workflow**: "Deploy the inventory service to staging"
  — unless the workflow generalizes ("Deploy any service to staging")

#### Distinguishing procedural from declarative

| Entry content | Type | Route to |
|---------------|------|----------|
| "Always run X before Y" | Procedural | `skill-harvest` |
| "X depends on Y being initialized first" | Declarative | `okf-bundle-harvest` |
| "To fix X, run Y then Z" | Procedural | `skill-harvest` |
| "X breaks when Y > version N" | Declarative | `okf-bundle-harvest` |
| "Use wrapper `crcstart` instead of `crc start`" | Atomic + system-specific | Keep as memory |
| "After CRC start: login → silence alerts → enable monitoring" | Multi-step workflow | `skill-harvest` |

#### Output of Phase 2

A list of skill candidates, each with:

1. **Source entries** — which MEMORY.md entries contribute to this skill
   (project path + file + entry content)
2. **Skill name** — proposed kebab-case directory name (≤25 chars)
3. **Title** — human-readable name
4. **Description** — one-line summary
5. **Tags** — categorization strings
6. **Idempotent** — whether the skill can be safely re-run (yes/no/partial)
7. **Scripts needed** — list of scripts to generate

### Phase 3 — Inspect existing skills

Check what already exists in `~/.agents/skills/` to avoid duplication:

```bash
ls -d ~/.agents/skills/*/SKILL.md 2>/dev/null | while read f; do
  dir=$(basename $(dirname "$f"))
  desc=$(sed -n 's/^description:[[:space:]]*//p' "$f" | head -1)
  echo "  $dir — $desc"
done
```

Also scan `./.agents/skills/` in each project for project-scoped skills.

### Phase 4 — Plan the write (skill design)

For each graduation candidate from Phase 2:

#### 4a. Match against existing skills

Compare each candidate against the existing skill inventory (Phase 3).
Use **semantic matching** — a candidate might overlap with an existing
skill that uses different naming.

#### 4b. Decide action

| Situation | Action |
|-----------|--------|
| New workflow, no overlap | **Create** new skill under `~/.agents/skills/` |
| Overlaps existing skill — extends it | **Update** existing skill (add steps, scripts) |
| Overlaps existing skill — already covered | **Skip** |
| Project-specific but abstractable | **Create** with parameterization |

#### 4c. Design each new skill

For each skill to create, plan:

- **SKILL.md structure**: Overview, usage, steps, verification, changelog
- **Scripts**: What shell/python scripts to generate
- **Idempotency**: How to make the skill safe to re-run
- **Parameters**: What inputs the skill accepts
- **Verification**: How to confirm the skill completed successfully

#### 4d. Plan source cleanup

For each graduated entry, record which MEMORY.md file and which
entry content should be removed in Phase 7.

**Output:** A structured write plan, e.g.:

```
CREATE  crc-post-start/SKILL.md      — Multi-step CRC post-start workflow
CREATE  crc-post-start/scripts/post-start.sh
UPDATE  crc-status/SKILL.md           — Add alert silencing step
SKIP    (single make test command)    — Too atomic for a skill
ROUTE   (ebpf cap note)              — Declarative → okf-bundle-harvest
PRUNE   project-A/.agents/memories/MEMORY.md  — remove 3 entries
```

### Phase 5 — Scaffold and write skills

For each new skill in the write plan:

#### 5a. Create directory structure

```bash
SKILL_DIR="$HOME/.agents/skills/<skill-name>"
mkdir -p "$SKILL_DIR/scripts"
```

#### 5b. Write SKILL.md

Generate an Agent Skills format SKILL.md:

```markdown
---
name: <skill-name>
description: >
  <One-paragraph description distilled from the source memory entries>
argument-hint: "<usage hint>"
compatibility: "<requirements>"
metadata:
  author: agentfs
  version: "1.0"
  tags: [<tags>]
user-invocable: true
disable-model-invocation: false
---

# <Title>

<Overview paragraph — what this skill does and why>

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| ~/projects/foo | default-agent/MEMORY | "After CRC starts, run oc login..." |
| ~/projects/bar | verifier/MEMORY | "Always login after crc start" |

## Prerequisites

- <List of requirements>

## Steps

1. **Step name**
   Description and commands.

2. **Step name**
   Description and commands.

## Verification

- [ ] <How to confirm success>

## Changelog

| Updated | Change |
|---------|--------|
| YYYY-MM-DD HH:MM | v1.0 — Initial skill harvested from project memories |
```

#### 5c. Write scripts

Generate executable scripts under `scripts/`:

- **Idempotent**: Check preconditions before acting
- **Exit codes**: 0 = success, 1 = failure, 2 = usage error
- **Portable**: Use `$HOME` not hardcoded paths
- **Documented**: Header comment with usage

```bash
#!/usr/bin/env bash
# <script-name>.sh — <one-line description>
#
# Usage: bash <script-name>.sh [args]
#
# Harvested from project memory entries. See SKILL.md for details.

set -euo pipefail

# ... implementation ...
```

#### 5d. Write supporting references (if needed)

If the skill references external docs, create `references/` directory:

```bash
mkdir -p "$SKILL_DIR/references"
```

### Phase 6 — Update existing skills (if applicable)

For candidates that extend an existing skill:

1. Read the existing SKILL.md completely
2. Add new steps or scripts
3. Update the description if scope expanded
4. Add a changelog entry with current timestamp
5. Preserve existing content that's still accurate

### Phase 7 — Prune graduated entries from MEMORY.md

For each graduated entry, remove it from its source MEMORY.md file:

```bash
bash ~/.agents/skills/okf-bundle-harvest/scripts/prune-memory.sh \
  <MEMORY_FILE> \
  "<entry-content-to-remove>"
```

**Safety rules:**

- Only remove entries that were actually written as skills
- Never remove ALL entries — leave the file header if it would be empty
- Create a backup before modifying: `cp MEMORY.md MEMORY.md.bak.<timestamp>`
- If a project root is read-only, skip pruning and warn
- Entries routed to `okf-bundle-harvest` are NOT pruned by this skill

### Phase 8 — Update indexes and logs

#### 8a. Regenerate skills index

Invoke the `skill-index` skill to regenerate `~/.agents/skills/index.md`:

```
load_skill(name: "skill-index")
```

This ensures the new skills appear in the index with correct timestamps.

#### 8b. Update USER-scope log

Update `~/.agents/log.md`:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  ~/.agents/log.md \
  "* **Skill Harvest**: Created N new skill(s) from MEMORY.md entries across M project(s): <skill-names>"
```

#### 8c. Update PROJECT-scope logs

For each project whose MEMORY.md was pruned, update
`./.agents/log.md`:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  "$project/.agents/log.md" \
  "* **Skill Harvest**: Graduated N entries to USER skills: <skill-names>"
```

### Phase 9 — Verify

For each new skill created:

1. Confirm `SKILL.md` exists and has YAML frontmatter
2. Confirm scripts are executable (`chmod +x`)
3. Confirm the skill appears in `~/.agents/skills/index.md`
4. Optionally do a dry-run of the scripts if safe

---

## Quality Checklist

Before completing, verify:

- [ ] Only entries meeting procedural graduation criteria were harvested
- [ ] Every new skill has a **"Harvested From" table** with source traceability
- [ ] Declarative entries were NOT harvested (routed to `okf-bundle-harvest`)
- [ ] System-specific entries were either abstracted or left as memory
- [ ] Graduated entries were **removed** from source MEMORY.md files
- [ ] MEMORY.md backups were created before pruning
- [ ] Every SKILL.md has YAML frontmatter with `name` and `description`
- [ ] Scripts are idempotent (or document why not)
- [ ] Scripts use `$HOME` not hardcoded paths
- [ ] `~/.agents/skills/index.md` regenerated via `skill-index`
- [ ] `~/.agents/log.md` updated to reflect the harvest
- [ ] Project-scope `log.md` updated for pruned MEMORY.md files

---

## Example Scenario

Given two projects with these MEMORY.md entries:

**Project A** (`.agents/memories/MEMORY.md`):
```
§ After CRC starts, always run: oc login -u kubeadmin -p <pass> https://api.crc.testing:6443
§ Silence noisy dev-irrelevant alerts with oc apply -f silence-alerts.yaml
§ The inventory service uses Redis 7.2.1 specifically
§ eBPF programs need CAP_BPF on kernel ≥5.8
§ Use crcstart/crcstop instead of crc start/stop on this machine
```

**Project B** (`.agents/memories/MEMORY.md`):
```
§ After CRC start: oc login, then enable monitoring, then silence alerts
§ Always run go mod tidy before committing
§ Pin Go version in go.mod AND Makefile
```

**Harvest result:**

| Entry | Action | Reason |
|-------|--------|--------|
| CRC post-start login (A+B) | **Graduate** → `crc-post-start` skill | Cross-project recurrence, multi-step workflow |
| Silence alerts (A+B) | **Merge** into `crc-post-start` skill | Part of the same workflow |
| Redis 7.2.1 (A) | **Keep** in MEMORY.md | Project-specific, declarative |
| eBPF CAP_BPF (A) | **Route** → `okf-bundle-harvest` | Declarative knowledge, not procedural |
| crcstart/crcstop (A) | **Keep** in MEMORY.md | System-specific, single atomic command |
| go mod tidy (B) | **Keep** in MEMORY.md | Single atomic command |
| Pin Go version (B) | **Route** → `okf-bundle-harvest` | Declarative convention |

After harvest:
- New skill: `~/.agents/skills/crc-post-start/` with SKILL.md + scripts/
- Project A MEMORY.md: Redis + crcstart entries remain
- Project B MEMORY.md: go mod tidy entry remains
- Entries routed to `okf-bundle-harvest` flagged for separate processing

---

## Pitfalls

1. **Over-skilling** — Not every repeated command deserves a skill. If
   it's a single command with no setup/teardown/verification, it's too
   atomic. Skills should encapsulate meaningful workflows.

2. **Under-abstracting** — When harvesting from multiple projects, look
   for the common workflow, not the project-specific variant. "Deploy
   inventory service" stays as memory; "Deploy a service with health
   checks" becomes a skill.

3. **Mixing declarative and procedural** — A memory entry like "always
   pin Go versions" is a convention (declarative → `okf-bundle-harvest`).
   "Run `go mod tidy && go mod verify` before commit" is a procedure
   (→ `skill-harvest`). Route accordingly.

4. **Non-idempotent scripts** — Prefer idempotent scripts that check
   preconditions. If a script can't be idempotent, document it clearly
   in the SKILL.md.

5. **Hardcoded paths** — Scripts must use `$HOME`, `~`, or parameters.
   Never hardcode `/home/<username>/` or machine-specific paths.

6. **System-specific procedures** — If a workflow only works on one
   machine (e.g., uses a custom binary), either abstract it with
   parameters or leave it as memory. Skills should be portable.

## Supporting Files

Skill directory: `~/.agents/skills/skill-harvest`

- `scripts/scan-procedural.sh` — Scan MEMORY.md files and flag
  procedural vs declarative entries

Dependencies (from `okf-bundle-gen`):
- `scripts/scan-memories.sh` — Scan and display MEMORY.md entries
- `scripts/merge-log-entry.sh` — Append entries to log.md

Dependencies (from `okf-bundle-harvest`):
- `scripts/prune-memory.sh` — Remove graduated entries from MEMORY.md
- `scripts/harvest-summary.sh` — Generate summary of harvest candidates

Dependencies (from `skill-index`):
- Regenerate `skills/index.md` after new skills are created

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-09 19:52 | v1.0 — Initial skill: procedural memory scanning, graduation criteria, skill scaffolding, MEMORY.md pruning |
