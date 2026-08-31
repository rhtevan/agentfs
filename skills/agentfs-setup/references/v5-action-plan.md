# AgentFS v5 Action Plan

> Version: 2 — 2026-08-31
> Strategy: [agentfs-v5-strategy.md](./agentfs-v5-strategy.md) (v3)
> Status: **Executed** — all 11 actions complete + 10 follow-up fixes (v5.1.0)
> Note: Token target was ≤900 but actual v5 AGENTS.md is ~1,227 tokens.
> Difference due to Markdown table formatting overhead not counted in
> content-only estimate. The 69% reduction from v4 (4,029→1,227) met
> the percentage target. Accepted as known deviation.

## Dependency Graph

```
Phase 1 (prerequisites — no AGENTS.md changes yet)
  A1 → A2 → A3 (serial — each validates the previous)
  A4 (parallel with A1–A3, independent)

Phase 2 (template update — requires Phase 1 complete)
  A5 → A6 (serial — write, test)

Phase 3 (KGM integration — independent of Phase 2)
  A8 → A9 (serial)

Phase 4 (integration test + documentation — after Phase 2 AND Phase 3)
  A7 → A10 → A11 (serial — sync this project, README, archive)
```

---

## Phase 1: Prerequisites

### A1. Create `agentfs-git-push` skill

**Strategy:** S5 (Externalize Complex Workflows)
**Scope:** USER (`~/.agents/skills/agentfs-git-push/`)
**Blocks:** A5 (template needs `load_skill` reference)

**Deliverables:**
- `SKILL.md` — full Git Push Safety workflow absorbed from current
  AGENTS.md Guardrail #10 (387 tokens of inline content)
- `CHANGELOG.md` — initial entry
- No new scripts — skill references existing scripts in
  `agentfs-setup/scripts/` (`pre-push-scan.sh`, `merge-log-entry.sh`)

