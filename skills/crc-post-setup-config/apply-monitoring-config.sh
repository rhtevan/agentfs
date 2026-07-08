#!/bin/bash
# apply-monitoring-config.sh
# Apply cluster-monitoring-config with disk-saving Prometheus retention tuning for CRC.
# Safe to run repeatedly — oc apply is idempotent.

set -euo pipefail

echo "Applying cluster-monitoring-config with retention tuning..."

cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      retention: 24h
      retentionSize: "4GB"
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 5Gi
      resources:
        requests:
          cpu: 100m
          memory: 512Mi
    alertmanagerMain:
      resources:
        requests:
          cpu: 10m
          memory: 64Mi
EOF

echo "✅ cluster-monitoring-config applied"
echo ""
echo "Settings:"
echo "  Prometheus retention:      24h  (default: 15d)"
echo "  Prometheus retentionSize:  4GB  (hard cap on TSDB disk usage)"
echo "  Prometheus PVC request:    5Gi"
echo "  Prometheus CPU request:    100m"
echo "  Prometheus memory request: 512Mi"
echo "  Alertmanager CPU request:  10m"
echo "  Alertmanager memory:       64Mi"
