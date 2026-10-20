# Phase contract

`/orchestrate-phase <epic> <phase> [<arg>] --base <branch>` runs one phase of an orchestrate
run and returns one JSON object (`phase.schema.json`). The caller is `orchestrate-epic.sh`,
headless, from the main checkout `<clone>`, which passes the schema as `--json-schema`.
Nothing is remembered between calls: a phase reads its state from beads, git and GitHub,
does its work, writes what the next phase needs back to them, and returns.

## Fixed names

The driver and the phases agree on these; never invent others.

- `<repo>` is the basename of `<clone>`. The epic worktree is `<clone>/../<repo>-<epic>`
  on branch `<epic>/<slug>`; the driver made it from `origin/<base>` before any phase ran.
  `git -C <epic-worktree> rev-parse --abbrev-ref HEAD` gives the branch.
- A bead `<epic>.<n>` (dots inside `<n>` become dashes) works in `<clone>/../<repo>-<epic>-<n>`
  on branch `<epic>/<n>`, which the driver created from the epic branch's tip before the
  call and prepared with the repo's `make worktree-setup` when it has one. A bead never
  works in the epic worktree. Before removing a worktree the driver runs the repo's
  `make worktree-teardown` in it when it has one, which stops what a gate left running there.
- `bd` runs from `<clone>`. Every git command carries `-C`.
- A fix bead is a child of the epic (`--parent <epic>`) in the epic skill's shape:
  acceptance, READ FIRST, TOUCHES, MODEL, deps, plus `--append-notes "FILED BY: <phase>"`.
  The TOUCHES, READ FIRST, MODEL and Hazards lines go in the notes (`--append-notes`), each
  on a line of its own, as the epic skill writes them: the driver's scheduler reads them there
  to decide what runs together (it falls back to the description, where an earlier run's fix
  beads carried them). The scheduler picks it up like any other ready bead.

## The envelope

`status`: `done` (the work is complete), `noop` (nothing to do), `blocked` (a question only
the user can answer; it is also written on the bead or epic), `failed` (the phase could not
finish; what was tried is on the bead or epic as a note). `summary` is two sentences at
most. The driver stops on `blocked` and `failed` and prints `summary` and `question`.

In every phase: never ask the user (write the question down and return `blocked`); never
merge into `<base>`; never force-push; never edit the main checkout, except a gitignored plan
doc named in READ FIRST (`project_plan/…`), which exists only there and is read and edited by
its path relative to `<clone>`; never spawn a `general-purpose` agent; never do another phase's
work.

Never end your turn while a command or agent you started is still running: a headless call
that stops is made to return at once, before the work finishes. A run longer than one Bash
call allows (`make e2e`, the full gate) starts in the background with its output in a file,
and you wait for it with further foreground Bash calls (`while kill -0 <pid>; do sleep 15;
done`, up to ten minutes each) until it exits, then read the file. Wait on the pid or on a line
the job writes to its log, never on `pgrep -f`/`pkill -f` with a pattern: the waiting shell's
own command line holds the pattern, so the loop matches itself until the Bash timeout
(integrate and two workers once lost 29 minutes between them).

## setup

Read the epic. DECISIONS, SEQUENCING, ACCEPTANCE BAR or CHANGE PROTOCOL missing → `failed`
naming the section. DONE MEANS missing → append the three fixed lines (orchestrate Setup
step 1) and return `done`; present → `noop`. Confirm the epic worktree exists on a branch
named `<epic>/…`; return `branch` and `worktree`. Claim nothing.

## bead `<id>`

Precondition: `<id>` is a child of the epic, open or in_progress, and its worktree exists.

1. **Resume check**: `git -C <wt> log <epic-branch>..HEAD --oneline` and
   `git -C <wt> status --porcelain`. Commits or changes mean an earlier call was interrupted
   or blocked: read them and the bead's BLOCKED, FAILED and ANSWER notes, then continue the
   same work; never start over.
2. **Claim, prompt, spawn, review** as the orchestrate per-bead loop says, with two changes:
   the worker runs in the foreground (`run_in_background: false`), and the prompt names
   this bead's worktree and branch (never the epic worktree). The fast gate runs in `<wt>`.
   A bead that touches e2e specs runs only those spec files, one spec at a time with the
   repo's single-spec command and a port of its own (`E2E_PORT` or the repo's equivalent),
   never the whole e2e tier: up to three workers and a merge gate share one machine, and the
   timed specs fail under that load. The full tier is integrate's.
   Two rounds then a fresh `worker-opus`, as the skill says, with the `ROUND 2:` note on the
   bead, but the push-back is never a SendMessage: a resumed worker runs in the background,
   and a headless call cannot wait for it, so it is made to return before the worker
   finishes. Round 2 is a new foreground worker of the same type in the same worktree, given
   the original prompt, the correction, and that the worktree holds the first pass to build
   on. Never end your turn while a worker you started is still running.
