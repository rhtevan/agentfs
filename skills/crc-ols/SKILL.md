---
name: crc-ols
description: >
  install ols, list ols providers, add ols provider,
  switch ols provider, switch ols model, remove ols provider,
  rotate ols key, ols credential status
argument-hint: "install | list | add-provider | switch-provider PROVIDER MODEL | remove-provider PROVIDER | rotate-key PROVIDER"
metadata:
  author: agentfs
  version: "3.5.0"
  model-tier: T3
  tags: [openshift, crc, lightspeed, ols, llm, provider-management, credentials, rotation]
  related_skills: [gcp-vertex-models, goose-corp-provider, crc-ctl, skupper-model-provider]
user-invocable: true
disable-model-invocation: false
---

# OpenShift Lightspeed on CRC — Multi-Provider Management

Install OpenShift Lightspeed on an OpenShift Local (CRC) cluster, configure one or more LLM providers, switch between them, and apply CRC-specific tunings.


## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Usage

| Operation | Script | Description |
|-----------|--------|-------------|
| `install` (or no args) | `scripts/install.sh [--dry-run]` | Install OLS operator, apply CRC fix, configure first provider, create OLSConfig. Idempotent; never mutates an existing OLSConfig |
| `list` | `scripts/list.sh` | Show all providers, models, active default, status, and credential health |
| `add-provider` | Prose (agent-orchestrated) | Add a provider: create secret, patch OLSConfig, verify rollout |
| `switch-provider` | `scripts/switch-provider.sh PROVIDER MODEL` | Switch active provider+model, wait for reconciliation, verify |
| `remove-provider` | `scripts/remove-provider.sh PROVIDER [--delete-secret]` | Remove a provider (cannot remove the active one — switch first) |
| `rotate ols key` | `scripts/rotate-key.sh PROVIDER [--from-keyring] [--create] [--dry-run]` | Rotate or create a provider's credential: validate → write → reload → verify in-pod |
| `ols credential status` | `scripts/list.sh` | Credential age vs rotation policy + live in-pod auth probe per provider |

**Provider-Model relationship:** Each provider has one or more models.
OLS requires both `defaultProvider` and `defaultModel` to be set
together. Switching means selecting a provider AND one of its models
— you cannot switch to a model without specifying which provider
serves it.

---

## Prerequisites

- OpenShift Local (CRC) running (`crc status` shows Running)
- Logged in as `kubeadmin` (`oc whoami` confirms)
- For each provider, appropriate credentials (see Provider Types Reference below)

---

## Operation: `install`

Full installation of the Lightspeed Operator and initial provider configuration.

**Use the script.** It performs every phase below, is idempotent, and refuses
to mutate an existing OLSConfig:

```bash
# ALWAYS dry-run first — it reports the delta and emits a result signal.
bash scripts/install.sh --dry-run --context crc-admin
#   DRY_RUN_RESULT=CONVERGED → already installed, nothing to do
#   DRY_RUN_RESULT=PENDING   → run again without --dry-run

bash scripts/install.sh --context crc-admin
```

The phases below document what the script does and how to perform each step by
hand when debugging a partial install.

### Phase 0 — Resolve provider settings (never hand-edit placeholders)

`install.sh` resolves the GCP project, location, model, and service-account key
from the **`gcp-vertex-models`** skill. Nothing is hardcoded and no placeholder
is ever sent to the cluster — the script aborts if one appears.

```bash
GVM=~/.agents/skills/gcp-vertex-models/scripts

# Model + region: highest-ranked AVAILABLE model (opus > sonnet > haiku, newest).
# Prints "<model> <region>" on stdout; diagnostics go to stderr.
read -r MODEL LOCATION < <(bash $GVM/models.sh default 2>/dev/null)

# Project: recorded in the probe cache by the last probe run.
PROJECT=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser(
  '~/.cache/gcp-vertex-models/models.json')))['project'])")

# SA key: filters to type:service_account and rejects the default compute SA.
SA_KEY=$(bash $GVM/select-sa.sh --project "$PROJECT")

echo "$PROJECT / $LOCATION / $MODEL"
echo "$SA_KEY"
```

If the cache is missing or stale, refresh it first: `bash $GVM/probe-models.sh`.

