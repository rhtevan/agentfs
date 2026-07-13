---
name: hermes-desktop-fixes
description: Diagnose and maintain Hermes Agent Desktop fixes for custom provider identity loss, Electron sandbox issues, and electron-builder workspace hoisting problems
version: 2
metadata:
  tags: [hermes, desktop, electron, fix, provider]
---

# Hermes Desktop Fixes

## Bugs Fixed

### 0. LC_CTYPE Locale Warning (Cosmetic, Annoying)
**Symptom:** `bash: warning: setlocale: LC_CTYPE: cannot change locale (UTF-8): No such file or directory` — appears 6× in the Desktop in-app terminal on every shell start.
**Root cause:** Electron inherits macOS-style `LC_CTYPE=UTF-8` (bare, no language prefix like `en_US.`). Bash calls `setlocale()` during startup before any profile/rc file is sourced, so `.bashrc` fixes are too late.
**Fix:** Three layers (belt-and-suspenders):
1. `~/.hermes/.env` — `LC_CTYPE=en_US.UTF-8` (loaded by `load_hermes_dotenv()` before spawning terminals)
2. `~/.hermes/hermes-env.sh` — conditional export when `LC_CTYPE` is "UTF-8" or empty
3. `~/.config/environment.d/50-locale-fix.conf` — systemd user env (applies to new login sessions)
**Note:** The `.bash_profile` early-export approach does NOT work — bash's `setlocale()` fires before any profile is sourced.

### 1. Provider Identity Loss (Critical)
**Symptom:** "No LLM provider configured" on new Desktop sessions; CLI works fine.
**Root cause:** `_session_info()` in `tui_gateway/server.py` reports `agent.provider = "custom"` (resolved generic) instead of `"custom:litellm-vertex-ai"`. Desktop caches this bare `"custom"` in localStorage, sends it on next `session.create`. `_get_named_custom_provider("custom")` returns None → falls through → no provider.
**Fix:** `_resolve_session_info_provider(agent)` helper maps bare `"custom"` back to `custom:<name>` via `find_custom_provider_identity(base_url)`.

### 2. Goose Node Wrapper Breaks Builds
**Symptom:** npm/electron-builder fails with CWD errors.
**Root cause:** `/usr/lib/Goose/resources/bin/node` wrapper does `cd ~/.config/goose/mcp-hermit` before running real node.
**Fix:** `hermes-env.sh` strips it from PATH.

### 3. Electron Sandbox Requires Sudo
**Symptom:** `hermes desktop` prompts for sudo password to set SUID on chrome-sandbox.
**Root cause:** `_desktop_linux_sandbox_fixup()` in `hermes_cli/main.py` requires root.
**Fix:** Early return when `ELECTRON_DISABLE_SANDBOX=1` is set. Env var set in `hermes-env.sh` and `.env`.

### 4. electron-builder Can't Find Electron
**Symptom:** Build fails looking for `../../node_modules/electron/dist`.
**Root cause:** npm workspace hoisting puts electron in `apps/desktop/node_modules/electron/`, not repo root.
**Fix:** Inject symlink creation into `apps/desktop/scripts/patch-electron-builder-mac-binary.cjs`.

## Architecture

### Update-proof mechanism
The key challenge: `git pull --ff-only` refuses to merge when skip-worktree files differ from the index (despite hiding from `git status`). And `git reset --hard` (the fallback) fires no hooks.

**Solution:** The launcher intercepts `hermes update`:
1. **Before update:** `hermes-revert-patches.sh` reverts all 3 files to clean upstream + clears skip-worktree
2. **During update:** `git pull --ff-only` succeeds (working tree is clean)
3. **After update:** Two mechanisms re-apply patches:
   - `post-merge` git hook calls `hermes-apply-patches.sh` (fires when pull has new commits)
   - Launcher calls `hermes-apply-patches.sh` as belt-and-suspenders (always fires)

### Files outside git (permanent, never overwritten by update)

| File | Purpose |
|------|---------|
| `~/.hermes/hermes-env.sh` | PATH fix + `ELECTRON_DISABLE_SANDBOX=1` + `LC_CTYPE` fix |
| `~/.hermes/hermes-apply-patches.sh` | Idempotent: applies all 3 source patches + sets skip-worktree |
| `~/.hermes/hermes-revert-patches.sh` | Reverts patched files to clean upstream before update |
| `~/.hermes/hermes-check-patches.sh` | Health check (9 checks) |
| `~/.hermes/.env` | `ELECTRON_DISABLE_SANDBOX=1` + `LC_CTYPE=en_US.UTF-8` (loaded by `load_hermes_dotenv()`) |
| `~/.local/bin/hermes` | Launcher: sources env, intercepts update |
| `~/.hermes/hermes-agent/.git/hooks/post-merge` | Calls hermes-apply-patches.sh |

### Files patched (git-tracked, skip-worktree protected)

1. `tui_gateway/server.py` — `_resolve_session_info_provider()` + usage in `_session_info()`
2. `hermes_cli/main.py` — `ELECTRON_DISABLE_SANDBOX` check in `_desktop_linux_sandbox_fixup()`
3. `apps/desktop/scripts/patch-electron-builder-mac-binary.cjs` — electron symlink at line 2

## Recovery

```bash
# Health check
bash ~/.hermes/hermes-check-patches.sh

# Full recovery (idempotent)
bash ~/.agents/skills/hermes-desktop-fixes/recover.sh

# Clear stale Desktop cache (if provider issue recurs)
rm -rf ~/.config/Hermes/Local\ Storage/leveldb/*
```

## Known Limitations
- If upstream renames `_session_info`, `_desktop_linux_sandbox_fixup`, or removes the `process.exit(0)` in the prebuilder, the sed patterns will silently fail. The health check detects this.
- The Desktop rebuild during `hermes update` calls `python -m hermes_cli.main desktop --build-only` directly (bypasses launcher), but `--build-only` returns before the sandbox check, so it's non-fatal.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-26 14:07 | v1.0 — Initial skill |
