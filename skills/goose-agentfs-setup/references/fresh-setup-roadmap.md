# Fresh Goose AgentFS Setup — Roadmap

Optimized sequence for setting up AgentFS on a fresh Goose install and a
new project. Derived from the first fresh setup (2026-11-19, Goose 1.60.1),
which took ~35 turns because bugs and missing steps surfaced one at a time.
Following this order: ~5 user turns.

**Principle:** survey everything first, decide once, apply in dependency
order, verify end-to-end (the SOUL appears in `<turn-context>`).

## Interaction Contract

| Rule | Why |
|------|-----|
| Phase 0 is read-only and ends with **one** consolidated gap list + **one** plan | Reporting issues one at a time costs a turn each |
| The user approves the whole plan with one `go`. The preflight hook holds the first change of each turn; `go`, `A`, `fix + go` release it | Goose appends "Do not retry" to every hook denial, so the agent stops at each hold |
| Run `post-write.sh` after **each** `.agents/` write, standalone — not chained (`&&`), not in the same batch as the edit | post-write-enforce clears only after a *successful* `post-write.sh` shell call |
| Checkpoint before delete, rename, or edits to ≥3 `.agents/` files | Rule 5 |
| Push needs its own confirmation after the scan report | Git push safety |
| Start the Goose session **in the project directory** | `system-md-gen.sh` reads `./AGENTS.md` and `./.agents/SOUL.md` from CWD |

## Skill Sequence

| # | Skill | Signal | Phase | Depends on | Produces |
|---|-------|--------|-------|------------|----------|
| 0 | a `goose-*-provider` skill | e.g. `configure goose gcp` | before all | — | A working model |
| 1 | `agentfs-setup` | `hey setup agentfs` | 1 | Goose works | `.agents/`, SOUL.md, AGENTS.md (template), verify pass |
| 2 | `goose-agentfs-setup` | `hey configure goose agentfs` | 0, 2, 3 | 1 | `CONTEXT_FILE_NAMES`, `.goosehints`, memory routing, plugin check |
| 3 | `goose-agentfs-setup` | `hey sync goose agentfs` | 4 | 1, 2 | Custom `system.md`, tom on, `GOOSE_MOIM_MESSAGE_FILE`, SOUL in `instructions.md` |
| 4 | `goose-kgm` (optional) | `hey setup goose kgm` | 5 | 1 | KGM extension + index; enable per session |
| — | restart Goose | — | 6 | 3 | Verification |
| 5 | `agentfs-git-push` | `hey git` | 7 | all | Scan → report → `go` → push (auto-loads `agentfs-readme-audit`) |

On demand: `goose-doc-guide` (read Goose docs before changing anything
goose-specific), `agentfs-eval` (`hey agentfs health`), `okf-bundle-harvest`
/ `skill-harvest` (`hey harvest`) after the work.

**Bootstrap note:** before step 4 there is no `search_nodes`, so `hey`
signals resolve through Rule 1's index-browse fallback, and the
signal-dispatch plugin stays inactive (fail-open). Nothing blocks.

## Phase 0 — Survey (read-only, one turn)

```bash
goose --version     # compare with artifacts/system.md.base.meta
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --check
bash ~/.agents/skills/goose-agentfs-setup/scripts/setup.sh --plugin-check
bash ~/.agents/skills/goose-agentfs-setup/scripts/system-md-gen.sh --check
bash ~/.agents/skills/goose-kgm/scripts/status-kgm.sh
grep -n '^GOOSE_MOIM_MESSAGE_FILE:' ~/.config/goose/config.yaml   # anchored
```

Output: gap table + phase plan → user `go`.

## Phases 1–5 — Apply (one `go`)

| # | Phase | Commands | Gate | Gotcha |
|---|-------|----------|------|--------|
| 1 | Project scaffold | `NON_INTERACTIVE=true scaffold-dotagents.sh --scope project` → `seed-agents-md.sh` | `verify-setup.sh` all pass | AGENTS.md is generated from `seed-agents-md.sh`; never hand-edit |
| 2 | Context files | `setup.sh` → `setup.sh --remove AGENTS.md` | `setup.sh --check` | AGENTS.md is delivered via `system.md`; leaving it in `CONTEXT_FILE_NAMES` double-loads it |
| 3 | Hints + memory routing | `setup.sh --hints-install` → `setup.sh --memory-install` | `--hints-check`, `--memory-check` | Writes `instructions.md`, shared with the SOUL section |
| 4 | system.md + SOUL (from the project dir) | `system-md-gen.sh` | `--check`: "GOOSE_MOIM_MESSAGE_FILE: registered ✅" | tom has **no default file**; without the key nothing is injected while every other check is green |
| 5 | KGM (optional) | `setup-kgm.sh --dry-run` → apply if PENDING → `reindex-kgm.sh` | `status-kgm.sh` all ✅ | Default `enabled: false`: enable per session, and signal-dispatch stays inactive — expected. If KGM is enabled globally (`enabled: true`, e.g. via the desktop toggle), signal-dispatch enforces in every session and each session starts its own KGM server (~165 MB) |

Config backups written automatically: `config.yaml.bak.pre-kgm`,
`.bak.pre-tom`, `.bak.pre-moim`.

## Phase 6 — Restart and Verify (one turn)

`system.md` is read at session start: restart Goose Desktop or start a new
CLI session in the project directory.

| Check | Pass |
|-------|------|
| **SOUL delivered** | `<turn-context>` shows the Memory Routing Override and the SOUL — the only true end-to-end test |
| Rules at primacy | The agent writes the Rule 3 session canary on turn 1 |
| Dispatch | `hey setup goose kgm` → first tool `search_nodes` → `load_skill` (KGM enabled in session) |
| Plugins fail-open | One hold on the first change, `go` passes; no lockouts |

## Phase 7 — Commit (two turns)

`hey git` → report → `go` pushes `~/.agents`. Then the project's first
local commit; add `.obsidian/` and other editor directories to `.gitignore`
first.

## Deferred

`bash ~/.agents/scripts/update-compliance.sh --check` — re-measuring against
a new template is its own task, not part of setup.

## Ideal Turn Budget

| Turn | User | Agent |
|------|------|-------|
| 1 | `hey configure goose agentfs` | Phase 0 survey → gap table + plan |
| 2 | `go` | Phases 1–5 |
| 3 | (after restart) anything | Phase 6 verification |
| 4 | `hey git` | Scan + report |
| 5 | `go` | Commit + push |

## Related Knowledge

- [MOIM / Persistent Instructions Reality](../../../knowledge/context-engineering/moim-persistent-instructions-reality.md) — where tom reads the file path, silent-failure gotchas
- [Fail-Open Hook Design](../../../knowledge/context-engineering/fail-open-hook-design.md) — why the plugins behave as they do