> **Why not a placeholder:** the OLSConfig CRD does **not** validate `projectID`,
> `location`, or the model name. A placeholder produces a provider that reports
> `Ready` and then fails with a runtime 404 on the first query. `install.sh`
> rejects any value matching `YOUR_*`, `CHANGEME`, or `<...>`.

### Phase 1 — Install the Lightspeed Operator

#### Step 1: Create the namespace, OperatorGroup, and Subscription

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-lightspeed
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-lightspeed-operator
  namespace: openshift-lightspeed
spec:
  targetNamespaces:
    - openshift-lightspeed
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lightspeed-operator
  namespace: openshift-lightspeed
spec:
  channel: stable
  name: lightspeed-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

#### Step 2: Wait for the operator to install

```bash
oc get csv -n openshift-lightspeed -w
```

Wait until the `PHASE` column shows `Succeeded`.

#### ⚠️ CRC Fix — Missing `metrics-client-ca` ConfigMap

CRC disables the monitoring stack, so the operator will crash with:

```
ConfigMap "metrics-client-ca" not found in namespace "openshift-monitoring"
```

**Fix:** Create the missing ConfigMap manually by extracting the CA from the kube-apiserver:

```bash
# Extract the CA bundle
oc get configmap client-ca -n openshift-kube-apiserver \
  -o jsonpath='{.data.ca-bundle\.crt}' > /tmp/client-ca-bundle.crt

# Create the missing ConfigMap (key MUST be 'client-ca.crt', not 'ca-bundle.crt')
oc create configmap metrics-client-ca \
  --from-file=client-ca.crt=/tmp/client-ca-bundle.crt \
  -n openshift-monitoring
```

> **Critical:** The key name must be exactly `client-ca.crt`. Using a different key name (e.g., `ca-bundle.crt`) will cause the operator to remain stuck.

After creating the ConfigMap, the operator pod should start. Verify:

```bash
oc get csv -n openshift-lightspeed
# PHASE should show Succeeded
```

### Phase 2 — Configure LLM Credentials

