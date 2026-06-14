#!/usr/bin/env bash
#
# sync-claude-memory.sh — move Claude Code auto-memory between this repo and the
# live home-directory location Claude actually reads from.
#
# WHY: Claude Code stores per-project memory under
#   ~/.claude/projects/<path-slug>/memory/
# where <path-slug> is this repo's absolute path with every "/" replaced by "-".
# That directory lives OUTSIDE the repo, so `git pull` alone does not restore it.
# We keep a version-controlled copy in `.claude/memory/` and sync it with a script.
#
# USAGE:
#   scripts/sync-claude-memory.sh restore   # repo  -> live   (run once on a new machine)
#   scripts/sync-claude-memory.sh backup    # live  -> repo   (run before committing memory changes)
#   scripts/sync-claude-memory.sh status    # show what differs
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_MEM="$REPO_ROOT/.claude/memory"

# Claude derives the slug from the absolute repo path: "/" -> "-".
SLUG="$(printf '%s' "$REPO_ROOT" | sed 's#/#-#g')"
LIVE_MEM="$HOME/.claude/projects/$SLUG/memory"

cmd="${1:-status}"

case "$cmd" in
  restore)
    mkdir -p "$LIVE_MEM"
    rsync -av --delete "$REPO_MEM/" "$LIVE_MEM/"
    echo "Restored repo memory -> $LIVE_MEM"
    ;;
  backup)
    mkdir -p "$REPO_MEM"
    rsync -av --delete "$LIVE_MEM/" "$REPO_MEM/"
    echo "Backed up live memory -> $REPO_MEM (now: git add .claude/memory && commit)"
    ;;
  status)
    echo "Repo memory:  $REPO_MEM"
    echo "Live memory:  $LIVE_MEM"
    echo
    if [ -d "$LIVE_MEM" ]; then
      diff -rq "$REPO_MEM" "$LIVE_MEM" || true
    else
      echo "(live memory dir does not exist yet — run: $0 restore)"
    fi
    ;;
  *)
    echo "usage: $0 {restore|backup|status}" >&2
    exit 1
    ;;
esac
