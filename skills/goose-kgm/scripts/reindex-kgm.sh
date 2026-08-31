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

KNOWLEDGE_DIR="$HOME/.agents/knowledge"
INDEX="$KNOWLEDGE_DIR/index.md"
JSONL_PATH="$KNOWLEDGE_DIR/.kgm-index.jsonl"
CONFIG="$HOME/.config/goose/config.yaml"

# ── Optional: check if KGM is enabled ─────────────────────────────
if [[ "${1:-}" == "--check-enabled" ]]; then
  if ! grep -q 'knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
    exit 0  # Not configured — silent skip
  fi
  ENABLED=$(python3 -c "
import yaml, os
config = yaml.safe_load(open(os.path.expanduser('~/.config/goose/config.yaml')))
ext = config.get('extensions', {}).get('knowledgegraphmemory', {})
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
jsonl_path = knowledge_dir / ".kgm-index.jsonl"

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
    # Table format: | [Name](./file.md) | description |
    concept_pattern_table = re.compile(r'\|\s*\[([^\]]+)\]\(\.\/([^)]+\.md)\)\s*\|([^|]*)\|')
    # List format: * [Name](file.md) - description
    concept_pattern_list = re.compile(r'^\s*\*\s*\[([^\]]+)\]\(([^)]+\.md)\)\s*-?\s*(.*)', re.MULTILINE)

    table_concepts = list(concept_pattern_table.finditer(bundle_text))
    list_concepts = list(concept_pattern_list.finditer(bundle_text))
    concept_matches = table_concepts if table_concepts else list_concepts

    for cmatch in concept_matches:
        concept_name = cmatch.group(1).strip()
        concept_file = cmatch.group(2).strip()
        # Remove leading ./ if present
        concept_file = concept_file.lstrip('./')
        concept_desc = cmatch.group(3).strip()
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
