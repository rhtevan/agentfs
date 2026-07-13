---
name: openshift-lightspeed-crc
description: Install and configure OpenShift Lightspeed on OpenShift Local (CRC), with specific guidance for Google Vertex AI Anthropic as the LLM provider and tunings to avoid known LLM invocation errors.
metadata:
  tags: [openshift, crc, lightspeed, llm, operator]
---

# OpenShift Lightspeed on CRC with Google Vertex AI

Step-by-step guide to install OpenShift Lightspeed on an OpenShift Local (CRC) cluster, configure it with Google Vertex AI (Anthropic models), and apply tunings to work around known compatibility issues.

## Prerequisites

- OpenShift Local (CRC) running (`crc status` shows Running)
- Logged in as `kubeadmin` (`oc whoami` confirms)
- A GCP project with Vertex AI API enabled and an Anthropic model available (e.g., `claude-sonnet-4-20250514`, `claude-opus-4-6`)
- A GCP service account key (JSON) with `aiplatform.endpoints.predict` permission

## Phase 1 — Install the Lightspeed Operator

### Step 1: Create the namespace, OperatorGroup, and Subscription

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

### Step 2: Wait for the operator to install

```bash
oc get csv -n openshift-lightspeed -w
```

Wait until the `PHASE` column shows `Succeeded`.

### ⚠️ CRC Fix — Missing `metrics-client-ca` ConfigMap

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

## Phase 2 — Configure the LLM Credentials

### Step 3: Create the GCP service account key secret

```bash
oc create secret generic llmcreds \
  --from-file=gcp-service-account.json=/path/to/your-sa-key.json \
  -n openshift-lightspeed
```

> **Tip — Choosing the right service account:**
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

## Phase 3 — Create the OLSConfig Custom Resource

### Step 4: Apply the OLSConfig

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

> **Important — `maxIterations: 20`:** This is a required tuning for the Vertex AI Anthropic provider. See [Tuning: maxIterations](#tuning-maxiterations) below for the full explanation.

### Step 5: Verify deployment

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

## Phase 4 — Tunings for Vertex AI Anthropic Provider

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

## Verification

After completing all steps, test Lightspeed through the OpenShift web console:

1. Open the OpenShift web console
2. Click the Lightspeed chat icon (bottom-right)
3. Test a simple query: `hello` — should respond immediately
4. Test a cluster query: `list all pods in the openshift-lightspeed namespace` — should use MCP tools and return pod information
5. If the cluster query works without the `[LLM Backend]` error, the tunings are effective

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
| 2026-06-19 12:42 | v1.0 — Initial skill |
