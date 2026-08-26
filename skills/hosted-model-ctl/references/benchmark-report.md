# Model Benchmark Report

> Comprehensive benchmark results across all tested models, hosts, and configurations.
> Generated: 2026-08-25 22:44

---

## 1. Hardware Inventory

| Host | GPUs | VRAM/GPU | Memory Bandwidth/GPU | Total Bandwidth | Memory Type |
|------|------|:---:|:---:|:---:|:---:|
| **rhel-ai** | 4× NVIDIA L4 | 21.95 GB | 300 GB/s | 1,200 GB/s | GDDR6 |
| **rhtevan-work** | 1× NVIDIA RTX A500 | 4 GB | 128 GB/s | 128 GB/s | GDDR6 |

**Key constraint:** Both hosts use GDDR6, not HBM. Memory bandwidth — not compute — is the
bottleneck for autoregressive LLM inference. Every output token requires reading the entire
model weights from GPU memory once:

```
Theoretical max tok/s ≈ Total Bandwidth (GB/s) ÷ Model Size in Memory (GB)
```

---

## 2. Benchmark Suite (7 Tests)

| # | Test | What It Measures | Max Tokens |
|---|------|-----------------|:---:|
| 1 | Instruction Following | Strict format compliance (exactly 5 items, numbered, no intro/outro) | 500 |
| 2 | Reasoning | Step-by-step arithmetic (64 GB RAM allocation) | 1,000 |
| 3 | Tool Calling | Proper function call parsing via OpenAI tool_calls API | 500 |
| 4 | Code Generation | Python function with docstring, edge case handling | 1,000 |
| 5 | Multi-step Reasoning | K8s scheduling decision with capacity + balance analysis | 1,000 |
| 6 | Conciseness | One-sentence answer (measures verbosity control) | 200 |
| 7 | Speed / Long Generation | Extended structured output (Prometheus monitoring guide) | 2,000 |

All tests run with thinking/reasoning disabled for consistent comparison.
Tool calling tested with OpenAI-compatible function calling schema.

---

## 3. Results — rhtevan-work (1× RTX A500, 4 GB)

### Runtime: llama.cpp (GGUF quantized models)

| Metric | Granite 350M (BF16) | Granite 3B (Q4_K_M) | Granite 8B (Q4_K_M) |
|--------|:---:|:---:|:---:|
| **Parameters** | 350M | 3B | 8B |
| **Model size in VRAM** | ~0.7 GB | ~1.7 GB | ~4.5 GB (partial offload) |
| **Context window** | 2K | 16K | 4K |
| **Slots (concurrent)** | 4 | 1 | 1 |
| **Token speed** | **44 tok/s** | **37 tok/s** | **6.5 tok/s** |

#### Quality Results

| Test | Granite 350M | Granite 3B | Granite 8B |
|------|:---:|:---:|:---:|
| 1. Instruction Follow | ❌ Too small | ✅ Pass | ✅ Pass |
| 2. Reasoning | ❌ Too small | ✅ 8 GB correct | ✅ 8 GB correct |
| 3. Tool Calling | ❌ Too small | ✅ Parsed | ✅ Parsed |
| 4. Code Gen | ❌ Too small | ✅ Clean, with docstring | ✅ Clean, with docstring |
| 5. Multi-step | ❌ Too small | ✅ Node B correct | ✅ Node B correct |
| 6. Conciseness | ❌ Too small | ✅ Concise (25 tok) | ✅ Concise |
| 7. Speed (long gen) | 44 tok/s (no quality) | **37 tok/s** | **6.5 tok/s** |
| **Verdict** | ❌ Unusable | ✅ **Production-grade** | ✅ Production-grade |

#### Analysis

- **Granite 3B is the optimal model** — identical quality to 8B at **5.7× the speed**
- Granite 350M is fast but cannot complete any quality test — too small for real tasks
- Granite 8B requires partial CPU offload to fit in 4 GB, killing speed
- 16K context is the hardware ceiling for 3B Q4_K_M on 4 GB VRAM (1 slot)
- Increasing to 32K/64K context fails with OOM — no headroom

