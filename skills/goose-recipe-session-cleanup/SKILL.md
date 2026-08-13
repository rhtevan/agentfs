---
name: goose-recipe-session-cleanup
description: >
  clean goose sessions, cleanup recipe sessions, remove orphaned sessions,
  clean desktop sessions, clean terminal sessions
metadata:
  author: agentfs
  version: "3.0.0"
  tags: [goose, recipe, session, cleanup, orphan, desktop, terminal]
---

# goose-recipe-session-cleanup

Identify and remove Goose session records from the sessions database.
Covers all four session categories with per-category opt-in and optional
date filtering.

## Problem

Goose accumulates session records in its SQLite database over time:

- **Recipe sessions** from ad-hoc CLI runs are invisible in Desktop UI
- **Terminal sessions** from `goose term` are never shown anywhere
- **Hidden sessions** from `goose doctor` are diagnostic leftovers
- **Desktop sessions** from interactive use may become stale over time

Without periodic cleanup, the database grows large and fills with
sessions that will never be revisited.

## Architecture

Goose stores sessions in two places:

| Store | Path | Purpose |
|-------|------|---------|
| **SQLite DB** | `~/.local/share/goose/sessions/sessions.db` | All session metadata + messages |
| **projects.json** | `~/.local/share/goose/projects.json` | Desktop UI project/session visibility |

The DB contains four session categories with distinct characteristics:

| Category | `session_type` | DB marker | `name` pattern | `provider_name` | `extension_data` |
|----------|----------------|-----------|----------------|-----------------|-------------------|
| **Desktop** | `user` | `recipe_json IS NULL` | Descriptive, user-assigned | Set (e.g. `custom_redhat`) | Full JSON with extensions |
| **Recipe** | `user` | `recipe_json IS NOT NULL` | Auto-generated from recipe | Set | Full JSON |
| **Terminal** | `terminal` | — | Always `"Goose Term Session"` | `None` | `{}` (empty) |
| **Hidden** | `hidden` | — | Always `"/doctor I ran /doctor"` | `None` | varies |

## How It Works

The scan queries the SQLite database and groups results into four
categories. The user can:

- Supply a **before date** to only target old sessions
- Choose which **categories** to delete (any combination)
- Say **"clean all sessions"** to include every category

Deletion removes `sessions`, `messages`, and `usage_ledger` records.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `before_date` | *(none — show all)* | Only show/delete sessions created before this date (ISO 8601: `YYYY-MM-DD`) |

The agent should ask if the user wants to filter by date. If the user
says something like "clean sessions before July", "older than 30 days",
or "before 2026-07-01", convert that to a `YYYY-MM-DD` value and pass
it to the scan script as the `BEFORE_DATE` variable.

## Procedure

Follow these steps **in order**. Do NOT skip the confirmation step.

### Step 1 — Scan and Identify

Run this script to scan all session categories. Set `BEFORE_DATE` to
filter, or leave empty to show all.

