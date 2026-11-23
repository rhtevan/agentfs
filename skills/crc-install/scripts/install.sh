#!/usr/bin/env bash
# install.sh — Guided install / upgrade / repair / uninstall of CRC (OpenShift Local).
# Usage: bash install.sh [--dry-run] [--version X.Y.Z] [--confirm-delete] [--no-start] [--uninstall]
# Exit: 0 done/converged · 1 failure · 2 usage · 3 needs sudo (prints the command) · 4 needs deletion confirmation (Gate A)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-install" "1.0.0" 2>/dev/null || true

DRY=0; WANT=latest; CONFIRM=0; NOSTART=0; UNINSTALL=0
START_TIMEOUT="${CRC_START_TIMEOUT:-2700}"   # crc start of a large VM incl. operator settle can take 20–40 min
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY=1; shift ;;
    --version)        WANT="${2:-}"; shift 2 ;;
    --confirm-delete) CONFIRM=1; shift ;;
    --no-start)       NOSTART=1; shift ;;
    --uninstall)      UNINSTALL=1; shift ;;
    -h|--help)        sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "❌ Unknown option: $1"; exit 2 ;;
  esac
done
[[ -n "$WANT" ]] || { echo "❌ --version needs a value"; exit 2; }
export PATH="$CRC_BIN_DIR:$PATH"   # crcstart/crcstop call `crc` from PATH

STEP=0
step() { STEP=$((STEP + 1)); echo; echo "── Phase $STEP: $* ──"; }
done_() { trace_step "$STEP" "$1" "${2:-0}" "${3:-}" 2>/dev/null || true; }
die() { echo "❌ $*"; trace_step "$STEP" "fail" 1 "$*" 2>/dev/null || true; trace_end 2>/dev/null || true; exit 1; }
finish() { trace_end 2>/dev/null || true; exit "${1:-0}"; }

# ── actions ────────────────────────────────────────────────────────────

ensure_wrappers() {   # crcstart/crcstop from the crc-cmd skill (dry-run gate first)
  local out res
  [[ -f "$CRC_CMD_SKILL/scripts/install.sh" ]] || die "crc-cmd skill missing ($CRC_CMD_SKILL) — crcstart/crcstop are required"
  out="$(bash "$CRC_CMD_SKILL/scripts/install.sh" --dry-run 2>&1)"
  res="$(grep -o 'DRY_RUN_RESULT=[A-Z]*' <<<"$out" | tail -1)"
  case "$res" in
    DRY_RUN_RESULT=CONVERGED) echo "  ✅ crcstart/crcstop installed" ;;
    DRY_RUN_RESULT=PENDING)   bash "$CRC_CMD_SKILL/scripts/install.sh" >/dev/null 2>&1 \
                                && echo "  ✅ crcstart/crcstop installed by crc-cmd" \
                                || die "crc-cmd install.sh failed" ;;
    *) echo "$out"; die "crc-cmd dry-run gave no DRY_RUN_RESULT" ;;
  esac
}

snapshot_notes() {   # rebuild to-do list for the new cluster (not a data backup)
  local f oc
  mkdir -p "$CRC_STATE_DIR"
  f="$CRC_STATE_DIR/upgrade-notes-${INST_VER:-none}-to-${TARGET_VER}-$(date +%Y%m%d-%H%M%S).txt"
  oc="$CRC_HOME/bin/oc/oc"; [[ -x "$oc" ]] || oc="$(command -v oc 2>/dev/null || true)"
  {
    echo "# CRC upgrade notes — $(date -Iseconds)"
    echo "# old: crc ${INST_VER:-?} (OpenShift ${INST_OCP:-?}) → new: crc $TARGET_VER (OpenShift $TARGET_OCP)"
    echo "# Rebuild list only: the old cluster and all its data are deleted."
    echo; echo "## crc config view"; "$CRC_BIN" config view 2>&1
    if [[ -n "$oc" ]] && "$oc" whoami >/dev/null 2>&1; then
      echo; echo "## subscriptions";  "$oc" get subscriptions.operators.coreos.com -A 2>&1
      echo; echo "## CSVs";           "$oc" get csv -A --no-headers 2>&1 | awk '!seen[$2]++ {print $1, $2, $NF}'
      echo; echo "## user namespaces"; "$oc" get ns --no-headers -o custom-columns=NAME:.metadata.name 2>&1 | grep -vE '^(openshift|kube-|default$)'
      command -v helm >/dev/null && { echo; echo "## helm releases"; helm list -A 2>&1; }
    else
      echo; echo "## cluster not reachable — no operator list captured"
    fi
  } >"$f"
  echo "  ✅ Notes: $f"
}

