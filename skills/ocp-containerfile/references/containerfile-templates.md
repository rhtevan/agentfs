# Containerfile Templates

Full annotated templates for common languages/frameworks, organized
by mode. Use as reference when `generate.sh` output needs
customization.

## Mode Reference

| Mode | SCC Target | Key Differences |
|------|-----------|-----------------|
| `legacy` | `restricted-v2` (OCP 4.11–4.19) | GID 0 pattern required, random UID override |
| `userns` | `restricted-v3` (OCP 4.20+) | User namespace isolation, idmap mounts, `USER` honored |
| `both` | Both | GID 0 pattern included for compat, works on all versions |

---

## Go Application

### Both Mode

```dockerfile
# ---- Build ----
FROM registry.access.redhat.com/ubi9/go-toolset:latest AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server .

# ---- Runtime ----
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

LABEL name="mycompany/myapp" \
      vendor="My Company" \
      version="1.0.0" \
      release="1" \
      summary="Go REST API Server" \
      description="Go REST API Server for widget management" \
      io.openshift.tags="go,api" \
      io.k8s.display-name="Go API Server"

RUN mkdir -p /licenses
COPY --from=builder --chown=1001:0 /app/server /server
COPY LICENSE /licenses/LICENSE

# GID 0 — backward compat with restricted-v2
# Harmless under restricted-v3 with user namespaces
USER 1001
EXPOSE 8080
ENTRYPOINT ["/server"]
```

Notes:
- `ubi-micro` has no package manager or shell — ideal for static Go binaries
- `CGO_ENABLED=0` produces a static binary that works on `ubi-micro`
- No writable directories needed → no `chgrp`/`chmod` required
- If the app writes to disk, add writable dirs with GID 0 pattern

---

## Python Application

### Both Mode

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf upgrade -y && microdnf clean all

LABEL name="mycompany/pyapp" \
      vendor="My Company" \
      version="1.0.0" \
      release="1" \
      summary="Python Web Application" \
      description="Flask-based web application" \
      io.openshift.tags="python,flask,web"

RUN microdnf install -y python3 python3-pip && \
    microdnf clean all && \
    rm -rf /var/cache/yum

RUN mkdir -p /licenses
COPY LICENSE /licenses/LICENSE

WORKDIR /app
COPY --chown=1001:0 requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt
COPY --chown=1001:0 . /app

# Writable dirs for runtime data
RUN mkdir -p /app/data /app/logs && \
    chgrp -R 0 /app/data /app/logs && \
    chmod -R g=u /app/data /app/logs

USER 1001
EXPOSE 8080
ENTRYPOINT ["python3", "-m", "flask", "run", "--host=0.0.0.0", "--port=8080"]
```

### User Namespace Mode (Simplified)

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf upgrade -y && microdnf clean all

LABEL name="mycompany/pyapp" \
      vendor="My Company" \
      version="1.0.0" \
      release="1" \
      summary="Python Web Application" \
      description="Flask-based web application"

RUN microdnf install -y python3 python3-pip && \
    microdnf clean all

RUN mkdir -p /licenses
COPY LICENSE /licenses/LICENSE

WORKDIR /app
COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt
COPY . /app

# No GID 0 pattern needed — idmap mounts handle ownership
USER 1001
EXPOSE 8080
ENTRYPOINT ["python3", "-m", "flask", "run", "--host=0.0.0.0", "--port=8080"]
```

---

## Node.js Application

### Both Mode

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf upgrade -y && microdnf clean all

LABEL name="mycompany/nodeapp" \
      vendor="My Company" \
      version="1.0.0" \
      release="1" \
      summary="Node.js Application" \
      description="Express-based REST API" \
      io.openshift.tags="nodejs,express,api"

RUN microdnf install -y nodejs npm && \
    microdnf clean all && \
    rm -rf /var/cache/yum

RUN mkdir -p /licenses
COPY LICENSE /licenses/LICENSE

WORKDIR /app

# Dependencies first for cache efficiency
COPY --chown=1001:0 package.json package-lock.json ./
RUN npm ci --production

# Application source
COPY --chown=1001:0 . /app

# GID 0 for writable dirs
RUN mkdir -p /app/uploads /app/tmp && \
    chgrp -R 0 /app/uploads /app/tmp && \
    chmod -R g=u /app/uploads /app/tmp

USER 1001
EXPOSE 8080
CMD ["node", "server.js"]
```

---

## Java (Maven) Application

### Both Mode

```dockerfile
# ---- Build ----
FROM registry.access.redhat.com/ubi9/ubi:latest AS builder
RUN dnf install -y java-21-openjdk-devel maven && dnf clean all
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# ---- Runtime ----
FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:latest

LABEL name="mycompany/javaapp" \
      vendor="My Company" \
      version="1.0.0" \
      release="1" \
      summary="Java Spring Boot Application" \
      description="Spring Boot REST API with PostgreSQL" \
      io.openshift.tags="java,spring,api" \
      io.openshift.wants="postgresql"

RUN mkdir -p /licenses
COPY LICENSE /licenses/LICENSE

COPY --from=builder --chown=1001:0 /app/target/*.jar /app/app.jar
WORKDIR /app

# GID 0 for writable paths
RUN mkdir -p /app/logs && \
    chgrp -R 0 /app/logs && \
    chmod -R g=u /app/logs

USER 1001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

---

## Static Binary / Generic

### Both Mode

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

LABEL name="mycompany/mybin" \
      vendor="My Company" \
      version="1.0.0" \
      release="1" \
      summary="Static binary application" \
      description="Pre-compiled binary application"

RUN mkdir -p /licenses
COPY LICENSE /licenses/LICENSE
COPY --chown=1001:0 myapp /app/myapp

USER 1001
EXPOSE 8080
ENTRYPOINT ["/app/myapp"]
```

---

## Companion Kubernetes Manifest

### For restricted-v3 (User Namespaces)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      hostUsers: false    # mandatory for restricted-v3
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: myapp
        image: myregistry/myapp:1.0.0
        ports:
        - containerPort: 8080
        securityContext:
          runAsUser: 1001
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
```

### For restricted-v2 (Legacy)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      # hostUsers defaults to true (no user namespace)
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: myapp
        image: myregistry/myapp:1.0.0
        ports:
        - containerPort: 8080
        securityContext:
          # runAsUser omitted — SCC injects from namespace range
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```
