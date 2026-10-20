#!/usr/bin/env bash
# Fallback chapters when the demo folder has no chapters.json: each step picture's mtime
# minus the original .webm's start (its mtime minus its duration). Approximate; say so.
# usage: chapters.sh <demo-dir> [<path to the .webm Playwright wrote, default: newest under test-results>]
set -euo pipefail
DEMO=${1:?demo dir}
V=${2:-$(ls -t test-results/*/video.webm 2>/dev/null | head -1)}
[ -n "$V" ] || { echo "no .webm found; list the steps without times" >&2; exit 1; }
if stat -f %m "$V" >/dev/null 2>&1; then MT='stat -f %m'; else MT='stat -c %Y'; fi
END=$($MT "$V"); DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$V")
START=$(printf '%.0f' "$(echo "$END - $DUR" | bc)")
for f in "$DEMO"/[0-9]*.png; do
  t=$(( $($MT "$f") - START )); [ "$t" -lt 0 ] && t=0
  printf '%d:%02d  %s\n' $((t/60)) $((t%60)) "$(basename "$f" .png)"
done
echo "(approximate: from picture times against the recording's end; round each down a second)"
