#!/usr/bin/env bash
# enable-kgm.sh — DEPRECATED: KGM enable/disable is now session-scoped
#
# The agent should use the extensionmanager tool instead:
#   extensionmanager__manage_extensions(action: "enable", extension_name: "$KGM_TOOL_PREFIX")
#
# This script is retained for backward compatibility but simply prints
# instructions for the agent.
set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
source "${HOME}/.agents/scripts/agentfs-contract.sh"   # KGM_EXT_KEY / KGM_EXT_NAME / KGM_TOOL_PREFIX
trace_init "goose-kgm" "1.7.0" 2>/dev/null || true

cat << EOF
⚠️  KGM enable/disable is session-scoped (not global config).

To enable KGM in the current session, the agent should call:
  extensionmanager__manage_extensions(action: "enable", extension_name: "$KGM_TOOL_PREFIX")

This activates KGM tools (search_nodes, read_graph, etc.) for the
current session only, without modifying the global Goose config.

The global config retains enabled: false — KGM is opt-in per session.
EOF