**SKILL.md content (from current Guardrail #10 + #5 overlap):**
1. `git add -A`
2. Run `pre-push-scan.sh` — deterministic scan of staged diff
3. Read `.pre-push-allowlist`, semantically filter findings
4. If output contains `README_AUDIT_REQUIRED` →
   `load_skill(name: "agentfs-readme-audit")`
5. If memory files are flagged → semantic PII review
6. Present complete report as rendered Markdown (single turn)
7. **WAIT** — do NOT commit until user replies to this turn
8. `git commit` with descriptive message
9. `git push`

**Violation definitions** (move from AGENTS.md inline):
- Committing without running `pre-push-scan.sh`
- Committing without user confirmation in same turn as report
- Skipping README audit when `README_AUDIT_REQUIRED` emitted
- Skipping PII review when memory files flagged
- Merging report and commit into single agent action

**Acceptance criteria:**
- [ ] `load_skill(name: "agentfs-git-push")` loads correctly
- [ ] Skill covers all 8 steps from current Guardrail #10
- [ ] Skill covers allowlist filtering from current Guardrail #10
- [ ] All violation definitions present
- [ ] No new scripts needed (references agentfs-setup scripts)
- [ ] Signal phrases: `git push safety, pre-push scan, hey git workflow`

### A2. Verify `agentfs-setup` covers delegated details

**Strategy:** S1, S5 (Filesystem Integrity delegation)
**Scope:** USER (`~/.agents/skills/agentfs-setup/`)
**Blocks:** A5 (template delegates to agentfs-setup)

**Check that existing SKILL.md and scripts cover:**
- [ ] `merge-log-entry.sh` delegation table (which script for which gate)
- [ ] `merge-changelog-entry.sh` usage for version bumps
- [ ] `post-edit.sh` as the index rebuild mechanism
- [ ] `checkpoint.sh` usage for destructive ops
- [ ] Scope rules: log to every scope touched (USER/PROJECT/knowledge)

**If gaps found:** Add missing details to `agentfs-setup/SKILL.md`
references section. Do NOT add to AGENTS.md — the whole point is
delegation.

### A3. Validate content coverage

**Strategy:** S3 (Content Coverage Audit)
**Blocks:** A5 (final gate before template rewrite)

**Process:**
1. Extract all discrete rules/instructions from current AGENTS.md
   (v4.x seed template)
2. Map each to its v5 destination:
   - Inline in v5 flat table → mark RETAINED
   - In `agentfs-git-push` SKILL.md → mark DELEGATED
   - In `agentfs-setup` SKILL.md/scripts → mark DELEGATED
   - Intentionally removed → mark REMOVED with rationale
3. Confirm zero true content loss
4. Save mapping as `agentfs-setup/references/v5-migration-map.md`

### A4. Create `goose-kgm` skill

**Strategy:** S6 (KG Memory as Optional Knowledge Index)
**Scope:** USER (`~/.agents/skills/goose-kgm/`)
**Independent of** A1–A3, can be done in parallel

**Deliverables:**
- `SKILL.md` — lifecycle management for KG Memory MCP extension
- `CHANGELOG.md` — initial entry
- `scripts/setup-kgm.sh` — configure Goose KG Memory extension
  (add to `config.yaml`, set `MEMORY_FILE_PATH`, disabled by default)
- `scripts/teardown-kgm.sh` — remove configuration
- `scripts/enable-kgm.sh` / `scripts/disable-kgm.sh` — toggle
  extension enabled/disabled in Goose config
- `scripts/status-kgm.sh` — check if configured, enabled, and
  the JSONL file exists/has content

**Signal phrases:** `setup goose kgm, teardown goose kgm, enable kgm,
disable kgm, kgm status`

**Design decisions:**
- `MEMORY_FILE_PATH` default: `~/.agents/knowledge/.kgm-index.jsonl`
  (colocated with knowledge bundles, dot-prefixed to signal derived
  artifact, gitignored)
- Extension disabled by default — user must explicitly enable
- KGM indexes knowledge concepts only (not guardrails, not memories)

**Acceptance criteria:**
- [ ] `load_skill(name: "goose-kgm")` loads correctly
- [ ] Setup creates config entry with extension disabled
- [ ] Enable/disable toggles work idempotently
- [ ] Status reports: configured/not, enabled/not, JSONL exists/not,
      entity count
- [ ] Teardown removes config cleanly

---

## Phase 2: Template Update

### A5. Rewrite `seed-agents-md.sh` template (PROJECT scope)

**Strategy:** S1, S2, S3, S4, S5
**Scope:** USER (`~/.agents/skills/agentfs-setup/scripts/seed-agents-md.sh`)
**Requires:** A1 complete, A2 complete, A3 complete
**Blocks:** A6, A7

**Changes to the heredoc template in `seed-agents-md.sh`:**

1. **Quick Orientation table** — keep as-is (compact, high value)

2. **Signal Routing table** — reduce to 6 rows (non-skill only):
   | Signal | Route |
   |--------|-------|
   | "remember this" / "note that" | `.agents/memories/MEMORY.md` |
   | "always do X" / "never do Y" | Propose `AGENTS.md` guardrail |
   | "I prefer" / "my style is" | `.agents/memories/USER.md` |
   | "forget this" / "remove that note" | Edit `MEMORY.md`, remove |
   | "what do you remember" | Read `MEMORY.md` |
   | "hey git" | Stage, commit, `load_skill("agentfs-git-push")` |

3. **Guardrail Quick Reference table** — DELETE entirely (double
   encoding eliminated)

4. **Scope Definitions** — keep as-is (compact, high value)

5. **Full guardrail section** — REPLACE with flat table:

   | # | Trigger | Action |
   |---|---------|--------|
   | 1 | User message received | Scan skill descriptions for signal match → `load_skill` → follow. Check Signal Routing table for LLM-direct routes. Only if no match: proceed with generic interpretation. |
   | 2 | Accessing `.agents/` content | Browse `index.md` first, follow links to content. |
   | 3 | Session start | Check for `CLAUDE.md`, `.cursorrules`, `.cursor/rules/`, `.windsurfrules`, `.github/copilot-instructions.md`. Treat as supplementary. AGENTS.md wins on conflict. |
   | 4 | Creating a skill | Default to USER `~/.agents/skills/`. PROJECT only when user explicitly says "project skill" / "for this project" / "local skill". |
   | 5 | Any write/edit under `.agents/` or `~/.agents/` | ✅ `merge-log-entry.sh` for each touched scope ✅ `merge-changelog-entry.sh` + version bump for modified skills ✅ `post-edit.sh` runs clean ✅ All markdown links resolve |
   | 6 | `git add` or "hey git" | `load_skill(name: "agentfs-git-push")` — follow completely. |
   | 7 | Before destructive op (delete, bulk rename, multi-file edit under `.agents/`) | `checkpoint.sh create <files>` → execute → `checkpoint.sh clear`. |
   | 8 | Action involves policy, domain concepts, or unfamiliar procedures | Consult knowledge index (`~/.agents/knowledge/index.md`) for relevant context before acting. |
   | 9 | `memories/` write | PROJECT scope only. Experiences → `MEMORY.md`. Rules → `AGENTS.md`. Preferences → `USER.md`. Mature patterns → graduate to OKF bundle. |
   | 10 | Always | No validation phrases ("Great question", "Absolutely"). Lead with substance. Name risks proactively. |
   | 11 | Always | Don't reverse position without new information or logical argument. When reversing, state what changed and previous position. When request conflicts with guardrail, quote it, explain, ask for confirmation. Log overrides with `[OVERRIDE]`. |
   | 12 | Always | Session canary name (random, ephemeral). Emit turn 1. ~1-in-5 turns: emit + self-check. Never persist to files. |

6. **Agent Profiles** — keep as-is (project-owned section)

7. **SPECKIT block** — keep as-is (project-owned section)

8. **Template version** — bump to `5.0.0`

**Also update the LITE scope template** in the same heredoc — align
rule numbers but keep the 6-rule subset. Review which of the 12 v5
rules apply to LITE.

**Acceptance criteria:**
- [ ] Template generates valid AGENTS.md
- [ ] Token count ≤ 900 (target 874)
- [ ] All 12 rules present in flat table
- [ ] No Quick Reference table (double encoding eliminated)
- [ ] Signal Routing has exactly 6 rows
- [ ] Rule 6 references `agentfs-git-push` skill
- [ ] Rule 8 (context enrichment) present
- [ ] Rules 10 + 11 are the split Anti-Sycophancy
- [ ] PROJECT-OWNED marker preserved for sync compatibility
- [ ] `agentfs-template-version: 5.0.0` in generated output

### A6. Test template fidelity

**Scope:** Test script execution
**Requires:** A5 complete

**Process:**
1. Run `test-agents-md-fidelity.sh` against generated output
2. Run `sync-agents-md.sh` against a test project with v4.x AGENTS.md
   to verify upgrade path:
   - Project-owned sections preserved (Agent Profiles, SPECKIT)
   - Template-owned sections regenerated from v5 template
   - Version stamp updated to 5.0.0
3. Manually verify token count of generated AGENTS.md
4. Verify LITE scope template generates correctly

**Acceptance criteria:**
- [ ] `test-agents-md-fidelity.sh` passes
- [ ] Sync preserves project-owned sections
- [ ] Sync updates template version from 4.x to 5.0.0
- [ ] Generated PROJECT AGENTS.md ≤ 900 tokens
- [ ] Generated LITE AGENTS.md ≤ 850 tokens (existing target)

### A7. Sync current project (integration test)

**Scope:** This project (`context-eng`) ONLY
**Requires:** A6 passes, A8–A9 complete (Phase 3)

This is intentionally the last functional action — it serves as a
live integration test of the full v5 stack:
- v5.0.0 AGENTS.md template (from A5)
- KGM extension configured and enabled in current session (from A4)
- KGM knowledge index populated (from A9)
- Real project with real `.agents/` structure

Other projects sync opportunistically when they are next worked on,
not as part of this rollout. This limits the blast radius of v5
changes to a single controlled project.

**Process:**
1. Enable KGM extension in current Goose session
2. Run `sync-agents-md.sh` on this project
3. Verify synced AGENTS.md: token count, rule count, version stamp
4. Verify KGM index has entities for all 9 knowledge bundles
5. Test knowledge discovery: query a concept via `search_nodes`,
   confirm Source observation points to correct file
6. Test guardrail compliance: trigger Rule 6 (git push) to verify
   skill delegation works
7. Commit and push this project

---

## Phase 3: Optional KGM Integration

### A8. Design KGM entity schema for OKF bundles

**Strategy:** S6
**Requires:** A4 complete
**Independent of** Phase 2

**Deliverables:**
- Entity naming convention: `bundle:<bundle-name>` for bundles,
  `concept:<bundle>/<concept>` for individual concept docs
- Relation types: `contains` (bundle → concept), `related_to`
  (cross-bundle concept links)
- Observation types: `Source: <path>` (file location),
  `Summary: <text>` (concept description),
  `Tags: <csv>` (discovery tags from bundle index)
- Document schema as `goose-kgm/references/kgm-entity-schema.md`

**Acceptance criteria:**
- [ ] Schema covers all 9 existing knowledge bundles
- [ ] Schema handles sub-bundles (e.g., skupper-v2-concepts has
      multiple concept docs)
- [ ] `search_nodes("skupper")` would return bundle + concept entities
      with Source observations pointing to actual files
- [ ] Schema documented in goose-kgm references

### A9. Add conditional KGM reindex to `agentfs-setup` sync

**Strategy:** S6 (KGM index sync)
**Scope:** USER (`~/.agents/skills/agentfs-setup/`)
**Requires:** A4, A8 complete

**Changes:**
- Add to `post-edit.sh` (or a new `sync-kgm-index.sh` called by
  post-edit): detect if KGM extension is enabled in Goose config →
  if yes, rebuild KGM entities from OKF bundle indexes → if no,
  skip silently
- Add to `agentfs-setup/SKILL.md` sync instructions: mention KGM
  reindex as part of `sync agentfs` when KGM is enabled

**Detection method:**
```bash
# Check if goose config has kgm/knowledge-graph-memory enabled
grep -A2 'knowledge.graph.memory\|kgm' ~/.config/goose/config.yaml \
  | grep 'enabled: true' && KGM_ENABLED=true || KGM_ENABLED=false
```

**Reindex method:**
- Parse `~/.agents/knowledge/index.md` for bundle list
- For each bundle, parse its `index.md` for concept list
- Generate JSONL entries matching A8 schema
- Write to `MEMORY_FILE_PATH` (default:
  `~/.agents/knowledge/.kgm-index.jsonl`)

**Acceptance criteria:**
- [ ] `sync agentfs` with KGM enabled → reindexes knowledge
- [ ] `sync agentfs` with KGM disabled → no error, no output
- [ ] Reindex is idempotent (full rebuild, not append)
- [ ] `.kgm-index.jsonl` added to `~/.agents/.gitignore`

---

## Phase 4: Documentation

### A10. Update `~/.agents/README.md`

**Requires:** A5–A7 complete (Phase 2 done)

**Changes:**
- Update Structural Guardrails section: flat table format,
  12 rules, no enforcement level markers
- Update guardrail type table: remove Gate/Rule/Habit taxonomy
- Update template version references: 5.0.0
- Add KGM as optional capability (if A8–A9 complete)
- Update any prose that references old guardrail numbers/names

### A11. Archive strategy docs into `agentfs-setup`

**Strategy:** Documentation section of strategy doc
**Requires:** A10 complete

**Deliverables:**
- Copy `agentfs-v5-strategy.md` →
  `~/.agents/skills/agentfs-setup/references/v5-strategy.md`
- Copy `agentfs-v5-action-plan.md` →
  `~/.agents/skills/agentfs-setup/references/v5-action-plan.md`
- Copy migration map from A3 already at
  `~/.agents/skills/agentfs-setup/references/v5-migration-map.md`
- Bump `agentfs-setup` version to `5.0.0`
- Update `agentfs-setup/CHANGELOG.md`

---

## Version Bumps Summary

| Artifact | Current | Target | When |
|----------|---------|--------|------|
| `agentfs-setup` skill | 4.19.0 | 5.0.0 | A11 (after all changes) |
| AGENTS.md template | 4.19.0 | 5.0.0 | A5 |
| `agentfs-git-push` skill | — | 1.0.0 | A1 (new) |
| `goose-kgm` skill | — | 1.0.0 | A4 (new) |

## Execution Order (Recommended)

```
Session 1:  A1 (create agentfs-git-push)
            A2 (verify agentfs-setup coverage)
            A3 (validate content coverage, create migration map)

Session 2:  A4 (create goose-kgm) — can overlap with Session 1

Session 3:  A5 (rewrite seed template)
            A6 (test fidelity — template only, no project sync yet)

Session 4:  A8 (KGM entity schema)
            A9 (conditional reindex in sync)

Session 5:  A7 (sync THIS project — integration test with KGM enabled)
            A10 (update README)
            A11 (archive docs, final version bump)
```

Sessions 1 and 2 can run in parallel. Sessions 3–5 are serial.
Each session should commit and push on completion.

A7 is intentionally last among functional actions — it is the
integration test gate. Other projects sync on next use, not in
this rollout.

## Rollback Plan

If v5 causes compliance regression in production use:
1. `git revert` the seed template commit (A5)
2. Re-sync affected projects with `sync-agents-md.sh`
   (reverted template restores v4.x)
3. `agentfs-git-push` skill remains — it adds capability without
   removing anything
4. KGM integration (Phase 3) is fully independent — no rollback needed

The rollback is clean because the seed template is the single source
of truth for generated AGENTS.md content.
