---
name: adversarial-review
description: Runs a multi-agent find, dedupe, verify code review on whatever the user points it at — a diff, a directory, a PR, or the whole repo — using the review-finder, review-deduper and review-skeptic agents (Opus 5.5, high effort). Finders read every hunk in the worktree and grep for the rule it re-implements; one deduper folds findings that describe the same bug into one before any skeptic runs; skeptics may refute only by citing the line that rules the failure out, an uncertain verdict keeps the finding alive, and a split pair is a tie the fixer settles. Files every surviving finding as a beads issue, marked confirmed, unverified or tie, and writes a copy-pasteable handoff note for the next agent. Use when the user asks for "adversarial review", "find→verify review", or wants this specific find→dedupe→verify→file→handoff flow instead of a plain single-pass review; /orchestrate calls it at the end of an epic.
argument-hint: "[what to review: a diff, path, PR number, or leave blank for the current branch's changes]"
---

# Adversarial Review (find → dedupe → verify with evidence → file → hand off)

This skill runs a find, dedupe, verify review and turns the survivors into tracked work. It
calls the Workflow tool directly because the user asked for this named flow, which is itself
the opt-in. **Every agent is one of three types defined in `~/.claude/agents`**: `review-finder`
reads a shard through one lens, `review-deduper` folds the finders' list into one finding per
bug, `review-skeptic` verifies one finding. Never spawn a `general-purpose` or default agent for
any of these jobs: the method that makes this review find what a diff-skim misses lives in
those three files, not in your prompt.

All three run Opus 5.5 at high effort. The script passes `agentType` **and** the matching
`model` and `effort` on every `agent()` call so nothing inherits the session's settings; if you
change one of them, change the agent file to match.

