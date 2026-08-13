# skupper-linux-two-site Changelog


| Updated | Change |
|---------|--------|
| 2026-08-04 19:09 | v2.1 — Fixed terminology consistency: local=edge, remote=hub/interior. Replaced confusing my-hub/my-edge examples with neutral my-local/my-remote/my-remote-host placeholders to avoid conflating site names with Skupper roles. |
| 2026-08-04 18:25 | v2.0 — Swapped site roles: localhost=edge (outbound only, no firewall needed), remote=interior/hub (accepts inbound links). Updated all scripts and documentation. |
| 2026-07-22 21:34 | v1.3 — Replaced environment-specific examples (ezhang-work, rhtevan-work) with generic placeholders (my-hub, my-edge) |
| 2026-07-22 21:21 | v1.2 — Added Invocation Example section (happy path + missing params) |
| 2026-07-22 21:11 | v1.1 — Added structured parameter definitions with binding-cues, usage hints, confirmation flow, and script argument mapping table |
| 2026-07-22 19:54 | v1.0 — Initial skill from verified two-site Linux/systemd setup procedure |
