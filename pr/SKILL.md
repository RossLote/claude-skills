---
name: pr
description: Open (or rewrite) a pull request that one time-poor reviewer can judge without reading the diff. The first three lines are the door (two-way or one-way), what to do before merging, and the undo recipe; then what changed with one diagram, evidence matched to the kind of change (a slowed-down chaptered walkthrough, a before-and-after of the screen, or the test that failed and now passes), a review guide of at most ten places linked into the PR's own diff with what to check at each, the technical breakdown, the choices made unattended and the verification record. Reads every migration and data script as SQL before calling a door. Use whenever a branch is ready for review and a PR is to be opened or its description rewritten — "/pr", "open the PR", "write up the pull request", "make this reviewable", "is this a one-way door", "what's the blast radius" — and as the pull-request step of /orchestrate.
---

# Write a pull request the reviewer can judge without reading the diff

The reviewer is one person with about twenty minutes, usually the person who ran the agents.
They will not read a diff of several thousand lines and should not have to: you wrote it, or
you ran the agents that did, so you know which door this is, what a revert does not put
back, and which fifty lines out of ten thousand deserve a human eye. Put that on the PR,
actionable things first. Everything else earns its place by changing what the reviewer does
next; otherwise it goes in a closed `<details>` at the end, or it goes.

## Inputs

- `<base>`: the branch the PR targets. The argument if given, else the branch CLAUDE.md
  names, else `main`. The head is the current branch; never open a PR from `main`.
- `--epic <id>`: the beads epic, if any. Default: the `<id>` prefix of a `<id>/<slug>` branch.
- `--demo <dir>`: where the walkthrough recording, pictures and `chapters.json` live.
  Default: `docs/demos/<epic>/` when it exists. No recording means no video.
- `--screenshots`: also attach the per-step pictures, in a closed `<details>` at the very end.

A caller such as `/orchestrate` passes these inline. Standalone, work them out and say in
the final message what you assumed.

## 1. Gather before writing a word

The body quotes real output, never estimates. From the repo root:

```bash
BASE=<base>; HEAD=$(git rev-parse HEAD); REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
git fetch origin "$BASE"
git diff --stat "origin/$BASE...HEAD" | tail -1      # headline numbers
git diff --name-status "origin/$BASE...HEAD"          # A / M / D / R per file
git log --oneline "origin/$BASE..HEAD"                # what landed, in order
bash ~/.claude/skills/pr/buckets.sh "$BASE"           # files and lines per bucket, and the test lines to read
```

Then read: **the whole product-code diff** (you cannot rank what you have not read);
**every migration** and every seed, backfill or pre-deploy script that changed, as SQL, not
the ORM's summary; **every config and deploy file** (CI, Dockerfiles, infrastructure code,
`.env.example`, `package.json`); **CLAUDE.md**, for the hazards the project names and how
and when migrations run. For the buckets you will not read line by line, confirm with one
command: regenerate generated code and `git diff --quiet`; picture paths belong to the
screenshot pipeline; the tests add no `.skip` or `.only` and every removed assertion was
replaced (`buckets.sh` prints the candidates; read each).

## 2. Which door

Two questions: **does reverting the merge put everything back?** and **what is the worst
this does to data, people, money or a security boundary if it is wrong?** Answer both from
what you read. Note every signal that fires; the body names them.

| Signal | Look for | Door |
| --- | --- | --- |
| Schema, additive | `CREATE TABLE`, `ADD COLUMN` nullable or defaulted, `CREATE INDEX` | two-way; the object stays behind after a revert |
| Schema, constraining | `SET NOT NULL`, `ADD CONSTRAINT`, unique index on existing rows (the deploy stops if live rows violate it) | two-way; the old code may be refused writes it used to make |
| Schema, destructive | `DROP`, `RENAME`, narrowing `TYPE`, enum value removed | one-way |
| Data moved or rewritten | `UPDATE`, `DELETE`, `INSERT … SELECT` in a migration; backfill, seed or pre-deploy scripts on real rows | one-way |
| Deletion paths in code | delete, purge, cascade, storage-object removal reachable on deploy or first use | one-way |
| Auth, sessions, permissions | auth config, cookie and session options, guards, roles, password or MFA flows | two-way; one-way if a check is loosened or everyone is signed out |
| Money | payments, refunds, invoices, prices, currency arithmetic, rounding | one-way if what is charged or recorded changes |
| Outbound | email, SMS, webhooks, third-party calls, schedulers, queues | two-way if inert until used; one-way if it fires on deploy or for existing users |
| Untrusted input | HTML rendered, uploads, raw SQL, deserialisation, open redirects | one-way if the untrusted thing is newly rendered or executed |
| Deploy and config | a variable the app needs at boot, Dockerfile, CI, infrastructure code, pre-deploy command | two-way, with a before-merging step |
| Dependencies, shared code, removals | major bumps and new runtime dependencies; packages many apps import; deleted pages, endpoints, settings | two-way, named |
| Named hazards | whatever CLAUDE.md calls a hazard | named, even when it looks harmless |
| Not confirmed | any of the above you could not check | "one-way until you confirm X", naming where to look |

