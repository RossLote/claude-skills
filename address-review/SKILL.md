---
name: address-review
description: Work through the review of a pull request after /orchestrate has opened it — every human and Copilot review thread is read, verified against the code, and either fixed as a bead under the epic through the orchestrate per-bead loop and pushed, or answered with the reason; one re-review is requested per round; CI is watched; and once the PR is merged the epic is closed, reversed decisions reach the plan doc, and the run record gets its review line. Use when the user says "/address-review <pr>", "handle the review comments", "the PR has comments", or "it's merged, close it off".
argument-hint: "[<pr-number>] [--epic <id>]   defaults: the current branch's PR, the epic named by the branch"
model: claude-opus-5-5[1m]
---

# Address a pull request's review

/orchestrate stops at CI green on an open PR. What follows, the reviewers' comments and the
merge, had no skill, so it was done by hand and nothing from it reached the record. This
skill is that stretch. It never pushes to `<base>`, never force-pushes, never merges, and
never asks a reviewer to change a verdict: it fixes or it explains.

Inputs: the PR number (default: `gh pr view` on the current branch) and the epic id
(default: the `<id>` prefix of a `<id>/<slug>` head branch). Work happens in a worktree on
the PR's head branch, `../<repo>-<epic-id>-review`, made as the orchestrate skill's Setup
step 2 makes one.

## 1. Read every thread

```
gh api repos/{owner}/{repo}/pulls/<n>/reviews
gh api repos/{owner}/{repo}/pulls/<n>/comments        # inline threads
gh api repos/{owner}/{repo}/issues/<n>/comments       # the conversation
```
Collect every comment you have not answered, grouped by reviewer and review id. A human
reviewer outranks Copilot where they disagree. Verify each one against the code before
deciding anything: open the file, read the function, run the one test that would settle
it. A reviewer is often right and sometimes reading a stale diff.

## 2. Decide each, in writing

One of three, and every thread gets a reply either way, through
`gh api -X POST repos/{owner}/{repo}/pulls/<n>/comments/<id>/replies -f body=…`:
- **Real**: `bd create` a bug under the epic, titled from the comment, description
  `Review thread <id> by <who>: <what is wrong, file:line, the fix>`, with READ FIRST,
  TOUCHES and a MODEL line like any bead. Reply once the fix is pushed, naming the commit.
- **Not real**: reply with the reason in one or two sentences, citing the line that rules
  it out. Never close a real finding as not real to save a round.
- **Out of this epic**: file it in one line under the epic that owns it and reply with the
  id. A human request that reverses a DECISION is real: the reversal goes in the epic's
  DECISIONS, the plan doc the epic cites, and the fix bead, as the CHANGE PROTOCOL says.

## 3. Fix as beads, push once per round

Run the orchestrate skill's **Per-bead loop** for every real finding: claim, prompt, spawn
`worker-sonnet` or `worker-opus` by the bead's MODEL line, review the diff, commit in the
worktree, close with the fixed close reason. Beads whose TOUCHES are disjoint run together,
at most three. Then the full gate once, one push to the head branch, and a reply on each
fixed thread naming the commit. Request a re-review from each reviewer who left a real
finding, once per round; Copilot is never asked twice on one PR. Then watch CI as the
orchestrate skill's End of epic step 8 says.

Append to the epic under RUN RECORD, one line per round:
`REVIEW_ROUND n=1 by=human,copilot findings=5 fixed=4 declined=1 out-of-scope=0 commit=<sha>`

## 4. Once the PR is merged

Invoked after the merge, or when `gh pr view --json state` turns merged: `bd close` the
epic and every bead this skill made; if beads syncs through a committed file, say so in the
final message so the user takes it onto their next branch. Remove the review worktree, then
`git pull --ff-only && git fetch --prune` in the main checkout. Nothing else is left locally.

Final message: `Blocked on you:` first (a reviewer's request that needs a decision only the
user can make, or `nothing`); then per reviewer: fixed, declined and out of scope, with
thread links; the CI outcome; and whether the PR is merged or awaiting merge.
