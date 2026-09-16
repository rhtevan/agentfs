#!/usr/bin/env bash
# generate.sh — Generate an OpenShift-compatible Containerfile from CWD content
# Usage: bash generate.sh [--mode legacy|userns|both] [--output <path>]
# Exit codes: 0 = generated, 1 = unsupported language, 2 = usage error
set -euo pipefail

MODE="both"
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash generate.sh [--mode legacy|userns|both] [--output <path>]"
      echo "Modes: legacy (restricted-v2), userns (restricted-v3), both (default)"
      echo "Detects language from CWD and generates an appropriate Containerfile."
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1"
      exit 2
      ;;
  esac
done

if [[ ! "$MODE" =~ ^(legacy|userns|both)$ ]]; then
  echo "❌ Invalid mode: $MODE (must be legacy, userns, or both)"
  exit 2
fi

# --- Language Detection ---
LANG=""
if [[ -f "go.mod" ]]; then
  LANG="go"
elif [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]] || [[ -f "Pipfile" ]]; then
  LANG="python"
elif [[ -f "package.json" ]]; then
  LANG="nodejs"
elif [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
  LANG="java"
elif [[ -f "Gemfile" ]]; then
  LANG="ruby"
elif [[ -f "Cargo.toml" ]]; then
  LANG="rust"
else
  echo "❌ Could not detect language/framework from CWD: $(pwd)"
  echo "   Supported: Go (go.mod), Python (requirements.txt/pyproject.toml),"
  echo "   Node.js (package.json), Java (pom.xml/build.gradle), Rust (Cargo.toml)"
  exit 1
fi

echo "# Detected language: $LANG" >&2
echo "# Mode: $MODE" >&2

# --- GID 0 Block ---
gid0_block() {
  local dirs="$1"
  if [[ "$MODE" == "userns" ]]; then
    echo "# GID 0 pattern not required under user namespaces (restricted-v3)"
  elif [[ "$MODE" == "both" ]]; then
    cat <<GID
# GID 0 pattern — required for restricted-v2 compat, harmless on v3
RUN chgrp -R 0 ${dirs} && \\
    chmod -R g=u ${dirs}
GID
  else
    cat <<GID
# GID 0 pattern — required for restricted-v2
RUN chgrp -R 0 ${dirs} && \\
    chmod -R g=u ${dirs}
GID
  fi
}

# --- USER block ---
user_block() {
  if [[ "$MODE" == "userns" ]]; then
    echo "# Under user namespaces, USER 0 is safe (unprivileged on host)"
    echo "# Using non-root for defense-in-depth"
    echo "USER 1001"
  else
    echo "# Non-root user — required for certification and restricted-v2/v3"
    echo "USER 1001"
  fi
}

# --- Labels block ---
labels_block() {
  cat <<LABELS
# Required labels for Red Hat certification
LABEL name="CHANGEME/app-name" \\
      vendor="CHANGEME Company" \\
      version="1.0.0" \\
      release="1" \\
      summary="CHANGEME short description" \\
      description="CHANGEME long description" \\
      io.openshift.tags="CHANGEME" \\
      io.k8s.display-name="CHANGEME" \\
      io.k8s.description="CHANGEME"
LABELS
}

# --- License block ---
license_block() {
  cat <<LIC
# License directory — required for certification
RUN mkdir -p /licenses
COPY LICENSE /licenses/LICENSE
LIC
}

# --- Generate by language ---
generate() {
  case "$LANG" in

  go)
    cat <<'EOF'
# ---- Build Stage ----
FROM registry.access.redhat.com/ubi9/go-toolset:latest AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server .

# ---- Runtime Stage ----
FROM registry.access.redhat.com/ubi9/ubi-micro:latest
EOF
    labels_block
    license_block
    echo ""
    echo "COPY --from=builder --chown=1001:0 /app/server /server"
    echo ""
    user_block
    echo "EXPOSE 8080"
    echo 'ENTRYPOINT ["/server"]'
    ;;

  python)
    cat <<'EOF'
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Security patches
RUN microdnf upgrade -y && microdnf clean all
EOF
    echo ""
    labels_block
    echo ""
    cat <<'EOF'
RUN microdnf install -y python3 python3-pip && \
    microdnf clean all && \
    rm -rf /var/cache/yum
EOF
    echo ""
    license_block
    echo ""
    cat <<'EOF'
COPY --chown=1001:0 requirements.txt /app/requirements.txt
WORKDIR /app
RUN pip3 install --no-cache-dir -r requirements.txt
COPY --chown=1001:0 . /app
EOF
    echo ""
    gid0_block "/app/data /app/logs"
    echo ""
    user_block
    echo "EXPOSE 8080"
    echo 'ENTRYPOINT ["python3", "-m", "app"]'
    ;;

  nodejs)
    cat <<'EOF'
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Security patches
RUN microdnf upgrade -y && microdnf clean all
EOF
    echo ""
    labels_block
    echo ""
    cat <<'EOF'
RUN microdnf install -y nodejs npm && \
    microdnf clean all && \
    rm -rf /var/cache/yum
EOF
    echo ""
    license_block
    echo ""
    cat <<'EOF'
WORKDIR /app
COPY --chown=1001:0 package.json package-lock.json ./
RUN npm ci --production
COPY --chown=1001:0 . /app
EOF
    echo ""
    gid0_block "/app"
    echo ""
    user_block
    echo "EXPOSE 8080"
    echo 'CMD ["node", "server.js"]'
    ;;

  java)
    cat <<'EOF'
# ---- Build Stage ----
FROM registry.access.redhat.com/ubi9/ubi:latest AS builder
RUN dnf install -y java-21-openjdk-devel maven && dnf clean all
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# ---- Runtime Stage ----
FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:latest
EOF
    echo ""
    labels_block
    echo ""
    license_block
    echo ""
    echo "COPY --from=builder --chown=1001:0 /app/target/*.jar /app/app.jar"
    echo "WORKDIR /app"
    echo ""
    gid0_block "/app"
    echo ""
    user_block
    echo "EXPOSE 8080"
    echo 'ENTRYPOINT ["java", "-jar", "/app/app.jar"]'
    ;;

  rust)
    cat <<'EOF'
# ---- Build Stage ----
FROM registry.access.redhat.com/ubi9/ubi:latest AS builder
RUN dnf install -y gcc make && dnf clean all
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

# ---- Runtime Stage ----
FROM registry.access.redhat.com/ubi9/ubi-micro:latest
EOF
    echo ""
    labels_block
    echo ""
    license_block
    echo ""
    echo "COPY --from=builder --chown=1001:0 /app/target/release/app /server"
    echo ""
    user_block
    echo "EXPOSE 8080"
    echo 'ENTRYPOINT ["/server"]'
    ;;

  *)
    echo "❌ Unsupported language: $LANG" >&2
    exit 1
    ;;
  esac
}

# --- Output ---
if [[ -n "$OUTPUT" ]]; then
  generate > "$OUTPUT"
  echo "✅ Generated $OUTPUT (language: $LANG, mode: $MODE)" >&2
else
  generate
fi
