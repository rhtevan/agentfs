---
name: skupper-linux-two-site
description: >
  Set up a two-site Skupper V2 network on the Linux/systemd platform with
  native skrouterd, link the sites, and verify connectivity with a netcat
  (nc) echo test. Use when a user wants to create a Skupper VAN between
  two Linux hosts using systemd (not Podman/Docker), or when testing
  inter-site connectivity on bare-metal or VM hosts.
argument-hint: >
  Usage: skupper-linux-two-site --local-site <name> --remote-site <name>
    --remote-host <ssh-host> --namespace <ns>
    [--firewall-zone <zone>] [--test-port <port>] [--routing-key <key>]
  Example: skupper-linux-two-site --local-site my-hub
    --remote-site my-edge --remote-host my-edge
    --namespace playground
parameters:
  LOCAL_SITE_NAME:
    description: Name for the interior (hub) Skupper site on localhost
    required: true
    binding-cues: ["local site", "this host", "hub site", "interior site"]
    example: my-hub
  REMOTE_SITE_NAME:
    description: Name for the edge Skupper site on the remote host
    required: true
    binding-cues: ["remote site", "edge site", "other host"]
    example: my-edge
  REMOTE_SSH_HOST:
    description: SSH target for the remote host (alias or user@host)
    required: true
    binding-cues: ["ssh host", "remote host", "connect to", "ssh alias"]
    example: my-edge
  NAMESPACE:
    description: Skupper namespace (isolates sites on the same host)
    required: true
    binding-cues: ["namespace", "ns"]
    example: playground
  FIREWALL_ZONE:
    description: Firewall zone on the interior site (auto-detected if omitted)
    required: false
    default: auto-detect via 'firewall-cmd --get-active-zones'
    binding-cues: ["firewall zone", "zone"]
    example: FedoraWorkstation
  TEST_PORT:
    description: Port number for the nc echo test
    required: false
    default: "9090"
    binding-cues: ["test port", "port", "nc port"]
    example: "9090"
  TEST_ROUTING_KEY:
    description: Skupper routing key for the nc test service
    required: false
    default: nc-test
    binding-cues: ["routing key", "service key"]
    example: nc-test
compatibility: >
  Requires: skrouterd (native) on both hosts, skupper CLI 2.x on both
  hosts, systemd --user support, SSH access to remote host, firewall-cmd
  (if firewall is active on interior site)
metadata:
  author: agentfs
  version: "1.3"
  tags: [skupper, linux, systemd, two-site, van, networking, skrouterd]
user-invocable: true
disable-model-invocation: false
---

# Skupper V2 — Linux/systemd Two-Site Setup

Create a two-site Skupper Virtual Application Network (VAN) on the
Linux/systemd platform using native `skrouterd`, link the sites with
mTLS, and verify end-to-end connectivity using `nc` (netcat).

## Parameters

Parameters are defined in the YAML frontmatter under `parameters:`.
Each parameter has `binding-cues` — phrases the agent should match
against user input for semantic binding.

| Parameter | Required | Default | Binding Cues | Example |
|-----------|:--------:|---------|-------------|----------|
| `LOCAL_SITE_NAME` | ✅ | — | "local site", "this host", "hub site" | `my-hub` |
| `REMOTE_SITE_NAME` | ✅ | — | "remote site", "edge site", "other host" | `my-edge` |
| `REMOTE_SSH_HOST` | ✅ | — | "ssh host", "remote host", "connect to" | `my-edge` |
| `NAMESPACE` | ✅ | — | "namespace", "ns" | `playground` |
| `FIREWALL_ZONE` | ❌ | auto-detect | "firewall zone", "zone" | `FedoraWorkstation` |
| `TEST_PORT` | ❌ | `9090` | "test port", "port", "nc port" | `9090` |
| `TEST_ROUTING_KEY` | ❌ | `nc-test` | "routing key", "service key" | `nc-test` |

### Agent Binding Rules

1. **Match user input against `binding-cues`** — when the user says
   "set up a skupper VAN to remote host my-edge", bind
   `my-edge` to `REMOTE_SSH_HOST` (matches "remote host").

