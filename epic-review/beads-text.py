#!/usr/bin/env python3
"""Print beads' raw fields as plain text for agent prompts. usage: beads-text.py <id>...
The rendered `bd show` drops backslashes (an escaped bracket, a \\| alternation), so a grep
quoted in a bead looks broken when it is not. This prints the fields `bd show --json` holds."""
import json
import subprocess
import sys

for bid in sys.argv[1:]:
    out = subprocess.run(["bd", "show", bid, "--json"], capture_output=True, text=True).stdout
    b = json.loads(out)
    b = b[0] if isinstance(b, list) else b
    deps = ", ".join(d["id"] for d in b.get("dependencies") or [] if d["id"] != b.get("parent")) or "none"
    print(f"===== {b['id']} · {b['title']} [{b['status']}, {b['issue_type']}]")
    print(f"DEPENDS ON: {deps}\n\nDESCRIPTION\n{b.get('description') or ''}\n")
    print(f"ACCEPTANCE CRITERIA\n{b.get('acceptance_criteria') or ''}\n\nNOTES\n{b.get('notes') or ''}\n")
