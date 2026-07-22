# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## 2026-07-22 19:06

* **Creation**: Added `migration/v1-to-v2-changes.md` — V1 deprecated concepts, changed commands, and new V2 features.
* **Creation**: Added `platform-details/linux-systemd-architecture.md` — native skrouterd, bootstrap container, systemd templates.
* **Creation**: Added `platform-details/site-bundles.md` — generate-bundle, install.sh, remote deployment without CLI.
* **Creation**: Added `platform-details/multiple-sites-per-host.md` — namespace-scoped services, port conflicts.
* **Creation**: Added `platform-details/skupper-router-installation.md` — Red Hat repos, COPR, build from source on Fedora 44.
* **Creation**: Added `operations/firewall-rules.md` — ports, proxy tunneling, relay pattern.
* **Update**: Updated `index.md` at session root, operations, and new sub-bundle indexes.

## 2026-07-22 15:41

* **Update**: Updated `security/application-tls.md` — added TLS Passthrough section (end-to-end encryption, observer settings, double encryption, model comparison).
* **Update**: Updated `security/router-access.md` — added Inter-Site Link Ports section (55671/45671, port roles, protocol) and Inter-Router mTLS Always On section (cannot disable, customizable certs).
* **Update**: Updated `security/index.md` descriptions to reflect new content.

## 2026-07-20 17:24

* **Creation**: Generated 11 concept documents from session context across 4 sub-bundles.
* **Sub-bundles**: core-concepts/ (6 docs), security/ (3 docs), advanced-features/ (2 docs), operations/ (2 docs)
* **Core concepts**: overview-and-model, listener-connector-model, multi-key-listener, load-balancing-and-failover, site-configuration, attached-connectors
* **Security**: access-grant-token-flow, router-access, application-tls
* **Advanced features**: individual-pod-services, large-networks
* **Operations**: network-console, components
* **Update**: Generated index.md for all directories.

## 2026-07-20 17:19

- Created OKF knowledge bundle structure.