2. **Prompt for missing required parameters** — if a required parameter
   cannot be resolved from context, present a usage hint:

   ```
   Missing required parameters. Usage:
     skupper-linux-two-site --local-site <name> --remote-site <name>
       --remote-host <ssh-host> --namespace <ns>
   ```

3. **Apply defaults for optional parameters** — do not prompt for
   optional parameters unless the user explicitly mentions them.

4. **Confirm bindings before executing** — show the resolved parameter
   table and ask for confirmation:

   ```
   Resolved parameters:
     LOCAL_SITE_NAME:  my-hub
     REMOTE_SITE_NAME: my-edge
     REMOTE_SSH_HOST:  my-edge
     NAMESPACE:        playground
     TEST_PORT:        9090 (default)
   Proceed? [y/n]
   ```

5. **Script argument mapping** — parameters map to script args as:

   | Script | Args |
   |--------|------|
   | `verify-prerequisites.sh` | `$1=REMOTE_SSH_HOST` |
   | `create-site.sh` | `$1=SITE_NAME $2=NAMESPACE $3=ROLE $4=REMOTE_SSH_HOST` |
   | `link-sites.sh` | `$1=NAMESPACE $2=LOCAL_IP $3=REMOTE_SSH_HOST` |
   | `test-nc.sh` | `$1=NAMESPACE $2=REMOTE_SSH_HOST $3=LOCAL_SITE_NAME $4=TEST_PORT $5=TEST_ROUTING_KEY` |
   | `teardown.sh` | `$1=NAMESPACE $2=REMOTE_SSH_HOST` |

## Invocation Example

### Happy path — all required parameters provided

User: *"Set up a skupper VAN between this host and my-edge, call the local site my-hub and the remote site my-edge, use namespace playground"*

```
load_skill(name: "skupper-linux-two-site", args: "--local-site my-hub --remote-site my-edge --remote-host my-edge --namespace playground")
```

Agent confirms:

```
Resolved parameters:
  LOCAL_SITE_NAME:   my-hub
  REMOTE_SITE_NAME:  my-edge
  REMOTE_SSH_HOST:   my-edge
  NAMESPACE:         playground
  FIREWALL_ZONE:     auto-detect
  TEST_PORT:         9090 (default)
  TEST_ROUTING_KEY:  nc-test (default)

Proceed? [y/n]
```

### Missing required parameters

User: *"Set up skupper on namespace playground"*

Agent responds:

```
Missing required parameters. Usage:
  skupper-linux-two-site --local-site <name> --remote-site <name>
    --remote-host <ssh-host> --namespace <ns>

Please provide:
  --local-site   Name for the interior site on this host (e.g., my-hub)
  --remote-site  Name for the edge site on the remote host (e.g., my-edge)
  --remote-host  SSH target for the remote host (e.g., my-edge)
```

## Prerequisites

- [ ] `skrouterd` installed natively on **both** hosts (see `skupper-router-installation` knowledge bundle)
- [ ] `skupper` CLI (v2.x) installed on **both** hosts
- [ ] SSH access from localhost to `REMOTE_SSH_HOST` (key-based, no password prompt)
- [ ] systemd `--user` support on both hosts
- [ ] `nc` (ncat/netcat) available on both hosts
- [ ] A working directory on both hosts (e.g., `~/app/playground/rhsi`)

## Architecture

```
Localhost (Interior)                    Remote Host (Edge)
┌──────────────────────┐  mTLS Link  ┌──────────────────────┐
│  LOCAL_SITE_NAME     │ ←────────── │  REMOTE_SITE_NAME    │
│  linkAccess: default │   port      │  edge: true          │
│  ports: 55671, 45671 │   45671     │                      │
│  (skrouterd native)  │             │  (skrouterd native)  │
└──────────────────────┘             └──────────────────────┘
   namespace: NAMESPACE                 namespace: NAMESPACE
```

**Link direction:** The edge site (remote) connects **outbound** to
the interior site (localhost). Only the interior site needs inbound
firewall rules.

## Steps

### Phase 1: Verify Prerequisites

1. **Check skrouterd on both hosts**

   ```bash
   skrouterd --version
   ssh ${REMOTE_SSH_HOST} 'skrouterd --version'
   ```

   Both must return a version (e.g., `3.4.2`).

2. **Check skupper CLI on both hosts**

   ```bash
   skupper version
   ssh ${REMOTE_SSH_HOST} 'skupper version'
   ```

   Both must return a version (e.g., `2.2.1`).