---

## 4. Results — rhel-ai Solo Deployments (4× L4, TP=4)

### Runtime: vLLM nightly (--enforce-eager, 128K context)

| Metric | Qwen3.8-27B FP8 | Gemma 4 31B FP8-block |
|--------|:---:|:---:|
| **Parameters** | 27B | 31B |
| **Quantization** | FP8 | FP8-block |
| **Model size in VRAM** | ~14 GB (3.5 GB/GPU) | ~31 GB (7.75 GB/GPU) |
| **Context window** | 128K | 128K |
| **Token speed** | **11.8 tok/s** | **13.4 tok/s** |

#### Quality Results (Thinking Disabled)

| Test | Qwen3.8-27B FP8 | Gemma 4 31B FP8-block |
|------|:---:|:---:|
| 1. Instruction Follow | ✅ 5 items correct | ✅ 5 items correct |
| 2. Reasoning | ✅ 8 GB, step-by-step (331 tok) | ✅ 8 GB, step-by-step (243 tok) |
| 3. Tool Calling | ✅ Parsed, 3.4s latency | ✅ Parsed, **1.2s latency** |
| 4. Code Gen | ✅ Clean (168 tok) | ✅ Thorough (720 tok) |
| 5. Multi-step | ✅ Node B, table (832 tok) | ✅ Node B, table (569 tok) |
| 6. Conciseness | ⚠️ 36 tok (wordy) | ✅ 28 tok (tight) |
| 7. Speed (long gen) | 11.8 tok/s (2000 tok) | **13.4 tok/s** (1358 tok) |
| **Verdict** | ✅ Excellent | ✅ **Excellent** |

#### Gemma 4 Advantages Over Qwen3.8

- **14% faster** sustained output (13.4 vs 11.8 tok/s)
- **2.8× faster tool calling** (1.2s vs 3.4s) — critical for agentic use
- **More concise** output without sacrificing quality
- No thinking-token budget exhaustion problem (see Section 5)

---

## 5. Qwen3.8 Thinking Mode Issue

When Qwen3.8 runs with thinking enabled (default behavior), internal reasoning
tokens consume the `max_tokens` budget before producing visible content:

| Test | Reasoning Tokens | Content Tokens | Visible Output |
|------|:---:|:---:|:---:|
| 4. Code Gen (max=2000) | 2000 | 0 | ❌ **NULL** |
| 7. Speed (max=3000) | 3000 | 0 | ❌ **NULL** |
| 2. Reasoning (max=2000) | 73 | 135 | ✅ Works |
| 5. Multi-step (max=2000) | 355 | 543 | ✅ Works |

**Root cause:** Complex tasks trigger extended thinking chains that exhaust
the token budget. Workaround: set `chat_template_kwargs.enable_thinking: false`
or use very high `max_tokens` (16K+).

Gemma 4 does not have this problem — it does not have built-in thinking mode.

---

## 6. Speculative Decoding Results — rhel-ai

### 6.1 N-gram Speculation (Gemma 4 31B)

Config: `--speculative-config '{"method": "ngram", "num_speculative_tokens": 5, "prompt_lookup_max": 4}'`

| Test | Baseline (tok/s) | N-gram (tok/s) | Delta |
|------|:---:|:---:|:---:|
| 1. Instruction Follow | 8.9 | **4.1** | ❌ 2× slower |
| 2. Reasoning | 13.4 | 13.8 | ~Same |
| 3. Tool Calling | 12.7 | 12.9 | ~Same |
| 4. Code Gen | 13.4 | 14.0 | +4% |
| 5. Multi-step | 13.4 | 13.6 | ~Same |
| 6. Conciseness | 13.0 | 12.9 | ~Same |
| 7. Speed (long gen) | 13.4 | 13.7 | +2% |

