---
name: brief
description: Work out what a feature is, in rounds of questions, before /epic — the user describes it freely, the agent researches the code, the plan docs and the web, then asks at most five ranked questions at a time as plain text, reads a dictated paragraph back against them, re-ranks what is left, keeps the whole record on one bead so a fresh session can resume it, and ends with a one-screen summary the epic skill can cite decision by decision. Use when the user says "/brief", "/brief <bead-id>" to resume, "brief this", "let's work out this feature", "grill me", or starts describing something to build and wants a structured path to the epic.
argument-hint: "[<bead-id>] [<feature in a sentence>]"
model: claude-opus-5-5[1m]
---

# Brief a feature

This is the step between a feature in the user's head and `/epic`. The user is both the
product owner and the developer, so every decision is theirs to make here; nobody else is
ever deferred to. Your job is to draw the decisions out in short rounds until nothing left
would change what gets built, then hand `/epic` a summary it can cite by number.

## Start, or resume

- **New brief**: let the user describe the feature in their own words, then create the
  bead: `bd create "<short title>" -t spike -l idea -d "<the problem, in their words>"`.
- **Resume** (`/brief <bead-id>`): `bd show <id>`, then recap in three lines what is
  settled and what is still open, and go straight to the next round.
- Either way, open your message with the bead on its own line, `Brief: <id> — <title>`,
  and below it the line `/rename brief <id> — <title>` for the user to paste, so the
  session is findable on resume. You cannot rename it yourself.

## Research before round one

Read what the feature touches as it stands on the base branch, the plan docs and glossary,
and earlier beads in the same area (`bd search`, `bd list -l <label>`). Search the web when
the feature leans on something outside the repo: a third-party API, a standard, a library.
Go as wide as the feature needs. Report what you looked at and the one or two findings that
change the picture in three or four lines, then start the first round in the same message.

## The question pool

Generate many more questions than you will ask, through every lens: who does this, from
which app, page and role; the data and its lifecycle; permissions; what already exists and
what this collides with; edge cases and failure; what the user sees and the words on the
screen; what is deliberately left out; rollout and existing records. A thin pool means a
lens was skipped. Drop anything a worker could decide without changing what the user sees.
Rank by fork: the question whose answer collapses the most others goes first.

## A round

- **At most five questions**, fewer when fewer would collapse more. Numbered plain text in
  the message, never the AskUserQuestion tool. Each: the question in a sentence or two,
  what it decides, and your recommended answer, so "your defaults, except 3" is a complete
  reply.
- Never say how many questions remain; the pool changes every round.
- The user answers in one paragraph. Open your next message with one line per question
  saying what you took the answer to be, re-ask only what was not covered, name in one
  line any pooled questions the answers settled, add what they raised, re-rank, and ask the
  next round.
- After every round rewrite the bead's notes (`bd update <id> --notes`) under these
  headings: PROBLEM, FOUND, DECISIONS (`D1`… one sentence each with its reason), OPEN
  (the remaining pool, ranked), ROUNDS (date, questions asked, answers in brief). That
  record is the whole state; a fresh session continues from it alone.

## Stop and summarise

Stop when every remaining question is one a worker could settle without changing what the
user sees or does, and say that is why; or when the user says enough. Then the summary,
one screen, in this order: what it is in two sentences; who uses it and where; in scope
and out of scope, an out item naming the epic that owns it; `D1`… one line each; what it
deliberately does not do. Write the same summary into the bead's description
(`bd update <id> -d`). Do not commit or push. Final line: `/epic <id>` when ready; the epic
skill promotes this bead.
