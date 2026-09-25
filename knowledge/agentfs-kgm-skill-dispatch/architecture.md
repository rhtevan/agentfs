# Architecture

## KGM Skill Index

Skills are indexed into KGM as `AgentSkill` entities alongside
existing `KnowledgeBundle` and `KnowledgeConcept` entities.

### Entity Format

```jsonl
{"type": "entity", "name": "skill:skupper-model-provider",
 "entityType": "AgentSkill",
 "observations": [
   "Signals: setup skupper, stop skupper, skupper status, ...",
   "Action: load_skill(name: \"skupper-model-provider\")"
 ]}
```

`search_nodes("skupper status")` matches the Signals observation
and returns the entity with the exact `load_skill` call.

### Separate Indexes, Merged Output

| File | Contains | Generator |
|------|----------|-----------|
| `~/.agents/knowledge/.kgm-knowledge.jsonl` | KnowledgeBundle + KnowledgeConcept | `reindex-kgm.sh` |
| `~/.agents/skills/.kgm-skills.jsonl` | AgentSkill | `reindex-skills-kgm.sh` |
| `~/.agents/knowledge/.kgm-index.jsonl` | Combined | Concatenation at end of `reindex-kgm.sh` |

### Symlink Workaround

Goose does not reliably pass the `MEMORY_FILE_PATH` env var from
config.yaml to the MCP server-memory process (the session extension
data has `envs: {}`). The MCP server falls back to its default
`dist/memory.jsonl` inside the npm package cache.

Fix: `setup-kgm.sh` creates a symlink:

```
<npm-cache>/server-memory/dist/memory.jsonl → ~/.agents/knowledge/.kgm-index.jsonl
```

This breaks on npm package upgrades — `setup-kgm.sh` re-creates it.

## Dispatch Flow

```
User: "skupper status"
  → Model calls search_nodes("skupper status")
  → KGM returns: skill:skupper-model-provider
     Action: load_skill(name: "skupper-model-provider")
  → Model calls load_skill(name: "skupper-model-provider")
  → Skill content loaded into context
  → Model follows skill instructions
```

No prose scanning. No pattern matching by the model. One tool call
to find, one tool call to load.
