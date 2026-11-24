# SDM Endpoint Reference

SystemOne API endpoint specification for AgentFS skill evaluation.

## Endpoint

| Property | Value |
|----------|-------|
| Base URL | `${SDM_ENDPOINT:-http://localhost:9000}` |
| Path | `/v1/systemone` |
| Method | `POST` |
| Content-Type | `application/json` |
| API | SystemOne (vLLM logit-reading, structured decision output) |
| Latency | ~115-200ms per question |
| Availability | Coexists with LLM on same port — always available when model is running |

## Why SystemOne

SystemOne was chosen over NextToken (`/v1/decisions`) because:
- Same port, same model, same latency — no tradeoff
- Richer response: explicit `confidence`, full `probabilities` map
- `diagnostics.label_mass` — detects when evidence quality is too low
- `diagnostics.argmax_is_label` — detects unreliable classifications
- Native `probabilities.yes`/`probabilities.no` — no polarity inversion hacks needed

Both APIs are available on the same vLLM port. The `/v1/decisions` API
is deprecated for AgentFS use but remains available for backward
compatibility.

## Model Resolution

The model ID must match the deployed model. Resolve dynamically:

```bash
SDM_MODEL=$(curl -s "${SDM_ENDPOINT}/v1/models" | jq -r '.data[0].id')
```

## Question Types

### Noul (Yes/No)

```json
{
  "q1": {
    "type": "noul",
    "instructions": "Question text?"
  }
}
```

Response: `{"noul": 0.99, "probabilities": {"yes": 0.99, "no": 0.01}, "confidence": 1.0}`.
Threshold: `probabilities.yes` ≥0.7 = pass, <0.3 = fail, 0.3-0.7 = uncertain.

### Choice (Multiple Options)

```json
{
  "q2": {
    "type": "choice",
    "instructions": "Question text?",
    "criteria": {"option_a": null, "option_b": null, "option_c": null}
  }
}
```

Response: `{"choice": "option_a", "probabilities": {"option_a": 0.99, ...}, "confidence": 1.0}`.

### Score (Ordinal Scale)

```json
{
  "q3": {
    "type": "score",
    "instructions": "Rate the quality of X.",
    "criteria": ["poor", "fair", "good", "excellent"]
  }
}
```

Response: `{"score": 2.8, "legend": {"0":"poor",...}, "probabilities": {"0": 0.01,...}, "confidence": 0.92}`.
Score is 0-indexed weighted average.

## Request Format

```json
{
  "model": "<model-id>",
  "state": "<evidence text>",
  "questions": {
    "q1": { "type": "noul", "instructions": "..." },
    "q2": { "type": "choice", "instructions": "...", "criteria": {"a": null} },
    "q3": { "type": "score", "instructions": "...", "criteria": ["low","high"] }
  }
}
```

Multiple questions in one request. Output tokens = 1 per question.
Latency scales linearly with question count.

## Response Format

```json
{
  "model": "<model-id>",
  "answers": {
    "q1": { "type": "noul", "noul": 0.99, "probabilities": {"yes": 0.99, "no": 0.01}, "confidence": 1.0 },
    "q2": { "type": "choice", "choice": "a", "probabilities": {"a": 0.99}, "confidence": 1.0 },
    "q3": { "type": "score", "score": 2.8, "legend": {"0":"low","1":"high"}, "probabilities": {"0": 0.01, "1": 0.99}, "confidence": 0.99 }
  },
  "usage": {
    "input_tokens": 120,
    "output_tokens": 3,
    "total_tokens": 123
  },
  "diagnostics": {
    "q1": { "label_mass": 1.0, "argmax_is_label": true },
    "q2": { "label_mass": 1.0, "argmax_is_label": true },
    "q3": { "label_mass": 0.99, "argmax_is_label": true }
  }
}
```

### Diagnostics

| Field | Meaning | Action |
|-------|---------|--------|
| `label_mass` | How much probability lands on valid answer tokens (0-1) | If < 0.8, evidence may be noisy |
| `argmax_is_label` | Whether the model's top token is a valid answer | If `false`, result is unreliable |

### Response Shape Variants

Not every SystemOne server returns the full shape above. `sdm-evaluate.sh`
handles both:

| Server | `noul` answer | `confidence` (noul) | `diagnostics` |
|--------|---------------|:---:|:---:|
| vLLM (generic model, logit reading) | `noul` + `probabilities.yes/no` | ✅ | ✅ |
| llama.cpp `llama-server` (native decision GGUF: vllm-d3, clef, lfm2-d1, laya, …) | `noul` only | ❌ (derived: `max(noul, 1-noul)`) | ❌ (reliability checks skipped, warning logged) |

Negative-polarity boolean dimensions read `probabilities.no`, falling back
to `1 - noul`. Before this fallback, every negative-polarity dimension
(all 17 readme-alignment dimensions) failed against noul-only servers.

## Validating a New SDM Endpoint

Before pointing `SDM_ENDPOINT` at a different model or provider, run:

