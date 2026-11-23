# crc-post-setup-config Changelog


| Updated | Change |
|---------|--------|
| 2026-11-23 14:52 | v1.4.0 — crc-post-setup-config: setup.sh rewritten to orchestrate the documented helpers (was: KubeletConfig 512Mi + wrong silences, no retention); Part 4 removes the security-notice console banner; --check prints DRY_RUN_RESULT; crc-post-setup-config: apply-system-reserved.sh restart hint uses crcstop && crcstart; crc-post-setup-config: Part 4 console banner removal; Quick Run section (setup.sh --check gate); banner verification item; crc-post-setup-config: Part 2 waits for MachineConfigPool rollout (MCD reboots the node itself on OCP 5.0); no manual restart; crc-post-setup-config: apply-system-reserved.sh says the MCD reboots the node itself; do not crcstop until MCP updated; crc-post-setup-config: Part 2 doc — automatic MCD reboot, no manual restart, never crcstop during it; verification via MCP + allocatable |
| 2026-11-23 13:53 | v1.3.1 — crc-post-setup-config: restart hint uses crcstop && crcstart (wrapper rule) |
| 2026-11-08 23:00 | v1.3.0 — Create setup script extracting inline oc commands; Bump version to 1.3.0 |
| 2026-11-08 21:20 | v1.1.0 — Add anti-fabrication rules and CNL compliance for Observable qualification |
| 2026-11-05 19:30 | v1.0.0 — Add model-tier to frontmatter |
| 2026-06-19 19:41 | v1.0 — Initial skill |
