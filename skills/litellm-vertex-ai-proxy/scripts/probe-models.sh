#!/usr/bin/env bash
# probe-models.sh — DEPRECATED compatibility wrapper (removed in litellm-vertex-ai-proxy v4.0.0).
# The probe now lives in the gcp-vertex-models skill.
set -euo pipefail
echo "⚠️  Deprecated path — use ~/.agents/skills/gcp-vertex-models/scripts/probe-models.sh" >&2
exec bash "${HOME}/.agents/skills/gcp-vertex-models/scripts/probe-models.sh" "$@"