- **Two-way door**: reverting the merge restores behaviour. Things may outlive it (an unused
  column, a set variable, a sent email) and each is named.
- **One-way door**: a revert does not restore the previous state. Something was dropped,
  rewritten, sent, charged, registered or invalidated; only a snapshot or a forward fix
  brings it back.
- The door is the worst signal, never an average. Do not inflate: a routine PR says
  "**Two-way door.** Revert and redeploy puts everything back." and moves on.

### Migrations and data scripts, one by one

One line each: the file, what it does in plain words, its class (**additive**,
**constraining**, **destructive**, **data-moving**) and what a revert leaves behind. When
they apply, also: when it runs and whether the old build survives the window in which it
runs against the new schema; whether it locks a large or busy table (`ALTER TABLE` takes an
exclusive lock; `CREATE INDEX` without `CONCURRENTLY` blocks writes; say so if you do not
know the table's size); what is left if it fails halfway; and that the tool's diff command
(`prisma migrate diff` for Prisma) reports nothing pending.

### Before merging, and undo

**Before merging** is a checklist of only what follows from a signal: take a database
snapshot (name the project's mechanism); set the named variable on the named service; merge
at a quiet time because a hot table locks; tell a named person because real people will
receive something. A two-way door with nothing to do says "Nothing."

**Undo** is a recipe, not a reassurance: "Revert the merge commit (`git revert -m 1 <sha>`)
and let it deploy", then the manual step if any (unset the variable; drop the unused column
when convenient) or "nothing else". One-way: the same, then one line per thing the revert
does **not** put back and how it comes back: from the snapshot taken before merging, by a
forward migration you name, or not at all.

## 3. What changed, in one picture

One diagram, only when there is a mechanism to draw, under the two or three sentences of
What changed. Pick the smallest view that makes the point, and show what changed, never the
whole system:

- a flow across apps or services: a mermaid sequence diagram (GitHub renders a
  ` ```mermaid ` block);
- a change to a shape that already exists (a call tree, a component tree, a file layout, a
  state machine): a diff-sketch in a ` ```diff ` block, `+` and `-` only on the lines that
  changed;
- a schema change: the tables and columns touched, as a short tree or diff.

Under about twenty-five lines. A wording or styling pass gets no diagram; say so in a clause.

## 4. Evidence, by the kind of change

Show the proof the change has, not every kind of proof.

- **A visual change to an existing screen**: before and after of the same screen in a
  two-column table. The before is the user-guide picture already in git on the base branch
  (`git show "origin/$BASE:<path>" > before.png`); the after is the retaken one. Attach
  both. No guide picture: say so and use the video.
- **A new feature or a flow**: the walkthrough video, slowed down, with a chapter per
  acceptance-bar step so the reviewer scrubs to the one they care about. Chapters come from
  `<demo>/chapters.json`, written by the walkthrough fixture (`n`, `title`, `ms`); render
  each as `m:ss | n. title`. No chapters file: `bash ~/.claude/skills/pr/chapters.sh <demo>`
  derives them from the original `.webm`'s times and you mark them approximate; if that
  fails too, list the steps with no times and say why. Never space them evenly. A recording
  made at full speed (chapters a second apart, two at 0:00) is re-recorded with the repo's
  recorded-walkthrough target (`make e2e-demo id=<epic>` here) before the PR is opened.
  Attach only the mp4 (ffmpeg from the webm). No gif. GitHub's player has no chapter menu;
  the table is for scrubbing by hand, and the body says so once.
- **A behaviour fix**: the test that failed before and passes now, as its name and the
  assertion, a few lines in a code block.
- **An internal rewrite with nothing to see**: no video. The diagram and the gate counts in
  Verification carry it; say that in one line.

Per-step pictures are attached only on `--screenshots`, in a closed `<details>` at the end.

## 5. Review guide

At most **ten** places, each about **forty lines**, together readable in about twenty
minutes, ranked: anything that fired a signal, then security boundaries, then judgment calls
the spec left open, then the first instance of a pattern others copy, then shared code with
many callers, then anything subtle (dates and time zones, money arithmetic, pagination,
concurrency, locale). More than ten after honest ranking means the PR should have been
split: keep ten and say so in the final message. Do not pad a small PR to ten.

Each link opens the PR's own **Files changed** tab at that file with the lines highlighted,
so the reviewer sees the diff, not the whole file. The anchor is the SHA-256 of the path
and `R` lines are the new side:

```bash
bash ~/.claude/skills/pr/links.sh link <path> <from> <to>    # prints the link, with PR_N for the number
```

GitHub renders at most 300 files in one diff and loads 400 lines of a file's diff before
asking for the rest. When the PR has more files than that, or the file's diff is longer,
also give the blob permalink (`blob/$HEAD/<path>#L<from>-L<to>`) and say why. The number is
only known once step 7 creates the PR, so entries carry `PR_N` and `links.sh fill` replaces it.

```
N. **<what it is, in words>** — `<kind>` [<path>:<from>-<to>](<link>)
   What it does in one sentence. **Check:** one thing the reviewer can confirm by looking.
```

Kinds: `risk` (fired a signal), `security`, `judgment` (names the choice in Choices made
for you), `new pattern`, `fan-out`, `subtle`. "Check" is a lookable fact ("the iframe has
`sandbox` with no `allow-*` and the HTML never reaches `srcdoc` unsanitised"), never "make
sure this is correct". Then **Skim-safe**: one line per remaining bucket with the reason it
needs no reading and how you confirmed it.

## 6. The body

Plain words; file paths only in the review guide; counts in tables or on their own line.
Everything above the appendices in about eighty lines. A blank line after every
`<summary>` or GitHub will not render the markdown inside. The worked example is in
`EXAMPLE.md` next to this file.

```
**Two-way door.** <the clause that decided it; what outlives a revert, if anything>
**Before merging:** <the checklist, or "Nothing.">
**Undo:** <the recipe>

## What changed
Two or three sentences in product terms, then the one diagram from §3, if any.

## Evidence
<one of §4: the before/after table; or `![walkthrough video](<demo>/walkthrough.mp4)` with
the `| Time | Step |` table; or the test; or the one line>

## Signals
<only those that fired, one bullet each, in this order: Schema (one line per migration, from
§2), Data, Auth, Money, Outside the system, Deploy, Shared code, Removed, Not confirmed>
Checked and clear: <the rest, by name>.

## Review guide (about <n> minutes)
<+added / −removed across <files> files; <n> lines of product code, the rest is …; map at the end.>
1. …
Skim-safe: …

## Technical breakdown
One line per mechanism, grouped by app or package, naming the mechanism, not the files. About
ten lines at most; end with "Removed: …" when anything a user could see or call is gone.

## Choices made for you
Only one-way choices and those where the build follows a DECISION over the spec, each as
"<choice> over <alternative>, because <reason>". The rest go in the first appendix.

## Verification
Walkthrough: <n> steps passed, video above. (or: not applicable, internal change)
Full gate: <what ran, with real counts>.
Simplify / review: <passes, findings fixed, refuted>.
Done means: every line ticked; evidence in the appendix.
Not confirmed: <what, where you looked>. (omit if nothing)

<details><summary>Other choices</summary> … </details>
<details><summary>Diff map: <files> files by bucket</summary> | Bucket | Files | Added | Removed | … </details>
<details><summary>Done means, line by line</summary> - <line> — <evidence> </details>
<details><summary>Screenshots, one per step</summary> … </details>   (only with --screenshots)
```

The title is the epic's title or a one-line product summary, with the epic id in
parentheses, as the project's existing PRs do.

## 7. Open it

1. `git push -u origin HEAD`.
2. Write the body to a file in your scratchpad, then from the repo root:
   ```bash
   gh pr create --base "$BASE" --title "<title>" --body-file <file> \
     --attach <demo>/walkthrough.mp4 [--attach before.png --attach after.png] [--attach <each step picture, only with --screenshots>]
   ```
   gh 2.99 or later uploads each attachment and rewrites the body's relative paths to the
   asset URLs. Nothing under `docs/demos/` is ever committed, and neither is the walkthrough
   spec: the recording goes on the PR, the code that made it does not (user, 2026-10-13).
3. `bash ~/.claude/skills/pr/links.sh fill <n>`: reads the body back, puts the number into
   the review-guide links, edits the body in place, and fails if a `docs/demos` path or a
   `PR_N` is left.
4. No remote: publish the same report as an Artifact with the video attached, send the mp4
   with SendUserFile, and give the user the branch name.
5. Standalone, the final message is the PR link, the body's first three lines verbatim, and
   anything you assumed from Inputs. Under `/orchestrate`, that skill's final-message shape
   wins.

## 8. After a later push

After any push that adds a migration, touches a file the review guide lists, or changes a
signal in §2, redo §2 and §5 against the new head and `gh pr edit --body-file`. The diff
links follow the latest diff, so a touched file's highlighted lines have moved. A push that
changes none of those leaves the body alone.

## Checklist

- [ ] Every migration and data script read as SQL; each has its one line and class.
- [ ] The door is the worst signal; nothing unconfirmed made it two-way.
- [ ] Door, Before merging and Undo are the first three lines; each step traces to a signal;
      a quiet two-way says "Nothing."
- [ ] Evidence matches the kind of change; chapters from `chapters.json` or marked
      approximate; a full-speed recording was redone; no gif, no inline per-step pictures.
- [ ] Review guide: at most ten places, each linked into the PR's diff with a lookable
      Check; skim-safe buckets each say how they were confirmed.
- [ ] Counts in Verification and the diff map come from command output.
- [ ] `gh pr view --json body` has no `docs/demos` path and no `PR_N`.
- [ ] The diff carries no walkthrough spec, fixture, helper, page object or package; the
      throwaway spec is untracked or gone.
