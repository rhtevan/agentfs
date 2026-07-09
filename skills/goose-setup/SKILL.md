---
name: goose-setup
description: "Configure Goose global persistent instructions for cross-project, cross-session use"
version: 1.3
metadata:
    tags: [goose, config, instructions, persistent]
---

# Goose Global Setup

Configure Goose with persistent instructions that apply across all projects and sessions.

## What It Does

1. Creates a **persistent instructions file** at `~/.config/goose/instructions.md`
2. Registers it in `~/.config/goose/config.yaml` via `GOOSE_MOIM_MESSAGE_FILE`
3. Instructions are injected into Goose's working memory **every turn**, so they can never be forgotten

## Prerequisites

- Goose is installed and `~/.config/goose/config.yaml` exists
- Familiarity with Goose's [persistent instructions](https://goose-docs.ai/docs/guides/context-engineering/using-persistent-instructions) feature

## Note on Tool Discovery

Previous versions of this skill included "Tool Discovery" instructions to help Goose find devbox/Nix-installed tools at non-standard paths. **This is no longer needed** if you have configured the `goose-shell` wrapper (`~/.local/bin/goose-shell`) and set `GOOSE_SHELL` in the Goose Desktop `.desktop` file. The wrapper sources `~/.bashrc` before executing commands, which sets up nix, devbox, crc/oc, sdkman, and all other PATH entries automatically — even for non-interactive shells.

See the related files:
- `~/.local/bin/goose-shell` — wrapper that sources `~/.bashrc`
- `~/.local/share/applications/Goose.desktop` — passes `GOOSE_SHELL` to the Goose process
- `~/.config/environment.d/60-goose-shell.conf` — sets `GOOSE_SHELL` for systemd user session

## Steps

### Step 1: Create the instructions file

Create `~/.config/goose/instructions.md` with your global instructions:

```markdown
## Path Hygiene

- **Never use explicit home directory paths** like `/home/<username>/` in scripts, configurations, or output.
- Always use `~` or `$HOME` instead.
- When displaying paths to the user, prefer `~/...` over `/home/<username>/...`.

## Git Push Safety

- Before any push to GitHub, **DO NOT PUSH AUTOMATICALLY**.
- Conduct a thorough security and risk evaluation on the changes (scan for secrets, credentials, hardcoded paths, PII, and sensitive data).
- Show the full evaluation report to the user.
- Wait for explicit go-ahead before executing the push.
```

Add any other cross-project instructions you want Goose to always follow.

### Step 2: Register in config.yaml

Add the following line to `~/.config/goose/config.yaml` (at root level, alongside other `GOOSE_*` settings):

```yaml
GOOSE_MOIM_MESSAGE_FILE: ~/.config/goose/instructions.md
```

**How it works:** Goose uses MOIM (Model-Observed Internal Memory) to inject this file's contents into the model's context every turn. Changes to the file take effect immediately — no session restart needed.

### Step 3: Verify

Start a new Goose session and test that your persistent instructions are active.

## Customization

The instructions file supports any Markdown content. Common additions:

```markdown
## Code Style
- Use `python3` not `python`
- Prefer `pnpm` over `npm`

## Security
- Never upload code to external services
- Always confirm before making network requests

## Git
- Always use `cd <repo-dir> &&` before git commands when CWD differs from the target repo
```

### Persistent Instructions vs goosehints

| Feature | Persistent Instructions | goosehints |
|---------|------------------------|------------|
| When loaded | Every turn | Session start |
| Can be forgotten | No | Yes, as context fills |
| Best for | Critical guardrails | Project context |
| Token cost | Per turn | Once at start |
| Update requires | No restart | Session restart |

## Key Files

| File | Purpose |
|------|--------|
| `~/.config/goose/instructions.md` | Persistent instructions content |
| `~/.config/goose/config.yaml` | Goose config — `GOOSE_MOIM_MESSAGE_FILE` entry |

## References

- [Goose Persistent Instructions](https://goose-docs.ai/docs/guides/context-engineering/using-persistent-instructions)
- [Goose Configuration Files](https://goose-docs.ai/docs/guides/config-files)

## Changelog

| Date | Change |
|------|--------|
| 2026-07-08 22:34 | v1.3 — Added Path Hygiene guardrail: never use explicit home directory paths, prefer ~ or $HOME |
| 2026-07-08 22:16 | v1.2 — Removed Tool Discovery instructions (obsoleted by goose-shell wrapper fix); updated description and examples |
| 2026-07-08 17:49 | v1.1 — Added Git Push Safety guardrail: security evaluation required before any push |
| 2026-07-08 17:40 | v1.0 — Initial skill: persistent instructions with devbox tool discovery |
