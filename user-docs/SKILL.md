---
name: user-docs
description: Write task-based user documentation for an app, one set per kind of reader, by checking every sentence against the code and capturing every screenshot with a Playwright script on a throwaway stack. Because an honest guide must describe what the product really does, the same pass surfaces bugs, missing features and bad copy. Plans the work with the user and files a beads epic for /orchestrate (authoring guide + glossary, capture harness and demo world, freshness checks, one writer bead per audience and area). Afterwards, "/user-docs triage" turns what the writers found into a follow-up epic. Use whenever the user wants user guides, help docs, how-to articles, in-app help, a user manual or onboarding docs for an app's users, says "document the app" or "/user-docs", or wants to shake bugs out of an app by documenting it. Not for code comments, API reference, developer READMEs or architecture docs.
model: claude-opus-5-5[1m]
---

# Document an app for its users, and find its bugs doing it

The writers follow one rule: **a guide describes what the product does today, for one kind of
reader, and every claim in it is checked against the code and carried out by a script.** That
rule is also why this finds bugs. A writer can't document the **Top up** button if there isn't
one. They can't quote a friendly error that is really a 500. They can't write "only admins can"
when only the browser enforces it. Each mismatch like that becomes a *finding*.

On the first app this ran on, it produced 58 guides and 129 screenshots. It also produced 17
findings, which became a 25-bead follow-up epic. One finding was a feature whose API shipped
with no UI. The bead had been closed on the strength of the API, and every e2e test set up
that state through an admin shortcut, so nothing had noticed. `references/worked-example.md`
has the full worked example.

The work happens in two separate sessions:

1. **Plan** (now, with the user): survey the app, settle decisions, and file a **docs epic**. The
   user then runs `/orchestrate <epic>`. Writer agents write the guides and capture scripts, and
   record findings without fixing them.
2. **Triage** (`/user-docs triage [epic]`, after the docs PR): go through the findings with the
   user, get their decisions, and file a **follow-up epic** that fixes the product and updates
   the guides to match.

If the user names a docs epic that has landed, or there is a findings file, run Triage.
Otherwise run Plan.

The skill runs through beads and `/orchestrate`. If the project has no `.beads`, ask whether to
`bd init`. If the answer is no, say the skill can't run as designed, and stop.

## Plan

### 1. Survey before asking anything

Read enough that your questions come with evidence and a recommendation. Use Explore agents in
parallel for a big app.

- **Who signs in**: roles, permissions, and where the server enforces them (not just where the
  UI hides things). Group people into **audiences**: sets of people who get the same docs. For
  example, a customer organisation's admins and operators usually share one set. Note anyone who uses the app but
  won't read these docs.
- **What they can reach**: nav, routes and page list per role, and the actions on each page
  (buttons, forms, dialogs).
- **Plan docs and specs**, for vocabulary and intended rules. These are *not* the truth; the
  code is.
- **The test stack**: is there an e2e setup with a throwaway database, seed data, sign-in
  helpers (2FA included), fake third-party providers and ways to fake time or external systems?
  The capture scripts are built on it. If none exists, the harness bead has to build one, and
  it becomes the biggest cost in the epic. Say so.
- **Existing docs**, and how the repo runs things (`make` targets, gates in CLAUDE.md).

Then draft a **task inventory**: for each audience, the jobs they come to the app to do, one
article per task, titled as a command ("Book a candidate onto an exam"). Include "Getting
started" for each audience, and the account topics everyone shares: sign in, password, 2FA,
switching product. Build the inventory from what each role can reach, not from the plan. A task
the plan promises that the role can't reach is already a finding.

### 2. Settle decisions with the user

Ask with AskUserQuestion, recommendation first, and ask only what the survey couldn't answer:

- **Where the docs live**: in-app help, Markdown in the repo, or a docs site. See
  `references/delivery.md` for what each needs and when to recommend it. The key question is
  whether some readers must *never* receive another audience's docs. If so, filtering has to
  happen on the server, screenshots included.
- **Audiences**, including who is *not* a reader.
- **The task inventory**: show it grouped by audience so they can cut or add items.
- **Language and naming**: language variant, product and platform names, words to avoid.
  These seed the glossary.

Don't ask about things with a sensible default. Use the defaults from the references (a 1280×800
frame, WebP, one task per article, "Why can't I…?" sections) and say what you chose.

### 3. File the docs epic

Invoke the `epic` skill and give it this shape. Use the bead list in
`references/worked-example.md` as the template.

**Foundation beads.** They can run in parallel where their TOUCHES are disjoint.

