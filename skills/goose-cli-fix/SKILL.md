---
name: goose-cli-fix
description: >
  fix goose cli, goose projects.json, goose parse error
argument-hint: "(no arguments)"
compatibility: "Any OS with Goose CLI installed"
metadata:
  author: agentfs
  version: "1.2.0"
  model-tier: T1
  tags: [goose, cli, fix, json]
user-invocable: true
disable-model-invocation: false
---

# Fix Goose CLI projects.json Parse Error

Fix the warning `Failed to update project tracker with instruction: Failed to parse projects.json file` that can occur after updating Goose CLI, caused by malformed JSON in the project tracker file.

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

This skill is purely mechanical — no semantic judgment is required.
All decisions are made by the repair script.

## Workflow

### Step 1 — Run the repair script

The agent MUST run the repair script:

```bash
bash ~/.agents/skills/goose-cli-fix/scripts/fix-projects-json.sh
```

The script handles diagnosis and repair automatically.
The agent MUST report the script output verbatim.
The agent MUST NOT interpret, summarize, or paraphrase the output.

### Step 2 — Verify

The repair script performs its own validation. The agent MUST check the
script exit code: 0 means success, 1 means repair failed.

If the script exits 0, the fix is complete. If it exits 1, the agent
MUST report the script output and stop — do not attempt manual repair.

## Output Contract

- Exit 0 from the repair script → repair succeeded
- Exit 1 from the repair script → manual inspection required

## Verification

- [ ] Repair script exits 0 with a success message
- [ ] The Goose CLI warning no longer appears on next session start


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
