---
name: epic
description: Turn a settled design conversation into a beads epic that /orchestrate can run unattended — DECISIONS, sized vertical-slice beads with acceptance criteria, READ FIRST and TOUCHES lines, explicit bd dep edges, a SEQUENCING plan naming what may run in parallel, an ACCEPTANCE BAR written as a demo script, a CHANGE PROTOCOL, and a DONE MEANS checklist whose proof is always the recorded walkthrough on the pull request. Use when the user says "file the epic", "/epic", "turn this into an epic", or asks whether an epic is written the way it should be.
---

# Write an epic the orchestrator can run unattended

You are the user's planner. This is the last step of a planning session: after it
the user leaves, `/orchestrate` runs the epic with worker agents, and the user comes back
to a pull request with a demo. Nobody answers questions mid-run. Anything you leave
implicit a worker will guess; anything you leave open the orchestrator will decide.

The standard is the worked example at the bottom. Copy its structure and density.

## Before you write anything

1. **Every decision is made now.** An epic records decisions; it does not make them. If a
   question is still open, put it to the user in this conversation and get an answer. Do
   not file decision beads and do not file an epic with an open question in it.
2. **Research lives in the project's plan docs**, cited by path and section; the `/brief`
   bead (its description and DECISIONS notes), when one exists, is where the numbered
   decisions come from. The epic is a pointer plus the decisions, not a copy of the
   research.
3. **Promote the idea bead** if one exists: close it with `--reason "Promoted to <epic>"`.
4. **Design for `/orchestrate`**, which runs one epic per run:
   - Ordering is `bd dep` edges. Concurrency is file ownership: ready beads whose
     `TOUCHES` sets are disjoint and share no hazard run at the same time, at most three
     at once, each in its own worktree. Beads that overlap run one after another.
   - Beads are **vertical slices**: schema, server, client and tests for one
     user-visible capability. The one exception is a feature spanning several apps:
     one bead lands the API contract and its tests, then one bead per app consumes it,
     and those app beads run in parallel.
   - **Size cap: about a thousand changed lines per bead.** Split anything bigger. Small
     beads land often and review fast.
   - Hazards this project names (migration journal, generated API client, shared
     integration database, hot files): read them from CLAUDE.md or the repo conventions
     doc and cite them on every bead that touches one.

## The epic bead

`bd create "<title>" -t epic -p <0-2> -l <domain-label>`, description as a pointer to the
plan sections plus scope in and out, then `bd update <id> --notes` with six sections in
this order under these headings.

**DECISIONS** — header verbatim: `DECISIONS (epic-scoped log; durable record written to
<plan doc §> in bead .1)`. One bullet per settled decision, stated as a rule, with the
reason in a half-sentence and the precedent file or plan section. Never write this list
into a bd memory. Bead .1 is always "Decision record + plan update", no code, and it
writes the plan doc.

A plan doc the repo gitignores (`project_plan/…`) exists in the main checkout and in no
worktree. A bead that names it in READ FIRST, bead .1 above all, reads and edits it in the main
checkout by its path relative to that checkout during a worktree run; this is the one exception
to "never edit the main checkout", so a worker never skips the plan doc for that rule.

**SEQUENCING** — opens with one line, `planned=<n> beads in <g> groups, sonnet=<k>
opus=<m>`, which the orchestrator's run record measures drift against. Then what runs
alone first (.1, then whatever establishes a pattern others copy), then the parallel
groups as lines like `.4 .5 .6 together — disjoint apps`, then the tail. Name every hazard
and which beads hit it. The last bead is always the walkthrough that proves the
ACCEPTANCE BAR.

**ACCEPTANCE BAR** — the demo script. Numbered steps a person can perform in the browser
with no custom code. Each step names the app, the screen, the real fixture or account, the
action, and what is visible afterwards, with exact counts. The walkthrough bead turns each
step into a screenshot, so write steps as things that can be seen.

**CHANGE PROTOCOL** — what a mid-build discovery becomes: a new bead here (a new case of
the same pattern); a bead filed against a named other epic (a shape this epic consumes but
does not own); never widened inside a bead (shared schemas, the decision list); and "if a
DECISION proves wrong, the orchestrator records the reversal here and in the plan doc and
carries on".

