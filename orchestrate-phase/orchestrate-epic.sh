#!/usr/bin/env bash
# Run one beads epic headless as a chain of Claude calls to /orchestrate-phase.
#
# usage: orchestrate-epic.sh <epic-id> [--base <branch>] [--workers N] [--clone <path>]
#                            [--stop-after setup|build|integrate|prove|pr] [--dry-run]
#
# The script owns the loop; Claude owns each step. State lives in beads, git and GitHub,
# so a rerun after a crash continues from whatever it finds. Logs and every call's JSON go
# to $ORCH_RUNS/<epic>/ (default ~/orchestrate-runs). Exit 0: PR up and CI green, or no
# workflows to watch (the PR link is the last line and in <run-dir>/pr.url). Exit 2: blocked
# on the user; the question is printed. Exit 1: a phase failed; see the log. Exit 143 or 130:
# stopped by SIGTERM (systemctl stop, an OOM stop of the unit) or SIGINT.
#
# env: ORCH_CLAUDE_FLAGS adds flags to every claude call; ORCH_POLL is the seconds
# between checks on running beads (30); ORCH_WORKTREE_SETUP is run in every new worktree
# (default: `make worktree-setup` when the Makefile has that target, else nothing);
# ORCH_WORKTREE_TEARDOWN is run in a worktree before the driver removes it (default:
# `make worktree-teardown` when the Makefile has that target, else nothing), to stop the
# Docker project and host servers a gate left running there;
# ORCH_HEARTBEAT is the seconds between the driver.log lines that name a running call's
# latest tool step (600; 0 turns them off); ORCH_NOTES is a file of standing notes for this
# repo on this machine (known flakes, gate advice) appended to every call's system prompt;
# ORCH_FAST_GATE is run on the epic branch after a merge that lands on top of another
# bead's merge (default: `make check` when the Makefile has it, else the merge is ungated);
# ORCH_CI=skip ends the run without the CI watch, which the driver also skips on its own when
# the epic branch has no .github/workflows (the CI record line says which);
# ORCH_REQUIRED_ENV is a comma-separated list of key names that must have a non-empty value in
# <clone>/.env, checked in preflight (names only are ever printed, never a value).
# The run directory also gets `exit` (the driver's exit code, which systemd otherwise
# loses), `ci.counts` (CI watch counts carried across restarts) and one log per gate.
set -euo pipefail
# shellcheck source=/dev/null
[ -f ~/.orchestrator.env ] && . ~/.orchestrator.env
export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-0}

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)   # follows the ~/bin symlink
EPIC=${1:?usage: orchestrate-epic.sh <epic-id> [--base <branch>] [--workers N] [--clone <path>]}; shift
BASE=main; WORKERS=3; CLONE=; STOP_AFTER=; DRY=
while (($#)); do
  case $1 in
    --base) BASE=$2; shift 2;;
    --workers) WORKERS=$2; shift 2;;
    --clone) CLONE=$2; shift 2;;
    --stop-after) STOP_AFTER=$2; shift 2;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown argument $1" >&2; exit 64;;
  esac
