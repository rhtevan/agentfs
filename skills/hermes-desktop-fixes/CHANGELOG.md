# hermes-desktop-fixes Changelog


| Updated | Change |
|---------|--------|
| 2026-09-28 | v3.2.0 — Added Bug #6: GPU process crash (Intel Arc Meteor Lake + Electron 40 + no-sandbox + Wayland). GPU subprocess fails to launch (error_code=1002), retries 6×, then FATAL exits Electron. Fix: `desktop.disable_gpu: true` in config.yaml → `HERMES_DESKTOP_DISABLE_GPU=1` → `app.disableHardwareAcceleration()`. Also fixed `.desktop` entry overwritten by upstream's `linux_desktop_entry.py` regeneration (Exec pointed to raw python path instead of launcher wrapper). |
| 2026-09-27 20:22 | v3.1.1 — Added `--check` pre-flight to launcher: plain `hermes update` short-circuits in ~2s when already up to date, avoiding upstream's unconditional ~2min TUI/web/desktop rebuild. Read-only flags (`--check`, `--plan`) pass through without touching patches. |
| 2026-09-27 20:09 | v3.1.0 — Fixed orphaned skip-worktree on `hermes_cli/main.py` (retired Bug #3 leftover) that blocked `hermes update`. Rewrote `hermes-revert-patches.sh` to generically clear all skip-worktree flags instead of hardcoding filenames. Added orphaned skip-worktree detection to health check. |
| 2026-09-25 13:34 | v3.0.0 — v3.0: Rewrote Bug #4 (Wayland app-id), retired Bugs #3/#5, updated architecture |
| 2026-09-25 | v3.0 — Rewrote Bug #4: root cause is Wayland app-id mismatch (`com.nousresearch.hermes` from Electron `desktopName`), not `StartupWMClass` case. Desktop entry renamed to `com.nousresearch.hermes.desktop`. Launcher wrapper now has background watcher to delete upstream's auto-generated `hermes.desktop` and maintain our entry. Icon switched from absolute path to themed name (`Icon=hermes`) using upstream hicolor installs. Retired Bug #3 (sandbox bypass patch — upstream refactored, env var sufficient) and Bug #5 (electron symlink — file removed upstream). Updated recover.sh, health check, revert/apply scripts to match. Reduced skip-worktree to 1 file (server.py only). |
| 2026-07-28 | v2.1 — Added fix #4: duplicate taskbar icon on Fedora/GNOME Wayland (`StartupWMClass` case mismatch); renumbered electron-builder fix to #5; added `.desktop` file to "Files outside git" table |
| 2026-06-26 14:07 | v1.0 — Initial skill |
