#!/usr/bin/env bash
# install.sh — Install Hermes Agent via the upstream installer, non-interactively,
# preserving any existing ~/.hermes data.
# Usage: bash install.sh [--dry-run] [--no-desktop] [--channel stable|main]
#                        [--installer FILE] [--sha256 HEX]
# Exit: 0 ok/converged · 1 failure · 2 usage · 3 privilege gate (missing system package)
set -uo pipefail

# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "hermes-install" "1.2.0" 2>/dev/null || true

INSTALLER_URL="https://hermes-agent.nousresearch.com/install.sh"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
INSTALL_DIR="${HERMES_INSTALL_DIR:-$HERMES_HOME/hermes-agent}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false
DESKTOP=true
CHANNEL="stable"
INSTALLER=""
PIN_SHA=""
COMP_FILE="${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions/hermes"
COMP_MARK="# hermes — managed by hermes-install"

# Bash completion: a lazy loader that bash-completion sources on the first
# <Tab> after `hermes`. It evals `hermes completion bash` at that moment, so it
# always matches the installed version (no stale snapshot after `hermes update`)
# and costs nothing at shell startup (vs ~0.6s for eval in ~/.bashrc).
# Loader content. Upstream `hermes completion bash` (v0.23.3) lists options only
# for leaf subcommands — `hermes -<Tab>`, `hermes config -<Tab>` and
# `hermes config set --<Tab>` return nothing. The wrapper keeps upstream's
# completion and, when it is empty for a `-` word, falls back to the options in
# `hermes <path> --help` (cached per path for the shell session).
comp_content() {
  cat <<'LOADER'
# hermes — managed by hermes-install v1.2.0 r2 (loaded by bash-completion on first <Tab>; always matches the installed version)
eval "$(command hermes completion bash 2>/dev/null)"
declare -gA _hermes_optcache
_hermes_opts_for() {  # $@ = subcommand path; sets _hermes_opts (no subshell, so the cache persists)
  local key="${*:-.}"
  if [[ -z "${_hermes_optcache[$key]+x}" ]]; then
    _hermes_optcache[$key]="$(command hermes "$@" --help 2>/dev/null \
      | awk '/^(options|optional arguments):/{f=1;next} /^[^ ]/{f=0} f && /^  +-/' \
      | sed -E 's/^ +//; s/  .*//' | grep -oE '(^|, )--?[A-Za-z0-9][A-Za-z0-9_-]*' \
      | sed 's/^, //' | sort -u | tr '\n' ' ')"
  fi
  _hermes_opts="${_hermes_optcache[$key]}"
}
_hermes_completion_wrap() {
  declare -F _hermes_completion >/dev/null && _hermes_completion
  local cur="${COMP_WORDS[COMP_CWORD]}" path=() i opts
  [[ ${#COMPREPLY[@]} -eq 0 && "$cur" == -* ]] || return 0
  for ((i = 1; i < COMP_CWORD; i++)); do
    [[ "${COMP_WORDS[i]}" == -* ]] && break
    path+=("${COMP_WORDS[i]}")
  done
  # Drop trailing positional args (e.g. `config set KEY`) until --help parses.
  while :; do
    _hermes_opts_for "${path[@]}"; opts="$_hermes_opts"
    [[ -n "$opts" || ${#path[@]} -eq 0 ]] && break
    unset 'path[${#path[@]}-1]'
  done
  COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}
complete -F _hermes_completion_wrap hermes
LOADER
}
comp_state() {  # prints ok | stale | missing | foreign
  if [[ ! -f "$COMP_FILE" ]]; then echo missing
  elif ! grep -qF "$COMP_MARK" "$COMP_FILE"; then echo foreign
  elif [[ "$(cat "$COMP_FILE")" == "$(comp_content)" ]]; then echo ok
  else echo stale; fi
}
install_completion() {
  case "$(comp_state)" in
    ok) echo "  ✅ Bash completion: $COMP_FILE (present)" ;;
    foreign) echo "  ⚠️  Bash completion: $COMP_FILE exists and is not managed by hermes-install — left untouched" ;;
    missing|stale)
      local what; what="$( [[ "$(comp_state)" == stale ]] && echo updated || echo wrote )"
      if mkdir -p "$(dirname "$COMP_FILE")" && comp_content > "$COMP_FILE"; then
        echo "  ✅ Bash completion: $what $COMP_FILE (new shells: hermes <Tab>)"
      else
        echo "  ⚠️  Bash completion: could not write $COMP_FILE (non-fatal)"
      fi ;;
  esac
}

usage() { sed -n '4,5p' "$0" | sed 's/^# //'; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-desktop) DESKTOP=false; shift ;;
    --channel) [[ $# -ge 2 ]] || { usage; exit 2; }; CHANNEL="$2"; shift 2 ;;
    --installer) [[ $# -ge 2 ]] || { usage; exit 2; }; INSTALLER="$2"; shift 2 ;;
    --sha256) [[ $# -ge 2 ]] || { usage; exit 2; }; PIN_SHA="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown option: $1"; usage; exit 2 ;;
  esac
done
case "$CHANNEL" in stable|main) ;; *) echo "❌ --channel must be stable or main"; exit 2 ;; esac
[[ -z "$INSTALLER" || -f "$INSTALLER" ]] || { echo "❌ --installer file not found: $INSTALLER"; exit 2; }

echo "=== Hermes Agent — INSTALL$([[ $DRY_RUN == true ]] && echo ' (dry-run)') ==="

# ── Step 1: System prerequisites (privilege gate) ─────────────
# The upstream installer only asks sudo for libatomic in interactive mode;
# under --non-interactive Node.js would fail later, so gate it up front.
PKGS=()
command -v git >/dev/null 2>&1 || PKGS+=(git)
command -v curl >/dev/null 2>&1 || PKGS+=(curl)
{ ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null; } | grep -q 'libatomic\.so\.1' || PKGS+=(libatomic)
if [[ ${#PKGS[@]} -gt 0 ]]; then
  echo "🔒 Privilege gate: missing system packages: ${PKGS[*]}"
  echo "   Run manually:"
  echo "     sudo dnf install -y ${PKGS[*]}"
  trace_step 1 "prereqs" 3 "missing=${PKGS[*]}" 2>/dev/null || true
  trace_end 2>/dev/null || true
  exit 3
fi
echo "  ✅ Prerequisites: git, curl, libatomic"
trace_step 1 "prereqs" 0 "" 2>/dev/null || true

# ── Step 2: Current state ─────────────────────────────────────
HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
[[ -z "$HERMES_BIN" && -x "$HOME/.local/bin/hermes" ]] && HERMES_BIN="$HOME/.local/bin/hermes"
HAVE_CMD=false; HAVE_CHECKOUT=false; HAVE_CONFIG=false; HAVE_DESKTOP=false
[[ -n "$HERMES_BIN" ]] && "$HERMES_BIN" --version >/dev/null 2>&1 && HAVE_CMD=true
git -C "$INSTALL_DIR" rev-parse --verify HEAD >/dev/null 2>&1 && HAVE_CHECKOUT=true
[[ -f "$HERMES_HOME/config.yaml" ]] && HAVE_CONFIG=true
compgen -G "$INSTALL_DIR/apps/desktop/release/*" >/dev/null 2>&1 && HAVE_DESKTOP=true
echo "  Command: $HAVE_CMD · Checkout: $HAVE_CHECKOUT · Config: $HAVE_CONFIG · Desktop: $HAVE_DESKTOP (wanted: $DESKTOP)"

CONVERGED=false
if $HAVE_CMD && $HAVE_CHECKOUT && $HAVE_CONFIG && { [[ $DESKTOP == false ]] || $HAVE_DESKTOP; }; then
  CONVERGED=true
fi

# Existing top-level entries in HERMES_HOME — must all survive the install.
DATA=()
if [[ -d "$HERMES_HOME" ]]; then
  while IFS= read -r e; do DATA+=("$e"); done < <(ls -A "$HERMES_HOME")
fi
echo "  Existing $HERMES_HOME entries to preserve: ${#DATA[@]}"
trace_step 2 "state" 0 "converged=${CONVERGED} entries=${#DATA[@]}" 2>/dev/null || true

ARGS=(--non-interactive --channel "$CHANNEL")
[[ $DESKTOP == true ]] && ARGS+=(--include-desktop)

if [[ $DRY_RUN == true ]]; then
  echo
  if $CONVERGED && [[ "$(comp_state)" =~ ^(ok|foreign)$ ]]; then
    echo "  Already installed — nothing to do (upgrades go through 'hermes update')."
    [[ "$(comp_state)" == foreign ]] && echo "  ⚠️  $COMP_FILE is not managed by hermes-install — would be left untouched"
    echo "DRY_RUN_RESULT=CONVERGED"
  elif $CONVERGED; then
    echo "  Already installed (upgrades go through 'hermes update')."
    echo "  Would $( [[ "$(comp_state)" == stale ]] && echo update || echo write ): $COMP_FILE (bash completion lazy loader)"
    echo "DRY_RUN_RESULT=PENDING"
  else
    echo "  Would run: bash <upstream install.sh> ${ARGS[*]}"
    echo "    source:  ${INSTALLER:-$INSTALLER_URL}"
    echo "    creates: $INSTALL_DIR (git checkout), hermes command in ~/.local/bin"
    $HAVE_CONFIG || echo "    creates: $HERMES_HOME/config.yaml from cli-config.yaml.example (only because it is missing)"
    echo "    skips:   setup wizard + gateway service (--non-interactive)"
    [[ "$(comp_state)" =~ ^(missing|stale)$ ]] && echo "    writes:  $COMP_FILE (bash completion lazy loader)"
    echo "DRY_RUN_RESULT=PENDING"
  fi
  trace_end 2>/dev/null || true
  exit 0
fi

if $CONVERGED; then
  echo "✅ Hermes Agent already installed — not touched (upgrade with 'hermes update')"
  install_completion
  trace_step 6 "completion" 0 "$(comp_state)" 2>/dev/null || true
  trace_end 2>/dev/null || true
  exit 0
fi

# ── Step 3: Fetch + checksum the upstream installer ───────────
TMP=""
if [[ -z "$INSTALLER" ]]; then
  TMP="$(mktemp -d)"
  INSTALLER="$TMP/install.sh"
  if ! curl -fsSL "$INSTALLER_URL" -o "$INSTALLER"; then
    echo "❌ Download failed: $INSTALLER_URL — nothing changed"
    rm -rf "$TMP"; trace_step 3 "fetch" 1 "" 2>/dev/null || true; trace_end 2>/dev/null || true
    exit 1
  fi
fi
SHA="$(sha256sum "$INSTALLER" | cut -d' ' -f1)"
echo "  Installer sha256: $SHA"
if [[ -n "$PIN_SHA" && "$SHA" != "$PIN_SHA" ]]; then
  echo "❌ Installer checksum mismatch (expected $PIN_SHA) — nothing changed"
  [[ -n "$TMP" ]] && rm -rf "$TMP"
  trace_step 3 "fetch" 1 "sha_mismatch" 2>/dev/null || true; trace_end 2>/dev/null || true
  exit 1
fi
trace_step 3 "fetch" 0 "sha256=${SHA}" 2>/dev/null || true

# ── Step 4: Run the upstream installer ────────────────────────
echo "  → bash install.sh ${ARGS[*]}  (log: $HERMES_HOME/logs/install.log)"
RC=0
bash "$INSTALLER" "${ARGS[@]}" </dev/null || RC=$?
[[ -n "$TMP" ]] && rm -rf "$TMP"
trace_step 4 "upstream_install" "$RC" "" 2>/dev/null || true

# ── Step 5: Verify existing data survived ─────────────────────
LOST=()
for e in "${DATA[@]}"; do [[ -e "$HERMES_HOME/$e" ]] || LOST+=("$e"); done
if [[ ${#LOST[@]} -gt 0 ]]; then
  echo "❌ DATA CHECK FAILED — missing after install: ${LOST[*]}"
  trace_step 5 "data_check" 1 "lost=${LOST[*]}" 2>/dev/null || true; trace_end 2>/dev/null || true
  exit 1
fi
echo "  ✅ All ${#DATA[@]} pre-existing $HERMES_HOME entries preserved"
trace_step 5 "data_check" 0 "" 2>/dev/null || true

if [[ $RC -ne 0 ]]; then
  echo "❌ Upstream installer failed (exit $RC) — see $HERMES_HOME/logs/install.log; re-run is safe (it repairs)"
  trace_end 2>/dev/null || true
  exit 1
fi

# ── Step 6: Bash completion ───────────────────────────────────
install_completion
trace_step 6 "completion" 0 "$(comp_state)" 2>/dev/null || true

# ── Step 7: Final status ──────────────────────────────────────
echo
bash "$SCRIPT_DIR/status.sh"
ST=$?
trace_step 7 "status" "$ST" "" 2>/dev/null || true
trace_end 2>/dev/null || true
[[ $ST -eq 0 ]] && exit 0 || exit 1