```bash
python3 << 'SCAN_EOF'
import sqlite3, os, json
from datetime import datetime

DB_PATH = os.path.expanduser("~/.local/share/goose/sessions/sessions.db")
PROJECTS_FILE = os.path.expanduser("~/.local/share/goose/projects.json")

# ── CONFIG ──────────────────────────────────────────────────────────────
# Set to "YYYY-MM-DD" to only show sessions created before this date.
# Leave as "" to show all sessions.
BEFORE_DATE = ""  # e.g. "2026-07-01"
# ────────────────────────────────────────────────────────────────────────

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

# Load projects.json for cross-reference
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

# ── HEADER ──────────────────────────────────────────────────────────────
print("=" * 90)
print("GOOSE SESSION CLEANUP REPORT")
print("=" * 90)
print(f"Sessions database: {DB_PATH}")
print(f"Database size:     {os.path.getsize(DB_PATH) / 1_048_576:.1f} MB")
print(f"Date filter:       {date_label}")
print()

# Overall counts (unfiltered)
cur.execute("SELECT session_type, COUNT(*) FROM sessions GROUP BY session_type")
type_counts = dict(cur.fetchall())
print("Total sessions in database (all time):")
for stype in ['user', 'terminal', 'hidden']:
    print(f"  {stype:>10}: {type_counts.get(stype, 0)}")
print(f"Projects in projects.json:  {len(project_dirs)}")
print(f"Tracked session IDs:        {len(tracked_sids)}")

# ── SECTION 1: RECIPE SESSIONS ──────────────────────────────────────────
print()
print("─" * 90)
print("① RECIPE SESSIONS (ad-hoc CLI recipe runs)")
print("─" * 90)

cur.execute(f"""
    SELECT s.id, s.name, s.working_dir, s.created_at,
           s.total_tokens, s.provider_name,
           COUNT(m.id) as msg_count
    FROM sessions s
    LEFT JOIN messages m ON m.session_id = s.id
    WHERE s.recipe_json IS NOT NULL{date_filter_s}
    GROUP BY s.id
    ORDER BY s.created_at DESC
""")
recipe_sessions = cur.fetchall()

if not recipe_sessions:
    print("   ✅ No recipe sessions found.")
else:
    print(f"   Found: {len(recipe_sessions)} sessions")
    print()
    print(f"   {'ID':<16} {'Created':<20} {'Msgs':<6} {'Tokens':<10} {'Provider':<18} Name")
    print(f"   {'-'*86}")
    for sid, name, wdir, created, tokens, provider, msgs in recipe_sessions:
        tokens_str = str(tokens) if tokens else "0"
        prov = provider or "(none)"
        print(f"   {sid:<16} {created:<20} {msgs:<6} {tokens_str:<10} {prov:<18} {name}")

# ── SECTION 2: TERMINAL SESSIONS ────────────────────────────────────────
print()
print("─" * 90)
print("② TERMINAL SESSIONS (goose term)")
print("─" * 90)

cur.execute(f"""
    SELECT COUNT(*) as cnt,
           MIN(created_at) as oldest,
           MAX(created_at) as newest,
           SUM(total_tokens) as total_tok
    FROM sessions
    WHERE session_type='terminal'{date_filter}
""")
row = cur.fetchone()
term_count, term_oldest, term_newest, term_tokens = row

if not term_count:
    print("   ✅ No terminal sessions found.")
else:
    cur.execute(f"""
        SELECT COUNT(*) FROM messages WHERE session_id IN
        (SELECT id FROM sessions WHERE session_type='terminal'{date_filter})
    """)
    term_msg_count = cur.fetchone()[0]
    print(f"   Found:    {term_count} sessions ({term_msg_count} messages)")
    print(f"   Oldest:   {term_oldest}")
    print(f"   Newest:   {term_newest}")
    print(f"   Tokens:   {term_tokens or 0}")
    print("   Never visible in Desktop UI or 'goose session list'.")

# ── SECTION 3: HIDDEN SESSIONS ──────────────────────────────────────────
print()
print("─" * 90)
print("③ HIDDEN SESSIONS (goose doctor)")
print("─" * 90)

cur.execute(f"""
    SELECT COUNT(*) as cnt,
           MIN(created_at) as oldest,
           MAX(created_at) as newest
    FROM sessions
    WHERE session_type='hidden'{date_filter}
""")
row = cur.fetchone()
hidden_count, hidden_oldest, hidden_newest = row

if not hidden_count:
    print("   ✅ No hidden sessions found.")
else:
    print(f"   Found:    {hidden_count} sessions")
    print(f"   Oldest:   {hidden_oldest}")
    print(f"   Newest:   {hidden_newest}")
    print("   Diagnostic sessions from 'goose doctor' runs.")

# ── SECTION 4: DESKTOP SESSIONS ─────────────────────────────────────────
print()
print("─" * 90)
print("④ DESKTOP SESSIONS (interactive UI / goose session)")
print("─" * 90)

cur.execute(f"""
    SELECT COUNT(*) as cnt,
           MIN(created_at) as oldest,
           MAX(created_at) as newest,
           SUM(total_tokens) as total_tok
    FROM sessions
    WHERE session_type='user' AND recipe_json IS NULL{date_filter}
""")
row = cur.fetchone()
desk_count, desk_oldest, desk_newest, desk_tokens = row

if not desk_count:
    print("   ✅ No desktop sessions found.")
else:
    cur.execute(f"""
        SELECT COUNT(*) FROM messages WHERE session_id IN
        (SELECT id FROM sessions WHERE session_type='user' AND recipe_json IS NULL{date_filter})
    """)
    desk_msg_count = cur.fetchone()[0]
    # Check how many are tracked in projects.json
    cur.execute(f"""
        SELECT id FROM sessions
        WHERE session_type='user' AND recipe_json IS NULL{date_filter}
    """)
    desk_sids = [r[0] for r in cur.fetchall()]
    tracked_count = sum(1 for s in desk_sids if s in tracked_sids)
    print(f"   Found:    {desk_count} sessions ({desk_msg_count} messages)")
    print(f"   Oldest:   {desk_oldest}")
    print(f"   Newest:   {desk_newest}")
    print(f"   Tokens:   {desk_tokens or 0}")
    print(f"   Tracked in projects.json: {tracked_count} (these will be skipped unless forced)")
    print("   These are normal interactive sessions — only deleted on explicit request.")

print()
print("=" * 90)

conn.close()
SCAN_EOF
```

