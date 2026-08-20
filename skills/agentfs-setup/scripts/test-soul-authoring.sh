#!/usr/bin/env bash
# test-soul-authoring.sh — Test suite for author-soul.sh and related changes.
#
# Usage: bash test-soul-authoring.sh [--verbose]
#
# Tests:
#   T1.x  author-soul.sh unit tests
#   T2.x  scaffold-dotagents.sh integration
#   T3.x  seed-agents-md.sh AGENTS.md template
#   T4.x  create-profile.sh integration

set -euo pipefail

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTHOR_SOUL="$SCRIPT_DIR/author-soul.sh"
SCAFFOLD="$SCRIPT_DIR/scaffold-dotagents.sh"
SEED_AGENTS="$SCRIPT_DIR/seed-agents-md.sh"
PROFILE_SCRIPT="$HOME/.agents/skills/agentfs-profile/scripts/create-profile.sh"

PASS=0
FAIL=0
SKIP=0

# ── Test helpers ──────────────────────────────────────────────────────
run_test() {
  local id="$1"
  local desc="$2"
  local result="$3"  # 'pass' | 'fail' | 'skip'
  local detail="${4:-}"

  if [[ "$result" == "pass" ]]; then
    echo "  ✅ $id: $desc"
    (( PASS++ )) || true
  elif [[ "$result" == "skip" ]]; then
    echo "  ⏭  $id: $desc — SKIPPED ($detail)"
    (( SKIP++ )) || true
  else
    echo "  ❌ $id: $desc"
    [[ -n "$detail" ]] && echo "     Detail: $detail"
    (( FAIL++ )) || true
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -q "$pattern" "$file" 2>/dev/null
}

assert_file_exists() {
  [[ -f "$1" ]]
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" ]]
}

# ── T1: author-soul.sh unit tests ────────────────────────────────────
echo ""
echo "━━━ T1: author-soul.sh unit tests ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# T1.1: Non-interactive default → writes Agentic SRE SOUL
TMPDIR1=$(mktemp -d)
SOUL1="$TMPDIR1/SOUL.md"
NON_INTERACTIVE=true bash "$AUTHOR_SOUL" --path "$SOUL1" --non-interactive > /dev/null 2>&1
exitcode=$?
if assert_file_exists "$SOUL1" && assert_file_contains "$SOUL1" 'Agentic SRE' && [[ $exitcode -eq 0 ]]; then
  run_test T1.1 "Non-interactive default writes Agentic SRE SOUL" pass
else
  run_test T1.1 "Non-interactive default writes Agentic SRE SOUL" fail "exit=$exitcode file=$(cat "$SOUL1" 2>/dev/null || echo 'MISSING')"
fi
rm -rf "$TMPDIR1"

# T1.2: Non-interactive profile → writes profile stub with override header
TMPDIR2=$(mktemp -d)
SOUL2="$TMPDIR2/SOUL.md"
bash "$AUTHOR_SOUL" --path "$SOUL2" --role-hint verifier --non-interactive > /dev/null 2>&1
if assert_file_exists "$SOUL2" && assert_file_contains "$SOUL2" 'verifier' && assert_file_contains "$SOUL2" 'IMPORTANT.*override\|override.*IMPORTANT\|overrides the default'; then
  run_test T1.2 "Non-interactive profile writes override stub" pass
else
  run_test T1.2 "Non-interactive profile writes override stub" fail "$(cat "$SOUL2" 2>/dev/null | head -5)"
fi
rm -rf "$TMPDIR2"

# T1.3: Non-interactive watchdog → name appears in SOUL
TMPDIR3=$(mktemp -d)
SOUL3="$TMPDIR3/SOUL.md"
bash "$AUTHOR_SOUL" --path "$SOUL3" --role-hint watchdog --non-interactive > /dev/null 2>&1
if assert_file_exists "$SOUL3" && assert_file_contains "$SOUL3" 'watchdog'; then
  run_test T1.3 "Profile role-hint 'watchdog' appears in stub" pass
else
  run_test T1.3 "Profile role-hint 'watchdog' appears in stub" fail
fi
rm -rf "$TMPDIR3"

# T1.4: Existing non-stub SOUL + non-interactive → kept unchanged
TMPDIR4=$(mktemp -d)
SOUL4="$TMPDIR4/SOUL.md"
echo "You are a custom engineer. You do real things." > "$SOUL4"
ORIGINAL=$(cat "$SOUL4")
bash "$AUTHOR_SOUL" --path "$SOUL4" --non-interactive > /dev/null 2>&1
if [[ "$(cat "$SOUL4")" == "$ORIGINAL" ]]; then
  run_test T1.4 "Existing non-stub SOUL kept unchanged in non-interactive mode" pass
else
  run_test T1.4 "Existing non-stub SOUL kept unchanged in non-interactive mode" fail "File was modified"
fi
rm -rf "$TMPDIR4"

