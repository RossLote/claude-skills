#!/usr/bin/env bash
# Run several epics one after another through orchestrate-epic.sh, waiting for each PR to
# be merged before the next epic starts (so epic two branches from a base that has epic one).
#
# usage: orchestrate-run.sh <clone> <epic-id>... [--base <branch>] [--workers N] [--no-wait]
#
# Start it detached on the box so it survives the SSH session:
#   systemd-run --user --unit "orchestrate-$(date +%Y%m%d-%H%M)" --collect -p OOMPolicy=continue \
#     -p WorkingDirectory=<clone> ~/bin/orchestrate-run.sh <clone> <epic>... --base <branch>
# OOMPolicy=continue: with the default (stop), the kernel killing one test process stopped the
# whole unit, driver and every Claude call with it. Now that test fails instead.
# Follow it with: journalctl --user -u orchestrate-<stamp> -f, or tail ~/orchestrate-runs/<epic>/driver.log
set -euo pipefail
# shellcheck source=/dev/null
[ -f ~/.orchestrator.env ] && . ~/.orchestrator.env
HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)   # follows the ~/bin symlink
CLONE=${1:?usage: orchestrate-run.sh <clone> <epic-id>... [--base <branch>] [--workers N] [--no-wait]}; shift
BASE=main; WORKERS=3; WAIT=1; EPICS=()
while (($#)); do
  case $1 in
    --base) BASE=$2; shift 2;;
    --workers) WORKERS=$2; shift 2;;
    --no-wait) WAIT=; shift;;
    *) EPICS+=("$1"); shift;;
  esac
done
RUNS=${ORCH_RUNS:-$HOME/orchestrate-runs}
for i in "${!EPICS[@]}"; do
  EPIC=${EPICS[$i]}
  echo "$(date +%H:%M:%S) epic $EPIC base=$BASE workers=$WORKERS"
  if ! "$HERE/orchestrate-epic.sh" "$EPIC" --base "$BASE" --workers "$WORKERS" --clone "$CLONE"; then
    echo "$(date +%H:%M:%S) $EPIC stopped; see $RUNS/$EPIC/driver.log$( [ -f "$RUNS/$EPIC/blocked" ] && echo " and $(cat "$RUNS/$EPIC/blocked")")"; exit 1
  fi
  URL=$(cat "$RUNS/$EPIC/pr.url")
  echo "$(date +%H:%M:%S) $EPIC PR up: $URL"
  # The wait is there so the next epic branches from a base that has this one; after the last
  # epic there is nothing to wait for, and the unit sat polling the PR.
  [ -n "$WAIT" ] && [ $((i + 1)) -lt ${#EPICS[@]} ] || continue
  echo "$(date +%H:%M:%S) waiting for $URL to be merged (checking every 5 minutes)"
  until [ "$(cd "$CLONE" && gh pr view "$URL" --json state --jq .state)" = MERGED ]; do
    [ "$(cd "$CLONE" && gh pr view "$URL" --json state --jq .state)" = CLOSED ] && { echo "$URL was closed without merging; stopping"; exit 1; }
    sleep 300
  done
  echo "$(date +%H:%M:%S) $EPIC merged"
done
echo "$(date +%H:%M:%S) all epics done"
