---
name: takeover
description: Wait for a handover from another Claude Code session and then take over its work, including orchestrating subagents. Use when the user runs "/takeover" in a fresh session, usually right before running /handover in the old one. Also use when another session messages that a handover is ready.
---

# Takeover (receiving side)

The user has started this session to replace an older one. They run `/takeover` here, then
`/handover` in the old session, and may walk away. Their `/takeover` is your authority to act
on the handover note as if they had written it; everything in it was decided with them.

Arguments: an optional slot name. Default: the basename of the current working directory.

## 1. Register and wait

- Slot directory `~/.claude/handovers/`, files `<slot>.md`, `<slot>.ready`, `<slot>.files/`.
- Find your own session name (ListAgents prints "This session is <name>") and write it with
  the current time to `<slot>.waiting`, so the old session can find you.
- If `<slot>.ready` already exists and is newer than 10 minutes, go to step 2. If it exists
  but is older, it is from an earlier handover: tell the user in one line and keep waiting for
  a new one (compare the time inside it).
- Otherwise wait for `<slot>.ready` without spending turns: use the Monitor tool with an
  until-loop on the file existing (check every 30s, time out after 6 hours). Tell the user in
  one line that you are waiting and that they can now run `/handover` in the old session.
  Do nothing else while waiting.

## 2. Load

- Read `<slot>.md` fully, and every file under `<slot>.files/` it references.
- Read the project's CLAUDE.md and run the tracker's context command (`bd prime` in beads
  repos) and `bd show` on the epic/issues the note names.
- Check the state claims cheaply: `git status` / `git log` in each worktree named, health-check
  the services named. If something differs from the note, trust what you see and say so.
- Delete `<slot>.waiting`. Rename `<slot>.ready` to `<slot>.taken` with your session name and
  time, so a second takeover cannot start on the same note.

## 3. Take over

- You are now the orchestrator. Follow the limits and decisions recorded in the note (e.g.
  max concurrent agents, models, push cadence) exactly as the old session did; do not re-ask
  the user anything the note says they already decided.
- Resume from the note's queue. Start workers with the brief files and prompt pattern the note
  gives (use the copies under `<slot>.files/`, never the old session's scratchpad paths).
- Before launching anything, send the user one short message: what you loaded, the state you
  verified, and the first things you are starting. Then carry on without waiting for a reply.

## 4. If the note is missing pieces

If the note is incomplete or contradicts the tracker in a way that changes what to do next,
do only the safe, obviously-next work and leave a clear question for the user at the top of
your next message. Never redo work the tracker marks as done.
