---
name: agentflow-fuseki
description: >
  setup fuseki, start fuseki, stop fuseki, fuseki status
argument-hint: "fuseki {setup|start|stop|status}"
compatibility: "Linux with systemd user sessions, Java 17+"
metadata:
  author: agentfs
  version: "1.0.1"
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

## Prerequisites

- Linux with systemd user sessions (`systemctl --user` must work)
- Java 17+ installed and on PATH
- `curl` and `wget` available
- Internet access (for initial binary download only)

## Steps

### 1. Setup (install + configure)

Run the setup script. It is idempotent — safe to run multiple times.

```bash
bash ~/.agents/skills/fuseki/scripts/setup-fuseki.sh
```

This script:
1. Checks Java 17+ is available
2. Downloads Apache Jena and Jena Fuseki binaries (skips if already installed)
3. Creates stable symlinks (`~/.local/share/apache-jena`, `~/.local/share/apache-jena-fuseki`)
4. Adds `JENA_HOME`, `FUSEKI_HOME`, and PATH entries to `~/.bashrc` (skips if already present)
5. Creates `~/.local/share/fuseki-data/` for persistent data
6. Installs a systemd user service unit (`fuseki.service`)
7. Enables the service (does NOT start it automatically)

### 2. Start

Run the start script:

```bash
bash ~/.agents/skills/fuseki/scripts/start-fuseki.sh
```

This script:
1. Starts the `fuseki.service` systemd user service
2. Waits for Fuseki to become healthy (polls `/$/ping`)
3. Reports the endpoint URL and available datasets

### 3. Stop

Run the stop script:

```bash
bash ~/.agents/skills/fuseki/scripts/stop-fuseki.sh
```

This script:
1. Stops the `fuseki.service` systemd user service
2. Confirms the port is released

### 4. Status

Run the status script:

```bash
bash ~/.agents/skills/fuseki/scripts/status-fuseki.sh
```

This script:
1. Checks whether Jena and Fuseki binaries are installed
2. Checks systemd service state
3. If running, queries the Fuseki API for datasets and health
4. Reports versions of all Jena CLI tools

## Verification

- [ ] `riot --version` returns Apache Jena RIOT version
- [ ] `shacl --version` returns Apache Jena SHACL version
- [ ] `systemctl --user status fuseki` shows the service unit
- [ ] `fuseki start` → `http://localhost:3030` responds with HTTP 200
- [ ] `fuseki stop` → port 3030 is released


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
