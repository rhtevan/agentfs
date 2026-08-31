---
name: goose-kgm
description: >
  setup goose kgm, teardown goose kgm, enable kgm, disable kgm, kgm status
metadata:
  version: "1.0.1"
  tags: [goose, kgm, knowledge-graph, mcp, knowledge]
---

# Goose KG Memory — Knowledge Index

Manage the Knowledge Graph Memory (KGM) MCP extension for Goose.
KGM provides a deterministic substring-search index over OKF
knowledge bundles — it is an **optional accelerator**, not a
replacement for OKF progressive discovery.

## Design Constraints

- **OKF-primary.** The OKF index chain (`~/.agents/knowledge/index.md`
  → bundle `index.md` → concept docs) is the required discovery path.
  KGM collapses multi-hop lookups into a single `search_nodes` call
  when enabled, but OKF must work without KGM.
- **Disabled by default.** User must explicitly enable.
- **Knowledge concepts only.** KGM indexes bundle/concept metadata
  from OKF — not guardrails, not memories, not skill content.
- **Derived artifact.** The JSONL file is regenerated from OKF indexes.
  It is gitignored and never hand-edited.

## Configuration

| Setting | Value |
|---------|-------|
| Extension name | `knowledge-graph-memory` |
| Type | `stdio` (MCP server) |
| Command | `npx` |
| Args | `["-y", "@modelcontextprotocol/server-memory"]` |
| Env var | `MEMORY_FILE_PATH` |
| JSONL path | `~/.agents/knowledge/.kgm-index.jsonl` |
| Config file | `~/.config/goose/config.yaml` |

## Operations

### Setup

> Signal: "setup goose kgm"

```bash
bash ~/.agents/skills/goose-kgm/scripts/setup-kgm.sh
```

Adds the `knowledge-graph-memory` extension entry to Goose config
with `enabled: false`. Creates the JSONL directory if needed.
Idempotent — skips if entry already exists.

### Teardown

> Signal: "teardown goose kgm"

```bash
bash ~/.agents/skills/goose-kgm/scripts/teardown-kgm.sh
```

Removes the `knowledge-graph-memory` extension entry from Goose
config and deletes the JSONL file. Idempotent.

### Enable

> Signal: "enable kgm"

```bash
bash ~/.agents/skills/goose-kgm/scripts/enable-kgm.sh
```

Sets `enabled: true` in the extension config. Requires setup first.
After enabling, the agent should restart or the extension becomes
available in the next Goose session.

### Disable

> Signal: "disable kgm"

```bash
bash ~/.agents/skills/goose-kgm/scripts/disable-kgm.sh
```

Sets `enabled: false` in the extension config. The JSONL file is
preserved — re-enabling restores the index without rebuild.

### Status

> Signal: "kgm status"

```bash
bash ~/.agents/skills/goose-kgm/scripts/status-kgm.sh
```

Reports:
- Configured: yes/no (extension entry exists in config)
- Enabled: yes/no
- JSONL file: exists/missing, entity count, file size
- Last reindex: timestamp from JSONL file mtime

## KGM Reindex

Reindexing rebuilds the JSONL from OKF bundle indexes. It runs:

1. As part of `sync agentfs` (via `agentfs-setup`) — conditional on
   KGM being enabled
2. Manually via `bash ~/.agents/skills/goose-kgm/scripts/reindex-kgm.sh`

See [references/kgm-entity-schema.md](./references/kgm-entity-schema.md)
for the entity/relation/observation schema (created in A8).

## Agent Usage (when KGM is enabled)

When KGM tools are available in the session, the agent can use
`search_nodes("<query>")` to quickly find relevant knowledge bundle
paths before loading them. This replaces the multi-hop index walk
but does NOT replace reading the actual concept documents.

**Flow:** `search_nodes` → get `Source` observation → read file path.
