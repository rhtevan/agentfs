# agentfs-eval archive

Retired 2026-11-24 (R-a, F22). Kept for history; nothing references them.

| File | Was | Replaced by |
|------|-----|-------------|
| `template-scores.md` | pre-QOO score sheet (Template + Behavioral), last real row 2026-10-02; first row corrupt (2026-10-28 merge bug) | static record `agentfs-setup/artifacts/agents-md/scores.yaml`; runtime record `agentfs-setup/compliance-profile.yaml` |
| `merge-score-entry.sh` | sole writer of `template-scores.md` | — |

`scripts/template-behavioral.sh` (deprecated B1–B3) still names
`references/template-scores.md` in its 10-minute dedup guard; with the
file gone the guard is a no-op. See
`knowledge/agentfs-engineering-evolution/evaluation-methodology.md`.