### Step 2 — Present and Confirm

**STOP.** Present the scan report to the user. Do NOT proceed to
deletion without explicit human confirmation.

Interpret the user's request to determine which categories to clean:

| User says | Categories to delete |
|-----------|---------------------|
| "clean recipe sessions" | ① Recipe only |
| "clean terminal sessions" | ② Terminal only |
| "clean desktop sessions" | ④ Desktop only |
| "clean all sessions" | ① Recipe + ② Terminal + ③ Hidden + ④ Desktop |
| "clean recipe and terminal" | ① Recipe + ② Terminal |
| *(specific IDs)* | Only those session IDs |

If the user chose to include **Desktop sessions** (④), add a warning:

> ⚠️ **Desktop session deletion is destructive.** These are your
> interactive Goose sessions — once deleted, their conversation history
> is gone permanently. Sessions tracked in `projects.json` will be
> **skipped by default** to avoid breaking the Desktop UI sidebar.
> Say "include tracked" to override.

Ask the user to confirm before proceeding.

### Step 3 — Delete (only after confirmation)

Once the user confirms, run the appropriate deletion script.
Set `BEFORE_DATE` to match the filter used in the scan (or leave
empty if no filter was used). Set the `DELETE_*` flags based on
user choice.

```bash
python3 << 'DELETE_EOF'
import sqlite3, os, sys, json

DB_PATH = os.path.expanduser("~/.local/share/goose/sessions/sessions.db")
PROJECTS_FILE = os.path.expanduser("~/.local/share/goose/projects.json")

# ── CONFIG ──────────────────────────────────────────────────────────────
# Match the BEFORE_DATE used during scan ("" = no filter)
BEFORE_DATE = ""  # e.g. "2026-07-01"

# Set True/False based on user confirmation
DELETE_RECIPE = False
DELETE_TERMINAL = False
DELETE_HIDDEN = False
DELETE_DESKTOP = False

# Skip desktop sessions tracked in projects.json (safe default)
SKIP_TRACKED = True

# Or specify individual session IDs (overrides all flags above)
DELETE_SPECIFIC_IDS = [
    # "20260730_22",
    # "20260730_23",
]
# ────────────────────────────────────────────────────────────────────────

date_filter = ""
if BEFORE_DATE:
    date_filter = f" AND created_at < '{BEFORE_DATE}'"

# Load tracked session IDs if we need to protect them
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
    """Delete sessions matching where_clause. Returns (session_count, msg_count, usage_count)."""
    if skip_ids:
        placeholders = ",".join(["?" for _ in skip_ids])
        where_clause += f" AND id NOT IN ({placeholders})"

    cur.execute(f"SELECT COUNT(*) FROM sessions WHERE {where_clause}",
                list(skip_ids) if skip_ids else [])
    session_count = cur.fetchone()[0]
    if session_count == 0:
        print(f"   {label}: nothing to delete")
        return 0, 0, 0

    params = list(skip_ids) if skip_ids else []

    cur.execute(f"""SELECT COUNT(*) FROM messages WHERE session_id IN
                  (SELECT id FROM sessions WHERE {where_clause})""", params)
    msg_count = cur.fetchone()[0]

    cur.execute(f"""DELETE FROM messages WHERE session_id IN
                  (SELECT id FROM sessions WHERE {where_clause})""", params)
    cur.execute(f"""DELETE FROM usage_ledger WHERE session_id IN
                  (SELECT id FROM sessions WHERE {where_clause})""", params)
    usage_count = cur.rowcount
    cur.execute(f"DELETE FROM sessions WHERE {where_clause}", params)

    print(f"   {label}: {session_count} sessions, {msg_count} messages, {usage_count} usage records")
    return session_count, msg_count, usage_count

total_sessions = 0
total_messages = 0

if DELETE_SPECIFIC_IDS:
    for sid in DELETE_SPECIFIC_IDS:
        cur.execute("SELECT id, name FROM sessions WHERE id=?", (sid,))
        row = cur.fetchone()
        if not row:
            print(f"   ⚠️  {sid}: not found, skipping")
            continue
        if sid in tracked_sids and SKIP_TRACKED:
            print(f"   ⏭️  {sid} ({row[1]}): tracked in projects.json, skipping")
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
        s, m, u = delete_sessions(
            f"recipe_json IS NOT NULL{date_filter}",
            "Recipe sessions"
        )
        total_sessions += s
        total_messages += m

    if DELETE_TERMINAL:
        s, m, u = delete_sessions(
            f"session_type='terminal'{date_filter}",
            "Terminal sessions"
        )
        total_sessions += s
        total_messages += m

    if DELETE_HIDDEN:
        s, m, u = delete_sessions(
            f"session_type='hidden'{date_filter}",
            "Hidden sessions"
        )
        total_sessions += s
        total_messages += m

    if DELETE_DESKTOP:
        skip = tracked_sids if SKIP_TRACKED else None
        s, m, u = delete_sessions(
            f"session_type='user' AND recipe_json IS NULL{date_filter}",
            "Desktop sessions",
            skip_ids=skip
        )
        total_sessions += s
        total_messages += m
        if SKIP_TRACKED and tracked_sids:
            print(f"   ⏭️  Skipped {len(tracked_sids)} session(s) tracked in projects.json")

conn.commit()

# Vacuum to reclaim disk space if significant deletion occurred
if total_sessions > 10:
    print("\n   Running VACUUM to reclaim disk space...")
    conn.execute("VACUUM")
    print(f"   Database size now: {os.path.getsize(DB_PATH) / 1_048_576:.1f} MB")

conn.close()

print(f"\n✅ Cleanup complete: {total_sessions} sessions, {total_messages} messages removed")
DELETE_EOF
```

