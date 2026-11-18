#!/usr/bin/env bash
# preflight-reminder: SessionStart (new sessions only). Clear this session
# ID's flag (IDs are reused) and drop flags from crashed sessions (> 1 h).
set -euo pipefail
sid="$(jq -r '.session_id // empty' 2>/dev/null || true)"
if [[ -n "$sid" ]]; then rm -f "/tmp/goose-preflight/${sid}" 2>/dev/null || true; fi
[[ -d /tmp/goose-preflight ]] && find /tmp/goose-preflight -type f -mmin +60 -delete 2>/dev/null || true
