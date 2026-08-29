---
name: goose-nextai-drawio
description: >
  setup nextai drawio, teardown nextai drawio, upgrade nextai drawio,
  update nextai drawio, nextai drawio status
argument-hint: "setup | teardown | upgrade | status"
compatibility: "Node.js >= 18, npx, Goose with developer extension"
metadata:
  author: agentfs
  version: "1.1.2"
  tags: [goose, mcp, drawio, diagram, extension]
  related_skills: [archify]
user-invocable: true
disable-model-invocation: false
writes-files: true
---

# Next AI Draw.io — Goose MCP Extension

Manage the [next-ai-draw-io](https://github.com/DayuanJiang/next-ai-draw-io)
MCP server as a Goose custom extension. This skill installs the
`@next-ai-drawio/mcp-server` npm package locally (avoiding repeated
`npx` downloads), registers it as a `stdio` extension in Goose's
`config.yaml`, and provides teardown and upgrade operations. Use when
the user wants AI-powered draw.io diagram generation with real-time
browser preview from inside a Goose session.

**Trade-off awareness:** This extension adds ~1,600 tokens of tool
definitions to every Goose turn (10 tools). For agent-native diagram
generation without the per-turn context tax, consider the `archify`
skill instead — it produces self-contained HTML diagrams from a
typed JSON spec with zero idle token cost.

## Prerequisites

- Node.js >= 18 (`node --version`)
- npm / npx available
- Goose installed with `developer` extension enabled
- `~/.config/goose/config.yaml` exists (standard Goose config location)

## Operations

### Setup

Install the MCP server package locally and register it in Goose config.

```bash
bash ~/.agents/skills/goose-nextai-drawio/scripts/manage.sh setup
```

What it does:
1. Checks Node.js version (>= 18 required)
2. Installs `@next-ai-drawio/mcp-server` globally via `npm install -g`
3. Locates the installed binary (`next-ai-drawio-mcp`)
4. Backs up `~/.config/goose/config.yaml`
5. Adds a `nextaidrawio` extension entry (type: stdio) to the config
6. Reports the registration — user must restart Goose to activate

After setup, the user can:
- Enable the extension via Goose settings or `manage_extensions`
- Use natural language to create draw.io diagrams (the MCP server
  opens a browser tab with a live draw.io editor)

### Teardown

Remove the extension from Goose config and uninstall the package.

```bash
bash ~/.agents/skills/goose-nextai-drawio/scripts/manage.sh teardown
```

What it does:
1. Removes the `nextaidrawio` entry from Goose config
2. Uninstalls `@next-ai-drawio/mcp-server` globally
3. Reports completion — user must restart Goose to take effect

### Upgrade

Update the package to the latest version.

```bash
bash ~/.agents/skills/goose-nextai-drawio/scripts/manage.sh upgrade
```

What it does:
1. Runs `npm update -g @next-ai-drawio/mcp-server`
2. Reports the new version
3. If the extension is registered, no config change needed — the
   binary path stays the same

### Status

Check current installation and registration state.

```bash
bash ~/.agents/skills/goose-nextai-drawio/scripts/manage.sh status
```

Reports:
- Whether the npm package is installed and which version
- Whether the extension is registered in Goose config
- Whether it is enabled or disabled

## Goose Config Schema

> ⚠️ **Use this exact schema.** Do NOT write from memory or
> improvise field names. Copy this template and substitute only
> the marked placeholders.

The extension entry added to `~/.config/goose/config.yaml` under
the `extensions:` key:

```yaml
  nextaidrawio:
    enabled: false
    type: stdio
    name: Next AI Drawio
    description: AI-powered draw.io diagram generation with real-time browser preview via MCP
    cmd: <BINARY_PATH>
    args: []
    envs: {}
    env_keys: []
    timeout: 300
```

- `<BINARY_PATH>` is resolved at install time via `npm bin -g` +
  `next-ai-drawio-mcp` (the `bin` name from the package's
  `package.json`).
- `enabled: false` by default — the user explicitly enables it
  when they want the 1,600-token context tax.
- The extension starts **disabled** so it does not consume context
  tokens until the user opts in.

## Gotchas

- **npx vs local install:** The upstream README recommends
  `npx @next-ai-drawio/mcp-server@latest` which downloads the
  package on every invocation. This skill installs globally to
  avoid repeated downloads and ensure a stable binary path.
- **Port 6002:** The MCP server starts an embedded HTTP server on
  port 6002 by default. If that port is in use, set the `PORT`
  environment variable in the extension's `envs` config.
- **Browser required:** The MCP server opens a browser tab for the
  draw.io preview. Headless/SSH sessions won't work without a
  display.
- **Restart required:** Goose must be restarted after config changes
  for the extension to appear. `manage_extensions` enable/disable
  works within a session only for already-registered extensions.
- **Context cost:** When enabled, this extension injects ~1,600
  tokens into every turn (10 tool definitions). Disable it when
  not actively creating diagrams.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Setup installs npm package to user-local prefix | `manage.sh status` reports INSTALLED with version |
| S2 | Setup registers `nextaidrawio` stdio extension in Goose config | `grep nextaidrawio ~/.config/goose/config.yaml` returns entry |
| S3 | Setup creates config backup before modifying | Timestamped `.bak` file exists in `~/.config/goose/` |
| S4 | Setup defaults extension to `enabled: false` | Config entry shows `enabled: false` |
| S5 | Setup is idempotent — re-running updates path without duplicating entry | Run setup twice; `grep -c nextaidrawio config.yaml` returns 1 |
| S6 | Teardown removes extension from Goose config | `grep nextaidrawio config.yaml` returns nothing after teardown |
| S7 | Teardown removes the installed package directory | `~/.local/share/goose-nextai-drawio/` does not exist after teardown |
| S8 | Upgrade updates package to latest version | `manage.sh status` reports new version after upgrade |
| S9 | Status reports package version, binary path, and registration state | Output contains all three fields |
| S10 | Script rejects missing argument with exit code 2 | `manage.sh` with no args exits 2 |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `bash manage.sh setup && bash manage.sh status` | `Package: INSTALLED (@next-ai-drawio/mcp-server@<version>)` |
| T2 | S2 | `grep -A2 'nextaidrawio:' ~/.config/goose/config.yaml` | Shows `type: stdio` and `name: Next AI Drawio` |
| T3 | S3 | `ls -t ~/.config/goose/config.yaml.bak.* \| head -1` | Backup file with timestamp within last minute |
| T4 | S4 | `grep -A1 'nextaidrawio:' ~/.config/goose/config.yaml` | `enabled: false` |
| T5 | S5 | `bash manage.sh setup && bash manage.sh setup && grep -c 'nextaidrawio:' ~/.config/goose/config.yaml` | `1` |
| T6 | S6, S7 | `bash manage.sh setup && bash manage.sh teardown && bash manage.sh status` | `Package: NOT INSTALLED` and `Registered: NO` |
| T7 | S8 | `bash manage.sh upgrade` | `Upgraded: <old> → <new>` or `Already at latest version` |
| T8 | S9 | `bash manage.sh status` | Output contains `Package:`, `Binary:`, `Registered:` |
| T9 | S10 | `bash manage.sh; echo $?` | Exit code `2` |

## Verification

Run the test sequence to confirm the skill is working:

```bash
# Full lifecycle test (setup → status → upgrade → teardown → status)
SKILL=~/.agents/skills/goose-nextai-drawio/scripts/manage.sh
bash "$SKILL" setup    # T1, T2, T3, T4
bash "$SKILL" status   # T8
bash "$SKILL" setup    # T5 (idempotency)
bash "$SKILL" upgrade  # T7
bash "$SKILL" teardown # T6
bash "$SKILL" status   # T6 confirms removal
bash "$SKILL" 2>/dev/null; echo "exit: $?"  # T9 → exit: 2
```

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