Target: `$ARGUMENTS`. If empty, review the current branch's diff against its base (e.g. `git
diff main...HEAD`). If a path is given, review that path. If something that looks like a PR
number or URL is given, fetch that PR's diff with `gh`. A caller (e.g. `/orchestrate`) may also
give a worktree path, a branch, a base, and a **shard map**; see "Sharding a large scope".

## Why the verify step is shaped the way it is

The earlier version of this review refuted a finding whenever its skeptics were unsure. The
record shows that killed real bugs: a race it found and refuted was raised again by a second
reviewer and fixed. The cost asymmetry runs the other way. A false positive costs a worker a few
minutes; a false negative costs a review round or a production bug. So a finding now dies only
when two skeptics each cite the line that makes it impossible, and "uncertain" is a verdict that
keeps the finding alive at a lower priority, with the skeptic's note attached for the fixer.

The same record says a third skeptic settles nothing. Under this rule, 449 findings across eight
runs produced two split pairs, and both times the tiebreaker sided with the refuter. So there is
no third skeptic: a split pair is a **tie**, filed with the refuting citation on top, and the
fixer, who has to read the code anyway, decides. Nor is there a mechanical dedupe: two findings a
few lines apart may be one bug or two unrelated ones, and only a reader of the findings can tell,
so one `review-deduper` reads the list (never the code) before any skeptic runs.

## Step 1 — Scope the review

Work out concretely what "the changed code" is before spawning anything (`git diff --name-only
<base>...HEAD`, or `gh pr diff <n>`). Write the diff to a file in your scratchpad. Pass the
actual file list and diff path into the workflow; don't make agents re-derive it.

### Getting the scope into the agents (the recurring failure of this skill)

**Inline the scope into the script's string literals.** You author the script fresh each run, so
write the worktree path, base, branch, diff path and changed-file list straight into the prompt
template literals as text. Nothing to interpolate means nothing to get wrong.

If you use `args`, it must be an actual JSON **value** in the tool call, never a JSON-encoded
string:

```
args: {"diffPath": "/tmp/.../diff.txt", "base": "main"}     // correct
args: "{\"diffPath\": \"/tmp/.../diff.txt\"}"                 // WRONG — args is a string
```

A stringified object reaches the script as one string, so `args.diffPath` is `undefined` and
`${args.diffPath}` interpolates as the literal text "undefined". **This fails silently**: the
agents still run, read *something*, and return plausible findings, so the review looks fine and
was in fact unscoped.

**Verify before the fan-out.** `log()` the resolved scope as the first statement of the script
body and check the narrator line in the tool result for the word `undefined`. If the scope is
wrong, kill the run and fix it. If you only notice afterwards, say so plainly in your final
report: the findings are not invalid, but the coverage claim is.

### Sharding a large scope

A finder reads its whole shard: every hunk, in the worktree, with the callers. When the diff is
large (more than roughly 30 changed files, or several unrelated areas) one finder per lens over
the whole diff dilutes that and produces vague findings. Shard it:

- **Use the caller's shard map if one was given** (`shard name → changed files`; for an
  orchestrate run, one shard per epic plus a `cross-lane` shard for files more than one lane
  touched). Otherwise build one from `git diff --name-only`, grouping by app/package or feature
  area, so each shard is a coherent slice of about 5–25 files.
- Write each shard's diff to its own scratchpad file (`git diff <base>...<branch> -- <files>`)
  and inline the shard name, its file list and its diff path into that shard's finder prompts.
  Give every finder the **full** changed-file list as well, marked "context only".
- The finder fleet is **shards × lenses**. Every finding carries its `shard` and `lens`.
  Verification is against the whole branch, not the shard, so a skeptic can see cross-shard
  interactions.
- A small scope (one epic, a PR, a few files) is one shard and this section changes nothing.

### Choosing lenses

The lens cards live in `review-finder.md`; you only name them. Some are required because the
record says those are the classes a single-pass review misses most:

| Lens | When |
| --- | --- |
| `correctness` | every shard |
| `consistency` | every shard that contains code |
| `concurrency` | any shard that writes data, sends anything, enqueues, or schedules |
| `boundaries` | any shard that touches both sides of an API line, a DTO, a paged source, dates or money |
| `ui-states` | any shard with UI |
| `security` | auth, authorization, untrusted input, secrets, uploads, raw queries present |
| `test-coverage` | the shard changes or should change tests |
| `infra-config` | env, CI, IaC, Dockerfiles, migrations or deploy scripts changed |
| `architecture` | the change crosses apps or packages, or adds something a shared package owns |
| `docs-accuracy` | comments, docs or guides changed, or code changed under an existing contract comment |
| `caller` | any shard that adds or changes an endpoint, a form, a CLI or an error response |

Drop a lens only where it plainly does not apply (no `concurrency` for a docs-only shard). Say the
resulting finder count before running.

## Step 2 — Run the Workflow

Use this shape. Prompts are template literals with the scope inlined; the agents' own files carry
the method, so each prompt is short: the scope, the shard, the lens or finding, and the schema's
field meanings.

```js
export const meta = {
  name: 'adversarial-review',
  description: 'Find with review-finder, dedupe with review-deduper, verify with review-skeptic',
  phases: [{ title: 'Find' }, { title: 'Dedupe' }, { title: 'Verify' }],
}
const FINDINGS = { type: 'object', required: ['findings'], properties: { findings: { type: 'array', items: {
  type: 'object',
  required: ['file', 'line', 'summary', 'failure_scenario', 'severity', 'shard', 'lens', 'evidence'],
  properties: {
    file: { type: 'string' }, line: { type: 'integer' }, summary: { type: 'string' },
    failure_scenario: { type: 'string' }, category: { type: 'string' },
    severity: { type: 'string', enum: ['Critical', 'High', 'Medium', 'Low'] },
    shard: { type: 'string' }, lens: { type: 'string' },
    evidence: { type: 'array', items: { type: 'string' } },      // path:line of every line read
  } } } } }
const GROUPS = { type: 'object', required: ['groups'], properties: { groups: { type: 'array', items: {
  type: 'object', required: ['ids', 'summary', 'root_cause'],
  properties: { ids: { type: 'array', items: { type: 'integer' } }, summary: { type: 'string' }, root_cause: { type: 'string' } },
} } } }
const VERDICT = { type: 'object', required: ['verdict', 'evidence', 'reason'], properties: {
  verdict: { type: 'string', enum: ['confirmed', 'refuted', 'uncertain'] },
  evidence: { type: 'array', items: { type: 'string' } },        // path:line; required for refuted
  reason: { type: 'string' }, repaired_scenario: { type: 'string' },
  severity: { type: 'string', enum: ['Critical', 'High', 'Medium', 'Low'] },
} }
const FINDER  = { agentType: 'review-finder',  model: 'claude-opus-5-5', effort: 'high' }  // must match the agent files
const DEDUPER = { agentType: 'review-deduper', model: 'claude-opus-5-5', effort: 'high' }
const SKEPTIC = { agentType: 'review-skeptic', model: 'claude-opus-5-5', effort: 'high' }

