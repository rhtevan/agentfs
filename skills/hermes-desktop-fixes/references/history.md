# hermes-desktop-fixes — Bug History (v1–v3) and Upstream Absorption

v1–v3 of this skill patched Hermes Desktop by hand: a wrapper launcher, a
`server.py` sed patch, a post-merge hook that re-applied patches, and a
hand-written `hermes.desktop`. Hermes Agent v0.23.3 (2026.9.24, commit
`caafe5389ae5`) ships equivalent fixes upstream. In v4.0.0 the skill only
checks health and cleans up v3 leftovers.

## Bug table

| # | Symptom (v1–v3 era) | v3 fix | Upstream status (v0.23.3) | v4 action |
|---|---------------------|--------|---------------------------|-----------|
| 0 | Locale crash / garbled text when `LC_CTYPE` was unset in GUI launch | `LC_CTYPE` exported by `hermes-env.sh` wrapper | Not reproduced in the 2026-11-22 user test | Wrapper removed |
| 1 | Desktop showed the wrong provider for a session | sed patch on `tui_gateway/server.py` `_session_info` | `_session_info` uses `_scoped_session_provider()` (`tui_gateway/server.py:1466`, defined in `tui_gateway/agent_factory.py:185`) | Patch reverted; skip-worktree cleared |
| 2 | Desktop picked up Goose's bundled `node` from PATH | PATH-cleaning wrapper | Not reproduced | Wrapper removed |
| 3 | Chromium setuid-sandbox failure → sudo prompt / crash | `--no-sandbox` / `ELECTRON_DISABLE_SANDBOX` in wrapper | Probes the user-namespace sandbox (`✓ Using Chromium's user-namespace sandbox`) and honours `ELECTRON_DISABLE_SANDBOX` | Nothing needed |
| 4 | Two taskbar icons / generic icon on GNOME Wayland | Hand-written `hermes.desktop`, `StartupWMClass=Hermes` | `hermes_cli/linux_desktop_entry.py` writes `com.nousresearch.hermes.desktop` with `StartupWMClass=com.nousresearch.hermes`, hides legacy `hermes.desktop` (`NoDisplay`); opt-out `desktop.manage_launcher_entry` | Visible legacy entry removed |
| 5 | electron-builder rebuild steps | Manual build script | `hermes desktop` builds/stamps the packaged app itself | Retired |
| 6 | Intel Arc (Meteor Lake-P) GPU-process FATAL → window vanishes | `--disable-gpu` in wrapper | `desktop.disable_gpu` config (default `auto` = only on remote displays, `config_defaults.py:2590`) | Set `desktop.disable_gpu true` **only** when `FATAL.*GPU process` appears in `~/.hermes/logs/desktop-chromium.log` |
| 7 | Window translucency made text unreadable | Renderer-JS localStorage edit (below) | Still a user preference, not a bug | Documented here only |
| — | `update --check` modified the tree | Custom check script | `update --check` / `--plan` are report-only (`venv_sync.py:377`) | Check script removed |

## Bug #7 — translucency reset technique

Hermes Desktop stores translucency in renderer localStorage under
`hermes.desktop.translucency.v2`. To set it to fully clear, run this in the
renderer:

```js
localStorage.setItem('hermes.desktop.translucency.v2', JSON.stringify({mode:'clear',base:{intensity:0,fade:0},light:{},dark:{}}));
dispatchEvent(new StorageEvent('storage',{key:'hermes.desktop.translucency.v2'}));
```

Delivery: put the snippet in a `<script>` in an HTML file and render it inside
Hermes Desktop with `::preview{file="/path/to/file.html"}`. The preview runs in
the renderer's origin, so the localStorage write applies right away. Do not
clear all of localStorage. v3 `recover.sh` did that and lost other UI state.

## Why v3 `recover.sh` was deleted

- It wrote a launcher that execs `~/.hermes/hermes-agent/venv/bin/hermes`.
  That path does not exist in v0.23.x (the real binary is
  `~/.hermes/hermes-agent/.hermes/bin/hermes`), so `hermes` would break.
- It wrote `StartupWMClass=Hermes`, which does not match upstream's
  `com.nousresearch.hermes`, so two icons would come back.
- It re-installed the patch/post-merge-hook machinery. That machinery
  conflicts with upstream updates (`not uptodate. Cannot merge`).

## Verification evidence (2026-11-22, v0.23.3, Fedora, GNOME Wayland, Intel Arc)

User launched `hermes desktop` without the patches: no sudo prompt, GUI stable,
correct Hermes icon, a single launcher entry `com.nousresearch.hermes.desktop`,
0 FATAL lines in `desktop-chromium.log`. The only output was harmless Chromium
noise (`'--ozone-platform=wayland' is not compatible with Vulkan`,
`Persistent cache error`, a GLib-GObject handler warning at close).
