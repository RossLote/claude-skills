#!/usr/bin/env python3
"""Print the COST line of an orchestrate run record.

usage: cost.py <epic-id>

Sums every subagent of every session on this machine whose Agent `description`
names the epic (the id followed by a dot, a space or the end), reading agent
type, minutes and token usage from the transcript files Claude Code keeps under
<config dir>/projects/<project>/<session>/subagents/, where the config dir is ~/.claude or
CLAUDE_CONFIG_DIR on a machine that runs more than one account.
"""
import collections
import datetime
import glob
import json
import os
import re
import sys

epic = sys.argv[1]
names = re.compile(re.escape(epic) + r"(?![\w-])")
# The home server's second account lives in ~/.claude-2: a run there found 0 agents while this
# read ~/.claude.
root = os.path.join(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude"), "projects")
by = collections.defaultdict(lambda: [0, 0.0, 0, 0])  # count, minutes, tokens in, tokens out


def when(ts):
    return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))


for meta in glob.glob(f"{root}/*/*/subagents/*.meta.json"):
    m = json.load(open(meta))
    if not names.search(str(m.get("description", ""))):
        continue
    first = last = None
    tin = tout = 0
    try:
        for line in open(meta[: -len(".meta.json")] + ".jsonl"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("timestamp"):
                first = first or d["timestamp"]
                last = d["timestamp"]
            msg = d.get("message")
            usage = msg.get("usage") if isinstance(msg, dict) else None
            if usage:
                tin += usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0) + usage.get("cache_creation_input_tokens", 0)
                tout += usage.get("output_tokens", 0)
    except FileNotFoundError:
        continue
    row = by[m.get("agentType", "unknown")]
    row[0] += 1
    row[1] += (when(last) - when(first)).total_seconds() / 60 if first and last else 0
    row[2] += tin
    row[3] += tout


def short(n):
    for unit, size in (("B", 1e9), ("M", 1e6), ("k", 1e3)):
        if n >= size:
            return f"{n / size:.1f}{unit}" if unit == "B" else f"{n / size:.0f}{unit}"
    return str(n)


parts = [f"agents={sum(r[0] for r in by.values())}"]
parts += [f"{kind}={r[0]}/{r[1]:.0f}min" for kind, r in sorted(by.items(), key=lambda kv: -kv[1][2])]
parts.append(f"tokens-in={short(sum(r[2] for r in by.values()))}")
parts.append(f"tokens-out={short(sum(r[3] for r in by.values()))}")
print("COST " + " ".join(parts))
