#!/usr/bin/env bash
# setup.sh — One-time Skupper VAN infrastructure setup
# Usage: bash setup.sh [--check]
# Creates sites, RouterAccess, Connectors, Listeners, Links on all 3 hosts.
# Applies auto-restart patches and podman 4.x workarounds.
# Idempotent: safe to re-run.
#
# --check    Run precheck only (validate topology, don't build anything)

source "$(dirname "$0")/common.sh"

# ── Handle --check flag ───────────────────────────────────────
if [[ "${1:-}" == "--check" ]]; then
  precheck_topology
  exit $?
fi

echo "=== Skupper Model Provider — SETUP ==="
echo "  Namespace:  $NAMESPACE"
echo "  Sites:      ${SITE_NAMES[rhel-ai]}, ${SITE_NAMES[rhtevan-work]}, ${SITE_NAMES[local]}"
echo

# ── Phase 0: Precheck ─────────────────────────────────────────
echo "Phase 0: Precheck"
if ! precheck_topology; then
  echo
  echo "❌ Precheck failed. Fix the errors above before proceeding."
  exit 1
fi
echo

FAILED=0

# ── Phase 1: Build hub-rhel-ai ────────────────────────────────
echo "Phase 1: Build ${SITE_NAMES[rhel-ai]} site"

RHELAI_NS=$(run_on_host rhel-ai "test -d ~/.local/share/skupper/namespaces/${NAMESPACE}/runtime/resources && echo yes || echo no")

if [[ "$RHELAI_NS" == "yes" ]]; then
  echo "  ✅ Site already exists"
else
  echo "  → Creating site resources..."

  # Build SAN YAML lines for rhel-ai
  RHEL_AI_SAN_YAML=$(sans_to_yaml "${SITE_SANS[rhel-ai]}")

  run_on_host rhel-ai "mkdir -p ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources

  cat > ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources/Site-${SITE_NAMES[rhel-ai]}.yaml << 'EOF'
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: ${SITE_NAMES[rhel-ai]}
  namespace: ${NAMESPACE}
spec:
  defaultIssuer: self-signed
EOF

  cat > ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources/RouterAccess-${SITE_NAMES[rhel-ai]}.yaml << EOF
apiVersion: skupper.io/v2alpha1
kind: RouterAccess
metadata:
  name: ${SITE_NAMES[rhel-ai]}
  namespace: ${NAMESPACE}
spec:
  roles:
    - name: inter-router
      port: ${RHEL_AI_INTER_ROUTER_PORT}
    - name: edge
      port: ${RHEL_AI_EDGE_PORT}
  subjectAlternativeNames:
    - \"0.0.0.0\"
    - \"::\"
${RHEL_AI_SAN_YAML}
  tlsCredentials: ${SITE_NAMES[rhel-ai]}
EOF

  cat > ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources/RouterAccess-${SITE_NAMES[rhel-ai]}-public.yaml << EOF
apiVersion: skupper.io/v2alpha1
kind: RouterAccess
metadata:
  name: ${SITE_NAMES[rhel-ai]}-public
  namespace: ${NAMESPACE}
spec:
  roles:
    - name: inter-router
      port: 8000
  subjectAlternativeNames:
    - \"0.0.0.0\"
    - \"::\"
${RHEL_AI_SAN_YAML}
  tlsCredentials: ${SITE_NAMES[rhel-ai]}-public
EOF

  cat > ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources/Connector-model-connector.yaml << EOF
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: model-connector
  namespace: ${NAMESPACE}
spec:
  routingKey: ${RHEL_AI_ROUTING_KEY}
  host: host.containers.internal
  port: ${RHEL_AI_MODEL_PORT}
EOF

  skupper --platform podman system start -n ${NAMESPACE}"
  sleep 8
fi

