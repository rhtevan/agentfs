---
name: fedora-window-list
description: >
  toggle window list, taskbar toggle, gnome taskbar
argument-hint: "{enable|disable|status}"
compatibility: "Fedora with GNOME desktop"
metadata:
  author: agentfs
  version: "1.2.0"
  model-tier: T1
  tags: [fedora, gnome, desktop, taskbar]
user-invocable: true
disable-model-invocation: false
---

# Fedora GNOME Window List Toggle

Enable, disable, or check the status of the GNOME Window List
taskbar extension.

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

This skill is purely mechanical — no semantic judgment is required.
All decisions are made by the toggle script.

## Workflow

### Step 1 — Run the toggle script

The agent MUST run:

```bash
bash ~/.agents/skills/fedora-window-list/scripts/toggle-window-list.sh {enable|disable|status}
```

The agent MUST pass one argument:
- `enable` — show the window list taskbar
- `disable` — hide the window list taskbar
- `status` — report current state

If the user did not specify an action, the agent MUST use `status`.

The agent MUST report the script output verbatim.
The agent MUST NOT interpret, summarize, or paraphrase the output.

## Output Contract

- Exit 0 → action completed successfully
- Exit 1 → error (script output explains the cause)

## Verification

- [ ] Script exits 0 with a confirmation message
- [ ] The taskbar change is visible immediately (no restart needed)

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
