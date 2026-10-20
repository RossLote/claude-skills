#!/usr/bin/env python3
"""Pick the beads of an epic that may run now with disjoint files.

usage: schedule.py <epic-id> [--max N] [--running id,id] [--repo <clone>] [--json] [--explain]

The deterministic half of the orchestrate skill's Scheduling section: candidates are
`bd ready` under the epic; two beads run together only when their TOUCHES do not overlap
and they share no hazard named in SEQUENCING or on the beads; a bead SEQUENCING runs
"alone" runs with nothing else. Beads in progress (and --running) hold their files, and a
bead whose dependency is still running is not ready, even when bd says it is: the worker
closes a bead inside its phase call, before the driver has merged its branch, and a worktree
cut then would miss that commit.
Prints one bead id per line, in plan order, at most N minus the running count.
--explain prints only what the plan text was read as ({"alone": [...], "hazard_groups": [[...]]})
and exits, which works on a closed epic too.
"""
import fnmatch
import glob
import json
import os
import re
import subprocess
import sys

args = sys.argv[1:]
epic = args.pop(0)
opt = {"--max": "3", "--running": "", "--repo": ".", "--json": None, "--explain": None}
while args:
    a = args.pop(0)
    opt[a] = args.pop(0) if a in ("--max", "--running", "--repo") else True
os.chdir(opt["--repo"])
EXT = re.compile(r"\.(tsx?|jsx?|mdx?|json|ya?ml|prisma|py|sh|css|sql|mjs|cjs)$")


