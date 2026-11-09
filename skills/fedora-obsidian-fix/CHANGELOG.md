# fedora-obsidian-fix Changelog

| Updated | Change |
|---------|--------|
| 2026-11-08 21:31 | v1.2.0 — Add anti-fabrication rules and CNL compliance for Observable qualification; Restructure steps to CNL workflow format for Quality qualification |
| 2026-11-05 19:31 | v1.1.0 — Add model-tier to frontmatter |
| 2026-09-04 11:04 | v1.1.0 — Fix duplicate GNOME Dash icon. Added `--class=md.obsidian.Obsidian` to wrapper (forces consistent WM_CLASS on all Electron windows under X11 mode). Added step to shadow Snap-provided `obsidian_obsidian.desktop` with `Hidden=true` override (prevents competing `.desktop` files with same `StartupWMClass` from causing duplicate icons). Updated gotchas and verification checklist. |
| 2026-08-27 09:06 | v1.0.0 — Initial skill capturing Obsidian Snap portal fix for Fedora Wayland. Wrapper script sets SNAP_DESKTOP_FILE and forces --ozone-platform=x11 to bypass broken portal auth. |
