# Authoring guide template

Copy this into the repo as the docs' README: `<docs-root>/README.md`. Fill in every `<…>`, delete
the sections that don't apply, and keep the rest. Writer beads work from this file, so it has to
stand on its own without this skill.

---

# <Product> user docs: authoring guide

These pages are the help that <readers> read at <where: /help in the app | docs/user/ | the docs
site>. <One sentence on filtering, if any: "The server sends each person only the articles
written for them; <audience> never receive an <other audience> article, paragraph or
screenshot.">

```
<docs-root>/
  articles/<area>/<slug>.md   one task per file
  screenshots/<name>.webp     written by `<capture command>`, committed
```

`<test command>` checks the whole library. It fails on invalid frontmatter, a missing or unused
screenshot, a link to an article that doesn't exist, a route the app no longer has, and a
duplicate title.

## Readers

| Audience | Who | Sees |
| --- | --- | --- |
| `<id>` | <roles, spelled out, and "one set" where roles share docs> | <which articles> |

<Who is not a reader.> <Whether admins can preview another audience's view.>

## An article

```markdown
---
title: <Do the task>             # the task, as a command
summary: <One sentence.>
area: <area>                     # must match the folder
audiences: [<id>, <id>]
routes: ["/things/[id]"]         # pages this explains; quote them, since [id] is YAML syntax
keywords: [<words people type>]  # include synonyms and words the text avoids
order: 20                        # position within the area, lower first
---
```

- **One task per article.** The title is the task as a command: "Book a candidate onto an
  exam", not "Booking" or "How do I book…?".
- **`keywords`** are extra words people search for: synonyms, spelling variants, and the
  planning-doc words the text avoids.
- **`routes`** use the app's page paths. The freshness checks fail when a path no longer
  exists.

### A step only some readers see

```markdown
<!-- audience: <id> -->
<Only these readers see this paragraph.>
<!-- /audience -->
```

Put the markers on their own lines. They can't be nested. To list several audiences, separate
them with commas.

### Screenshots and links

- `![<what the picture shows, for screen readers>](shot:<area>-<page>-<what>)`
- `[<link text>](help:<area>/<slug>)`. If the reader can't see that article, the link becomes
  plain text.
- Screenshots come only from `<capture command>`. Never edit one by hand: change the capture
  script and run it again.

## Style

- **<Language variant>** spelling. Money as <£283.00>. Dates as <10 July 2026>.
- **Second person, present tense, short sentences.** "Select **Withdraw**. The money held for
  them goes back to your available balance."
- **Name controls exactly as the screen shows them**, in bold. Where the nav label and the page
  heading differ, give both once: "Open **Arrangements** (the page is called *Access
  arrangements*)".
- **Say who can do it** when not every reader can.
- **Say what can't be undone** before the step that does it.
- **Quote the error messages** people will actually see, and say what to do next.
- Use numbered steps for a procedure and a short paragraph for background. Add a **"Why can't
  I…?"** section for the common refusals.
- **No internal names**: no ticket ids, endpoint paths, table or enum names, or developer words
  like "tenant", "DTO" or "record".

## Glossary

Use the word in the first column. **The screens win over the planning documents wherever they
disagree.**

| Say | Meaning | Avoid |
| --- | --- | --- |
| <term> | <plain meaning, including who sees it> | <words not to use> |

## How to write a guide: the method

A guide describes **what the product does today**, for **one kind of reader**, and every claim
in it is checked. This is what makes the guides trustworthy. It is also how the docs pass finds
bugs.

1. **Start from the screen, as the reader.** Sign in as the audience's person in the capture
   world. Do the task the way a reader would. Copy every label, heading and message exactly.
2. **Trace every claim to the code.**
   - *Words on screen*: grep the source for each quoted string. If it isn't there, you are
     looking at an old build or quoting from memory.
   - *Rules* (who can, limits, deadlines, amounts, what can be undone): find the **server-side**
     check and describe that. A rule only the browser enforces is a finding.
   - *Messages*: find where each error is produced. Trigger it in the capture script when you
     can, quote it word for word, and say what to do next. "Internal server error", "Request
     validation failed" and any raw code are findings.
   - *Consequences*: what changes afterwards (balances, emails, audit rows, what other roles
     now see). Check that it actually happens. Don't assume the email is sent.
3. **Walk the unhappy paths.** Each refusal a reader will meet (permission, validation limits,
   deleting something in use, not enough money, time windows, already-done states) goes into
   "Why can't I…?", and the capture script triggers it.
4. **Check every other audience's view of the same page.** For each control: who sees it, and
   can they use it? A control shown to someone the server will refuse is a finding. So is a
   control that's missing for someone who needs it.
5. **Compare against the plan, and write the product's truth.** The plan docs give intent and
   vocabulary. When the product differs, the guide describes the product and you record a
   finding. Either side could be wrong, and the user decides which.
6. **When the truth is bad, write it down honestly and carry on.** Describe what happens today
   and the workaround ("There is no payment button at the moment. To add funds, contact…").
   Record a finding. Never describe intended behaviour, never skip over the problem, and never
   fix product code in a docs bead. Changing selectors, test helpers and capture-world setup is
   fine.

### What to look out for

These are the kinds of finding a docs pass turns up:

- A friendly refusal that reaches the user as a 500, because the database driver reports the
  error differently from what the code checks for.
- A rule enforced only in the browser, such as "can't demote the last admin", which only
  worked when the list fitted on one page.
- Issued documents rebuilt from live settings, so renaming something rewrites invoices already
  issued.
- Money or stock checks missing on one path, such as a manual deduction that can make a
  balance negative.
- A **backend with no UI**: an API that was built and closed without any page calling it,
  hidden because the tests set up state through an admin shortcut.
- Controls and hints shown to roles that can't use them, or that point somewhere unhelpful
  ("Top up" when there is no top-up button).
- Actions that should notify someone or be audited, but aren't.
- Raw enum codes, amounts in pence, ISO dates or field-less validation errors on screen.
- Internal jargon, inconsistent spelling, and the wrong brand in emails.
- Layout that breaks at the capture viewport (clipped action cells, wrapping tabs).
- Dead states and stale helpers: enum values no code path sets, and permission helpers that
  disagree with the server.
- Test tooling that reaches around the app (raw SQL through `docker exec`) and breaks when the
  environment changes.

### Recording a finding

Each writer bead writes `<findings-dir>/<bead-id>.md` and adds one entry per finding:

```markdown
## F<n>: <the claim, one line>
- Kind: bug | gap | copy | housekeeping
- Severity: high | medium | low   (high = wrong data or money, permission or security, blocks a task)
- Audience / area: <id> / <area>
- Today: <what happens now; what the guide says>
- Why it looks wrong: <what a reader would expect, and the source: plan doc §, another screen, common sense>
- Evidence: <file:line>; "<exact message>"; shot:<name>; <steps to see it>
- Guide text: articles/<area>/<slug>.md § <heading>
- Decision needed: no | yes: <the question the user must answer>
```

If a bead has no findings, write "No findings" and list what you checked.

### What a reviewer checks on a writer bead

- Pick three claims at random and trace each one to the code yourself.
- Every screenshot an article uses comes from the capture script, and the article's steps
  match what the script does.
- The unhappy paths are covered and their messages are quoted.
- There's no product-code change, and no guide describes behaviour that doesn't exist yet.
- The findings file is present, and each finding has evidence and a guide-text pointer.
