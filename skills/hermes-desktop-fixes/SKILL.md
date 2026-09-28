---
name: hermes-desktop-fixes
description: >
  fix hermes desktop, hermes electron fix, hermes identity fix
metadata:
  version: "3.1.1"
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

### 3. Electron Sandbox Requires Sudo (RETIRED — v3.0)
**Status:** Patch retired as of Sep 2026. Upstream refactored `_desktop_linux_sandbox_fixup()` — the function still exists but the code structure changed, so the sed pattern no longer matches. The `ELECTRON_DISABLE_SANDBOX=1` env var in `hermes-env.sh` and `.env` still prevents the sudo prompt; the source patch is no longer needed or applied.
**Original symptom:** `hermes desktop` prompts for sudo password to set SUID on chrome-sandbox.
**Original fix:** Early return when `ELECTRON_DISABLE_SANDBOX=1` is set, injected via sed into `main.py`.

### 4. Generic Taskbar Icon on Fedora/GNOME Wayland (Rewritten — v3.0)
**Symptom:** Hermes shows a generic application icon in the GNOME taskbar/dock instead of the Hermes logo. May also show duplicate icons (one pinned, one for the running window).
**Root cause (v2.1, Jul 2026):** `StartupWMClass=hermes` (lowercase) vs Electron's `WM_CLASS=Hermes` (capital H). This was the X11-era fix.
**Root cause (v3.0, Sep 2026):** On Wayland, GNOME matches windows to `.desktop` files using the **app-id**, not `StartupWMClass`. Electron derives the app-id from `package.json` `desktopName` field, which electron-builder sets via `extraMetadata: { desktopName: appId }` → resolves to `com.nousresearch.hermes`. GNOME looks for `com.nousresearch.hermes.desktop` — if that file doesn't exist, no icon match → generic icon.
**Additional complication:** Upstream's `linux_desktop_entry.py` auto-generates `hermes.desktop` on every `hermes desktop` launch with a broken `Exec` path (points into a stale install environment venv). If both `hermes.desktop` and our entry coexist, GNOME shows two entries in Apps grid.
**Fix (v3.0):**
1. Desktop entry named `com.nousresearch.hermes.desktop` — matches Electron's Wayland app-id
2. `Icon=hermes` (themed name) — resolves via upstream's hicolor icon installs at 24/32/48/256px
3. `Exec` uses our launcher wrapper with `ELECTRON_DISABLE_SANDBOX=1` and `--skip-build`
4. Background watcher in launcher wrapper detects upstream's `hermes.desktop` regeneration, deletes it, and refreshes our entry
5. GNOME favorites pinned to `com.nousresearch.hermes.desktop`

**Diagnostics:**
```bash
# Check Electron's Wayland app-id (from built package.json)
npx asar extract ~/.hermes/hermes-agent/apps/desktop/release/linux-unpacked/resources/app.asar /tmp/asar-check
python3 -c "import json; print(json.load(open('/tmp/asar-check/package.json'))['desktopName'])"

# Check which .desktop file GNOME used to launch
cat /proc/$(pgrep -f "linux-unpacked/Hermes" | head -1)/environ 2>/dev/null | tr '\0' '\n' | grep GIO_LAUNCHED_DESKTOP_FILE

# Verify icon theme resolves
python3 -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk; i=Gtk.IconTheme.get_default().lookup_icon('hermes',48,0); print(i.get_filename() if i else 'NOT FOUND')"

# Check for duplicate entries
ls ~/.local/share/applications/*hermes*.desktop
```

### 5. electron-builder Can't Find Electron (RETIRED — v3.0)
**Status:** Patch retired as of Sep 2026. Upstream removed `patch-electron-builder-mac-binary.cjs` entirely — only `dmgbuild-diagnostics.cjs` remains in `apps/desktop/scripts/`. The electron workspace hoisting issue may have been fixed upstream or is no longer relevant with current electron-builder versions.
**Original symptom:** Build fails looking for `../../node_modules/electron/dist`.
**Original fix:** Inject symlink creation into the prebuilder script.

## Architecture

### Update-proof mechanism
The key challenge: upstream's `linux_desktop_entry.py` regenerates `hermes.desktop` on every `hermes desktop` launch, and `git pull --ff-only` refuses to merge when skip-worktree files differ from the index.

**Solution:** The launcher wrapper (`~/.local/bin/hermes`) handles two concerns:

