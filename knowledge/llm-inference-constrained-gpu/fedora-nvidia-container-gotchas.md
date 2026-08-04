---
title: Fedora NVIDIA + Container Gotchas
created: 2026-08-04
tags: [fedora, nvidia, podman, container, rpmfusion, selinux]
---

# Fedora NVIDIA + Container Gotchas

A collection of pitfalls encountered when running GPU-accelerated
containers on Fedora with RPMFusion NVIDIA drivers and Podman.

## No `nvidia-smi` on Fedora RPMFusion

**Problem:** RPMFusion's `xorg-x11-drv-nvidia` package does not include
the `nvidia-smi` binary. The NVIDIA CUDA base container images also
don't include it. Standard GPU verification workflows fail.

**Workaround:** Use Python ctypes with the NVML library, which IS
installed:

```python
import ctypes

nv = ctypes.CDLL("libnvidia-ml.so.1")
nv.nvmlInit()

count = ctypes.c_uint()
nv.nvmlDeviceGetCount(ctypes.byref(count))
print(f"GPU count: {count.value}")

handle = ctypes.c_void_p()
nv.nvmlDeviceGetHandleByIndex(0, ctypes.byref(handle))

name = ctypes.create_string_buffer(256)
nv.nvmlDeviceGetName(handle, name, 256)
print(f"GPU name: {name.value.decode()}")

class MemInfo(ctypes.Structure):
    _fields_ = [("total", ctypes.c_ulonglong),
                ("free", ctypes.c_ulonglong),
                ("used", ctypes.c_ulonglong)]

mi = MemInfo()
nv.nvmlDeviceGetMemoryInfo(handle, ctypes.byref(mi))
print(f"VRAM total: {mi.total / 1024**3:.1f} GB")
print(f"VRAM free:  {mi.free / 1024**3:.1f} GB")

nv.nvmlShutdown()
```

## Podman `pasta` Network Breaks Port Forwarding

**Problem:** Podman's default network mode (`pasta`/`slirp4netns`)
causes `Connection reset by peer` (curl exit code 56) when accessing
forwarded ports, even though the container is listening correctly.
The port appears open but connections are reset.

**Workaround:** Use `--network host` instead of port forwarding:

```bash
# ❌ Fails with pasta
podman run -d -p 8000:8000 <image>

# ✅ Works
podman run -d --network host <image> --port 8000
```

## Podman Short-Name Resolution Fails Without TTY

**Problem:** When running Podman via SSH (non-interactive), short image
names like `vllm/vllm-openai` trigger an interactive registry selection
prompt that fails without a TTY.

**Workaround:** Always use fully-qualified image names:

```bash
# ❌ Fails via SSH
podman run vllm/vllm-openai

# ✅ Works
podman run docker.io/vllm/vllm-openai:latest
```

## SELinux Volume Mount Labeling

**Problem:** Bind mounts without SELinux labels fail with permission
denied errors on Fedora/RHEL.

**Workaround:** Append `:Z` to volume mounts:

```bash
# ❌ Permission denied
-v ~/.cache/huggingface:/models

# ✅ Works
-v ~/.cache/huggingface:/models:Z
```

## `~/.cache/huggingface` May Not Exist

**Problem:** First-time deployments fail with `statfs: no such file or
directory` because the HuggingFace cache directory hasn't been created.

**Workaround:** Always `mkdir -p` before running:

```bash
mkdir -p ~/.cache/huggingface
mkdir -p ~/.cache/huggingface/gguf
```

## llama.cpp Container Image Registry Changed

**Problem:** The original llama.cpp container images were under
`ghcr.io/ggerganov/llama.cpp` with simple tags like `server-cuda`.
These tags no longer exist. The project moved to `ghcr.io/ggml-org/llama.cpp`
with build-number tags.

**Workaround:** Use the new registry with build tags:

```bash
# ❌ Not found
ghcr.io/ggerganov/llama.cpp:server-cuda

# ✅ Works
ghcr.io/ggml-org/llama.cpp:server-cuda-b9994
```

Discover available tags with:

```bash
skopeo list-tags docker://ghcr.io/ggml-org/llama.cpp | \
  python3 -c "import json,sys; [print(t) for t in json.load(sys.stdin)['Tags'] if 'server-cuda-b' in t]" | \
  sort -r | head -5
```

## Source

Derived from deploying vLLM and llama.cpp on Fedora 44 with RPMFusion
NVIDIA driver 610.43.03, Podman 5.8.4, and NVIDIA RTX A500.
