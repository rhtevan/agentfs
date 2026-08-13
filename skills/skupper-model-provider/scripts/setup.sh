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

  LINK_TMPFILE=$(mktemp /tmp/link-hub-rhel-ai.XXXXXX.yaml)
  chmod 600 "$LINK_TMPFILE"
  cat > "$LINK_TMPFILE" << EOF
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

  skupper --platform podman system apply -n "${NAMESPACE}" -f "$LINK_TMPFILE"
  rm -f "$LINK_TMPFILE"
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

  LINK_TMPFILE=$(mktemp /tmp/link-hub-rhtevan-work.XXXXXX.yaml)
  chmod 600 "$LINK_TMPFILE"
  cat > "$LINK_TMPFILE" << EOF
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

  skupper --platform podman system apply -n "${NAMESPACE}" -f "$LINK_TMPFILE"
  rm -f "$LINK_TMPFILE"
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

# ── Phase 6: CRC site (Kubernetes) ────────────────────────────
if [[ "$CRC_ENABLED" == "true" ]]; then
  echo "Phase 6: Build ${CRC_SITE_NAME} site (CRC/Kubernetes)"

  # 6a. Create namespace
  if oc_crc get namespace "${CRC_NAMESPACE}" &>/dev/null; then
    echo "  ✅ Namespace ${CRC_NAMESPACE} exists"
  else
    echo "  → Creating namespace ${CRC_NAMESPACE}..."
    oc_crc create namespace "${CRC_NAMESPACE}"
    echo "  ✅ Namespace ${CRC_NAMESPACE} created"
  fi

  # 6b. Install Skupper operator (AllNamespaces mode → openshift-operators)
  # The skupper-operator v2.2.1 only supports AllNamespaces install mode.
  # It must be installed in openshift-operators (which has the global-operators
  # OperatorGroup). The operator watches ALL namespaces, including our
  # model-provider-crc namespace, so Skupper CRs work there.
  CRC_OPERATOR_NS="openshift-operators"
  if oc_crc get csv -n "${CRC_OPERATOR_NS}" 2>/dev/null | grep -q 'skupper-operator.*Succeeded'; then
    echo "  ✅ Skupper operator already installed (in ${CRC_OPERATOR_NS})"
  else
    echo "  → Installing Skupper operator (stable-2.2) in ${CRC_OPERATOR_NS}..."

    # OperatorGroup already exists (global-operators) — no need to create one

    # Subscription
    if ! oc_crc get subscription -n "${CRC_OPERATOR_NS}" 2>/dev/null | grep -q skupper; then
      cat << SUBEOF | oc_crc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: skupper-operator
  namespace: ${CRC_OPERATOR_NS}
spec:
  channel: stable-2.2
  installPlanApproval: Automatic
  name: skupper-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
