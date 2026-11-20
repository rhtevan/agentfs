#!/usr/bin/env bash
# signal-dispatch: flag a "hey" dispatch as pending for this session.
# Called by UserPromptSubmit hook when prompt matches ^[Hh]ey .
# Also saves the keywords (everything after "hey ") for the block reason.
#
# Reads table-matched patterns from patterns.txt (single source of truth).
# If keywords match a pattern → Path A (no flag, model handles directly).
# If no match → Path B (flag set, enforce search_nodes via Signal Dispatch rule).
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
message="$(printf '%s' "$payload" | jq -r '.message // ""')"

dispatch_dir="/tmp/goose-dispatch"
mkdir -p "$dispatch_dir"
# Dispatch is per prompt: drop any state from an earlier prompt (or an
# earlier session that had the same reused ID) before deciding.
rm -f "${dispatch_dir}/${session_id}" "${dispatch_dir}/${session_id}.keywords" 2>/dev/null || true

# Extract keywords: strip leading "hey " (case-insensitive)
keywords="$(echo "$message" | sed -E 's/^[Hh]ey[[:space:]]+//')"
keywords_lower="$(echo "$keywords" | tr '[:upper:]' '[:lower:]')"

# Load table-matched patterns from patterns.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="$SCRIPT_DIR/../patterns.txt"

table_match=false
if [[ -f "$PATTERNS_FILE" ]]; then
  while IFS='|' read -r prefix _action; do
    # Skip comments and empty lines
    [[ -z "$prefix" || "$prefix" =~ ^# ]] && continue
    # 2.3.0: no trimming. A trailing space is intentional ("note " must not
    # match "notebook"); lowercase only.
    prefix="$(printf '%s' "$prefix" | tr '[:upper:]' '[:lower:]')"
    # Match if keywords start with this prefix
    if [[ "$keywords_lower" == "$prefix"* ]]; then
      table_match=true
      break
    fi
  done < "$PATTERNS_FILE"
else
  echo "[signal-dispatch] WARNING: patterns.txt not found at $PATTERNS_FILE" >&2
fi

# 2.4.0 fail-open: enforce only when the KGM extension is confirmed enabled.
# Any doubt (no config, other layout, no contract) -> no block; Rule 1 is
# left to the model.
kgm_enabled() {
  # shellcheck source=/dev/null
  source "$HOME/.agents/scripts/agentfs-contract.sh" 2>/dev/null || return 1
  [[ -n "${KGM_EXT_KEY:-}" ]] || return 1
  awk -v key="  ${KGM_EXT_KEY}:" '
    /^[^[:space:]#]/ { ext = ($0 ~ /^extensions:/); blk = 0; next }
    ext && $0 == key { blk = 1; next }
    blk && /^  [^ ]/ { blk = 0 }
    blk && /^    enabled:[[:space:]]*true[[:space:]]*$/ { found = 1 }
    END { exit !found }' "$HOME/.config/goose/config.yaml" 2>/dev/null
}

if [ "$table_match" = false ] && kgm_enabled; then
  # Unmatched signal — enforce search_nodes first via Signal Dispatch rule
  echo "pending" > "${dispatch_dir}/${session_id}"
  echo "$keywords" > "${dispatch_dir}/${session_id}.keywords"
fi
