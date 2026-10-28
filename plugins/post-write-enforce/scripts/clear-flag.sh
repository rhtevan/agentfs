#!/usr/bin/env bash
# post-write-enforce: clear pending flag after post-write.sh runs.
# Called by AfterShellExecution when command matches post-write.sh.
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"

flag_file="/tmp/goose-postwrite/${session_id}"
rm -f "$flag_file" 2>/dev/null
