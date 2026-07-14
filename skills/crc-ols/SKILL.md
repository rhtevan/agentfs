---
name: openshift-lightspeed-crc
version: 2.1.0
description: Install, configure, and manage OpenShift Lightspeed on OpenShift Local (CRC). Supports multiple LLM providers (Google Vertex AI Anthropic, OpenAI-compatible/MaaS, Azure OpenAI, WatsonX), adding/removing providers, switching defaults, and CRC-specific tunings.
metadata:
  tags: [openshift, crc, lightspeed, ols, vertex-ai, anthropic, llm, maas, openai, provider-management]
---

# OpenShift Lightspeed on CRC — Multi-Provider Management

Install OpenShift Lightspeed on an OpenShift Local (CRC) cluster, configure one or more LLM providers, switch between them, and apply CRC-specific tunings.

## Usage

This skill supports multiple operations via arguments:

| Argument | Description | Keywords / Signals |
|----------|-------------|--------------------|
| `install` (or no args) | Install the Lightspeed Operator on CRC, apply the `metrics-client-ca` fix, configure the first LLM provider, create OLSConfig, and verify deployment | *install lightspeed*, *set up OLS*, *deploy lightspeed on CRC*, *first time setup* |
| `add-provider` | Add an additional LLM provider: create credentials secret (file-based), patch OLSConfig providers array, verify pod rollout and status | *add provider*, *new LLM*, *add maas*, *add openai*, *another model*, *configure additional provider* |
| `list` | Display all configured providers, their types, URLs, models, and which provider/model is the active default | *list providers*, *show models*, *what's configured*, *current OLS config*, *which model*, *show lightspeed config* |
| `switch-default` | Change the default provider and model, wait for pod rollout, verify the switch | *switch model*, *change provider*, *use qwen*, *switch to claude*, *change default*, *swap model* |
| `remove-provider` | Remove a provider from OLSConfig (cannot remove the current default — switch first), optionally delete the credentials secret | *remove provider*, *delete provider*, *drop maas*, *uninstall provider*, *clean up provider* |

### Cross-Cutting Capabilities

These capabilities are embedded across multiple operations:

| Capability | Description | Keywords / Signals |
|-----------|-------------|--------------------|
| Credential security | File-based secret creation (`echo -n` + `--from-file`) to avoid key leakage in shell history, process listings, or AI chat sessions | *create secret*, *API key*, *credentials*, *secure*, *401 error* |
| CRC tunings | `maxIterations: 20` (avoids Anthropic `tool_choice="none"` bug), `introspectionEnabled` toggle for MCP server | *tuning*, *maxIterations*, *tool_choice error*, *LLM backend error*, *disable MCP*, *introspection* |
| Provider type reference | Supported types: `openai`, `google_vertex_anthropic`, `azure_openai`, `watsonx`, `bam` — with credential format and required fields for each | *what providers*, *supported types*, *provider reference*, *how to configure azure*, *watsonx setup* |
| 401 troubleshooting | Diagnosis and fix for the most common auth failure: whitespace/newline in API keys stored via `--from-literal` | *401*, *unauthorized*, *auth error*, *invalid token*, *key not found* |

---

## Prerequisites

- OpenShift Local (CRC) running (`crc status` shows Running)
- Logged in as `kubeadmin` (`oc whoami` confirms)
- For each provider, appropriate credentials (see Provider Types Reference below)

---

## Operation: `install`

Full installation of the Lightspeed Operator and initial provider configuration.

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
```bash
oc create secret generic llmcreds \
  --from-file=gcp-service-account.json=/path/to/your-sa-key.json \
  -n openshift-lightspeed
```

> **Tip — Choosing the right GCP service account:**
> If a dedicated service account (e.g., `vertex-ai-sa`) returns permission errors like
> `"Permission 'aiplatform.endpoints.predict' denied"`, test with the Compute Engine
> default service account instead. You can verify access with:
> ```bash
> curl -s -X POST \
>   "https://aiplatform.googleapis.com/v1/projects/YOUR_PROJECT/locations/YOUR_LOCATION/publishers/anthropic/models/YOUR_MODEL:rawPredict" \
>   -H "Authorization: Bearer $(gcloud auth print-access-token --impersonate-service-account=YOUR_SA_EMAIL)" \
>   -H "Content-Type: application/json" \
>   -d '{"anthropic_version":"vertex-2023-10-16","messages":[{"role":"user","content":"hello"}],"max_tokens":50}'
> ```

### Phase 3 — Create the OLSConfig Custom Resource

Replace `YOUR_GCP_PROJECT`, `YOUR_LOCATION`, and `YOUR_MODEL` with your values:

```bash
oc apply -f - <<'EOF'
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
        projectID: YOUR_GCP_PROJECT
        location: YOUR_LOCATION
      models:
      - name: YOUR_MODEL
  ols:
    defaultModel: YOUR_MODEL
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

---

## Operation: `add-provider`

Add an additional LLM provider to an existing OpenShift Lightspeed deployment.

### Step 1: Identify the provider type

Ask the user for:
- **Provider type** — one of: `openai`, `google_vertex_anthropic`, `azure_openai`, `watsonx`, `bam`
- **Provider name** — a unique identifier (e.g., `maas-litellm`, `my-openai`)
- **URL** — required for `openai` type (the base API URL, e.g., `https://api.openai.com/v1`)
- **Models** — list of model names to configure
- **Credentials** — API key or service account key

