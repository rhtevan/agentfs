#!/usr/bin/env bash
# ensure-kgm-symlink.sh — Ensure the MCP server's default memory.jsonl
# is a symlink to our managed .kgm-index.jsonl.
#
# WHY: Goose does not pass MEMORY_FILE_PATH from config.yaml envs to
#      the MCP stdio process. The server falls back to its built-in
#      default path (dist/memory.jsonl in its package dir). Without a
#      symlink, reindex-kgm.sh writes to a file the server never reads.
#
# FRAGILITY: `npx -y` can reinstall the package and replace the symlink
#            with a regular file. This script is idempotent — call it
#            from setup, reindex, and status to self-heal.
#
# Usage: bash ensure-kgm-symlink.sh [--quiet]
set -euo pipefail

QUIET="${1:-}"
JSONL_TARGET="$HOME/.agents/knowledge/.kgm-index.jsonl"

# Search all known npx cache locations
NPX_DIRS=(
  "$HOME/.npm/_npx"
  "$HOME/.config/goose/mcp-hermit/.hermit/node/cache/_npx"
)

FOUND=0
for NPX_DIR in "${NPX_DIRS[@]}"; do
  [[ -d "$NPX_DIR" ]] || continue

  # Find all server-memory memory.jsonl files (there may be multiple npx hash dirs)
  while IFS= read -r SERVER_MEM; do
    [[ -n "$SERVER_MEM" ]] || continue

    if [[ -L "$SERVER_MEM" ]]; then
      LINK_TARGET=$(readlink -f "$SERVER_MEM")
      EXPECTED_TARGET=$(readlink -f "$JSONL_TARGET" 2>/dev/null || echo "$JSONL_TARGET")
      if [[ "$LINK_TARGET" == "$EXPECTED_TARGET" ]]; then
        [[ "$QUIET" == "--quiet" ]] || echo "✅ Symlink OK: $SERVER_MEM → $JSONL_TARGET"
      else
        # Symlink points to wrong target — fix it
        rm "$SERVER_MEM"
        ln -s "$JSONL_TARGET" "$SERVER_MEM"
        [[ "$QUIET" == "--quiet" ]] || echo "🔧 Fixed symlink: $SERVER_MEM → $JSONL_TARGET (was → $LINK_TARGET)"
      fi
      FOUND=1
    elif [[ -f "$SERVER_MEM" ]]; then
      # Regular file — npx reinstalled and overwrote our symlink
      cp "$SERVER_MEM" "${SERVER_MEM}.bak"
      rm "$SERVER_MEM"
      ln -s "$JSONL_TARGET" "$SERVER_MEM"
      [[ "$QUIET" == "--quiet" ]] || echo "🔧 Replaced regular file with symlink: $SERVER_MEM → $JSONL_TARGET"
      FOUND=1
    fi
  done < <(find "$NPX_DIR" -path "*/server-memory/dist/memory.jsonl" 2>/dev/null)
done

if [[ "$FOUND" -eq 0 ]]; then
  [[ "$QUIET" == "--quiet" ]] || echo "⚠️  No server-memory package found in npx cache. Run the extension once to install, then re-run."
fi