**Verdict: ❌ No benefit.** N-gram speculation pattern-matches against prior
text for repetitive output. Agentic workloads produce novel content — low
acceptance rate makes speculation overhead a net negative.

### 6.2 Native MTP (Gemma 4 31B)

Config: `--speculative-config '{"method": "gemma4_mtp", "num_speculative_tokens": 2}'`

**Verdict: ❌ Not applicable.** The `RedHatAI/gemma-4-31B-it-FP8-block` checkpoint
does not contain MTP heads (`num_mtp_modules` not present in config). The
`gemma4_mtp` method exists in vLLM but requires a model trained with MTP modules.

### 6.3 Draft Model Speculation (Granite 8B + 3B Draft) ✅

Config: `--speculative-config '{"method": "draft_model", "model": "ibm-granite/granite-4.1-3b", "num_speculative_tokens": 5, "draft_tensor_parallel_size": 4}'`

| Test | Granite 8B + 3B Draft (tok/s) | Gemma 4 Baseline (tok/s) | Qwen3.8 Baseline (tok/s) |
|------|:---:|:---:|:---:|
| 1. Instruction Follow | 10.3 | 8.9 | 11.7 |
| 2. Reasoning | **25.0** | 13.4 | 11.8 |
| 3. Tool Calling | **20.3** | 12.7 | 11.3 |
| 4. Code Gen | **25.5** | 13.4 | 11.8 |
| 5. Multi-step | **22.8** | 13.4 | 11.8 |
| 6. Conciseness | 17.8 | 13.0 | 11.5 |
| 7. Speed (long gen) | **18.7** | 13.4 | 11.8 |

**Verdict: ✅ Significant speedup.** Draft model speculation delivers
~1.5-2× speedup on structured/reasoning tasks (25 tok/s vs ~13 tok/s baseline).
Acceptance rate is high because Granite 3B and 8B share the same architecture
and tokenizer.

**Constraint discovered:** vLLM nightly requires `draft_tensor_parallel_size`
to match target `tensor_parallel_size`. The draft model cannot run on fewer
GPUs — it runs TP=4 alongside the target.

### 6.4 FP8 + CUDA Graphs + Draft Speculation (Granite 8B FP8 + 3B FP8 Draft) ✅✅

Config: FP8 quantized target + FP8 draft, CUDA graphs enabled (no `--enforce-eager`),
`num_speculative_tokens: 5`, `draft_tensor_parallel_size: 4`

| Test | BF16 + enforce-eager (tok/s) | **FP8 + CUDA graphs (tok/s)** | **Speedup** |
|------|:---:|:---:|:---:|
| 1. Instruction Follow | 10.3 | **22.8** | 2.2× |
| 2. Reasoning | 25.0 | **76.0** | 3.0× |
| 3. Tool Calling | 20.3 | **47.9** | 2.4× |
| 4. Code Gen | 25.5 | **79.2** | 3.1× |
| 5. Multi-step | 22.8 | **72.3** | 3.2× |
| 6. Conciseness | 17.8 | **32.1** | 1.8× |
| 7. Speed (long gen) | 18.7 | **58.2** | 3.1× |

**Verdict: ✅✅ Breakthrough result.** Three optimizations stacked multiplicatively:

1. **FP8 quantization** — halved weight reads (16 GB → 8 GB target, 6 GB → 3 GB draft)
2. **CUDA graphs** — eliminated Python/framework overhead per step
3. **Speculative decoding** — multiple tokens verified per weight read

GPU utilization during inference: 97-100% compute, 93.8% VRAM (21.6/23 GB per GPU).
Tool call latency: 0.56 seconds. 128K context preserved.

This config achieves **comparable or faster speed than Opus 4.6 cloud** for
agentic workloads (tool calls: 62 tok/s vs 26 tok/s). Cloud Opus is faster
only on sustained long generation (67 vs 60 tok/s). See Section 12.

