---
name: orchestrate-phase
description: Run exactly one phase of an /orchestrate run (setup, bead <id>, merge <id>, integrate, prove, pr, ci <pr>) and return a JSON result, so that a script can drive an epic headless on a server as a chain of Claude calls. The orchestrate skill itself is unchanged and stays the way to run an epic interactively; this skill exists for `orchestrate-epic.sh` in this folder, which schedules beads, merges, watches CI and reruns after a crash. Use only when invoked as "/orchestrate-phase <epic> <phase> …" by that driver or by hand to test one phase.
argument-hint: "<epic-id> <phase> [<arg>] --base <branch>"
model: claude-opus-5-5[1m]
---

# One phase of an orchestrate run

Arguments: `<epic-id> <phase> [<arg>] --base <branch>`. Load the orchestrate skill first:
call the Skill tool with `orchestrate` and `<epic-id>` as its argument, then follow it
word for word for the phase you were given and nothing else. Where this file or
`phases.md` disagrees with it, this file wins.

**You do one phase, then stop.** The phase contract, including the fixed worktree and
branch names, what each phase reads, writes and returns, is `phases.md` in this folder.
Read it before acting. The result is the JSON object the caller asked for with
`--json-schema`; return it as your final output and nothing else.

## What changes from the interactive run

- `<base>` is the `--base` argument, everywhere the orchestrate skill says `<base>`.
- The driver owns the loop: scheduling, worktree creation and removal, the plain
  `git merge --no-ff` of each bead branch, the CI watch (the Actions runs on the head commit;
  skipped when the repo has no workflows), the RUN, PHASES, CI and COST_USD record lines, and
  the final clean-up. You never do those unless the phase says.
- Nobody will answer. The skill's stop-and-ask becomes: write the question on the bead or
  epic as `phases.md` says, return `blocked` with it, and the driver stops for the user.
- Every "fix it through the per-bead loop" in the end-of-epic steps becomes a fix bead
  filed under the epic and returned in `fix_beads`; the driver runs it as a bead.
- Workers are spawned in the foreground. Agent types, models, review rules, close reasons,
  SCHEDULE and DECISIONS lines are exactly as the orchestrate skill says.
- The orchestrate final message is not produced; the JSON is the message.
