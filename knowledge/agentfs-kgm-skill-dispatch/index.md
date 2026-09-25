# KGM-Based Skill Dispatch

Knowledge bundle capturing the design decisions, evidence, and
implementation of using KGM (Knowledge Graph Memory) as a skill
dispatch mechanism for weaker LLM models.

## Concepts

| Concept | File | Summary |
|---------|------|---------|
| [Problem & Evidence](./problem-evidence.md) | problem-evidence.md | Granite 8B fails to scan `# Skills` prose; behavioral score progression 0/3 → 1/3 → KGM solution |
| [Architecture](./architecture.md) | architecture.md | Separate JSONL indexes, AgentSkill entity format, symlink workaround, reindex pipeline |
| [AGENTS.md Evolution](./agents-md-evolution.md) | agents-md-evolution.md | Template token reduction 2100 → 1362, section reordering, Discovery Tiers elimination, Rule 8 rewrites |
| [Testing Infrastructure](./testing-infrastructure.md) | testing-infrastructure.md | template-check.sh, template-behavioral.sh, template-eval.sh, merge-score-entry.sh, score tracking |
| [Design Principles](./design-principles.md) | design-principles.md | Lower cognitive bar, prose → scripts, zero-arg wrappers, ledger integrity |
