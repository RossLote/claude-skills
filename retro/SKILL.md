---
name: retro
description: Retrospective over one or more orchestrate runs — gathers each epic's RUN RECORD and SCHEDULE lines and per-bead close reasons from beads, and the PR's review and merge timings from GitHub, then writes a short dated report of phase ratios, second-round rates by worker type, plan drift, repeat incidents and reversed decisions, ending in the few changes it proposes to the epic and orchestrate skills and to MODEL lines. Use when the user says "/retro", "retro on <epics or dates>", "how did the runs go", or wants to tune the workflow from the record. Report only: never edits a skill.
argument-hint: "<epic-id>… | --closed-after <date> [--closed-before <date>]"
model: claude-opus-5-5[1m]
---

# Retro over orchestrate runs

The orchestrate skill leaves a RUN RECORD on every epic and a fixed close reason on every
bead so that runs can be compared. This skill is the comparison. It reads; it does not
judge code; and it never changes a skill. Its last section is proposals for the user.

## 1. Gather

```
python3 ~/.claude/skills/retro/gather.py <epic-id>…
python3 ~/.claude/skills/retro/gather.py --closed-after 2026-10-02 --closed-before 2026-10-04
```
from the repo root. It prints, per epic, the RUN RECORD and SCHEDULE lines, a per-bead
table from the close reasons (worker, rounds, respawn, minutes, gate, round2, mismatch,
unconfirmed) and the PR's created, first-review and merged times; then across epics: a row
per run, second-round and respawn rates by worker type, and INCIDENTS tags with counts. An
epic from before the run record has a TELEMETRY paragraph instead: it is printed raw, read
it by hand and say so in the report.

## 2. Read for causes, not totals

For every number that stands out, open what is behind it before writing: the bead whose
`round2` names the correction, the SCHEDULE line that re-cut a group, the DECISION that
was reversed, the INCIDENTS tag that recurs, the PR thread that cost a round. The question
is always which upstream text would have prevented it: a bead's acceptance, a READ FIRST
precedent, a SEQUENCING group, a MODEL line, or a rule in a skill.

## 3. Report

Write `<snapshot folder>/retro-<date>.md`, where the folder is the one CLAUDE.md names for
dated snapshots (else the scratchpad, and say so). Under 400 words plus tables:

1. **Runs**: a row per epic: hours, beads planned and added, workers, second rounds,
   respawns, review findings confirmed, review-round findings, CI failures.
2. **Where the time went**: phase hours as a share of the run, from PHASES.
3. **What went wrong more than once**: INCIDENTS tags and round2 reasons that repeat.
4. **Plan drift**: added beads by source (review, Copilot or human, simplify,
   orchestrator), SCHEDULE lines, reinterpreted bar steps, reversed decisions.
5. **Proposals**: at most five, each one sentence naming the skill, agent or line to
   change and the number above that justifies it, ordered by expected saving.

Final message: the report path and the proposals verbatim. Do not edit any skill; the user
decides which proposals to take.
