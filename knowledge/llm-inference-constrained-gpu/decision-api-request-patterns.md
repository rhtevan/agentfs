---
title: "Decision API Request Patterns: NextToken vs D3 System One"
created: 2026-10-22
tags: [decision-api, nexttokenstrategy, d3, systemone, vllm, api-patterns]
evidence: "Validated live against qw14b-40k (Qwen3-14B-FP8) on port 9000 via Skupper VAN, 2026-10-22. D3 samples from deployment session evidence (port 9001 not active — solo profile uses all 4 GPUs)."
---

# Decision API Request Patterns

Two decision API implementations serve different deployment scenarios.
Both are served by vLLM but use different endpoints, field names, and
question schemas. This concept captures validated request/response
patterns for each.

## API Format Differences

| Field | NextToken (`/v1/decisions`) | D3 System One (`/v1/systemone`) |
|-------|:---:|:---:|
| **Endpoint** | `/v1/decisions` | `/v1/systemone` (or `/v1/decisions`) |
| **Input field** | `"input": "..."` | `"state": "..."` |
| **Questions** | Array of objects | Dict keyed by question name |
| **Yes/No type** | `"type": "predicate"` | `"type": "noul"` |
| **Question text** | `"instructions": "..."` | `"instructions": "..."` |
| **Choice values** | `"choices": [{"value": "..."}]` | `"criteria": {"key": "description"}` |
| **Score levels** | `"levels": [{"label": "..."}]` | `"criteria": ["low", "med", "high"]` |
| **Score support** | ✅ Supported (validated) | ✅ Supported (native) |
| **Output tokens** | 1 per question (logit reading) | 0 output tokens (structured) |
| **Coexists with chat** | ✅ Same port as `/v1/chat/completions` | ❌ Dedicated port |

## NextToken API (vLLM `/v1/decisions`)

NextToken reads logit probabilities from the model's next-token
distribution. Zero output tokens are generated — the answer comes
from token probability analysis. This coexists with chat/completions
on the same port (9000).

### Predicate (Yes/No)

**Request:**

```bash
curl -s http://localhost:9000/v1/decisions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-14B-FP8",
    "input": "The sky is blue during a clear day.",
    "questions": [
      {
        "name": "is_blue",
        "type": "predicate",
        "instructions": "Is the sky blue?"
      }
    ]
  }'
```

**Response (114ms):**

```json
{
  "model": "Qwen/Qwen3-14B-FP8",
  "answers": [
    {
      "type": "predicate",
      "name": "is_blue",
      "probability": 0.9999999998973812
    }
  ],
  "usage": {
    "input_tokens": 45,
    "output_tokens": 1,
    "total_tokens": 46
  }
}
```

**Interpretation:** `probability` near 1.0 = yes, near 0.0 = no.
Value 0.9999999999 = virtually certain "yes".

### Choice (Multiple Options)

**Request:**

```bash
curl -s http://localhost:9000/v1/decisions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-14B-FP8",
    "input": "A customer wants to return a product purchased 45 days ago. Our return policy allows returns within 30 days.",
    "questions": [
      {
        "name": "action",
        "type": "choice",
        "instructions": "What action should the agent take?",
        "choices": [
          {"value": "approve_return"},
          {"value": "deny_return"},
          {"value": "escalate_to_manager"}
        ]
      }
    ]
  }'
```

**Response (134ms):**

```json
{
  "model": "Qwen/Qwen3-14B-FP8",
  "answers": [
    {
      "type": "choice",
      "name": "action",
      "choice": "deny_return",
      "probabilities": [
        {"value": "approve_return", "probability": 3.098e-12},
        {"value": "deny_return", "probability": 0.9999999999964817},
        {"value": "escalate_to_manager", "probability": 4.194e-13}
      ],
      "confidence": 1.0
    }
  ],
  "usage": {
    "input_tokens": 75,
    "output_tokens": 1,
    "total_tokens": 76
  }
}
```

**Interpretation:** `choice` is the winning option. `probabilities`
shows the full distribution. `confidence` is the max probability.

### Score (Ordinal Scale)

**Request:**

```bash
curl -s http://localhost:9000/v1/decisions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-14B-FP8",
    "input": "The server has 95% CPU utilization, 87% memory usage, and 3 failed health checks in the last hour.",
    "questions": [
      {
        "name": "severity",
        "type": "score",
        "instructions": "Rate the severity of this infrastructure alert.",
        "levels": [
          {"label": "low"},
          {"label": "medium"},
          {"label": "high"},
          {"label": "critical"}
        ]
      }
    ]
  }'
```

