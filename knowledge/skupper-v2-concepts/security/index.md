# Security

Skupper V2 security mechanisms — link authentication, router access, and application TLS.

* [AccessGrant and AccessToken — Link Creation Workflow](access-grant-token-flow.md) - How sites securely establish links using the grant → token → redeem workflow
* [RouterAccess — Router Network Exposure](router-access.md) - How RouterAccess controls the external accessibility of the Skupper router, including ports, mTLS enforcement, and access types
* [Application TLS — Hop-by-Hop and Passthrough](application-tls.md) - How to configure TLS for client-to-router and router-to-server segments, plus end-to-end TLS passthrough in Skupper V2