3. **Commit** in `<wt>`, subject naming the bead id. **Close** with the fixed reason. Return
   `done` with `close_reason`, `branch`, `worktree`. Never merge.
4. **Blocked** (the skill's stop-and-ask, or a worker question that DECISIONS and the plan
   docs do not answer): commit what exists as `wip(<id>): blocked`, then
   `bd update <id> --status blocked --append-notes "BLOCKED <date>: <question>"` and return
   `blocked` with the question. The user answers with
   `bd update <id> --status open --append-notes "ANSWER: …"` and reruns the driver.
5. **Failed** (the second review fails after the fresh worker, or the worker cannot reach
   the finish line): commit as `wip(<id>): failed`,
   `--status blocked --append-notes "FAILED <date>: <ten words>"`, return `failed`.
6. A discovery that changes the plan is handled as the skill's "The epic is a starting plan"
   says, with its SCHEDULE line; a new bead is a child of the epic and the scheduler finds
   it. This call never claims a second bead.

## merge `<id>` [`--gate-red <log>`]

Without `--gate-red`: called only after the driver's own `git merge --no-ff <epic>/<n>` into
the epic branch failed and was aborted. In the epic worktree: redo the merge, give
`merge-resolver` the conflicting files and both sides' bead summaries, run the fast gate,
commit the merge as `merge(<id>): <title>`, return `done`.

With `--gate-red <log>`: the merge went in cleanly but the fast gate the driver ran on the
result failed (its output is at `<log>`); another bead had merged since `<id>` branched, so
the two were never checked together. The merge commit stays. Give `merge-resolver` the gate
output and both beads' summaries, fix the combined result in the epic worktree, run the fast
gate, commit as `fix(<id>): after merge`, return `done`.

Either way, the resolver reporting an incompatible design choice: undo (`git merge --abort`,
or `git reset --hard HEAD~1` after a gate-red fix attempt), append
`SCHEDULE <date>: merge of <id> blocked — <why>` to the epic, return `blocked` with the
question. The driver removes the bead worktree and branch.

## integrate

In the epic worktree, orchestrate End-of-epic steps 1 to 5 with every "fix through the
per-bead loop" replaced by filing a fix bead, in this order, which is not the skill's: the
full gate runs once, last, and not before the reviews as well. On the box a full gate takes
about fifty minutes, and one run spent four of its nine and a half hours in it, most of
them on trees that a review's fix round then changed. The beads' fast
gates and the driver's merge gates already stand for the tree the reviews start from.

1. **Simplify** once, unless the epic's RUN RECORD has a `SIMPLIFY` line; then only when the
   diff since that line's commit is over about a hundred lines or adds a file. Run the fast
   gate after it, not the full gate the skill's step 2 names. Commit; append the `SIMPLIFY`
   line.
