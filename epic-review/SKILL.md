---
name: epic-review
description: Adversarial pre-flight of a beads epic before /orchestrate runs it — a lint script checks every bead's READ FIRST paths, TOUCHES globs, MODEL line, acceptance and deps and the parallel groups' overlap, then epic-finder agents read the beads against the repo through feasibility, completeness, size and sequencing lenses and review-skeptic agents verify each finding; typos and gaps are fixed on the beads, the rest is put to the user with a recommendation. Use when the user says "/epic-review <epic-id>", "review the epic", "is this epic ready to orchestrate", or right after /epic has filed one.
argument-hint: "<epic-id> [<base>]"
model: claude-opus-5-5[1m]
---

# Review an epic before it runs

/orchestrate runs an epic unattended, so every gap in it costs run time: an acceptance
item naming a fixture that does not exist, two "together" beads that share a file, a bar
step the API refuses. Over four runs such gaps added between 12 and 30 beads per epic and
re-sequenced one of them six times. Most were visible from the plan and the repo before
the first worker was spawned. This skill finds them then.

It checks two things: that each bead is structured as a task a trusted developer can do alone
(the outcome, the decisions that bind it, pointers, hazards, deps, coarse TOUCHES, a MODEL
line, an acceptance a reviewer can see) and that nothing in it is wrong against the repo or
the DECISIONS. It never asks for a file, a test name, a signature or a code location to be
added; those are the developer's (user, 2026-10-06). A wrong one is removed, not corrected.

Target: `$ARGUMENTS`, the epic id and optionally the base branch (default: the branch
CLAUDE.md names, else `main`). The repo is read at that base in the main checkout and
nothing is edited there. Agents are spawned by type, never `general-purpose`:
`epic-finder` to find, `review-skeptic` to verify.

## 1. Lint

```
python3 ~/.claude/skills/epic-review/lint.py <epic-id>
```
from the repo root. It prints, per bead: READ FIRST paths that do not exist, TOUCHES globs
that match nothing (a new file, or a typo: the finder decides), a missing MODEL, acceptance,
TOUCHES or READ FIRST, a bead with no dep, an acceptance `git grep … returns nothing` that
hits files outside the bead's TOUCHES or already returns nothing on the base; then every
SEQUENCING "together" group whose TOUCHES overlap, and the `planned=` line against the real
bead count. Fix what is plainly a
typo on the bead with `bd update` and say so; everything else goes to the finders as context.

## 2. Find, then verify

Group the beads by SEQUENCING: each parallel group and each chain is one group, at most
eight beads in it. Every group gets one finder per lens, `feasible`, `complete`, `size`
and `sequencing` (the cards are in `epic-finder.md`). Each prompt inlines the repo path and
base, the epic id, the epic's DECISIONS, SEQUENCING, ACCEPTANCE BAR and DONE MEANS, the
group's beads as `python3 ~/.claude/skills/epic-review/beads-text.py <ids>` prints them (the raw
fields; the rendered `bd show` drops backslashes, so a quoted grep in it looks broken when it is
not), the lint lines for them, and the lens.

Run the fleet as the adversarial-review skill runs its own: the Workflow tool with the same
`pipeline` and schemas, two `review-skeptic` agents per finding, a third on a single
evidence-backed refutation, a finding dropped only on two citations; the same shape through
Agent calls when the Workflow tool is absent. The skeptic prompt says the "branch" is the
base, that evidence is a `path:line` in the repo or a `bd:<id>` field read with `bd show --json`,
and that a finding about a quoted command is confirmed only after running the raw command. Check the
narrator line for `undefined`.

## 3. Fix the beads, report the rest

Every surviving finding is one of two things:
- **Fixed on the bead**: a path, glob, dep, MODEL line, acceptance wording or READ FIRST
  precedent corrected with `bd update` or `bd dep add`, a wrong implementation detail
  deleted; a group re-cut with
  `bd update <epic> --append-notes "SEQUENCING change (epic-review, <date>): …"`. Do this
  for anything that needs no decision from the user. A pass that rewrites a DECISIONS bullet
  or re-cuts a group with a `SEQUENCING change` line also searches every child bead's
  description, acceptance and notes (`beads-text.py` prints them) for the old wording and
  corrects each hit with `bd update`, so no bead contradicts a decision the review itself
  changed (one bead still quoted a label that the second pass had renamed away).
- **Needs the user**: a missing fixture, an API the step assumes, a decision the plan does
  not make, a bead to split. One line each, recommendation first. Never file a decision
  bead and never widen a bead to settle it yourself.

Final message: `Ready: yes | no — <n> questions`; the fixes made, one line each with the
bead id; the questions; then one line in this shape, appended to the epic under RUN RECORD
with `bd update <epic> --append-notes` as well:
`EPIC_REVIEW finders=<n> findings=<k> confirmed=<c> unverified=<u> refuted=<r> fixed=<f> open=<q>`
