#!/usr/bin/env bash
# merge-log-entry.sh — Prepend a new log entry to any log.md file.
#
# Usage: bash merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>
#
# Writes ENTRY_TEXT verbatim under a timestamped ## YYYY-MM-DD HH:MM
# heading. If that heading already exists, appends under it. Otherwise
# creates a new heading above all existing date sections (reverse
# chronological order).
#
# Multiple lines can be passed as a single string with embedded
# newlines (\n). The script interprets \n escape sequences via printf.
#
# Do not start entries with a date/time: a leading timestamp on any
# entry line is stripped (with a stderr warning) to avoid duplicating
# the heading.
#
# Entry validation (see test-merge-log-entry.sh):
#   auto-fixed : raw <tag> outside backticks (wrapped, warns) — bare
#                angle brackets are parsed as HTML and swallow the
#                following content when rendered
#   rejected   : a line not starting with "- " or "  - "  (exit 2)
#   rejected   : the log's first line is not "# Directory Update Log"
#                (exit 1) — prevents injecting a second header mid-file
#   warned     : entry with no trailing (relative/path)
#
# Exit codes: 0 = success, 1 = malformed log file, 2 = invalid entry

set -euo pipefail

# Source trace library if available
if [[ -f "$HOME/.agents/scripts/trace-lib.sh" ]]; then
  source "$HOME/.agents/scripts/trace-lib.sh"
else
  trace_step() { echo "[trace] $*" >&2; }
fi

LOG_FILE="${1:?Usage: merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>}"
ENTRY_TEXT_RAW="${2:?Usage: merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>}"
# Interpret \n escape sequences so callers can pass multi-line entries
# as a single argument: "- line1\n- line2"
ENTRY_TEXT="$(printf '%b' "$ENTRY_TEXT_RAW")"

# ── Guard: strip caller-supplied leading timestamps ────────────────
# The ## YYYY-MM-DD HH:MM heading already carries the time. A line like
# "- 2026-11-13 20:20 foo" or "- 2026-11-13T19:54:02-05:00 foo" would
# duplicate it, so drop the leading date/time (and a trailing ':' or
# '—' separator) from every entry line and warn on stderr.
TS_RE='^(- )?[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}(:[0-9]{2})?([+-][0-9]{2}:?[0-9]{2}|Z)?)?[[:space:]]*(:|—|–)?[[:space:]]+'
if printf '%s\n' "$ENTRY_TEXT" | grep -qE "$TS_RE"; then
  echo "[merge-log-entry] ⚠️  Leading timestamp removed from entry text (the ## heading already has it)." >&2
  ENTRY_TEXT="$(printf '%s\n' "$ENTRY_TEXT" | sed -E "s/${TS_RE}/\\1/")"
fi

# ── Guard: entry shape ─────────────────────────────────────────────
# Every line must be a list item. A bare line renders as a paragraph
# glued to the previous entry and loses its bullet.
while IFS= read -r _line; do
  [[ -z "${_line//[[:space:]]/}" ]] && continue
  if [[ "$_line" != "- "* && "$_line" != "  - "* && "$_line" != "    - "* ]]; then
    echo "[merge-log-entry] ❌ Entry line must start with '- ' (or an indented '  - '):" >&2
    echo "    $_line" >&2
    exit 2
  fi
done <<< "$ENTRY_TEXT"

# ── Guard: raw HTML tags ───────────────────────────────────────────
# A bare <tag> outside backticks is passed through as HTML: an unclosed
# one swallows every following line until the renderer recovers. Wrap
# each offender in backticks rather than rejecting, so callers need not
# think about Markdown escaping.
if printf '%s' "$ENTRY_TEXT" | grep -qE '<[^ >`][^>]*>'; then
  FIXED="$(ENTRY="$ENTRY_TEXT" python3 -c '
import os, re, sys
out = []
for line in os.environ["ENTRY"].split("\n"):
    res, idx, ticks = [], 0, 0
    for m in re.finditer(r"<[^ >`][^>]*>", line):
        ticks += line.count("`", idx, m.start())
        res.append(line[idx:m.start()])
        res.append(m.group(0) if ticks % 2 else "`" + m.group(0) + "`")
        idx = m.end()
    res.append(line[idx:])
    out.append("".join(res))
