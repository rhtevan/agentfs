---
type: Procedure
title: Installing skupper-router (skrouterd)
description: How to install the skrouterd binary for Linux/systemd sites — Red Hat repos, COPR, and building from source
tags: [skupper, skrouterd, installation, rpm, copr, fedora, rhel, build]
timestamp: 2026-07-22T19:03:00-04:00
---

# Installing skupper-router (skrouterd)

The `skrouterd` binary is **only required for Linux/systemd sites**. Docker, Podman, and Kubernetes platforms use the container image (`quay.io/skupper/skupper-router`) instead.

## What the Package Contains

The `skupper-router` RPM installs:

| File | Purpose |
|------|---------|
| `/usr/sbin/skrouterd` | The router binary |
| `/etc/skupper-router/skrouterd.conf` | Default config file |
| `/etc/sasl2/skrouterd.conf` | SASL auth config |
| Man pages | `skrouterd.8`, `skrouterd.conf.5` |

**The package does NOT install any systemd service.** The service is created by the Skupper CLI or site bundle at site creation time.

## Method 1: Red Hat Repos (RHEL — Requires Subscription)

```bash
# Enable the repository
# Replace <version> with 2 (latest 2.x) or 2.2 (LTS)
# Replace <architecture> with x86_64, aarch64, ppc64le, or s390x

# RHEL 9:
sudo subscription-manager repos \
  --enable=service-interconnect-<version>-for-rhel-9-<architecture>-rpms

# RHEL 8:
sudo subscription-manager repos \
  --enable=service-interconnect-<version>-for-rhel-8-<architecture>-rpms

# Install
sudo dnf install skupper-router
```

| `<version>` | What You Get |
|-------------|-------------|
| `2` | Latest 2.x release (rolling updates) |
| `2.2` | 2.2.x LTS stream (patch updates only) |

## Method 2: COPR (Fedora — Community)

```bash
sudo dnf copr enable gmurthy/skupper-router
sudo dnf install skupper-router
```

Available for: Fedora 43/44/Rawhide, EPEL 9 (x86_64, aarch64, ppc64le, s390x).

**Note:** COPR builds may lag behind or have dependency mismatches with newer Fedora versions. If the COPR package doesn't work, build from source.

## Method 3: Build from Source (Fedora 44 Verified)

This procedure was verified on Fedora 44 with Python 3.14 and libwebsockets 4.5.5.

### Why Build from Source?

The COPR and Fedora packages may have dependency mismatches (e.g., requiring `libwebsockets.so.19` when Fedora 44 ships `.so.21`). The Fedora-packaged `qpid-proton-c` has TLS **disabled**, but skupper-router requires it.

### Prerequisites

```bash
sudo dnf install -y \
  qpid-proton-c-devel \
  python3-qpid-proton \
  cmake make gcc gcc-c++ \
  python3-devel \
  cyrus-sasl-plain cyrus-sasl-devel \
  libnghttp2-devel \
  libwebsockets-devel \
  openssl-devel
```

### Step 1: Rebuild qpid-proton 0.40.0 with TLS

```bash
cd /tmp
git clone --depth 1 -b 0.40.0 https://github.com/apache/qpid-proton.git
cd qpid-proton
mkdir build && cd build
cmake .. \
  -DBUILD_TLS=ON \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DBUILD_TESTING=OFF \
  -DBUILD_TOOLS=OFF \
  -DBUILD_EXAMPLES=OFF
make -j$(nproc)
sudo make install
```

### Step 2: Build skupper-router 3.4.2

Version 3.4.2 is the latest release compatible with Proton 0.40.0. Version 3.5.x requires Proton ≥ 0.41.0 (not yet publicly released).

```bash
cd /tmp
git clone https://github.com/skupperproject/skupper-router.git
cd skupper-router
git fetch --tags
git checkout 3.4.2
mkdir build && cd build
cmake .. \
  -DCMAKE_PREFIX_PATH=/usr/local \
  -DVERSION=3.4.2
make -j$(nproc)
sudo make install
```

### Step 3: Verify

```bash
skrouterd --version
# 3.4.2

which skrouterd
# /usr/local/sbin/skrouterd
```

### Compatibility Matrix

| Component | Version |
|-----------|---------|
| Fedora | 44 |
| skrouterd | 3.4.2 (from source) |
| qpid-proton | 0.40.0 (rebuilt with TLS) |
| Skupper CLI | 2.2.1 ✅ compatible |
| libwebsockets | 4.5.5 (Fedora package) |
| Python | 3.14 (Fedora package) |

### Cleanup

```bash
rm -rf /tmp/qpid-proton /tmp/skupper-router
```
