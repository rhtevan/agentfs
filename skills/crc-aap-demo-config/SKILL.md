---
name: crc-aap-demo-config
description: >
  Clone the aap-demo repo from GitHub and configure it for safe deployment on
  an existing OpenShift Local (CRC) cluster. Runs pre-flight checks against
  local system and CRC settings, then applies protective configuration to
  ~/.aap-demo/config to prevent aap-demo from silently overwriting CRC preset
  or resource allocations. Installs the aap-demo CLI and prepares the
  pull secret.
metadata:
  tags: [openshift, crc, aap-demo, configuration, safety, preflight]
---

# CRC AAP Demo Configuration

Clone the `aap-demo` repository and safely configure it for deployment on an
existing OpenShift Local (CRC) cluster — without disrupting CRC's preset,
resource allocations, or other settings.

## Why This Skill Exists

`aap-demo` was designed for MicroShift and makes assumptions that are
**dangerous on an existing OpenShift CRC**:

| Risk | What aap-demo does | Impact |
|------|-------------------|--------|
| **Preset override** | If CRC preset is `openshift`, defaults to `microshift` and runs `crc config set preset microshift` | Destroys your OpenShift VM on next `crc start` |
| **Resource downgrade** | Sets CPUs=8, memory=16384, disk=100 via `crc config set` | Downgrades your VM resources on next `crc start` |
| **CoreDNS modification** | Patches `dns-default` ConfigMap in `openshift-dns` | Mostly harmless but unexpected |
| **Ingress CA trust** | Adds cluster CA to host trust store via `sudo update-ca-trust` | Requires sudo, modifies host PKI |

This skill detects these conflicts and applies protective configuration
**before** any `aap-demo` command is run.

## Prerequisites

- OpenShift Local (CRC) installed and configured
- CRC cluster running or stopped (must exist — `crc status` returns a known state)
- `git` installed
- Internet access (to clone the repo)

## Steps

### Part 1 — Clone the Repository

1. **Choose a target directory** for the clone (e.g., `~/app/playground/aap-demo`
   or any preferred location).

2. **Clone the repo**:
   ```bash
   git clone https://github.com/RedHatOfficial/aap-demo.git <target-dir>
   cd <target-dir>
   ```
   If the directory already exists and contains the repo, skip the clone:
   ```bash
   git -C <target-dir> remote get-url origin 2>/dev/null | grep -q 'aap-demo' && echo 'Already cloned'
   ```

### Part 2 — Pre-Flight Checks

3. **Check CRC exists and get current state**:
   ```bash
   crc status --output json 2>/dev/null
   ```
   Extract `crcStatus` (Running, Stopped, Unknown) and `preset` from the JSON.
   If `crcStatus` is `Unknown`, CRC has no VM — warn the user that `aap-demo create`
   will create a new one (this is safe).

4. **Capture current CRC resource configuration**:
   ```bash
   crc config view
   ```
   Record the values of: `cpus`, `memory`, `disk-size`, `preset`,
   `enable-cluster-monitoring`, `host-network-access`, `kubeadmin-password`,
   `pull-secret-file`.

