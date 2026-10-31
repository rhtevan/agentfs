# ES Implementation Patterns

Three patterns for implementing Executable Specifications in AgentFS,
ordered by complexity.

## Pattern 1: Deterministic Script

**When:** The pass/fail criteria can be expressed as filesystem state,
output patterns, or structural properties.

**How:** Write a shell function or script that greps, parses, or diffs
against concrete artifacts.

**Example:**
```bash
# ES: Rule 6 must mention "deleting" in its When clause
check_rule6_deletion_coverage() {
  if grep -q "deleting" AGENTS.md; then
    echo "PASS: Rule 6 covers deletions"
  else
    echo "FAIL: Rule 6 does not mention deletions"
  fi
}
```

**Strengths:** Fast, reproducible, zero LLM cost, no stochasticity.
**Limits:** Cannot assess semantic quality, intent, or ambiguity.

## Pattern 2: SDM-Hybrid

**When:** The pass/fail criteria involve semantic or qualitative
judgment that cannot be reduced to grep patterns.

**How:** Combine structural evidence gathering (deterministic script)
with SDM scoring (LLM-as-classifier with a structured schema).
The SDM produces a quantitative score; the ES defines a threshold.

**Example:**
```bash
# ES: CNL compliance of Rule 1 must score >= 0.80
# Step 1: Gather structural evidence (deterministic)
bash gather-skill-state.sh --target agents-md ./AGENTS.md > /tmp/evidence.txt

# Step 2: Score via SDM (semantic, bounded)
score=$(bash sdm-evaluate.sh /tmp/evidence.txt quality-agents-md.yaml \
  | jq '.dimensions[] | select(.name=="has_muscle") | .score')

# Step 3: Threshold (deterministic)
if (( $(echo "$score >= 0.80" | bc -l) )); then
  echo "PASS: CNL compliance $score >= 0.80"
else
  echo "FAIL: CNL compliance $score < 0.80"
fi
```

**Strengths:** Can assess semantic properties quantitatively.
**Limits:** Stochastic (LLM variance). Mitigated by majority vote
and bounded classification.

## Pattern 3: Benchmark Test Case

**When:** The pass/fail criteria require observing a model's behavior
in response to a prompt — end-to-end runtime validation.

**How:** Add a test to `benchmark.sh` with a prompt, a checker
function, and pass criteria. Run against a known-bad fixture (must
fail) and known-good fixture (must pass).

**Example:**
```bash
# ES: Dispatch chain must verify invocation correctness, not just presence
TEST_PROMPT[t_dispatch_fidelity]="hey check violations"
check_t_dispatch_fidelity() {
  local output="$1"
  # Level 1: search_nodes present
  grep -q 'search_nodes' "$output" || { echo "FAIL: no search_nodes"; return 1; }
  # Level 2: search_nodes succeeded (no error response)
  if grep -q 'search_nodes.*error\|isError.*true' "$output"; then
    echo "FAIL: search_nodes called but returned error"
    return 1
  fi
  # Level 3: load_skill matches search_nodes result
  ...
}
```

**Strengths:** Tests actual model behavior end-to-end.
**Limits:** Slow (runs goose), stochastic (model variance), expensive.
Use sparingly for critical paths.

## Fixture-Based Validation

For Pattern 3, maintain test fixtures — captured outputs from
known-good and known-bad sessions:

```
~/.agents/scripts/fixtures/
  dispatch-good.txt    # Known-good dispatch output
  dispatch-bad-qw14b.txt  # Known-bad: wrong parameter name
```

The improved checker must:
1. FAIL against `dispatch-bad-qw14b.txt`
2. PASS against `dispatch-good.txt`

This validates the checker itself without running the full model,
following the ES-First sequence: red first, then green.

## Choosing a Pattern

| Signal | Pattern |
|--------|---------|
| Can I grep for it? | Pattern 1 (deterministic) |
| Is it about meaning, quality, or ambiguity? | Pattern 2 (SDM-hybrid) |
| Does it require observing model behavior? | Pattern 3 (benchmark) |
| Multiple signals? | Compose: deterministic base + SDM or benchmark overlay |