**Response (121ms):**

```json
{
  "model": "Qwen/Qwen3-14B-FP8",
  "answers": [
    {
      "type": "score",
      "name": "severity",
      "score": 1.9968334610680771,
      "probabilities": [
        {"value": 0, "label": "low", "probability": 1.778e-11},
        {"value": 1, "label": "medium", "probability": 0.003172663574972051},
        {"value": 2, "label": "high", "probability": 0.9968212117286515},
        {"value": 3, "label": "critical", "probability": 0.000006124678600688751}
      ],
      "confidence": 0.9968211695877528
    }
  ],
  "usage": {
    "input_tokens": 75,
    "output_tokens": 1,
    "total_tokens": 76
  }
}
```

**Interpretation:** `score` is the weighted average (0-indexed).
`probabilities` shows the distribution across levels. Here, 99.7%
probability on "high" → score ~2.0 on a 0-3 scale.

### Multi-Question Batch

**Request:**

```bash
curl -s http://localhost:9000/v1/decisions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-14B-FP8",
    "input": "A web application deployment failed on 2 of 5 nodes. Error logs show disk space exhaustion. Current disk usage is 98%. The application serves 10,000 daily users.",
    "questions": [
      {
        "name": "is_outage",
        "type": "predicate",
        "instructions": "Is there a service outage?"
      },
      {
        "name": "root_cause",
        "type": "choice",
        "instructions": "What is the most likely root cause?",
        "choices": [
          {"value": "disk_full"},
          {"value": "network_failure"},
          {"value": "code_bug"},
          {"value": "resource_limit"}
        ]
      },
      {
        "name": "urgency",
        "type": "score",
        "instructions": "Rate the urgency of remediation.",
        "levels": [
          {"label": "low"},
          {"label": "medium"},
          {"label": "high"},
          {"label": "critical"}
        ]
      }
    ]
  }'
```

**Response (202ms):**

```json
{
  "model": "Qwen/Qwen3-14B-FP8",
  "answers": [
    {
      "type": "predicate",
      "name": "is_outage",
      "probability": 0.022977372418942873
    },
    {
      "type": "choice",
      "name": "root_cause",
      "choice": "disk_full",
      "probabilities": [
        {"value": "disk_full", "probability": 0.9999999468400976},
        {"value": "network_failure", "probability": 1.659e-12},
        {"value": "code_bug", "probability": 4.194e-13},
        {"value": "resource_limit", "probability": 5.316e-8}
      ],
      "confidence": 0.9999985694905719
    },
    {
      "type": "score",
      "name": "urgency",
      "score": 2.952571580706344,
      "probabilities": [
        {"value": 0, "label": "low", "probability": 1.499e-11},
        {"value": 1, "label": "medium", "probability": 0.0000013059389652556911},
        {"value": 2, "label": "high", "probability": 0.04742580737075334},
        {"value": 3, "label": "critical", "probability": 0.9525728866752907}
      ],
      "confidence": 0.9525724194983776
    }
  ],
  "usage": {
    "input_tokens": 261,
    "output_tokens": 3,
    "total_tokens": 264
  }
}
```

**Analysis of batch quality:**
- **is_outage**: 2.3% probability — correct. Partial failure (2/5 nodes)
  is degraded service, not an outage.
- **root_cause**: disk_full at 99.99% — correct. Disk exhaustion is
  explicitly stated.
- **urgency**: critical at 95.3%, score 2.95/3 — appropriate. 10K
  daily users + disk at 98% + failed health checks = high urgency.

### Latency Profile

| Question Type | Avg Latency | Output Tokens |
|:---:|:---:|:---:|
| Predicate (single) | ~115ms | 1 |
| Choice (single) | ~135ms | 1 |
| Score (single) | ~120ms | 1 |
| Batch (3 questions) | ~200ms | 3 |

Latency scales linearly with question count. Each question requires
exactly 1 output token (the logit being read). Sub-200ms for single
questions makes NextToken suitable for real-time agentic decisions.

## D3 System One API (`/v1/systemone`)

D3 models use the System One endpoint with a different schema. The key
differences are: `state` instead of `input`, dict-based questions instead
of array, `noul` instead of `predicate`, and `criteria` instead of
`choices`/`levels`.