2. **Plain review and fix** once, unless the RUN RECORD has a `PLAIN` line: the `code-review`
   skill at high effort with `--fix` in the epic worktree, then the fast gate; a fix that breaks
   it is reverted and counted as skipped. Commit; append the `PLAIN` line. When a `PLAIN` line
   is there, it runs again only when the diff from that line's commit to `HEAD` is over about a
   hundred lines or adds a file, and then scoped to that diff (`code-review` at high effort with
   `--fix` on `<plain-commit>..HEAD`), then the fast gate, then a new `PLAIN` line: a fix round
   can rewrite a hot path and otherwise reaches the PR with only its per-bead review
   (one fix bead rewrote a third-party send path's lock, deadline and transaction order).
3. **Adversarial review**, unless the RUN RECORD has a `REVIEW` line. Its beads are
   reparented under the epic (`bd update <id> --parent <epic>`) and given TOUCHES, READ
   FIRST and MODEL; a false positive is closed with a reason. A tie bead keeps the skeptic's
   citation at the top of its description, so its worker checks it before fixing and closes
   the bead as not real when it holds. Append the `REVIEW` line.
4. **The workers' own flags.** Read every child's close reason
   (`bd list --all --parent <epic> --flat --json`). Each `mismatch=` or `unconfirmed=` value
   other than `none` is something a worker left: a path it could not test, a gap between the
   bead and the code, a choice it could not confirm. One already answered, by a bead under the
   epic that names it (open or closed), a finding of step 2 or 3, or a DECISIONS line, needs
   nothing more. Otherwise it is a fix bead when it names work left undone, or a DECISIONS line
   `chosen by orchestrator, reversible: …` when it names a choice the product now makes, so the
   PR lists it under "Choices made for you". Append
   `FLAGS read=<n> answered=<n> fix-beads=<ids> decisions=<n>`, again on a later call only when
   its values changed. In one run, a deletion gap and an untested queue drop reached the
   review by luck, not by rule.
5. **Full gate**, only when steps 1 to 4 filed no fix bead in this call: a fix round would
   change the tree it checked, and the next `integrate` call runs it on the tree after the
   fixes. Each failure, or group of failures with one cause, is a fix bead; nothing is fixed
   inline. A failure that is no fault of the epic (that one test fails the same way on
   `<base>`, or only on this machine) is an `INCIDENTS` line, as `ci` writes them, and no bead.
   When the gate passes, append `GATE commit=<short sha of the epic worktree's HEAD>
   result=green minutes=<n>`; `prove` reads it.

A fix bead's `Hazards:` line names only a file or resource that bead really shares with
another bead, or is left out. Gate advice (one e2e stack per machine, port overrides,
a test-database URL override) goes in the bead's description or the worker
prompt's gate line, never the Hazards line: `schedule.py` reads that line's first clause as a
resource name and never pairs two beads that share one, so one advice line stamped on every
fix bead ran the whole fix round one bead at a time. A hazard that every
bead genuinely shares (three migration beads on one journal) still goes on each of them and
keeps them serial.

Return `done` with `fix_beads` naming every open bead this call filed or reparented, empty
when the branch is clean. The driver runs them through `bead` and its merge, then calls
`integrate` again.

## prove

Orchestrate End-of-epic step 6 and the RUN RECORD lines DRIFT, INCIDENTS, COST (from
`cost.py`) and DONE_MEANS (step 7). RUN, PHASES, WORKERS, CI and COST_USD are the driver's.
The walkthrough spec is throwaway (orchestrate step 6; user, 2026-10-13): when the `bead`
phase's worktree took it away, this call writes it again under `docs/demos/<epic>/` in the
epic worktree and records from there; it is never committed, and `pr` checks the diff carries
none of it. DONE MEANS's full-gate line is ticked from the RUN RECORD's last `GATE` line when
its commit is still the epic worktree's `HEAD`: the walkthrough commits nothing, so a tree
integrate has just gated needs no second fifty-minute run. The full gate
runs again only when `HEAD` has moved since, or there is no `GATE` line, and then appends one.
A walkthrough that fails, or a DONE MEANS line that cannot be ticked, is a fix bead.
Return `done` with `fix_beads`; empty means proven. The driver calls `prove` again after the
fixes, and the walkthrough runs again. The second call reads the RUN RECORD first: a line
whose key is already there (DRIFT, INCIDENTS) is appended again only when its values changed
(a new INCIDENTS tag, a new DRIFT count), never as a copy of the line already there; the retro
reads the last line of each key (one epic carried DRIFT twice, identical). COST and
DONE_MEANS are written once, on the call that proves.

## pr

When the repo tracks `.beads/issues.jsonl`, export the beads from `<clone>` straight into the
epic worktree, `(cd <clone> && bd export -o <epic-worktree>/.beads/issues.jsonl)`, never a
copy of the clone's file, which is `<base>`'s and has none of this run; commit it if it
changed (`chore(beads): <epic> notes`). A repo that does not track the file gets no beads
commit. Push the epic branch with `-u`. Run the `pr` skill with
`<base> --epic <epic> --demo docs/demos/<epic>/`; a PR already open for the branch has its
body rewritten instead. `gh pr view --json body` must contain no `docs/demos` path. Return
`done` with `pr` and `pr_url`. No remote → `failed`.

## ci `<pr>`

Called only after the driver's CI watch (the Actions runs on the PR's head commit) ended red;
a repo with no workflows never reaches this phase. Read
`gh run view <run-id> --log-failed` for every failed check. A failure inside the epic's scope
is a fix bead. One outside it (a flake, a pre-existing failure) is a line
`INCIDENTS <tag>=<what>` appended to the epic and no bead. Read the RUN RECORD's `INCIDENTS`
lines first: append only for a different incident, reusing the tag already there, never a
reworded tag or value for the same one, as prove's keyed lines (two calls on one red audit
step once left the same incident as two lines). Return `done` with `ci: failed`
and `fix_beads`. The driver runs the fix beads, merges, pushes and watches again; with no fix
beads it reruns the failed jobs once and otherwise stops with your `summary`.
