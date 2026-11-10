---
name: agentflow-fuseki
description: >
  setup fuseki, start fuseki, stop fuseki, fuseki status
argument-hint: "fuseki {setup|start|stop|status}"
compatibility: "Linux with systemd user sessions, Java 17+"
metadata:
  author: agentfs
  version: "1.2.0"
  model-tier: T1
  tags: [fuseki, jena, sparql, rdf, infrastructure, service]
user-invocable: true
disable-model-invocation: false
---

# Fuseki

Install and manage Apache Jena Fuseki as a local user systemd service
with associated CLI tools (`riot`, `shacl`, etc.).

## Overview

| Property | Value |
|----------|-------|
| **Fuseki Home** | `~/.local/share/apache-jena-fuseki/` |
| **Jena Home** | `~/.local/share/apache-jena/` |
| **Systemd Unit** | `~/.config/systemd/user/fuseki.service` |
| **Default Port** | `3030` |
| **Data Directory** | `~/.local/share/fuseki-data/` |
| **Web UI** | `http://localhost:3030` |

## Signal Routing

| Signal | Action |
|--------|--------|
| "fuseki setup" | Run setup script (install binaries + systemd service) |
| "fuseki start" | Start the fuseki systemd user service |
| "fuseki stop" | Stop the fuseki systemd user service |
| "fuseki status" | Check service status, port, and dataset health |

## Rules

Do NOT fabricate or invent command output. Every status report MUST
come from actual script execution. If a script fails, report the
actual error — do not guess what the output should be.

Do NOT modify Fuseki configuration files directly. All changes MUST
go through the setup script.

## Prerequisites

- Linux with systemd user sessions (`systemctl --user` must work)
- Java 17+ installed and on PATH
- `curl` and `wget` available
- Internet access (for initial binary download only)

## Steps

### Step 1 — Setup (install + configure)

The agent MUST run the setup script. It is idempotent — safe to run
multiple times.

```bash
bash ~/.agents/skills/fuseki/scripts/setup-fuseki.sh
```

The agent MUST report the script output verbatim. Do NOT summarize
or paraphrase what the script does.

### Step 2 — Start

The agent MUST run the start script:

```bash
bash ~/.agents/skills/fuseki/scripts/start-fuseki.sh
```

The agent MUST wait for the script to complete and report the
endpoint URL and available datasets from the actual output.

### Step 3 — Stop

The agent MUST run the stop script:

```bash
bash ~/.agents/skills/fuseki/scripts/stop-fuseki.sh
```

### Step 4 — Status

The agent MUST run the status script:

```bash
bash ~/.agents/skills/fuseki/scripts/status-fuseki.sh
```

The agent MUST report the actual output. Do NOT fabricate service
state or dataset information.

## Verification

- [ ] `riot --version` returns Apache Jena RIOT version
- [ ] `shacl --version` returns Apache Jena SHACL version
- [ ] `systemctl --user status fuseki` shows the service unit
- [ ] `fuseki start` → `http://localhost:3030` responds with HTTP 200
- [ ] `fuseki stop` → port 3030 is released


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
