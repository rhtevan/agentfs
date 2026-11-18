#!/usr/bin/env bash
# post-write-enforce: a NEW session starts with no pending post-write.
# goose reuses session IDs (date-scoped counter restarts at UTC midnight
# and after deletions), so a flag left by an earlier session with the same
# ID would block this one (2026-11-17: false block in benchmark t_r1).
# SessionStart fires for new sessions only, not on --resume.
set -euo pipefail
sid="$(jq -r '.session_id // empty' 2>/dev/null || true)"
if [[ -n "$sid" ]]; then rm -f "/tmp/goose-postwrite/${sid}" 2>/dev/null || true; fi
[[ -d /tmp/goose-postwrite ]] && find /tmp/goose-postwrite -type f -mmin +1440 -delete 2>/dev/null || true