1. **Authoring guide and glossary** in the repo, from `references/authoring-guide.md` with
   every `<…>` filled in. The glossary comes from the plan docs and the live UI; where they
   disagree, the UI wins. The guide includes the writer method and the finding format, because
   the writer beads work from it. Add a standing rule to CLAUDE.md: *when a UI change alters a
   label, flow or rule that a guide describes, update the guide and recapture that area.*
2. **Capture harness and demo world**, from `references/capture-harness.md`.
3. **Delivery**, only for in-app help or a docs site, from `references/delivery.md`. It includes
   the boundary test that shows a lower-privileged reader can't fetch another audience's
   article or screenshot.
4. **Freshness checks**: tests that fail when a screenshot is missing or unused, a link or route
   is broken, frontmatter is invalid, or titles are duplicated. They join the normal unit gate
   so the docs can't quietly go stale.

**Writer beads**: one per audience × area, each about 6–12 articles (the first run's were: product A
for customer staff, product A for the partner, product A for admins, product B for admins,
and the shared platform pages). Each bead owns its slice of the articles folder and its own capture script, so writer
beads can run in parallel. Each writer bead's acceptance:

- Every article on its list is written to the authoring guide, with the task list copied into
  the bead.
- Its capture script runs clean on a fresh stack and produces every screenshot its articles
  show.
- The freshness checks pass.
- `<findings-dir>/<bead-id>.md` exists in the finding format. If there were no findings, it
  says "No findings".
- It changes no product code. Test helpers, seed data and capture-world setup are allowed.

**Final bead: consolidate findings.** Merge the per-bead files into one `FINDINGS.md`. Remove
duplicates, combine findings that share a cause, sort by kind and severity, and link it from
the PR body.

**The epic's CHANGE PROTOCOL must say this, word for word.** It overrides `/orchestrate`'s rule
that a discovery becomes a bead in the same epic:

> Findings are this epic's second deliverable, not work for it. A writer who finds the product
> wrong documents what it does today, records a finding, and carries on. Nobody fixes product
> code, adds a bead to fix a finding, or writes a guide describing intended behaviour instead
> of actual behaviour. The orchestrator does not decide findings.

Here's why. On the first run, most fixes needed a product decision from the user, such as freezing
issued invoices or whether to cap deductions. A docs epic that fixed things as it went would
have made those calls without the user, and left the guides describing a moving target.

The **acceptance bar** for the docs epic is a demo script. For each audience: sign in, open the
docs, search for a task, open the guide, and see its screenshots. Where filtering applies, show
the reader can't reach another audience's article. Then run the capture command from a clean
stack, and show the freshness checks pass.

After filing, tell the user the epic id, the number of writer beads, and the next step:
`/orchestrate <epic>`, then `/user-docs triage` once the PR is up.

## Triage

1. **Read** `FINDINGS.md` and the guide paragraph each finding points to. The writer already
   checked each one, so only spot-check the ones that surprise you, against the code.
2. **Group** findings that share a cause (the first run folded several wording items into one copy
   bead). Sort them into four kinds:
   - **Bug**: the product does something wrong. Examples: a 500 instead of a message, a rule
     enforced only in the browser, issued data that changes afterwards.
   - **Gap**: something is missing, such as a UI, notification, audit row or admin tool.
   - **Copy**: wording, spelling, raw codes on screen, internal jargon.
   - **Housekeeping**: dead code, stale types, test tooling.
3. **Show the user a table**: id, kind, severity, and one plain sentence per finding. Then ask
   about every finding that needs a product decision, with your recommendation first. Record
   each answer as a decision with the date and the user as its source. List what's out of
   scope.
4. **File the follow-up epic** with the `epic` skill. It needs:
   - **Fix beads**: each fix bead also updates the guide paragraphs that describe the old
     behaviour, and names those articles in its acceptance.
   - **A decision-record bead**: writes the decisions into the plan docs and deletes the
     findings files, since the beads now hold them.
   - **A recapture bead**, after every code bead, that retakes every screenshot once. It
     touches selectors only.
   - **The acceptance walkthrough.**
   - **A precondition**: the docs epic's PR is merged.
5. Tell the user the follow-up epic id and how many beads it has, by kind.

## References

- `references/authoring-guide.md`: the template for the repo's authoring guide. Covers article
  format, style, audience blocks, screenshots and links, **the writer method**, what to look
  for, and the finding format.
- `references/capture-harness.md`: the Playwright capture project, `shoot()`, the demo world,
  and the freshness checks.
- `references/delivery.md`: in-app help vs Markdown in the repo vs a docs site, and what each
  needs.
- `references/worked-example.md`: a docs epic and its follow-up epic, bead by bead, and what
  the findings turned out to be.
