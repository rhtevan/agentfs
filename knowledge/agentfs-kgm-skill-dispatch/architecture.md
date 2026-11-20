---
type: Reference
title: "Architecture"
description: "Separate JSONL indexes, AgentSkill entity format, index path delivery (env wrapper), reindex pipeline"
timestamp: 2026-09-25T02:00:00-04:00
---

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

### Index Path Delivery (env wrapper)

The server reads its index from `MEMORY_FILE_PATH`; without it, it
falls back to `dist/memory.jsonl` in the npx cache, which does not
exist, so `search_nodes` returns an empty graph.

Root cause (goose 1.60.1 source, verified live 2026-11-19): goose
never sends inline stdio `envs` over ACP. `config_to_goose_extension`
drops them and `goose_extension_to_config_without_secrets` forces
them empty (`crates/goose/src/acp/server/extensions.rs`). Desktop new
sessions and desktop toggles both go through ACP, so an `envs`-only
`MEMORY_FILE_PATH` never reached those servers. Only the agent's
`manage_extensions` path (reads `config.yaml` directly) kept it.

Fix (goose-kgm 1.8.3): put the path in `cmd`/`args`, which survive
every path:

```yaml
cmd: env
args: [MEMORY_FILE_PATH=/home/<user>/.agents/knowledge/.kgm-index.jsonl, npx, -y, '@modelcontextprotocol/server-memory']
```

The path must be absolute — no shell runs, so `~` and `$HOME` are
not expanded (`setup-kgm.sh` writes the resolved path).
`/usr/bin/env` execs in place (no extra process). Verified for new
desktop sessions, desktop toggles (after a Goose Desktop restart),
agent `manage_extensions`, and `goose run`. `status-kgm.sh` checks
`MEMORY_FILE_PATH` in `/proc/<pid>/environ` of every running server.

Superseded: the earlier symlink workaround (npx-cache
`dist/memory.jsonl` → the index) was removed in 1.8.3. It could not
create a missing file, broke when the npx cache hash changed, and
let the server's write tools modify the derived index.

The combined index is replaced atomically (temp file + rename,
goose-kgm 1.8.5) because every server re-reads it on each call.

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
