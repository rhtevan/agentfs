#!/usr/bin/env bash
# create-site.sh — Create a Skupper Linux/systemd site and start the router
# Usage: bash create-site.sh <SITE_NAME> <NAMESPACE> <ROLE> [REMOTE_SSH_HOST]
#   ROLE: "interior" or "edge"
#   REMOTE_SSH_HOST: if provided, creates the site on the remote host via SSH
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <SITE_NAME> <NAMESPACE> <ROLE> [REMOTE_SSH_HOST]" >&2
  echo "  ROLE: interior | edge" >&2
  exit 2
fi

SITE_NAME="$1"
NAMESPACE="$2"
ROLE="$3"
REMOTE_SSH_HOST="${4:-}"

if [[ "$ROLE" != "interior" && "$ROLE" != "edge" ]]; then
  echo "Error: ROLE must be 'interior' or 'edge', got '${ROLE}'" >&2
  exit 2
fi

# Generate site YAML
TMP_YAML=$(mktemp /tmp/site-XXXXXX.yaml)
if [[ "$ROLE" == "interior" ]]; then
  cat > "$TMP_YAML" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: ${SITE_NAME}
spec:
  linkAccess: default
EOF
else
  cat > "$TMP_YAML" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: ${SITE_NAME}
spec:
  edge: true
EOF
fi

run_cmd() {
  if [[ -n "$REMOTE_SSH_HOST" ]]; then
    ssh "$REMOTE_SSH_HOST" "$*"
  else
    eval "$*"
  fi
}

# Copy YAML to remote if needed
if [[ -n "$REMOTE_SSH_HOST" ]]; then
  REMOTE_YAML="/tmp/site-${SITE_NAME}.yaml"
  scp -q "$TMP_YAML" "${REMOTE_SSH_HOST}:${REMOTE_YAML}"
  YAML_PATH="$REMOTE_YAML"
else
  YAML_PATH="$TMP_YAML"
fi

# Apply and start
echo "Creating ${ROLE} site '${SITE_NAME}' in namespace '${NAMESPACE}'..."
run_cmd "skupper system -n ${NAMESPACE} -p linux apply -f ${YAML_PATH}"
run_cmd "skupper system -n ${NAMESPACE} -p linux start"

# Verify
echo ""
echo "Verifying..."
run_cmd "systemctl --user status skupper-${NAMESPACE}.service --no-pager" | head -5

if [[ "$ROLE" == "interior" ]]; then
  echo ""
  echo "Listening ports:"
  if [[ -n "$REMOTE_SSH_HOST" ]]; then
    ssh "$REMOTE_SSH_HOST" 'ss -tlnp | grep -E "55671|45671"'
  else
    ss -tlnp | grep -E '55671|45671'
  fi
fi

# Cleanup temp file
rm -f "$TMP_YAML"

echo ""
echo "✅ Site '${SITE_NAME}' (${ROLE}) created and running in namespace '${NAMESPACE}'"
