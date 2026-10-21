# Troubleshooting

## Common Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| CRC link `Pending - Not operational` | Stale CA cert in CRC link secret | Compare CA fingerprints: `oc get secret <link> -o jsonpath='{.data.ca\.crt}' \| base64 -d \| openssl x509 -noout -fingerprint -sha256`. If mismatch → delete secret, recreate with current certs, restart router pod |
| `SSL Failure: certificate verify failed` in CRC router logs | Server cert missing SANs for `host.crc.testing` / `192.168.127.254` | Regenerate local server cert with proper SANs using `openssl`. Check with `openssl x509 -in tls.crt -noout -ext subjectAltName` |
| `Connection refused` to `host.crc.testing:55672` | No inter-router listener on localhost | Check `ss -tlnp \| grep 55672`. If missing, inject listener into `skrouterd.json` and restart router |
| Link `Pending` but TCP port reachable | Cert mismatch (CA rotation) | Update link secret with current certs from hub's `client-*` cert dir |
| Controller errors: `invalid role: normal` | `normal` role in RouterAccess input | Remove `normal` role — only `inter-router` and `edge` are valid in input |
| Controller errors: `unable to load router configuration` | `skrouterd.json` deleted | Never delete runtime files. Use `systemctl --user restart` not `skupper system stop/start` |
| `multiple namespaces found` on `system start/reload` | Secret YAML missing `namespace:` field | Add `namespace: model-provider-podman` to all Secret metadata |
| Observer shows random suffixed site names | Router ID used as display name (podman platform) | Expected on v2.2.1. May improve on v2.2.3 |
| Listeners show `No matching connectors` | Remote connector's host is down or link not connected | Check link status first. If link is Ready, check remote connector + model container |
| `status.sh` reports operator "not found" | Hardcoded CSV version in status check | Fixed in v8.17.2 — prefix-based match |

## Debugging Procedures

### Check cert chain for a link
```bash
# Local link cert CA
cat ~/.local/share/skupper/namespaces/model-provider-podman/runtime/certs/<link-profile>/ca.crt | openssl x509 -noout -fingerprint -sha256

# Remote hub server cert
echo | openssl s_client -connect <host>:<port> 2>/dev/null | openssl x509 -noout -subject -ext subjectAltName
```

### Check router config
```bash
cat ~/.local/share/skupper/namespaces/model-provider-podman/runtime/router/skrouterd.json | python3 -m json.tool
```

### Check CRC router logs
```bash
oc --context <CRC_CONTEXT> logs -n model-provider-crc -l skupper.io/component=router -c router --tail=50
```

## Postmortem

See [POSTMORTEM.md](../POSTMORTEM.md) for detailed incident history.
