#!/usr/bin/env python3
"""Gather the record of orchestrate runs for /retro.
usage: gather.py <epic-id>…  |  gather.py --closed-after <date> [--closed-before <date>]
Run from the repo root, where bd and gh resolve the project."""
import collections
import json
import re
import subprocess
import sys

RECORD = {"RUN", "PHASES", "WORKERS", "SIMPLIFY", "PLAIN", "REVIEW", "FLAGS", "GATE", "DRIFT", "INCIDENTS", "CI", "COST",
          "COST_USD", "DONE_MEANS", "EPIC_REVIEW", "REVIEW_ROUND", "SCHEDULE", "TELEMETRY"}


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def bd(*args):
    out = run("bd", *args, "--json")
    return json.loads(out) if out.strip() else []


def kv(text):
    return dict(re.findall(r"(\w[\w-]*)=(\S+)", text))


def order(b):
    return [int(x) if x.isdigit() else x for x in b["id"].split(".")]


args = sys.argv[1:]
if args[:1] == ["--closed-after"]:
    epics = [e["id"] for e in bd("list", "--all", "--type", "epic", "--flat", "--brief", *args)]
else:
    epics = args
if not epics:
    sys.exit("no epics given or found")

by_worker = collections.defaultdict(collections.Counter)
incidents = collections.Counter()
rows = []
for epic in epics:
    e = bd("show", epic)
    e = e[0] if isinstance(e, list) else e
    notes = e.get("notes") or ""
    print(f"\n# {epic} — {(e.get('title') or '')[:80]}")
    record = [l.strip() for l in notes.splitlines() if l.strip().split(" ")[0].rstrip(":") in RECORD]
    for l in record:
        print(l if len(l) < 400 else l[:400] + " …")
    if not any(l.startswith(("RUN ", "PHASES ")) for l in record):
        print("(no RUN RECORD: a pre-record epic, read its TELEMETRY by hand)")
    r = kv(" ".join(l for l in record if l.startswith(("RUN ", "DRIFT ", "REVIEW ", "CI "))))
    # A key appended again (prove after its fix beads, the RUN line with pr= filled in) carries
    # the whole line, so the last one is the record: counting every INCIDENTS line double-counts
    # the tags a re-run repeated.
    last_incidents = [l for l in record if l.startswith("INCIDENTS")][-1:]
    for l in last_incidents:
        incidents.update(k for k, _ in re.findall(r"(\S+?)=(\S+)", l[len("INCIDENTS"):]))
    print("\n| bead | worker | rounds | respawn | min | gate | round2 | mismatch | unconfirmed |")
    print("|---|---|---|---|---|---|---|---|---|")
    for b in sorted(bd("list", "--all", "--parent", epic, "--flat"), key=order):
        c = kv(b.get("close_reason") or "")
        if "worker" not in c:
            continue
        print("| " + " | ".join([b["id"]] + [c.get(k, "") for k in ("worker", "rounds", "respawn", "minutes", "gate", "round2", "mismatch", "unconfirmed")]) + " |")
        w = by_worker[c["worker"]]
        w["beads"] += 1
        w["second-round"] += c.get("rounds", "1") not in ("1", "")
        w["respawn"] += c.get("respawn", "0") not in ("0", "no", "")
        w["minutes"] += int(re.sub(r"\D", "", c.get("minutes", "0")) or 0)
    prs = [p for p in json.loads(run("gh", "pr", "list", "--state", "all", "--search", epic, "--json", "number,headRefName,createdAt,mergedAt") or "[]") if p["headRefName"].startswith(epic + "/")]
    if prs:
        p = prs[0]
        reviews = json.loads(run("gh", "pr", "view", str(p["number"]), "--json", "reviews") or "{}").get("reviews", [])
        first = min((x["submittedAt"] for x in reviews), default="")
        print(f"\nPR #{p['number']} created={p['createdAt'][11:16]} first-review={first[11:16]} merged={(p['mergedAt'] or '')[11:16]} reviews={len(reviews)}")
    rows.append([epic] + [r.get(k, "") for k in ("hours", "planned", "added", "workers", "respawns", "confirmed", "failed")] + [sum(l.startswith("SCHEDULE") for l in record)])

print("\n# Across epics\n")
print("| epic | hours | planned | added | workers | respawns | review confirmed | CI failed | SCHEDULE lines |")
print("|---|---|---|---|---|---|---|---|---|")
for row in rows:
    print("| " + " | ".join(str(x) for x in row) + " |")
print("\n| worker | beads | second-round | respawn | mean minutes |\n|---|---|---|---|---|")
for w, c in sorted(by_worker.items()):
    print(f"| {w} | {c['beads']} | {c['second-round']} | {c['respawn']} | {c['minutes'] // max(c['beads'], 1)} |")
print("\nINCIDENTS across epics: " + (", ".join(f"{k}×{v}" for k, v in incidents.most_common()) or "none"))
