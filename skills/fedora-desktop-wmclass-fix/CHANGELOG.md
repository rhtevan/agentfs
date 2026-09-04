# Changelog

| Updated | Change |
|---------|--------|
| 2026-09-04 11:12 | v1.1.0 — Added gotchas for competing .desktop files and --ozone-platform=x11 WM_CLASS behavior |

## v1.1.0 — 2026-09-04

- Added gotcha: competing `.desktop` files with same `StartupWMClass` across
  `XDG_DATA_DIRS` locations cause duplicate GNOME Dash icons. Must shadow
  extras with `Hidden=true` user overrides.
- Added gotcha: `--ozone-platform=x11` changes Electron WM_CLASS behavior;
  pass `--class=<app-id>` in wrappers to force consistent WM_CLASS.
- Audit script TODO: detect multiple `.desktop` files claiming the same
  `StartupWMClass` and flag as a conflict.

## v1.0.0 — 2026-08-14

- Initial release
- Audit script scans system, user, Flatpak, and Snap `.desktop` dirs
- Detects Electron apps via `resources/app.asar` adjacency check
- Computes expected `StartupWMClass` using lowercase binary name convention
- Reports MISSING, MISMATCH, or OK status per app
- `--fix` mode: copies system files to user dir, sets correct WMClass
- `--app` flag: target a single application
- Documents the Electron/Wayland lowercase app-id convention
- Gotchas section covers reinstall resets, custom app-ids, Flatpak edge cases