### Phase 2: Create Sites

3. **Create the Interior site on localhost**

   Write the Site resource YAML:

   ```yaml
   # site-local.yaml
   apiVersion: skupper.io/v2alpha1
   kind: Site
   metadata:
     name: ${LOCAL_SITE_NAME}
   spec:
     linkAccess: default
   ```

   Apply and start:

   ```bash
   skupper system -n ${NAMESPACE} -p linux apply -f site-local.yaml
   skupper system -n ${NAMESPACE} -p linux start
   ```

   Verify the systemd service is running:

   ```bash
   systemctl --user status skupper-${NAMESPACE}.service
   ```

   Verify ports are listening:

   ```bash
   ss -tlnp | grep -E '55671|45671'
   ```

4. **Create the Edge site on the remote host**

   Write the Site resource YAML:

   ```yaml
   # site-remote.yaml
   apiVersion: skupper.io/v2alpha1
   kind: Site
   metadata:
     name: ${REMOTE_SITE_NAME}
   spec:
     edge: true
   ```

   Copy to remote, apply, and start:

   ```bash
   scp site-remote.yaml ${REMOTE_SSH_HOST}:~/site-remote.yaml
   ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux apply -f ~/site-remote.yaml"
   ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux start"
   ```

   Verify:

   ```bash
   ssh ${REMOTE_SSH_HOST} 'systemctl --user status skupper-${NAMESPACE}.service'
   ```

### Phase 3: Open Firewall (Interior Site Only)

The interior site accepts inbound links. If a firewall is active on
localhost, open port **45671** (edge links). Port 55671 is only
needed if other interior sites will link in.

5. **Check and open firewall (requires sudo)**

   ```bash
   # Detect active zone if FIREWALL_ZONE not provided
   firewall-cmd --get-active-zones

   # Open port
   sudo firewall-cmd --zone=${FIREWALL_ZONE} --add-port=45671/tcp --permanent
   sudo firewall-cmd --reload

   # Verify
   firewall-cmd --list-ports
   ```

   > **Note:** This step requires `sudo`. The agent cannot perform
   > this automatically — provide the commands for the user to run.

   If no firewall is active, skip this step.

### Phase 4: Link the Sites

6. **Get the interior site's reachable IP**

   ```bash
   LOCAL_IP=$(hostname -I | awk '{print $1}')
   echo "Interior site IP: ${LOCAL_IP}"
   ```

   Verify the remote host can reach this IP:

   ```bash
   ssh ${REMOTE_SSH_HOST} "nc -zv ${LOCAL_IP} 45671 -w 5"
   ```

7. **Generate a link token on the interior site**

   ```bash
   skupper link generate -n ${NAMESPACE} -p linux --host ${LOCAL_IP} > link-token.yaml
   ```

8. **Copy the token to the remote host and apply**

   ```bash
   scp link-token.yaml ${REMOTE_SSH_HOST}:~/link-token.yaml
   ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux apply -f ~/link-token.yaml"
   ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux reload"
   ```

9. **Verify the link**

   Check TCP connection:

   ```bash
   ss -tnp | grep 45671 | grep ESTAB
   ```

   Check link status (may show "Pending" — see Known Issues):

   ```bash
   ssh ${REMOTE_SSH_HOST} 'skupper link status -n ${NAMESPACE} -p linux'
   ```

### Phase 5: Test with nc

10. **Create a Connector on the remote host**

    ```yaml
    # connector-nc.yaml
    apiVersion: skupper.io/v2alpha1
    kind: Connector
    metadata:
      name: nc-connector
    spec:
      routingKey: ${TEST_ROUTING_KEY}
      port: ${TEST_PORT}
      host: localhost
    ```

    ```bash
    scp connector-nc.yaml ${REMOTE_SSH_HOST}:~/connector-nc.yaml
    ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux apply -f ~/connector-nc.yaml"
    ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux reload"
    ```

