---
name: crc-status
description: Check OpenShift Local (CRC) cluster status and remove the default caution banner from the web console if present
---

# OpenShift Local Status & Banner Cleanup

Check the status of the OpenShift Local (CRC) cluster and remove the default caution banner from the OpenShift web console if it exists.

## Steps

1. **Check CRC status**
   Run `crc status` to verify the cluster is running and review resource usage (RAM, disk, etc.).

2. **Get console credentials**
   Run `crc console --credentials` to retrieve the kubeadmin login command.

3. **Log in as admin**
   Log in to the cluster as `kubeadmin` using the credentials from the previous step:
   ```
   oc login -u kubeadmin -p <password> https://api.crc.testing:6443
   ```

4. **Check for the caution banner**
   Look for the default `ConsoleNotification` resource named `security-notice`.
   Redirect stderr to suppress any "not found" error noise:
   ```
   oc get consolenotification security-notice 2>/dev/null
   ```
   - If this produces output (a resource row), the banner **exists**.
   - If this produces **no output**, the banner does **not** exist.

5. **Remove the banner (only if it exists)**
   If step 4 produced output (the banner exists), delete it:
   ```
   oc delete consolenotification security-notice
   ```
   If step 4 produced no output (the banner does not exist), skip this step and inform the user the banner has already been removed.

## Verification

- [ ] `crc status` shows the CRC VM and OpenShift as Running
- [ ] `oc get consolenotifications` returns no `security-notice` resource

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 18:12 | v1.0 — Initial skill |
