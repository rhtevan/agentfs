---
name: goose-desktop-env-fix
description: "Fix Goose Desktop shell environment so that shell commands have access to the full user environment (devbox/nix tools, crc/oc, cargo, sdkman, etc.)"
version: 1.0
metadata:
    tags: [goose, desktop, shell, environment, bashrc, devbox, nix]
---

# Goose Desktop Environment Fix

Fix the Goose Desktop `shell` tool so that shell commands run with the
full user environment — including devbox/nix-installed tools, crc/oc,
cargo, sdkman, and custom exports.

## Problem

Goose Desktop's `shell` tool runs **non-interactive, non-login** bash
shells (`bash -c "<command>"`). Bash only sources `~/.bashrc` for
**interactive** shells, so all user environment setup is missing:

| Shell Type                  | Files Sourced               |
|-----------------------------|-----------------------------|
| Login + Interactive         | `~/.bash_profile` → `~/.bashrc` |
| Interactive (non-login)     | `~/.bashrc`                 |
| Non-interactive, non-login  | **Only `$BASH_ENV`** (if set) |

Goose Desktop falls into the third category, resulting in:
- Bare `PATH` (missing devbox/nix, cargo, crc/oc, sdkman paths)
- Missing environment variables
- Tools like `gh`, `oc`, `hey`, `java` not found

Additionally, Goose Desktop on Fedora/GNOME may have a **user-level
`.desktop` file override** at `~/.local/share/applications/Goose.desktop`
that hardcodes `PATH` via `Exec=env PATH=...`, preventing
`environment.d` variables from reaching the Goose process.

## Root Causes

1. **Bash sourcing rules** — non-interactive shells don't source `~/.bashrc`
2. **Nix double-source guard** — `nix-daemon.sh` sets
   `__ETC_PROFILE_NIX_SOURCED=1` and skips if already set. The GNOME
   session sets this during login, but the Goose `.desktop` file
   overrides `PATH` without nix paths, so nix is "sourced" but its
   paths are missing.
3. **Desktop file override** — the user-level `.desktop` file's
   `Exec=env PATH=...` line overrides session environment variables
   set via `~/.config/environment.d/`

## Solution (3 files)

The fix has three components that work together:

### File 1: `~/.local/bin/goose-shell` (wrapper script)

A bash wrapper that sources `~/.bashrc` before executing the command.
Goose calls `$GOOSE_SHELL -c "<command>"`, so this wrapper runs first.

```bash
#!/bin/bash
# Goose Desktop shell wrapper — sources ~/.bashrc for full environment
# before executing the command passed via -c.
# Guard against recursive sourcing when exec'd bash also triggers this wrapper.
if [ -z "$__GOOSE_SHELL_SOURCED" ]; then
    export __GOOSE_SHELL_SOURCED=1
    # The Goose .desktop file sets a bare PATH, so nix/profile.d paths
    # are missing. Clear the nix "already sourced" guard so nix-daemon.sh
    # re-adds its paths.
    unset __ETC_PROFILE_NIX_SOURCED
    unset BASHRCSOURCED
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
exec /bin/bash "$@"
```

**Key details:**
- `__GOOSE_SHELL_SOURCED` guard prevents infinite recursion
- `unset __ETC_PROFILE_NIX_SOURCED` forces `nix-daemon.sh` to re-add
  nix paths (they were lost when the `.desktop` file overrode `PATH`)
- `unset BASHRCSOURCED` lets `/etc/bashrc` re-run to source
  `/etc/profile.d/*.sh` scripts
- `exec /bin/bash "$@"` replaces the wrapper with real bash to run the
  actual command

### File 2: `~/.local/share/applications/Goose.desktop` (desktop entry)

The user-level `.desktop` file must pass `GOOSE_SHELL` to the Goose
process. Add it to the existing `Exec=env ...` line:

```ini
[Desktop Entry]
Name=Goose
Exec=env GOOSE_SHELL=$HOME/.local/bin/goose-shell PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin /usr/lib/Goose/Goose %U
Icon=/usr/share/pixmaps/Goose.png
Terminal=false
Type=Application
Categories=Development;
MimeType=x-scheme-handler/goose;
```

**Note:** Replace `$HOME` with the actual home directory path (e.g.,
`/home/username`) since `.desktop` files don't expand shell variables.

If there is no user-level `.desktop` override, you can either:
- Create one from the system file at `/usr/share/applications/Goose.desktop`
- Or rely on `environment.d` alone (File 3)

### File 3: `~/.config/environment.d/60-goose-shell.conf`

Sets `GOOSE_SHELL` in the systemd user environment as a fallback for
any launch method that doesn't use the `.desktop` file:

```ini
# Tell Goose Desktop to use our wrapper shell that sources ~/.bashrc
GOOSE_SHELL=$HOME/.local/bin/goose-shell
```

**Note:** Replace `$HOME` with the actual home directory path.

### Prerequisite: `~/.bashrc` restructuring

The `~/.bashrc` must be restructured with an **interactive guard** so
that environment setup runs for all shells, but interactive-only setup
(completions, prompt integration) is skipped for non-interactive shells:

```bash
# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# ============================================================
# Environment setup (runs for ALL shells)
# ============================================================

# PATH additions
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH=$PATH:$HOME/.cargo/bin

# User-specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        [ -f "$rc" ] && . "$rc"
    done
fi
unset rc

# Devbox environment
eval "$(devbox global shellenv 2>/dev/null)"

# Other environment setup (crc/oc, exports, sdkman, etc.)
# ... add your environment exports here ...

# SDKMAN — must be near the end of the environment section
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# ============================================================
# Interactive-only setup (completions, prompt integration)
# Skipped for non-interactive shells (Goose Desktop, scripts, cron)
# ============================================================
[[ $- != *i* ]] && return

# Goose terminal integration
eval "$(goose term init bash)"

# Completions (devbox, hermes, gcloud, etc.)
. <(devbox completion bash 2>/dev/null)
eval "$(hermes completion bash 2>/dev/null)"
```

**Key principle:** Everything above `[[ $- != *i* ]] && return` runs
for ALL shells. Everything below runs only in interactive terminals.

## Steps to Apply

### Step 1: Create the goose-shell wrapper

```bash
cat > ~/.local/bin/goose-shell << 'EOF'
#!/bin/bash
if [ -z "$__GOOSE_SHELL_SOURCED" ]; then
    export __GOOSE_SHELL_SOURCED=1
    unset __ETC_PROFILE_NIX_SOURCED
    unset BASHRCSOURCED
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
exec /bin/bash "$@"
EOF
chmod +x ~/.local/bin/goose-shell
```

### Step 2: Restructure ~/.bashrc

Move all environment setup (PATH, exports, devbox shellenv, sdkman)
**above** the interactive guard. Move completions and prompt
integration **below** it. Add `[[ $- != *i* ]] && return` as the
separator.

**Caution with `crc oc-env`:** The output of `crc oc-env` contains
a comment line with an unmatched single quote (`# eval $(crc oc-env)`).
Using `eval "$(crc oc-env)"` in non-interactive shells causes a
parsing error. Replace it with a direct `export PATH=` statement:

```bash
# Instead of: eval "$(crc oc-env 2>/dev/null)"
export PATH="$HOME/.crc/bin/oc:$PATH"
```

### Step 3: Set GOOSE_SHELL in desktop entry

Check if a user-level `.desktop` override exists:

```bash
ls ~/.local/share/applications/Goose.desktop 2>/dev/null
```

If it exists, add `GOOSE_SHELL=/home/<user>/.local/bin/goose-shell`
to the `Exec=env ...` line. If not, create one from the system file:

```bash
cp /usr/share/applications/Goose.desktop ~/.local/share/applications/Goose.desktop
```

Then edit the `Exec` line to include `GOOSE_SHELL`.

### Step 4: Set GOOSE_SHELL in environment.d

```bash
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/60-goose-shell.conf << EOF
GOOSE_SHELL=/home/$(whoami)/.local/bin/goose-shell
EOF
```

### Step 5: Apply and verify

```bash
# Reload systemd user environment
systemctl --user daemon-reload

# Update desktop database
update-desktop-database ~/.local/share/applications/ 2>/dev/null

# Restart Goose Desktop, then test:
# In Goose Desktop, run: which gh && gh --version
```

## Verification Checklist

- [ ] `GOOSE_SHELL` is set in the Goose process environment
      (`cat /proc/$(pgrep -f '/usr/lib/Goose/Goose' | head -1)/environ | tr '\0' '\n' | grep GOOSE_SHELL`)
- [ ] Shell commands see the full PATH (devbox/nix, cargo, crc/oc, sdkman)
- [ ] `which gh` finds gh at the devbox nix path
- [ ] `which oc` finds oc
- [ ] `devbox global shellenv` runs without errors
- [ ] Environment variables are set (`CLOUD_ML_REGION`, `SDKMAN_DIR`, etc.)
- [ ] Interactive bash sessions still work normally (completions, prompt)
- [ ] No `eval` errors in shell output

## Affected Files

| File | Purpose |
|------|--------|
| `~/.local/bin/goose-shell` | Wrapper: sources ~/.bashrc for non-interactive shells |
| `~/.local/share/applications/Goose.desktop` | Desktop entry: passes GOOSE_SHELL to Goose process |
| `~/.config/environment.d/60-goose-shell.conf` | Systemd user env: sets GOOSE_SHELL as fallback |
| `~/.bashrc` | Restructured: env setup for all shells, interactive guard |

## Platform Notes

- Tested on **Fedora** with **GNOME/Wayland** desktop
- Goose Desktop is an **Electron** app installed at `/usr/lib/Goose/`
- The Goose `shell` tool honors the `GOOSE_SHELL` environment variable
  to select the shell binary (defaults to `/bin/bash`)
- The `environment.d` mechanism works for apps launched via systemd
  user session (GNOME on Fedora). Other desktop environments may need
  different approaches.
- If nix is not installed, skip the `unset __ETC_PROFILE_NIX_SOURCED`
  line in the wrapper

## Changelog

| Date | Change |
|------|--------|
| 2026-07-08 22:24 | v1.0 — Initial skill capturing the full Goose Desktop environment fix |
