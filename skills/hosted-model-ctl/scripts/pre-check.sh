#!/usr/bin/env bash
# pre-check.sh — Verify host meets requirements for model deployment
# Usage: bash pre-check.sh HOST
#   HOST: rhtevan-work | rhel-ai

source "$(dirname "$0")/common.sh"

TARGET="${1:?Usage: pre-check.sh HOST (rhtevan-work|rhel-ai)}"
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

# 4. NVIDIA Container Toolkit / CDI
echo "4. Container GPU access (CDI)"
cdi_file=$(run_on_host "$TARGET" "ls /etc/cdi/nvidia.yaml 2>/dev/null" || echo "")
if [[ -n "$cdi_file" ]]; then
  pass "CDI spec: /etc/cdi/nvidia.yaml"
else
  fail "CDI spec not found — install nvidia-container-toolkit"
fi

# 5. Container images
echo "5. Container images"
case "$TARGET" in
  rhtevan-work)
    images=("docker.io/vllm/vllm-openai:latest" "ghcr.io/ggml-org/llama.cpp:server-cuda-b9994")
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
avail=$(run_on_host "$TARGET" "df -BG --output=avail / 2>/dev/null | tail -1 | tr -d ' G'" || echo "0")
if (( avail > 50 )); then
  pass "Disk: ${avail}G available"
else
  fail "Disk: only ${avail}G available (need >50G for model weights)"
fi

# Summary
echo
echo "=== Results: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
