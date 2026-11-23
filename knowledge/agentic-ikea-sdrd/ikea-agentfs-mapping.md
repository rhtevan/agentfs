---
type: Reference
title: I.K.E.A. → AgentFS Mapping
description: How each I.K.E.A. store and flow maps to AgentFS files, skills, and KGM — harvest routing, and why KGM entities must come from bundles not hand-creation
tags: [ikea, agentfs, kgm, harvest, okf, skills, memory]
timestamp: 2026-11-23T09:55:00-05:00
---

# I.K.E.A. → AgentFS Mapping

Implementation of the [Agentic I.K.E.A. Model](./ikea-model.md) in
AgentFS. The slide does not define this mapping; it is derived from
the AgentFS skills and file layout.

## Stores

| I.K.E.A. store | AgentFS artifact | Scope |
|---|---|---|
| SESSION (working) | Live conversation context | — |
| LOG (episodic) | `.agents/memories/MEMORY.md` (`hey remember`), `.agents/memories/USER.md` | PROJECT |
| SKILL (procedure) | `~/.agents/skills/<name>/SKILL.md` | USER (default) |
| OKF (semantic) | `~/.agents/knowledge/<bundle>/` | USER only |
| Knowledge → Expertise | KGM index (`search_nodes`) built from skills + OKF | USER |

`.agents/log.md` is a file-change audit trail, not episodic memory.

## Flows

| I.K.E.A. flow | AgentFS mechanism |
|---|---|
| remember (SESSION → LOG) | `hey remember ...` → MEMORY.md + `post-write.sh` |
| harvest → SKILL | `skill-harvest` (from memories), `skill-gen` (from session) |
| harvest → OKF | `okf-bundle-harvest` (from memories), `okf-bundle-gen` (from session) |
| Knowledge → Expertise | `reindex-kgm.sh` → `AgentSkill` / `KnowledgeBundle` / `KnowledgeConcept` entities |

## Harvest routing: procedural vs declarative

| Content shape | Example | Target |
|---|---|---|
| "To do X, run Y then Z" | Install steps with dry-run, rollback | SKILL |
| "Always run X before Y" | Ordering constraint | SKILL |
| "X belongs to layer Y because Z" | Tooling-layer rules | OKF |
| "X breaks when Y > version N" | Compatibility fact | OKF |

### When a procedure does NOT deserve a skill

A skill earns its maintenance cost (index entry, versioning,
`skill-eval` audits) only when it wraps real hazard: ordering,
credentials, config mutation, verification, rollback. A one-line,
idempotent command (e.g. `devbox global add <tool>`) does not. The
reusable part is usually the **decision rule** that picked the
command — which is declarative and belongs in OKF. Example:
[SDRD Tooling Strategy](./sdrd-tooling-strategy.md) instead of a
per-tool install skill.

## KGM entities come from bundles, not hand-creation

`goose-kgm/scripts/reindex-kgm.sh` **regenerates** the KGM JSONL from
`~/.agents/knowledge/index.md` and each bundle's `index.md`. Entities
created by hand via `create_entities` are outside this pipeline and are
lost on the next reindex. To make something discoverable:

```
write OKF bundle → list it in knowledge/index.md → reindex-kgm.sh → search_nodes hits
```

## Discoverability gap pattern

Knowledge that exists only in an ad-hoc document (incident notes, a
slide deck) is invisible to `search_nodes` and index browsing. Symptom:
the agent searches KGM, skills, knowledge, and memories, finds nothing,
and the user must supply the path. Fix: harvest into OKF. Both SDRD
(recovery plan) and I.K.E.A. (slide deck) had this gap before this
bundle.

# Citations

[1] `~/.agents/skills/goose-kgm/SKILL.md` — entity types, staleness guard, sync model.
[2] `~/.agents/skills/goose-kgm/scripts/reindex-kgm.sh` — rebuilds JSONL from knowledge indexes.
[3] `~/.agents/skills/skill-harvest/SKILL.md` — procedural vs declarative routing table.
