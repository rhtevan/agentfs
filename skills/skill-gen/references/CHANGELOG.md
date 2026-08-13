# skill-schema Changelog

| Updated | Change |
|---------|--------|
| 2026-08-13 19:21 | v2.1.0 — Externalized changelog: `CHANGELOG.md` is now the canonical location for version history; SKILL.md retains only a reference link; updated Changelog Rules, Anti-Patterns table, and template |
| 2026-08-13 12:25 | v2.0.0 — Breaking: `description` field redefined as signal phrases (Command: `verb+noun(s)`, Query: `noun(s)`); removed `metadata.signals` from schema; added Signal Phrase Rules section with patterns, three quality principles (Concise, No redundant, Complete), completeness guidance, smell test; added Opening Paragraph Requirement; added Progressive Disclosure Model; updated Reference Template and Anti-Patterns |
| 2026-08-08 10:55 | v1.1.0 — Added `writes-files` optional field: flags skills that write/modify files outside `.agents/`, signaling critical file templates that must be followed exactly |
| 2026-08-04 23:46 | v1.0.0 — Initial schema: canonical version location (metadata.version), quoted 3-part semver, changelog as Markdown section, anti-patterns table |