stop_vm() {   # graceful stop via crcstop — never `crc stop` (driver force-kills after 120 s)
  [[ "$(vm_state)" == running ]] || { echo "  ✅ VM not running"; return 0; }
  ensure_wrappers
  "$CRC_BIN_DIR/crcstop" || echo "  ⚠️  crcstop hit its timeout and force-stopped the VM"
}

cleanup_lingering() {   # crc-ctl rule 3: no VM/process left behind after crcstop
  [[ "$(vm_state)" == running ]] && { "${VIRSH[@]}" destroy "$CRC_DOMAIN" >/dev/null 2>&1; echo "  ⚠️  VM still running — destroyed"; }
  if pgrep -f "qemu.*guest=${CRC_DOMAIN}," >/dev/null 2>&1; then
    echo "  ⚠️  qemu process for '$CRC_DOMAIN' still present: $(pgrep -f "qemu.*guest=${CRC_DOMAIN}," | tr '\n' ' ')"
  fi
  if systemctl --user cat crc-daemon.service >/dev/null 2>&1; then
    systemctl --user stop crc-daemon.service crc-daemon.socket 2>/dev/null
    echo "  ✅ crc-daemon stopped (crc setup re-creates it for the new binary)"
  fi
  pkill -f "${CRC_BIN_DIR}/crc daemon" 2>/dev/null && echo "  ✅ stray 'crc daemon' killed"
  return 0
}

delete_cluster() {   # $1 = binary that created the cluster; virsh fallback for leftovers
  local bin="$1"
  if [[ -x "$bin" ]] && { [[ "$(vm_state)" != absent ]] || [[ -d "$CRC_HOME/machines/$CRC_DOMAIN" ]]; }; then
    "$bin" delete -f && echo "  ✅ crc delete -f ($bin)" || echo "  ⚠️  crc delete -f failed — removing leftovers directly"
  fi
  if [[ "$(vm_state)" != absent ]]; then
    "${VIRSH[@]}" destroy "$CRC_DOMAIN" >/dev/null 2>&1
    "${VIRSH[@]}" undefine "$CRC_DOMAIN" --nvram >/dev/null 2>&1 || "${VIRSH[@]}" undefine "$CRC_DOMAIN" >/dev/null 2>&1
    echo "  ✅ virsh undefine $CRC_DOMAIN --nvram"
  fi
  if pool_exists; then
    "${VIRSH[@]}" pool-destroy "$CRC_DOMAIN" >/dev/null 2>&1
    "${VIRSH[@]}" pool-undefine "$CRC_DOMAIN" >/dev/null 2>&1 && echo "  ✅ virsh pool-undefine $CRC_DOMAIN"
  fi
  [[ -d "$CRC_HOME/machines/$CRC_DOMAIN" ]] && rm -rf "${CRC_HOME:?}/machines/$CRC_DOMAIN" && echo "  ✅ removed $CRC_HOME/machines/$CRC_DOMAIN"
  [[ "$(vm_state)" == absent ]] || die "domain '$CRC_DOMAIN' still defined — run: virsh -c qemu:///system undefine $CRC_DOMAIN --nvram"
  pool_exists && die "pool '$CRC_DOMAIN' still defined — run: virsh -c qemu:///system pool-undefine $CRC_DOMAIN"
  echo "  ✅ no crc domain, pool or machine dir left"
}