**Update interception:**
1. **Pre-flight:** Read-only flags (`--check`, `--plan`, `--list-venv-holders`, `--install-id`) pass through without touching patches. Plain `hermes update` runs `--check` first; if already up to date, short-circuits (avoids upstream's unconditional TUI/web/desktop rebuild in the completion path).
2. **Before update:** `hermes-revert-patches.sh` finds *all* skip-worktree files (`git ls-files -v | grep ^S`), clears flags, and checks out clean copies — this is generic, not hardcoded, so retired patches with orphaned flags are automatically cleaned up
3. **During update:** `git pull --ff-only` / `git reset` succeeds (working tree is clean)
4. **After update:** `hermes-apply-patches.sh` re-applies patches + sets skip-worktree
5. **Belt-and-suspenders:** `post-merge` git hook also calls apply-patches

**Desktop entry maintenance (background watcher):**
On `hermes desktop`, a background subshell polls for upstream's `hermes.desktop` (up to 30s). When detected:
1. Deletes upstream's `hermes.desktop` (broken `Exec`, causes duplicate in Apps grid)
2. Writes/refreshes `com.nousresearch.hermes.desktop` with correct `Exec` and `Icon=hermes`
3. Runs `update-desktop-database`

### Files outside git (permanent, never overwritten by update)

| File | Purpose |
|------|---------|
| `~/.hermes/hermes-env.sh` | PATH fix + `ELECTRON_DISABLE_SANDBOX=1` + `LC_CTYPE` fix |
| `~/.hermes/hermes-apply-patches.sh` | Idempotent: applies source patches + sets skip-worktree |
| `~/.hermes/hermes-revert-patches.sh` | Generically clears all skip-worktree flags + checks out clean upstream before update |
| `~/.hermes/hermes-check-patches.sh` | Health check |
| `~/.hermes/.env` | `ELECTRON_DISABLE_SANDBOX=1` + `LC_CTYPE=en_US.UTF-8` (loaded by `load_hermes_dotenv()`) |
| `~/.local/share/applications/com.nousresearch.hermes.desktop` | GNOME desktop entry (matches Wayland app-id) |
| `~/.local/bin/hermes` | Launcher: sources env, intercepts update, desktop entry watcher |
| `~/.hermes/hermes-agent/.git/hooks/post-merge` | Calls hermes-apply-patches.sh |

### Files patched (git-tracked, skip-worktree protected)

1. `tui_gateway/server.py` — `_resolve_session_info_provider()` + usage in `_session_info()`

*Retired patches (no longer applied):*
- ~~`hermes_cli/main.py` — sandbox bypass~~ (upstream refactored, env var sufficient)
- ~~`apps/desktop/scripts/patch-electron-builder-mac-binary.cjs` — electron symlink~~ (file removed upstream)

## Recovery

```bash
# Health check
bash ~/.hermes/hermes-check-patches.sh

# Full recovery (idempotent)
bash ~/.agents/skills/hermes-desktop-fixes/recover.sh

# Clear stale Desktop cache (if provider issue recurs)
rm -rf ~/.config/Hermes/Local\ Storage/leveldb/*
```

## Resolved Issues (v3.1)
- **Orphaned skip-worktree on `hermes_cli/main.py`:** The v3.0 retirement of Bug #3 stopped *applying* the `main.py` patch but never cleared the `skip-worktree` flag left behind by older versions. When upstream changed `hermes_cli/main.py`, `git reset --hard` failed with `Entry 'hermes_cli/main.py' not uptodate. Cannot merge.` The revert script now generically discovers and clears all skip-worktree flags, and the health check detects orphaned flags.
- **Unconditional TUI/web/desktop rebuild on every `hermes update`:** Upstream's completion path (`complete_source_checkout` → `build_update_products`) unconditionally rebuilds all frontends even when already up to date. This was masked before because the orphaned skip-worktree flag made updates fail before reaching the build step. Fixed by adding a `--check` pre-flight in the launcher: plain `hermes update` now fetches and checks first, short-circuiting in ~2s when current instead of ~2min of unnecessary rebuilds.

## Known Limitations
- If upstream renames `_session_info` or changes the provider plumbing, the sed pattern for Bug #1 will silently fail. The health check detects this.
- If upstream changes `desktopName` from `com.nousresearch.hermes` to a different app-id, the desktop entry filename must be updated to match.
- The background watcher polls for up to 30s. If upstream's deferred desktop entry write takes longer (unlikely), the duplicate may briefly appear.
- The Desktop rebuild during `hermes update` calls `python -m hermes_cli.main desktop --build-only` directly (bypasses launcher), but `--build-only` returns before the sandbox check, so it's non-fatal.

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
