#!/usr/bin/env bash
# delete.sh — Delete Goose sessions by category
# Usage: delete.sh [--recipe] [--terminal] [--hidden] [--desktop] [--all]
#                  [--before YYYY-MM-DD] [--include-tracked] [--ids ID1,ID2,...]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-recipe-session-cleanup" "1.0.0" 2>/dev/null || true

BEFORE_DATE=""
DELETE_RECIPE=false
DELETE_TERMINAL=false
DELETE_HIDDEN=false
DELETE_DESKTOP=false
INCLUDE_TRACKED=false
SPECIFIC_IDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before) BEFORE_DATE="$2"; shift 2 ;;
    --recipe) DELETE_RECIPE=true; shift ;;
    --terminal) DELETE_TERMINAL=true; shift ;;
    --hidden) DELETE_HIDDEN=true; shift ;;
    --desktop) DELETE_DESKTOP=true; shift ;;
    --all) DELETE_RECIPE=true; DELETE_TERMINAL=true; DELETE_HIDDEN=true; DELETE_DESKTOP=true; shift ;;
    --include-tracked) INCLUDE_TRACKED=true; shift ;;
    --ids) SPECIFIC_IDS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

DB_PATH="${HOME}/.local/share/goose/sessions/sessions.db"
PROJECTS_FILE="${HOME}/.local/share/goose/projects.json"

if [[ ! -f "$DB_PATH" ]]; then
  echo "✗ Sessions database not found: $DB_PATH"
  exit 1
fi

if ! $DELETE_RECIPE && ! $DELETE_TERMINAL && ! $DELETE_HIDDEN && ! $DELETE_DESKTOP && [[ -z "$SPECIFIC_IDS" ]]; then
  echo "Usage: delete.sh [--recipe] [--terminal] [--hidden] [--desktop] [--all]"
  echo "                 [--before YYYY-MM-DD] [--include-tracked] [--ids ID1,ID2,...]"
  echo ""
  echo "No categories selected. Nothing to delete."
  exit 1
fi

# ── Step 1: Build deletion config ────────────────────────────────────────
trace_step 1 "build_config" 0 "before=${BEFORE_DATE:-all}" 2>/dev/null || true

SKIP_TRACKED="True"
$INCLUDE_TRACKED && SKIP_TRACKED="False"

PY_DELETE_RECIPE="False"; $DELETE_RECIPE && PY_DELETE_RECIPE="True"
PY_DELETE_TERMINAL="False"; $DELETE_TERMINAL && PY_DELETE_TERMINAL="True"
PY_DELETE_HIDDEN="False"; $DELETE_HIDDEN && PY_DELETE_HIDDEN="True"
PY_DELETE_DESKTOP="False"; $DELETE_DESKTOP && PY_DELETE_DESKTOP="True"

# ── Step 2: Execute deletion ─────────────────────────────────────────────
trace_step 2 "execute_deletion" 0 "" 2>/dev/null || true

python3 << DELETE_PYTHON_EOF
import sqlite3, os, json

DB_PATH = os.path.expanduser("${DB_PATH}")
PROJECTS_FILE = os.path.expanduser("${PROJECTS_FILE}")
BEFORE_DATE = "${BEFORE_DATE}"
DELETE_RECIPE = ${PY_DELETE_RECIPE}
DELETE_TERMINAL = ${PY_DELETE_TERMINAL}
DELETE_HIDDEN = ${PY_DELETE_HIDDEN}
DELETE_DESKTOP = ${PY_DELETE_DESKTOP}
SKIP_TRACKED = ${SKIP_TRACKED}
SPECIFIC_IDS_STR = "${SPECIFIC_IDS}"

DELETE_SPECIFIC_IDS = [s.strip() for s in SPECIFIC_IDS_STR.split(",") if s.strip()] if SPECIFIC_IDS_STR else []

