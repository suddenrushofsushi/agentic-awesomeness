#!/bin/sh
# Link hooks/pre-push into the .git/hooks folder of each repo you name.
#   hooks/install-pre-push.sh REPO...            show what it would do (changes nothing)
#   hooks/install-pre-push.sh --apply REPO...    make the links
#   hooks/install-pre-push.sh --remove REPO...   remove only the links that point at this hook
# It never overwrites: a repo with its own pre-push hook, or its own core.hooksPath, is skipped and reported.
# A git hook is local to this machine. It is not committed and teammates do not get it.
set -eu
HOOK="$(cd "$(dirname "$0")" && pwd)/pre-push"
MODE=""
case "${1:-}" in --apply|--remove) MODE="$1"; shift ;; esac
[ $# -gt 0 ] || { echo "usage: $0 [--apply|--remove] REPO..." >&2; exit 2; }
for REPO in "$@"; do
  COMMON="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo "SKIPPED  $REPO (not a git repo)"; continue; }
  if [ -n "$(git -C "$REPO" config --get core.hooksPath 2>/dev/null)" ]; then
    echo "SKIPPED  $REPO (core.hooksPath is set; add the hook there by hand)"; continue
  fi
  LINK="$COMMON/hooks/pre-push"
  if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$HOOK" ]; then
    if [ "$MODE" = "--remove" ]; then rm "$LINK"; echo "removed  $LINK"; else echo "ok       $LINK"; fi
  elif [ -e "$LINK" ] || [ -L "$LINK" ]; then
    echo "SKIPPED  $LINK (exists, not ours)"
  elif [ "$MODE" = "--apply" ]; then
    mkdir -p "$COMMON/hooks"; ln -s "$HOOK" "$LINK"; echo "linked   $LINK"
  elif [ "$MODE" != "--remove" ]; then
    echo "would link $LINK"
  fi
done
