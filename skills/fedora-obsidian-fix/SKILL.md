---
name: fedora-obsidian-fix
description: >
  fix obsidian, obsidian file dialog, obsidian open button broken,
  obsidian snap wayland fix, obsidian portal denied
argument-hint: "No arguments required — run the skill to diagnose and fix"
compatibility: "Fedora with GNOME/Wayland, Obsidian installed via Snap (classic)"
metadata:
  author: agentfs
  version: "1.0.0"
  tags: [fedora, obsidian, wayland, snap, desktop-fix]
user-invocable: true
disable-model-invocation: false
---

# Fix Obsidian Snap File Dialog on Fedora Wayland

Fixes the Obsidian Snap's broken "Open folder as vault" button on
Fedora running GNOME/Wayland. The button appears to do nothing when
clicked — no file picker dialog appears and no error is shown to the
user. The root cause is a portal authentication failure between the
Snap's Electron process and `xdg-desktop-portal`. This skill creates
a wrapper script and `.desktop` override that bypass the broken
Wayland portal path.

## Root Cause

The Obsidian Snap (classic confinement) does not set
`SNAP_DESKTOP_FILE` in its environment. On Fedora 44+,
`xdg-desktop-portal` validates the calling application's desktop
file identity via snap metadata. Without the `DesktopFile` key,
portal operations are silently denied:

```
GDBus.Error:org.freedesktop.DBus.Error.AccessDenied:
Portal operation not allowed: Key file does not have key
"DesktopFile" in group "Snap Info"
```

Electron's `dialog.showOpenDialog` goes through the portal path
when `--ozone-platform=wayland` is active (auto-detected). The
portal denial causes the dialog promise to silently fail — no
dialog, no error visible to the user.

## Prerequisites

- Fedora with GNOME and Wayland session
- Obsidian installed via Snap (`snap list obsidian`)
- `xdg-desktop-portal` and `xdg-desktop-portal-gnome` installed

## Steps

1. **Diagnose**

   Run the diagnostic script to confirm the issue applies:

   ```bash
   bash ~/.agents/skills/fedora-obsidian-fix/scripts/diagnose.sh
   ```

   The script checks: Snap installation, Wayland session, portal
   services, and the portal error condition.

2. **Apply the fix**

   Run the fix script to create the wrapper and desktop override:

   ```bash
   bash ~/.agents/skills/fedora-obsidian-fix/scripts/fix.sh
   ```

   This creates:
   - `~/.local/bin/obsidian-wrapper.sh` — sets
     `BAMF_DESKTOP_FILE_HINT`, `SNAP_DESKTOP_FILE`, `GTK_USE_PORTAL=1`,
     and passes `--ozone-platform=x11` to Obsidian
   - `~/.local/share/applications/obsidian_md.obsidian.Obsidian.desktop`
     — user-local `.desktop` override that launches via the wrapper

3. **Restart Obsidian**

   Quit Obsidian completely and relaunch from the Dash (or run
   `~/.local/bin/obsidian-wrapper.sh` from terminal).

4. **Verify**

   Click "Open folder as vault" → the GNOME file picker should
   appear and the "Open" button should respond.

## Gotchas

- **Snap refreshes do not break the fix.** The user-local `.desktop`
  file in `~/.local/share/applications/` takes priority over the
  snap-provided one in `/var/lib/snapd/desktop/applications/`.
- **Stale SingletonLock.** If Obsidian was killed without clean
  shutdown, `~/.config/obsidian/SingletonLock` may be stale. The
  fix script removes it automatically.
- **`--ozone-platform=x11` trade-off.** This forces Electron to
  use XWayland instead of native Wayland. Visual differences are
  minimal (slightly different window decorations, no fractional
  scaling), but the file dialog works reliably.
- **The Vulkan warning is harmless.** When running on Wayland,
  Obsidian may log `'--ozone-platform=wayland' is not compatible
  with Vulkan`. With the x11 override, this warning disappears.
- **GTK_USE_PORTAL=1 alone is insufficient.** The env var makes
  GTK apps route dialogs through the portal, but the portal itself
  rejects the call due to the missing Snap desktop file identity.
  The `--ozone-platform=x11` bypasses the portal path entirely.

## Verification

- [ ] `~/.local/bin/obsidian-wrapper.sh` exists and is executable
- [ ] `~/.local/share/applications/obsidian_md.obsidian.Obsidian.desktop`
      exists and `Exec=` points to the wrapper
- [ ] Obsidian launches from Dash without portal errors
- [ ] "Open folder as vault" → "Open" button opens the file picker

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