const TASKS = [ /* one { shard, files, diffPath, lens } per shard × lens, written out as literals */ ]
log(`reviewing <base>...<branch> in <worktree>: ${TASKS.length} finder tasks`)   // no 'undefined' here

const finderPrompt = t => `Worktree: <worktree>. Base: <base>. Branch: <branch>.
Shard "${t.shard}": files ${t.files.join(', ')}. Its diff is at ${t.diffPath}.
All changed files (context only): <full list>.
Your lens: ${t.lens}. Return findings per your lens card; evidence is the path:line of every line you read.`

// Find: every finder finishes before anything else starts; the deduper needs the whole list.
const found = (await parallel(TASKS.map(t => () =>
  agent(finderPrompt(t), { ...FINDER, phase: 'Find', schema: FINDINGS, label: `find:${t.shard}/${t.lens}` }))))
  .flatMap(r => (r ? r.findings : [])).map((f, id) => ({ ...f, id }))

// Dedupe: one agent reads the findings (never the code) and says which are the same bug.
// The script does the merging, so every member's location, lens, scenario and evidence survives.
const groups = found.length < 2 ? [] : ((await agent(
  `Findings from a code review, as JSON: ${JSON.stringify(found)}
Return the groups of ids that describe the same underlying bug, per your instructions.`,
  { ...DEDUPER, phase: 'Dedupe', schema: GROUPS, label: 'dedupe' })) || { groups: [] }).groups
const grouped = new Set(groups.flatMap(g => g.ids))
const merged = [
  ...groups.map(g => {
    const m = g.ids.map(i => found[i]).filter(Boolean)
    return { ...m[0], summary: g.summary, root_cause: g.root_cause,
      failure_scenario: m.map(f => `${f.file}:${f.line}: ${f.failure_scenario}`).join('\n'),
      locations: m.map(f => `${f.file}:${f.line}`), lenses: [...new Set(m.map(f => f.lens))],
      evidence: [...new Set(m.flatMap(f => f.evidence))], members: m.map(f => f.id) }
  }),
  ...found.filter(f => !grouped.has(f.id)),
]
log(`found ${found.length}, ${merged.length} after dedupe (${groups.length} groups)`)

// Verify: two skeptics per finding, never a third. A split pair is a tie for the fixer.
const skepticPrompt = f => `Worktree: <worktree>. Base: <base>. Branch: <branch>.
Verify this finding against the whole branch: ${JSON.stringify(f)}.
Refute only with a path:line that rules the scenario out; otherwise confirm or say uncertain.`
const isRefuted = v => v && v.verdict === 'refuted' && v.evidence.some(e => /:\d+/.test(e))
const skeptic = f => agent(skepticPrompt(f), { ...SKEPTIC, phase: 'Verify', schema: VERDICT, label: `skeptic:${f.file}:${f.line}` })

const all = await parallel(merged.map(f => async () => {
  const live = (await parallel([() => skeptic(f), () => skeptic(f)])).filter(Boolean)
  const refs = live.filter(isRefuted).length
  const confs = live.filter(v => v.verdict === 'confirmed').length
  const repaired = live.find(v => v.verdict === 'confirmed' && v.repaired_scenario)
  const sev = live.find(v => v.verdict === 'confirmed' && v.severity)
  return { ...f,
    failure_scenario: repaired ? repaired.repaired_scenario : f.failure_scenario,
    severity: sev ? sev.severity : f.severity,
    status: refs >= 2 ? 'refuted' : refs === 1 ? 'tie' : confs > 0 ? 'confirmed' : 'unverified',
    votes: live }
}))
const by = s => all.filter(f => f.status === s)
const votes = {}
for (const v of all.flatMap(f => f.votes)) votes[v.verdict] = (votes[v.verdict] || 0) + 1
log(`verified ${all.length}: confirmed ${by('confirmed').length}, unverified ${by('unverified').length}, ties ${by('tie').length}, refuted ${by('refuted').length}; votes ${JSON.stringify(votes)}`)
return { found: found.length, deduped: merged.length, votes,
  confirmed: by('confirmed'), unverified: by('unverified'), ties: by('tie'), refuted: by('refuted') }
