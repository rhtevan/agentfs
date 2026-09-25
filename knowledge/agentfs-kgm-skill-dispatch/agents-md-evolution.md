# AGENTS.md Evolution

## Token Reduction

| Version | Tokens | Delta | Key change |
|---------|--------|-------|------------|
| 5.10.1 | ~2100 | — | Baseline (Orientation → Scopes → Discovery → Rules) |
| 5.11.0 | ~1660 | -22% | Reorder to Scopes → Discovery → Rules → Orientation; trim WHY prose; merge tier Action column |
| 5.13.0 | ~1362 | -35% | Delete Discovery Tiers section; KGM-based Rule 8 |

## Section Order Evolution

| Version | Order | Rationale |
|---------|-------|-----------|
| 5.10.1 | Orientation → Scopes → Discovery → Rules | Navigation first |
| 5.11.0 | Scopes → Discovery → Rules → Orientation | Dependency chain: Scopes needed by Discovery, Discovery needed by Rules |
| 5.13.0 | Scopes → Rules → Orientation | Discovery Tiers eliminated; KGM handles dispatch |

## Rule 8 Evolution

| Version | Rule 8 content |
|---------|---------------|
| 5.10.1 | "Follow Discovery Tiers (Tier 1 → 2a → 2b → 2c)" — cross-reference to separate section |
| 5.11.0 | "FIRST check # Skills section... call load_skill" — self-contained but relies on prose scanning |
| 5.11.3 | Added anti-pattern clause + concrete example — marginal improvement on 8B |
| 5.12.0 | "FIRST call knowledgegraphmemory__search_nodes" — full tool name |
| 5.13.0 | "FIRST call search_nodes" — canonical short name, tested on Granite |

## Discovery Tiers Lifecycle

Created in v5.4.0 as a 4-tier table (Frontmatter → Skill index →
KGM → Knowledge index). Grew to include staleness guards, freshness
checks, anti-pattern callouts. Deleted in v5.13.0 — replaced by
one-line Rule 8 + KGM skill entities. Operational concerns (staleness,
anti-pattern) moved to `goose-kgm` SKILL.md.

## Key Decision: Why Delete Rather Than Simplify

Discovery Tiers was the only section referenced by a single rule
(Rule 8). It existed to describe a multi-step procedure the model
should follow. When KGM collapsed that procedure to one tool call,
the section had no remaining purpose. A 2-line fallback note replaced
13 lines of tier tables and prose.
