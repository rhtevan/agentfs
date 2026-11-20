# goose-desktop-env-fix Changelog

| Updated | Change |
|---------|--------|
| 2026-11-20 18:47 | v1.8.0 — rm guard for goose shell commands (after the 2026-11-18 home-wipe incident). New `scripts/rm-guard.sh`, installed as `~/.local/share/goose-guard/bin/rm`: refuses rm when a target, after shell expansion, is `/`, `$HOME`, `~/app`, `~/app/playground`, `~/.config`, `~/.local`, `~/.local/share` or anything directly inside them; blocks are logged to `~/.local/state/goose-guard/blocked.log`. `setup.sh`: wrapper template puts the guard first in PATH and upgrades an existing wrapper (backup), step 2b installs the guard, step 5b adds `export GOOSE_SHELL=…` to `~/.bashrc` above the interactive guard (backup + `bash -n`). SKILL.md: rm Guard section. |
| 2026-11-09 18:50 | v1.7.0 — Migrate --check to --dry-run contract with DRY_RUN_RESULT signals |
| 2026-11-09 10:47 | v1.6.0 — New script: install goose-shell wrapper, environment.d config, desktop entry fix with --check mode and trace instrumentation |
| 2026-11-08 22:50 | v1.5.0 — Add Rules + trace |
| 2026-11-05 19:31 | v1.4.0 — Add model-tier to frontmatter |
| 2026-10-12 14:41 | v1.4.0 — Added GPU/Wayland fix: `--ozone-platform=x11` in `.desktop` Exec line. Documented Chromium GPU process crash (error_code=1002) on Wayland as Root Cause 1. Updated desktop file template, verification checklist. |
| 2026-08-24 14:24 | v1.3.0 — Added Gotchas section documenting hermit node wrapper PATH interference and per-skill workaround pattern for Node.js-based skills |


| Date | Change |
|------|--------|
| 2026-07-15 | v1.2 — Changed devbox shellenv guard from exported `__DEVBOX_SHELLENV_LOADED` to shell-local `__devbox_shellenv_done`. Fixes `refresh-global` alias missing inside `devbox shell` sessions while preserving fork-bomb protection. Added Guard Variables summary table. Added `refresh-global` to verification checklist. |
| 2026-07-08 | v1.1 — Added devbox fork bomb root cause analysis, trigger chain, symptoms, emergency cleanup, and `__DEVBOX_SHELLENV_LOADED` recursion guard as critical fix. Updated `.bashrc` example, verification checklist, and tags. |
| 2026-07-08 | v1.0 — Initial skill capturing the full Goose Desktop environment fix |
