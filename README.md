# Claude Code skills and agents

Ross Lote's global [Claude Code](https://code.claude.com) skills and the agent
definitions they spawn. Installed on a machine, this directory *is*
`~/.claude/skills`, and `~/.claude/agents` is a symlink to `agents/` inside it.

## Layout

- `<skill>/SKILL.md` — one skill per folder. A few carry a helper script next to
  the skill (`epic-review/lint.py`, `orchestrate/cost.py`, `retro/gather.py`) or
  reference material (`user-docs/references/`).
- `orchestrate-phase/` — the headless form of `/orchestrate` for a server: the skill
  runs one phase per call against the contract in `phases.md`, `schedule.py` picks the
  beads that may run together, `orchestrate-epic.sh` drives one epic from setup to a
  green PR, and `orchestrate-run.sh` runs several epics in turn. Interactive
  `/orchestrate` is unchanged.
- `agents/*.md` — the purpose-built agents the fan-out skills spawn by type:
  `review-finder` and `review-skeptic` (adversarial review, epic review),
  `epic-finder` (epic review), `worker-opus` and `worker-sonnet` and
  `merge-resolver` (orchestrate).

## The planning-to-PR pipeline

`/brief` works out what a feature is in rounds of questions and keeps the record
on one bead. `/epic` turns the settled design into a beads epic. `/epic-review`
lints it before it runs. `/orchestrate` runs it unattended with worker agents and
ends with `/adversarial-review` and `/pr`. `/address-review` handles the review
threads until merge. `/retro` reads the run records back and proposes changes to
the skills. `/handover` and `/takeover` move a running orchestration between
sessions; `/handoff` is the copy-paste version.

## Install on another machine

```bash
git clone git@github.com:RossLote/claude-skills.git ~/.claude/skills
ln -s ~/.claude/skills/agents ~/.claude/agents
```

A second config dir (for example `CLAUDE_CONFIG_DIR=~/.claude-2`) gets the same
set by linking `skills` and `agents` to the ones above.

Not in this repo: `find-skills` is installed separately by the skills CLI into
`~/.agents/skills` and linked from here; `synced/` is Claude Code's own
plugin-sync state; `home-server/` is a private, machine-specific skill (how to
reach one particular box) that stays gitignored on purpose.
