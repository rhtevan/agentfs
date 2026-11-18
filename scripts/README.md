# ~/.agents/scripts/

AGENTS-specific scripts referenced directly from AGENTS.md rules.

Skill scripts stay in their respective skill directories
(e.g., `~/.agents/skills/agentfs-setup/scripts/`). This directory
is only for scripts that belong to the AGENTS.md root workflow
itself and do not warrant a dedicated skill.

AGENTS.md rule scripts (`checkpoint.sh`, `post-write.sh`) remain in
`~/.agents/skills/agentfs-setup/scripts/`.

## SDM (Structured Decision Model) pipeline

| Script | Purpose |
|--------|---------|
| `sdm-call.sh` | Low-level `POST /v1/systemone` client (`SDM_ENDPOINT`, `SDM_MODEL`, `SDM_TIMEOUT`) |
| `sdm-evaluate.sh` | Score a skill/trace/AGENTS.md against a QOO schema via the SDM |
| `gather-skill-state.sh` | Pre-compute concise evidence facts for SDM evaluation |
| `score-all.sh` | Batch Quality + Observable + Operable (build) scoring → `scores.yaml` |
| `sdm-validate.sh` | Validate a candidate SDM endpoint for AgentFS usability before switching `SDM_ENDPOINT` (agreement with baseline + ground-truth facts; no scores persisted) |

## Compliance benchmark

| Script | Purpose |
|--------|---------|
| `benchmark.sh` | Runs the AGENTS.md compliance tests against one model (`--queue FILE` for work-queue mode, `--regrade DIR`). Contains tests: sandbox git target, network push blocked, real `~/.agents` index guard |
| `run-parallel.sh` | `smoke\|real [--shards "T4=2,T3=6,T2=4"] [--tiers ...]` — dry-run gate, per-tier work queue across N workers with isolated project/sandbox copies, merge, regrade, record |
| `update-compliance.sh` | Records results into `compliance-profile.yaml` (`--tier Tx`, `--dry-run` gate, `--check`) |
| `rules-hash.sh` | Hashes the AGENTS.md `## Rules` + `## Signal Dispatch` sections |
| `agentfs-contract.sh` | Sourced, not executed. Single source of the KGM names: config key, display `name`, derived tool prefix (goose builds the prefix from `name`) |
| `agentfs-contract-lint.sh` | Fails if the KGM key literal appears in `plugins/`, `scripts/`, `skills/` outside the contract |

Endpoint contract: [`skills/schemas/sdm-endpoint.md`](../skills/schemas/sdm-endpoint.md).