done
CLONE=$(cd "${CLONE:-$(git rev-parse --show-toplevel)}" && pwd)
REPO=$(basename "$CLONE"); PARENT=$(dirname "$CLONE")
EPIC_WT=$PARENT/$REPO-$EPIC
RUN_DIR=${ORCH_RUNS:-$HOME/orchestrate-runs}/$EPIC; CALLS=$RUN_DIR/calls; TIMES=$RUN_DIR/times
POLL=${ORCH_POLL:-30}
SCHEMA=$(cat "$HERE/phase.schema.json")
mkdir -p "$CALLS"

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "FAILED: $*"; exit 1; }
blocked() { log "Blocked on you: $*"; echo "Blocked on you: $*" > "$RUN_DIR/blocked"; exit 2; }
bdc() { (cd "$CLONE" && bd "$@"); }
mark() { grep -q "^$1=" "$TIMES" 2>/dev/null || echo "$1=$(date +%H:%M)" >> "$TIMES"; }
t() { grep "^$1=" "$TIMES" 2>/dev/null | cut -d= -f2; }
suffix() { local s=${1#"$EPIC".}; echo "${s//./-}"; }                 # crm-x.4.1 → 4-1
bead_wt() { echo "$PARENT/$REPO-$EPIC-$(suffix "$1")"; }
bead_branch() { echo "$EPIC/$(suffix "$1")"; }
field() { jq -r ".structured_output.$2 // empty" "$1" 2>/dev/null; }
# A fresh worktree has no gitignored env files and no generated client.
prepare_wt() {
  local wt=$1 cmd=${ORCH_WORKTREE_SETUP:-}
  [ -z "$cmd" ] && make -C "$wt" -n worktree-setup > /dev/null 2>&1 && cmd="make worktree-setup"
  [ -z "$cmd" ] && return 0
  if (cd "$wt" && eval "$cmd") > "$RUN_DIR/setup-${wt##*/}.log" 2>&1; then log "prepared $wt ($cmd)"
  else log "WARNING: '$cmd' failed in $wt; see $RUN_DIR/setup-${wt##*/}.log"; fi
}
# The mirror of prepare_wt, run before every worktree removal. A gate's Docker project outlived
# its worktree, and its host dev servers wrote generated files back into the removed folder
# until the unit ended (six stacks reaped by hand on a box that had already been OOM-killed
# once).
teardown_wt() {
  local wt=$1 cmd=${ORCH_WORKTREE_TEARDOWN:-}
  [ -d "$wt" ] || return 0
  [ -z "$cmd" ] && make -C "$wt" -n worktree-teardown > /dev/null 2>&1 && cmd="make worktree-teardown"
  [ -z "$cmd" ] && return 0
  if (cd "$wt" && eval "$cmd") > "$RUN_DIR/teardown-${wt##*/}.log" 2>&1; then log "tore down $wt ($cmd)"
  else log "WARNING: '$cmd' failed in $wt; see $RUN_DIR/teardown-${wt##*/}.log"; fi
}
# The keys of ORCH_REQUIRED_ENV that <file> lacks or leaves empty (KEY=, KEY="", KEY= # note),
# space-separated. The last assignment of a key wins, as in dotenv. Never prints a value.
missing_env() {
  awk -v keys="$1" '
    { sub(/\r$/, "") }
    /^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ {
      line = $0; sub(/^[[:space:]]*(export[[:space:]]+)?/, "", line)
      i = index(line, "="); name = substr(line, 1, i - 1); gsub(/[[:space:]]/, "", name)
      v = substr(line, i + 1); sub(/^[[:space:]]+/, "", v)
      if (v ~ /^"/) { v = substr(v, 2); sub(/".*$/, "", v) }
      else if (v ~ /^\047/) { v = substr(v, 2); sub(/\047.*$/, "", v) }
      else { sub(/^#.*$/, "", v); sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v) }
      set[name] = (v != "")
    }
    END {
      n = split(keys, k, ",")
      for (i = 1; i <= n; i++) { key = k[i]; gsub(/[[:space:]]/, "", key); if (key != "" && !set[key]) out = out (out == "" ? "" : " ") key }
      print out
    }' "$2"
}
open_children() { bdc list --all --parent "$EPIC" --flat --json | jq -r '.[] | select(.status != "closed") | .id'; }

# The latest tool step in a transcript: "Bash Run the full gate", "Agent <epic>.3 …".
tool_step() {
  tail -n 400 "$1" 2>/dev/null | jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use")
    | "\(.name) \((.input.description // .input.command // .input.file_path // .input.pattern // .input.prompt // "") | tostring | gsub("\\s+"; " ") | .[0:100])"' 2>/dev/null | tail -1
}
# A call's latest step, and its newest subagent's (a worker runs inside one Agent step for
# its whole life). The session id is the driver's, so parallel calls from one clone never mix.
last_step() {
  local f sub
  f=$(ls -t ~/.claude*/projects/*/"$1".jsonl 2>/dev/null | head -1) || true
  [ -z "$f" ] && { echo "no transcript yet"; return; }
  sub=$(ls -t "${f%.jsonl}"/subagents/*.jsonl 2>/dev/null | head -1) || true
  echo "$(tool_step "$f")${sub:+ | worker: $(tool_step "$sub")}"
}
# A driver.log line every ORCH_HEARTBEAT seconds while a call runs: integrate ran 1 h 44 min
# with the log saying only "call integrate", and from outside the run looked dead.
heartbeat() { # heartbeat <pid> <label> <session-id>
  local pid=$1 label=$2 sid=$3 every=${ORCH_HEARTBEAT:-600} start next
  [ "$every" -gt 0 ] 2>/dev/null || return 0
  start=$(date +%s); next=$((start + every))
  while kill -0 "$pid" 2>/dev/null; do
    sleep 15
    [ "$(date +%s)" -ge "$next" ] && kill -0 "$pid" 2>/dev/null || continue
    log "  … $label, $(( ($(date +%s) - start) / 60 )) min: $(last_step "$sid")"
    next=$((next + every))
  done
}

# call <phase> <arg> <out.json> [<extra add-dir>] — one headless Claude call
call() {
  local phase=$1 arg=$2 out=$3 extra=${4:-} sid pid hb
  local prompt="/orchestrate-phase $EPIC $phase $arg --base $BASE"
  sid=$(python3 -c 'import uuid; print(uuid.uuid4())')
  local flags=(--output-format json --json-schema "$SCHEMA" --add-dir "$EPIC_WT" --session-id "$sid")
  [ -n "$extra" ] && flags+=(--add-dir "$extra")
  # Standing notes for this repo on this box, so a worker meeting a known flake does not spend
  # minutes proving it pre-existing.
  [ -n "${ORCH_NOTES:-}" ] && [ -r "$ORCH_NOTES" ] && flags+=(--append-system-prompt "$(cat "$ORCH_NOTES")")
  log "call $phase $arg → ${out##*/} (session $sid)"
  # shellcheck disable=SC2086
  (cd "$CLONE" && claude -p "$prompt" "${flags[@]}" ${ORCH_CLAUDE_FLAGS:-} > "$out" 2> "$out.err") &
  pid=$!
  # stdout to /dev/null: the caller reads call's stdout through $(…), which would wait for the
  # heartbeat's last sleep to let go of it.
  heartbeat "$pid" "$phase${arg:+ $arg}" "$sid" > /dev/null & hb=$!
  wait "$pid" || true
  kill "$hb" 2>/dev/null || true
  local status; status=$(field "$out" status)
  [ -z "$status" ] && { status=failed; log "no structured result: $(jq -r '.result // empty' "$out" 2>/dev/null | head -c 300) $(head -c 300 "$out.err")"; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$phase" "$arg" "$status" "$(jq -r '.total_cost_usd // 0' "$out" 2>/dev/null)" "$(jq -r '.num_turns // 0' "$out" 2>/dev/null)" "${out##*/}" >> "$RUN_DIR/calls.tsv"
  log "  $phase $arg: $status — $(field "$out" summary)"
  echo "$status"
}
stop_on() { # stop_on <status> <out.json> <what>
  case $1 in
    blocked) blocked "$3: $(field "$2" question) $(field "$2" summary)";;
    failed) die "$3: $(field "$2" summary)";;
  esac
}

# ---- merge a finished bead into the epic branch; Claude only on conflict or a red gate ---
# A bead's own gate ran on its branch. When nothing else merged since it branched, the merged
# tree is that same tree and needs no gate. When another bead landed in between, the two were
# never checked together (two beads once collided on one file), so the fast gate runs here.
post_merge_gate() {
  local id=$1 wt=$2 cmd=${ORCH_FAST_GATE:-} gl out
  [ -z "$cmd" ] && make -C "$EPIC_WT" -n check > /dev/null 2>&1 && cmd="make check"
  [ -z "$cmd" ] && { log "no fast gate (ORCH_FAST_GATE unset, no 'make check'); $id merged ungated"; return; }
  gl="$RUN_DIR/gate-$(suffix "$id").log"; log "gating the merge of $id ($cmd)"
  if (cd "$EPIC_WT" && eval "$cmd") > "$gl" 2>&1; then log "gate green after merging $id"; return; fi
  log "gate red after merging $id; asking merge-resolver"
  out="$CALLS/$(date +%Y%m%d-%H%M%S)-merge-$(suffix "$id").json"
  stop_on "$(call merge "$id --gate-red $gl" "$out" "$wt")" "$out" "merge $id"
}
merge_bead() {
  local id=$1 br wt moved=; br=$(bead_branch "$id"); wt=$(bead_wt "$id")
  git -C "$CLONE" rev-parse -q --verify "$br" > /dev/null || { log "no branch $br for $id, nothing to merge"; return; }
  [ "$(git -C "$EPIC_WT" merge-base HEAD "$br")" != "$(git -C "$EPIC_WT" rev-parse HEAD)" ] && moved=1
  local err
  if err=$(git -C "$EPIC_WT" merge --no-ff -q "$br" -m "merge($id): $(bdc show "$id" --json | jq -r '(if type=="array" then .[0] else . end).title')" 2>&1); then
    [ -n "$moved" ] && post_merge_gate "$id" "$wt"
  elif ! git -C "$EPIC_WT" rev-parse -q --verify MERGE_HEAD > /dev/null 2>&1; then
    # No MERGE_HEAD: git refused before merging (no committer identity, a dirty tree), which
    # no resolver can fix; one run spent a resolver call on exactly that.
    die "merge of $id failed before any conflict: $(tail -1 <<< "$err")"
  else
    git -C "$EPIC_WT" merge --abort || true
    log "conflict merging $id; asking merge-resolver"
    local out; out="$CALLS/$(date +%Y%m%d-%H%M%S)-merge-$(suffix "$id").json"
    stop_on "$(call merge "$id" "$out" "$wt")" "$out" "merge $id"   # the phase runs the gate itself
  fi
  teardown_wt "$wt"
  [ -d "$wt" ] && git -C "$CLONE" worktree remove --force "$wt"
  git -C "$CLONE" branch -D "$br" > /dev/null
  log "merged $id into $(git -C "$EPIC_WT" rev-parse --abbrev-ref HEAD)"
}

# ---- the bead loop: up to $WORKERS bead calls in parallel, merged as each finishes ------
RUN_IDS=(); RUN_PIDS=(); RUN_OUTS=(); STOP=
start_bead() {
  local id=$1 wt br out; wt=$(bead_wt "$id"); br=$(bead_branch "$id")
  if [ ! -d "$wt" ]; then
    if git -C "$CLONE" rev-parse -q --verify "$br" > /dev/null; then git -C "$CLONE" worktree add -q "$wt" "$br"
    else git -C "$CLONE" worktree add -q "$wt" -b "$br" "$(git -C "$EPIC_WT" rev-parse HEAD)"; fi
    prepare_wt "$wt"
  fi
  out="$CALLS/$(date +%Y%m%d-%H%M%S)-bead-$(suffix "$id").json"
  call bead "$id" "$out" "$wt" > /dev/null &
  RUN_IDS+=("$id"); RUN_PIDS+=($!); RUN_OUTS+=("$out")
  # The commit the worker starts from, so a run record shows what each worker saw.
  log "started $id at $(git -C "$wt" rev-parse --short HEAD) (${#RUN_IDS[@]}/$WORKERS running)"
}
reap() { # finished bead at index $1
  local id=${RUN_IDS[$1]} out=${RUN_OUTS[$1]} status
  wait "${RUN_PIDS[$1]}" || true
  status=$(field "$out" status); [ -z "$status" ] && status=failed
  case $status in
    done) merge_bead "$id";;
    blocked) STOP="$id blocked: $(field "$out" question) $(field "$out" summary)";;
    *) STOP="$id failed: $(field "$out" summary) $(head -c 200 "$out.err" 2>/dev/null)";;
  esac
  local ids=() pids=() outs=() i
  for i in "${!RUN_IDS[@]}"; do [ "$i" = "$1" ] || { ids+=("${RUN_IDS[$i]}"); pids+=("${RUN_PIDS[$i]}"); outs+=("${RUN_OUTS[$i]}"); }; done
  RUN_IDS=("${ids[@]}"); RUN_PIDS=("${pids[@]}"); RUN_OUTS=("${outs[@]}")
}
# Every finished bead is reaped (merged) before the next schedule call. Reaping one per tick
# let a bead start while its dependency, finished and closed in bd but still unmerged,
# waited behind another bead's gate: its worktree was cut from a head one bead short.
reap_finished() {
  local i found
  while :; do
    found=
    for i in "${!RUN_PIDS[@]}"; do kill -0 "${RUN_PIDS[$i]}" 2>/dev/null || { reap "$i"; found=1; break; }; done
    [ -n "$found" ] || return 0
  done
}
build() {
  mark build_start
  while :; do
    reap_finished
    if [ -z "$STOP" ] && [ ${#RUN_IDS[@]} -lt "$WORKERS" ]; then
      local running batch; running=$(IFS=,; echo "${RUN_IDS[*]}")
      # A scheduler that crashes is not an empty batch: read as one, a crash once ended a run
      # with a false "nothing is ready" over eight ready fix beads.
      # Running beads finish and merge; then the run stops on the traceback.
      if batch=$(python3 "$HERE/schedule.py" "$EPIC" --max "$WORKERS" --running "$running" --repo "$CLONE" 2> "$RUN_DIR/schedule.err"); then
        for id in $batch; do start_bead "$id"; done
      else
        STOP="schedule.py failed: $(tail -3 "$RUN_DIR/schedule.err" | tr '\n' ' ')"; log "$STOP"
      fi
    fi
    [ ${#RUN_IDS[@]} -eq 0 ] && break
    sleep "$POLL"
  done
  [ -n "$STOP" ] && { case $STOP in *" blocked:"*) blocked "$STOP";; *) die "$STOP";; esac; }
  local left; left=$(open_children | grep -v "^$EPIC$" || true)
  [ -n "$left" ] && blocked "beads under $EPIC are not closed and nothing is ready (blocked, or waiting on a blocked bead): $(echo "$left" | tr '\n' ' ')"
  mark build_end
}
fix_loop() { # fix_loop <phase> [<arg>]: call the phase, run its fix beads, repeat; at most 3 rounds
  local phase=$1 arg=${2:-} out status fixes
  for _ in 1 2 3; do
    out="$CALLS/$(date +%Y%m%d-%H%M%S)-$phase${arg:+-$arg}.json"
    status=$(call "$phase" "$arg" "$out"); stop_on "$status" "$out" "$phase"
    fixes=$(jq -r '.structured_output.fix_beads // [] | .[]' "$out" 2>/dev/null | tr '\n' ' ')
    [ -z "${fixes// }" ] && return 0
    log "$phase filed fix beads: $fixes"; build
  done
  die "$phase still needs fixes after 3 rounds"
}

# ---- preflight ---------------------------------------------------------------------------
for tool in claude bd gh jq python3 git; do command -v "$tool" > /dev/null || die "$tool not on PATH"; done
git -C "$CLONE" var GIT_COMMITTER_IDENT > /dev/null 2>&1 || die "git has no committer identity in $CLONE; set user.name and user.email there (the driver merges and commits)"
# A box with one fine-grained GitHub token per org keeps it at ~/.orchestrator/tokens/<org>;
# gh and git (credential helper `gh auth git-credential`) and the phases' gh calls read GH_TOKEN.
OWNER=$(git -C "$CLONE" remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)([^/]+)/.*#\2#')
[ -z "${GH_TOKEN:-}" ] && [ -r ~/.orchestrator/tokens/"$OWNER" ] && { GH_TOKEN=$(<~/.orchestrator/tokens/"$OWNER"); export GH_TOKEN; }
exec 9> "$RUN_DIR/lock"; command -v flock > /dev/null && { flock -n 9 || die "another run of $EPIC holds $RUN_DIR/lock"; }
# The exit and blocked files belong to the run holding the lock. A dry run, or a start that lost
# the lock, never writes them, and a new run clears the last one's: the dry run's trap wrote 0
# and it stood in the run dir for five hours while the live run went on.
if [ -z "$DRY" ]; then rm -f "$RUN_DIR/exit" "$RUN_DIR/blocked"; trap 'echo $? > "$RUN_DIR/exit"' EXIT; fi
# A signal stop is never exit 0. Untrapped, SIGTERM left the EXIT trap writing the status of
# the last command, and the OOM stop of a run's unit read as a success.
trap 'exit 143' TERM; trap 'exit 130' INT; trap 'exit 129' HUP
# tee closes the lock fd (9>&-): it drains after the script has exited and would hold the flock
# a moment longer, so a start chained right after a dry run died in preflight.
exec > >(tee -a "$RUN_DIR/driver.log" 9>&-) 2>&1
log "orchestrate-epic $EPIC base=$BASE workers=$WORKERS clone=$CLONE run-dir=$RUN_DIR"
# Run with the skills as pushed: on the box ~/.claude/skills is a clone of claude-skills.
SKILLS=$(cd "$HERE/.." && pwd)
if [ -d "$SKILLS/.git" ]; then
  if git -C "$SKILLS" pull -q --ff-only 2>/dev/null; then log "skills at $(git -C "$SKILLS" rev-parse --short HEAD)"
  else log "WARNING: could not pull $SKILLS; running with what is there"; fi
fi
git -C "$CLONE" fetch -q origin
git -C "$CLONE" rev-parse -q --verify "origin/$BASE" > /dev/null || die "origin/$BASE does not exist"
[ -z "$(git -C "$CLONE" status --porcelain --untracked-files=no | grep -v ' .beads/' || true)" ] || die "the main checkout has uncommitted changes outside .beads/"
bdc show "$EPIC" --json > /dev/null || die "bd cannot show $EPIC"
# A key the epic needs left empty in .env stops a bead mid-call instead of here (one bead
# returned blocked after six minutes on an empty third-party credential).
if [ -n "${ORCH_REQUIRED_ENV:-}" ]; then
  [ -f "$CLONE/.env" ] || die "ORCH_REQUIRED_ENV is set but $CLONE/.env does not exist"
  bad=$(missing_env "$ORCH_REQUIRED_ENV" "$CLONE/.env")
  [ -z "$bad" ] || die "$CLONE/.env has no value for: $bad (ORCH_REQUIRED_ENV); fill them in by key and rerun"
  log "required env present in $CLONE/.env: $ORCH_REQUIRED_ENV"
fi

if [ -n "$DRY" ]; then
  log "dry run: epic worktree $EPIC_WT ($( [ -d "$EPIC_WT" ] && echo exists || echo "would be created from origin/$BASE"))"
  batch=$(python3 "$HERE/schedule.py" "$EPIC" --max "$WORKERS" --repo "$CLONE" --json) || die "schedule.py failed (traceback above)"
  log "dry run: first batch $batch"
  log "dry run: open children $(open_children | grep -v "^$EPIC$" | tr '\n' ' ')"
  exit 0
fi

# ---- epic worktree (the driver's, not a phase's) ------------------------------------------
if [ ! -d "$EPIC_WT" ]; then
  remote=$(git -C "$CLONE" branch -r --list "origin/$EPIC/*" | head -1 | sed 's#^ *origin/##')
  if [ -n "$remote" ]; then git -C "$CLONE" worktree add -q "$EPIC_WT" "$remote"; log "resumed epic branch $remote from origin"
  else
    title=$(bdc show "$EPIC" --json | jq -r '(if type=="array" then .[0] else . end).title')
    # The lead phrase before a colon names the epic; cut at 40 characters, since a whole
    # title made a branch name too long to read.
    slug=$(printf '%s' "${title%%: *}" | sed -E 's/\[(EPIC|epic)\]//; s/[^A-Za-z0-9]+/-/g; s/^-|-$//g' | tr A-Z a-z)
    [ ${#slug} -gt 40 ] && { slug=${slug:0:41}; slug=${slug%-*}; }   # cut at a word boundary
    git -C "$CLONE" worktree add -q "$EPIC_WT" -b "$EPIC/${slug:-epic}" "origin/$BASE"; log "created $EPIC_WT on $EPIC/${slug:-epic} from origin/$BASE"
  fi
  prepare_wt "$EPIC_WT"
fi
EPIC_BRANCH=$(git -C "$EPIC_WT" rev-parse --abbrev-ref HEAD)

# ---- recover from an interrupted run -----------------------------------------------------
for id in $(bdc list --parent "$EPIC" --flat --json | jq -r '.[] | select(.status == "in_progress") | .id'); do
  bdc update "$id" --status open --append-notes "Released by orchestrate-epic.sh restart $(date +%F); any work so far is on $(bead_branch "$id")." > /dev/null
  log "released in-progress bead $id"
done
known=$(git -C "$CLONE" worktree list --porcelain | awk '/^worktree /{print $2}')
for wt in "$PARENT/$REPO-$EPIC-"*; do
  [ -d "$wt" ] || continue
  grep -qx "$wt" <<< "$known" || { log "ignoring $wt: a leftover folder, not a worktree git knows"; continue; }
  n=${wt##*/"$REPO-$EPIC-"}; [[ $n =~ ^[0-9][0-9-]*$ ]] || continue; id="$EPIC.${n//-/.}"
  [ -n "$(git -C "$wt" status --porcelain)" ] && { git -C "$wt" add -A && git -C "$wt" commit -q -m "wip($id): left by an interrupted run"; log "committed leftover work in $wt"; }
  status=$(bdc show "$id" --json 2>/dev/null | jq -r '(if type=="array" then .[0] else . end).status' 2>/dev/null) || status=unknown
  [ "$status" = closed ] && { log "$id closed but unmerged; merging"; merge_bead "$id"; }
done

# ---- the run -----------------------------------------------------------------------------
PR=$(cd "$EPIC_WT" && gh pr list --head "$EPIC_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
if [ -z "$PR" ]; then
  out="$CALLS/$(date +%Y%m%d-%H%M%S)-setup.json"; stop_on "$(call setup "" "$out")" "$out" setup
  [ "$STOP_AFTER" = setup ] && { log "stopped after setup as asked"; exit 0; }
  build;                       [ "$STOP_AFTER" = build ] && { log "stopped after build as asked"; exit 0; }
  fix_loop integrate; mark integrate_end; [ "$STOP_AFTER" = integrate ] && { log "stopped after integrate as asked"; exit 0; }
  fix_loop prove; mark prove_end;         [ "$STOP_AFTER" = prove ] && { log "stopped after prove as asked"; exit 0; }
  out="$CALLS/$(date +%Y%m%d-%H%M%S)-pr.json"; stop_on "$(call pr "" "$out")" "$out" pr
  PR=$(field "$out" pr); [ -n "$PR" ] || die "pr phase returned no PR number"
  mark pr
fi
PR_URL=$(cd "$EPIC_WT" && gh pr view "$PR" --json url --jq .url); echo "$PR_URL" > "$RUN_DIR/pr.url"
log "PR #$PR $PR_URL"
[ "$STOP_AFTER" = pr ] && { log "stopped after pr as asked"; exit 0; }

# Watch every Actions run on the epic branch's head commit. Through the Actions API, not
# `gh pr checks`: a fine-grained token without Checks/Commit-status read gets a GraphQL error
# from the PR's check rollup, which looked like a red build.
ci_watch() {
  local sha runs="" id rc=0; sha=$(git -C "$EPIC_WT" rev-parse HEAD)
  for _ in $(seq 1 20); do   # GitHub can take a few minutes to start the runs for a push
    runs=$(cd "$EPIC_WT" && gh run list --commit "$sha" --json databaseId --jq '.[].databaseId' 2>/dev/null || true)
    [ -n "$runs" ] && break; sleep 15
  done
  [ -z "$runs" ] && { echo "NO RUNS for $sha"; return 1; }
  sleep 30; runs=$(cd "$EPIC_WT" && gh run list --commit "$sha" --json databaseId --jq '.[].databaseId')
  # Polled, not `gh run watch`: that asks for check annotations, which such a token cannot read.
  local st
  for id in $runs; do
    while st=$(cd "$EPIC_WT" && gh run view "$id" --json status,conclusion --jq '"\(.status) \(.conclusion)"' 2>/dev/null) && [ "${st%% *}" != completed ]; do sleep 60; done
    echo "run $id: ${st:-unreadable}"; [ "$st" = "completed success" ] || rc=1
  done
  return $rc
}
CI_RUNS=0; CI_FAILED=0; RERAN=; CI_NOTE="CI green"; CI_EXTRA=
# shellcheck source=/dev/null
[ -f "$RUN_DIR/ci.counts" ] && . "$RUN_DIR/ci.counts"    # a restarted driver carries the counts on
ci_counts() { printf 'CI_RUNS=%s\nCI_FAILED=%s\n' "$CI_RUNS" "$CI_FAILED" > "$RUN_DIR/ci.counts"; }
# A repo without workflows has nothing to watch and the run's own gates are the proof; one
# run blocked five minutes on "no CI run started" over that. ORCH_CI=skip
# says the same for a repo whose workflows do not run on this PR.
if [ "${ORCH_CI:-}" = skip ]; then CI_NOTE="CI skipped (ORCH_CI=skip)"; CI_EXTRA=" skipped=1"; log "skipping the CI watch as asked (ORCH_CI=skip)"
elif ! ls "$EPIC_WT"/.github/workflows/*.y*ml > /dev/null 2>&1; then CI_NOTE="no CI workflows"; CI_EXTRA=" workflows=none"; log "no .github/workflows on the epic branch; nothing to watch on PR #$PR"
else
while :; do
  CI_RUNS=$((CI_RUNS + 1)); ci_counts; log "watching CI on PR #$PR (run $CI_RUNS)"
  if ci_watch > "$RUN_DIR/ci-$CI_RUNS.log" 2>&1; then log "CI green"; break; fi
  CI_FAILED=$((CI_FAILED + 1)); ci_counts
  grep -q "^NO RUNS" "$RUN_DIR/ci-$CI_RUNS.log" && blocked "no CI run started for PR #$PR's head commit; is $BASE in the workflow's pull_request branches?"
  [ "$CI_RUNS" -gt 4 ] && blocked "CI still red after $CI_FAILED failures on PR #$PR; see $RUN_DIR/ci-*.log"
  out="$CALLS/$(date +%Y%m%d-%H%M%S)-ci.json"; stop_on "$(call ci "$PR" "$out")" "$out" ci
  fixes=$(jq -r '.structured_output.fix_beads // [] | .[]' "$out" | tr '\n' ' ')
  if [ -z "${fixes// }" ]; then
    [ -n "$RERAN" ] && blocked "CI red outside the epic's scope on PR #$PR: $(field "$out" summary)"
    RERAN=1; log "no fix beads; rerunning the failed jobs once"
    (cd "$EPIC_WT" && gh run list --commit "$(git rev-parse HEAD)" --status failure --json databaseId --jq '.[].databaseId' | xargs -r -I{} gh run rerun {} --failed) || true
  else
    log "ci filed fix beads: $fixes"; build
    git -C "$EPIC_WT" push -q
  fi
done
fi
mark ci_green

# ---- close: run record, epic closed, beads committed, worktrees gone ---------------------
cost() { awk -F'\t' -v p="$1" '$2==p {s+=$5} END {printf "%.2f", s}' "$RUN_DIR/calls.tsv"; }
WORKERS_LINE=$(bdc list --all --parent "$EPIC" --flat --json | jq -r '[.[] | .close_reason // "" | capture("worker=(?<w>[a-z]+) rounds=(?<r>[0-9]+)")] | "opus=\(map(select(.w=="opus"))|length) sonnet=\(map(select(.w=="sonnet"))|length) second-round=\(map(select(.r!="1"))|length) sonnet-second-round=\(map(select(.w=="sonnet" and .r!="1"))|length)"')
bdc update "$EPIC" --append-notes "RUN spawn=$(t build_start) pr=$(t pr) ci-green=$(t ci_green) workers=$(bdc list --all --parent "$EPIC" --flat --json | jq '[.[] | select(.close_reason // "" | test("worker="))] | length') driver=orchestrate-epic.sh
PHASES build=$(t build_start)-$(t build_end) integrate=-$(t integrate_end) prove=-$(t prove_end) pr=$(t pr) ci-green=$(t ci_green)
WORKERS $WORKERS_LINE
CI runs=$CI_RUNS failed=$CI_FAILED$CI_EXTRA
COST_USD total=$(awk -F'\t' '{s+=$5} END {printf "%.2f", s}' "$RUN_DIR/calls.tsv") calls=$(wc -l < "$RUN_DIR/calls.tsv" | tr -d ' ') bead=$(cost bead) merge=$(cost merge) integrate=$(cost integrate) prove=$(cost prove) pr=$(cost pr) ci=$(cost ci) setup=$(cost setup)" > /dev/null
bdc close "$EPIC" --reason "orchestrate-epic.sh: PR #$PR, $CI_NOTE" > /dev/null || log "bd close $EPIC refused; closing by hand is the one thing left"
# The run's closes and fix beads live only in this box's db until they are exported; the
# clone's committed file is <base>'s copy and never has them.
if git -C "$EPIC_WT" ls-files --error-unmatch .beads/issues.jsonl > /dev/null 2>&1; then
  bdc export -o "$EPIC_WT/.beads/issues.jsonl"
  if [ -n "$(git -C "$EPIC_WT" status --porcelain .beads/issues.jsonl)" ]; then
    git -C "$EPIC_WT" add .beads/issues.jsonl && git -C "$EPIC_WT" commit -q -m "chore(beads): close $EPIC — PR #$PR" && git -C "$EPIC_WT" push -q
  fi
else log "this repo does not track .beads/issues.jsonl; the run's beads stay in this box's db"; fi
teardown_wt "$EPIC_WT"
{ git -C "$CLONE" worktree remove --force "$EPIC_WT" && git -C "$CLONE" branch -D "$EPIC_BRANCH" > /dev/null && git -C "$CLONE" worktree prune; } || log "could not remove $EPIC_WT; remove it by hand"
log "done: $EPIC closed, worktrees removed, $(wc -l < "$RUN_DIR/calls.tsv" | tr -d ' ') calls"
echo "PR: $PR_URL"
