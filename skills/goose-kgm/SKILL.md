---
name: goose-kgm
description: >
  setup goose kgm, teardown goose kgm, enable kgm, disable kgm, kgm status, reindex kgm, sync kgm
metadata:
  version: "1.8.4"
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
- **Session-scoped activation.** `setup-kgm.sh` writes `enabled: false`,
  so KGM is opt-in per session (desktop chat extension toggle, or the
  extension manager tool). If the user turns it on globally in Goose
  Settings → Extensions (`enabled: true`), every new session gets KGM.
- **Disabled by default.** Fresh setup leaves it off; migration of an
  existing entry preserves whatever `enabled` value is already there.
- **Index path in `cmd`/`args`, never `envs`.** See Index Path Delivery.
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
extension manager tool (or the user's desktop toggle) for
session-scoped activation.

Do NOT put `MEMORY_FILE_PATH` in the extension's `envs`. Goose drops
inline `envs` on the desktop ACP path; MUST use the `env` wrapper
that `setup-kgm.sh` writes.

## Configuration

| Setting | Value |
|---------|-------|
| Extension name | `knowledgegraphmemory` |
| Type | `stdio` (MCP server) |
| Command | `env` |
| Args | `["MEMORY_FILE_PATH=<abs path to .kgm-index.jsonl>", "npx", "-y", "@modelcontextprotocol/server-memory"]` |
| `envs` | none (MEMORY_FILE_PATH there is dropped by Goose — see below) |
| JSONL path | `~/.agents/knowledge/.kgm-index.jsonl` |
| Config file | `~/.config/goose/config.yaml` |

## Index Path Delivery

Goose 1.60.1 never sends inline `envs` over ACP: `config_to_goose_extension`
drops them and `goose_extension_to_config_without_secrets` forces them
empty (`crates/goose/src/acp/server/extensions.rs`). Desktop sessions and
desktop toggles are built from that ACP listing, so an `envs`-only
`MEMORY_FILE_PATH` never reaches the server. The server then reads its
empty default (`dist/memory.jsonl` in the npx cache) and `search_nodes`
returns nothing while `config.yaml` looks correct. `cmd`/`args` survive
every path, hence `env MEMORY_FILE_PATH=… npx …`.

| Path | Index path delivered (env wrapper) |
|------|------------------------------------|
| New desktop session | ✅ |
| Desktop toggle in an open session | ✅ only after the desktop has reloaded its extension list (restart Goose Desktop first) |
| Resume of a session saved before the fix | ❌ until KGM is toggled once (after restart) |
| Agent `manage_extensions` enable | ✅ live-tested 2026-11-20 (disable released the old server; enable spawned a new one with the path set; `search_nodes` hit) |
| `goose` CLI (`goose run`) | ✅ live-tested 2026-11-20 (server child of `goose run` had the path set; `search_nodes` hit; server exited with the run) |

Each session launches its own server from its **saved** extension copy
(`sessions.db`), so verify the running processes, not just `config.yaml`:
`status-kgm.sh` reports `MEMORY_FILE_PATH` from `/proc/<pid>/environ`
for every running server. No symlink into the npx cache is needed or
created (removed in 1.8.3).

## Known Issues

| Issue | Impact | Status |
|-------|--------|--------|
| One KGM server per session | Every session with KGM enabled spawns its own `npm exec` + `node` pair (~165 MB). With `enabled: true` globally, each new desktop session adds one. Cost scales with open sessions, not with the single shared index. | Documented, no action. Candidate fix: one shared long-running server — not researched. |
| Server lifetime follows the session | Verified 2026-11-20: deleting a session, `manage_extensions` disable, and the end of a `goose run` each stopped that session's server — no orphans observed. A server stays alive as long as its session exists in Goose Desktop. | Expected behavior. If `status-kgm.sh` ever lists a server whose session is gone, kill it and report it here. |

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

The script adds the entry, or migrates a legacy `envs`-only entry to
the `env` wrapper. After it changes `config.yaml`, the agent MUST tell
the user: start a new session, or restart Goose Desktop and toggle KGM
off/on in each open session. Then run Step 5 to confirm every running
server reports ✅.

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

The agent MUST report the script output verbatim. A `Runtime: ❌` line
means that session's server runs without the index path; report the
fix the script prints. Do NOT report KGM healthy from the config
check alone.

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
