---
name: handover
description: Hand this session's work, including orchestration of subagents, to a fresh Claude Code session with no pasting. Winds down running subagents, records their results, writes a handover file, and signals the new session (which the user has started with /takeover) to take over. Use when the user says "/handover", "hand over", "swap to a new orchestrator", or wants to move the work to a fresh session because context is getting full. Not for a plain copy-paste summary — that is /handoff.
---

# Handover (sending side)

The user has opened a fresh session and run `/takeover` in it; that session is waiting for a
handover file. Your job: finish up here cleanly, write the file, signal it, and stop. The user
may have walked away, so do everything without asking questions unless something would be
destroyed.

Arguments: `now` = stop running subagents instead of waiting for them. Anything else is a note
to include for the next session.

## 1. Locate the handover slot

- Slot directory: `~/.claude/handovers/`. Slot name: the basename of the current working
  directory (e.g. `main`). Files: `<slot>.md` (the note), `<slot>.ready` (written last),
  `<slot>.waiting` (written by the waiting /takeover session: its session name and time).
- Read `<slot>.waiting`. If it exists, note the session name in it. If it does not exist, the
  user may not have run /takeover yet: continue anyway (the file handover still works when they
  do), and use the fallback in step 6.
- If `<slot>.ready` already exists from an earlier handover, move the old pair to
  `<slot>.<timestamp>.md` / `.ready` first.

## 2. Stop starting new work

From now on launch no new subagents, workflows or long commands. Tell running subagents
nothing new unless they ask.

## 3. Wind down running subagents

List them (ListAgents). For each still running:
- Default: wait for it to report. Process each report as usual (verify claims cheaply, update
  the tracker, commit finished work if your workflow commits per unit). Keep replies to the
  user between notifications to one line.
- With `now`: SendMessage each one to stop at the next safe point and report what is finished
  and unfinished; if it does not report within a few minutes, stop it with TaskStop and record
  it as interrupted, listing the files it was known to be touching.
Do not hand over while any subagent you started is still running: the new session cannot
receive their reports or message them.

## 4. Make the durable state true

- Tracker (beads in repos that use it): every unit of work has an accurate status and a note
  with what is done, what is not, and evidence paths. File issues for loose ends.
- Git: commit finished work the way this workflow already does. Do not push unless the
  workflow in progress already pushes at this point. Leave uncommitted work in place and list
  it.
- Anything that lives only in this session's scratchpad directory (worker briefs, templates,
  logs the next session needs) is copied into `~/.claude/handovers/<slot>.files/`, because the
  scratchpad is private to this session. Rewrite paths in those files that point at the old
  scratchpad.
- Long-running local services (docker stacks, servers) stay up; record how to check them.

## 5. Write `<slot>.md`

Follow the /handoff note structure (goal, done, in progress, next steps, do-not-retry), written
for a fresh orchestrator, plus:
- **Role**: what the user asked for, in their words where it matters, and the decisions they
  made (with dates), so the next session does not re-ask.
- **Orchestration state**: limits the user set (e.g. max concurrent agents, models), each
  worker's last report in two lines, the queue of units not yet started in order, and the
  exact prompt pattern or brief files used to start workers (paths under `<slot>.files/`).
- **Environment**: worktree paths, running services and how to health-check them, known
  environment gotchas found this session.
- **User preferences seen this session** (how they want progress reported, pushes, costs).
- **Tracker pointers**: epic and issue IDs, `bd show` commands.
Verify every state claim against the tracker, git and the filesystem before writing it.

## 6. Signal

- Write `<slot>.ready` containing the time and this session's name. Write it only after
  `<slot>.md` is complete: the waiting session starts as soon as this file exists.
- If `<slot>.waiting` named a session, also SendMessage it one line: "Handover ready at
  ~/.claude/handovers/<slot>.md". The file is the real signal; the message is a nudge.
- Fallback (no `<slot>.waiting`): ListAgents; if exactly one peer session is interactive,
  idle, in this project (name starts with the slot name) and started after this handover
  began or within the last hour, SendMessage it: "The user asked for a handover. Run
  /takeover." Say in your final message that the new session may treat this as a request
  from another agent rather than from the user, so the user should type `/takeover` there if
  nothing happens. Never message a session that is busy or whose purpose you cannot tell.

## 7. Stop

Final message to the user, short: where the handover file is, which session was signalled
(or that none was found and they should run `/takeover` in a new session), what was left
uncommitted, and that this session will do nothing further. Then do nothing further: no new
agents, no edits, even if more notifications arrive — answer any later notification with one
line pointing at the new session.
