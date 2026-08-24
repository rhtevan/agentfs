---
name: dsh-setup
description: >
  setup dsh, install dsh, update dsh, teardown dsh,
  dsh launcher, dsh desktop
platforms: ['linux']
writes-files: true
metadata:
  author: agentfs
  version: "1.2.1"
  tags: [dsh, deepseek-harness, agent-harness, setup, launcher]
  related_skills: [dsh-litellm-provider]
user-invocable: true
disable-model-invocation: false
---

# DSH Setup — Install, Launch, and Manage DeepSeek Harness

Install and manage [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`) as a locally-installed agent harness with a dedicated Chrome
app-mode launcher and GNOME `.desktop` integration. DSH is a WebUI-based
agent harness where everything is a plugin, powered by Cordis.

This skill uses **pnpm** for package management (npm cannot handle DSH's
62+ direct dependencies — it hangs indefinitely consuming 3+ GB RAM).
The install is persistent (not ephemeral `npx`), so launches are instant
(~3 seconds) and updates are explicit.

## Prerequisites

- Node.js ≥ 22.19.0 or ≥ 24.0.0 (`node --version`)
- Google Chrome installed (`/usr/bin/google-chrome`)
- Internet access for initial install and updates

## Architecture

| Component | Path | Purpose |
|-----------|------|----------|
| pnpm | `~/.local/share/pnpm/` | Package manager (installed once) |
| DSH install | `~/.local/share/dsh/` | pnpm-managed DSH + node_modules (~250 MB) |
| DSH home | `~/.dsh/` | DSH user data, settings, credentials, sessions |
| Systemd service | `~/.config/systemd/user/dsh.service` | Backend lifecycle (start/stop/status/logs) |
| Chrome profile | `~/.local/share/dsh-chrome-profile/` | Separate Chrome profile for security isolation |
| Launcher | `~/.local/bin/dsh-launcher` | Starts service → Chrome app-mode (maximized) → waits for Chrome exit → stops service |
| Desktop file | `~/.local/share/applications/dsh.desktop` | GNOME app launcher entry |
| Icon | `~/.local/share/icons/hicolor/*/apps/dsh.png` | App icon (48, 128, 256, 1024px) |

DSH stores its config in `~/.dsh/` by default (overridable via `DSH_HOME`
env var). The `settings.yaml` within controls model providers.

## Steps

### Setup (initial install)

1. **Run the install script**
   ```bash
   bash ~/.agents/skills/dsh-setup/scripts/install.sh
   ```
   This script:
   - Verifies Node.js version meets DSH requirements
   - Installs pnpm locally if not present
   - Creates `~/.local/share/dsh/` and runs `pnpm add @deepseek-ai/dsh`
   - Approves required build scripts (node-pty, koffi, protobufjs)
   - Verifies the `dsh` binary works

2. **Install the desktop launcher**
   ```bash
   bash ~/.agents/skills/dsh-setup/scripts/install-desktop.sh
   ```
   This script:
   - Creates a systemd user service (`dsh.service`) for backend lifecycle
   - Writes `dsh-launcher` wrapper to `~/.local/bin/`
   - Creates a `.desktop` file with the DSH icon (multiple hicolor sizes)
   - Updates the desktop database
   - The launcher starts the backend via `systemctl --user start dsh`,
     waits for port 3080, then opens Chrome in `--app` mode
   - Chrome opens in a separate profile (`--user-data-dir`) for
     security isolation and to enable `--start-maximized`
   - When Chrome exits, the launcher stops the service automatically
     (separate profile = independent process, trackable via `wait`)

3. **Verify the installation**
   ```bash
   bash ~/.agents/skills/dsh-setup/scripts/verify.sh
   ```

### Update

```bash
bash ~/.agents/skills/dsh-setup/scripts/update.sh
```

Runs `pnpm update @deepseek-ai/dsh` in the install directory. This
re-resolves from the pnpm store — typically completes in under 5
seconds for cached packages.

### Teardown

```bash
bash ~/.agents/skills/dsh-setup/scripts/teardown.sh
```

Removes:
- `dsh.service` (systemd user service — stopped and disabled first)
- `~/.local/share/dsh/` (install directory)
- `~/.local/bin/dsh-launcher` (wrapper script)
- `~/.local/share/applications/dsh.desktop` (desktop entry)
- `~/.local/share/icons/hicolor/*/apps/dsh.png` (all icon sizes)
- Optionally `~/.dsh/` (user data — use `--with-data` flag)

Does NOT remove pnpm (shared tool, may be used by other projects).

## Gotchas

- **npm is broken for DSH.** 62 direct dependencies with deep
  transitive trees causes npm's resolver to OOM at 3+ GB. Always
  use pnpm.
- **Goose's hermit node wrapper intercepts `node`/`npx`/`pnpm`
  commands** in shell tool contexts. Scripts use `/usr/bin/node`
  explicitly to bypass hermit and use the system Node.js.
- **First install downloads ~250 MB** of packages. Subsequent
  installs/updates reuse the pnpm content-addressable store.
- **`pnpm approve-builds` is required** — DSH has native deps
  (node-pty, koffi) that need post-install build scripts.
- **Port 3080 conflict** — the launcher checks if the systemd
  service is already active. If so, it reuses the running backend.
- **Backend lifecycle** — managed by systemd user service. Use
  `systemctl --user status dsh` for status, `journalctl --user -u dsh`
  for logs. The launcher stops the service when Chrome exits.
- **Separate Chrome profile** — DSH runs in its own Chrome profile
  (`~/.local/share/dsh-chrome-profile/`) for security isolation.
  This also makes `--start-maximized` work (ignored when merging
  into existing Chrome session) and gives a trackable process.
- **WMClass matching** — Chrome with `--user-data-dir` on Wayland
  uses app_id `chrome-127.0.0.1__-Default`. The `.desktop` file's
  `StartupWMClass` must match this exactly for GNOME to show the
  whale icon instead of a generic Chrome icon.
- **DSH is in developer preview** (created 2026-08-13). Expect
  breaking changes. Pin the version via
  `pnpm add @deepseek-ai/dsh@<version>` if stability is needed.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|----------------|
| S1 | Install pnpm and DSH to `~/.local/share/dsh/` | `verify.sh` checks binary + node_modules |
| S2 | Create desktop launcher that starts backend + Chrome app window | `verify.sh` checks files exist |
| S3 | Update DSH to latest version | `update.sh` exits 0, `dsh --version` shows new version |
| S4 | Teardown removes all installed files | `teardown.sh` exits 0, paths absent |
| S5 | Systemd service manages backend lifecycle | `systemctl --user status dsh` shows active/inactive |
| S6 | Launcher stops service when Chrome exits | Close Chrome window, service stops immediately |
| S7 | Separate Chrome profile for security isolation | `~/.local/share/dsh-chrome-profile/` exists |
| S8 | Window opens maximized | Visual check on launch |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `bash scripts/verify.sh` | All checks pass |
| T2 | S2 | `ls ~/.local/bin/dsh-launcher ~/.local/share/applications/dsh.desktop` | Both files exist |
| T3 | S3 | `bash scripts/update.sh && bash scripts/verify.sh` | Update succeeds, verify passes |
| T4 | S4 | `bash scripts/teardown.sh --no-data && bash scripts/verify.sh` | Teardown succeeds, verify reports missing |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