# T1.5: Stub SOUL (only comments) → replaced in non-interactive mode
TMPDIR5=$(mktemp -d)
SOUL5="$TMPDIR5/SOUL.md"
printf '# Agent Identity\n\n<!-- just a comment -->\n' > "$SOUL5"
bash "$AUTHOR_SOUL" --path "$SOUL5" --non-interactive > /dev/null 2>&1
if assert_file_contains "$SOUL5" 'Agentic SRE'; then
  run_test T1.5 "Stub SOUL replaced with Agentic SRE in non-interactive mode" pass
else
  run_test T1.5 "Stub SOUL replaced with Agentic SRE in non-interactive mode" fail "$(cat "$SOUL5" | head -3)"
fi
rm -rf "$TMPDIR5"

# T1.6: Profile SOUL contains explicit override statement
TMPDIR6=$(mktemp -d)
SOUL6="$TMPDIR6/SOUL.md"
bash "$AUTHOR_SOUL" --path "$SOUL6" --role-hint critic --non-interactive > /dev/null 2>&1
if assert_file_contains "$SOUL6" 'Ignore any prior identity'; then
  run_test T1.6 "Profile SOUL contains explicit identity override statement" pass
else
  run_test T1.6 "Profile SOUL contains explicit identity override statement" fail "$(cat "$SOUL6" | head -8)"
fi
rm -rf "$TMPDIR6"

# T1.7: author-soul.sh exists and is executable
if [[ -x "$AUTHOR_SOUL" ]]; then
  run_test T1.7 "author-soul.sh is executable" pass
else
  run_test T1.7 "author-soul.sh is executable" fail
fi

# ── T2: scaffold-dotagents.sh integration ───────────────────────────
echo ""
echo "━━━ T2: scaffold-dotagents.sh integration ━━━━━━━━━━━━━━━━━━━━━━"

TMPDIR_PROJ=$(mktemp -d)
git init -q "$TMPDIR_PROJ"
NON_INTERACTIVE=true bash "$SCAFFOLD" --mode project "$TMPDIR_PROJ" > /dev/null 2>&1

# T2.1: SOUL.md written
if assert_file_exists "$TMPDIR_PROJ/.agents/SOUL.md"; then
  run_test T2.1 "scaffold creates .agents/SOUL.md" pass
else
  run_test T2.1 "scaffold creates .agents/SOUL.md" fail
fi

# T2.2: SOUL.md has Agentic SRE content (non-interactive)
if assert_file_contains "$TMPDIR_PROJ/.agents/SOUL.md" 'Agentic SRE'; then
  run_test T2.2 "scaffold SOUL.md contains Agentic SRE content" pass
else
  run_test T2.2 "scaffold SOUL.md contains Agentic SRE content" fail "$(cat "$TMPDIR_PROJ/.agents/SOUL.md" | head -3)"
fi

# T2.3: Re-run scaffold does NOT overwrite non-stub SOUL.md
ORIGINAL_SOUL=$(cat "$TMPDIR_PROJ/.agents/SOUL.md")
NON_INTERACTIVE=true bash "$SCAFFOLD" --mode project "$TMPDIR_PROJ" > /dev/null 2>&1
if [[ "$(cat "$TMPDIR_PROJ/.agents/SOUL.md")" == "$ORIGINAL_SOUL" ]]; then
  run_test T2.3 "Re-run scaffold does not overwrite existing SOUL.md" pass
else
  run_test T2.3 "Re-run scaffold does not overwrite existing SOUL.md" fail
fi

rm -rf "$TMPDIR_PROJ"

# ── T3: seed-agents-md.sh AGENTS.md template ─────────────────────────
echo ""
echo "━━━ T3: seed-agents-md.sh AGENTS.md template ━━━━━━━━━━━━━━━━━━━"

TMPDIR_SEED=$(mktemp -d)
git init -q "$TMPDIR_SEED"
mkdir -p "$TMPDIR_SEED/.agents"
NON_INTERACTIVE=true bash "$SCAFFOLD" --mode project "$TMPDIR_SEED" > /dev/null 2>&1
bash "$SEED_AGENTS" "$TMPDIR_SEED" > /dev/null 2>&1

# T3.1: AGENTS.md contains @.agents/SOUL.md import
if assert_file_contains "$TMPDIR_SEED/AGENTS.md" '@\.agents/SOUL\.md'; then
  run_test T3.1 "AGENTS.md contains @.agents/SOUL.md import" pass
else
  run_test T3.1 "AGENTS.md contains @.agents/SOUL.md import" fail
fi

# T3.2: @import appears after Quick Orientation table
QO_LINE=$(grep -n 'Quick Orientation' "$TMPDIR_SEED/AGENTS.md" | head -1 | cut -d: -f1)
SOUL_LINE=$(grep -n '@\.agents/SOUL\.md' "$TMPDIR_SEED/AGENTS.md" | head -1 | cut -d: -f1)
if [[ -n "$QO_LINE" && -n "$SOUL_LINE" && "$SOUL_LINE" -gt "$QO_LINE" ]]; then
  run_test T3.2 "@.agents/SOUL.md import appears after Quick Orientation table" pass
