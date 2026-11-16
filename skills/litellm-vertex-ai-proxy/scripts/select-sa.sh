#!/usr/bin/env bash
# select-sa.sh — DEPRECATED compatibility wrapper (removed in litellm-vertex-ai-proxy v5.0.0).
# GCP credential selection now lives in the gcp-vertex-models skill.
set -euo pipefail
echo "⚠️  Deprecated path — use ~/.agents/skills/gcp-vertex-models/scripts/select-sa.sh" >&2
exec bash "${HOME}/.agents/skills/gcp-vertex-models/scripts/select-sa.sh" "$@"