> **Note:** These samples are from deployment session evidence (2026-10-15).
> Port 9001 was not live at validation time — the solo qw14b-40k profile
> uses all 4 GPUs. D3 requests require the composite profile `qw14b+d3`
> or standalone `d3-27b-8k` to be deployed.

### Predicate (Noul)

**Request:**

```bash
curl -s http://localhost:9001/v1/systemone \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vllm-sr/d3",
    "state": "The sky is blue during a clear day.",
    "questions": {
      "is_blue": {
        "type": "noul",
        "instructions": "Is the sky blue?"
      }
    }
  }'
```

**Response (~250ms):**

```json
{
  "model": "vllm-sr/d3",
  "answers": {
    "is_blue": {
      "type": "noul",
      "probability": 1.0
    }
  },
  "usage": {
    "input_tokens": 42,
    "output_tokens": 0,
    "total_tokens": 42
  }
}
```

### Choice (Criteria Dict)

**Request:**

```bash
curl -s http://localhost:9001/v1/systemone \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vllm-sr/d3",
    "state": "A customer wants to return a product purchased 45 days ago. Our return policy allows returns within 30 days.",
    "questions": {
      "action": {
        "type": "choice",
        "instructions": "What action should the agent take?",
        "criteria": {
          "approve_return": "Accept the return request",
          "deny_return": "Reject the return request",
          "escalate_to_manager": "Forward to a manager for review"
        }
      }
    }
  }'
```

**Response (~300ms):**

```json
{
  "model": "vllm-sr/d3",
  "answers": {
    "action": {
      "type": "choice",
      "choice": "deny_return",
      "confidence": 0.97
    }
  },
  "usage": {
    "input_tokens": 68,
    "output_tokens": 0,
    "total_tokens": 68
  }
}
```

### Score (Criteria Array)

**Request:**

```bash
curl -s http://localhost:9001/v1/systemone \
  -H "Content-Type: application/json" \
  -d '{
    "model": "vllm-sr/d3",
    "state": "The server has 95% CPU utilization, 87% memory usage, and 3 failed health checks in the last hour.",
    "questions": {
      "severity": {
        "type": "score",
        "instructions": "Rate the severity of this infrastructure alert.",
        "criteria": ["low", "medium", "high", "critical"]
      }
    }
  }'
```

**Response (~280ms):**

```json
{
  "model": "vllm-sr/d3",
  "answers": {
    "severity": {
      "type": "score",
      "score": 2.89,
      "label": "critical",
      "confidence": 0.91
    }
  },
  "usage": {
    "input_tokens": 58,
    "output_tokens": 0,
    "total_tokens": 58
  }
}
```

## Format Pitfalls

Common mistakes when switching between NextToken and D3 APIs:

1. **`query` vs `instructions`:** The question text field is `instructions`
   in both APIs. Using `query` returns a 400 validation error.

2. **`input` vs `state`:** NextToken uses `input`, D3 uses `state`.
   Wrong field name silently passes but gives nonsensical answers.

3. **Questions array vs dict:** NextToken takes an array with `name` field
   on each question. D3 takes a dict keyed by question name. Mixing
   formats returns a validation error.

4. **`predicate` vs `noul`:** D3 calls yes/no questions "noul" (not "predicate").
   Using `predicate` on `/v1/systemone` returns a validation error.

5. **Score criteria format:** NextToken uses `"levels": [{"label": "..."}]`.
   D3 uses `"criteria": ["low", "med", "high"]` (plain string array).
   Using `levels` on D3 or `criteria` on NextToken returns validation errors.

6. **Choice criteria format:** NextToken uses `"choices": [{"value": "..."}]`.
   D3 uses `"criteria": {"key": "description"}` (dict with descriptions).
   NextToken choices have no description field.

## When to Use Which

| Use Case | Recommended | Why |
|----------|:-----------:|-----|
| Real-time agentic routing | NextToken | ~115-200ms, coexists on gen-ai port |
| High-stakes decisions | D3-27B | SOTA accuracy (66.26 Decision Index), better calibration |
| Batch classification | NextToken | Linear scaling, 3 tokens per 3 questions |
| Nuanced risk assessment | D3-27B | Hedges appropriately on ambiguous inputs |
| Trick/adversarial inputs | D3-27B or NextToken (14B+) | Both 19/19; D3-Flash (9B) fails on tricks |
| Resource-constrained | NextToken | Zero extra GPUs, same port as chat |
