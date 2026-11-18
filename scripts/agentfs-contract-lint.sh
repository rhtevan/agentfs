#!/usr/bin/env bash
# agentfs-contract-lint.sh — fail if a contract name is hardcoded outside
# scripts/agentfs-contract.sh. Scans code only (*.sh, *.json) under
# plugins/, scripts/, skills/ of ~/.agents (or $1). Docs may mention names.
# Exit: 0 clean, 1 literal copies found, 2 contract file missing.
set -uo pipefail
ROOT="${1:-$HOME/.agents}"
CONTRACT="$ROOT/scripts/agentfs-contract.sh"
[[ -f "$CONTRACT" ]] || { echo "[contract-lint] ❌ missing $CONTRACT"; exit 2; }
# shellcheck source=/dev/null
source "$CONTRACT"
hits=$(cd "$ROOT" && grep -rnF "$KGM_EXT_KEY" --include='*.sh' --include='*.json' plugins scripts skills 2>/dev/null \
  | grep -v '^scripts/agentfs-contract\.sh:' || true)
if [[ -n "$hits" ]]; then
  echo "[contract-lint] ❌ hardcoded KGM name '$KGM_EXT_KEY' (use \$KGM_EXT_KEY / \$KGM_TOOL_PREFIX / \$KGM_SEARCH_TOOL from scripts/agentfs-contract.sh):"
  echo "$hits" | sed 's/^/  /'
  exit 1
fi
echo "[contract-lint] ✅ no hardcoded contract names"
