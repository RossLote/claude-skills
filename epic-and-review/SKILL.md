---
name: epic-and-review
description: After a finished /brief, file the epic in one subagent with the epic skill and then review it in a second with the epic-review skill, so the planning session keeps its context and the user only answers the questions either agent cannot settle. Runs only when the user types "/epic-and-review <brief-bead-id>"; never start it on your own at the end of a brief, because the user picks the moment by how much session usage is left.
argument-hint: "<brief-bead-id> [<base>]"
disable-model-invocation: true
---

# File and review an epic with subagents

The step after `/brief`, started by hand. It never follows a brief by itself: filing and
reviewing an epic costs a good share of a session's usage, and the user picks when to
spend it (user, 2026-10-30). This session coordinates and talks to the user. One agent
files the epic with the epic skill; when it reports, a second reviews the epic with the
epic-review skill. Neither agent can ask the user anything, so each returns its questions
and this session puts them to the user.

Target: `$ARGUMENTS`, the brief bead and optionally the base branch (default: the branch
CLAUDE.md names, else `main`).

## 0. Check the brief is done

- Work in the repo whose beads hold the bead: the one CLAUDE.md points at, and for a
  folder of repos the app repo's main checkout.
- `bd show <id>`: the description opens with the brief's summary and the notes' OPEN holds
  nothing the user decides. Otherwise stop, say what is still open and suggest
  `/brief <id>`. Spawn nothing.
- `git fetch origin <base>`. The agents read code at `origin/<base>`. When the main
  checkout is behind it, say so in both prompts; never pull or switch the checkout.

## 1. File the epic

Spawn one agent, `general-purpose`, model `opus`, in the background. Its prompt carries the
repo path, the base ref and the brief bead, and says:

- Invoke the epic skill with the Skill tool (skill `epic`, args the bead id) and follow it,
  including its lint run and its After filing checks, except step 4: the review is the
  next agent's job.
- You cannot ask the user. The brief is the source of every decision: the summary at the
  top of the bead's description and the D-lines in its notes. Where the epic skill says
  to put a question to the user, do not guess and do not file a decision bead: stop before
  filing anything and return the questions, numbered, each with what it decides and your
  recommended answer.
- When the brief's scope names changes to beads outside the new epic (another epic's
  unstarted beads), make them in this step and list each one.
- Do not commit or push.
- Return: the epic id, the `planned=` line, the parallel groups, any scope call you made,
  each bead outside the epic you changed (one line each), and what lint printed; or, when
  you stopped, the questions.

When it returns questions, put them to the user as numbered plain text with the agent's
recommendation on each, append the answers to the brief bead as new D-lines
(`bd update <brief> --append-notes`), then SendMessage the answers to the same agent so it
carries on with its context intact. Never file or edit the epic yourself.

## 2. Review it

When step 1 reports an epic id, spawn a second agent, `general-purpose`, model `opus`, in
the background. Its prompt carries the repo path, the base ref and the epic id, and says:

- Invoke the epic-review skill with the Skill tool (args `<epic-id> <base>`) and follow it.
- A subagent has no Workflow tool, so run the fleet through Agent calls, as the skill
  allows. Spawn `epic-finder` and `review-skeptic` by type when your Agent tool offers
  them. When it offers only `general-purpose`, spawn that with model `opus` and effort
  `high`, the body of `~/.claude/agents/epic-finder.md` or `review-skeptic.md` at the top
  of each prompt, and the line "read-only: never edit, commit or push". If you cannot
  spawn agents at all, stop and say so; never review alone.
- You cannot ask the user: the skill's "needs the user" items go in your final message,
  one line each, recommendation first.
- Do not commit or push.
- Return the skill's final message as it defines it: the Ready line, the fixes, the
  questions, the `EPIC_REVIEW` line.

If the review agent says it could not spawn agents, tell the user and offer to run
`/epic-review <epic-id>` in this session instead.

The review covers the new epic only. When step 1 changed beads in another epic, name that
epic in the report and offer `/epic-review <other-epic>`; do not run it unasked.

## 3. Report

One screen to the user: the epic id, bead count and parallel groups; the beads changed
outside it; the review's Ready line and its fixes, one line each; then its questions,
numbered, each with the recommendation, so "your defaults" is a complete reply. Send the
answers to the review agent with SendMessage to apply (it holds the context), then report
what changed. Do not commit or push. Final line: `/orchestrate <epic-id>` (or
`/queue <epic-id>` for the server) when ready.