**DONE MEANS** — the epic's definition of done: a checklist the orchestrator ticks, with
the evidence named, before it opens the pull request. The first three lines are fixed and
appear in every epic, in this order:
- The walkthrough performs every ACCEPTANCE BAR step end to end with video recording on
  and saves one picture and a chapter per step. The spec that performs it is thrown
  away: never committed, and the pull request's diff carries none of it.
- A pull request carries that video with its chapters. The recording on the PR is the
  proof the work was done; nothing else stands in for it.
- The full gate is green: lint, unit, integration, e2e.
Then the lines this epic adds, each a thing that can be checked rather than a quality: a
migration committed with no pending diff, `makemessages` run for new strings, a plan doc
section updated, a rollout confirmed on a named environment. Every child bead inherits the
fixed part in miniature: a bead is done when its own acceptance passes, the fast gate is
green, nothing was edited outside TOUCHES, and nothing in its report is marked as not
confirmed.

**RUN RECORD** — the heading alone, left empty. The orchestrator appends its ten-line run
record under it, and every SCHEDULE line, so every epic ends the same way.

## Each child bead

`bd create "<title>" -t <task|feature|bug> -p <n> --parent <epic> -l <domain-label>`, then
`bd update <id>` with:

- **Title**: what lands, specific enough to be the commit subject.
- **Description**: the outcome and the behaviour the user sees, the decisions that bind it,
  and what is deliberately out of scope. Not the files or the code.
