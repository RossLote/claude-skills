#!/usr/bin/env python3
"""Remove the worktrees of merged branches and close their epics.
usage: gc.py [--apply] [--repo <main checkout>]   (default: dry run, the current directory)

A worktree is dead when its branch's pull request has merged. The end-of-run cleanup in the
orchestrate skill only runs when a run reaches its end, and the merge happens by hand after
the session is gone, so merged worktrees pile up and hold Docker networks, ports and disk.
Orchestrate runs this at setup, address-review after a merge it saw.

For each worktree other than the main checkout:
  - skipped when it has uncommitted changes, or a live claim (<git-dir>/orchestrate-claim
    whose pid is alive on this host), or no PR, or a PR that is open;
  - when its PR has merged: `make worktree-teardown` there if the Makefile has that target,
    else `docker compose -p <folder name> down -v --remove-orphans` when docker is present;
    then `git worktree remove --force` and `git branch -D`.
For each merged branch named <epic>/<slug>: `bd close <epic>` with the PR number when the
epic is still open, and a list of the beads under it that are still open, which need a
person or the orchestrator to settle (done but never closed, dropped, or a real follow-up).
Nothing is imported into beads: a repo that tracks .beads/issues.jsonl imports it on pull.
"""
import json
import os
import re
import subprocess
import sys

apply = "--apply" in sys.argv
repo = sys.argv[sys.argv.index("--repo") + 1] if "--repo" in sys.argv else os.getcwd()
repo = os.path.abspath(repo)


def run(*cmd, cwd=None, check=False):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    if check and r.returncode:
        sys.exit(f"{' '.join(cmd)}: {r.stderr.strip()}")
    return r


def pr_for(branch):
    r = run("gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "1",
            "--json", "number,state,mergedAt", cwd=repo)
    try:
        prs = json.loads(r.stdout or "[]")
    except json.JSONDecodeError:
        return None
    return prs[0] if prs else None


def claimed(wt):
    gitdir = run("git", "rev-parse", "--git-dir", cwd=wt).stdout.strip()
    path = os.path.join(wt, gitdir, "orchestrate-claim") if not os.path.isabs(gitdir) else os.path.join(gitdir, "orchestrate-claim")
    if not os.path.exists(path):
        return False
    try:
        pid, host = open(path).read().split()[:2]
    except ValueError:
        return True
    if host != os.uname().nodename:
        return True  # another host's claim: not ours to judge
    try:
        os.kill(int(pid), 0)
        return True
    except (ProcessLookupError, ValueError):
        return False  # a dead claim does not hold the worktree
    except PermissionError:
        return True


main = run("git", "rev-parse", "--show-toplevel", cwd=repo, check=True).stdout.strip()
worktrees = []
cur = {}
for line in run("git", "worktree", "list", "--porcelain", cwd=repo).stdout.splitlines():
    if line.startswith("worktree "):
        cur = {"path": line[9:]}
        worktrees.append(cur)
    elif line.startswith("branch "):
        cur["branch"] = line[7:].replace("refs/heads/", "")

removed, kept, epics = [], [], {}
for wt in worktrees:
    path, branch = wt["path"], wt.get("branch")
    if os.path.abspath(path) == main or not branch:
        continue
    name = os.path.basename(path)
    if not os.path.isdir(path):
        kept.append(f"{name}: folder missing (git worktree prune would drop it)")
        continue
    if run("git", "status", "--porcelain", cwd=path).stdout.strip():
        kept.append(f"{name}: dirty, left alone")
        continue
    if claimed(path):
        kept.append(f"{name}: claimed by a live run, left alone")
        continue
    pr = pr_for(branch)
    if not pr:
        kept.append(f"{name}: {branch} has no PR")
        continue
    if pr["state"] != "MERGED":
        kept.append(f"{name}: PR #{pr['number']} is {pr['state'].lower()}")
        continue
    merged = (pr.get("mergedAt") or "")[:10]
    m = re.match(r"([a-z0-9]+-[a-z0-9]+)(?:\.\d+)*/", branch)
    if m:
        epics.setdefault(m.group(1), pr["number"])
    removed.append(f"{name}: {branch} merged in PR #{pr['number']} on {merged}")
    if not apply:
        continue
    if run("make", "-n", "worktree-teardown", cwd=path).returncode == 0:
        run("make", "worktree-teardown", cwd=path)
    elif run("docker", "info").returncode == 0:
        run("docker", "compose", "-p", name.lower(), "down", "-v", "--remove-orphans", cwd=path)
    r = run("git", "worktree", "remove", "--force", path, cwd=repo)
    if r.returncode:
        removed[-1] += f"  (remove failed: {r.stderr.strip()})"
        continue
    run("git", "branch", "-D", branch, cwd=repo)

if apply:
    run("git", "worktree", "prune", cwd=repo)
    if run("docker", "info").returncode == 0:
        run("docker", "network", "prune", "-f")

print(("Removed" if apply else "Would remove") + f" {len(removed)} worktree(s):")
for r in removed:
    print("  -", r)
print(f"Kept {len(kept)}:")
for k in kept:
    print("  -", k)

if epics and run("bd", "--version", cwd=repo).returncode == 0:
    print("Epics of merged branches:")
    for epic, pr in epics.items():
        r = run("bd", "show", epic, "--json", cwd=repo)
        try:
            e = json.loads(r.stdout)
            e = e[0] if isinstance(e, list) else e
        except (json.JSONDecodeError, IndexError):
            print(f"  - {epic}: not in this beads database")
            continue
        status = e.get("status")
        if status != "closed":
            if apply:
                run("bd", "close", epic, "--reason", f"PR #{pr} merged (gc.py)", cwd=repo)
                print(f"  - {epic}: was {status}, closed with PR #{pr}")
            else:
                print(f"  - {epic}: {status}, would close with PR #{pr}")
        else:
            print(f"  - {epic}: already closed")
        r = run("bd", "list", "--all", "--parent", epic, "--flat", "--json", cwd=repo)
        try:
            kids = [b for b in json.loads(r.stdout or "[]") if b.get("status") != "closed"]
        except json.JSONDecodeError:
            kids = []
        for b in kids:
            print(f"      open under it: {b['id']} [{b.get('status')}] {(b.get('title') or '')[:70]}  <- settle by hand")
