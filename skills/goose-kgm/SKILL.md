---
name: goose-kgm
description: >
  setup goose kgm, teardown goose kgm, enable kgm, disable kgm, kgm status, reindex kgm, sync kgm
metadata:
  version: "1.1.0"
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
- **Session-scoped activation.** KGM is enabled/disabled per session
  using the extension manager, not by editing `config.yaml`. The
  global config keeps `enabled: false` — KGM is opt-in each session.
- **Disabled by default.** User must explicitly enable per session.
- **Knowledge concepts only.** KGM indexes bundle/concept metadata
  from OKF — not guardrails, not memories, not skill content.
- **Derived artifact.** The JSONL file is regenerated from OKF indexes.
  It is gitignored and never hand-edited.

## Configuration

| Setting | Value |
|---------|-------|
| Extension name | `knowledgegraphmemory` |
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

Adds the `knowledgegraphmemory` extension entry to Goose config
with `enabled: false`. Creates the JSONL directory if needed.
Idempotent — skips if entry already exists.

### Teardown

> Signal: "teardown goose kgm"

```bash
bash ~/.agents/skills/goose-kgm/scripts/teardown-kgm.sh
```

Removes the `knowledgegraphmemory` extension entry from Goose
config and deletes the JSONL file. Idempotent.

### Enable (Session-scoped)

> Signal: "enable kgm"

**Do not edit config.yaml.** Use the extension manager tool:

```
extensionmanager__manage_extensions(action: "enable", extension_name: "knowledgegraphmemory")
```

This activates KGM tools (`search_nodes`, `read_graph`, etc.) for
the current session only. The global config retains `enabled: false`.
Requires setup to have been run first (extension entry must exist).

### Disable (Session-scoped)

> Signal: "disable kgm"

**Do not edit config.yaml.** Use the extension manager tool:

```
extensionmanager__manage_extensions(action: "disable", extension_name: "knowledgegraphmemory")
```

Deactivates KGM tools for the current session. The JSONL index file
is preserved on disk for future sessions.

### Status

> Signal: "kgm status"

Two-part check:

**1. Infrastructure status** (JSONL file, config entry):

```bash
bash ~/.agents/skills/goose-kgm/scripts/status-kgm.sh
```

**2. Session status** (agent self-check):

The agent verifies whether `knowledgegraphmemory` tools are available
in the current session by inspecting its active tool set. Report:

- Session active: yes/no (are KGM tools available right now?)
- Config entry: yes/no (is the extension configured in `config.yaml`?)
- JSONL: exists/missing, bundle count, concept count, last reindex

### Reindex

> Signal: "reindex kgm", "sync kgm"

```bash
bash ~/.agents/skills/goose-kgm/scripts/reindex-kgm.sh
```

Rebuilds the JSONL index from scratch by parsing OKF knowledge
bundle indexes. Use after adding, removing, or modifying knowledge
bundles to keep KGM in sync.

Also runs automatically as part of `sync agentfs` (via `agentfs-setup`)
when KGM is configured — pass `--check-enabled` flag to conditionally
skip when disabled in config.

**Manual reindex does not require KGM to be enabled** — the JSONL
file can be rebuilt at any time regardless of session state.

## Agent Usage (when KGM is enabled)

When KGM tools are available in the session, the agent can use
`search_nodes("<query>")` to quickly find relevant knowledge bundle
paths before loading them. This replaces the multi-hop index walk
but does NOT replace reading the actual concept documents.

**Flow:** `search_nodes` → get `Source` observation → read file path.

## Sync Model

KGM does **not** auto-sync with OKF. The JSONL is a point-in-time
snapshot rebuilt on demand. Staleness signals:

- `kgm status` reports last reindex timestamp
- If a `Source:` path from `search_nodes` points to a missing file,
  the index is stale — reindex and retry

Sync triggers:
1. Manual: "reindex kgm" or "sync kgm"
2. Automatic: as part of `sync agentfs` (conditional on config)
3. No file watchers, no hooks, no reactive sync
