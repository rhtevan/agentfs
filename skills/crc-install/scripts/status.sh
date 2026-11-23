#!/usr/bin/env bash
# status.sh — Read-only assessment of the CRC installation (Phase 0).
# Usage: bash status.sh [--version X.Y.Z]
# Exit: 0 assessed (MODE=… line printed) · 1 mirror unreachable / unknown version · 2 usage
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-install" "1.0.0" 2>/dev/null || true

WANT=latest
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) WANT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "❌ Unknown option: $1"; exit 2 ;;
  esac
done
[[ -n "$WANT" ]] || { echo "❌ --version needs a value"; exit 2; }

echo "=== CRC — INSTALL STATUS ==="

# 1. target release from the mirror
if ! resolve_target "$WANT"; then
  echo "  ❌ Target:    release '$WANT' not found on $CRC_MIRROR (offline or wrong version)"
  trace_step 1 "target" 1 "want=$WANT" 2>/dev/null || true; trace_end 2>/dev/null || true
  exit 1
fi
echo "  ℹ️  Target:    crc $TARGET_VER (OpenShift $TARGET_OCP)"
trace_step 1 "target" 0 "ver=$TARGET_VER" 2>/dev/null || true

# 2. installed binary (+ others on PATH that would shadow it)
if installed_version; then
  echo "  ✅ Binary:    $CRC_BIN → crc $INST_VER (OpenShift $INST_OCP)"
else
  echo "  ⚠️  Binary:    $CRC_BIN not installed"
fi
P="$(command -v crc 2>/dev/null || true)"
[[ -n "$P" && "$P" != "$CRC_BIN" ]] && echo "  ⚠️  PATH:      'crc' resolves to $P (not $CRC_BIN)"
while read -r b; do [[ -n "$b" ]] && echo "  ℹ️  Old binary: $b ($(size_of "$b"), removed by prune.sh)"; done < <(old_binaries)

# 3. libvirt domain / pool / machine dir
ST="$(vm_state)"
case "$ST" in
  absent) echo "  ✅ VM:        no libvirt domain '$CRC_DOMAIN'" ;;
  *)      echo "  ℹ️  VM:        domain '$CRC_DOMAIN' is $ST" ;;
esac
pool_exists && echo "  ℹ️  Pool:      libvirt pool '$CRC_DOMAIN' defined"
[[ -d "$CRC_HOME/machines/$CRC_DOMAIN" ]] && echo "  ℹ️  Machine:   $CRC_HOME/machines/$CRC_DOMAIN ($(size_of "$CRC_HOME/machines/$CRC_DOMAIN"))"
trace_step 2 "binary_vm" 0 "inst=${INST_VER:-none} vm=$ST" 2>/dev/null || true

# 4. cluster state (only meaningful with a binary)
if [[ -n "${INST_VER:-}" ]]; then
  JS="$(cluster_json)"
  if [[ "$(json_get success <<<"$JS")" == True ]]; then
    echo "  ℹ️  Cluster:   crc $(json_get crcStatus <<<"$JS"), OpenShift $(json_get openshiftStatus <<<"$JS") $(json_get openshiftVersion <<<"$JS")"
  else
    echo "  ℹ️  Cluster:   $(json_get error <<<"$JS")"
  fi
  if "$CRC_BIN" setup --check-only >/dev/null 2>&1; then
    echo "  ✅ Setup:     crc setup --check-only passes"
  else
    echo "  ⚠️  Setup:     crc setup needed (crc setup --check-only failed)"
  fi
fi

# 5. cache, downloads, config
N=0
while read -r b; do
  [[ -z "$b" ]] && continue
  N=$((N + 1))
  tag="old — removed by prune.sh"
  [[ "$b" == *"_${TARGET_OCP}_"* || "$b" == *"_${TARGET_OCP}" ]] && tag="target"
  echo "  ℹ️  Bundle:    $b ($(size_of "$b"), $tag)"
