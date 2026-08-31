---
name: agentfs-git-push
description: >
  git push safety, pre-push scan, hey git workflow, hey git, git
metadata:
  version: "1.1.0"
  tags: [agentfs, git, safety, pre-push, guardrail]
---

# Git Push Safety

Stage, scan, report, wait for confirmation, then commit and push.
This skill absorbs the full Git Push Safety workflow previously
inline in AGENTS.md Guardrail #10 (v4.x).

## Workflow

Execute these steps in exact order. Do NOT skip or combine steps.

### Step 0 — Resolve Target

Determine which git repo to operate on:

1. If the user specifies a repo explicitly ("push this project",
   "push context-eng", "push ~/.agents"), use that.
2. If invoked with bare "hey git" or "git push" **without** an
   explicit target, the default is **`~/.agents/`** (USER scope
   AgentFS repo).
3. If the CWD is a different git repo with uncommitted changes,
   confirm with the user before assuming CWD.

All subsequent steps (`git add`, `pre-push-scan.sh`, `git commit`,
`git push`) run inside the resolved target directory.

### Step 1 — Stage

```bash
git add -A
```

### Step 2 — Scan

```bash
bash ~/.agents/skills/agentfs-setup/scripts/pre-push-scan.sh
```

This scans the staged diff for secrets, hardcoded paths, username
leakage, IP addresses, sensitive URLs, and PII.

### Step 3 — Allowlist Filtering

Read `.pre-push-allowlist` (at repo root, e.g. `~/.agents/.pre-push-allowlist`
for USER scope). Semantically match each finding against the allowlist
descriptions.

- Findings matching a known false positive → report as `✅ Known FP`
- Findings NOT matching → report as `⚠️ FOUND`
- Only `⚠️ FOUND` items count toward a blocking verdict

### Step 4 — README Audit (conditional)

If `pre-push-scan.sh` output contains `README_AUDIT_REQUIRED`
(emitted when `skills/`, `knowledge/`, or `AGENTS.md` are staged):

```
load_skill(name: "agentfs-readme-audit")
```

Follow that skill completely before continuing.

### Step 5 — PII Review (conditional)

If memory files (`.agents/memories/`) are among the flagged findings,
perform a semantic PII review of the staged memory content. Look for:
- Real names, email addresses, phone numbers
- Account identifiers, credentials
- Location data, health data

### Step 6 — Report

Present the complete scan report in a **single turn**, rendered as
Markdown (no code fence wrapping the tables — tables must display
natively). Include:

- Scan findings table (with `✅ Known FP` / `⚠️ FOUND` status)
- README audit results (if Step 4 was triggered)
- PII review results (if Step 5 was triggered)
- Blocking verdict: CLEAN or BLOCKED (with reasons)

### Step 7 — WAIT ⛔

**STOP.** Do NOT proceed to commit.

Wait for the user to reply to the report turn with explicit
confirmation (e.g., "go", "push", "approved", "yes").

### Step 8 — Commit

```bash
git commit -m "<descriptive message>"
```

Use a descriptive commit message summarizing the changes.

### Step 9 — Push

```bash
git push
```

## Violations

Any of the following is a protocol violation:

1. **Committing without scanning** — `git commit` before
   `pre-push-scan.sh` completes
2. **Committing without confirmation** — `git commit` before the
   user replies to the report turn
3. **Skipping README audit** — not loading `agentfs-readme-audit`
   when `README_AUDIT_REQUIRED` is emitted
4. **Skipping PII review** — not reviewing memory file content
   when memory files are flagged in the scan
5. **Merging report and commit** — presenting the report and
   running `git commit` in the same agent action (must be
   separate turns)

## Override

If the user requests to skip the scan or push without confirmation,
this conflicts with this safety workflow. The agent MUST:

1. State the conflict
2. Ask for explicit confirmation
3. If confirmed, log in the appropriate `log.md` with `[OVERRIDE]`
