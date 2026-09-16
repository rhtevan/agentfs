#!/usr/bin/env bash
# disable-kgm.sh — DEPRECATED: KGM enable/disable is now session-scoped
#
# The agent should use the extensionmanager tool instead:
#   extensionmanager__manage_extensions(action: "disable", extension_name: "knowledgegraphmemory")
#
# This script is retained for backward compatibility but simply prints
# instructions for the agent.
set -euo pipefail

cat << 'EOF'
⚠️  KGM enable/disable is session-scoped (not global config).

To disable KGM in the current session, the agent should call:
  extensionmanager__manage_extensions(action: "disable", extension_name: "knowledgegraphmemory")

This deactivates KGM tools for the current session only.
The JSONL index file is preserved on disk for future sessions.
EOF
