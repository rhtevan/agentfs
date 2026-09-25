# hermes-desktop-fixes Changelog


| Updated | Change |
|---------|--------|
| 2026-09-25 13:34 | v3.0.0 — v3.0: Rewrote Bug #4 (Wayland app-id), retired Bugs #3/#5, updated architecture |
| 2026-09-25 | v3.0 — Rewrote Bug #4: root cause is Wayland app-id mismatch (`com.nousresearch.hermes` from Electron `desktopName`), not `StartupWMClass` case. Desktop entry renamed to `com.nousresearch.hermes.desktop`. Launcher wrapper now has background watcher to delete upstream's auto-generated `hermes.desktop` and maintain our entry. Icon switched from absolute path to themed name (`Icon=hermes`) using upstream hicolor installs. Retired Bug #3 (sandbox bypass patch — upstream refactored, env var sufficient) and Bug #5 (electron symlink — file removed upstream). Updated recover.sh, health check, revert/apply scripts to match. Reduced skip-worktree to 1 file (server.py only). |
| 2026-07-28 | v2.1 — Added fix #4: duplicate taskbar icon on Fedora/GNOME Wayland (`StartupWMClass` case mismatch); renumbered electron-builder fix to #5; added `.desktop` file to "Files outside git" table |
| 2026-06-26 14:07 | v1.0 — Initial skill |
