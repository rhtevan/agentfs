#!/usr/bin/env bash
# signal-dispatch: clean stale flag and keyword files from crashed sessions.
# Called by SessionStart hook. Removes any files older than 1 hour.
set -euo pipefail

dispatch_dir="/tmp/goose-dispatch"
if [ -d "$dispatch_dir" ]; then
  find "$dispatch_dir" -type f -mmin +60 -delete 2>/dev/null || true
fi
