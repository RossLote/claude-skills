#!/usr/bin/env bash
# Files and lines per bucket for the PR's diff map, then the test lines worth reading.
# usage: buckets.sh <base>   (from the repo root; later rules win, adapt the patterns to the repo)
set -euo pipefail
BASE=${1:?base branch}
git diff --numstat "origin/$BASE...HEAD" | awk '
  { f=$3; b="product" }
  f ~ /\.(test|spec)\.[cm]?[jt]sx?$/ || f ~ /(^|\/)(__tests__|e2e|tests?)\//   { b="tests" }
  f ~ /(^|\/)docs\// || f ~ /\.mdx?$/                                         { b="docs" }
  f ~ /\.(png|jpe?g|gif|webp|svg|mp4|webm)$/                                  { b="pictures" }
  f ~ /(^|\/)(\.github|\.railway|docker)\// || f ~ /(^|\/)(Dockerfile.*|\.env\.example|package\.json)$/ { b="config" }
  f ~ /(^|\/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$/ || f ~ /\/generated\//        { b="generated" }
  f ~ /(^|\/)\.beads\//                                                         { b="tracker" }
  f ~ /migrations\//                                                            { b="migrations" }
  { n[b]++; a[b]+=($1=="-"?0:$1); d[b]+=($2=="-"?0:$2) }
  END { for (b in n) printf "%-11s %4d files  +%-6d -%d\n", b, n[b], a[b], d[b] }' | sort -k3 -t+ -rn
echo
echo "# test lines to read: added .skip/.only, removed expect()"
git diff "origin/$BASE...HEAD" -- '*.test.*' '*.spec.*' | grep -nE '^\+.*\.(skip|only)\(|^-.*expect\(' || echo "(none)"
