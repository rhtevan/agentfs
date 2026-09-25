# Testing Infrastructure

## Scripts (all under `~/.agents/skills/agentfs-eval/scripts/`)

| Script | Type | Purpose |
|--------|------|---------|
| `template-check.sh` | Deterministic | 10 structural assertions on AGENTS.md (token budget, section order, rule completeness, etc.) |
| `template-behavioral.sh` | LLM-dependent | Replays fixed inputs via `goose run`, asserts first tool call matches expected |
| `template-eval.sh` | Wrapper | Zero-arg: auto-detects provider/model from `AGENT_SESSION_ID`, runs both checks, records scores |
| `merge-score-entry.sh` | Deterministic | Insert/update score rows in `template-scores.md` (dedup, reverse chronological) |

## Provider/Model Auto-Detection

`template-eval.sh` resolves the current session's provider/model via:

```
AGENT_SESSION_ID env var (set by goose)
  → goose session export --name $AGENT_SESSION_ID --format json
    → provider_name + model_config.model_name
```

Fallback chain: CLI args → session metadata → config.yaml.

## Behavioral Test Cases

| ID | Input | Expected | Tests |
|----|-------|----------|-------|
| B1 | "skupper status" | `load_skill` | Skill discovery from free-text |
| B2 | "hey git" | `load_skill` | Rule 7 explicit signal |
| B3 | "check crc status" | `load_skill` | Skill discovery without exact name match |

## Score Sheet

Single table at `~/.agents/skills/agentfs-eval/references/template-scores.md`.
Reverse chronological. One row per version + model combination.

## Test Session Cleanup

`template-behavioral.sh` cleans up spawned test sessions via direct
SQLite deletion — avoids the interactive confirmation prompt of
`goose session remove`.

## Key Lessons

- **Double-run bug**: First version ran each check twice (once for
  display, once to capture output). Fixed by capturing output from
  single run.
- **Wrong model detection**: `config.yaml` `active_provider` is
  global, not per-session. Fixed by reading `AGENT_SESSION_ID`
  session metadata.
- **Script name confusion**: `agentfs-behavior.sh` vs
  `agents-md-behavioral.sh` — Granite called the wrong one 8 times.
  Fixed by renaming to `template-check.sh` / `template-behavioral.sh`.