```bash
~/.agents/scripts/sdm-validate.sh --candidate <url> [--baseline http://localhost:9000] [--sample N]
```

It runs the `score-all.sh` evaluations against both endpoints without
persisting scores, and gates on ≥90% pass/fail agreement with the baseline
plus ground-truth accuracy on facts stated verbatim in the evidence.

Reference result (2026-11-16): vllm-sr d3-mini 4B on llama.cpp (RTX A500,
4 GB) scored 19/20 on generic decisions but only **69.7%** agreement and
**9/61** ground truth on AgentFS evidence → FAIL. Generic decision benchmarks
do not predict AgentFS usability.
```

## Error Handling

| HTTP Code | Meaning | Action |
|:---------:|---------|--------|
| 200 | Success | Parse response |
| 400 | Bad request (wrong field names, invalid type) | Log error, exit 1 |
| 404 | Endpoint not found | SDM not running, exit 2 |
| 422 | Validation error (wrong question format) | Log error, exit 1 |
| 429 | Rate limit | Retry after 1s, max 3 retries |
| 500 | Model error | Log error, exit 1 |
| 000 | Connection refused | SDM not running, exit 2 |

## SDM Unavailable — T4 Fallback (report only)

Decided 2026-11-23. When `sdm-call.sh` exits 2 (endpoint unreachable):

| Caller | Output | Exit |
|--------|--------|:----:|
| `sdm-evaluate.sh` | `band: SDM_UNAVAILABLE`; each dimension carries `question`, `metric`, `target`, `polarity`; top-level `fallback` block | 0 |
| `agentfs-readme-audit/scripts/evaluate-alignment.sh` | `band: SDM_UNAVAILABLE`, `evidence_file`, in-scope `dimensions` with `question`; `fallback` block | 2 |

`fallback` = `{mode: "t4-in-session", persist: false, instruction}`.

The calling skill then:

1. Answers each dimension question as a classifier against the same
   evidence. The fallback model is the current session model (the
   SDM-using skills agentfs-eval, skill-eval and skill-gen are
   `model-tier: T4`; agentfs-setup and agentfs-readme-audit are T3 —
   name the model in the report).
2. Reports the results labelled `T4-fallback (<model>, not persisted)`.
3. Does NOT write fallback answers to `scores.yaml`, `observations/`
   or any history. Existing SDM scores stay unchanged; a record already
   at `SDM_UNAVAILABLE` stays so until SDM returns.

Recovery is automatic: every run probes SDM, so the next run after SDM
is reachable uses SDM and persists scores normally. Batch scorers
(`score-all.sh`, `evaluate-pending.sh`) have no fallback — their only
output is persisted scores. `sdm-validate.sh` has no fallback — it
validates the SDM itself.

Limits: no logits, so the fallback has no calibrated `confidence`,
`label_mass` or `argmax_is_label`; in-session answers are not an
independent grader (F17).

## Exception — Base-Skill Static Record: Calibrated T4 Scorer (F30)

Decided 2026-11-24 (option C). Applies ONLY to the base skill's static
record (`agentfs-setup/artifacts/agents-md/scores.yaml`, "upgrade
agentfs"). Every other caller keeps the report-only fallback above.

| Item | Contract |
|------|----------|
| Scorer | `scripts/t4-score-call.sh`, a drop-in for `sdm-call.sh` (same interface and JSON). Model: a different family from the prose author (default `gemini-3.1-pro-preview` on Vertex). Not the session model. |
| Scoring | `scripts/t4-static-score.sh`: `sdm-evaluate.sh` with `SDM_CALL=t4-score-call.sh`, 3 runs, median aggregate, per-dimension `agreement` (no logits → `confidence: null`). Same score map, bands and deterministic overrides as SDM. Never writes. |
| Gate | Before persisting: `--calibrate <SDM score>` on the template version and schema the SDM score was produced from. Persist only on `T4_CALIBRATION=PASS` (median within ±3). |
| Record | `quality.scorer` / `operable.build.scorer` = `t4-fallback:<model>`; `quality.calibration` holds reference, T4 median, delta, tolerance, runs, result; one `history` entry with `scorer`. |
| Status | `static-sheet-status.sh` prints the scorer; `STATIC_SHEET=CURRENT` stays the signal. A T4 score without a passing calibration is `INVALID`. |
| Recovery | When SDM is reachable again, "upgrade agentfs" re-scores with SDM and removes the `scorer`/`calibration` keys. |

Limits: the calibration checks the aggregate, not each dimension (at
calibration T4 and SDM agreed on 4/6 dimensions); the original SDM
evidence was not kept, so calibration evidence is re-extracted.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SDM_ENDPOINT` | `http://localhost:9000` | Base URL |
| `SDM_MODEL` | Auto-detected from `/v1/models` | Model ID |
| `SDM_TIMEOUT` | `10` | Request timeout in seconds |
| `SDM_RETRIES` | `3` | Max retries on 429 |