```

The rules the script encodes, so you can check a run against them:

- Every finder finishes before the deduper runs, so verification starts after the slowest
  finder, not as each one returns.
- One `review-deduper` call over the findings, never the code. The script merges the groups it
  returns, keeping every member's location, lens, scenario and evidence line; a finding in no
  group passes through unchanged.
- Two skeptics per merged finding, never a third.
- A `refuted` verdict with no `path:line` in its evidence counts as `uncertain`.
- **Dropped only when both skeptics cite evidence against it.** One citation against a
  confirmation or an uncertain is a `tie`. Otherwise `confirmed` when a skeptic confirmed, else
  `unverified`.
- A confirming skeptic's `repaired_scenario` replaces the finder's; its `severity` wins.
- The return carries the vote tally, so the handoff and the run record say how often the
  skeptics doubted.

Do not proceed past this step by guessing at results: wait for the Workflow tool's return value.

### If the Workflow tool is not available

Run the same shape through the Agent tool rather than improvising a different one: spawn the
finders with `subagent_type: review-finder` (a handful at a time, in the background), collect
their findings, one `review-deduper` over the list, then two `review-skeptic` agents per merged
finding, never a third, and apply the same verdict rules by hand. Say in the handoff that the run
went through Agent calls. If neither tool is available, stop and say so; a single-agent read is
not this review.

## Step 3 — File beads for every surviving finding

Check the project uses beads (`.beads/` directory or `bd` on PATH). If it does, one bead per
surviving finding; a merged finding is one bead naming every location, and the fixer fixes all
of them:

```
bd create --title="<short summary>" --type=bug --priority=<p> \
  --description="Shard: <name>. Status: confirmed | unverified | tie. <file:line, every location>. <failure scenario>. Why it matters. Skeptics: <verdict — reason — evidence> ×2."
```

A tie bead's description opens instead with `TIE: <the refuting skeptic's path:line and reason>.
Check that line first; if it holds, close this bead as not real with a reason and change
nothing.` Priority maps severity: Critical/High → 1, Medium → 2, Low → 3. An `unverified` or
`tie` finding is one step lower than its severity says, never below 3. The skeptics' verdicts
and evidence go in the description so the fixer can decide one in a minute without re-deriving
it; closing an unverified or tie bead as a false positive with a reason is a fine outcome.

If the project does not use beads, tell the user and ask whether to write the findings to a plain
markdown list instead. Do not silently skip filing.

## Step 4 — Write the handoff note

A short, copy-pasteable message in a fenced code block, addressed to a fresh agent picking up the
work:

- What was reviewed (scope from Step 1), when, and whether it ran through Workflow or Agent calls.
- One telemetry line, in this exact shape so runs can be compared over time:
  `Review: <n> finders (<shards>×<lenses>), <k> found, <d> after dedupe, <c> confirmed, <u> unverified, <t> ties, <r> refuted, votes c<a>/u<b>/r<c>.`
  A caller such as `/orchestrate` appends it to the epic's notes.
- The filed issue ids, one line each, most severe first, confirmed, then ties, then unverified,
  grouped by shard when sharded.
- A suggested starting point (usually the highest-severity confirmed, or the most isolated).
- Anything dropped for a reason other than two refutations (an agent error, a finding that never
  got verified), so it is not silently lost.
- A reminder to `bd update <id> --claim` before each and `bd close <id>` after, with
  `--reason` when closing an unverified one as not real.

Keep the note under about 200 words. It is a pointer, not the review.

## What this skill does not do

- It does not modify code. It finds, verifies, files and hands off.
- It does not spawn `general-purpose` agents, and it does not override the three agents' model
  or effort from the session: `review-finder`, `review-deduper` and `review-skeptic` are Opus 5.5
  at high effort, and the script passes the same values explicitly.
- It does not refute by argument. A finding leaves this review alive unless two skeptics each
  cite the line that rules it out, and it never launches a third skeptic to settle a split: the
  fixer settles it.
- It does not merge findings by line distance. Only the deduper says two findings are one bug.
