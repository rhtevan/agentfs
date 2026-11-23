#!/usr/bin/env bash
# lib.sh — Shared helpers for crc-install scripts (sourced, not executed).
# Paths are overridable for sandbox tests; crc itself always uses ~/.crc.

CRC_MIRROR="${CRC_MIRROR:-https://mirror.openshift.com/pub/openshift-v4/clients/crc}"
CRC_BIN_DIR="${CRC_BIN_DIR:-$HOME/.local/bin}"
CRC_BIN="${CRC_BIN_DIR}/crc"
CRC_HOME="${CRC_HOME:-$HOME/.crc}"
CRC_STATE_DIR="${CRC_STATE_DIR:-$HOME/.local/share/crc-install}"   # upgrade notes + verified markers
CRC_STAGE_DIR="${CRC_STAGE_DIR:-$HOME/.cache/crc-install}"         # tarball downloads
CRC_DOMAIN="${CRC_DOMAIN:-crc}"
CRC_MIN_FREE_GB="${CRC_MIN_FREE_GB:-40}"   # 5.0.0 bundle is ~5.3 GB compressed; extracted bundle + VM disk grow far beyond
CRC_CMD_SKILL="${HOME}/.agents/skills/crc-cmd"
VIRSH=(virsh --connect qemu:///system)

# json_get FILE_OR_- KEY.PATH — print a value from JSON on stdin/file; empty on any error
json_get() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        d = d[k]
    print(d)
except Exception:
    pass' "$1"
}

# release_info VERSION|latest — print release-info.json (empty on failure)
release_info() { curl -fsSL --max-time 30 "${CRC_MIRROR}/$1/release-info.json" 2>/dev/null; }

# resolve_target [VERSION] — sets TARGET_VER and TARGET_OCP; returns 1 when the mirror has no such release
resolve_target() {
  local want="${1:-latest}" info
  info="$(release_info "$want")"
  TARGET_VER="$(json_get version.crcVersion <<<"$info")"
  TARGET_OCP="$(json_get version.openshiftVersion <<<"$info")"
  [[ -n "$TARGET_VER" && -n "$TARGET_OCP" ]]
}

# installed_version [BIN] — sets INST_VER and INST_OCP (empty when no runnable binary)
installed_version() {
  local bin="${1:-$CRC_BIN}" out
  INST_VER=""; INST_OCP=""
  [[ -x "$bin" ]] || return 1
  out="$("$bin" version -o json 2>/dev/null)" || return 1
  INST_VER="$(json_get version <<<"$out")"
  INST_OCP="$(json_get openshiftVersion <<<"$out")"
  [[ -n "$INST_VER" ]]
}

# vm_state — libvirt state of the crc domain: running | shut off | ... | absent
vm_state() {
  local s
  s="$("${VIRSH[@]}" domstate "$CRC_DOMAIN" 2>/dev/null | head -1)"
  echo "${s:-absent}"
}

pool_exists() { "${VIRSH[@]}" pool-info "$CRC_DOMAIN" >/dev/null 2>&1; }

# cluster_json — `crc status -o json` (exit code is 0 even on error, so callers parse .success)
cluster_json() { [[ -x "$CRC_BIN" ]] && "$CRC_BIN" status -o json 2>/dev/null; }

# cached_bundles — one path per line: *.crcbundle files and extracted bundle dirs
cached_bundles() {
  local p
  for p in "$CRC_HOME"/cache/crc_*; do
    [[ -e "$p" ]] && echo "$p"
  done
}

# old_binaries — crc-<version> backups left by an upgrade
old_binaries() {
  local p
  for p in "$CRC_BIN_DIR"/crc-[0-9]*; do
    [[ -x "$p" ]] && echo "$p"
  done
}

size_of() { du -sh "$@" 2>/dev/null | awk '{print $1}' | paste -sd' ' -; }
free_gb() { df -BG --output=avail "${1:-$HOME}" 2>/dev/null | tail -1 | tr -dc '0-9'; }

# detect_mode — sets MODE: FRESH | RESUME | CONVERGED | UPGRADE | REPAIR (needs TARGET_VER)
#   FRESH     no crc binary, no VM, no machine dir
#   REPAIR    no usable crc binary, but a crc domain / pool / machine dir is left over
#   UPGRADE   crc binary at another version (up- or downgrade: the cluster must be recreated)
#   RESUME    binary at target, cluster not (yet) running at the target OCP version
#   CONVERGED binary at target and the cluster runs the target OCP version
detect_mode() {
  local st js leftovers=0
  st="$(vm_state)"
  [[ "$st" != absent ]] && leftovers=1
  pool_exists && leftovers=1
  [[ -d "$CRC_HOME/machines/$CRC_DOMAIN" ]] && leftovers=1
  if ! installed_version; then
    if [[ $leftovers -eq 1 ]]; then MODE=REPAIR; else MODE=FRESH; fi
    return 0
  fi
  if [[ "$INST_VER" != "$TARGET_VER" ]]; then MODE=UPGRADE; return 0; fi
  js="$(cluster_json)"
  if [[ "$(json_get success <<<"$js")" == True && "$(json_get crcStatus <<<"$js")" == Running \
        && "$(json_get openshiftVersion <<<"$js")" == "$TARGET_OCP" ]]; then
    MODE=CONVERGED
  else
    MODE=RESUME
  fi
}