SUBEOF
    fi

    # Wait for CSV
    echo "  → Waiting for operator CSV to succeed..."
    crc_csv_attempts=0
    while [[ $crc_csv_attempts -lt 60 ]]; do
      if oc_crc get csv -n "${CRC_OPERATOR_NS}" 2>/dev/null | grep -q 'skupper-operator.*Succeeded'; then
        break
      fi
      sleep 5
      ((crc_csv_attempts++)) || true
    done
    if oc_crc get csv -n "${CRC_OPERATOR_NS}" 2>/dev/null | grep -q 'skupper-operator.*Succeeded'; then
      echo "  ✅ Skupper operator installed"
    else
      echo "  ❌ Skupper operator CSV did not reach Succeeded"
      ((FAILED++))
    fi
  fi

  # 6c. Create TLS Secret (client certs from local link profile)
  if oc_crc get secret link-hub-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" &>/dev/null; then
    echo "  ✅ Secret link-hub-${CRC_LINK_TARGET} exists"
  else
    echo "  → Creating TLS secret from local cert profile..."
    cert_dir="${HOME}/.local/share/skupper/namespaces/${NAMESPACE}/runtime/certs/link-${SITE_NAMES[$CRC_LINK_TARGET]}-profile"
    if [[ ! -d "$cert_dir" ]]; then
      echo "  ❌ Cert profile not found: $cert_dir"
      echo "     Run setup without CRC first to establish local links."
      ((FAILED++))
    else
      # Must use 'tls' type secret (not generic/Opaque) — the kube-adaptor
      # only auto-mounts kubernetes.io/tls secrets into the router pod.
      oc_crc create secret tls link-hub-"${CRC_LINK_TARGET}" \
        -n "${CRC_NAMESPACE}" \
        --cert="${cert_dir}/tls.crt" \
        --key="${cert_dir}/tls.key"
      # Add ca.crt (not part of 'create secret tls' command)
      oc_crc patch secret link-hub-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" \
        --type=merge -p "{\"data\":{\"ca.crt\":\"$(base64 -w0 "${cert_dir}/ca.crt")\"}}"
      echo "  ✅ Secret link-hub-${CRC_LINK_TARGET} created"
    fi
  fi

  # 6d. Create Site
  if oc_crc get site "${CRC_SITE_NAME}" -n "${CRC_NAMESPACE}" &>/dev/null; then
    echo "  ✅ Site ${CRC_SITE_NAME} exists"
  else
    echo "  → Creating site ${CRC_SITE_NAME}..."
    cat << SITEEOF | sed "s/PLACEHOLDER_NS/${CRC_NAMESPACE}/g" | sed "s/PLACEHOLDER_SITE/${CRC_SITE_NAME}/g" | oc_crc apply -f -
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: PLACEHOLDER_SITE
  namespace: PLACEHOLDER_NS
spec: {}
SITEEOF

    # Wait for Site Ready
    echo "  → Waiting for site to become Ready..."
    crc_site_attempts=0
    while [[ $crc_site_attempts -lt 30 ]]; do
      site_status=""
      site_status=$(oc_crc get site "${CRC_SITE_NAME}" -n "${CRC_NAMESPACE}" \
        -o jsonpath='{.status.status}' 2>/dev/null || echo "")
      if [[ "$site_status" == "Ready" ]]; then break; fi
      sleep 5
      ((crc_site_attempts++)) || true
    done
    site_status=$(oc_crc get site "${CRC_SITE_NAME}" -n "${CRC_NAMESPACE}" \
      -o jsonpath='{.status.status}' 2>/dev/null || echo "")
    if [[ "$site_status" == "Ready" ]]; then
      echo "  ✅ Site ${CRC_SITE_NAME} Ready"
    else
      echo "  ❌ Site ${CRC_SITE_NAME} not Ready (status: ${site_status})"
      ((FAILED++))
    fi
  fi

  # 6e. Create Link
  crc_link_name="link-hub-${CRC_LINK_TARGET}"
  if oc_crc get link "${crc_link_name}" -n "${CRC_NAMESPACE}" &>/dev/null; then
    echo "  ✅ Link ${crc_link_name} exists"
  else
    echo "  → Creating link ${crc_link_name}..."
    crc_hub_host=""
    crc_hub_port=""
    IFS='|' read -r crc_hub_port _ _ _ crc_hub_host <<< "${SITE_PROFILES[$CRC_LINK_TARGET]}"
    cat << LINKEOF | sed "s/PLACEHOLDER_NS/${CRC_NAMESPACE}/g" | oc_crc apply -f -
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: ${crc_link_name}
  namespace: PLACEHOLDER_NS
spec:
  cost: 1
  endpoints:
    - name: inter-router
      host: ${crc_hub_host}
      port: "${crc_hub_port}"
  tlsCredentials: ${crc_link_name}
LINKEOF

    # Wait for Link Ready
    echo "  → Waiting for link to connect..."
    crc_link_attempts=0
    while [[ $crc_link_attempts -lt 30 ]]; do
      link_status=""
      link_status=$(oc_crc get link "${crc_link_name}" -n "${CRC_NAMESPACE}" \
        -o jsonpath='{.status.status}' 2>/dev/null || echo "")
      if [[ "$link_status" == "Ready" ]]; then break; fi
      sleep 5
      ((crc_link_attempts++)) || true
    done
    link_status=$(oc_crc get link "${crc_link_name}" -n "${CRC_NAMESPACE}" \
      -o jsonpath='{.status.status}' 2>/dev/null || echo "")
    if [[ "$link_status" == "Ready" ]]; then
      echo "  ✅ Link ${crc_link_name} connected"
    else
      echo "  ⚠️  Link ${crc_link_name} status: ${link_status} (may need time)"
      ((FAILED++))
    fi
  fi

  # 6f. Create Listener
  crc_listener_name="model-listener-${CRC_LINK_TARGET}"
  if oc_crc get listener "${crc_listener_name}" -n "${CRC_NAMESPACE}" &>/dev/null; then
    echo "  ✅ Listener ${crc_listener_name} exists"
  else
    echo "  → Creating listener ${crc_listener_name}..."
    cat << LISTEOF | sed "s/PLACEHOLDER_NS/${CRC_NAMESPACE}/g" | oc_crc apply -f -
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: ${crc_listener_name}
  namespace: PLACEHOLDER_NS
spec:
  host: ${crc_listener_name}
  port: ${CRC_MODEL_PORT}
  routingKey: ${CRC_ROUTING_KEY}
LISTEOF

    # Wait for Listener Matched
    echo "  → Waiting for listener to match..."
    crc_list_attempts=0
    while [[ $crc_list_attempts -lt 20 ]]; do
      list_status=""
      list_status=$(oc_crc get listener "${crc_listener_name}" -n "${CRC_NAMESPACE}" \
        -o jsonpath='{.status.status}' 2>/dev/null || echo "")
      if [[ "$list_status" == "Ready" ]]; then break; fi
      sleep 3
      ((crc_list_attempts++)) || true
    done
    list_status=$(oc_crc get listener "${crc_listener_name}" -n "${CRC_NAMESPACE}" \
      -o jsonpath='{.status.status}' 2>/dev/null || echo "")
    if [[ "$list_status" == "Ready" ]]; then
      echo "  ✅ Listener ${crc_listener_name} matched"
    else
      echo "  ⚠️  Listener ${crc_listener_name} status: ${list_status}"
    fi
  fi

  # 6g. Verify Service created
  if oc_crc get svc "${crc_listener_name}" -n "${CRC_NAMESPACE}" &>/dev/null; then
    echo "  ✅ Service ${crc_listener_name}.${CRC_NAMESPACE}:${CRC_MODEL_PORT} created"
  else
    echo "  ⚠️  Service ${crc_listener_name} not yet created (may need time)"
  fi

  # 6h. Network Observer (optional)
  if [[ "$CRC_OBSERVER_ENABLED" == "true" ]]; then
    CRC_OBSERVER_NS="openshift-operators"
    if oc_crc get csv -n "${CRC_OBSERVER_NS}" 2>/dev/null | grep -q 'skupper-netobs-operator.*Succeeded'; then
      echo "  ✅ Network Observer operator already installed"
    else
      echo "  → Installing Network Observer operator (stable-2.2)..."

      if ! oc_crc get subscription -n "${CRC_OBSERVER_NS}" 2>/dev/null | grep -q skupper-netobs; then
        cat << NOBSEOF | oc_crc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: skupper-netobs-operator
  namespace: ${CRC_OBSERVER_NS}
spec:
  channel: stable-2.2
  installPlanApproval: Automatic
  name: skupper-netobs-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
NOBSEOF
      fi

      echo "  → Waiting for observer operator CSV..."
      crc_obs_attempts=0
      while [[ $crc_obs_attempts -lt 60 ]]; do
        if oc_crc get csv -n "${CRC_OBSERVER_NS}" 2>/dev/null | grep -q 'skupper-netobs-operator.*Succeeded'; then
          break
        fi
        sleep 5
        ((crc_obs_attempts++)) || true
      done
      if oc_crc get csv -n "${CRC_OBSERVER_NS}" 2>/dev/null | grep -q 'skupper-netobs-operator.*Succeeded'; then
        echo "  ✅ Network Observer operator installed"
      else
        echo "  ❌ Network Observer operator CSV did not reach Succeeded"
        ((FAILED++))
      fi
    fi

    # Create NetworkObserver CR
    if oc_crc get networkobserver skupper-network-observer -n "${CRC_NAMESPACE}" &>/dev/null; then
      echo "  ✅ NetworkObserver CR exists"
    else
      echo "  → Creating NetworkObserver CR..."
      cat << NOCREOF | oc_crc apply -f -
apiVersion: observability.skupper.io/v2alpha1
kind: NetworkObserver
metadata:
  name: skupper-network-observer
  namespace: ${CRC_NAMESPACE}
spec: {}
NOCREOF

      # Wait for observer pods
      echo "  → Waiting for observer pods..."
      crc_obs_pod_attempts=0
      while [[ $crc_obs_pod_attempts -lt 30 ]]; do
        if oc_crc get pods -n "${CRC_NAMESPACE}" -l app.kubernetes.io/name=network-observer 2>/dev/null | grep -q 'Running'; then
          break
        fi
        sleep 5
        ((crc_obs_pod_attempts++)) || true
      done
      if oc_crc get pods -n "${CRC_NAMESPACE}" -l app.kubernetes.io/name=network-observer 2>/dev/null | grep -q 'Running'; then
        echo "  ✅ Network Observer pods running"
      else
        echo "  ⚠️  Network Observer pods not yet running (may need time)"
      fi
    fi

    # Get or display Route
    obs_route=$(crc_observer_route_url)
    if [[ "$obs_route" != "not found" && -n "$obs_route" ]]; then
      echo "  ✅ Network Observer dashboard: https://${obs_route}"
    else
      echo "  ⚠️  Network Observer Route not found yet (may need time)"
    fi
  else
    echo "  ℹ️  Network Observer — skipped (CRC_OBSERVER_ENABLED=false)"
  fi

  echo
else
  echo "Phase 6: CRC site — skipped (CRC_ENABLED=false)"
  echo
fi

# ── Phase 7: Verify ───────────────────────────────────────────
echo "Phase 7: Verify"

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

if [[ "$CRC_ENABLED" == "true" ]]; then
  echo "  CRC:"
  local_site_status=$(oc_crc get site "${CRC_SITE_NAME}" -n "${CRC_NAMESPACE}" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "not found")
  local_link_status=$(oc_crc get link link-hub-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "not found")
  local_list_status=$(oc_crc get listener model-listener-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "not found")
  echo "    Site ${CRC_SITE_NAME}: ${local_site_status}"
  echo "    Link link-hub-${CRC_LINK_TARGET}: ${local_link_status}"
  echo "    Listener model-listener-${CRC_LINK_TARGET}: ${local_list_status}"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "✅ Setup complete. Run 'bash up.sh' to start the VAN."
else
  echo "⚠️  Setup completed with errors — check output above."
fi
exit $FAILED
