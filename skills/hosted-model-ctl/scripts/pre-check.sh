#!/usr/bin/env bash
# pre-check.sh — Verify host meets requirements for model deployment
# Usage: bash pre-check.sh HOST
#   HOST: rhtevan-work | rhel-ai

source "$(dirname "$0")/common.sh"

TARGET="${1:?Usage: pre-check.sh HOST (rhtevan-work|rhel-ai)}"
host_enabled "$TARGET" || { host_disabled_msg "$TARGET" >&2; exit 2; }
PASSED=0
FAILED=0

pass() { echo "  ✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ❌ $1"; FAILED=$((FAILED + 1)); }
warn() { echo "  ⚠️  $1"; }

echo "=== Pre-Check: $TARGET ==="
echo

# 1. SSH connectivity
echo "1. SSH connectivity"
if ssh -o ConnectTimeout=5 "$TARGET" 'echo ok' &>/dev/null; then
  pass "SSH to $TARGET"
else
  fail "Cannot SSH to $TARGET"
  echo "Aborting — SSH required for all further checks."
  exit 1
fi

# 2. Podman
echo "2. Container runtime"
podman_ver=$(run_on_host "$TARGET" "podman --version 2>/dev/null" || echo "")
if [[ -n "$podman_ver" ]]; then
  pass "Podman: $podman_ver"
else
  fail "Podman not found"
fi

# 3. NVIDIA GPU
echo "3. NVIDIA GPU"
gpu_info=$(run_on_host "$TARGET" "ls /dev/nvidia* 2>/dev/null | head -1" || echo "")
if [[ -n "$gpu_info" ]]; then
  pass "NVIDIA device nodes found"
else
  fail "No NVIDIA device nodes in /dev/"
fi

drv_ver=$(run_on_host "$TARGET" "nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1" || echo "")
if [[ -n "$drv_ver" ]]; then
  pass "NVIDIA driver loaded: $drv_ver"
else
  fail "nvidia-smi cannot reach the driver (nvidia module not loaded — nouveau active or kmod missing for running kernel?)"
fi

# akmods (Fedora/RPM Fusion) exits 0 even when the kmod build fails, so a
# kernel update can silently leave the host on nouveau. Look for the log.
akmod_ver=$(run_on_host "$TARGET" "rpm -q akmod-nvidia >/dev/null 2>&1 && rpm -q --qf '%{VERSION}' akmod-nvidia" || echo "")
if [[ -n "$akmod_ver" ]]; then
  failed_log=$(run_on_host "$TARGET" "ls /var/cache/akmods/nvidia/${akmod_ver}-*-for-\$(uname -r).failed.log 2>/dev/null | head -1" || echo "")
  if [[ -z "$failed_log" ]]; then
    pass "akmods: no failed nvidia ${akmod_ver} build for running kernel"
  else
    fail "akmods: nvidia ${akmod_ver} failed to build for running kernel — see ${failed_log}"
  fi
fi

# 4. NVIDIA Container Toolkit / CDI
echo "4. Container GPU access (CDI)"
cdi_file=$(run_on_host "$TARGET" "ls /etc/cdi/nvidia.yaml 2>/dev/null" || echo "")
if [[ -n "$cdi_file" ]]; then
  pass "CDI spec: /etc/cdi/nvidia.yaml"
else
  fail "CDI spec not found — install nvidia-container-toolkit"
fi

# A CDI spec generated for an older driver references library files that
# no longer exist; podman then fails to inject devices/libs at start.
cdi_ver=$(run_on_host "$TARGET" "f=/var/run/cdi/nvidia.yaml; [ -f \$f ] || f=/etc/cdi/nvidia.yaml; grep -oE 'libcuda\.so\.[0-9]+(\.[0-9]+)+' \$f 2>/dev/null | head -1 | sed 's/^libcuda\.so\.//'" || echo "")
if [[ -z "$drv_ver" ]]; then
  warn "CDI driver match: skipped (driver not loaded)"
elif [[ -z "$cdi_ver" ]]; then
  warn "CDI driver match: could not read driver version from CDI spec"
elif [[ "$cdi_ver" == "$drv_ver" ]]; then
  pass "CDI spec matches loaded driver ($cdi_ver)"
else
  fail "CDI spec is for driver $cdi_ver but $drv_ver is loaded — run: sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml"
fi

# 5. Container images
echo "5. Container images"
case "$TARGET" in
  rhtevan-work)
    images=("docker.io/vllm/vllm-openai:latest" "ghcr.io/ggml-org/llama.cpp@sha256:f8e7c336e3660804f6bc35a4147dbfdf1ddae9b7c3c50d412fab49b323e28fea")  # llama.cpp b12648
    ;;
  rhel-ai)
    images=("registry.redhat.io/rhelai1/instructlab-nvidia-rhel9:1.5.0")
    ;;
  *)
    images=()
    ;;
esac

for img in "${images[@]}"; do
  found=$(run_on_host "$TARGET" "podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -F '$img'" || echo "")
  if [[ -n "$found" ]]; then
    pass "Image: $img"
  else
    warn "Image not found: $img (will be pulled on first setup)"
  fi
done

# 6. HuggingFace cache
echo "6. HuggingFace cache"
hf_exists=$(run_on_host "$TARGET" "test -d ~/.cache/huggingface && echo yes" || echo "no")
if [[ "$hf_exists" == "yes" ]]; then
  pass "HF cache directory exists"
else
  warn "HF cache not found — will be created on first setup"
fi

# 7. Disk space
echo "7. Disk space"
# Measure where model weights / HF cache live ($HOME), not '/': on image-mode
# (bootc) hosts such as rhel-ai, '/' is a read-only overlay that always shows 0.
avail=$(run_on_host "$TARGET" "df -BG --output=avail \$HOME 2>/dev/null | tail -1 | tr -d ' G'" || echo "0")
if (( avail > 50 )); then
  pass "Disk: ${avail}G available"
else
  fail "Disk: only ${avail}G available (need >50G for model weights)"
fi

# Summary
echo
echo "=== Results: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
