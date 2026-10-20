---
name: orchestrate
description: Run one beads epic unattended with worker agents doing the implementation — beads in parallel where their TOUCHES are disjoint, a simplify pass, a plain review with its fixes applied, an adversarial review with fixes, then the acceptance-bar walkthrough recorded slowed down with a chapter per step, a pull request written with the pr skill, and local worktrees cleaned up. Use when the user says "orchestrate", "/orchestrate <epic-id>", or asks to run an epic with subagents doing the work.
model: claude-opus-5-5[1m]
---

# Orchestrate one epic with worker agents

You are the **orchestrator**. Workers write the code; you write their prompts, review
every diff, commit, keep beads current, and produce the pull request. Workers never talk
to the user. One epic per run; the user opens another terminal for a second epic.

Workers are spawned by agent type, never by `model` and never as `general-purpose`:
`worker-sonnet` for a bead whose notes carry `MODEL: sonnet`, `worker-opus` for a bead
marked `MODEL: opus` or carrying no `MODEL:` line at all, `merge-resolver` for conflicts.
The epic chose the model; you never re-route a bead except through the escalation in
the per-bead loop.

## The user is away

Assume nobody will answer until the run is over. Every epic carries DECISIONS, a CHANGE
PROTOCOL, and per-bead acceptance, READ FIRST and TOUCHES. Build what they say.

