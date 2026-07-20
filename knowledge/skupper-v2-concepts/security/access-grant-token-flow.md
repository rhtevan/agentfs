---
type: Reference
title: AccessGrant and AccessToken — Link Creation Workflow
description: How sites securely establish links using the grant → token → redeem workflow
tags: [skupper, access-grant, access-token, linking, security, mtls]
timestamp: 2026-07-20T17:19:00-04:00
---

# AccessGrant and AccessToken

These resources implement the secure workflow for establishing links between sites.

## The Flow

```
Site A (accepting links)                Site B (wants to link)

1. Create AccessGrant
2. Grant produces: url, code, ca  ───→  3. Apply AccessToken (url, code, ca)
   (in status)                          4. Token redeems against grant URL
                                        5. Receives signed certificate
                                        6. Link established (mutual TLS)
```

## AccessGrant Resource

Created on the **site that accepts links**:

```yaml
apiVersion: skupper.io/v2alpha1
kind: AccessGrant
metadata:
  name: my-grant
spec:
  redemptionsAllowed: 3    # How many tokens can redeem this grant
  expirationWindow: 1h     # Time window for redemption
```

| Spec Field | Default | Description |
|------------|---------|-------------|
| `redemptionsAllowed` | `1` | Max number of token redemptions |
| `expirationWindow` | `15m` | Time window for redemption |
| `code` | Auto-generated | Secret authentication code |
| `issuer` | Site's `defaultIssuer` | CA secret for signing certificates |

**Status fields produced after creation:**

| Status Field | Description |
|-------------|-------------|
| `url` | URL of the token-redemption service |
| `ca` | Trusted server certificate |
| `code` | Secret code (auto-generated if not set) |
| `redemptions` | Current redemption count |
| `expirationTime` | When the grant expires |

## AccessToken Resource

Created on the **site that wants to link** (from grant's status values):

```yaml
apiVersion: skupper.io/v2alpha1
kind: AccessToken
metadata:
  name: link-to-site-a
spec:
  url: https://claims.example.com:8081/my-grant   # From grant status
  code: "abc123secret"                              # From grant status
  ca: |                                             # From grant status
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
  linkCost: 1                                       # Optional: cost for resulting link
```

Once applied, the token automatically redeems itself, receives a signed certificate, creates a Link, and marks itself `redeemed: true`.

## CLI Shortcut

```bash
# On Site A (grant side):
skupper token issue ~/token.yaml

# Transfer token.yaml to Site B, then:
skupper token redeem ~/token.yaml
```

## Security Properties

| Property | Detail |
|----------|--------|
| Short-lived | Tokens expire (default 15 minutes) |
| Limited use | Grants limit redemption count (default 1) |
| One-time | Once redeemed, a token cannot be reused |
| mTLS result | Resulting link uses mutual TLS with the signed certificate |