11. **Create a Listener on localhost**

    ```yaml
    # listener-nc.yaml
    apiVersion: skupper.io/v2alpha1
    kind: Listener
    metadata:
      name: nc-listener
    spec:
      routingKey: ${TEST_ROUTING_KEY}
      host: localhost
      port: ${TEST_PORT}
    ```

    ```bash
    skupper system -n ${NAMESPACE} -p linux apply -f listener-nc.yaml
    skupper system -n ${NAMESPACE} -p linux reload
    ```

    Verify the listener port is bound by skrouterd:

    ```bash
    ss -tlnp | grep ${TEST_PORT}
    ```

12. **Start nc listener on the remote host** (in a separate terminal
    or backgrounded with output to file)

    ```bash
    ssh ${REMOTE_SSH_HOST} 'nc -l -k -p ${TEST_PORT} > ~/nc-received.txt &'
    ```

13. **Send a test message from localhost**

    ```bash
    echo "hello from ${LOCAL_SITE_NAME} via skupper VAN" | nc -w 2 localhost ${TEST_PORT}
    ```

14. **Verify the message arrived on the remote host**

    ```bash
    ssh ${REMOTE_SSH_HOST} 'cat ~/nc-received.txt'
    # Expected: hello from ${LOCAL_SITE_NAME} via skupper VAN
    ```

### Phase 6: Cleanup Test Resources (Keep Sites)

15. **Remove test artifacts** — preserves the sites and inter-site link.

    ```bash
    # Kill nc on remote
    ssh ${REMOTE_SSH_HOST} 'pkill -f "nc -l" || true'

    # Remove Connector
    ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux delete -f ~/connector-nc.yaml"

    # Remove Listener
    skupper system -n ${NAMESPACE} -p linux delete -f listener-nc.yaml

    # Reload both
    ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux reload"
    skupper system -n ${NAMESPACE} -p linux reload

    # Remove test data file
    ssh ${REMOTE_SSH_HOST} 'rm -f ~/nc-received.txt'
    ```

### Phase 7: Full Teardown (Optional)

To completely remove everything including sites:

16. **Stop both sites**

    ```bash
    ssh ${REMOTE_SSH_HOST} "skupper system -n ${NAMESPACE} -p linux stop"
    skupper system -n ${NAMESPACE} -p linux stop
    ```

17. **Clean up stale systemd state** (if needed)

    ```bash
    systemctl --user reset-failed skupper-${NAMESPACE}.service 2>/dev/null
    systemctl --user daemon-reload
    ssh ${REMOTE_SSH_HOST} 'systemctl --user reset-failed skupper-${NAMESPACE}.service 2>/dev/null; systemctl --user daemon-reload'
    ```

18. **Remove firewall rule** (if added)

    ```bash
    sudo firewall-cmd --zone=${FIREWALL_ZONE} --remove-port=45671/tcp --permanent
    sudo firewall-cmd --reload
    ```

## Known Issues

| Issue | Description | Impact |
|-------|-------------|--------|
| Link status "Pending / Not Operational" | On the Linux/systemd platform with skrouterd 3.4.2 + CLI 2.2.1, `skupper link status` may report the link as pending even when the TCP connection is established and data flows correctly. | Status display only — data plane works. Verify with `ss -tnp \| grep 45671` and the nc test. |
| `skupper system stop` may not fully stop service | The `stop` command removes the namespace but the systemd service may linger. | Run `systemctl --user reset-failed` and `daemon-reload` after stop. |
| Bootstrap container needed | `skupper system start` pulls a bootstrap container image even on Linux platform (for config generation). A container runtime (Podman/Docker) must be available. | One-time pull; the router itself runs natively. |

## Verification

- [ ] Both `skupper-${NAMESPACE}.service` units are `active (running)`
- [ ] `skrouterd` processes running on both hosts
- [ ] Ports 55671 and 45671 listening on interior site
- [ ] TCP ESTABLISHED connection on port 45671 between the hosts
- [ ] nc test message delivered end-to-end through the VAN

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-22 21:34 | v1.3 — Replaced environment-specific examples (ezhang-work, rhtevan-work) with generic placeholders (my-hub, my-edge) |
| 2026-07-22 21:21 | v1.2 — Added Invocation Example section (happy path + missing params) |
| 2026-07-22 21:11 | v1.1 — Added structured parameter definitions with binding-cues, usage hints, confirmation flow, and script argument mapping table |
| 2026-07-22 19:54 | v1.0 — Initial skill from verified two-site Linux/systemd setup procedure |
