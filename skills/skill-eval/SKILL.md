---
name: skill-eval
description: >
  check skill, eval skill, audit skill quality,
  check all skills, skill evaluation
argument-hint: "hey check skill <name> | hey check all skills"
compatibility: "bash, shellcheck (optional)"
metadata:
  author: agentfs
  version: "1.0.0"
  tags: [agentfs, skills, evaluation, quality, audit]
user-invocable: true
disable-model-invocation: false
---

# Skill Eval

Evaluate individual skills against the seven quality principles
defined in `skill-gen`. Runs deterministic checks on structure,
scripts, and content, plus optional LLM rubric checks for semantic
quality. Produces a severity-graded report per skill.

This skill is the sole authority for skill-level evaluation.
`agentfs-eval` evaluates workspace health and does NOT inspect
skill internals.

## Prerequisites

- `bash`, `grep`, `find`, `wc`
- `shellcheck` (optional — S05 skipped if absent)
- LLM required only for S23–S26 rubric checks

## Modes

| Mode | Signal | Behavior |
|------|--------|----------|
| **Single skill** | `hey check skill <name>` | Run all checks against that skill, report |
| **All skills** | `hey check all skills` | List skills → **ask human permission** → run each → summary |

### Mode 1: Single Skill

1. Resolve skill path — check USER (`~/.agents/skills/<name>/`)
   then PROJECT (`./.agents/skills/<name>/`)
2. Run deterministic checks:
   ```bash
   bash <skill-dir>/scripts/skill-check.sh <path-to-skill-dir>
   ```
3. Run LLM rubric checks (S23–S26) by reading each rubric YAML
   and applying it to the skill content
4. Present report

### Mode 2: All Skills

1. List all skills at the target scope (USER or PROJECT)
2. **Present the list and ask for human confirmation before proceeding**
3. On approval, run Mode 1 against each skill
4. Produce summary report with per-skill pass/warn/fail counts

## Checks

### Deterministic Checks (S01–S22)

Run via `scripts/skill-check.sh`. No LLM required.

| ID | P | Check | Severity | Method |
|:--:|:-:|-------|:--------:|--------|
| S01 | 1 | Frontmatter has `name`, `description`, `metadata.version` (quoted semver), `metadata.tags` (non-empty), `user-invocable` | 🔴 | YAML parse |
| S02 | 1 | `name` matches parent directory name | 🔴 | String compare |
| S03 | 1 | Signal phrases are 2–4 words each | 🟡 | Word count |
| S04 | 1 | Opening paragraph after `# Title` heading | 🟡 | Line scan |
| S05 | 1 | Shellcheck passes on `.sh` scripts | 🟡 | `shellcheck` |
| S06 | 1 | Consistent values across scripts and SKILL.md (ports, hostnames) | 🟡 | Cross-reference |
| S07 | 2 | Referenced commands exist | 🟡 | `command -v` |
| S08 | 2 | Referenced file paths exist | 🔴 | Filesystem check |
| S09 | 2 | Supporting Files section matches actual directory contents | 🟡 | Dir listing diff |
| S10 | 2 | No references to deleted/renamed files | 🔴 | Path check |
| S11 | 3 | `CHANGELOG.md` exists; latest version matches `metadata.version` | 🟡 | Version compare |
| S12 | 3 | Markdown well-formed (unclosed code blocks, broken tables) | 🟢 | Syntax scan |
| S13 | 4 | Specification section exists with IDs | 🟡 | Section scan |
| S14 | 4 | Tests section exists with testcases mapped to spec IDs | 🟡 | Section + ID cross-ref |
| S15 | 5 | No hardcoded secrets/API keys in scripts | 🔴 | Regex patterns |
| S16 | 5 | No `eval`/`source` of untrusted input in scripts | 🔴 | Grep scan |
| S17 | 6 | SKILL.md line count; warn if >300 | 🟡 | `wc -l` |
| S18 | 6 | `## References` section if `references/` dir exists | 🟡 | Dir + heading check |
| S19 | 7 | Scripts use semantic exit codes (0/1/2/3) | 🟡 | Parse `exit` statements |
| S20 | 7 | Error Handling table exists | 🟡 | Section scan |
| S21 | 7 | Troubleshooting table exists | 🟡 | Section scan |
| S22 | 7 | Privilege gates use exit 3 | 🟡 | Grep `sudo` + exit code |

### LLM Rubric Checks (S23–S26)

Rubric YAMLs in `rubrics/`. Require LLM classification.

| ID | P | Check | Method |
|:--:|:-:|-------|--------|
| S23 | 1 | Operations as prose that should be scripts | LLM per code block |
| S24 | 3 | Duplicate/conflicting procedures | LLM across sections |
| S25 | 5 | Prompt injection patterns in SKILL.md | LLM classification |
| S26 | 1 | Steps follow logical sequence | LLM classification |

## Severity Levels

| Icon | Level | Meaning |
|:----:|:-----:|---------|
| 🔴 | Critical | Skill will malfunction |
| 🟡 | Warning | Skill works but violates a principle |
| 🟢 | Info | Improvement suggestion |

## Report Format

```
## Skill Eval Report: <skill-name>

Date: YYYY-MM-DD HH:MM
Version: <metadata.version>
Checks: N pass / N warn / N fail / N skip

| # | ID | P | Severity | Finding | Fix |
|:-:|:--:|:-:|:--------:|---------|-----|
```

## Gotchas

- S05 (shellcheck) is skipped if `shellcheck` is not installed —
  reported as SKIP, not FAIL
- S06 (value consistency) uses heuristic grep — may produce false
  positives on common port numbers like 8080
- S13/S14 (Spec/Test) are 🟡 not 🔴 — many valid utility skills
  are too simple for formal specification sections
- S07 (command existence) only checks commands available on the
  current host — a skill targeting a remote system may reference
  commands not locally installed

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