def bd(*a):
    # A failed bd call exits non-zero rather than reading as an empty list: the driver reported
    # "nothing is ready" for an epic whose scheduler could not read it.
    r = subprocess.run(["bd", *a, "--json"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"schedule.py: bd {' '.join(a)} failed: {r.stderr.strip()[:300]}")
    return json.loads(r.stdout) if r.stdout.strip() else []


def order(b):
    return [int(x) if x.isdigit() else x for x in b["id"].split(".")]


def text(bead):
    # The epic skill puts TOUCHES, MODEL and Hazards in a bead's notes; a phase that files a fix bead
    # has put them in its description, where a notes-only read saw no files at all, so any two fix
    # beads ran together (two that shared a spec and a guide did). The
    # notes come first, so a line there wins over one in the description.
    return (bead.get("notes") or "") + "\n" + (bead.get("description") or "")


def line(bead, key):
    m = re.search(rf"^{key}:\s*(.+)$", text(bead), re.M)
    return m.group(1).strip() if m else ""


def paths(s):  # same parser as epic-review/lint.py
    out = []
    for t in re.split(r"[\s,;]+", s):
        t = re.sub(r"[§#].*$", "", t.strip("`'\"(),;:")).rstrip(".")   # a leading dot is a path (.railway/, .github/)
        if t and not t.startswith("http") and ("/" in t or EXT.search(t)):
            out.append(t)
    return out


def files(bead):
    out = set()
    for g in paths(line(bead, "TOUCHES")):
        out |= set(glob.glob(g.replace("[", "[[]"), recursive=True)) or {g}
        out.add(g)
    return out


def overlap(a, b):
    for x in a:
        for y in b:
            dx, dy = x.rstrip("*/"), y.rstrip("*/")
            if x == y or fnmatch.fnmatch(x, y) or fnmatch.fnmatch(y, x) or x.startswith(dx and dy + "/") or y.startswith(dy and dx + "/"):
                return True
    return False


def refs(s):  # ".4 .5 .6" → {"<epic>.4", ...}
    return {f"{epic}.{n}" for n in re.findall(r"(?<![\w.])\.(\d+(?:\.\d+)*)", s)}


parent = bd("show", epic)
parent = parent[0] if isinstance(parent, list) else parent
notes = parent.get("notes") or ""
seq = notes[notes.find("SEQUENCING"):] if "SEQUENCING" in notes else ""
seq = seq[: seq.find("ACCEPTANCE BAR")] if "ACCEPTANCE BAR" in seq else seq

SENTENCE = r"[;\n•]|(?<=[a-z0-9)`])\.\s+(?=[A-Z`])"  # ; • newline, or a full stop before a capital

alone = set()
for frag in re.split(SENTENCE, seq):
    if re.search(r"\balone\b", frag):
        # The beads before "alone" are the sentence's subject; the ones after "after", "before"
        # or "once" are what it waits on (".5 after .3, alone on the messages hazard" marks .5,
        # not .3, which that plan runs together with .4).
        subject = re.split(r"\b(?:after|before|once)\b", frag.split("alone")[0])[0]
        alone |= refs(subject)
# a sentence that names a hazard, a hot or shared file, or sits in the Hazards block, groups the beads it names.
# The Hazards block ends at the next line that starts with SEQUENCING: the "SEQUENCING change
# (epic-review, <date>): ..." paragraphs appended below it are plan edits, not hazards, and read as
# hazard text every sentence naming two beads in them became a group (one epic's
# ".7 ... runs alongside .1 and .2" and ".3 depends on .7 and .2" serialised .2, .1 and .7).
plan = seq[: m.start() + 1] if (m := re.search(r"^\W*SEQUENCING", seq[1:], re.M)) else seq
tail = plan[plan.lower().find("hazard"):] if "hazard" in plan.lower() else ""
# A "together" sentence is the plan's explicit call and never a hazard group, whatever words it
# uses: one plan's ".6 .7 .8 .9 .10 together — disjoint: ... shared ..." would otherwise have run
# all five one after the other.
hazard_groups = [refs(f) for f in re.split(SENTENCE, seq) if re.search(r"hazard|\bhot\b|\bshared\b", f, re.I) and not re.search(r"\btogether\b", f)]
hazard_groups += [refs(f) for f in re.split(SENTENCE, tail) if not re.search(r"\btogether\b", f)]
hazard_groups = [g for g in hazard_groups if len(g) > 1]
if opt["--explain"]:
    print(json.dumps({"alone": sorted(alone, key=lambda i: order({"id": i})), "hazard_groups": [sorted(g, key=lambda i: order({"id": i})) for g in hazard_groups]}))
    sys.exit(0)

all_beads = {b["id"]: b for b in bd("list", "--all", "--parent", epic, "--flat")}
running = {x for x in opt["--running"].split(",") if x}
running |= {i for i, b in all_beads.items() if b.get("status") == "in_progress"}
ready = [b for b in sorted(bd("list", "--ready", "--parent", epic, "--flat"), key=order) if b["id"] != epic and b["id"] not in running]


def blockers(bead):  # the beads this one depends on ("blocks" edges; the parent edge is not one)
    return {d.get("depends_on_id") for d in bead.get("dependencies") or [] if d.get("type") == "blocks"}


# Readiness means every dependency merged into the epic branch, not every dependency closed:
# a dependency in --running is closed in bd by its own phase call but not yet reaped and merged.
waiting = [b["id"] for b in ready if blockers(b) & running]
ready = [b for b in ready if b["id"] not in waiting]
ready.sort(key=lambda b: (b.get("priority", 2), order(b)))


def named_hazards(bead):  # "Hazard: integration DB, packages/db/src/schema/auth.ts (after .2)."
    m = re.search(r"\bHazards?:\s*([^\n;]+)", text(bead), re.I)
    if not m:
        return set()
    # Never name a local `text`: it makes text() above local to the whole function, so the first
    # line raised UnboundLocalError on every call, and no two beads ran together.
    s = re.split(r"\.\s+(?=[A-Z`])|\.\s*$", m.group(1))[0]   # the sentence, not the ones after it
    s = re.sub(r"\([^)]*\)", "", s)                          # a parenthetical is a note, not a name
    # Split on commas and "and" only: a slash is part of a path, and splitting on it made any two
    # beads with paths under the same tree (apps/web/src/...) share "apps", "web" and "src".
    return {h.strip(" `'\"").lower() for h in re.split(r",| and ", s)} - {""}


def clash(a, b):
    if a in alone or b in alone:
        return True
    if any(a in g and b in g for g in hazard_groups):
        return True
    ba, bb = all_beads.get(a, {}), all_beads.get(b, {})
    if named_hazards(ba) & named_hazards(bb):
        return True
    return overlap(files(ba), files(bb))


slots = max(0, int(opt["--max"]) - len(running))
picked = []
for b in ready:
    if len(picked) >= slots:
        break
    if all(not clash(b["id"], other) for other in list(running) + picked):
        picked.append(b["id"])

if opt["--json"]:
    print(json.dumps({"run": picked, "running": sorted(running), "ready": [b["id"] for b in ready], "waiting": waiting, "alone": sorted(alone)}))
else:
    print("\n".join(picked))