download_install() {   # sha256-verified mirror tarball → $CRC_BIN (old binary kept as crc-<old> until prune)
  local stage="$CRC_STAGE_DIR/$TARGET_VER" url="$CRC_MIRROR/$TARGET_VER" new
  [[ "$(uname -m)" == x86_64 ]] || die "only linux amd64 is supported (got $(uname -m))"
  mkdir -p "$stage" "$CRC_BIN_DIR"
  curl -fsSL --max-time 60 "$url/sha256sum.txt" -o "$stage/sha256sum.txt" || die "download failed: $url/sha256sum.txt"
  curl -fSL --progress-bar --max-time 1800 "$url/crc-linux-amd64.tar.xz" -o "$stage/crc-linux-amd64.tar.xz" \
    || die "download failed: $url/crc-linux-amd64.tar.xz"
  ( cd "$stage" && grep ' crc-linux-amd64.tar.xz$' sha256sum.txt | sha256sum -c --quiet - ) \
    || { rm -f "$stage/crc-linux-amd64.tar.xz"; die "sha256 mismatch for crc-linux-amd64.tar.xz — download removed, binary unchanged"; }
  echo "  ✅ sha256 verified ($stage/crc-linux-amd64.tar.xz)"
  rm -rf "$stage/extract"; mkdir -p "$stage/extract"
  tar -xJf "$stage/crc-linux-amd64.tar.xz" -C "$stage/extract" || die "extract failed"
  new="$(find "$stage/extract" -type f -name crc -perm -u+x | head -1)"
  installed_version "$new" && [[ "$INST_VER" == "$TARGET_VER" ]] || die "extracted binary is not crc $TARGET_VER (got '${INST_VER:-none}')"
  if installed_version "$CRC_BIN" && [[ "$INST_VER" != "$TARGET_VER" ]]; then
    mv -f "$CRC_BIN" "$CRC_BIN_DIR/crc-$INST_VER" && echo "  ✅ old binary kept as $CRC_BIN_DIR/crc-$INST_VER (rollback until prune.sh)"
  fi
  install -m 0755 "$new" "$CRC_BIN" || die "cannot write $CRC_BIN"
  rm -rf "$stage/extract"
  installed_version || die "$CRC_BIN not runnable after install"
  echo "  ✅ $CRC_BIN → crc $INST_VER (OpenShift $INST_OCP)"
}

run_setup() {   # Gate B: crc setup needs sudo (crc-admin-helper) and downloads the bundle
  if "$CRC_BIN" setup --check-only >/dev/null 2>&1; then
    echo "  ✅ crc setup --check-only passes"; return 0
  fi
  if sudo -n true 2>/dev/null; then
    echo "  ℹ️  running crc setup (downloads the OpenShift $TARGET_OCP bundle, ~5 GB)"
    "$CRC_BIN" setup || die "crc setup failed — see ~/.crc/crc.log"
    return 0
  fi
  echo "  🔒 crc setup needs sudo (crc-admin-helper) and downloads the ~5 GB bundle into $CRC_HOME/cache."
  echo "     Run in your own terminal, then re-run this script (it resumes at Phase 'setup'):"
  echo
  echo "       $CRC_BIN setup"
  echo
  done_ "setup" 3 "needs_sudo"
  finish 3
}

start_cluster() {   # agent-run start via crcstart — never `crc start` directly
  ensure_wrappers
  echo "  ℹ️  $("$CRC_BIN" version | tr '\n' ' ')"
  echo "  ℹ️  crcstart (timeout ${START_TIMEOUT}s)…"
  timeout "$START_TIMEOUT" "$CRC_BIN_DIR/crcstart"
  local rc=$?
  [[ $rc -eq 124 ]] && die "crcstart exceeded ${START_TIMEOUT}s — check: crc status; tail ~/.crc/crc.log"
  [[ $rc -eq 0 ]] || die "crcstart failed (exit $rc) — see ~/.crc/crc.log"
}