date_filter = ""
if BEFORE_DATE:
    date_filter = f" AND created_at < '{BEFORE_DATE}'"

tracked_sids = set()
if SKIP_TRACKED and DELETE_DESKTOP:
    try:
        with open(PROJECTS_FILE) as f:
            pdata = json.load(f)
        for path, info in pdata.get("projects", {}).items():
            sid = info.get("last_session_id")
            if sid:
                tracked_sids.add(sid)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

def delete_sessions(where_clause, label, skip_ids=None):
    params = []
    wc = where_clause
    if skip_ids:
        placeholders = ",".join(["?" for _ in skip_ids])
        wc += f" AND id NOT IN ({placeholders})"
        params = list(skip_ids)

    cur.execute(f"SELECT COUNT(*) FROM sessions WHERE {wc}", params)
    session_count = cur.fetchone()[0]
    if session_count == 0:
        print(f"   {label}: nothing to delete")
        return 0, 0

    cur.execute(f"SELECT COUNT(*) FROM messages WHERE session_id IN (SELECT id FROM sessions WHERE {wc})", params)
    msg_count = cur.fetchone()[0]

    cur.execute(f"DELETE FROM messages WHERE session_id IN (SELECT id FROM sessions WHERE {wc})", params)
    cur.execute(f"DELETE FROM usage_ledger WHERE session_id IN (SELECT id FROM sessions WHERE {wc})", params)
    cur.execute(f"DELETE FROM sessions WHERE {wc}", params)

    print(f"   {label}: {session_count} sessions, {msg_count} messages removed")
    return session_count, msg_count

total_sessions = 0
total_messages = 0

if DELETE_SPECIFIC_IDS:
    for sid in DELETE_SPECIFIC_IDS:
        cur.execute("SELECT id, name FROM sessions WHERE id=?", (sid,))
        row = cur.fetchone()
        if not row:
            print(f"   ⚠  {sid}: not found, skipping")
            continue
        if sid in tracked_sids and SKIP_TRACKED:
            print(f"   ⏭  {sid} ({row[1]}): tracked in projects.json, skipping")
            continue
        cur.execute("DELETE FROM messages WHERE session_id=?", (sid,))
        mc = cur.rowcount
        cur.execute("DELETE FROM usage_ledger WHERE session_id=?", (sid,))
        cur.execute("DELETE FROM sessions WHERE id=?", (sid,))
        print(f"   ✅ {sid} ({row[1]}): {mc} messages removed")
        total_sessions += 1
        total_messages += mc
else:
    if DELETE_RECIPE:
        s, m = delete_sessions(f"recipe_json IS NOT NULL{date_filter}", "Recipe sessions")
        total_sessions += s; total_messages += m

    if DELETE_TERMINAL:
        s, m = delete_sessions(f"session_type='terminal'{date_filter}", "Terminal sessions")
        total_sessions += s; total_messages += m

    if DELETE_HIDDEN:
        s, m = delete_sessions(f"session_type='hidden'{date_filter}", "Hidden sessions")
        total_sessions += s; total_messages += m

    if DELETE_DESKTOP:
        skip = tracked_sids if SKIP_TRACKED else None
        s, m = delete_sessions(f"session_type='user' AND recipe_json IS NULL{date_filter}", "Desktop sessions", skip_ids=skip)
        total_sessions += s; total_messages += m
        if SKIP_TRACKED and tracked_sids:
            print(f"   ⏭  Skipped {len(tracked_sids)} session(s) tracked in projects.json")

conn.commit()

if total_sessions > 10:
    print("\\n   Running VACUUM to reclaim disk space...")
    conn.execute("VACUUM")
    print(f"   Database size now: {os.path.getsize(DB_PATH) / 1_048_576:.1f} MB")

conn.close()
print(f"\\n✅ Cleanup complete: {total_sessions} sessions, {total_messages} messages removed")
DELETE_PYTHON_EOF

trace_end 2>/dev/null || true
