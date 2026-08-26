# goose-skupper-provider Changelog


| Updated | Change |
|---------|--------|
| 2026-08-26 17:07 | v5.3.0 — Fix test.sh T6 chat completion for reasoning models: increase max_tokens to 200, add reasoning_content fallback |
| 2026-08-26 14:08 | v5.2.0 — Set supports_streaming:false in setup.sh and PROVIDER.md. Workaround for goose v1.47.0 streaming tool-call parser bug: vLLM hermes sends name and initial args as separate entries in the same streaming chunk — goose drops the args-only entry, truncating tool call arguments. Non-streaming avoids the accumulation path entirely. Updated post-write validation assertion to match. |
| 2026-08-26 11:07 | v5.1.0 — Skill check fixes: Added Signal Routing Table with 10 signal patterns, routing rules, and preconditions. Expanded opening paragraph with why/when context. Signal phrases updated: added test/recreate/check, removed ambiguous bare query. Fixed heredoc injection risk: values passed via env vars with single-quoted PYEOF. Removed redundant changelog from PROVIDER.md (links to CHANGELOG.md). Made T8 concrete with injection test command. Fixed double-v in v5.0.0 changelog entry. |
| 2026-08-26 10:33 | v5.0.0 — API-driven model discovery replaces static alias mapping. setup.sh accepts host names (rhel-ai, rhtevan-work) or profile names (g8b-fp8-spec-128k). Model ID and context discovered from live API (/v1/models) — handles both vLLM (max_model_len) and llama.cpp (meta.n_ctx). Poison-JSON safeguard: JSON written via Python json.dumps (not heredoc), round-trip validated pre-write, post-write validated from disk, backup restored on any failure. SKILL.md rewritten: alias routing table replaced with host-based table, new S5/S6 specs for discovery and poison prevention, T7/T8 tests added. PROVIDER.md rewritten: alias references removed, API discovery documented, manual setup de-emphasized with safety warnings. |
| 2026-08-08 | v4.0 — All operations as scripts; added Spec and Tests; `writes-files: true`; applied skill-check 4 principles |
| 2026-08-08 | v3.1 — Schema warning in PROVIDER.md; incident fix |
| 2026-08-08 | v3.0 — Port 10000 for rhtevan-work; routing keys |
| 2026-08-07 | v2.0 — Multi-port; model alias routing |
| 2026-08-06 | v1.2 — Recreate capability |
| 2026-08-04 | v1.0 — Initial skill |