# Apply podman 4.x workaround for rhel-ai
RHELAI_ROUTER=$(check_router_status rhel-ai)
if [[ "$RHELAI_ROUTER" == *"Up"* ]]; then
  # Check if it's running in Interior mode
  MODE=$(run_on_host rhel-ai "podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1" || echo "unknown")
  if [[ "$MODE" == "Interior" ]]; then
    echo "  ✅ Router running in Interior mode"
  else
    echo "  → Router in $MODE mode, recreating with --tmpfs..."
    recreate_router_with_tmpfs rhel-ai
    sleep 5
  fi
else
  echo "  → Starting router with --tmpfs workaround..."
  fix_cert_perms rhel-ai
  run_on_host rhel-ai "skupper --platform podman system start -n ${NAMESPACE} 2>/dev/null" || true
  sleep 3
  recreate_router_with_tmpfs rhel-ai
  sleep 5
fi

# Verify
MODE=$(run_on_host rhel-ai "podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1" || echo "unknown")
if [[ "$MODE" == "Interior" ]]; then
  echo "  ✅ hub-rhel-ai: Interior mode, ready"
else
  echo "  ❌ hub-rhel-ai: $MODE mode — check logs"
  FAILED=1
fi
echo

# ── Phase 2: Build hub-rhtevan-work ───────────────────────────
echo "Phase 2: Build ${SITE_NAMES[rhtevan-work]} site"

RTW_NS=$(run_on_host rhtevan-work "test -d ~/.local/share/skupper/namespaces/${NAMESPACE}/runtime/resources && echo yes || echo no")

if [[ "$RTW_NS" == "yes" ]]; then
  echo "  ✅ Site already exists"
else
  echo "  → Creating site resources..."

  # Build SAN YAML lines for rhtevan-work
  RHTEVAN_WORK_SAN_YAML=$(sans_to_yaml "${SITE_SANS[rhtevan-work]}")

  run_on_host rhtevan-work "mkdir -p ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources

  cat > ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources/Site-${SITE_NAMES[rhtevan-work]}.yaml << 'EOF'
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: ${SITE_NAMES[rhtevan-work]}
  namespace: ${NAMESPACE}
spec:
  defaultIssuer: self-signed
EOF

  cat > ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources/RouterAccess-${SITE_NAMES[rhtevan-work]}.yaml << EOF
apiVersion: skupper.io/v2alpha1
kind: RouterAccess
metadata:
  name: ${SITE_NAMES[rhtevan-work]}
  namespace: ${NAMESPACE}
spec:
  roles:
    - name: inter-router
      port: ${RHTEVAN_WORK_INTER_ROUTER_PORT}
    - name: edge
      port: ${RHTEVAN_WORK_EDGE_PORT}
  subjectAlternativeNames:
    - \"0.0.0.0\"
    - \"::\"
${RHTEVAN_WORK_SAN_YAML}
  tlsCredentials: ${SITE_NAMES[rhtevan-work]}
EOF

  cat > ~/.local/share/skupper/namespaces/${NAMESPACE}/input/resources/Connector-model-connector.yaml << EOF
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: model-connector
  namespace: ${NAMESPACE}
spec:
  routingKey: ${RHTEVAN_WORK_ROUTING_KEY}
  host: host.containers.internal
  port: ${RHTEVAN_WORK_MODEL_PORT}
EOF

  skupper --platform podman system start -n ${NAMESPACE}"
  sleep 8
fi

RTW_ROUTER=$(check_router_status rhtevan-work)
if [[ "$RTW_ROUTER" == *"Up"* ]]; then
  echo "  ✅ Router running"
else
  echo "  → Starting router..."
  run_on_host rhtevan-work "systemctl --user start skupper-${NAMESPACE}.service 2>/dev/null" || true
  sleep 5
fi

MODE=$(run_on_host rhtevan-work "podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1" || echo "unknown")
if [[ "$MODE" == "Interior" ]]; then
  echo "  ✅ hub-rhtevan-work: Interior mode, ready"
else
  echo "  ❌ hub-rhtevan-work: $MODE mode — check logs"
  FAILED=1
fi
echo

# ── Phase 3: Build local site ─────────────────────────────────
echo "Phase 3: Build ${SITE_NAMES[local]} site"

