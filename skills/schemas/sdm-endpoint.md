# SDM Endpoint Reference

Decision API endpoint specification for AgentFS skill evaluation.

## Endpoint

| Property | Value |
|----------|-------|
| Base URL | `${SDM_ENDPOINT:-http://localhost:9000}` |
| Path | `/v1/decisions` |
| Method | `POST` |
| Content-Type | `application/json` |
| API | NextToken (vLLM logit-reading, zero output tokens) |
| Latency | ~115-200ms per question |
| Availability | Coexists with LLM on same port — always available when model is running |

## Why NextToken over D3 SystemOne

NextToken was chosen over D3 (`/v1/systemone`) because:
- Always available on the LLM port (no extra GPUs or composite profile)
- Faster (~150ms vs ~350ms per question)
- Sufficient accuracy for bounded skill evaluation judgments
- Multi-question batching in one request

D3 SystemOne is preferred for high-stakes production decisions requiring
SOTA accuracy (Decision Index 66.26). Skill evaluation is pass/fail
classification on well-defined dimensions — NextToken is adequate.

## Model Resolution

The model ID must match the deployed model. Resolve dynamically:

```bash
SDM_MODEL=$(curl -s "${SDM_ENDPOINT}/v1/models" | jq -r '.data[0].id')
```

## Question Types

### Predicate (Yes/No)

```json
{
  "name": "dimension_name",
  "type": "predicate",
  "instructions": "Question text?"
}
```

Response: `{"probability": 0.99}` — near 1.0 = yes, near 0.0 = no.
Threshold: ≥0.7 = pass, <0.3 = fail, 0.3-0.7 = uncertain.

### Choice (Multiple Options)

```json
{
  "name": "dimension_name",
  "type": "choice",
  "instructions": "Question text?",
  "choices": [
    {"value": "option_a"},
    {"value": "option_b"},
    {"value": "option_c"}
  ]
}
```

Response: `{"choice": "option_a", "confidence": 0.95, "probabilities": [...]}`.

### Score (Ordinal Scale)

```json
{
  "name": "dimension_name",
  "type": "score",
  "instructions": "Rate the quality of X.",
  "levels": [
    {"label": "poor"},
    {"label": "fair"},
    {"label": "good"},
    {"label": "excellent"}
  ]
}
```

Response: `{"score": 2.8, "confidence": 0.92, "probabilities": [...]}`.
Score is 0-indexed weighted average.

## Request Format

```json
{
  "model": "<model-id>",
  "input": "<evidence text>",
  "questions": [
    { "name": "q1", "type": "predicate", "instructions": "..." },
    { "name": "q2", "type": "choice", "instructions": "...", "choices": [...] },
    { "name": "q3", "type": "score", "instructions": "...", "levels": [...] }
  ]
}
```

Multiple questions in one request. Output tokens = 1 per question.
Latency scales linearly with question count.

## Response Format

```json
{
  "model": "<model-id>",
  "answers": [
    { "type": "predicate", "name": "q1", "probability": 0.99 },
    { "type": "choice", "name": "q2", "choice": "option_a", "confidence": 0.95, "probabilities": [...] },
    { "type": "score", "name": "q3", "score": 2.8, "confidence": 0.92, "probabilities": [...] }
  ],
  "usage": {
    "input_tokens": 120,
    "output_tokens": 3,
    "total_tokens": 123
  }
}
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
