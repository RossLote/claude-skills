#!/usr/bin/env python3
"""Lint an epic's beads before /orchestrate. usage: lint.py <epic-id>   (from the repo root)"""
import glob
import json
import re
import shlex
import subprocess
import sys
from fnmatch import fnmatch

epic = sys.argv[1]
EXT = re.compile(r"\.(tsx?|jsx?|mdx?|json|ya?ml|prisma|py|sh|css|sql)$")


def bd(*args):
    out = subprocess.run(["bd", *args, "--json"], capture_output=True, text=True).stdout
    return json.loads(out) if out.strip() else []


def order(b):
    return [int(x) if x.isdigit() else x for x in b["id"].split(".")]


def line(bead, key):  # notes first, then the description, as schedule.py reads them
    text = (bead.get("notes") or "") + "\n" + (bead.get("description") or "")
    m = re.search(rf"^{key}:\s*(.+)$", text, re.M)
    return m.group(1).strip() if m else None


def find(pattern):
    return glob.glob(pattern.replace("[", "[[]"), recursive=True)


def paths(text):
    out = []
    for t in re.split(r"[\s,;]+", text):
        t = re.sub(r"[§#].*$", "", t.strip("`'\"(),;:")).rstrip(".")   # a leading dot is a path (.railway/, .github/)
        t = re.sub(r":\d+(-\d+)?$", "", t)  # a path:line reference
        if t and not t.startswith("http") and ("/" in t or EXT.search(t)):
            out.append(t)
    return out


tracked = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.splitlines()

parent = bd("show", epic)
parent = parent[0] if isinstance(parent, list) else parent
notes = parent.get("notes") or ""
beads = sorted((b for b in bd("list", "--all", "--parent", epic, "--flat") if b.get("status") != "closed"), key=order)  # a closed bead is not run
problems = []
touches = {}
globs = {}
GREP = re.compile(r"git grep\s+(.*?)\s+returns nothing", re.S)

for b in beads:
    bid = b["id"]
    for key in ("READ FIRST", "TOUCHES", "MODEL"):
        if not line(b, key):
            problems.append(f"{bid}: no {key} line")
    if not (b.get("acceptance_criteria") or "").strip():
        problems.append(f"{bid}: no acceptance")
    read_first = line(b, "READ FIRST") or ""
    for p in paths(read_first):
        found = find(p) or any(t.endswith("/" + p) or "/" + p + "/" in t for t in tracked)
        if "*" not in p and not found:
            problems.append(f"{bid}: READ FIRST path not found: {p}")
    touches[bid] = set()
    touches_line = line(b, "TOUCHES") or ""
    # `none (throwaway; ...)` is the walkthrough bead: it commits nothing (epic skill).
    globs[bid] = [] if touches_line.lower().startswith("none") else paths(touches_line)
    new = []
    for g in globs[bid]:
        hits = find(g)
        if not hits:
            folder = (g.rsplit("/", 1)[0] if "/" in g else ".").split("*")[0].rstrip("/") or "."
            if find(folder):
                new.append(g)
            else:
                problems.append(f"{bid}: TOUCHES parent folder does not exist (typo, or a new folder): {g}")
        touches[bid] |= set(hits) or {g}
    if new:
        problems.append(f"{bid}: {len(new)} TOUCHES path(s) do not exist yet (new files): {', '.join(new[:2])}{'…' if len(new) > 2 else ''}")
    for cmd in GREP.findall(b.get("acceptance_criteria") or ""):
        # The grep is run on the base: a hit in a file outside the bead's TOUCHES is one the
        # worker cannot clear; no hit at all means the check proves nothing on the base.
        main, *drops = cmd.split(" | grep -v ")  # a trailing `| grep -v "x"` is applied by hand
        try:
            args, drops = shlex.split(main), [shlex.split(d)[0] for d in drops]
        except (ValueError, IndexError):
            continue
        hits = subprocess.run(["git", "grep", *args], capture_output=True, text=True).stdout.splitlines()
        hits = [h for h in hits if not any(d in h for d in drops)]
        outside = [h for h in hits if not any(fnmatch(h.split(":", 1)[0], g) or h.startswith(g.split("*")[0]) for g in globs[bid])]
        if outside:
            problems.append(f"{bid}: acceptance grep hits {len(outside)} line(s) outside TOUCHES, e.g. {outside[0][:90]}")
        elif not hits:
            problems.append(f"{bid}: acceptance grep already returns nothing on the base (proves nothing, or guards a new string): git grep {cmd[:70]}")
    model = (line(b, "MODEL") or "").lower()
    if model.startswith("sonnet") and not read_first:
        problems.append(f"{bid}: MODEL sonnet with no READ FIRST precedent")
    if not b.get("dependency_count") and bid != f"{epic}.1" and b.get("status") != "closed":
        problems.append(f"{bid}: no dependency (fine only if it may start first)")

seq = notes[notes.find("SEQUENCING"):notes.find("ACCEPTANCE BAR")] if "SEQUENCING" in notes else ""
# The scheduler (orchestrate-phase/schedule.py, same rule) keeps apart every bead one Hazards
# item names, so a "together" group that an item names is a plan at odds with itself: one epic's
# "e2e/helpers/** (.2 imports, .3 the storage constant, .4 ..., then .5)" ran .3 and .4 serially.
SENTENCE = r"[;\n•]|(?<=[a-z0-9)`])\.\s+(?=[A-Z`])"
hazard_tail = seq[seq.lower().find("hazard"):] if "azard" in seq else ""
hazard_items = [f for f in re.split(SENTENCE, seq) if re.search(r"hazard|\bhot\b|\bshared\b", f, re.I) and not re.search(r"\btogether\b", f)]
hazard_items += [f for f in re.split(SENTENCE, hazard_tail) if not re.search(r"\btogether\b", f)]
hazard_groups = [(f.strip(), {f"{epic}.{n}" for n in re.findall(r"(?<![\w.])\.(\d+(?:\.\d+)*)", f)}) for f in hazard_items]
for l in seq.splitlines():
    if "together" not in l:
        continue
    ids = [f"{epic}.{n}" for n in re.findall(r"\.(\d+)", l.split("together")[0])]
    for i, a in enumerate(ids):
        for c in ids[i + 1:]:
            shared = touches.get(a, set()) & touches.get(c, set())
            if shared:
                problems.append(f"{a} and {c} run together but share: {', '.join(sorted(shared)[:3])}")
            for item, named in hazard_groups:
                if a in named and c in named:
                    problems.append(f"{a} and {c} run together but one Hazards item names both, so the scheduler runs them one after the other: {item[:70]}")
                    break

m = re.search(r"planned=(\d+)", notes)
print(f"{epic}: {len(beads)} beads, planned={m.group(1) if m else 'no planned= line in SEQUENCING'}")
for p in problems:
    print(" -", p)
if not problems:
    print(" - nothing found by lint")