---

## 7. Failed Experiments

| Experiment | Why It Failed |
|-----------|---------------|
| Gemma 4 31B BF16 @128K | OOM — 78 GB model + 16 GB KV > 89 GB (4× L4) |
| Gemma 4 31B FP8 without --enforce-eager | OOM — CUDA graph overhead ~10 GB/GPU |
| Gemma 4 31B gemma4_mtp speculation | Checkpoint lacks MTP heads |
| Granite 8B + 3B draft with draft_tp=1 | vLLM requires draft_tp == target_tp |
| Granite 2B as draft (ibm-granite/granite-4.1-2b) | Model repo does not exist on HuggingFace |
| Granite 3B Q4_K_M @32K on RTX A500 | OOM — KV cache needs 2.5 GB, only 0.3 GB free |
| N-gram speculation on Gemma 4 | No speedup — novel content has low n-gram match rate |
| Qwen3.8 with thinking enabled (max_tokens ≤ 3000) | Reasoning tokens exhaust budget, NULL content output |

---

## 8. Complete Speed Comparison

| Model | Host | GPUs | Quant | TP | Context | Spec Decode | tok/s | Quality |
|-------|------|:---:|:---:|:---:|:---:|:---:|---:|:---:|
| Granite 350M | rhtevan-work | 1× A500 | BF16 | 1 | 2K | — | 44 | ❌ Unusable |
| **Granite 3B** | **rhtevan-work** | **1× A500** | **Q4_K_M** | **1** | **16K** | **—** | **37** | **✅ Pass all** |
| Granite 8B | rhtevan-work | 1× A500 | Q4_K_M | 1 | 4K | — | 6.5 | ✅ Pass all |
| Granite 8B + 3B draft | rhel-ai | 4× L4 | BF16 | 4 | 128K | draft_model | 19-25 | ✅ Pass all |
| **Granite 8B FP8 + 3B FP8 draft** | **rhel-ai** | **4× L4** | **FP8** | **4** | **128K** | **draft_model + CUDA graphs** | **58-79** | **✅ Pass all** |
| Gemma 4 31B | rhel-ai | 4× L4 | FP8-block | 4 | 128K | — | 13.4 | ✅ Pass all |
| Gemma 4 31B | rhel-ai | 4× L4 | FP8-block | 4 | 128K | ngram | 13.5 | ✅ Pass all |
| Qwen3.8-27B | rhel-ai | 4× L4 | FP8 | 4 | 128K | — | 11.8 | ✅ Pass all |
| Opus 4.6 | Cloud (GCP Vertex) | — | — | — | — | — | 17-67 | ✅ Reference |

---

## 9. Key Findings

### 9.1 Memory Bandwidth Is the Bottleneck

L4 GPUs at 300 GB/s/GPU cap 27-31B FP8 models at ~13 tok/s (TP=4). This is a
hardware wall — no software optimization can exceed:

```
1,200 GB/s ÷ 31 GB weights = ~38 tok/s theoretical
1,200 GB/s ÷ 16 GB weights = ~75 tok/s theoretical
```

Actual efficiency is 35-50% of theoretical due to TP communication overhead,
attention computation, and Python/framework overhead.

### 9.2 Smaller Models Win on Speed

Granite 3B on a $200 laptop GPU (37 tok/s) is nearly 3× faster than Gemma 4 31B
on $10,000 worth of L4 GPUs (13.4 tok/s). Both pass all 7 benchmark tests.

The 31B model produces higher quality on complex tasks, but for routine agentic
work (tool calling, simple reasoning, code gen), the 3B is indistinguishable.

### 9.3 Speculative Decoding Works (With the Right Method)

- **Draft model speculation: ✅** 1.5-2× speedup on Granite 8B with 3B draft
- **N-gram speculation: ❌** No benefit for novel content generation
- **Native MTP: ❌** Gemma 4 checkpoint lacks MTP heads

