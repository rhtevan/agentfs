---
name: crc-status
description: >
  crc status, check crc, crc health
metadata:
  author: agentfs
  version: "1.1.0"
  tags: [openshift, crc, status, console]
user-invocable: true
disable-model-invocation: false
---

# OpenShift Local Status & Banner Cleanup

Read-only health check for an OpenShift Local (CRC) cluster. Reports
cluster state, resource usage, and optionally removes the default
caution banner from the OpenShift web console. This skill **never
starts, stops, or modifies the CRC cluster itself** — it only
observes and reports.

## Prerequisites

- `crc` CLI installed
- `oc` CLI installed (for banner check/removal)

## Scope & Boundaries

> ⚠️ **This is a status-check skill. Do NOT start, stop, restart,
> or reconfigure CRC.** If the cluster is stopped, report that fact
> and stop. The user will decide whether to start it.

| In scope | Out of scope |
|----------|-------------|
| Report CRC VM and OpenShift state | Starting or stopping CRC |
| Report disk and cache usage | Changing CRC configuration |
| Check for and remove the console banner | Troubleshooting CRC failures |
| Report credentials | Installing or updating CRC |

## Steps

### Step 1 — Check CRC status

Run `crc status` to read the current cluster state.

```bash
crc status
```

### Step 2 — Evaluate state (decision point)

| CRC VM State | Agent Action |
|:------------:|-------------|
| **Running** | Proceed to Step 3 |
| **Stopped** | Report status to user. **STOP here. Do NOT proceed.** |
| **Starting / Stopping** | Report transitional state to user. **STOP here.** |
| **Error / other** | Report the full output to user. **STOP here.** |

> ⛔ **Hard gate:** Steps 3–6 require a running cluster. If CRC is
> not in `Running` state, the skill ends at Step 2. Do NOT attempt
> to start CRC or work around the stopped state.

### Step 3 — Get console credentials

Run `crc console --credentials` to retrieve the kubeadmin login
command.

```bash
crc console --credentials
```

### Step 4 — Log in as admin

Log in to the cluster using the credentials from Step 3:

```bash
oc login -u kubeadmin -p <password> https://api.crc.testing:6443
```

### Step 5 — Check for the caution banner

Look for the default `ConsoleNotification` resource:

```bash
oc get consolenotification security-notice 2>/dev/null
```

- If output contains a resource row → banner **exists**, proceed to Step 6
- If no output → banner **does not exist**, report to user and end

### Step 6 — Remove the banner (only if it exists)

Delete the banner resource:

```bash
oc delete consolenotification security-notice
```

Report the result to the user.

## Verification

Observational checks — verify these are true after execution:

- [ ] `crc status` output was presented to the user
- [ ] If CRC was stopped, no further steps were attempted
- [ ] If CRC was running, credentials were retrieved
- [ ] If banner existed, it was removed; if not, user was informed

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