- **Decide yourself** whenever the epic, the plan docs, CLAUDE.md or an existing pattern
  answers it, and also when they do not: pick the option you would recommend and carry
  on. Two kinds of choice, recorded apart:
  - what the product does → appended to the epic's DECISIONS as `chosen by orchestrator,
    reversible: <choice> over <alternative> because <reason>`, and listed in the PR under
    "Choices made for you";
  - how the run proceeds (re-ordering beads, running two together, splitting one, widening
    TOUCHES) → appended to the epic as `SCHEDULE <date>: <what> because <reason>`, never
    in DECISIONS and never in the PR.
- **Stop and ask** only when a choice changes what the product does for its user *and*
  guessing would make the rest of the epic wrong. One question, recommendation first.
  This should be rare.
- **Never pause for confirmation** before a step this skill prescribes. The only things
  you never do are merge into `<base>` and force-push.
- **The proof of done is the recording.** DONE MEANS always opens with the acceptance-bar
  walkthrough recorded as video with a chapter and one picture per step, and a pull request
  carrying it. A run that cannot show that is not finished, whatever else is green.
  The spec that records it is throwaway: never committed, so the PR's diff carries no
  walkthrough spec, fixture, helper, page object, package or workflow (user, 2026-10-13).
- **The run ends with nothing for the user to do** except read the PR and merge it. No
  follow-up beads, no open questions, no list of things to consider. Worth doing means
  done in this run; not worth doing in this run means not worth a bead.

## RUN MODE on the epic

An epic whose notes open with a **RUN MODE** section is run the way that section says.
Read it in setup before anything else. Each of its lines replaces the step of this skill
it names: which branch a bead starts from, whether beads merge into an epic branch or each
opens its own pull request, which end-of-epic steps run (simplify, plain review,
adversarial review, walkthrough, run record, final PR), what proof a bead carries, and who
merges. Everything RUN MODE does not mention runs exactly as written here: the per-bead
loop, the diff review, the close reasons, the three-worker cap, the worktree hygiene. A
RUN MODE line is never a reason to stop and ask, and the fixed DONE MEANS lines are not
appended to an epic whose RUN MODE replaces them. The headless driver
(`orchestrate-phase`) does not read RUN MODE; such an epic runs interactively.

The known variant is **one pull request per bead** (user, 2026-10-15): no
epic branch. Each bead gets its own worktree `../<repo>-<bead-id>` on branch
`<bead-id>/<slug>` from `<base>`; after the review and the commit, the orchestrator pushes
that branch, runs the `pr` skill for it against `<base>` (no `--demo` unless the bead
ships a user-facing change), appends `PR: <url>` to the bead's notes, closes the bead and
removes the worktree. Beads never merge into each other; the user merges each PR. When
`<base>` moves and an open PR conflicts, the orchestrator rebases that branch onto
`<base>` (merge-resolver on a conflict) and pushes it with `--force-with-lease`. TOUCHES
overlap does not stop two such beads running together; it only predicts a rebase.

## The epic is a starting plan

When a landed bead proves part of the plan wrong, change the plan in `bd`, for any bead
not yet claimed: rewrite, split, merge, re-order, add or drop deps, close as obsolete, or
add a bead the epic missed in the same shape as its siblings with acceptance, READ FIRST
and TOUCHES. Each such change is a SCHEDULE line. A discovery that matters becomes a bead
run in this epic before it ends, never a note for later. A reversed DECISION is recorded
in the epic notes and the plan doc it cites, committed with the bead that acts on it. Work
that belongs to another epic is filed there in one line and not built here.

## Setup

1. `bd show <epic>` and read DECISIONS, SEQUENCING, ACCEPTANCE BAR, CHANGE PROTOCOL and
   DONE MEANS in full. An epic filed without DONE MEANS gets the three fixed lines
   (recorded walkthrough, PR carrying it, full gate) appended with
   `bd update <epic> --append-notes` before any bead is claimed. Note SEQUENCING's
   `planned=` line: the run record measures drift against it. `bd ready` for the
   starting beads. `bd prime` if beads context is missing.
2. `<base>` is the branch pull requests target: the one CLAUDE.md names, `main` if it
   names none. Epic worktree and branch off `<base>`, never the main checkout:
   ```
   git worktree add ../<repo>-<epic-id> -b <epic-id>/<slug> <base>
   ```
   Every git command runs with `-C <worktree>`. A fresh worktree has none of the gitignored
   env files and no generated client: run the repo's `make worktree-setup` in every worktree
   this run adds, when the Makefile has that target, and its `make worktree-teardown` before
   removing one: a gate's Docker project and dev servers otherwise outlive the worktree.
3. Read the gates and standing rules from the repo's CLAUDE.md. The worker gate is the
   fast tier (lint, unit tests, and the test files the bead touches). The full tier
   (integration, e2e) runs at the end of the epic, not per bead. A bead that touches e2e
   specs runs only those spec files, with the repo's single-spec command and a port of its
   own, never the whole e2e tier: workers run three at a time next to a merge gate, and the
   timed specs fail under that load. Say so in the prompt's gate line.

## Scheduling

- The candidates are `bd ready` within the epic. Two candidates run at the same time when
  their `TOUCHES` do not overlap and they do not both hit a hazard named in SEQUENCING or
  CLAUDE.md. Everything else is serial. **At most three workers at once.**
- A bead that runs alongside others gets its own worktree branched from the epic branch:
  ```
  git worktree add ../<repo>-<epic-id>-<n> -b <epic-id>/<n> <epic-branch>
  ```
  After its review it is committed there and merged into the epic branch with
  `--no-ff`; a conflict goes to `merge-resolver`. When another bead merged since this one
  branched, the two were never checked together: run the fast gate on the epic branch after
  the merge, and a failure goes to `merge-resolver` too. Then `make worktree-teardown` runs
  in the worktree when the Makefile has that target, and the worktree and branch are
  removed. A bead that runs alone works in the epic worktree directly.
- **Batch** closely related ready beads for one worker: same pattern repeated, same
  files, follow-ups on one screen, and the same `MODEL:`. Never across an unmet dep. If
  a batch partially fails, split the remainder back into single beads.
- **Two rounds, then a fresh worker**: a diff that fails review gets one specific
  correction; if the second review still fails, spawn a fresh worker with the original
  prompt plus what went wrong. The fresh worker is always `worker-opus`, whichever type
  ran first, so a Sonnet bead that fails twice escalates to Opus. Never a third round on
  the same worker.

## Per-bead loop

1. **Claim**: `bd update <id> --claim`.
2. **Prompt**: title and description; the epic's DECISIONS, marked as settled; worktree
   path and branch; READ FIRST; TOUCHES with "do not edit outside these paths"; the fast
   gate command. Then the finish line in one block:
   ```
   Done means: <each acceptance item>; the fast gate green; nothing edited outside
   TOUCHES; nothing in your report marked as not confirmed.
   Stop only if the bead, DECISIONS and the plan docs leave a question open and
   guessing would change the design. Otherwise keep going to the finish line.
   ```
   Then the standing rules: work only in the worktree, read the plan docs before coding,
   grep for an existing helper before writing one, never commit or push; a gate failure in
   a test the bead does not touch is run once on `<base>`, and when it fails there too it is
   reported as pre-existing and the bead carries on, never chased further. The report, in
   this order: `Blocked on you:` (one question, or `nothing`); what was done; files
   changed; gate output pasted verbatim; anything not confirmed and where the worker
   looked; any mismatch between the bead and the code. Nothing else.
3. **Spawn** in the background with `subagent_type` `worker-sonnet` or `worker-opus`
   per the bead's `MODEL:` line; no line means `worker-opus`. The Agent `description`
   starts with the bead id (`acme-k3p1.3 invitation actions`): the cost script finds the
   run's agents by it. Wait for the completion notification. Never fabricate a result. A
   result that mentions a flagged message or a model switch is discarded: spawn a fresh
   worker of the same type with the same prompt and count it as a respawn.
4. **Review the diff**, every bead, proportionate to its risk. Read the worker's
   `Blocked on you` line first. Four questions:
   - **Correct**: every acceptance item, nothing beyond. An item the worker marked as not
     confirmed is a failed item. Spot-check one test for behaviour rather than coverage.
   - **Fits**: consistent with landed beads, the plan docs and CLAUDE.md's standing
     rules. Re-inventing something or quietly changing scope fails.
   - **Honest**: read the worker's gate output; re-run the fast gate only when the
     report is unclear. Look for skipped tests, `eslint-disable`, `as any`.
   - **No loose ends**: anything found is fixed in the push-back, folded into a later
     bead's prompt, or dropped. Never deferred to the user.
   A gate failure the worker found red on `<base>` too is not this bead's: review the rest
   as usual, and the first time it is reported, file one fix bead for it under the epic,
   priority 1 so the scheduler starts it next, unless a bead under the epic already names
   that test; name the bead in the close reason's `mismatch`. Every later worker meets the
   same failure, and in one run four workers each spent minutes proving one pre-existing
   before a fifth filed it.
   Push back via SendMessage with a specific correction and append the same sentence to
   the bead as `ROUND 2: <correction>`; re-review; count the round.
5. **Commit** in the bead's worktree, subject naming the bead id. **Close** with one
   fixed reason, the same keys on every bead so runs compare:
   ```
   bd close <id> --reason "worker=opus rounds=1 respawn=0 minutes=22 gate=5m round2=none mismatch=none unconfirmed=none"
   ```
   `minutes` is spawn to close, `gate` the gate's own run time; `round2`, `mismatch` and
   `unconfirmed` are ten words each, copied from your correction and from the worker's
   last two report lines, `none` when there was nothing. Tell the user in one line.

## End of epic

1. **Full gate** on the epic branch. Failures are fixed through the per-bead loop.
2. **Simplify once**: run the `simplify` skill scoped to `git -C <worktree> diff
   <base>...<epic-branch>`; re-run the full gate; revert any hunk that changes behaviour;
   one commit. Keep the counts of items applied and skipped, with each skip's reason.
3. **Plain review and fix**: run the `code-review` skill at high effort with `--fix`, scoped
   like simplify, in the epic worktree. It takes the obvious bugs off the table before the
   fan-out, and its fixes land inside the adversarial review's scope, so they get the full
   treatment there. Re-run the fast gate; a fix that breaks it is reverted and counted as
   skipped. One commit. Keep the counts of findings fixed and skipped, with each skip's reason.
4. **Adversarial review**: run the `adversarial-review` skill with worktree, branch and
   base `<base>` inlined into the script. Do not review the diff yourself and do not
   override its model or effort. Check its narrator line for `undefined`.
5. **Fix the findings** through the per-bead loop, parented under the epic. A false
   positive is closed with a reason. A **tie** bead, where the skeptics split, is checked
   before it is fixed: the worker reads the cited line first and, if it holds, closes the
   bead as not real with a reason and changes nothing; that is the expected outcome, not a
   failure. Run a second simplify only if the fix diff is over about a hundred lines or adds
   a file. One review pass only.
6. **Prove and show**: record the walkthrough spec slowed down, with video on, so a
   person can follow it: the repo's recorded-walkthrough target when it has one
   (`make e2e-demo id=<epic-id>` here), else Playwright with video on and slowMo. It
   leaves the pictures and `chapters.json` in `docs/demos/<epic-id>/`; convert the webm
   to an mp4 there, no gif. If it fails, the epic is not done; fix it. `docs/demos/` is
   gitignored and the spec asserts with locators, not `toHaveScreenshot`: no media or
   pixel baseline is ever committed; step 8 uploads it. The spec is throwaway too (user,
   2026-10-13): the walkthrough bead runs in the epic worktree, not a bead worktree of its
   own, because it commits nothing and there is nothing to merge; its worker writes the
   spec under the gitignored `docs/demos/<epic-id>/` when the suite can run it from there,
   else next to the suite's own specs as an untracked file, never `git add`s it, and the
   untracked file stays for this slowed-down re-recording until step 10 deletes it. When
   the PR opens, `git status` on the epic branch shows no walkthrough file and the diff
   carries no walkthrough spec, fixture, helper, page object, package or workflow. Then go
   through DONE MEANS line by line; an unticked line is fixed through the per-bead loop
   before the PR is opened, never noted for later.
7. **Run record**: `bd update <epic> --append-notes` under the epic's RUN RECORD heading,
   one line each, key=value only, no prose. The per-bead detail is already on the beads'
   close reasons; this is the run in ten lines, written so a retro can grep it across
   epics. Fill the `pr` and `ci` keys later by appending the line again, never by editing;
   a step that runs again (prove after its fix beads) appends a line again only when its
   values changed, never a copy, and a retro reads the last line of each key:
   ```
   RUN spawn=05:34 pr=12:00 ci-green=12:40 hours=7.1 workers=33 respawns=0 escalations=0
   PHASES build=05:34-09:30 docs+walkthrough=-10:11 simplify=-10:24 review+fix=-11:58 pr=12:00
   WORKERS opus=27 sonnet=6 second-round=4 sonnet-second-round=0
   SIMPLIFY passes=2 applied=66 skipped=4(spec-pins-it,type-error) behaviour-reverted=0 bugs-found=3
   PLAIN found=14 fixed=11 skipped=3(not-a-bug,spec-pins-it)
   REVIEW finders=11 shards=6 found=36 deduped=29 confirmed=20 unverified=1 ties=2 refuted=6 votes=c40/u2/r16 fixed-in=.28-.50
   DRIFT planned=24 added=30 resequenced=4 touches-widened=1 bar-steps-reinterpreted=0 decisions-reversed=0
   INCIDENTS apply-form-walkthrough=local-aws-creds sales-register-479=flaky-rerun-passed
   CI runs=4 failed=1 cause=session-tasks-spec-hydration fixed-in=.54
   COST agents=33 worker-opus=27/510min worker-sonnet=6/60min tokens-in=1.2B tokens-out=120k
   DONE_MEANS 10/10 migration=20261003090000-no-pending-diff plan-rows=#319-#337 …
   ```
   `INCIDENTS` names each flake or environment failure once, with a tag reused across
   runs. `COST` is the output of `python3 ~/.claude/skills/orchestrate/cost.py <epic-id>`.
   `DONE_MEANS` has one clause per epic-specific line: the command and its result. If
   `escalations` exceeds a quarter of `workers`, add `tune=sonnet-too-wide` or
   `tune=opus-beads-too-big` so the next epic's `MODEL:` lines can be corrected.
8. **Pull request**: run the `pr` skill with `<base>`, `--epic <epic-id>` and
   `--demo docs/demos/<epic-id>/` inline. It reads the diff and every migration, calls
   the door, pushes the epic branch, opens the PR with the mp4 attached and fills the
   review-guide links. A PR without the recording is not done: back to step 6. With no
   remote the skill publishes the report as an Artifact and tells the user the branch.
9. **Watch CI**: poll `gh pr checks <pr> --watch` until every check is terminal. On a
   failure, read `gh run view <run-id> --log-failed`, fix it through the per-bead loop
   under the epic like any gate failure, push, and re-watch from scratch until all green.
   A failure outside the epic's scope (a flaky or pre-existing test) is not fixed here:
   say so in the final message and put it on the run record's `CI` and `INCIDENTS` lines.
10. **Clean up**: `bd close <epic>`. Delete the throwaway walkthrough spec and any untracked
   file that went with it. If beads syncs through a committed file, commit it on
   the epic branch after the last append and push, so the PR carries the run record.
   `make worktree-teardown` (when the Makefile has it) then `git worktree remove` in every
   worktree this run made, and delete their local branches,
   including the epic branch once it is pushed. The main checkout is untouched.
   `bd list --status=in_progress` must be empty.
11. **Final message**, in this order: `Blocked on you:` first, holding the one question
   the run stopped on or a CI failure outside the epic's scope, or `nothing`; then the PR
   link with the PR's first three lines (door, before merging, undo), the two-sentence
   summary, the CI outcome, and the choices made for the user.
   Nothing else. Review comments on the PR are `/address-review <pr>`'s job. After the
   merge, `git pull --ff-only && git fetch --prune` is the only local step.
