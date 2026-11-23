# crc-cmd Changelog


| Updated | Change |
|---------|--------|
| 2026-11-23 15:17 | v1.3.0 — crc-cmd: crcstop repeats the shutdown request every 60s (a request during a guest/MCD reboot is lost); crcstart removes a stale docker.sock left by a force-stop; lessons from CRC 2.65/OCP 5.0; crc-cmd: install.sh updates installed wrappers that differ from SKILL.md (dry-run PENDING when outdated); crc-cmd: crcstop re-sends only until an SSH poweroff succeeds; stale docker.sock happens after every stop (not only force-stop); measured round trip 150s stop / 3m13s start |
| 2026-11-09 18:54 | v1.2.0 — Migrate --check to --dry-run with DRY_RUN_RESULT/APPLY_RESULT signals; Fix --dry-run arg parsing for non-case-style syntax |
| 2026-11-09 11:51 | v1.1.0 — New script: install crcstart/crcstop wrappers from SKILL.md with --check mode and trace; Added Rules, Workflow CNL Step 1, Output Contract |
| 2026-11-05 19:30 | v1.0.0 — Add model-tier to frontmatter |
| 2026-06-19 22:04 | v1.0 — Initial skill |
