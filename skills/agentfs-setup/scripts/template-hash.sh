#!/usr/bin/env bash
# template-hash.sh — Content hashes of the base skill's template-owned prose,
# rendered from the seed scripts (the single sources of truth). Read-only:
# renders into a temp dir that is removed on exit.
#
# Usage: template-hash.sh
# Output (two lines):
#   RULES_HASH=<16 hex>   rules-hash.sh of the rendered project AGENTS.md
#                         (## Rules + ## Signal Dispatch; same function as
#                         compliance-profile.yaml agents_md_rules_hash)
#   SOUL_HASH=<16 hex>    sha256 of the rendered SOUL.md template section
#                         (# Agent Identity + ## Principles)
# Exit: 0 ok · 1 render failed
#
# Why: static-sheet-status.sh compared only version strings, so a record
# whose version field was advanced without a re-score looked CURRENT
# (2026-11-24: the 95.8 record was labelled 7.7.2 but scored on 7.6.0).
set -euo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.agents"
(cd "$T" && bash "$D/seed-agents-md.sh" --scope project "$T" >/dev/null 2>&1) || { echo "template-hash: AGENTS.md render failed" >&2; exit 1; }
bash "$D/seed-soul.sh" "$T/.agents/SOUL.md" >/dev/null 2>&1 || { echo "template-hash: SOUL.md render failed" >&2; exit 1; }
rules="$(bash "$HOME/.agents/scripts/rules-hash.sh" "$T/AGENTS.md")"
soul="$(sed '/PROJECT-OWNED/,$d' "$T/.agents/SOUL.md" | sed -e 's/[[:space:]]*$//' | sha256sum | cut -c1-16)"
[[ -n "$rules" && -n "$soul" ]] || { echo "template-hash: empty hash" >&2; exit 1; }
echo "RULES_HASH=$rules"
echo "SOUL_HASH=$soul"