sys.stdout.write("\n".join(out))
')"
  if [[ "$FIXED" != "$ENTRY_TEXT" ]]; then
    echo "[merge-log-entry] ⚠️  Raw <tag> wrapped in backticks (bare angle brackets render as HTML)." >&2
    ENTRY_TEXT="$FIXED"
  fi
fi

# ── Advisory: missing path suffix ──────────────────────────────────
# Filenames recur across skills; without a path the entry is ambiguous.
if ! printf '%s' "$ENTRY_TEXT" | grep -qE '\([^()]*\)[[:space:]]*$'; then
  echo "[merge-log-entry] ⚠️  Entry has no trailing (path) — may be ambiguous." >&2
fi

NOW="$(date '+%Y-%m-%d %H:%M')"

if [[ ! -f "$LOG_FILE" ]]; then
  # Create fresh log.md
  cat > "$LOG_FILE" << EOF
# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## ${NOW}
${ENTRY_TEXT}
EOF
  echo "Created $LOG_FILE with current entry."
  exit 0
fi

# ── Guard: the log must already be a well-formed log ───────────────
# The rebuild branch below re-emits the title. If the first line is
# anything else (e.g. a truncated "r# Directory Update Log" from a
# partial write), that branch injects a SECOND header mid-file and
# orphans everything beneath it. Refuse instead.
FIRST_LINE="$(head -1 "$LOG_FILE")"
if [[ "$FIRST_LINE" != "# Directory Update Log" ]]; then
  echo "[merge-log-entry] ❌ $LOG_FILE does not start with '# Directory Update Log':" >&2
  echo "    first line: $FIRST_LINE" >&2
  echo "    Refusing to write — repair the header first (a second header would be injected)." >&2
  exit 1
fi

# ── Serialize access with flock ────────────────────────────────────
# Prevents race condition when multiple post-write calls target
# the same log file in rapid succession.
LOCK_FILE="${LOG_FILE}.lock"
exec 9>"$LOCK_FILE"
flock 9

# Use unique temp file to prevent collisions
TMPFILE="$(mktemp "${LOG_FILE}.XXXXXX")"
# Do NOT remove LOCK_FILE: another process may already hold a
# descriptor on it, and recreating the path yields a different inode,
# so two writers would each "hold the lock" on separate files.
trap 'rm -f "$TMPFILE"' EXIT

# Re-read NOW inside lock — parallel callers may span a minute boundary
NOW="$(date '+%Y-%m-%d %H:%M')"

# Check if current timestamp heading already exists
if grep -q "^## ${NOW}" "$LOG_FILE"; then
  # Heading exists — insert new entries directly after heading (no blank line)
  awk -v heading="## ${NOW}" -v entry="$ENTRY_TEXT" '
    $0 == heading {
      print
      print entry
      found = 1
      next
    }
    # Skip blank line immediately after heading (entries go right after)
    found && /^[[:space:]]*$/ { found = 0; next }
    { found = 0; print }
  ' "$LOG_FILE" > "$TMPFILE"
  mv "$TMPFILE" "$LOG_FILE"
  echo "Appended entries under existing ## ${NOW} heading."
else
  # Heading does not exist — insert new section after the
  # "# Directory Update Log" heading (and any comment/blank lines after it)
  {
    echo "# Directory Update Log"
    echo ""
    # Preserve the comment line if it exists anywhere in the preamble
    # (head -3 missed it when extra blank lines pushed it down, and the
    # rebuild below then dropped it silently).
    if awk 'NR>1 && /^## /{exit} /<!-- Append-only/{found=1} END{exit !found}' "$LOG_FILE"; then
      echo "<!-- Append-only. Newest entries at top. -->"
      echo ""
    fi
    echo "## ${NOW}"
    echo "$ENTRY_TEXT"
    echo ""
    # Skip the original heading + comment + trailing blank lines, keep the rest
    awk '
      BEGIN { skip=1 }
      skip && /^#[^#]/ { next }
      skip && /^<!--/ { next }
      skip && /^[[:space:]]*$/ { next }
      { skip=0; print }
    ' "$LOG_FILE"
  } > "$TMPFILE"
  mv "$TMPFILE" "$LOG_FILE"
  echo "Inserted new ## ${NOW} section at top of log."
fi