verify_cluster() {   # status Running + target OCP version; writes the marker prune.sh requires
  local js oc who
  js="$(cluster_json)"
  [[ "$(json_get success <<<"$js")" == True ]] || die "crc status: $(json_get error <<<"$js")"
  [[ "$(json_get crcStatus <<<"$js")" == Running ]] || die "crc status: $(json_get crcStatus <<<"$js") (want Running)"
  [[ "$(json_get openshiftVersion <<<"$js")" == "$TARGET_OCP" ]] \
    || die "OpenShift $(json_get openshiftVersion <<<"$js") running, want $TARGET_OCP"
  echo "  ✅ crc Running, OpenShift $(json_get openshiftStatus <<<"$js") $TARGET_OCP"
  oc="$CRC_HOME/bin/oc/oc"; [[ -x "$oc" ]] || oc="$(command -v oc 2>/dev/null || true)"
  if [[ -n "$oc" ]] && who="$("$oc" whoami 2>/dev/null)"; then
    echo "  ✅ oc whoami: $who"
  else
    echo "  ⚠️  oc whoami failed — run: eval \$(crc oc-env); oc login -u kubeadmin https://api.crc.testing:6443"
  fi
  mkdir -p "$CRC_STATE_DIR"
  echo "verified $(date -Iseconds) crc $TARGET_VER OpenShift $TARGET_OCP" >"$CRC_STATE_DIR/verified-$TARGET_VER"
  echo "  ✅ marker: $CRC_STATE_DIR/verified-$TARGET_VER (prune.sh may now run)"
}

# ── uninstall ──────────────────────────────────────────────────────────

if [[ $UNINSTALL -eq 1 ]]; then
  echo "=== CRC — UNINSTALL ==="
  installed_version || true
  echo "  Removes: VM '$CRC_DOMAIN' + its disk, libvirt pool, $CRC_BIN (crc ${INST_VER:-none}), old crc-* binaries,"
  echo "           $CRC_HOME/{cache,bin,machines}, $CRC_STAGE_DIR, crc setup changes (crc cleanup)"
  echo "  Keeps:   $CRC_HOME/crc.json, pull secret, $CRC_STATE_DIR/upgrade-notes-*, crcstart/crcstop"
  if [[ $DRY -eq 1 ]]; then echo; echo "DRY_RUN_RESULT=PENDING"; finish 0; fi
  if [[ $CONFIRM -eq 0 ]]; then
    echo; echo "  👤 Gate A: the cluster and all its data are destroyed. After the user says yes, re-run with --confirm-delete."
    done_ "gate_a" 4 "uninstall"; finish 4
  fi
  step "stop";     stop_vm; cleanup_lingering; done_ "stop"
  step "delete";   delete_cluster "$CRC_BIN"; done_ "delete"
  step "cleanup"
  if [[ -x "$CRC_BIN" ]]; then
    "$CRC_BIN" cleanup && echo "  ✅ crc cleanup" || echo "  ⚠️  crc cleanup failed — run it yourself: $CRC_BIN cleanup"
  fi
  rm -f "$CRC_BIN" "$CRC_STATE_DIR"/verified-*
  while read -r b; do [[ -n "$b" ]] && rm -f "$b"; done < <(old_binaries)
  rm -rf "${CRC_HOME:?}/cache" "${CRC_HOME:?}/bin" "${CRC_HOME:?}/machines" "${CRC_STAGE_DIR:?}"
  echo "  ✅ binaries, cache and downloads removed; crc.json kept"
  done_ "cleanup"; finish 0
fi

# ── install / upgrade / repair ─────────────────────────────────────────

echo "=== CRC — INSTALL ==="
resolve_target "$WANT" || die "release '$WANT' not found on $CRC_MIRROR (offline or wrong version)"
detect_mode
OLD_VER="${INST_VER:-}"; OLD_OCP="${INST_OCP:-}"; OLD_BIN="$CRC_BIN"
echo "  Target: crc $TARGET_VER (OpenShift $TARGET_OCP) · installed: ${OLD_VER:-none} · MODE=$MODE"
done_ "assess" 0 "mode=$MODE"

DIR=""
if [[ $MODE == UPGRADE ]]; then
  DIR=upgrade
  [[ "$(printf '%s\n' "$OLD_VER" "$TARGET_VER" | sort -V | head -1)" == "$TARGET_VER" ]] && DIR=downgrade
fi

