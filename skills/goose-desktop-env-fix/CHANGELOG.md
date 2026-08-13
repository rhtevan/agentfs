# goose-desktop-env-fix Changelog


| Date | Change |
|------|--------|
| 2026-07-15 | v1.2 — Changed devbox shellenv guard from exported `__DEVBOX_SHELLENV_LOADED` to shell-local `__devbox_shellenv_done`. Fixes `refresh-global` alias missing inside `devbox shell` sessions while preserving fork-bomb protection. Added Guard Variables summary table. Added `refresh-global` to verification checklist. |
| 2026-07-08 | v1.1 — Added devbox fork bomb root cause analysis, trigger chain, symptoms, emergency cleanup, and `__DEVBOX_SHELLENV_LOADED` recursion guard as critical fix. Updated `.bashrc` example, verification checklist, and tags. |
| 2026-07-08 | v1.0 — Initial skill capturing the full Goose Desktop environment fix |
