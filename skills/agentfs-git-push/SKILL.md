---
name: agentfs-git-push
description: >
  git push safety, pre-push scan, hey git workflow, hey git, git
metadata:
  version: "2.0.0"
  tags: [agentfs, git, safety, pre-push, guardrail]
user-invocable: true
disable-model-invocation: false
---

# Git Push Safety

Prevent accidental commit of secrets, PII, hardcoded paths, and
stale README content to git repositories. The workflow enforces a
two-phase safety model: deterministic scan (script) followed by a
mandatory human confirmation gate. This skill absorbs the full Git
Push Safety workflow previously inline in AGENTS.md Guardrail #10
(v4.x), ensuring the agent cannot skip, reorder, or combine steps.

## Prerequisites

- Git repository with at least one prior commit
- `~/.agents/skills/agentfs-setup/scripts/pre-push-scan.sh` exists
- Push credentials configured (SSH key or HTTPS token)

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Resolve target repo from explicit arg, bare invocation default, or CWD detection | `scripts/resolve-target.sh` outputs correct `TARGET=` |
| S2 | Stage all changes | `git diff --cached --stat` shows staged files |
| S3 | Scan staged diff for secrets, paths, PII | `pre-push-scan.sh` exits 0 (clean) or produces findings report |
| S4 | Filter scan findings against `.pre-push-allowlist` | Known FPs marked `✅`, real findings marked `⚠️` |
| S5 | Trigger README audit when agentfs files staged | `README_AUDIT_REQUIRED` in scan output → `agentfs-readme-audit` loaded |
| S6 | Trigger PII review when memory files staged | Memory files in findings → semantic PII review performed |
| S7 | Present report in single turn with blocking verdict | Report contains findings table + verdict (CLEAN/BLOCKED) |
| S8 | Mandatory wait gate — no commit without user confirmation | Agent does not call `git commit` until user replies |
| S9 | Commit and push | `git log -1` shows new commit; `git status` shows clean tree |

## Workflow

Execute these steps in exact order. Do NOT skip or combine steps.

### Step 0 — Resolve Target

Run the resolve-target script:

```bash
bash ~/.agents/skills/agentfs-git-push/scripts/resolve-target.sh [EXPLICIT_TARGET]
```

Read the output and apply:

| Output | Agent Action |
|--------|-------------|
| `TARGET=/path` | Use this as the working directory for all subsequent steps |
| `CWD_ALSO=true` + `CWD_PATH=/path` | After completing the workflow for `TARGET`, inform the user: "`CWD_PATH` also has uncommitted changes — want me to push it next?" |
| `CWD_ALSO=false` | No follow-up needed |
| Exit 1 | Report the error to the user. Do not proceed. |

All subsequent steps (`git add`, `pre-push-scan.sh`, `git commit`,
`git push`) run inside the resolved `TARGET` directory.

### Step 1 — Stage

```bash
cd "$TARGET" && git add -A
```

### Step 2 — Scan

```bash
cd "$TARGET" && bash ~/.agents/skills/agentfs-setup/scripts/pre-push-scan.sh
```

| Exit Code | Meaning | Agent Action |
|:---------:|---------|-------------|
| 0 | All checks clean | Continue to Step 3 |
| 1 | Findings detected | Continue to Step 3 — findings are in stdout |

The scan output is structured Markdown. Parse it for findings and
the `README_AUDIT_REQUIRED` flag.

### Step 3 — Allowlist Filtering

Read `.pre-push-allowlist` at the repo root (e.g.,
`~/.agents/.pre-push-allowlist` for USER scope). Semantically match
each finding against the allowlist descriptions.

- Findings matching a known false positive → report as `✅ Known FP`
- Findings NOT matching → report as `⚠️ FOUND`
- Only `⚠️ FOUND` items count toward a blocking verdict

If no `.pre-push-allowlist` exists, skip filtering — all findings
are `⚠️ FOUND`.

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
cd "$TARGET" && git commit -m "<message>"
```

Commit message format: imperative mood, ≤72 chars first line,
summarize the staged changes. Use `git diff --cached --stat` to
inform the summary. For multi-topic commits, add blank line then
bullet list of changes.

### Step 9 — Push

```bash
cd "$TARGET" && git push
```

After push completes, if Step 0 reported `CWD_ALSO=true`, inform
the user about the other repo's uncommitted changes and offer to
run the workflow again for it.

## Error Handling

| Step | Script/Command | Idempotent | On Failure |
|:----:|----------------|:----------:|------------|
| 0 | `resolve-target.sh` | ✅ (read-only) | Exit 1: report error, do not proceed |
| 1 | `git add -A` | ✅ | Safe to retry |
| 2 | `pre-push-scan.sh` | ✅ (read-only) | Exit 1 is expected (findings). Script errors → present output, do not proceed |
| 3 | Allowlist filtering | ✅ (LLM task) | Re-read allowlist and retry |
| 8 | `git commit` | ❌ | If "nothing to commit" → inform user, skip. If other error → present output, do not retry without user input |
| 9 | `git push` | ❌ | See Troubleshooting table |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `git push` rejected: "non-fast-forward" | Remote has commits not in local | `git pull --rebase` then retry push. Present the pull output to user first. |
| `git push` rejected: "permission denied" | Auth failure (SSH key or token) | Present error. User must fix credentials. Do NOT retry. |
| `git push` rejected: "protected branch" | Branch protection rules | Inform user. They may need to push to a different branch or create a PR. |
| `git commit` "nothing to commit" | All changes already committed or unstaged | Inform user — working tree is clean. Skip Steps 8–9. |
| `pre-push-scan.sh` not found | `agentfs-setup` skill not installed | Present error: "pre-push-scan.sh requires the agentfs-setup skill at ~/.agents/skills/agentfs-setup/" |

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

## Tests

| Test | Spec | How to Verify | Expected Result |
|:----:|:----:|---------------|-----------------|
| T1 | S1 | `cd /tmp/some-project && bash resolve-target.sh` | `TARGET=~/.agents`, `CWD_ALSO=true` if CWD has changes |
| T2 | S1 | `bash resolve-target.sh /path/to/repo` | `TARGET=/path/to/repo`, `CWD_ALSO=false` |
| T3 | S1 | `bash resolve-target.sh /tmp` (non-git) | Exit 1 with error message |
| T4 | S3 | Stage a file containing `AKIA` prefix → run `pre-push-scan.sh` | Findings report with secrets category flagged |
| T5 | S5 | Stage a `skills/` change → run `pre-push-scan.sh` | Output contains `README_AUDIT_REQUIRED` |
| T6 | S8 | Observe agent behavior after report | Agent waits — no `git commit` in the same turn |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