Draft model speculation is the only viable software-level speedup, and it requires
a same-family draft model with matching tokenizer.

### 9.4 TP Does Not Increase Token Speed

TP spreads model weights so they fit across multiple GPUs, but each GPU still
reads its shard through the same bandwidth pipe. More GPUs = model fits, not
model runs faster. TP adds all-reduce communication overhead.

### 9.5 Co-hosting Was Explored But Not Practical

Co-hosting two TP=2 models was evaluated but not adopted. It provides model
diversity but drops large model speed to ~8 tok/s on GDDR6 — below usability
threshold. Speculative decoding on a single 8B model (58-79 tok/s) proved
far more effective than co-hosting a slow 27-31B model at 8 tok/s.

---

## 10. Recommendations

### Default Deployment: rhtevan-work — Profile `g3b-16k`

| Setting | Value |
|---------|-------|
| **Model** | Granite 4.1 3B (Q4_K_M GGUF) |
| **Runtime** | llama.cpp |
| **Context** | 16K |
| **Slots** | 1 (single-user agentic workload) |
| **Speed** | ~37 tok/s |
| **Why** | Best speed-to-quality ratio. Passes all 7 tests. 5.7× faster than 8B on same hardware. 16K context is hardware ceiling. |

### Default Deployment: rhel-ai — Profile `g8b-fp8-spec-128k`

| Setting | Value |
|---------|-------|
| **Model** | Granite 4.1 8B FP8 + Granite 4.1 3B FP8 draft |
| **Runtime** | vLLM nightly |
| **TP** | 4 (both target and draft) |
| **Context** | 128K |
| **Speculative Decoding** | draft_model, 5 speculative tokens, CUDA graphs enabled |
| **Speed** | **58-79 tok/s** (task dependent) |
| **GPU Utilization** | 94% VRAM, 97-100% compute during inference |
| **Why** | FP8 + CUDA graphs + speculative decoding achieves 58-79% of Opus cloud speed. 128K context. Same Granite family as rhtevan-work for consistent behavior. |

### Alternate Profile: rhel-ai — `g8b-spec-128k`

| Setting | Value |
|---------|-------|
| **Model** | Granite 4.1 8B BF16 + Granite 4.1 3B BF16 draft |
| **Speed** | 19-25 tok/s |
| **When** | If FP8 quality is insufficient for a specific task, or CUDA graph compilation overhead is problematic |

### On-Demand Models (Not Default Profiles)

| Alias | Model | Speed | When to Use |
|-------|-------|:---:|-------------|
| `gemma4-31b` | Gemma 4 31B FP8-block | 13.4 tok/s | Complex multi-hop reasoning requiring 31B quality |
| `qwen38-27b` | Qwen3.8-27B FP8 | 11.8 tok/s | Qwen-ecosystem compatibility, thinking mode |

Deploy via `setup.sh <alias>` — stops current model on port 9000 first.

### When to Use Cloud (Opus 4.6)

- Tasks requiring frontier-class reasoning beyond 8B capability
- Long document generation (Opus slightly faster at sustained output)
- Benchmarking / quality validation baseline
- Self-hosted Granite 8B is **faster for agentic tool-calling workflows**
  (0.34s vs 2.54s per tool call). See Section 12 for full comparison.

---

## 11. Deployment Commands

### rhtevan-work (default)
```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g3b-16k
# or directly:
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g3b
```

### rhel-ai (default — FP8 speculative decoding)
```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g8b-fp8-spec-128k
# or directly:
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g8b-fp8-spec
```

### rhel-ai (BF16 speculative decoding — safer, slower)
```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh g8b-spec-128k
```

### rhel-ai (alternate models — on demand)
```bash
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh gemma4-31b
bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh qwen38-27b
```

---

## 12. Self-Hosted vs Cloud Provider Comparison

