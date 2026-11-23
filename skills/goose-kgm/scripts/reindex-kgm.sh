#!/usr/bin/env bash
# reindex-kgm.sh — Rebuild KGM JSONL index from OKF knowledge bundles
#
# Usage: bash reindex-kgm.sh [--check-enabled]
#   --check-enabled  Only reindex if KGM is enabled in Goose config (for use by post-edit.sh)
#
# Reads ~/.agents/knowledge/index.md to discover bundles, then parses
# each bundle's index.md for concept entries. Generates JSONL entities
# matching the KGM entity schema.
set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
source "${HOME}/.agents/scripts/agentfs-contract.sh"   # KGM_EXT_KEY / KGM_EXT_NAME / KGM_TOOL_PREFIX
trace_init "goose-kgm" "1.8.5" 2>/dev/null || true

KNOWLEDGE_DIR="$HOME/.agents/knowledge"
INDEX="$KNOWLEDGE_DIR/index.md"
JSONL_KNOWLEDGE="$KNOWLEDGE_DIR/.kgm-knowledge.jsonl"
JSONL_COMBINED="$KNOWLEDGE_DIR/.kgm-index.jsonl"
CONFIG="$HOME/.config/goose/config.yaml"

# ── Optional: check if KGM is enabled ─────────────────────────────
if [[ "${1:-}" == "--check-enabled" ]]; then
  if ! grep -qF "$KGM_EXT_KEY" "$CONFIG" 2>/dev/null; then
    exit 0  # Not configured — silent skip
  fi
  ENABLED=$(python3 -c "
import yaml, os
config = yaml.safe_load(open(os.path.expanduser('~/.config/goose/config.yaml')))
ext = config.get('extensions', {}).get('$KGM_EXT_KEY', {})
print('yes' if ext.get('enabled') else 'no')
")
  if [[ "$ENABLED" != "yes" ]]; then
    exit 0  # Disabled — silent skip
  fi
fi

# ── Preflight ──────────────────────────────────────────────────────
if [[ ! -f "$INDEX" ]]; then
  echo "❌ Knowledge index not found: $INDEX"
  exit 1
fi

# ── Parse bundles and generate JSONL ───────────────────────────────
python3 << 'PYEOF'
import json, os, re, glob
from pathlib import Path

knowledge_dir = Path(os.path.expanduser("~/.agents/knowledge"))
index_path = knowledge_dir / "index.md"
jsonl_path = knowledge_dir / ".kgm-knowledge.jsonl"

entities = []

# Parse knowledge/index.md for bundle entries
# Supports two formats:
#   Table: | [bundle-name](./bundle-name/index.md) | tags | description | date |
#   List:  * [Bundle Name](bundle-name/index.md) - Description text...
index_text = index_path.read_text()

# Try table format first
bundle_pattern_table = re.compile(r'\|\s*\[([^\]]+)\]\(\.\/([^)]+)\/index\.md\)\s*\|([^|]*)\|([^|]*)\|')
# Then list format: * [Name](path/index.md) - description
bundle_pattern_list = re.compile(r'^\s*\*\s*\[([^\]]+)\]\(([^)]+)/index\.md\)\s*-?\s*(.*)', re.MULTILINE)

table_matches = list(bundle_pattern_table.finditer(index_text))
list_matches = list(bundle_pattern_list.finditer(index_text))

# Use whichever format has matches
if table_matches:
    bundle_entries = [(m.group(1).strip(), m.group(2).strip(), m.group(4).strip()) for m in table_matches]
elif list_matches:
    bundle_entries = [(m.group(1).strip(), m.group(2).strip(), m.group(3).strip()) for m in list_matches]
else:
    bundle_entries = []

for bundle_name, bundle_dir, description in bundle_entries:
    bundle_path = knowledge_dir / bundle_dir

    if not bundle_path.is_dir():
        continue

    # Create bundle entity
    bundle_entity = {
        "type": "entity",
        "name": f"bundle:{bundle_name}",
        "entityType": "KnowledgeBundle",
        "observations": [
            f"Source: {bundle_path}/index.md",
            f"Summary: {description}",
        ]
    }
    entities.append(bundle_entity)

    # Parse bundle's index.md for concept entries
    bundle_index = bundle_path / "index.md"
    if not bundle_index.is_file():
        continue

    bundle_text = bundle_index.read_text()
    # Look for markdown links to .md files (concepts)
    # Table format: | [Name](file.md) | ... |  — link with or without leading ./
    #   Summary column is chosen by header name (Description/Summary/Topic);
    #   falls back to the column right after the link when no header matches.
    # List format: * [Name](file.md) - description
    concept_pattern_list = re.compile(r'^\s*\*\s*\[([^\]]+)\]\(([^)]+\.md)\)\s*-?\s*(.*)', re.MULTILINE)
    link_re = re.compile(r'^\[([^\]]+)\]\(([^)]+\.md)\)$')
    SUMMARY_HEADERS = ("description", "summary", "topic")

    def split_row(line):
        return [c.strip() for c in line.strip().strip('|').split('|')]

    table_concepts = []  # (name, file, desc)
    header = None
    for line in bundle_text.splitlines():
        if not line.lstrip().startswith('|'):
            header = None
            continue
        cells = split_row(line)
        if all(re.fullmatch(r':?-{3,}:?', c) for c in cells if c):
            continue  # separator row
        link_idx = next((i for i, c in enumerate(cells) if link_re.match(c)), None)
        if link_idx is None:
            header = [c.lower() for c in cells]
            continue
        lm = link_re.match(cells[link_idx])
        desc_idx = None
        if header:
            desc_idx = next((i for i, h in enumerate(header) if h in SUMMARY_HEADERS), None)
        if desc_idx is None or desc_idx >= len(cells) or desc_idx == link_idx:
            desc_idx = link_idx + 1 if link_idx + 1 < len(cells) else None
        desc = cells[desc_idx] if desc_idx is not None else ""
        table_concepts.append((lm.group(1), lm.group(2), desc))

    list_concepts = [(m.group(1), m.group(2), m.group(3)) for m in concept_pattern_list.finditer(bundle_text)]
    concept_matches = table_concepts if table_concepts else list_concepts

    for c_name, c_file, c_desc in concept_matches:
        concept_name = c_name.strip()
        concept_file = c_file.strip()
        # Remove leading ./ if present (exact prefix, not a character set)
        if concept_file.startswith('./'):
            concept_file = concept_file[2:]
        concept_desc = c_desc.strip()
        concept_path = bundle_path / concept_file

        if not concept_path.is_file():
            continue

        concept_entity = {
            "type": "entity",
            "name": f"concept:{bundle_name}/{concept_name}",
            "entityType": "KnowledgeConcept",
            "observations": [
                f"Source: {concept_path}",
                f"Summary: {concept_desc}",
                f"Bundle: {bundle_name}",
            ]
        }
        entities.append(concept_entity)

        # Create contains relation
        entities.append({
            "type": "relation",
            "from": f"bundle:{bundle_name}",
            "to": f"concept:{bundle_name}/{concept_name}",
            "relationType": "contains"
        })

# Write JSONL
with open(jsonl_path, 'w') as f:
    for entity in entities:
        f.write(json.dumps(entity) + '\n')

bundle_count = sum(1 for e in entities if e.get("entityType") == "KnowledgeBundle")
concept_count = sum(1 for e in entities if e.get("entityType") == "KnowledgeConcept")
relation_count = sum(1 for e in entities if e.get("type") == "relation")

print(f"✅ KGM reindex complete: {jsonl_path}")
print(f"   Bundles:   {bundle_count}")
print(f"   Concepts:  {concept_count}")
print(f"   Relations: {relation_count}")
print(f"   Total lines: {len(entities)}")
PYEOF

# ── Reindex skills ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/reindex-skills-kgm.sh"

# ── Merge knowledge + skills → combined index ─────────────────────
SKILLS_JSONL="$HOME/.agents/skills/.kgm-skills.jsonl"
# Build in a temp file in the same directory, then rename: every running
# server re-reads the combined index on each search_nodes call, so an
# in-place rewrite could serve a truncated or empty file mid-reindex.
# rename(2) within one filesystem is atomic — readers see old or new.
TMP_COMBINED="$(mktemp "$KNOWLEDGE_DIR/.kgm-index.jsonl.XXXXXX")"
trap 'rm -f "$TMP_COMBINED"' EXIT
cat "$JSONL_KNOWLEDGE" > "$TMP_COMBINED"
if [[ -f "$SKILLS_JSONL" ]]; then
  cat "$SKILLS_JSONL" >> "$TMP_COMBINED"
fi
chmod 644 "$TMP_COMBINED"   # mktemp creates 0600; keep the index's usual mode
mv -f "$TMP_COMBINED" "$JSONL_COMBINED"
trap - EXIT
TOTAL=$(wc -l < "$JSONL_COMBINED")
echo "✅ Combined index: $JSONL_COMBINED ($TOTAL lines)"
# Servers read this file via MEMORY_FILE_PATH (env wrapper in config.yaml)
# on every call — no restart needed. Verify delivery with status-kgm.sh.
