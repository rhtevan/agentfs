---
name: goose-setup
description: "Configure Goose global persistent instructions and tool discovery settings for cross-project, cross-session use"
version: 1.0
metadata:
    tags: [goose, config, instructions, persistent, devbox]
---

# Goose Global Setup

Configure Goose with persistent instructions that apply across all projects and sessions, including tool discovery for non-standard install paths (e.g., devbox/Nix).

## What It Does

1. Creates a **persistent instructions file** at `~/.config/goose/instructions.md`
2. Registers it in `~/.config/goose/config.yaml` via `GOOSE_MOIM_MESSAGE_FILE`
3. Instructions are injected into Goose's working memory **every turn**, so they can never be forgotten

## Prerequisites

- Goose is installed and `~/.config/goose/config.yaml` exists
- Familiarity with Goose's [persistent instructions](https://goose-docs.ai/docs/guides/context-engineering/using-persistent-instructions) feature

## Steps

### Step 1: Create the instructions file

Create `~/.config/goose/instructions.md` with your global instructions:

```markdown
## Tool Discovery

- Use `$(which gh)` to find the `gh` CLI. It may be installed via devbox at a non-standard path.
- When a tool is not found on `$PATH`, check `~/.local/share/devbox/global/default/.devbox/nix/profile/default/bin/` before giving up.

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

Start a new Goose session and test:

```
You: where is gh?
```

Goose should use `$(which gh)` or check the devbox path rather than assuming `gh` is not installed.

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
|------|---------|
| `~/.config/goose/instructions.md` | Persistent instructions content |
| `~/.config/goose/config.yaml` | Goose config — `GOOSE_MOIM_MESSAGE_FILE` entry |

## References

- [Goose Persistent Instructions](https://goose-docs.ai/docs/guides/context-engineering/using-persistent-instructions)
- [Goose Configuration Files](https://goose-docs.ai/docs/guides/config-files)

## Changelog

| Date | Change |
|------|--------|
| 2026-07-08 17:49 | v1.1 — Added Git Push Safety guardrail: security evaluation required before any push |
| 2026-07-08 17:40 | v1.0 — Initial skill: persistent instructions with devbox tool discovery |
