#!/usr/bin/env bash
# detect-sa.sh — DEPRECATED compatibility wrapper (removed in litellm-vertex-ai-proxy v5.0.0).
# GCP credential reporting now lives in the gcp-vertex-models skill.
set -euo pipefail
echo "⚠️  Deprecated path — use ~/.agents/skills/gcp-vertex-models/scripts/detect-sa.sh" >&2
exec bash "${HOME}/.agents/skills/gcp-vertex-models/scripts/detect-sa.sh" "$@"
