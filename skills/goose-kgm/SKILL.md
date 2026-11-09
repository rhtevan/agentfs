---
name: goose-kgm
description: >
  setup goose kgm, teardown goose kgm, enable kgm, disable kgm, kgm status, reindex kgm, sync kgm
metadata:
  version: "1.7.0"
  model-tier: T3
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

## Rules

Do NOT fabricate KGM status. Every status report MUST come from
actual script output or tool introspection. If a script fails,
report the actual error.

Do NOT edit the JSONL index file directly. All changes MUST go
through the reindex script.

Do NOT edit `config.yaml` to enable/disable KGM. MUST use the
extension manager tool for session-scoped activation.

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

## Workflow

The agent MUST select the appropriate operation based on the user's
request and run the corresponding script. The agent MUST report
the script output verbatim.

### Step 1 — Setup

> Signal: "setup goose kgm"

The agent MUST run:

```bash
bash ~/.agents/skills/goose-kgm/scripts/setup-kgm.sh
```

### Step 2 — Teardown

> Signal: "teardown goose kgm"

The agent MUST run:

```bash
bash ~/.agents/skills/goose-kgm/scripts/teardown-kgm.sh
```

### Step 3 — Enable (Session-scoped)

> Signal: "enable kgm"

The agent MUST use the extension manager tool:

```
extensionmanager__manage_extensions(action: "enable", extension_name: "knowledgegraphmemory")
```

### Step 4 — Disable (Session-scoped)

> Signal: "disable kgm"

The agent MUST use the extension manager tool:

```
extensionmanager__manage_extensions(action: "disable", extension_name: "knowledgegraphmemory")
```

### Step 5 — Status

> Signal: "kgm status"

The agent MUST run:

```bash
bash ~/.agents/skills/goose-kgm/scripts/status-kgm.sh
```

The agent MUST report the script output verbatim.

### Step 6 — Reindex

> Signal: "reindex kgm", "sync kgm"

The agent MUST run:

```bash
bash ~/.agents/skills/goose-kgm/scripts/reindex-kgm.sh
```

The agent MUST report the script output verbatim.

## Agent Usage (when KGM is enabled)

KGM indexes both **skills** and **knowledge**. `search_nodes` returns:

| entityType | Observations | Agent action |
|------------|-------------|-------------|
| `AgentSkill` | `Signals:` (match phrases), `Action:` (exact `load_skill` call) | Follow the Action observation |
| `KnowledgeConcept` | `Source:` (file path), `Summary:` | Read the Source file |
| `KnowledgeBundle` | `Source:` (index path), `Summary:` | Browse the bundle index |

Do not use `shell`, `extensionmanager`, or file browsing to discover skills. `load_skill` is the only correct tool for loading skills.

**Staleness guard:** If `search_nodes` returns nothing but the index files (`~/.agents/skills/index.md` or `~/.agents/knowledge/index.md`) contain a match → ① warn "⚠️ KGM index stale" ② use the index result ③ run `bash ~/.agents/skills/goose-kgm/scripts/reindex-kgm.sh` after responding ④ confirm reindex count delta.

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
