# Plugin Registration Survives Directory Removal (Gotcha)

**Observed:** goose 1.60.x, 2026-11-20 (found 2026-11-24).

## Gotcha

When goose runs in a project that has `<project>/.agents/plugins/<name>/`,
it records the plugin in the **global** `~/.config/goose/config.yaml`:

```yaml
plugins:
  /tmp/hooktest/.agents/plugins/always-block:
    enabled: true
```

Deleting the plugin directory does not remove this entry. The official
docs describe discovery (`~/.agents/plugins/`, `<project>/.agents/plugins/`)
and disabling (`disabledPlugins` in `settings.json`), not this persisted map.

## Evidence

- A throwaway test plugin `always-block` (blocks every shell command
  containing `BLOCKME`) was created in `/tmp/hooktest`, exercised with one
  headless `goose run` from that directory at ~11:07, then `rm -rf /tmp/hooktest`.
  No tool call edited `config.yaml`.
- `config.yaml.bak.pre-kgm-wrapper` (11-19 23:13): 0 `hooktest` lines.
  `config.yaml.bak.pre-corp` (11-20 11:07:01) and every later copy: 1.
- The stale entry stayed `enabled: true` for 4 days. Harmless while the path
  is missing; if the path is recreated, the plugin loads again in every session.

## Teardown for hook / plugin tests

A test's teardown removes **every** side effect, not only its files:

1. Remove the test directory (`rm -rf /tmp/<test>`).
2. Remove the plugin's entry from `~/.config/goose/config.yaml` `plugins:`
   (back up the file first). Check: `grep -n '<test path>' ~/.config/goose/config.yaml`
   prints nothing.
3. Untested option: run the test `goose run` with a throwaway `HOME` so the
   registration lands in a disposable config. Verify before relying on it.
