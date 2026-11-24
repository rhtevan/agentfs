# Reasoning Effort: Native vs Custom Providers (Gotcha)

**Observed:** goose 1.60.2, 2026-11-23. Model claude-sonnet-5-5 on Vertex AI.

## Gotcha

`GOOSE_THINKING_EFFORT` (config.yaml or env) reaches the model API **only
through native providers**. Custom OpenAI-engine providers silently drop it,
so the model runs at the **server default effort**.

| Route | What goose sends | Effective effort |
|-------|------------------|------------------|
| Native `gcp_vertex_ai` / `anthropic` | `thinking: {type: adaptive, display: summarized}` + `output_config: {effort: <GOOSE_THINKING_EFFORT>}` | as configured |
| Custom provider (`engine: openai`, e.g. custom_redhat → LiteLLM, custom_corp) | no thinking / effort fields (known goose bug); LiteLLM `drop_params: true` would drop them anyway | server default |

Notes:

- `model_config.request_params.thinking_effort` in `llm_request.*.jsonl` shows the
  **configured** value even when the request body omits it. Check `input`, not
  `model_config`.
- `GOOSE_THINKING_EFFORT=none` is mapped to `off`, but the native request still
  carried adaptive thinking with effort `high`. Do not use `none` to disable thinking.
- The env var overrides config.yaml for a single `goose run`.
- The value is global, not per provider.
- Server default ≈ `high`: inferred. The no-effort route behaved like explicit
  `high`. Not confirmed against vendor docs.

## Why It Matters

Effort changes rule adherence, not just quality. AgentFS R2 Pre-Flight, same
model, same Vertex endpoint, t_r2 + t_r2b × 4 runs:

| Effort | Result | Behaviour |
|--------|--------|-----------|
| medium | 0/8 | Treats a 2-file task as trivial. No visible plan. After the hook denial, writes the plan **inside the hidden thinking block** and retries with no visible text. |
| high | 8/8 | Reasons "touches ≥2 files → state a plan". Writes it as reply text. |
| server default (custom route) | 8/8 | Same as high. |

## Rules of Thumb

- **Benchmarks:** pin effort. `benchmark.sh` exports
  `GOOSE_THINKING_EFFORT=${BENCHMARK_THINKING_EFFORT:-high}`. Record the effort for
  each tier representative (`compliance-profile.yaml` → `effort:`).
- **Comparing providers:** a native-vs-custom difference for the same model may be
  an effort difference, not a provider difference. Diff the request `input` first.
- **Prose design:** instructions that must be *visible* (plans, confirmations)
  should say "in your reply text". At lower effort, models move them into thinking,
  which the user does not see.
- **Debugging:** goose keeps only the last 10 `~/.local/state/goose/logs/llm_request.*.jsonl`.
  Copy them right after the run you want to inspect.

## Sources

- AgentFS F24 (`agentfs-engineering-evolution/dry-run-and-compliance-plan.md`)
- Evidence: `~/.local/state/agentfs/benchmarks/probe-T4gcp-*`, `probe-T4redhat-r2-*`
