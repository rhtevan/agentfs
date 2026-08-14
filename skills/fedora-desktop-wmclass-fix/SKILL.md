---
name: fedora-desktop-wmclass-fix
description: >
  fix desktop wmclass, audit wmclass, electron duplicate icon,
  fix taskbar duplicate, desktop startup wmclass
argument-hint: "[--fix] [--app <name>]"
compatibility: "Fedora/GNOME on Wayland with Electron apps"
metadata:
  author: agentfs
  version: "1.0.0"
  tags: [fedora, gnome, wayland, electron, desktop, wmclass]
user-invocable: true
disable-model-invocation: false
---

# Fedora Desktop WMClass Fix

Audit and fix `StartupWMClass` mismatches in `.desktop` files for
Electron apps on Fedora/GNOME/Wayland. When `StartupWMClass` is
missing or uses the wrong case, GNOME cannot match a running window
to its pinned launcher icon, causing a duplicate generic icon to
appear on the taskbar (Window List) or dock. This skill detects
the problem across all installed Electron apps and can fix them
automatically.

## Prerequisites

- Fedora with GNOME desktop on Wayland
- One or more Electron apps installed (e.g., Goose, VS Code, Slack,
  Obsidian, Hermes)

## Background: The Lowercase Convention

Electron apps on Wayland register their `app-id` using the
**lowercase** binary name (derived from the `name` field in
`package.json` or the executable filename). GNOME matches running
windows to `.desktop` files using this `app-id` against the
`StartupWMClass` field.

| Binary Name | Wayland app-id | Required StartupWMClass |
|-------------|---------------|------------------------|
| `Goose`     | `goose`       | `goose`                |
| `Hermes`    | `hermes`      | `hermes`               |
| `Code`      | `code`        | `code`                 |

When `StartupWMClass` is missing, wrong-cased (e.g., `Goose` instead
of `goose`), or absent entirely, GNOME shows:
1. The **pinned** launcher icon (from favorites) — no running indicator
2. A separate **generic** icon on the taskbar for the running window

This is a recurring problem because app reinstalls or updates often
overwrite the system `.desktop` file with a default that lacks
`StartupWMClass` or uses the original (wrong-cased) value.

## Steps

1. **Audit all Electron apps** (dry-run)

   Scan all `.desktop` files and report which Electron apps have
   missing or mismatched `StartupWMClass`:

   ```bash
   bash ~/.agents/skills/fedora-desktop-wmclass-fix/scripts/wmclass-audit.sh
   ```

2. **Audit a specific app**

   Check a single app by name (the `.desktop` basename without
   extension):

   ```bash
   bash ~/.agents/skills/fedora-desktop-wmclass-fix/scripts/wmclass-audit.sh --app Goose
   ```

3. **Fix all issues**

   Apply corrections automatically. For system-level `.desktop` files,
   the script copies them to `~/.local/share/applications/` first
   (user override), then sets the correct `StartupWMClass`:

   ```bash
   bash ~/.agents/skills/fedora-desktop-wmclass-fix/scripts/wmclass-audit.sh --fix
   ```

4. **Fix a specific app**

   ```bash
   bash ~/.agents/skills/fedora-desktop-wmclass-fix/scripts/wmclass-audit.sh --fix --app Goose
   ```

5. **Restart the affected app** to see the fix take effect.

## How the Script Works

The audit script (`scripts/wmclass-audit.sh`):

1. Scans `.desktop` files in:
   - `~/.local/share/applications/` (user overrides)
   - `/usr/share/applications/` (system)
   - `/var/lib/flatpak/exports/share/applications/` (Flatpak)
   - `/var/lib/snapd/desktop/applications/` (Snap)

2. Detects Electron apps by checking for `resources/app.asar`
   adjacent to the binary referenced in the `Exec=` line.

3. Computes the expected `StartupWMClass` by lowercasing the
   binary name (Electron's Wayland convention).

4. Compares current vs expected and reports:
   - ✅ OK — correct
   - ⚠️ MISSING — no `StartupWMClass` field
   - ⚠️ MISMATCH — value doesn't match expected lowercase

5. In `--fix` mode: copies system files to user dir if needed,
   sets/updates `StartupWMClass`, and refreshes the desktop
   database.

## Gotchas

- **Reinstalls reset the fix.** When an Electron app is reinstalled
  or updated via RPM/deb, the system `.desktop` file is overwritten.
  The user-level override in `~/.local/share/applications/` is
  preserved, but if the system file was the only one, re-run this
  skill after updates.

- **Some Electron apps set custom app-ids.** A few Electron apps
  override the default Wayland app-id via `app.setDesktopFileName()`
  or `--class` flag. In these cases, the lowercase-binary-name
  heuristic may not match. The script's output will show a mismatch
  even after fixing — if the app still shows a duplicate icon after
  the fix, manually inspect the actual app-id.

- **Flatpak Electron apps** use the Flatpak app-id (e.g.,
  `com.slack.Slack`) as the Wayland app-id, not the binary name.
  The script currently uses the binary name heuristic. Flatpak apps
  usually ship correct `.desktop` files, so this is rarely an issue.

- **The `Goose.desktop` user override** also contains `GOOSE_SHELL`
  and `PATH` in its `Exec=` line (from the `goose-desktop-env-fix`
  skill). When this script copies/modifies the file, it preserves
  the existing `Exec=` line — only `StartupWMClass` is touched.

- **GNOME Shell Eval is restricted** in GNOME 45+, so there is no
  programmatic way to query the actual Wayland app-id of a running
  window from a shell script. The lowercase heuristic is based on
  Electron's source code behavior and confirmed empirically.

## Verification

- [ ] Run the audit script — all Electron apps show ✅ OK
- [ ] Pinned Electron app icons on the dock show a running indicator
      (dot) when the app is open
- [ ] No duplicate generic icons appear on the Window List taskbar
- [ ] After app reinstall, re-running with `--fix` restores the
      correct `StartupWMClass`

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