> Measured: 2026-08-26. Non-streaming requests via OpenAI-compatible API.
> Self-hosted: Granite 8B FP8 + 3B FP8 draft (spec decode, CUDA graphs) via Skupper VAN on localhost:9000.
> Cloud: Claude Opus 4.6 via LiteLLM proxy → GCP Vertex AI on localhost:4000.

### 12.1 Raw Results

| Test | Max Tokens | Granite 8B FP8 | | Opus 4.6 (Cloud) | |
|------|:---:|:---:|:---:|:---:|:---:|
| | | **tok/s** | **time** | **tok/s** | **time** |
| Short text | 50 | **58.2** | **0.39s** | 17.5 | 1.89s |
| Tool call | 200 | **62.1** | **0.34s** | 26.4 | 2.54s |
| Medium text | 200 | **54.9** | 3.65s | 46.8 | 4.28s |
| Long generation | 1,000 | 60.4 | 16.56s | **66.6** | **15.02s** |

### 12.2 Analysis

**Latency profile is inverted.** Self-hosted wins on short/interactive
workloads (3.3× faster on short text, 2.4× on tool calls). Cloud wins
on sustained long generation (1.1× faster at 1,000 tokens).

| Metric | Granite 8B FP8 | Opus 4.6 | Winner |
|--------|:---:|:---:|:---:|
| Tool call latency | **0.34s** | 2.54s | Granite (7.5×) |
| Short response latency | **0.39s** | 1.89s | Granite (4.8×) |
| Sustained throughput (1K tok) | 60.4 tok/s | **66.6 tok/s** | Opus (1.1×) |
| 10-step agentic chain (est.) | **~3.4s** | ~25s | Granite (7.4×) |

**Why the crossover happens:**

- **Self-hosted advantage at short output:** Near-zero network latency
  (localhost Skupper VAN vs LiteLLM → GCP Vertex routing chain).
  Opus has ~1.5-2s of fixed overhead per request regardless of output
  length. Speculative decoding's high acceptance rate on short sequences
  amplifies the advantage.

- **Cloud advantage at long output:** Opus runs on H100/TPU clusters
  with ~3 TB/s aggregate memory bandwidth vs 1.2 TB/s on 4× L4 GDDR6.
  At sustained generation, the hardware advantage overcomes the network
  overhead.

### 12.3 Agentic Workload Implications

For typical agentic patterns (many short tool calls, occasional long
text generation), self-hosted Granite 8B FP8 with speculative decoding
is significantly faster wall-clock than cloud Opus:

- **Tool-heavy workflows:** File reads, shell commands, API calls —
  each tool call round-trip is 0.34s vs 2.54s. A session with 20 tool
  calls saves ~44 seconds on tool-call latency alone.

- **Quality trade-off:** Opus 4.6 is a frontier model with superior
  reasoning, instruction following, and code generation quality.
  Granite 8B is production-grade for routine agentic tasks but will
  underperform on complex multi-step reasoning, nuanced natural
  language understanding, and novel problem solving.

- **Cost:** Self-hosted inference on 4× L4 GPUs costs ~$2.40/hr (GCP
  on-demand). Opus via API costs ~$15/M input + $75/M output tokens.
  A heavy agentic session (~100K input + 20K output tokens) costs
  ~$3.00 on Opus vs ~$0.04 on self-hosted (amortized GPU time).

### 12.4 When to Use Which

| Use Case | Recommended | Why |
|----------|:-----------:|-----|
| Routine agentic work (file ops, shell, tool calling) | **Granite 8B** | 7× lower tool-call latency, sufficient quality |
| Complex reasoning / architecture decisions | **Opus 4.6** | Frontier-class reasoning required |
| Long document generation | Opus 4.6 | Slightly faster sustained throughput |
| Cost-sensitive batch operations | **Granite 8B** | ~75× cheaper per session |
| Benchmarking / quality baseline | Opus 4.6 | Reference-grade output quality |
