#!/usr/bin/env bash
# preflight-reminder: classify a shell command. Exit 0 = read-only, 1 = mutating.
# Conservative: anything not recognised as read-only counts as mutating
# (the cost of a false "mutating" is one extra reminder; never a skipped one).
set -uo pipefail
cmd="$1"
# 1.2.0: hide quoted text, so | ; > inside quotes are not read as operators.
cmd_q="$(printf '%s' "$cmd" | sed -E "s/'[^']*'/Q/g; s/\"[^\"]*\"/Q/g")"
# Output redirection to a file (not fd dup, not /dev/null) mutates.
stripped="$(printf '%s' "$cmd_q" | sed -E 's/[0-9]?>&[0-9]//g; s#[0-9]?>>? */dev/null##g')"
printf '%s' "$stripped" | grep -qE '(^|[^<])>' && exit 1
# Exempt AgentFS bookkeeping (Rule 6 post-write, Rule 5 checkpoint).
printf '%s' "$cmd" | grep -qE '(post-write|checkpoint)\.sh' && exit 0
# 1.4.0: [[ / [ (conditionals) and seq added — read-only checks such as
# `[[ -f x ]] && echo` were held. python3, bash <script> and other
# general-purpose interpreters stay mutating on purpose (can do anything).
RO=" cat head tail less more ls ll tree find fd rg grep egrep fgrep ag wc stat file du df pwd echo printf which type command whoami id date env printenv hostname uname jq yq sort uniq cut tr awk column diff cmp sha256sum md5sum basename dirname realpath readlink test [ [[ seq true false cd read sleep ps pgrep ss lsof nproc free uptime journalctl systemctl-status "
# Split on ; && || | and newlines into segments; check each command word.
while IFS= read -r seg; do
  # 1.4.0: VAR=$(cmd ...) — check the substituted command, not "-f" etc.
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*(\(|\{)?[[:space:]]*//; s/^[A-Za-z_][A-Za-z0-9_]*=\$\(//; s/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//')"
  # 1.2.0: shell keywords carry no command of their own; check what follows.
  seg="$(printf '%s' "$seg" | sed -E 's/^((do|then|else|elif|if|while|until|!)([[:space:]]+|$))+//')"
  [[ -z "$seg" ]] && continue
  # 1.6.0: a bare assignment (T=$PWD) runs no command. VAR=$(cmd) is handled
  # above (the substituted command is checked); backticks stay mutating.
  [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]\`]*[[:space:]]*$ && "$seg" != *'$('* ]] && continue
  case "${seg%% *}" in for|case|done|fi|esac|'}'|')') continue ;; esac
  w1="${seg%% *}"; rest="${seg#"$w1"}"; rest="${rest# }"
  w2="${rest%% *}"
  # 1.5.0: named AgentFS scripts verified read-only (no writes outside
  # /tmp and trace files). Named, not globbed: a future status-*.sh that
  # writes must not pass silently. Redirects and other segments are
  # still checked. A quoted path is hidden (Q) and stays mutating.
  script="${w1##*/}"; [[ "$script" == bash || "$script" == sh ]] && script="${w2##*/}"
  # 1.6.0: agentfs-eval read-only scripts (R-g 2026-11-24: a fresh-session
  # "hey eval agentfs" was held 5 times on them). update-compliance.sh only
  # with --check (that path exits before any write; other modes record).
  case "$script" in
    resolve-target.sh|pre-push-scan.sh|verify-bundle.sh|evaluate-alignment.sh|status-kgm.sh|status-fuseki.sh) continue ;;
    template-check.sh|agentfs-check.sh|agentfs-behavior.sh|runtime-compliance.sh|static-sheet-status.sh) continue ;;
    update-compliance.sh) [[ " $rest " == *" --check "* ]] && continue; exit 1 ;;
  esac
  case "$w1" in
    sed) printf '%s' "$rest" | grep -qE '(^| )-[a-zA-Z]*i' && exit 1; continue ;;
    # awk/sqlite3 programs sit inside quotes (hidden above): check the original.
    awk) printf '%s' "$cmd" | grep -qE 'inplace|system\(' && exit 1; continue ;;
    find) printf '%s' "$rest" | grep -qE -- '-(delete|exec|execdir|ok)\b' && exit 1; continue ;;
    git) # 1.2.0: git -C <path> <subcommand>
         if [[ "$w2" == -C ]]; then rest="${rest#-C }"; rest="${rest#* }"; w2="${rest%% *}"; fi
         case "$w2" in status|diff|log|show|branch|rev-parse|ls-files|ls-remote|remote|config|describe|blame|grep|shortlog|reflog|cat-file|for-each-ref|"")
           [[ "$w2" == branch && "$rest" =~ (-d|-D|-m|-M|--delete) ]] && exit 1
           [[ "$w2" == remote && "$rest" =~ (add|remove|rm|rename|set-url) ]] && exit 1
           [[ "$w2" == config && ! "$rest" =~ (--get|--list|-l) ]] && exit 1
           continue ;; *) exit 1 ;; esac ;;
    systemctl) case "$w2" in status|is-active|is-enabled|list-units|show|cat) continue ;; *) exit 1 ;; esac ;;
    sqlite3) printf '%s' "$cmd" | grep -qiE '\b(insert|update|delete|drop|create|alter|replace)\b' && exit 1; continue ;;
  esac
  [[ "$RO" == *" $w1 "* ]] || exit 1
done < <(printf '%s\n' "$cmd_q" | sed -E 's/(\&\&|\|\||;|\|)/\n/g')
exit 0
