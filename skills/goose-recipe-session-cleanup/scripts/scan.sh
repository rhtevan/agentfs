#!/usr/bin/env bash
# scan.sh — Scan Goose sessions database and report categories
# Usage: scan.sh [--before YYYY-MM-DD] [--check]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-recipe-session-cleanup" "1.0.0" 2>/dev/null || true

BEFORE_DATE=""
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before) BEFORE_DATE="$2"; shift 2 ;;
    --check) CHECK_ONLY=true; shift ;;
    *) shift ;;
  esac
done

DB_PATH="${HOME}/.local/share/goose/sessions/sessions.db"
PROJECTS_FILE="${HOME}/.local/share/goose/projects.json"

# ── Step 1: Check database exists ────────────────────────────────────────
trace_step 1 "check_database" 0 "path=${DB_PATH}" 2>/dev/null || true

if [[ ! -f "$DB_PATH" ]]; then
  echo "✗ Sessions database not found: $DB_PATH"
  exit 1
fi

if $CHECK_ONLY; then
  echo "✓ Database exists: $DB_PATH ($(du -h "$DB_PATH" | cut -f1))"
  total=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo 0)
  echo "  Total sessions: $total"
  trace_end 2>/dev/null || true
  exit 0
fi

# ── Step 2: Run Python scan ──────────────────────────────────────────────
trace_step 2 "run_scan" 0 "before=${BEFORE_DATE:-all}" 2>/dev/null || true

python3 << SCAN_PYTHON_EOF
import sqlite3, os, json

DB_PATH = os.path.expanduser("${DB_PATH}")
PROJECTS_FILE = os.path.expanduser("${PROJECTS_FILE}")
BEFORE_DATE = "${BEFORE_DATE}"

if not os.path.exists(DB_PATH):
    print("ERROR: Sessions database not found at", DB_PATH)
    exit(1)

date_filter = ""
date_filter_s = ""
date_label = "all time"
if BEFORE_DATE:
    date_filter = f" AND created_at < '{BEFORE_DATE}'"
    date_filter_s = f" AND s.created_at < '{BEFORE_DATE}'"
    date_label = f"before {BEFORE_DATE}"

try:
    with open(PROJECTS_FILE) as f:
        pdata = json.load(f)
    project_dirs = set(pdata.get("projects", {}).keys())
    tracked_sids = set()
    for path, info in pdata.get("projects", {}).items():
        sid = info.get("last_session_id")
        if sid:
            tracked_sids.add(sid)
except (FileNotFoundError, json.JSONDecodeError):
    project_dirs = set()
    tracked_sids = set()

conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

print("=" * 90)
print("GOOSE SESSION CLEANUP REPORT")
print("=" * 90)
print(f"Sessions database: {DB_PATH}")
print(f"Database size:     {os.path.getsize(DB_PATH) / 1_048_576:.1f} MB")
print(f"Date filter:       {date_label}")
print()

cur.execute("SELECT session_type, COUNT(*) FROM sessions GROUP BY session_type")
type_counts = dict(cur.fetchall())
print("Total sessions in database (all time):")
for stype in ['user', 'terminal', 'hidden']:
    print(f"  {stype:>10}: {type_counts.get(stype, 0)}")
print(f"Projects in projects.json:  {len(project_dirs)}")
print(f"Tracked session IDs:        {len(tracked_sids)}")

# Recipe sessions
print()
print("-" * 90)
print("① RECIPE SESSIONS (ad-hoc CLI recipe runs)")
print("-" * 90)
cur.execute(f"""
    SELECT s.id, s.name, s.working_dir, s.created_at,
           s.total_tokens, s.provider_name, COUNT(m.id) as msg_count
    FROM sessions s LEFT JOIN messages m ON m.session_id = s.id
    WHERE s.recipe_json IS NOT NULL{date_filter_s}
    GROUP BY s.id ORDER BY s.created_at DESC
""")
recipe_sessions = cur.fetchall()
if not recipe_sessions:
    print("   No recipe sessions found.")
else:
    print(f"   Found: {len(recipe_sessions)} sessions")
    print(f"   {'ID':<16} {'Created':<20} {'Msgs':<6} {'Tokens':<10} {'Provider':<18} Name")
    print(f"   {'-'*86}")
    for sid, name, wdir, created, tokens, provider, msgs in recipe_sessions:
        print(f"   {sid:<16} {created:<20} {msgs:<6} {str(tokens or 0):<10} {(provider or '(none)'):<18} {name}")

# Terminal sessions
print()
print("-" * 90)
print("② TERMINAL SESSIONS (goose term)")
print("-" * 90)
cur.execute(f"SELECT COUNT(*), MIN(created_at), MAX(created_at), SUM(total_tokens) FROM sessions WHERE session_type='terminal'{date_filter}")
row = cur.fetchone()
if not row[0]:
    print("   No terminal sessions found.")
else:
    cur.execute(f"SELECT COUNT(*) FROM messages WHERE session_id IN (SELECT id FROM sessions WHERE session_type='terminal'{date_filter})")
    msg_count = cur.fetchone()[0]
    print(f"   Found:    {row[0]} sessions ({msg_count} messages)")
    print(f"   Oldest:   {row[1]}")
    print(f"   Newest:   {row[2]}")
    print(f"   Tokens:   {row[3] or 0}")

# Hidden sessions
print()
print("-" * 90)
print("③ HIDDEN SESSIONS (goose doctor)")
print("-" * 90)
cur.execute(f"SELECT COUNT(*), MIN(created_at), MAX(created_at) FROM sessions WHERE session_type='hidden'{date_filter}")
row = cur.fetchone()
if not row[0]:
    print("   No hidden sessions found.")
else:
    print(f"   Found:    {row[0]} sessions")
    print(f"   Oldest:   {row[1]}")
    print(f"   Newest:   {row[2]}")

# Desktop sessions
print()
print("-" * 90)
print("④ DESKTOP SESSIONS (interactive UI)")
print("-" * 90)
cur.execute(f"SELECT COUNT(*), MIN(created_at), MAX(created_at), SUM(total_tokens) FROM sessions WHERE session_type='user' AND recipe_json IS NULL{date_filter}")
row = cur.fetchone()
if not row[0]:
    print("   No desktop sessions found.")
else:
    cur.execute(f"SELECT COUNT(*) FROM messages WHERE session_id IN (SELECT id FROM sessions WHERE session_type='user' AND recipe_json IS NULL{date_filter})")
    msg_count = cur.fetchone()[0]
    cur.execute(f"SELECT id FROM sessions WHERE session_type='user' AND recipe_json IS NULL{date_filter}")
    desk_sids = [r[0] for r in cur.fetchall()]
    tracked_count = sum(1 for s in desk_sids if s in tracked_sids)
    print(f"   Found:    {row[0]} sessions ({msg_count} messages)")
    print(f"   Oldest:   {row[1]}")
    print(f"   Newest:   {row[2]}")
    print(f"   Tokens:   {row[3] or 0}")
    print(f"   Tracked:  {tracked_count} (protected by default)")

print()
print("=" * 90)
conn.close()
SCAN_PYTHON_EOF

trace_end 2>/dev/null || true
