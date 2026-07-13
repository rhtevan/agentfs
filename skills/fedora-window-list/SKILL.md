---
name: fedora-window-list
description: Toggle the window list (taskbar) at the bottom of the Fedora GNOME desktop on or off
metadata:
  tags: [fedora, gnome, desktop, taskbar]
---

# Fedora GNOME Window List Toggle

This skill accepts one argument: `enable` or `disable`.

- `/fedora-window-list enable` — Show the window list at the bottom of the workspace
- `/fedora-window-list disable` — Hide the window list

If no argument is provided, check the current state and report it.

## Procedure

The window list is provided by the GNOME Shell extension `window-list@gnome-shell-extensions.gcampax.github.com`.

### If the argument is `disable`:

```bash
gnome-extensions disable window-list@gnome-shell-extensions.gcampax.github.com
```

### If the argument is `enable`:

```bash
gnome-extensions enable window-list@gnome-shell-extensions.gcampax.github.com
```

### If no argument is provided:

Check and report the current state:

```bash
gnome-extensions info window-list@gnome-shell-extensions.gcampax.github.com
```

## Verification

After any toggle, confirm the new state:

```bash
gnome-extensions info window-list@gnome-shell-extensions.gcampax.github.com 2>&1 | grep -i state
```

Look for `State: ACTIVE` (enabled) or `State: INACTIVE` (disabled). The change takes effect immediately — no restart needed.

## Notes

- The setting persists across reboots.
- If the extension is not installed: `sudo dnf install gnome-shell-extension-window-list`

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 10:31 | v1.0 — Initial skill |
