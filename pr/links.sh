#!/usr/bin/env bash
# Review-guide links into the PR's own Files changed tab.
#   links.sh link <path> <from> [<to>]   prints the link with PR_N where the number goes
#   links.sh fill <pr-number>            reads the body back, fills PR_N, edits the body in place
# The anchor is diff-<sha256 of the path>; R lines are the new side. GitHub renders at most
# 300 files per diff and auto-loads 400 lines per file; past that, give the blob permalink too.
set -euo pipefail
case "${1:-}" in
  link)
    P=${2:?path}; FROM=${3:?from line}; TO=${4:-$FROM}
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    H=$(printf '%s' "$P" | shasum -a 256 | cut -c1-64)
    echo "https://github.com/$REPO/pull/PR_N/files#diff-${H}R${FROM}-R${TO}"
    ;;
  fill)
    N=${2:?pr number}; F=$(mktemp)
    gh pr view "$N" --json body -q .body | sed "s#/pull/PR_N/files#/pull/$N/files#g" > "$F"
    gh pr edit "$N" --body-file "$F" >/dev/null; rm -f "$F"
    if gh pr view "$N" --json body -q .body | grep -nE 'docs/demos|PR_N'; then
      echo "body still has a local path or PR_N" >&2; exit 1
    fi
    echo "links filled; body clean"
    ;;
  *) sed -n '2,5p' "$0"; exit 2 ;;
esac
