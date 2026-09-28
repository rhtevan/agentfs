#!/usr/bin/env bash
# signal-dispatch: clear the hey-pending flag when search_nodes is called.
# This indicates the agent has started the dispatch flow correctly.
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"

rm -f "/tmp/goose-dispatch/${session_id}"
