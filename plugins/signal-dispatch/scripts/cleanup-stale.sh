#!/usr/bin/env bash
# signal-dispatch: called by SessionStart (new sessions only, not --resume).
# Clears state for THIS session ID (goose reuses IDs, so a stale 'pending'
# from an earlier session with the same ID would block this one) and
# removes files older than 1 hour from crashed sessions.
set -euo pipefail
dispatch_dir="/tmp/goose-dispatch"
sid="$(jq -r '.session_id // empty' 2>/dev/null || true)"
if [[ -n "$sid" ]]; then rm -f "${dispatch_dir}/${sid}" "${dispatch_dir}/${sid}.keywords" 2>/dev/null || true; fi
if [ -d "$dispatch_dir" ]; then
  find "$dispatch_dir" -type f -mmin +60 -delete 2>/dev/null || true
fi
