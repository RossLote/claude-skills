---
name: handoff
description: Produce a copy-pasteable handoff note summarizing the current conversation's work — state, decisions, findings, open threads — so the user can clear context and have a fresh agent continue. Use when the user asks to "write a handoff", "hand this off", wants to clear/reset context but continue, or wants a summary to give another agent/session.
---

# Handoff note

Generate a concise, copy-pasteable handoff note that lets a fresh agent with zero
conversation history pick up exactly where this session left off. The primary
source is the conversation itself — what was investigated, decided, changed, and
left open — not any particular tracking system.

## Steps

1. Review the conversation and reconstruct:
   - What the user is trying to accomplish (the overall goal/task at hand).
   - What has been done so far: files read/changed, commands run, findings,
     root-causes identified, decisions made and why.
   - What is still open or unfinished, including anything explicitly deferred.
   - Any dead ends already ruled out, so the next agent doesn't repeat them.
   - Relevant concrete pointers: file paths, line numbers, commands, error
     messages — anything that lets the next agent verify state rather than
     take the note on faith.
2. If issue-tracker items (e.g. beads) were created or touched during the session,
   include their IDs as pointers (`bd show <id>`) alongside the summary — but the
   note must stand on its own even for work that was never filed as an issue.
   Confirm current state of anything you cite (e.g. `bd show <id>`, `git status`,
   `git diff`) rather than relying on memory — state may have changed since it was
   mentioned.
3. Write the note as a single fenced code block (plain text) so it is trivially
   copy-pasteable. Structure:
   - Header: project name + date (use the current date, do not guess).
   - Goal: one or two sentences on what this session is working toward.
   - Done: what's been completed or established, tight bullet points.
   - In progress / open: what's unfinished, with enough context (files, why,
     current blocker) that the next agent doesn't have to rediscover it.
   - Next steps: a suggested order of action.
   - Anything the next agent should NOT do or re-try (dead ends, rejected
     approaches, and why).
4. Do not pad with restated instructions already in CLAUDE.md or other project
   docs (e.g. bd usage, build commands) — assume the next agent already has that
   context and can look it up.
5. Output only the fenced code block plus at most one sentence before it. Do not
   ask follow-up questions unless the scope of "current work" is genuinely
   ambiguous (e.g. multiple unrelated threads in one session).