LOCAL_NS_DIR="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"

if [[ -d "${LOCAL_NS_DIR}/runtime/resources" ]]; then
  echo "  ✅ Site already exists"
else
  echo "  → Creating site resources..."
  mkdir -p "${LOCAL_NS_DIR}/input/resources"

  cat > "${LOCAL_NS_DIR}/input/resources/Site-${SITE_NAMES[local]}.yaml" << EOF
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: ${SITE_NAMES[local]}
  namespace: ${NAMESPACE}
spec:
  defaultIssuer: self-signed
EOF

  cat > "${LOCAL_NS_DIR}/input/resources/Listener-model-rhel-ai.yaml" << EOF
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: model-rhel-ai
  namespace: ${NAMESPACE}
spec:
  routingKey: ${RHEL_AI_ROUTING_KEY}
  host: localhost
  port: ${RHEL_AI_MODEL_PORT}
EOF

  cat > "${LOCAL_NS_DIR}/input/resources/Listener-model-rhtevan-work.yaml" << EOF
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: model-rhtevan-work
  namespace: ${NAMESPACE}
spec:
  routingKey: ${RHTEVAN_WORK_ROUTING_KEY}
  host: localhost
  port: ${RHTEVAN_WORK_MODEL_PORT}
EOF

  skupper --platform podman system start -n "${NAMESPACE}"
  sleep 8
fi

LOCAL_ROUTER=$(check_router_status localhost)
if [[ "$LOCAL_ROUTER" == *"Up"* ]]; then
  echo "  ✅ Router running"
else
  echo "  → Starting router..."
  systemctl --user start "skupper-${NAMESPACE}.service" 2>/dev/null || true
  sleep 5
fi

MODE=$(podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1 || echo "unknown")
if [[ "$MODE" == "Interior" ]]; then
  echo "  ✅ ${SITE_NAMES[local]}: Interior mode, ready"
else
  echo "  ❌ ${SITE_NAMES[local]}: $MODE mode — check logs"
  FAILED=1
fi
echo

# ── Phase 4: Links ────────────────────────────────────────────
echo "Phase 4: Establish links"

# Link to rhel-ai (via port 8000, publicly accessible)
if [[ -f "${LOCAL_NS_DIR}/input/resources/Link-link-hub-rhel-ai.yaml" ]]; then
  echo "  ✅ Link to rhel-ai already exists"
else
  echo "  → Building link to rhel-ai (port ${RHEL_AI_INTER_ROUTER_PORT})..."
  CA_CRT=$(ssh "${SSH_HOSTS[rhel-ai]}" 'base64 -w0 ~/.local/share/skupper/namespaces/model-provider-podman/runtime/certs/client-hub-rhel-ai-public/ca.crt')
  TLS_CRT=$(ssh "${SSH_HOSTS[rhel-ai]}" 'base64 -w0 ~/.local/share/skupper/namespaces/model-provider-podman/runtime/certs/client-hub-rhel-ai-public/tls.crt')
  TLS_KEY=$(ssh "${SSH_HOSTS[rhel-ai]}" 'base64 -w0 ~/.local/share/skupper/namespaces/model-provider-podman/runtime/certs/client-hub-rhel-ai-public/tls.key')

  cat > /tmp/link-hub-rhel-ai.yaml << EOF
---
apiVersion: v1
data:
  ca.crt: ${CA_CRT}
  tls.crt: ${TLS_CRT}
  tls.key: ${TLS_KEY}
kind: Secret
metadata:
  name: link-hub-rhel-ai
---
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: link-hub-rhel-ai
  namespace: ${NAMESPACE}
spec:
  cost: 1
  endpoints:
  - host: ${RHEL_AI_PUBLIC_HOST}
    name: inter-router
    port: "${RHEL_AI_INTER_ROUTER_PORT}"
  tlsCredentials: link-hub-rhel-ai
EOF

  skupper --platform podman system apply -n "${NAMESPACE}" -f /tmp/link-hub-rhel-ai.yaml
  rm -f /tmp/link-hub-rhel-ai.yaml
  echo "  ✅ Link to rhel-ai created"
