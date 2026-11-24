#!/bin/bash
# rm-guard — installed as ~/.local/share/goose-guard/bin/rm by
# goose-desktop-env-fix setup.sh (v1.8.0). goose-shell puts that directory
# first in PATH, so it applies to goose shell commands (and everything they
# start) only. Terminals keep /usr/bin/rm.
#
# Refuses rm when any target is "/", a protected parent below, or anything
# directly inside a protected parent. Decides on the REAL arguments, after
# the shell expanded variables and globs (e.g. `rm -rf $EMPTY/*` arrives as
# `rm -rf /afs /bin /boot ...`). All targets are checked before anything is
# deleted, so a blocked command deletes nothing. Everything else is passed
# to /usr/bin/rm unchanged.
#
# Not covered (by design, keep it simple): /usr/bin/rm called by full path,
# python shutil.rmtree, find -delete, scripts that reset PATH, deliberate
# bypasses. Recovery for those is backup (Deja Dup).

REAL_RM=/usr/bin/rm
H=$(realpath -m -- "$HOME")

# Edit this list to change what is protected (direct children included).
PROTECT_CHILDREN_OF=("/" "$H" "$H/app" "$H/app/playground" "$H/.config" "$H/.local" "$H/.local/share" \
  "$H/.ssh" "$H/.local/state" "$H/.local/share/goose")
# Only DIRECTORIES directly inside these are protected; plain files are not
# (log writers keep temp files next to ~/.agents/log.md and rm them).
PROTECT_DIR_CHILDREN_OF=("$H/.agents")

LOG="$H/.local/state/goose-guard/blocked.log"

names=() dirs=() endopts=0
for a in "$@"; do
  if [[ $endopts == 0 ]]; then
    [[ $a == -- ]] && { endopts=1; continue; }
    [[ $a == -?* ]] && continue            # option (GNU rm accepts options anywhere before --)
  fi
  [[ -z $a ]] && continue                  # rm '' fails on its own
  x=$a
  while [[ $x == */ && $x != / ]]; do x=${x%/}; done
  if [[ $x == / ]]; then names+=(""); dirs+=("/"); continue; fi
  b=${x##*/}
  if [[ $x == */* ]]; then d=${x%/*}; d=${d:-/}; else d=.; fi
  if [[ $b == . || $b == .. ]]; then
    names+=(""); dirs+=("$x")              # target is the resolved path itself
  else
    names+=("$b"); dirs+=("$d")            # resolve symlinks in the parent only
  fi
done

if (( ${#dirs[@]} )); then
  mapfile -d '' -t res < <(realpath -m -z -- "${dirs[@]}")
  for i in "${!dirs[@]}"; do
    p=${res[i]}                            # empty if realpath failed -> blocks below (fail closed)
    if [[ -z ${names[i]} ]]; then t=${p:-/}; else t=${p%/}/${names[i]}; fi
    par=${t%/*}; par=${par:-/}
    hit=""
    for prot in "${PROTECT_DIR_CHILDREN_OF[@]}"; do
      [[ $par == "$prot" && -d $t && ! -L $t ]] && hit=1
    done
    for prot in "${PROTECT_CHILDREN_OF[@]}" ${hit:+"$par"}; do
      if [[ $t == "$prot" || $par == "$prot" ]]; then
        echo "rm-guard: BLOCKED: refusing to remove protected path '$t'" >&2
        echo "rm-guard: protected: '/', and these folders plus anything directly inside them: ${PROTECT_CHILDREN_OF[*]}" >&2
        echo "rm-guard: nothing was deleted. Do not bypass this guard; remove a deeper path, or ask the user to run it in their own terminal." >&2
        mkdir -p "${LOG%/*}" 2>/dev/null &&
          printf '%s\tcwd=%s\ttarget=%s\tcmd=rm %s\n' "$(date -Is)" "$PWD" "$t" "$*" >> "$LOG" 2>/dev/null
        exit 1
      fi
    done
  done
fi

exec "$REAL_RM" "$@"
