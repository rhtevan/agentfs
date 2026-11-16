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

Endpoint contract: [`skills/schemas/sdm-endpoint.md`](../skills/schemas/sdm-endpoint.md).
