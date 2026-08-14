# Changelog

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