- **`--acceptance`**: the bead's definition of done: what a reviewer with no context can
  see or check once it has landed, with a count where a number matters. It names no test
  file or case; the developer chooses how to prove it, and the fast gate and the
  walkthrough carry the proof. Do not repeat the fixed part (fast gate, TOUCHES); the epic's DONE MEANS carries it and the
  orchestrator puts it in every worker prompt. A migration bead's acceptance says the migration
  is applied with `prisma migrate deploy` (or the repo's equivalent) to a seeded database, the e2e stack's
  or a scratch one, with the seed run after it, never "on a copy of the dev DB": a headless box
  has no dev DB, and a developer's dev DB is private data, not a fixture.
- **`--append-notes "READ FIRST: …"`**: two to five files or plan sections to open before
  touching anything, the pattern to copy, and any hazard this bead hits. For a bead that
  adds a screen, also name the specific design patterns to avoid (cream backgrounds,
  `01 / 02 / 03` section labels, pill buttons, italic accent words): "not generic" swaps
  one default for another, a named exclusion forces a choice.
- **`--append-notes "TOUCHES: <globs>"`**: the areas this bead owns, as a few globs (an
  app, a package, a folder, the one shared file it may change), not a file list. The
  orchestrator uses it to decide what runs in parallel and tells the worker not to edit outside it.
  Be honest and complete; a bead that edits outside its TOUCHES collides.
- **`--append-notes "MODEL: sonnet"` or `"MODEL: opus"`** on every bead (user,
  2026-09-29; replaces the Opus-only rule of 2026-09-24). The orchestrator spawns the
  matching worker, and a bead with no line runs on Opus. `sonnet` when the bead copies a
  pattern that already exists (a sibling file, a landed bead, or a precedent named in
  READ FIRST) and the worker's job is to follow it. `opus` when the bead is the one that
  sets a pattern others copy (the beads SEQUENCING runs alone), touches a named hazard,
  spans more than one app or package, makes a judgment call the acceptance only bounds,
  or is the walkthrough. When in doubt, `opus`: a wrong Sonnet call costs a respawn, a
  wrong Opus call costs tokens. A bead that feels like it needs a stronger worker than
  Opus is a bead that needs tightening.
- **`bd dep add <bead> <prerequisite>`** for every real prerequisite. A bead in the
  middle of a chain with no deps is a bug in the plan. A prerequisite is any bead whose
  work this one plays through, not only one whose files it edits: a bead whose acceptance
  walks a screen, a prop, a route or a helper another bead in this epic adds depends on
  that bead even when their TOUCHES are disjoint. Disjoint TOUCHES let the two run
  together, and the consumer then starts on a tree without the thing it needs (one bead
  built its screens, then waited for another bead's and merged it by hand).

**The walkthrough bead** (last): a throwaway Playwright spec that performs the ACCEPTANCE
BAR in order with video recording on (a numbered step and a picture per bar step; the
chapters file written as it runs) and leaves the recording in `docs/demos/<epic-id>/`,
which the repo gitignores. The recording is the deliverable; the spec is not (user,
2026-10-13: trainee-ui grew a ten-thousand-line e2e package around its walkthroughs and
deleted it two weeks later). The spec is written wherever the repo's e2e suite can run it,
never `git add`ed, and deleted once the PR carries the recording; nothing is committed for
it, so no fixture, helper, page object, world builder, README section, package or workflow
is added to the tree to support it, and what it needs beyond what the suite already has it
carries inside itself. Its TOUCHES line reads `none (throwaway; writes only
docs/demos/<epic-id>/)` and its MODEL is `opus`. Its acceptance is "every step passes,
every picture exists, the chapters file names every step, the video exists, and
`git status` shows nothing from the spec". The bar is never shortened to a subset or
replaced by unit tests: the recording is the first line of DONE MEANS and the proof the
pull request carries.

## How loose a bead is

A bead is a task for a trusted developer, not a plan of edits. It says what lands and why,
the behaviour the user will see, the decisions that bind it, where the pattern it follows
lives, the hazards, and what is out of scope. The developer decides the files, the code,
the tests and how to prove it (user, 2026-10-06). The more exact a bead is beyond that, the
more of it is wrong by the time a worker reads it: one epic review found a hundred
gaps, nearly all file lists, test lists and quoted strings the planner never ran.

- **Not in a bead**: a file-by-file list of edits, a list of test cases, a grep to run, a
  hook or prop signature, an internal name. Quote a string only when the brief decided it
  (copy the user sees).
- **Between beads**: a bead that consumes a pattern another bead sets says in a sentence
  what it needs from it; the setter's bead lists those needs, so the worker who sets the
  pattern knows every consumer. Neither names the implementation.
- **Product decisions are never left open**: what the user sees, what happens when
  something fails, is empty or has changed since (a resumed draft, a second run), and
  which of two behaviours wins. Those are the PO's and belong in the bead; how is the
  developer's.
- **What is exact is checked**: the few exact claims that remain (a path in READ FIRST,
  "as landed by" another epic, a fixture, an account, an endpoint, a count in the bar)
  were opened or run on the base the epic runs on before filing. Then run
  `python3 ~/.claude/skills/epic-review/lint.py <epic>` from the repo root and fix what it
  prints.

## After filing

1. Verify: `bd list --parent <epic>` shows every child; `bd ready` lists exactly the beads
   that should start first; spot-check two `bd show` for deps and notes.
2. If the session produced a rejection or a stated preference no plan doc carries, record
   that one fact with `bd remember` (under 600 chars, no paths). Never store the epic.
3. Report: epic id, bead count, the parallel groups, and any scope call you made. Do not
   commit or push.
4. Run `/epic-review <epic>` before the epic is handed to `/orchestrate`.

## Checklist

- [ ] No open questions anywhere; no decision beads.
- [ ] Research cited by path and §; idea bead closed as promoted.
- [ ] Epic notes: DECISIONS, SEQUENCING, ACCEPTANCE BAR, CHANGE PROTOCOL, DONE MEANS, an
      empty RUN RECORD; SEQUENCING opens with the `planned=` line.
- [ ] DONE MEANS opens with the three fixed lines (recorded walkthrough, PR carrying it,
      full gate) and every added line is checkable.
- [ ] Every child: acceptance, READ FIRST, TOUCHES, MODEL, deps, under ~1000 lines.
- [ ] MODEL is `opus` on every bead SEQUENCING runs alone, every hazard bead, and the
      walkthrough; `sonnet` only where READ FIRST names the pattern to copy.
- [ ] Parallel groups named in SEQUENCING and consistent with TOUCHES and deps; a bead
      that plays through another bead's screen, prop or route depends on it.
- [ ] Every bead reads as a task for a trusted developer: outcome, binding decisions,
      pointers, hazards, out of scope; no file-by-file plan, test list or internals.
- [ ] Every exact claim left (a path, a fixture, an account, a count) was checked on the
      base; `lint.py` printed nothing a worker would hit.
- [ ] Acceptance bar is numbered, visible steps with counts; last bead is the walkthrough, its
      TOUCHES line `none (throwaway; writes only docs/demos/<epic-id>/)`.

---

## Worked example (invented project, prefix `acme-`)

```
bd create "Team invitations: invite by email, seat limits, revoke, audit trail" -t epic -p 1 -l accounts
```

Notes:

> **DECISIONS** (epic-scoped log; durable record written to `plans/accounts.md` §5 in bead .1)
> - An invitation is a row, not a signed token (user, 2026-09-02): tokens cannot be revoked. The link carries an opaque id looked up server-side. Precedent: the password-reset table in `packages/db/src/schema/auth.ts`.
> - Seats are counted at accept time, never at send time. The count comes from acme-9wqz's `workspaceSeats()`; this epic never computes it.
> - Invitations expire after 14 days, checked on read, not by a job.
> - Accepting while signed in as a different user is refused, not switched (user, 2026-09-02).
>
> **SEQUENCING**
> planned=7 beads in 1 group, sonnet=3 opus=4.
> .1 alone. .2 alone (migration journal). .3 alone: it sets the action and error-shape pattern.
> .4 .5 .6 together — disjoint: `apps/web/**/members/**`, `apps/web/**/invite/**`, `packages/email/**`.
> Then .7, the walkthrough. Hazards: migration journal (.2); `packages/db/src/schema/auth.ts` (.2 only); integration DB (.3, .7).
>
> **ACCEPTANCE BAR**
> 1. Web app, signed in as `owner@acme.test` on the 3-seat workspace with 2 members: Members page shows 2 rows and an Invite button.
> 2. Invite `new@example.test` as Editor: the pending list shows 1 invitation; Mailpit shows 1 email.
> 3. Open the link in a clean profile, sign up: land on the workspace as Editor; Members shows 3.
> 4. Invite and accept `fourth@example.test`: refused with "This workspace has no seats left"; Members still 3.
> 5. Revoke it: the link now shows the revoked page.
> 6. Admin → Audit shows exactly 5 rows for this run: sent, accepted, sent, accept-refused, revoked.
>
> **CHANGE PROTOCOL**
> - A new refusal case → new bead here, same pattern.
> - Anything about seat counting → acme-9wqz owns it; file there and depend on it.
> - Never widened inside a bead: the `invitations` table shape, the error enum, this list.
> - A wrong DECISION: orchestrator records the reversal here and in `plans/accounts.md` §5 and carries on.
>
> **DONE MEANS**
> - Walkthrough runs bar steps 1–6 in order with video on; six pictures and six chapters in `docs/demos/acme-k3p1/`; its spec is thrown away and the PR carries none of it.
> - Pull request carries the video with its six chapters.
> - Full gate green: lint, unit, integration, e2e.
> - `plans/accounts.md` §5 holds the decision record (.1).
> - The `invitations` migration is in the journal with no pending diff.
> - Mailpit shows exactly the two emails the bar sends and none from the refused accept.
>
> **RUN RECORD**

A child:

```
bd create "Invitation actions: send, resend, revoke, accept with seat and identity checks" -t task -p 1 --parent acme-k3p1 -l accounts
bd dep add acme-k3p1.3 acme-k3p1.2
```

> **Description**: `packages/api/src/invitations/`: four actions over the table added by .2. `send` (admin only) inserts a row with an opaque id, frozen role and 14-day expiry and enqueues the email; a resend updates the row. `revoke` sets `revokedAt`. `accept` fails in four named ways: `seat-limit` (read `workspaceSeats()`, never compute), `expired`, `wrong-account`, `already-member`. Every transition writes one `audit_log` row. Out of scope: UI, email body (.6), seat counting.
>
> **Acceptance**: send inserts one row and queues one email; a resend leaves one row with a new id; each of the four refusals returns its name and changes nothing; every successful transition writes exactly one audit row with the actor; a plain member cannot send.
>
> READ FIRST: `packages/db/src/schema/auth.ts` (table from .2); `packages/api/src/members/actions.ts` (the pattern to copy); `plans/accounts.md` §3 (audit row shape). Hazard: integration DB.
> TOUCHES: `packages/api/src/invitations/**`
> MODEL: opus (sets the action and error-shape pattern that .4 .5 .6 copy; .4 .5 .6 are `sonnet`)
