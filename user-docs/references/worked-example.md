# Worked example

This is the run the skill is based on, with the product's details removed. The app was a
Turborepo with a NestJS API, two Next.js portals and Playwright e2e on a throwaway Docker
stack. Its admin portal had three audiences: **admin** (the people who run the platform),
**customer** (a customer organisation's admins and operators, one set) and **partner** (an
external body with a small set of its own). It had two products, called A and B below.

## The docs epic

Decisions recorded on the epic:

- Lives at `/help` in the admin portal, not a separate site.
- Audiences: `admin` (sees everything), `customer` (admins and operators, one set), and
  `partner` (its own small set). The customers' own end users are not readers.
- Customer staff and the partner must never receive admin documentation. Filtering happens on
  the server, screenshots included.
- One source of Markdown articles tagged by audience and product, not duplicated copies.
- Screenshots are captured by a Playwright docs project on the throwaway e2e stack and committed
  to git.
- Terminology comes from the plan docs and the live UI; where they differ, the UI wording
  wins.

| Bead | What |
| --- | --- |
| .1 | Help API: article loader, audience filter, gated article and screenshot endpoints, and unit tests proving customer and partner readers never receive admin articles or screenshots |
| .2 | `/help` page: search, article view, per-page help link, admin "view as audience" filter |
| .3 | Capture pipeline: Playwright docs project, `make docs-screenshots`, fixed viewport, WebP |
| .4 | Style guide and glossary, from the plan docs and the live UI |
| .5 | Articles: product A for customer staff |
| .6 | Articles: product A for the partner |
| .7 | Articles: product A for admins |
| .8 | Articles: product B for admins |
| .9 | Articles: account, sign-in, 2FA, users, audit log (platform) |
| .10 | Freshness checks: every referenced screenshot and route exists |

The result was 58 articles and 129 screenshots across two commits (infrastructure, then content),
with all 48 capture steps passing and a browser e2e proving the boundary. The findings
weren't written to a findings file then; they were collected afterwards into the follow-up epic.
This skill adds the per-bead findings file so nothing depends on the orchestrator's memory.

## What the writers found: 17 findings

| Kind | Examples |
| --- | --- |
| Bug | A refusal that reached the screen as "Internal server error", because the driver reported a constraint error in a form the code didn't check for. Issued documents re-rendered from live settings. A balance that could go negative on one path. A protection that existed only in the browser, and only when the list fitted on one page. A hand-off to a third party that silently never happened. Controls shown to a role after the point it could use them. Layout clipped at 1280px. |
| Gap | An API that had shipped with no UI. Actions missing from the audit log. Emails that nobody sent. Admin tools missing for things admins were asked to do, such as resending an invitation or resetting 2FA. |
| Copy | US spellings, internal labels, raw enum codes and minor currency units on screen, the wrong brand in auth emails, unclear 2FA wording. |
| Housekeeping | An enum value no code path could set, a stale permission helper with zero callers, and capture tooling that shelled out to `psql`. |

A good share needed the user's decision before anyone could fix them: freeze issued documents
(which reversed an earlier call), cap a deduction with no override, lock edits while paid
applications wait, leave an expiry as it is, and never make impersonation read-only.

## The follow-up epic (25 beads)

- The original 17 ids were kept, three were narrowed, and eight were added once the decisions
  were in.
- **Fix beads** each change the product *and* the guide paragraphs that described the old
  behaviour.
- **`.18` Decision record**: writes the decisions into the plan docs so they outlast the epic.
- **`.19`** builds the UI for the API that had none. It was split out because it's a feature,
  not a fix.
- **`.24` Recapture every screenshot once**, after all code beads, touching selectors only.
- **`.25` Acceptance walkthrough**: a Playwright spec with numbered screenshots and a video.
- **Precondition**: the docs PR merged, because the guides it edits exist only there.
- **Out of scope** is listed explicitly on the epic, so the orchestrator doesn't pick those items
  up.

## Lessons folded into this skill

- The findings file and the CHANGE PROTOCOL wording exist so writers record findings rather than
  fix them, and the orchestrator can't decide them.
- "Drive what the guide says, stage the rest" plus "add a driver command, don't shell out to
  SQL" came from the `psql` capture step breaking.
- Quote routes in frontmatter: an unquoted `[id]` broke the whole library once.
- Serve screenshots as bytes: `sendFile` returned 404 for any path under a dot-folder
  (worktrees live under `.claude/`).