### Step 4 — Verify

After deletion, re-run the scan from Step 1 to confirm:
- Deleted categories now show zero (or reduced count)
- `goose session list` still works correctly
- Goose Desktop UI session list is unaffected for tracked sessions

## Safety Notes

- **Desktop sessions require explicit request.** They are only deleted
  when the user says "clean desktop sessions" or "clean all sessions".
- **Tracked sessions are protected by default.** Sessions referenced
  in `projects.json` (`last_session_id`) are skipped during desktop
  cleanup unless the user says "include tracked".
- **Hidden sessions are only deleted on explicit request or "clean all".**
- **VACUUM after bulk deletion.** SQLite doesn't reclaim disk space
  automatically — `VACUUM` is run when more than 10 sessions are deleted.
- **Idempotent.** Running the scan multiple times produces the same
  result. Deleting already-deleted sessions is a no-op.
- **projects.json is not modified.** This skill only modifies the
  SQLite database.
- **Date filter is optional.** When not set, all matching sessions
  across all time are included.

## Verification Checklist

- [ ] Scan completes without errors
- [ ] Report shows separate sections for each session category
- [ ] Date filter (if used) correctly limits results
- [ ] User confirmed deletion before any records were removed
- [ ] Desktop sessions tracked in projects.json were skipped (unless overridden)
- [ ] Post-deletion scan shows expected counts
- [ ] `goose session list` still works correctly
- [ ] Goose Desktop UI session list is unaffected for tracked sessions

## Changelog

| Date | Change |
|------|--------|
| 2026-07-30 | v3.0 — Desktop sessions now eligible for cleanup on explicit request; added ③ Hidden to deletable categories; added `SKIP_TRACKED` safety default for projects.json sessions; signal routing table for category selection; "clean all sessions" support |
| 2026-07-30 | v2.1 — Fixed SQL alias bugs in scan script; split `date_filter` / `date_filter_s` for joined vs non-joined queries |
| 2026-07-30 | v2.0 — Report shows 4 distinct sections; added optional `before_date` filter; configurable deletion flags; VACUUM only on bulk deletes |
| 2026-07-30 | v1.1 — Rewrote for SQLite DB storage (sessions.db), not .jsonl files; added terminal session cleanup; added usage_ledger cleanup; added VACUUM |
| 2026-07-30 | v1.0 — Initial creation (assumed .jsonl file storage) |
