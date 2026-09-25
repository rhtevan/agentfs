# Design Principles

Principles discovered or reinforced during the KGM skill dispatch work.

## Lower the Cognitive Bar for Model Callers

When a model fails to follow prose instructions reliably:
- Convert the prose to a single wrapper script with zero or minimal args
- Wrapper auto-detects context (provider, model, paths) from config/env
- Avoid similar script names within the same skill directory

Captured in `skill-gen` SKILL.md as a corollary to the Code-First principle.

## Prose → Script When Model Can't Follow

The existing rule "loose steps → instructions, fragile steps → code"
extends to: "steps the model fails to follow → code." Evidence:
post-write version bumps were missed repeatedly until `post-write.sh`
was changed to fail (exit 1) instead of warn when `--version` is missing.

## Ad-Hoc Fix → Durable Fix

Every ad-hoc fix must trace to root cause and produce a persistent
fix (script, guardrail, or config change). The KGM symlink started
as a hack (copy data to the npm cache file) and was formalized into
`setup-kgm.sh` creating the symlink automatically.

## Ledger Integrity

Ledger files (log.md, CHANGELOG.md, MEMORY.md, score sheets) are
always latest-entry-first. Flag ordering violations, duplicate
headers, or structural anomalies immediately. The `agentfs-setup`
CHANGELOG had two separate table headers — undetected until a human
caught it. Added to SOUL.md as an agent identity trait.

## Don't Explain Why in Rules

Rules table cells should contain HOW instructions, not WHY
explanations. Trailing sentences like "This combats multi-turn
discipline decay..." waste tokens and add no actionable value for
the model. WHY belongs in design specs and knowledge bundles.

## Test What You Ship

AGENTS.md had no tests validating whether its instructions actually
produced correct model behavior. The `template-check.sh` and
`template-behavioral.sh` infrastructure was built to close this gap.
Score tracking across versions provides immediate visibility into
whether a change helped or regressed.
