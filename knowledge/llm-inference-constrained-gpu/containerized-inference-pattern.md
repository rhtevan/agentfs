---
title: Containerized GPU Inference Server Pattern
created: 2026-08-04
tags: [podman, docker, nvidia, cuda, cdi, container, inference]
---

# Containerized GPU Inference Server Pattern

A reusable pattern for deploying LLM inference servers in containers
with NVIDIA GPU passthrough. The container bundles the full CUDA
runtime — the host only needs the NVIDIA driver.

## Host Requirements

| Component | Required | Notes |
|-----------|:--------:|-------|
| NVIDIA GPU driver | ✅ | Talks to GPU hardware |
| nvidia-container-toolkit | ✅ | Bridges GPU to container runtime |
| CDI spec (`/etc/cdi/nvidia.yaml`) | ✅ | Container Device Interface for Podman |
| CUDA toolkit (`nvcc`, etc.) | ❌ | Bundled inside the container |
| cuDNN / cuBLAS | ❌ | Bundled inside the container |

## CDI Setup (One-Time)

```bash
# Install toolkit
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
  | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null
sudo dnf install -y nvidia-container-toolkit

# Generate CDI spec
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

## Container Run Pattern

```bash
podman run -d \
  --name <container-name> \
  --device nvidia.com/gpu=all \        # CDI GPU passthrough
  --security-opt=label=disable \       # SELinux: allow GPU device access
  --network host \                     # Avoid pasta port forwarding issues
  -v <host-cache>:<container-path>:Z \ # Model cache; :Z for SELinux
  <image> \
  <server-args>
```

## Key Flags Explained

| Flag | Why |
|------|-----|
| `--device nvidia.com/gpu=all` | CDI-based GPU passthrough (Podman) |
| `--security-opt=label=disable` | Required for GPU device node access under SELinux |
| `--network host` | Podman's default `pasta` network breaks port forwarding; `host` mode works reliably |
| `-v ...:Z` | SELinux relabeling for bind mounts on Fedora/RHEL |
| Full image path (`docker.io/...`) | Podman short-name resolution fails without TTY |

## Common Container Images

| Engine | Image | GPU Support |
|--------|-------|:-----------:|
| vLLM | `docker.io/vllm/vllm-openai:latest` | CUDA (bundled) |
| llama.cpp (CPU) | `ghcr.io/ggml-org/llama.cpp:server-b<BUILD>` | None |
| llama.cpp (CUDA) | `ghcr.io/ggml-org/llama.cpp:server-cuda-b<BUILD>` | CUDA (bundled) |
| NVIDIA CUDA base | `nvcr.io/nvidia/cuda:12.6.0-base-ubuntu22.04` | CUDA (bundled) |

## Source

Derived from deploying vLLM and llama.cpp containers with Podman on
Fedora 44 with NVIDIA RTX A500 (RPMFusion drivers).
