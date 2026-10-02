# Changelog — skill-eval

| Updated | Change |
|---------|--------|
| 2026-10-02 15:06 | v1.0.0 — New skill: skill-eval v1.0.0 — deterministic checks S01-S22 (P1-P7), LLM rubrics S23-S26. Refactored out of agentfs-eval R4. |

## 2026-10-02 v1.0.0

- Initial release: deterministic checks S01–S22 covering all 7 skill-gen principles
- LLM rubric checks S23–S26 for prose-to-script, duplicate procedures, prompt injection, logical sequence
- Two modes: single skill (`hey check skill <name>`) and all skills (`hey check all skills`)
- Refactored out of `agentfs-eval` R4 (skill-accuracy) — clean separation of concerns