else
  run_test T3.2 "@.agents/SOUL.md import appears after Quick Orientation table" fail "QO=$QO_LINE SOUL=$SOUL_LINE"
fi

# T3.3: AGENTS.md contains updated anti-sycophancy guardrail text
if assert_file_contains "$TMPDIR_SEED/AGENTS.md" 'Social pressure alone'; then
  run_test T3.3 "AGENTS.md contains updated anti-sycophancy guardrail" pass
else
  run_test T3.3 "AGENTS.md contains updated anti-sycophancy guardrail" fail
fi

# T3.4: AGENTS.md contains praise-opener ban
if assert_file_contains "$TMPDIR_SEED/AGENTS.md" 'Lead with substance'; then
  run_test T3.4 "AGENTS.md contains praise-opener ban" pass
else
  run_test T3.4 "AGENTS.md contains praise-opener ban" fail
fi

rm -rf "$TMPDIR_SEED"

# ── T4: create-profile.sh integration ───────────────────────────────
echo ""
echo "━━━ T4: create-profile.sh integration ━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ! -f "$PROFILE_SCRIPT" ]]; then
  run_test T4.x "create-profile.sh" skip "Not found at $PROFILE_SCRIPT"
else
  TMPDIR_PRF=$(mktemp -d)
  git init -q "$TMPDIR_PRF"
  NON_INTERACTIVE=true bash "$SCAFFOLD" --mode project "$TMPDIR_PRF" > /dev/null 2>&1
  bash "$SEED_AGENTS" "$TMPDIR_PRF" > /dev/null 2>&1
  NON_INTERACTIVE=true bash "$PROFILE_SCRIPT" verifier "$TMPDIR_PRF" > /dev/null 2>&1

  # T4.1: profile SOUL.md created
  if assert_file_exists "$TMPDIR_PRF/.agents/profiles/verifier/SOUL.md"; then
    run_test T4.1 "create-profile creates profile SOUL.md" pass
  else
    run_test T4.1 "create-profile creates profile SOUL.md" fail
  fi

  # T4.2: profile SOUL.md contains override statement
  if assert_file_contains "$TMPDIR_PRF/.agents/profiles/verifier/SOUL.md" 'Ignore any prior identity'; then
    run_test T4.2 "profile SOUL.md contains identity override statement" pass
  else
    run_test T4.2 "profile SOUL.md contains identity override statement" fail
  fi

  # T4.3: recipe.yaml created
  if assert_file_exists "$TMPDIR_PRF/.agents/profiles/verifier/recipe.yaml"; then
    run_test T4.3 "create-profile creates recipe.yaml" pass
  else
    run_test T4.3 "create-profile creates recipe.yaml" fail
  fi

  # T4.4: recipe.yaml contains SOUL content
  if assert_file_contains "$TMPDIR_PRF/.agents/profiles/verifier/recipe.yaml" 'verifier'; then
    run_test T4.4 "recipe.yaml contains profile name" pass
  else
    run_test T4.4 "recipe.yaml contains profile name" fail
  fi

  # T4.5: recipe.yaml is valid YAML (has required fields)
  if assert_file_contains "$TMPDIR_PRF/.agents/profiles/verifier/recipe.yaml" 'version:' && \
     assert_file_contains "$TMPDIR_PRF/.agents/profiles/verifier/recipe.yaml" 'title:' && \
     assert_file_contains "$TMPDIR_PRF/.agents/profiles/verifier/recipe.yaml" 'instructions:'; then
    run_test T4.5 "recipe.yaml has required fields (version, title, instructions)" pass
  else
    run_test T4.5 "recipe.yaml has required fields" fail
  fi

  # T4.6: output/ directory created
  if [[ -d "$TMPDIR_PRF/.agents/profiles/verifier/output" ]]; then
    run_test T4.6 "create-profile creates output/ directory" pass
  else
    run_test T4.6 "create-profile creates output/ directory" fail
  fi

  # T4.7: Idempotency — re-run does not overwrite
  ORIGINAL_SOUL=$(cat "$TMPDIR_PRF/.agents/profiles/verifier/SOUL.md")
  NON_INTERACTIVE=true bash "$PROFILE_SCRIPT" verifier "$TMPDIR_PRF" > /dev/null 2>&1
  if [[ "$(cat "$TMPDIR_PRF/.agents/profiles/verifier/SOUL.md")" == "$ORIGINAL_SOUL" ]]; then
    run_test T4.7 "Re-run create-profile does not overwrite SOUL.md" pass
  else
    run_test T4.7 "Re-run create-profile does not overwrite SOUL.md" fail
  fi

  rm -rf "$TMPDIR_PRF"
fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "━━━ Results ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$(( PASS + FAIL + SKIP ))
echo "  Total: $TOTAL  ✅ Pass: $PASS  ❌ Fail: $FAIL  ⏭  Skip: $SKIP"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