echo; echo "Plan:"
case "$MODE" in
  CONVERGED)
    echo "  nothing to do — crc $TARGET_VER runs OpenShift $TARGET_OCP"
    [[ $DRY -eq 1 ]] && echo && echo "DRY_RUN_RESULT=CONVERGED"
    finish 0 ;;
  FRESH)   echo "  1. download + verify crc $TARGET_VER → $CRC_BIN" ;;
  RESUME)  echo "  1. (binary already at $TARGET_VER — no download)" ;;
  REPAIR)  echo "  1. 👤 Gate A, then remove leftover domain/pool/machine dir (virsh undefine --nvram)"
           echo "  2. download + verify crc $TARGET_VER → $CRC_BIN" ;;
  UPGRADE) echo "  ⚠️  $DIR crc $OLD_VER (OpenShift $OLD_OCP) → $TARGET_VER (OpenShift $TARGET_OCP): no in-place upgrade —"
           echo "     the cluster VM and ALL its data (operators, workloads, PVs) are deleted and recreated."
           echo "  1. 👤 Gate A (--confirm-delete)"
           echo "  2. snapshot rebuild notes → $CRC_STATE_DIR/upgrade-notes-*"
           echo "  3. crcstop → lingering-process cleanup → crc delete -f (old binary)"
           echo "  4. download + verify crc $TARGET_VER; old binary kept as crc-$OLD_VER until prune" ;;
esac
echo "  ·  👤 Gate B: crc setup (sudo; downloads the ~5 GB bundle) unless --check-only passes"
if [[ $NOSTART -eq 1 ]]; then echo "  ·  stop before start (--no-start)"
else echo "  ·  crcstart (crc-cmd wrapper, timeout ${START_TIMEOUT}s) → verify Running + OpenShift $TARGET_OCP"; fi
echo "  ·  afterwards: prune.sh removes old bundles/binaries/downloads (only after verify)"

if ! ls "$CRC_HOME"/cache/crc_*_"${TARGET_OCP}"_* >/dev/null 2>&1; then
  FREE="$(free_gb "$HOME")"
  [[ "${FREE:-0}" -ge "$CRC_MIN_FREE_GB" ]] || die "only ${FREE:-?} GiB free on $HOME, need ≥ $CRC_MIN_FREE_GB GiB"
  echo "  ✅ disk: $FREE GiB free (≥ $CRC_MIN_FREE_GB)"
fi

if [[ $DRY -eq 1 ]]; then
  [[ $MODE == UPGRADE || $MODE == REPAIR ]] && echo "  ⚠️  real run stops at Gate A (exit 4) until --confirm-delete"
  echo; echo "DRY_RUN_RESULT=PENDING"; finish 0
fi

if [[ ($MODE == UPGRADE || $MODE == REPAIR) && $CONFIRM -eq 0 ]]; then
  echo; echo "👤 Gate A — will destroy:"
  [[ "$(vm_state)" != absent ]] && echo "   • libvirt domain '$CRC_DOMAIN' ($(vm_state)) + NVRAM"
  pool_exists && echo "   • libvirt pool '$CRC_DOMAIN'"
  [[ -d "$CRC_HOME/machines/$CRC_DOMAIN" ]] && echo "   • $CRC_HOME/machines/$CRC_DOMAIN ($(size_of "$CRC_HOME/machines/$CRC_DOMAIN"))"
  [[ $MODE == UPGRADE ]] && echo "   • every operator, workload and PV in the OpenShift $OLD_OCP cluster"
  echo "   Ask the user. Only after an explicit yes, re-run with --confirm-delete."
  done_ "gate_a" 4 "mode=$MODE"; finish 4
fi

if [[ $MODE == UPGRADE ]]; then
  step "snapshot";  INST_VER="$OLD_VER"; INST_OCP="$OLD_OCP"; snapshot_notes; done_ "snapshot"
fi
if [[ $MODE == UPGRADE || $MODE == REPAIR ]]; then
  step "teardown";  stop_vm; cleanup_lingering; delete_cluster "$OLD_BIN"; done_ "teardown"
fi
if [[ $MODE != RESUME ]]; then
  step "download";  download_install; done_ "download"
fi
step "setup";       run_setup; done_ "setup"
if [[ $NOSTART -eq 1 ]]; then
  echo; echo "✅ crc $TARGET_VER installed and set up (--no-start). Next: re-run without --no-start."
  finish 0
fi
step "start";       start_cluster; done_ "start"
step "verify";      verify_cluster; done_ "verify"
echo
echo "✅ crc $TARGET_VER running OpenShift $TARGET_OCP"
echo "   Next: prune.sh --dry-run → prune.sh; then crc-post-setup-config and the operator skills."
finish 0
