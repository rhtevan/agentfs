# Agent Orchestration

This skill manages **Skupper VAN infrastructure only**. Model container
lifecycle is handled by `hosted-model-ctl` — the agent semantically
triggers that skill (loads and follows its instructions), NOT by
cross-referencing or invoking its scripts directly.

## Site Roles

| Role | Sites | What "start" includes |
|------|-------|----------------------|
| **Model Provider** | rhel-ai, rhtevan-work | VAN infra (controller + router) **+** model containers (via `hosted-model-ctl`) |
| **Model Consumer** | local-ezhang, crc-ezhang | VAN infra only (controller + router + listeners/links) |

The agent MUST understand this distinction: `hosted-model-ctl` is only
triggered for **Provider** sites that are up and reachable.

## Signal Routing Rules

| Signal pattern | Script invocation |
|----------------|-------------------|
| `setup skupper` | `setup.sh` (infra + model setup delegated) |
| `teardown skupper` | `teardown.sh` (remove infra, models stopped by script) |
| `upgrade skupper` | `upgrade.sh` (align podman versions to CRC baseline) |
| `start skupper` | `up.sh` (VAN + default DPs — all handled by script) |
| `stop skupper` | `down.sh` (models stopped + VAN — all handled by script) |
| `start skupper with PROFILE` | `up.sh <HOST> --profile <PROFILE>` (agent resolves profile → host) |
| `start skupper on SITE` | `up.sh <SITE>` (provider: VAN + model; consumer: VAN only) |
| `stop skupper on SITE` | `down.sh <SITE>` (provider: model + VAN; consumer: VAN only) |
| `check skupper` / `skupper status` | `status.sh` + `hosted-model-ctl list.sh` |

## Scoping Rules

- **Without `on SITE`** → action applies to ALL sites (providers + consumers).
- **Without `with PROFILE`** → `up.sh` uses default profile per host (deterministic).
- **With `on PROVIDER_SITE`** → scope VAN + model to that provider.
- **With `on CONSUMER_SITE`** → scope VAN only, no model delegation.
- **With `with PROFILE`** → agent resolves profile to its host, passes `--profile` to script.

## Name Resolution (Agent Responsibility)

Before calling `up.sh` or `down.sh`, the agent resolves user input
to exact site and profile names:

1. Run `up.sh --list-sites` → get valid site names.
2. If user specified a profile, run `hosted-model-ctl/scripts/list.sh --names-only <site>` → get valid profile names.
3. Match user input against valid names (semantic matching).
4. Call script with exact resolved names.

Scripts do **strict validation** — reject unknown names with the list
of valid alternatives.

## Error Handling

When any phase fails, the agent MUST:
1. Present the error output and analysis.
2. **STOP** — do not proceed to the next phase.
3. **WAIT** for user instructions before continuing.

## Partial Availability

`up.sh` and `down.sh` handle unreachable hosts gracefully — skipping
them with warnings instead of aborting entirely. The agent MUST:

1. Parse output for `✅ Up` vs `⏭️ Skipped` hosts.
2. Classify skipped hosts by role (Provider vs Consumer).
3. **Do NOT manually trigger `hosted-model-ctl`** — scripts handle model start/stop internally.
4. Report skipped providers: `⏭️ <host> skipped (<reason>) — models not started/stopped`.
5. Report skipped consumers: `⏭️ <host> skipped (<reason>) — no model action needed`.
6. **Do NOT ask** "proceed with available hosts?" — partial success is the default.
7. Present a **combined status report** at the end.

## Startup Order

`up.sh` orchestrates internally — agent does NOT pre-call `hosted-model-ctl`:

1. Skupper controllers (systemd) — Consumer + Provider sites.
2. Skupper routers (systemd) — Consumer + Provider sites.
3. Model containers — **Provider sites only** (via `get_default_profile`).

## Shutdown Order (reverse)

`down.sh` orchestrates internally — agent does NOT pre-call `hosted-model-ctl`:

1. Model containers — **Provider sites only** (via `get_active_profile`).
2. Skupper routers (systemd) — Consumer + Provider sites.
3. Skupper controllers (systemd) — Consumer + Provider sites.

**Agent rule: never hardcode a profile name when stopping. `down.sh`
resolves the active profile deterministically from state files.**