5. **Compare with aap-demo defaults**:

   | Setting | aap-demo default | Source |
   |---------|-----------------|--------|
   | Preset | `microshift` | `includes/crc-create.sh` line 175 |
   | CPUs | `8` | `includes/crc-create.sh` line 199 |
   | Memory | `16384` (16 GB) | `includes/crc-create.sh` line 200 |
   | Disk | `100` GB | `includes/crc-create.sh` line 201 |
   | PV Size | `50` GB | `includes/crc-create.sh` line 202 |

   **Report conflicts** — any case where the aap-demo default would downgrade
   or change a current CRC setting:

   ```
   ⚠️  CONFLICTS DETECTED:

   | Setting | Current CRC | aap-demo default | Action |
   |---------|-------------|-----------------|--------|
   | preset  | openshift   | microshift      | PROTECT — would destroy VM |
   | cpus    | 40          | 8               | PROTECT — would downgrade |
   | memory  | 49152       | 16384           | PROTECT — would downgrade |
   | disk    | 240         | 100             | PROTECT — would downgrade |
   ```

   If no conflicts are found (e.g., CRC doesn't exist yet), report that and
   skip Part 3.

6. **Check CLI dependencies**:
   ```bash
   command -v kubectl && echo '✅ kubectl' || echo '❌ kubectl'
   command -v ansible-playbook && echo '✅ ansible' || echo '❌ ansible'
   command -v jq && echo '✅ jq' || echo '❌ jq'
   command -v python3 && echo '✅ python3' || echo '❌ python3'
   command -v helm && echo '✅ helm' || echo '❌ helm'
   ```
   Report missing dependencies. `install.sh` will auto-install `kubectl`,
   `ansible`, `jq`, and `python3` but the user should be informed.

7. **Check pull secret availability**:
   Look for a pull secret in these locations (in order):
   ```
   ~/.aap-demo/pull-secret.txt
   ~/.aap-demo/pull-secret.json
   ~/Downloads/pull-secret.txt
   ~/Downloads/pull-secret*.txt
   ```
   If the CRC cluster is running, also compare file credentials against the
   cluster's pull secret to find the matching file:
   ```bash
   oc get secret pull-secret -n openshift-config \
     -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/crc-pull-secret.json
   ```
   Compare each candidate file's `auths` against the cluster's auths to
   identify which file matches.

### Part 3 — Apply Protective Configuration

8. **Create `~/.aap-demo/config`** with protective values.

   Read the current CRC settings and write them to the config file so
   `aap-demo.sh`'s config loader (line 58-66) sets them **before**
   `crc-create.sh` applies defaults. The config loader only sets variables
   that are not already in the environment:
   ```bash
   if [ -z "${!key+x}" ]; then
     export "$key=$value"
   fi
   ```

   Generate the config:
   ```bash
   mkdir -p ~/.aap-demo
   cat > ~/.aap-demo/config << EOF
   CRC_PRESET=$(crc config get preset 2>/dev/null | awk '{print $NF}')
   CRC_CPUS=$(crc config get cpus 2>/dev/null | awk '{print $NF}')
   CRC_MEMORY=$(crc config get memory 2>/dev/null | awk '{print $NF}')
   CRC_DISK=$(crc config get disk-size 2>/dev/null | awk '{print $NF}')
   CRC_PV_SIZE=50
   EOF
   ```

   If `~/.aap-demo/config` already exists, **merge** — only add keys that
   are missing, never overwrite existing values.

9. **Copy the pull secret** (if not already in place):
   ```bash
   cp <matching-pull-secret-file> ~/.aap-demo/pull-secret.txt
   ```
   Skip if `~/.aap-demo/pull-secret.txt` already exists.

### Part 4 — Install the CLI

10. **Run the installer**:
    ```bash
    cd <target-dir>
    ./install.sh
    ```
    This creates a symlink at `~/.local/bin/aap-demo` → `<target-dir>/aap-demo.sh`
    and installs shell completions. It does **not** touch CRC.

11. **Verify the CLI is accessible**:
    ```bash
    aap-demo help
    ```
    If `~/.local/bin` is not in `$PATH`, inform the user to add it.

## How the Protection Works

The protection relies on how `aap-demo.sh` loads its config (lines 58-66):

```bash
if [ -f "$AAP_DEMO_CONFIG" ]; then
  while IFS='=' read -r key value; do
    if [ -z "${!key+x}" ]; then   # only set if NOT already set
      export "$key=$value"
    fi
  done < "$AAP_DEMO_CONFIG"
fi
```

Then `includes/crc-create.sh` uses `${CRC_CPUS:-8}` syntax — if the variable
is already set (from the config file), the default is ignored.

For the preset, the protection works because line 168 checks the config file
for `CRC_PRESET=`. If found, it skips the hardcoded `microshift` default.

### Call Chain to the Dangerous Code

```
aap-demo deploy  (or create, redeploy-all)
  → cmd_deploy()          aap-demo.sh:1929
    → cmd_create()         aap-demo.sh:1905  (if no cluster exists)
      → bash crc-create.sh  includes/crc-create.sh
        → line 165: preset override check  ⚠️
        → line 219: crc config set cpus    ⚠️
        → line 220: crc config set memory  ⚠️
        → line 221: crc config set disk    ⚠️
```

### Safe vs Dangerous Entry Points

| Command | Calls crc-create.sh? | Risk |
|---------|:-------------------:|------|
| `aap-demo deploy` (CRC running) | ❌ | Safe — skips create |
| `aap-demo deploy` (CRC stopped) | ❌ | Safe — calls `_start_crc_cluster` only |
| `aap-demo deploy` (no CRC) | ✅ | ⚠️ Triggers `cmd_create` |
| `aap-demo create` (CRC running) | ✅ but exits | Safe — exits at line 153 |
| `aap-demo create` (CRC stopped) | ✅ | ⚠️ Proceeds past running check |
| `aap-demo create` (no CRC) | ✅ | ⚠️ Full create flow |
| `aap-demo start` | ❌ | Safe — sources for CoreDNS only |
| `aap-demo redeploy-all` | ✅ | 🔴 Destroys then creates |

## Verification

- [ ] Repo cloned and accessible
- [ ] `~/.aap-demo/config` exists with `CRC_PRESET`, `CRC_CPUS`, `CRC_MEMORY`, `CRC_DISK` matching current CRC values
- [ ] `~/.aap-demo/pull-secret.txt` exists and matches CRC cluster credentials
- [ ] `aap-demo help` works (CLI installed)
- [ ] `crc config view` unchanged from pre-flight values

## Post-Configuration

After this skill completes, the user can safely run:

```bash
aap-demo deploy    # Deploy AAP to existing CRC
aap-demo status    # Check deployment status
aap-demo diagnose  # Health check
```

For the full aap-demo workflow and troubleshooting, refer to the
`.claude/skills/aap-demo/SKILL.md` skill in the aap-demo repository.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-16 11:11 | v1.0 — Initial skill: clone, pre-flight, protective config, CLI install |