done < <(cached_bundles)
[[ $N -eq 0 ]] && echo "  ℹ️  Bundle:    none cached (crc setup downloads it)"
if [[ -d "$CRC_STAGE_DIR" ]] && [[ -n "$(ls -A "$CRC_STAGE_DIR" 2>/dev/null)" ]]; then
  echo "  ℹ️  Downloads: $CRC_STAGE_DIR ($(size_of "$CRC_STAGE_DIR"), removed by prune.sh)"
fi
if [[ -f "$CRC_HOME/crc.json" ]]; then
  PS="$(json_get pull-secret-file <"$CRC_HOME/crc.json")"
  echo "  ✅ Config:    $CRC_HOME/crc.json (cpus $(json_get cpus <"$CRC_HOME/crc.json"), memory $(json_get memory <"$CRC_HOME/crc.json") MiB, disk $(json_get disk-size <"$CRC_HOME/crc.json") GiB)"
  if [[ -n "$PS" && -r "$PS" ]]; then echo "  ✅ Pull secret: $PS"
  elif [[ -n "$PS" ]]; then echo "  ❌ Pull secret: $PS not readable"
  else echo "  ⚠️  Pull secret: not set in crc.json (crc start will prompt)"; fi
else
  echo "  ⚠️  Config:    $CRC_HOME/crc.json missing (crc defaults: 4 cpus, 10752 MiB)"
fi
echo "  ℹ️  Free disk: $(free_gb "$HOME") GiB on $HOME (needs ≥ $CRC_MIN_FREE_GB)"
for w in crcstart crcstop; do
  if [[ -x "$CRC_BIN_DIR/$w" ]]; then echo "  ✅ Wrapper:   $w"; else echo "  ⚠️  Wrapper:   $w missing (crc-cmd skill installs it)"; fi
done
# oc lives in ~/.crc/bin/oc (symlink into the current bundle); new shells need it on PATH.
# Completion needs nothing: bash-completion ships fallback loaders (_oc, _crc → "<cmd> completion bash").
RC_HIT=""
for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME"/.bashrc.d/*.sh; do
  [[ -f "$rc" ]] || continue
  if grep -v '^[[:space:]]*#' "$rc" 2>/dev/null | grep -qE '\.crc/bin/oc|crc oc-env'; then RC_HIT="$rc"; break; fi
done
if [[ -n "$RC_HIT" ]]; then
  echo "  ✅ oc PATH:   $CRC_HOME/bin/oc (via ${RC_HIT/#$HOME/\~})"
else
  echo "  ⚠️  oc PATH:   not set for new shells — add to ~/.bashrc: [ -d \"\$HOME/.crc/bin/oc\" ] && PATH=\"\$HOME/.crc/bin/oc:\$PATH\""
fi
if command -v virt-manager >/dev/null 2>&1; then
  echo "  ℹ️  virt-manager: installed (optional)"
else
  echo "  ℹ️  virt-manager: not installed (optional, sudo dnf install virt-manager)"
fi
trace_step 3 "cache_config" 0 "bundles=$N" 2>/dev/null || true

# 6. verdict
detect_mode
echo
case "$MODE" in
  FRESH)     echo "MODE=FRESH       — nothing installed; install.sh installs crc $TARGET_VER" ;;
  RESUME)    echo "MODE=RESUME      — crc $TARGET_VER installed, cluster not running $TARGET_OCP; install.sh continues at setup/start" ;;
  CONVERGED) echo "MODE=CONVERGED   — crc $TARGET_VER running OpenShift $TARGET_OCP" ;;
  UPGRADE)   echo "MODE=UPGRADE     — crc $INST_VER → $TARGET_VER; the cluster VM is deleted and recreated (data loss)" ;;
  REPAIR)    echo "MODE=REPAIR      — no usable crc binary but VM/pool/machine leftovers; install.sh removes them (Gate A)" ;;
esac
trace_step 4 "mode" 0 "mode=$MODE" 2>/dev/null || true
trace_end 2>/dev/null || true
exit 0
