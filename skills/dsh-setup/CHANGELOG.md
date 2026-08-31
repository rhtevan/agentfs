# dsh-setup Changelog

| Updated | Change |
|---------|--------|
| 2026-08-31 10:03 | v1.3.1 — Added version check to status.sh — compares installed vs registry latest, recommends update when behind |
| 2026-08-31 09:59 | v1.3.0 — Replaced ambiguous 'dsh launcher' and 'dsh desktop' signals with 'dsh status'; added status.sh script showing backend state and desktop path |
| 2026-08-24 19:26 | v1.2.1 — Separate Chrome profile (`--user-data-dir`) for security isolation + maximized window + trackable process; replaced TCP connection monitoring with simple `wait $CHROME_PID`; fixed WMClass to `chrome-127.0.0.1__-Default` for GNOME icon matching on Wayland |
| 2026-08-24 17:57 | v1.2.0 — Replaced PID-based idle detection with systemd user service + TCP connection monitoring; backend lifecycle managed by `dsh.service`; launcher auto-stops service on browser disconnect (15s grace); fixed ss header line counting as connection; teardown handles service cleanup; multi-size icon install; dummy API key env var for LiteLLM |
| 2026-08-24 14:25 | v1.1.0 — Fixed hermit PATH interference in install/update/verify scripts; fixed bash arithmetic exit under set -e; fixed DSH binary invocation (shell script not node module); fixed markdown rendering; added official DSH whale icon |
| 2026-08-24 13:47 | v1.0.0 — Initial skill: pnpm-based DSH install, Chrome app-mode launcher, .desktop integration, update, teardown, verify |
