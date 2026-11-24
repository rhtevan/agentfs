#!/usr/bin/env bash
# preflight-reminder: classify a shell command. Exit 0 = read-only, 1 = mutating.
# Conservative: anything not recognised as read-only counts as mutating
# (the cost of a false "mutating" is one extra reminder; never a skipped one).
set -uo pipefail
cmd="$1"
# 1.7.0: IS_RO_DEBUG=1 names the segment that made the command mutating (stderr).
mut() { [[ -n "${IS_RO_DEBUG:-}" ]] && printf 'mutating: %s\n' "$1" >&2; exit 1; }
# 1.2.0: hide quoted text, so | ; > inside quotes are not read as operators.
cmd="${cmd//$'\\\n'/ }"   # 1.7.0: join backslash-newline line continuations
# 1.8.0: one left-to-right pass (perl), so a quote inside the other kind of
# quotes, or an escaped \" inside "..", no longer shifts the string boundaries
# (`echo "it's"; rm -rf x; echo 'y'` passed as read-only before).
# strip_sq: '..' and $'..' -> Q (literal); "..", \x kept (may hold $(..)).
# strip_dq: "..", '..' -> Q; \x kept.
strip_sq() { perl -0777 -pe 's/(\\.)|("(?:[^"\\]|\\.)*")|\$\x27(?:[^\x27\\]|\\.)*\x27|\x27[^\x27]*\x27/defined $1 ? $1 : defined $2 ? $2 : "Q"/gse'; }
strip_dq() { perl -0777 -pe 's/(\\.)|"(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27/defined $1 ? $1 : "Q"/gse'; }
# inv_of <tool>: the tool's own invocation in the ORIGINAL command (quoted
# arguments included, up to the next unquoted ; & |). A heredoc body cannot be
# delimited this way, so with << the whole command is returned (conservative).
inv_of() {
  if [[ "$cmd" == *"<<"* ]]; then printf '%s' "$cmd"; return; fi
  printf '%s' "$cmd" | grep -zoE "(^|[^[:alnum:]_.-])$1([^;&|\"'\\\\]|\\\\.|\"([^\"\\\\]|\\\\.)*\"|'[^']*')*" | tr '\0' '\n'
}
cmd_s="$(printf '%s' "$cmd" | strip_sq)"
cmd_q="$(printf '%s' "$cmd_s" | strip_dq)"
# 1.7.0: command substitutions ($(..), `..`, <(..)) run commands even inside
# double quotes or as arguments (`echo $(rm -rf x)` passed before). Each one
# becomes an extra segment; $(( )) arithmetic is not a command.
# A small scanner prints each balanced inner command (nested ones too, with
# bash's per-substitution quote context); unclosed ones run to the end.
extra="$(printf '%s' "$cmd_s" | awk 'BEGIN { RS = "\001" } {
  s = $0; n = length(s); sp = 0; dq = 0; bt = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); c2 = substr(s, i, 2); c3 = substr(s, i, 3)
    if (c == "\\") { i++; continue }
    if (c3 == "$((") { sp++; T[sp] = "a"; Q[sp] = dq; dq = 0; sp++; T[sp] = "a"; Q[sp] = 0; i += 2; continue }
    if (c2 == "$(" || (c2 == "<(" && !dq)) { sp++; T[sp] = "s"; B[sp] = i + 2; Q[sp] = dq; dq = 0; i++; continue }
    if (c == "`") { if (bt) { print substr(s, bs, i - bs); bt = 0 } else { bt = 1; bs = i + 1 } continue }
    if (c == "\"") { dq = !dq; continue }
    # 1.8.0: outside "..", a single-quoted span is literal (strip_sq keeps
    # it inside "..", where only a nested $(..) gives it meaning again).
    if (c == "\047" && !dq) { j = index(substr(s, i + 1), "\047"); if (!j) break; i += j; continue }
    if (dq) continue
    if (c == "(") { sp++; T[sp] = "p"; Q[sp] = 0; continue }
    if (c == ")" && sp > 0) { if (T[sp] == "s") print substr(s, B[sp], i - B[sp]); dq = Q[sp]; sp--; continue }
  }
  for (; sp > 0; sp--) if (T[sp] == "s") print substr(s, B[sp])
  if (bt) print substr(s, bs)
}' | strip_dq)"
all="$cmd_q"$'\n'"$extra"
# Output redirection to a file (not fd dup, not /dev/null, not /tmp) mutates.
# 1.7.0: /tmp/<path> is scratch space (analysis output); a path with ".." is not.
printf '%s' "$all" | grep -qE '>>? *(/tmp/[^[:space:];|&)]*\.\.)' && mut "redirect with .. under /tmp"
stripped="$(printf '%s' "$all" | sed -E 's/[0-9]?>&[0-9]//g; s#[0-9]?>>? */dev/null##g; s#[0-9]?>>? */tmp/[A-Za-z0-9._/-]+##g')"
printf '%s' "$stripped" | grep -qE '(^|[^<])>' && mut "redirect to a file"
# 1.7.0: the AgentFS bookkeeping exemption (Rule 6 post-write, Rule 5
# checkpoint) moved into the segment loop: a command that merely MENTIONS
# post-write.sh / checkpoint.sh (comment, heredoc, echo) no longer passes.
# 1.4.0: [[ / [ (conditionals) and seq added — read-only checks such as
# `[[ -f x ]] && echo` were held. python3, bash <script> and other
# general-purpose interpreters stay mutating on purpose (can do anything).
RO=" cat head tail less more ls ll tree find fd rg grep egrep fgrep ag wc stat file du df pwd echo printf which type command whoami id date env printenv hostname uname jq yq sort uniq cut tr awk column diff cmp sha256sum md5sum basename dirname realpath readlink test [ [[ seq true false cd read sleep ps pgrep ss lsof nproc free uptime journalctl systemctl-status readelf nm objdump "
# Split on ; && || | and newlines into segments; check each command word.
declare -A VARS=()
while IFS= read -r seg; do
  # 1.4.0: VAR=$(cmd ...) — check the substituted command, not "-f" etc.
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*(\(|\{)?[[:space:]]*//; s/^[A-Za-z_][A-Za-z0-9_]*=\$\(//; s/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//')"
  # 1.2.0: shell keywords carry no command of their own; check what follows.
  seg="$(printf '%s' "$seg" | sed -E 's/^((do|then|else|elif|if|while|until|!)([[:space:]]+|$))+//')"
  seg="$(printf '%s' "$seg" | sed -E 's/[)[:space:]]+$//')"   # 1.7.0: (cd x && ls) -> "ls"
  [[ -z "$seg" || "$seg" =~ ^[[:space:]\"\']*$ || "$seg" == \#* ]] && continue   # 1.7.0: comment lines
  # 1.6.0: a bare assignment (T=$PWD) runs no command. VAR=$(cmd) is handled
  # above (the substituted command is checked); backticks stay mutating.
  if [[ "$seg" =~ ^([A-Za-z_][A-Za-z0-9_]*)=([^[:space:]\`]*)[[:space:]]*$ && "$seg" != *'$('* ]]; then
    VARS[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"   # 1.7.0: remembered for $VAR script names
    continue
  fi
  case "${seg%% *}" in for|case|done|fi|esac|'}'|')') continue ;; esac
  w1="${seg%% *}"; rest="${seg#"$w1"}"; rest="${rest# }"
  w2="${rest%% *}"
  # 1.5.0: named AgentFS scripts verified read-only (no writes outside
  # /tmp and trace files). Named, not globbed: a future status-*.sh that
  # writes must not pass silently. Redirects and other segments are
  # still checked. A quoted path is hidden (Q) and stays mutating.
  script="$w1"; [[ "${w1##*/}" == bash || "${w1##*/}" == sh ]] && script="$w2"
  # 1.7.0: bash $P / bash ${S}/x.sh, with P / S assigned earlier in this command.
  if [[ "$script" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(.*)$ && -n "${VARS[${BASH_REMATCH[1]}]:-}" ]]; then
    script="${VARS[${BASH_REMATCH[1]}]}${BASH_REMATCH[2]}"
  fi
  script="${script##*/}"
  # 1.6.0: agentfs-eval read-only scripts (R-g 2026-11-24: a fresh-session
  # "hey eval agentfs" was held 5 times on them). update-compliance.sh only
  # with --check (that path exits before any write; other modes record).
  case "$script" in
    resolve-target.sh|pre-push-scan.sh|verify-bundle.sh|evaluate-alignment.sh|status-kgm.sh|status-fuseki.sh) continue ;;
    template-check.sh|agentfs-check.sh|agentfs-behavior.sh|runtime-compliance.sh|static-sheet-status.sh) continue ;;
    update-compliance.sh) [[ " $rest " == *" --check "* ]] && continue; mut "$seg" ;;
    post-write.sh|checkpoint.sh) continue ;;   # bookkeeping: never held (1.7.0: only when run)
  esac
  case "$w1" in
    sed) printf '%s' "$rest" | grep -qE '(^| )-[a-zA-Z]*i' && mut "$seg"; continue ;;
    # awk/sqlite3 programs sit inside quotes (hidden above): check the original
    # invocation only (1.8.0: was the whole command — a keyword elsewhere held it).
    # Output/pipe to a string target: `print > "f"`, `print | "cmd"`. awk string
    # literals become Q first, so a literal " | " or ">" is not an operator.
    awk) inv_of awk | perl -0777 -pe 's/"(?:[^"\\]|\\.)*"/Q/g' | grep -qE 'inplace|system *\(|\| *getline|(>|\|) *Q' && mut "$seg"; continue ;;
    find) printf '%s' "$rest" | grep -qE -- '-(delete|exec|execdir|ok)\b' && mut "$seg"; continue ;;
    git) # 1.2.0: git -C <path> <subcommand>
         if [[ "$w2" == -C ]]; then rest="${rest#-C }"; rest="${rest#* }"; w2="${rest%% *}"; fi
         case "$w2" in status|diff|log|show|branch|rev-parse|ls-files|ls-remote|remote|config|describe|blame|grep|shortlog|reflog|cat-file|for-each-ref|check-ignore|check-attr|ls-tree|rev-list|merge-base|name-rev|count-objects|var|"")
           [[ "$w2" == branch && "$rest" =~ (-d|-D|-m|-M|-c|-C|-f|--delete|--move|--copy|--force|--set-upstream|-u|--unset-upstream|--edit-description) ]] && mut "$seg"
           # 1.8.0: 'git branch <name>' creates a branch (a positional arg without --list).
           [[ "$w2" == branch && ! "$rest" =~ (--list|-l|--contains|--merged|--no-merged|--points-at) && " ${rest#branch} " =~ \ [^-[:space:]] ]] && mut "$seg"
           [[ "$w2" == reflog && "$rest" =~ (expire|delete) ]] && mut "$seg"
           [[ "$w2" == remote && "$rest" =~ (add|remove|rm|rename|set-url|set-head|set-branches|prune|update) ]] && mut "$seg"
           [[ "$w2" == config && ! "$rest" =~ (--get|--list|-l) ]] && mut "$seg"
           continue ;; *) mut "$seg" ;; esac ;;
    systemctl) case "$w2" in status|is-active|is-enabled|list-units|show|cat) continue ;; *) mut "$seg" ;; esac ;;
    sqlite3) inv_of sqlite3 | grep -qiE '\b(insert|update|delete|drop|create|alter|replace|attach|vacuum|reindex)\b|\.(shell|system|output|once|import|save|backup|restore|read|load)\b' && mut "$seg"; continue ;;
    # 1.8.0: query-only subcommands of otherwise-mutating tools.
    gsettings) case "$w2" in get|list-schemas|list-relocatable-schemas|list-keys|list-children|list-recursively|range|describe|writable) continue ;; *) mut "$seg" ;; esac ;;
    secret-tool) case "$w2" in lookup|search) continue ;; *) mut "$seg" ;; esac ;;
    rpm) [[ "$w2" =~ ^-(q[a-zA-Z]*|V[a-zA-Z]*)$ || "$w2" == --query || "$w2" == --verify ]] && continue; mut "$seg" ;;
  esac
  [[ "$RO" == *" $w1 "* ]] || mut "$seg"
done < <(printf '%s\n' "$all" | sed -E 's/(\&\&|\|\||;|\||`)/\n/g')
exit 0
