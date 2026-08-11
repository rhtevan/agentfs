#!/usr/bin/env bash
# teardown.sh — Remove Skupper VAN infrastructure from all hosts
# Usage: bash teardown.sh
# Stops all sites, removes namespaces, removes systemd patches.
# Does NOT remove model containers (managed by hosted-model-ctl).

source "$(dirname "$0")/common.sh"

echo "=== Skupper Model Provider — TEARDOWN ==="
echo "  This will remove Skupper infrastructure from all 3 hosts."
echo "  Model containers will NOT be affected."
echo

# ── Phase 1: Stop local site ─────────────────────────────────
echo "Phase 1: Stop local site"

systemctl --user stop "skupper-${NAMESPACE}.service" 2>/dev/null || true
skupper --platform podman system stop -n "${NAMESPACE}" 2>/dev/null || true
echo "  ✅ Local site stopped"
echo

# ── Phase 2: Stop remote sites ────────────────────────────────
echo "Phase 2: Stop remote sites"

for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-${NAMESPACE}.service 2>/dev/null; skupper --platform podman system stop -n ${NAMESPACE} 2>/dev/null" || true
    echo "  ✅ $host site stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 3: Stop controllers ─────────────────────────────────
echo "Phase 3: Stop controllers"

# Local
systemctl --user stop skupper-controller.service 2>/dev/null || true
echo "  ✅ Local controller stopped"

for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-controller.service 2>/dev/null" || true
    echo "  ✅ $host controller stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 4: Remove auto-restart patches ──────────────────────
echo "Phase 4: Remove auto-restart patches"

# Restore original systemd units by removing patched ones
# (skupper system start will regenerate them on next setup)
for host in rhel-ai rhtevan-work localhost; do
  if [[ "$host" == "localhost" ]] || host_reachable "$host"; then
    run_on_host "$host" "
      rm -f ~/.local/share/skupper/system-controller/internal/scripts/start-watch.sh 2>/dev/null
      systemctl --user daemon-reload 2>/dev/null
    " || true
    echo "  ✅ $host patches removed"
  fi
done
echo

# ── Phase 5: Verify ───────────────────────────────────────────
echo "Phase 5: Verify"

# Check no skupper containers running
LOCAL_CONTAINERS=$(podman ps --filter label=application=skupper-v2 --format '{{.Names}}' 2>/dev/null | wc -l || echo "0")
echo "  Local skupper containers: $LOCAL_CONTAINERS"

for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    REMOTE_CONTAINERS=$(run_on_host "$host" "podman ps --filter label=application=skupper-v2 --format '{{.Names}}' 2>/dev/null | wc -l" || echo "?")
    echo "  $host skupper containers: $REMOTE_CONTAINERS"
  fi
done

echo
echo "✅ Teardown complete."
echo "   To fully remove all data: skupper --platform podman system uninstall -f"
echo "   To re-setup: bash setup.sh"