See [Provider Types Reference](#provider-types-reference) below for the credential format required by each provider type.

**Example — Google Vertex AI Anthropic:**

First, select the correct SA key (rejects the default compute SA automatically).
Use the `$PROJECT` resolved in [Phase 0](#phase-0--resolve-provider-settings-never-hand-edit-placeholders) —
passing a literal placeholder silently disables the `--project` filter:
```bash
SA_KEY=$(bash ~/.agents/skills/gcp-vertex-models/scripts/select-sa.sh \
  --project "$PROJECT")
```

Then create the secret using the selected key:
```bash
oc create secret generic llmcreds \
  --from-file=gcp-service-account.json="$SA_KEY" \
  -n openshift-lightspeed
```

> **Tip — Choosing the right GCP service account:**
> If a dedicated service account (e.g., `vertex-ai-sa`) returns permission errors like
> `"Permission 'aiplatform.endpoints.predict' denied"`, fix the SA's IAM permissions —
> do **not** fall back to the Compute Engine default service account (it holds
> `roles/editor`, which is over-privileged for Vertex AI workloads). Grant the
> dedicated SA the required role and verify:
> ```bash
> # Grant the role (if not already)
> gcloud projects add-iam-policy-binding YOUR_PROJECT \
>   --member="serviceAccount:YOUR_SA_EMAIL" \
>   --role="roles/aiplatform.user"
>
> # Test access
> curl -s -X POST \
>   "https://aiplatform.googleapis.com/v1/projects/YOUR_PROJECT/locations/YOUR_LOCATION/publishers/anthropic/models/YOUR_MODEL:rawPredict" \
>   -H "Authorization: Bearer $(gcloud auth print-access-token --impersonate-service-account=YOUR_SA_EMAIL)" \
>   -H "Content-Type: application/json" \
>   -d '{"anthropic_version":"vertex-2023-10-16","messages":[{"role":"user","content":"hello"}],"max_tokens":50}'
> ```

### Phase 3 — Create the OLSConfig Custom Resource

Uses `$PROJECT`, `$LOCATION`, and `$MODEL` from
[Phase 0](#phase-0--resolve-provider-settings-never-hand-edit-placeholders).
Note the heredoc is **unquoted** (`<<EOF`) so the variables expand:

```bash
oc apply -f - <<EOF
apiVersion: ols.openshift.io/v1alpha1
kind: OLSConfig
metadata:
  name: cluster
spec:
  llm:
    providers:
    - name: google-anthropic
      type: google_vertex_anthropic
      credentialsSecretRef:
        name: llmcreds
      credentialKey: gcp-service-account.json
      googleVertexAnthropicConfig:
        projectID: $PROJECT
        location: $LOCATION
      models:
      - name: $MODEL
  ols:
    defaultModel: $MODEL
    defaultProvider: google-anthropic
    maxIterations: 20
EOF
```

> **Important — `maxIterations: 20`:** This is a required tuning for the Vertex AI Anthropic provider. See [Tunings](#tunings-for-vertex-ai-anthropic-provider) below.

### Phase 4 — Verify deployment

```bash
# Wait for all pods to be Ready
oc get pods -n openshift-lightspeed -w

# Check OLSConfig status
oc get olsconfig cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Should return: True

# Test health
oc exec deployment/lightspeed-app-server -n openshift-lightspeed \
  -c lightspeed-service-api -- curl -s http://localhost:8443/healthz -k
# Should return: {"alive":true}
```

### Phase 5 — Trust a private CA (only for providers behind an internal CA)

Skip this phase unless a provider endpoint is served by a certificate your
cluster does not already trust (typical for corporate-internal model
endpoints). Symptom: the app-server can resolve and reach the host, but TLS
verification fails.

**Diagnose first — confirm it is CA trust and not network:**

```bash
# Without -k: expect HTTP=000 and "exit code 60" (certificate verify failed)
oc exec deployment/lightspeed-app-server -n openshift-lightspeed \
  -c lightspeed-service-api -- \
  curl -s -o /dev/null -w 'HTTP=%{http_code}\n' --connect-timeout 10 \
  https://YOUR_PROVIDER_HOST/v1/models

# With -k: HTTP=200 proves the endpoint is reachable and only trust is missing
oc exec deployment/lightspeed-app-server -n openshift-lightspeed \
  -c lightspeed-service-api -- \
  curl -sk -o /dev/null -w 'HTTP=%{http_code}\n' --connect-timeout 10 \
  https://YOUR_PROVIDER_HOST/v1/models
```

**Identify the root CA that validates the chain.** Do not guess — test each
candidate anchor until one verifies:

```bash
openssl s_client -connect YOUR_PROVIDER_HOST:443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer

for ca in /etc/pki/ca-trust/source/anchors/*.pem; do
  if openssl s_client -connect YOUR_PROVIDER_HOST:443 -CAfile "$ca" \
       </dev/null 2>/dev/null | grep -q 'Verify return code: 0'; then
    echo "ANCHOR: $ca"
  fi
done
```

**Apply the anchor.** The ConfigMap key MUST be `ca.crt`.

```bash
oc create configmap corp-ca \
  --from-file=ca.crt=/path/to/your-root-ca.pem \
  -n openshift-lightspeed

oc patch olsconfig cluster --type=merge \
  -p '{"spec":{"ols":{"additionalCAConfigMapRef":{"name":"corp-ca"}}}}'

oc rollout status deployment/lightspeed-app-server -n openshift-lightspeed --timeout=240s
```

> **`additionalCAConfigMapRef` MERGES — it does not replace.**
> The operator mounts your ConfigMap as a *separate* `additional-ca` volume at
> `/etc/certs/ols-additional-ca`, leaving the existing `openshift-ca` volume
> (backed by `kube-root-ca.crt`) untouched. An init step concatenates both into
> `/etc/certs/cert-bundle/ols.pem`, which `SSL_CERT_FILE` points at.
> **Put ONLY your private root CA in the ConfigMap.** Adding the cluster certs
> "to be safe" silently duplicates them in the merged bundle.

**Verify — the certificate count must rise by exactly the number you added:**

```bash
oc exec deployment/lightspeed-app-server -n openshift-lightspeed \
  -c lightspeed-service-api -- bash -c '
    echo -n "merged bundle: "; grep -c "BEGIN CERTIFICATE" /etc/certs/cert-bundle/ols.pem
    echo -n "provider TLS:  HTTP="
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
      https://YOUR_PROVIDER_HOST/v1/models; echo
    echo -n "cluster API:   HTTP="
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
      https://kubernetes.default.svc/version; echo'
```

Both `HTTP=200`. The cluster API check is a regression guard: it proves the
merge did not displace the cluster's own trust anchors.

**Rollback:**

```bash
oc patch olsconfig cluster --type=json \
  -p '[{"op":"remove","path":"/spec/ols/additionalCAConfigMapRef"}]'
```

---

## Operation: `add-provider`

Add an additional LLM provider to an existing OpenShift Lightspeed deployment.

**Use the script.** It performs all five steps below, guards against the two
failure modes that break the app-server (shared secret, wrong model name), and
is idempotent:

```bash
bash scripts/add-provider.sh NAME --type TYPE --model MODEL --url URL \
  [--from-keyring] [--set-default] --dry-run --context crc-admin
#   DRY_RUN_RESULT=CONVERGED → provider already exists
#   DRY_RUN_RESULT=PENDING   → re-run without --dry-run
```

Worked example (an openai-compatible endpoint whose key is in the keyring):

```bash
bash scripts/add-provider.sh corp-models \
  --type openai \
  --url https://models.corp.redhat.com/oai/v1 \
  --model Qwen3.8-27B-FP8 \
  --from-keyring --set-default --context crc-admin
```

The steps below document what the script does, for manual debugging.

### Step 1: Identify the provider type

```bash
bash scripts/add-provider.sh --help
```

Ask the user for:
- **Provider type** — one of: `openai`, `google_vertex_anthropic`, `azure_openai`, `watsonx`, `bam`
- **Provider name** — a unique identifier (e.g., `maas-litellm`, `my-openai`)
- **URL** — required for `openai` type (the base API URL, e.g., `https://api.openai.com/v1`)
- **Models** — list of model names to configure
- **Credentials** — API key or service account key

### Step 2: Create the credentials secret

Create a **separate** secret for the new provider (do NOT modify existing secrets).

**Preferred — scripted.** `rotate-key.sh` validates the key against the live
endpoint *before* writing, so a bad key never reaches the cluster. The key flows
keyring/prompt → `mktemp` (mode 600) → `oc` → `shred`, and is never printed:

```bash
# Key already in GNOME Keyring (stored by goose-corp-provider/scripts/store-key.sh):
bash scripts/rotate-key.sh PROVIDER --from-keyring --create --context crc-admin

# Otherwise prompt (no echo, not stored in shell history):
bash scripts/rotate-key.sh PROVIDER --create --context crc-admin
```

The provider must already be in the OLSConfig — `rotate-key.sh` resolves the
secret name, credential key, URL, and model from the CRD rather than taking
them as arguments. `add-provider.sh --from-keyring` sequences this for you.

The manual equivalent is below.

**⚠️ Security: Never pass API keys as command-line arguments or paste them into an AI chat session.** Use the file-based approach below to avoid keys leaking into shell history, process listings, or conversation logs.

**For OpenAI-compatible providers (including MaaS/LiteLLM):**

The user should run these commands themselves in a terminal:
```bash
# Write the API key to a temporary file (no trailing newline)
echo -n 'PASTE_YOUR_API_KEY_HERE' > /tmp/llm-key.txt

# Create the secret from the file
oc create secret generic NEW_SECRET_NAME \
  --from-file=apitoken=/tmp/llm-key.txt \
  -n openshift-lightspeed

# Remove the temporary file immediately
rm /tmp/llm-key.txt
```

> **Why file-based?** Using `--from-literal=` can introduce trailing whitespace/newline issues and exposes the key in shell history and `/proc` process listings. The file-based approach (`--from-file=`) avoids both problems.

> **Note on credential key naming:** The `credentialKey` field in the OLSConfig tells the operator which key to read from the secret. The default is `apitoken` if not specified. Use a clear key name and reference it in the OLSConfig.

**For Google Vertex AI Anthropic:**
```bash
oc create secret generic NEW_SECRET_NAME \
  --from-file=gcp-service-account.json=/path/to/your-sa-key.json \
  -n openshift-lightspeed
```

> **Troubleshooting 401 errors:** If the health check fails with `401 Unauthorized` after creating the secret, the most common cause is extra whitespace or newline characters in the key. Delete the secret (`oc delete secret NAME -n openshift-lightspeed`) and recreate it using the file-based approach above, ensuring `echo -n` (no trailing newline) is used.

### Step 3: Get the current providers configuration

```bash
oc get olsconfig cluster -o jsonpath='{.spec.llm.providers[*].name}'

# Or let the script check for you — it exits CONVERGED if the name is taken
# and fails fast if the secret name collides with another provider:
bash scripts/add-provider.sh NAME --type TYPE --model MODEL --url URL --dry-run
```

This shows existing provider names to avoid conflicts.

### Step 4: Patch the OLSConfig to add the new provider

Use a JSON patch to append the new provider to the existing providers array.
`add-provider.sh` builds this patch for you and backs up the OLSConfig first:

```bash
bash scripts/add-provider.sh NAME --type TYPE --model MODEL --url URL --context crc-admin
```

The hand-written equivalent:

**Example — Adding an OpenAI-compatible provider:**
```bash
oc patch olsconfig cluster --type=json -p '[
  {
    "op": "add",
    "path": "/spec/llm/providers/-",
    "value": {
      "name": "PROVIDER_NAME",
      "type": "openai",
      "url": "PROVIDER_URL",
      "credentialsSecretRef": {
        "name": "NEW_SECRET_NAME"
      },
      "credentialKey": "apitoken",
      "models": [
        {"name": "MODEL_1"},
        {"name": "MODEL_2"}
      ]
    }
  }
]'
```

**Example — Adding a Google Vertex AI Anthropic provider:**
```bash
oc patch olsconfig cluster --type=json -p '[
  {
    "op": "add",
    "path": "/spec/llm/providers/-",
    "value": {
      "name": "PROVIDER_NAME",
      "type": "google_vertex_anthropic",
      "credentialsSecretRef": {
        "name": "NEW_SECRET_NAME"
      },
      "credentialKey": "gcp-service-account.json",
      "googleVertexAnthropicConfig": {
        "projectID": "YOUR_GCP_PROJECT",
        "location": "YOUR_LOCATION"
      },
      "models": [
        {"name": "MODEL_NAME"}
      ]
    }
  }
]'
```

### Step 5: Verify the provider was added

```bash
# Scripted: providers, models, default, status, and credential health
bash scripts/list.sh --context crc-admin
```

```bash
# List all providers
oc get olsconfig cluster -o jsonpath='{range .spec.llm.providers[*]}{.name}{"\t"}{.type}{"\t"}{range .models[*]}{.name}{", "}{end}{"\n"}{end}'

# Wait for pods to restart and stabilize
oc get pods -n openshift-lightspeed -w

# Check overall status
oc get olsconfig cluster -o jsonpath='{.status.overallStatus}'
# Should return: Ready
```

---

## Operation: `list`

```bash
bash ~/.agents/skills/crc-ols/scripts/list.sh --context crc-admin
```

Shows all configured providers with type, URL, secret, models, the
active default provider+model, and overall OLS status.

For Skupper-backed providers (URLs containing `listener-`), the
script also probes the live `/v1/models` endpoint via the CRC router
pod and compares against the configured model names. Possible results:

| Status | Meaning |
|:------:|---------|
| ✅ Live | Configured model matches what the backend serves |
| ❌ MISMATCH | Configured model not found — wrong profile or model name |
| ⚠️ UNREACHABLE | Backend not responding — VAN down or model stopped |

---

## Operation: `switch-provider`

Switch the active provider and its model. Both PROVIDER and MODEL
are required — models belong to providers.

```bash
bash ~/.agents/skills/crc-ols/scripts/switch-provider.sh PROVIDER MODEL --context crc-admin
```

The script validates the provider exists, patches `defaultProvider`
and `defaultModel`, waits for OLS to reconcile to `Ready`, and
reports the result.

To see available providers and their models first, run `list`.

---

## Operation: `remove-provider`

Remove a provider from OLSConfig. Cannot remove the active default —
switch to another provider first.

```bash
bash ~/.agents/skills/crc-ols/scripts/remove-provider.sh PROVIDER --context crc-admin
# With secret cleanup:
bash ~/.agents/skills/crc-ols/scripts/remove-provider.sh PROVIDER --delete-secret --context crc-admin
```

The script finds the provider's index, verifies it's not the default,
removes it via JSON patch, and optionally deletes the credentials secret.

---

## Provider Types Reference

| Type | `type` value | URL Required | Credential Format | Extra Config |
|------|-------------|-------------|-------------------|-------------|
| OpenAI / OpenAI-compatible (LiteLLM, MaaS, vLLM) | `openai` | ✅ Yes | API key in secret (`--from-file=apitoken=FILE`) | None |
| Self-hosted via Skupper (Granite, vLLM) | `openai` | ✅ Yes (in-cluster) | Dummy key (`no-key-required`) | Requires `skupper-model-provider` VAN running |
| Google Vertex AI Anthropic | `google_vertex_anthropic` | ❌ No | GCP SA key JSON (`--from-file=gcp-service-account.json=FILE`) | `googleVertexAnthropicConfig` (projectID, location) |
| Azure OpenAI | `azure_openai` | ✅ Yes | API key in secret | `azureOpenAIConfig` |
| WatsonX | `watsonx` | ✅ Yes | API key in secret | None |
| BAM | `bam` | ✅ Yes | API key in secret | None |

### Credential Security Notes

- **Never commit credentials** to version control — this skill uses placeholder values only
- Each provider should use a **separate secret** for isolation
- Secret names should be descriptive (e.g., `llmcreds`, `maas-llmcreds`)
- The `credentialKey` in OLSConfig must match the key name used when creating the secret

### Self-Hosted Models via Skupper

Models served by `hosted-model-ctl` on remote GPU hosts can be exposed to the CRC cluster through the Skupper VAN (managed by `skupper-model-provider`). These appear as in-cluster OpenAI-compatible endpoints.

**How it works:**
1. `skupper-model-provider` creates a Listener + Service inside the CRC namespace (e.g., `listener-model-api-rhel-ai.model-provider-crc:9000`)
2. Traffic is routed over the Skupper link to the remote host's model container
3. OLS connects to this in-cluster service as an `openai` type provider

**Naming convention:** Use `skupper-model-<host>` (e.g., `skupper-model-rhel`,
`skupper-model-rhtevan`). Each provider needs its own credentials secret —
two providers sharing the same `credentialsSecretRef` causes a Kubernetes
duplicate volume mount error.

**Setup pattern:**
```bash
# 1. Create a dummy credentials secret (self-hosted models have no auth)
echo -n 'no-key-required' > /tmp/llm-key.txt
oc create secret generic skupper-model-rhel-llmcreds \
  --from-file=apitoken=/tmp/llm-key.txt \
  -n openshift-lightspeed
rm /tmp/llm-key.txt

# 2. Add provider pointing at the Skupper in-cluster service
oc patch olsconfig cluster --type=json -p '[
  {
    "op": "add",
    "path": "/spec/llm/providers/-",
    "value": {
      "name": "skupper-model-rhel",
      "type": "openai",
      "url": "http://listener-model-api-rhel-ai.model-provider-crc:9000/v1",
      "credentialsSecretRef": {"name": "skupper-model-rhel-llmcreds"},
      "credentialKey": "apitoken",
      "models": [{"name": "ibm-granite/granite-4.2-8b-fp8"}]
    }
  }
]'
```

**Dependencies:** Requires `skupper-model-provider` VAN to be running
(`start skupper`) and a model started via `hosted-model-ctl` on the target host.

---

## Tunings for Vertex AI Anthropic Provider

### Tuning: maxIterations

**Problem:** When `maxIterations` is set to the default of `5`, and the model uses tools through all 5 iterations, the OLS code enters a "final round" path that passes `tool_choice="none"` to the LLM. This parameter is valid for OpenAI but **incompatible with the Anthropic API via Vertex AI**. The Anthropic SDK interprets the string `"none"` as a tool name and returns:

```
Tool 'none' not found in provided tools
```

**Symptoms:**
- Simple queries (e.g., "hello") work fine — they finish without using tools and never hit the final round
- Complex cluster-related queries fail with: `[LLM Backend] An error occurred during LLM invocation`
- Logs show the model successfully completes 4 tool iterations, then crashes on the 5th

**Root cause:** In `llm_execution_agent.py`, the final-round code path:
```python
# is_final_round = True when i == max_rounds
llm = self.bare_llm.bind_tools(tools_map, tool_choice="none")
```
The `langchain-google-vertexai` adapter passes `tool_choice="none"` unmodified to the Anthropic SDK, which expects object format (`{"type": "auto"}`) not string format.

**Fix:** Set `maxIterations` to a high value (e.g., `20`) so the model naturally finishes its tool loop before the forced final round:

```bash
oc patch olsconfig cluster --type=merge -p '{"spec":{"ols":{"maxIterations": 20}}}'
```

With `maxIterations: 20`, the model will finish with `model_finished_without_tools` at around iteration 5–6 and never encounter the buggy `tool_choice="none"` final-round code path.

### Tuning: introspectionEnabled (Optional)

If you do **not** want Lightspeed to interact with the hosting cluster at all (pure documentation Q&A mode), you can disable the built-in MCP server:

```bash
oc patch olsconfig cluster --type=merge -p '{"spec":{"ols":{"introspectionEnabled": false}}}'
```

This removes the `openshift-mcp-server` sidecar container entirely. To re-enable:

```bash
oc patch olsconfig cluster --type=merge -p '{"spec":{"ols":{"introspectionEnabled": true}}}'
```

> **Note:** The field `clusterInteraction.enabled` does NOT exist in the CRD and will be silently ignored. The correct field is `introspectionEnabled`.

---

## Verification

After completing any operation, verify through the OpenShift web console:

1. Open the OpenShift web console
2. Click the Lightspeed chat icon (bottom-right)
3. Test a simple query: `hello` — should respond immediately
4. Test a cluster query: `list all pods in the openshift-lightspeed namespace` — should use MCP tools and return pod information
5. If the cluster query works without the `[LLM Backend]` error, the configuration is correct

## Quick Reference

| Setting | Default | Recommended for Vertex AI | Purpose |
|---|---|---|---|
| `maxIterations` | `5` | `20` | Avoid `tool_choice="none"` bug on final round |
| `introspectionEnabled` | `true` (omitted) | `true` or `false` | Enable/disable cluster MCP server |
| Secret key name | — | `gcp-service-account.json` | Must match `credentialKey` in OLSConfig |
| ConfigMap key (CRC fix) | — | `client-ca.crt` | Must be this exact key name, not `ca-bundle.crt` |


## Gotchas

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `metrics-client-ca` ConfigMap not found | CRC disables monitoring stack | Create manually from kube-apiserver CA; key MUST be `client-ca.crt` (not `ca-bundle.crt`) |
| 401 Unauthorized after secret creation | Whitespace/newline in API key via `--from-literal` | Use `echo -n` + `--from-file=` approach |
| Duplicate volume mount error | Two providers sharing the same `credentialsSecretRef` | Each provider MUST use a separate secret |
| `tool_choice="none"` error (Vertex AI) | OLS final-round code sends `tool_choice="none"` incompatible with Anthropic SDK | Set `maxIterations: 20` to avoid the final-round code path |
| "failed to parse grammar" (llama.cpp) | OLS sends `response_format: json_schema` which llama-server cannot parse | Set `introspectionEnabled: false` — basic Q&A works, tool-use does not |
| `clusterInteraction.enabled` silently ignored | Field does NOT exist in the CRD | Use `introspectionEnabled` instead |
| `defaultModel` mismatch goes undetected | OLSConfig CRD does not validate model exists under the provider — mismatch causes runtime 404 | `switch-provider.sh` validates model exists under provider before patching |
| Provider unreachable: in-pod `curl` → `HTTP=000`, `exit code 60` | Provider served by a private/corporate CA absent from the cluster trust bundle. `curl -k` → 200 confirms it is trust, not network | Add the root CA via `spec.ols.additionalCAConfigMapRef` — see [Phase 5](#phase-5--trust-a-private-ca-only-for-providers-behind-an-internal-ca) |
| Rotation backup leaks the old key | `rotate-key.sh` writes `/tmp/<secret>.bak.<ts>.yaml` (mode 600) containing the PREVIOUS key, and `/tmp` survives until reboot or the 10-day tmpfiles sweep | `shred -u /tmp/<secret>.bak.*.yaml` once the new key is confirmed. Same applies to any `oc get secret -o yaml` you redirect to a file |
| Duplicate certs in the merged CA bundle | Assuming `additionalCAConfigMapRef` *replaces* the trust bundle and pre-concatenating `kube-root-ca.crt` into it | It **merges** via a separate `additional-ca` volume. Put ONLY the private root CA in the ConfigMap; key MUST be `ca.crt` |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Install OLS operator on CRC with metrics-client-ca fix | Operator CSV `Succeeded`, OLSConfig `Ready` |
| S2 | List all providers, models, active default, and status | `scripts/list.sh` outputs structured report |
| S3 | Add a new provider with separate credentials secret | Provider appears in `list` output, status `Ready` |
| S4 | Switch active provider+model pair | `scripts/switch-provider.sh` → new default, status `Ready` |
| S5 | Remove a non-default provider | `scripts/remove-provider.sh` → provider gone, status `Ready` |
| S6 | Block removal of the active default provider | `scripts/remove-provider.sh` → exit 1 with clear error |
| S7 | Detect Skupper provider model mismatch | `scripts/list.sh` → ❌ MISMATCH when configured model differs from live backend |
| S8 | Trust a private/corporate CA so a provider's TLS verifies without `-k` | In-pod `curl` to the provider WITHOUT `-k` returns HTTP 200; cluster API still HTTP 200 |
| S9 | Install idempotently and never mutate an existing OLSConfig | `scripts/install.sh --dry-run` on an installed cluster → `DRY_RUN_RESULT=CONVERGED`, `Changes: none` |
| S10 | Resolve project/location/model/SA key from `gcp-vertex-models`, never a placeholder | `scripts/install.sh --dry-run` prints concrete values; `--project YOUR_GCP_PROJECT` exits 1 |
| S11 | Rotate or create a provider credential with pre-flight validation and in-pod verification | `scripts/rotate-key.sh PROVIDER` → validated before write, secret stamped, in-pod probe HTTP 200 |
| S12 | Refuse to write a secret when the new key fails validation | `scripts/rotate-key.sh` on a bad key → exit 1, `Secret NOT modified` |
| S13 | Report credential age against the rotation policy and live auth state | `scripts/list.sh` → `=== Credential Health ===` with Age + Auth per provider |

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | S2 | `bash scripts/list.sh --context crc-admin` | Default + all providers + status `Ready` |
| T2 | S4 | `bash scripts/switch-provider.sh skupper-model-rhel ibm-granite/granite-4.2-8b-fp8 --context crc-admin` | `✅ Switch complete`, status `Ready` |
| T3 | S6 | `bash scripts/remove-provider.sh skupper-model-rhel --context crc-admin` (while it's the default) | Exit 1, `❌ Cannot remove...` |
| T4 | S5 | `bash scripts/remove-provider.sh skupper-model-rhtevan --context crc-admin` (after switching away) | `✅ Provider removed` |
| T5 | S7 | `bash scripts/list.sh --context crc-admin` (with VAN running + models started) | Skupper providers show `✅ Live` |
| T6 | S7 | `bash scripts/list.sh --context crc-admin` (with VAN stopped) | Skupper providers show `⚠️ UNREACHABLE` |
| T7 | S8 | `oc exec deployment/lightspeed-app-server -n openshift-lightspeed -c lightspeed-service-api -- curl -s -o /dev/null -w '%{http_code}' https://models.corp.redhat.com/oai/v1/models` | `200` (no `-k`) |
| T8 | S8 | `oc exec deployment/lightspeed-app-server -n openshift-lightspeed -c lightspeed-service-api -- grep -c 'BEGIN CERTIFICATE' /etc/certs/cert-bundle/ols.pem` | Count = baseline + certs in `corp-ca` (merge, not replace) |
| T9 | S9 | `bash scripts/install.sh --dry-run --context crc-admin` (installed cluster) | `Changes: none` + `DRY_RUN_RESULT=CONVERGED`, exit 0 |
| T10 | S10 | `bash scripts/install.sh --dry-run --context crc-admin` | Prints a real project/location/model + an SA-key path of type `service_account` |
| T11 | S10 | `bash scripts/install.sh --dry-run --context crc-admin --project YOUR_GCP_PROJECT` | Exit 1, `Placeholder value ... refusing to install` |
| T12 | S11 | `bash scripts/rotate-key.sh corp-models --from-keyring --dry-run --context crc-admin` | Prints secret/key/url/model resolved from the CRD + `DRY_RUN_RESULT=` |
| T13 | S11 | `bash scripts/rotate-key.sh corp-models --from-keyring --context crc-admin` | `✅ HTTP 200` pre-flight, `Stamped: crc-ols/rotated-at=...`, in-pod probe `✅ HTTP 200` |
| T14 | S12 | `bash scripts/rotate-key.sh nosuchprovider --dry-run --context crc-admin` | Exit 1, `Provider ... not found` + list of configured providers |
| T15 | S13 | `bash scripts/list.sh --context crc-admin` | `Credential Health` shows `Age:` and `Auth:` for every provider |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