fi

# Link to rhtevan-work (LAN, port 55671)
if [[ -f "${LOCAL_NS_DIR}/input/resources/Link-link-hub-rhtevan-work.yaml" ]]; then
  echo "  ✅ Link to rhtevan-work already exists"
else
  echo "  → Building link to rhtevan-work (port ${RHTEVAN_WORK_INTER_ROUTER_PORT})..."
  CA_CRT=$(ssh "${SSH_HOSTS[rhtevan-work]}" 'base64 -w0 ~/.local/share/skupper/namespaces/model-provider-podman/runtime/certs/client-hub-rhtevan-work/ca.crt')
  TLS_CRT=$(ssh "${SSH_HOSTS[rhtevan-work]}" 'base64 -w0 ~/.local/share/skupper/namespaces/model-provider-podman/runtime/certs/client-hub-rhtevan-work/tls.crt')
  TLS_KEY=$(ssh "${SSH_HOSTS[rhtevan-work]}" 'base64 -w0 ~/.local/share/skupper/namespaces/model-provider-podman/runtime/certs/client-hub-rhtevan-work/tls.key')

  cat > /tmp/link-hub-rhtevan-work.yaml << EOF
---
apiVersion: v1
data:
  ca.crt: ${CA_CRT}
  tls.crt: ${TLS_CRT}
  tls.key: ${TLS_KEY}
kind: Secret
metadata:
  name: link-hub-rhtevan-work
---
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: link-hub-rhtevan-work
  namespace: ${NAMESPACE}
spec:
  cost: 1
  endpoints:
  - host: ${RHTEVAN_WORK_PUBLIC_HOST}
    name: inter-router
    port: "${RHTEVAN_WORK_INTER_ROUTER_PORT}"
  tlsCredentials: link-hub-rhtevan-work
EOF

  skupper --platform podman system apply -n "${NAMESPACE}" -f /tmp/link-hub-rhtevan-work.yaml
  rm -f /tmp/link-hub-rhtevan-work.yaml
  echo "  ✅ Link to rhtevan-work created"
fi

sleep 10
echo

# ── Phase 5: Auto-restart patches ─────────────────────────────
echo "Phase 5: Auto-restart patches"

for host in rhel-ai rhtevan-work localhost; do
  local_name="$host"
  [[ "$host" == "localhost" ]] && local_name="local"

  echo "  → Patching $host..."
  install_router_auto_restart "$host"
  install_controller_auto_restart "$host"
  run_on_host "$host" "systemctl --user restart skupper-controller.service 2>/dev/null" || true
  run_on_host "$host" "systemctl --user restart skupper-${NAMESPACE}.service 2>/dev/null" || true
  echo "  ✅ $host patched"
done

sleep 5
echo

# ── Phase 6: Verify ───────────────────────────────────────────
echo "Phase 6: Verify"

echo "  Sites:"
for host in rhel-ai rhtevan-work; do
  STATUS=$(run_on_host "$host" "skupper --platform podman site status -n ${NAMESPACE} 2>&1" | grep -oP 'Ready|Pending|Error' | head -1 || echo "unknown")
  echo "    ${SITE_NAMES[$host]}: $STATUS"
done
STATUS=$(skupper --platform podman site status -n "${NAMESPACE}" 2>&1 | grep -oP 'Ready|Pending|Error' | head -1 || echo "unknown")
echo "    ${SITE_NAMES[local]}: $STATUS"

echo "  Links:"
skupper --platform podman link status -n "${NAMESPACE}" 2>&1 | grep -E '^link-' || echo "    (none yet)"

echo "  Listeners:"
skupper --platform podman listener status -n "${NAMESPACE}" 2>&1 | grep -E '^model-' || echo "    (none yet)"

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "✅ Setup complete. Run 'bash up.sh MODEL_ALIAS' to start a model."
else
  echo "⚠️  Setup completed with errors — check output above."
fi
exit $FAILED
