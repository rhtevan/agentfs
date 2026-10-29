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

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `SDM_ENDPOINT` | `http://localhost:9000` | Base URL |
| `SDM_MODEL` | Auto-detected from `/v1/models` | Model ID |
| `SDM_TIMEOUT` | `10` | Request timeout in seconds |
| `SDM_RETRIES` | `3` | Max retries on 429 |
