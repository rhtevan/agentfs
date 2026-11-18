#!/usr/bin/env bash
# agentfs-contract.sh — single source of truth for external names AgentFS
# depends on. Source it; do not execute it:
#   source "$HOME/.agents/scripts/agentfs-contract.sh"
# Lint: bash ~/.agents/scripts/agentfs-contract-lint.sh (no literal copies
# of these names in plugins/, scripts/, skills/ code).
#
# KGM (Knowledge Graph Memory) extension
#   goose names MCP tools <prefix>__<tool>. The prefix comes from the
#   extension's `name` field, NOT its config key: lowercased, whitespace
#   removed, characters outside [a-z0-9_-] replaced by '_'. Verified
#   2026-11-17 on goose 1.59.2: key 'kgmkey' + name 'Probe Name Field' ->
#   probenamefield__search_nodes; name 'KGM-Test_2 x.y' -> kgm-test_2x_y__.
#   Renaming the display name therefore renames every KGM tool.

export KGM_EXT_KEY="knowledgegraphmemory"     # config.yaml: extensions.<key>
export KGM_EXT_NAME="Knowledge Graph Memory"  # extensions.<key>.name -> tool prefix

# kgm_tool_prefix [NAME] — the tool prefix goose derives from an extension name.
kgm_tool_prefix() {
  local n="${1-$KGM_EXT_NAME}"
  n="${n,,}"
  n="${n//[[:space:]]/}"
  printf '%s' "${n//[^a-z0-9_-]/_}"
}

KGM_TOOL_PREFIX="$(kgm_tool_prefix)"
KGM_SEARCH_TOOL="${KGM_TOOL_PREFIX}__search_nodes"
export KGM_TOOL_PREFIX KGM_SEARCH_TOOL
