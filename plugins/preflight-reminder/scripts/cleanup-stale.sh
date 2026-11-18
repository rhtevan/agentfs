#!/usr/bin/env bash
# preflight-reminder: drop flags from crashed sessions (older than 1 hour).
set -euo pipefail
[[ -d /tmp/goose-preflight ]] && find /tmp/goose-preflight -type f -mmin +60 -delete 2>/dev/null || true