### Step 2: Create the credentials secret

Create a **separate** secret for the new provider (do NOT modify existing secrets).

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
```

This shows existing provider names to avoid conflicts.

### Step 4: Patch the OLSConfig to add the new provider

Use a JSON patch to append the new provider to the existing providers array.

**Example — Adding an OpenAI-compatible provider (MaaS/LiteLLM):**
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

Show the current provider and model configuration.

```bash
echo "=== Default ==="
echo "Provider: $(oc get olsconfig cluster -o jsonpath='{.spec.ols.defaultProvider}')"
echo "Model:    $(oc get olsconfig cluster -o jsonpath='{.spec.ols.defaultModel}')"
echo ""
echo "=== All Providers ==="
oc get olsconfig cluster -o jsonpath='{range .spec.llm.providers[*]}{"Provider: "}{.name}{"\n"}{"  Type: "}{.type}{"\n"}{"  URL:  "}{.url}{"\n"}{"  Models: "}{range .models[*]}{.name}{", "}{end}{"\n\n"}{end}'
echo "=== Status ==="
oc get olsconfig cluster -o jsonpath='{.status.overallStatus}'
echo ""
```

---

## Operation: `switch-default`

Change the default provider and model. The target provider and model must already be configured in the OLSConfig.

### Step 1: List available providers and models

Run the `list` operation above to see what's available.

### Step 2: Patch the default provider and model

```bash
oc patch olsconfig cluster --type=merge -p '{
  "spec": {
    "ols": {
      "defaultProvider": "PROVIDER_NAME",
      "defaultModel": "MODEL_NAME"
    }
  }
}'
```

### Step 3: Verify the switch

```bash
# Confirm new defaults
echo "Provider: $(oc get olsconfig cluster -o jsonpath='{.spec.ols.defaultProvider}')"
echo "Model:    $(oc get olsconfig cluster -o jsonpath='{.spec.ols.defaultModel}')"

# Wait for pods to restart
oc get pods -n openshift-lightspeed -w

# Check status
oc get olsconfig cluster -o jsonpath='{.status.overallStatus}'
```

### Step 4: Test the new model

Open the OpenShift web console Lightspeed chat and send a test query to confirm the new model responds.

---

## Operation: `remove-provider`

Remove a provider from the OLSConfig. **Cannot remove the current default provider** — switch to a different default first.

### Step 1: Identify the provider index

```bash
oc get olsconfig cluster -o jsonpath='{range .spec.llm.providers[*]}{.name}{"\n"}{end}' | cat -n
```

Note the line number (1-based). The JSON patch index is **0-based** (subtract 1).

### Step 2: Verify it's not the default

```bash
DEFAULT=$(oc get olsconfig cluster -o jsonpath='{.spec.ols.defaultProvider}')
echo "Default provider: $DEFAULT"
```

If the provider to remove IS the default, run `switch-default` first.

### Step 3: Remove the provider using JSON patch

```bash
# Replace INDEX with the 0-based index from Step 1
oc patch olsconfig cluster --type=json -p '[
  {"op": "remove", "path": "/spec/llm/providers/INDEX"}
]'
```

### Step 4: Optionally delete the credentials secret

```bash
oc delete secret SECRET_NAME -n openshift-lightspeed
```

### Step 5: Verify

```bash
oc get olsconfig cluster -o jsonpath='{range .spec.llm.providers[*]}{.name}{"\n"}{end}'
oc get olsconfig cluster -o jsonpath='{.status.overallStatus}'
```

---

## Provider Types Reference

| Type | `type` value | URL Required | Credential Format | Extra Config |
|------|-------------|-------------|-------------------|-------------|
| OpenAI / OpenAI-compatible (LiteLLM, MaaS, vLLM) | `openai` | ✅ Yes | API key in secret (`--from-literal=apitoken=KEY`) | None |
| Google Vertex AI Anthropic | `google_vertex_anthropic` | ❌ No | GCP SA key JSON (`--from-file=gcp-service-account.json=FILE`) | `googleVertexAnthropicConfig` (projectID, location) |
| Azure OpenAI | `azure_openai` | ✅ Yes | API key in secret | `azureOpenAIConfig` |
| WatsonX | `watsonx` | ✅ Yes | API key in secret | None |
| BAM | `bam` | ✅ Yes | API key in secret | None |

### Credential Security Notes

- **Never commit credentials** to version control — this skill uses placeholder values only
- Each provider should use a **separate secret** for isolation
- Secret names should be descriptive (e.g., `llmcreds`, `maas-llmcreds`)
- The `credentialKey` in OLSConfig must match the key name used when creating the secret

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

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-14 14:03 | v2.1 — Credential security hardening: replaced --from-literal with file-based secret creation, added security warnings, 401 troubleshooting. Added Keywords/Signals column to Usage table and Cross-Cutting Capabilities section. Validated full add-provider + switch-default workflow against live MaaS LiteLLM endpoint. |
| 2026-07-14 13:26 | v2.0 — Enhanced with multi-provider management: add-provider, list, switch-default, remove-provider operations. Added Provider Types Reference table. |
| 2026-06-19 12:42 | v1.0 — Initial skill |
