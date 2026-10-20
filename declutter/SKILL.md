---
name: declutter
description: Report-only simplification review. Assumes the code in scope is too complicated, spawns three read-only Opus reviewers (cut-and-collapse, reuse-and-altitude, wasted work), and produces a report ending in a bead-ready list of actionable items with ready-to-run `bd create` commands. Never edits code. Use when the user says "declutter", "what can we cut", "this feels over-built", or wants a simplification report rather than applied fixes (use /simplify for applied fixes, /code-review for bugs).
argument-hint: "[what to review: branch, PR number, or path; blank for the current branch's changes]"
---

# Declutter

Assume the code in scope is too complicated. The user likes simple code and
dislikes complicated code. The job is to find where it can be cut down or done
in a much simpler way and produce a report. **Do not change any code.** No
bug hunting either; correctness is out of scope.

## Phase 0 - Scope

Target: `$ARGUMENTS`.

- Empty: `git diff @{upstream}...HEAD` plus any uncommitted working-tree
  changes (`git diff HEAD`). If there is no upstream, diff against `develop`
  (fall back to `main`).
- A branch name: diff that branch against `develop`.
- A PR number or URL: fetch its diff with `gh pr diff`.
- A path: review the files under that path in full.

Save the diff to the scratchpad and pass it to every reviewer verbatim.

## Phase 1 - Three read-only Opus reviewers, in parallel

Launch all three via the Agent tool in a single message, each with
`model: "opus"`. Tell each it is read-only and must not edit files. Give each
the full diff, the repo root, and exactly one of these briefs:

### 1. Cut and collapse

Start from the assumption that every abstraction, option, layer, and branch is
unnecessary until proven otherwise. Look for code that could be deleted,
merged, inlined, or replaced by a plainer form that does the same job:
redundant or derivable state, copy-paste with small variations, deep nesting,
dead code, over-general helpers with one caller, config for things that never
vary. Propose the simplest version, even if it means restructuring rather
than trimming.

### 2. Reuse and altitude

Grep shared and utility modules and the files next to the change. Flag
anything that re-implements something the codebase already has, and name the
existing helper to use instead. Also check each change is made at the right
depth: special cases bolted onto shared infrastructure mean the fix is too
shallow, so propose generalising the underlying mechanism instead.

### 3. Wasted work

Flag redundant computation, repeated I/O or queries, independent operations
run one after another, blocking work added to startup or hot paths, and
long-lived closures that capture large scopes. Name the cheaper alternative,
and prefer the one that is also simpler to read.

Each reviewer returns findings as: file, line, one-line summary, what it costs
today, and the concrete simpler form. Reviewers must not invent findings; if
the code is already simple they say so.

## Phase 2 - Consolidate

When all three are back, dedup findings that point at the same code or
mechanism, and drop anything you judge a false positive. Verify each surviving
finding against the actual file before including it.

## Phase 3 - Report

Write the report to the user in two parts. Do not edit code.

### Part 1: Summary

A few sentences on the overall shape of the complexity and the two or three
changes that would make the biggest difference. If the code is already
simple, say so plainly and stop after a short list of anything minor.

### Part 2: Actionable items

One per finding, ready to become beads. Each item is self-contained so a
fresh agent can pick it up without this conversation. Format each as:

- **Title**: imperative, under 70 chars (e.g. "Inline single-use FooHelper into bar.py")
- **Type**: task
- **Priority**: P1 (big simplification), P2 (worthwhile), P3 (nice to have)
- **Files**: paths with line numbers
- **Problem**: what is over-built and what it costs today
- **Proposed change**: the simpler form, concrete enough to implement
- **Behaviour impact**: none / changes interface / drops feature. Anything
  other than "none" needs the user's sign-off before it is worked on.
- **Effort**: S / M / L

Order items by priority, then group related items and note dependencies
between them (e.g. "do after item 3").

### Part 3: bd create block

Finish with one fenced block of `bd create` commands, one per item, that the
user can review and run. **Do not run them.** Use these real flags:

```
bd create "<Title>" -t task -p <1|2|3> -l declutter \
  -d "<Problem>. Proposed: <Proposed change>. Behaviour impact: <impact>. Effort: <S|M|L>." \
  --context "Files: <files with lines>"
```

Add `--deps "blocks:<id>"` only when the user has already given an ID; for
dependencies between new items, note them in a comment above the command
instead. Keep descriptions on one line so the block can be pasted as-is.
