#!/usr/bin/env python3
"""Edit the Task Ledger (state/tasks.md) without one-off scripts.

  python tools/ledger.py add T-007 --title "Fix login" --stage 2 --role developer \
      --tool codex --status ready --depends "T-006" --notes "..."
  python tools/ledger.py set T-007 --status review
  python tools/ledger.py set T-007 --status done --commit abc1234      # acceptance: needs a passing gate.py verify on that SHA
  python tools/ledger.py set T-007 --status rejected --notes "-> T-012: <why>"
  python tools/ledger.py show [T-007]

Only the Orchestrator (or a Single Mode session) runs this. Transitions follow docs/ai-handoff-protocol.md,
"Task lifecycle". A '|' inside a value is replaced with '/'. Task IDs are never reused.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

COLS = ["ID", "Title", "Stage", "Role", "Tool", "Status", "Depends on", "Commit / artifact", "Notes", "Updated"]
FIELD = {  # CLI option -> column
    "title": "Title", "stage": "Stage", "role": "Role", "tool": "Tool", "status": "Status",
    "depends": "Depends on", "commit": "Commit / artifact", "notes": "Notes",
}
NEXT = {  # allowed status transitions; done, rejected, cancelled are final
    "ready": {"in progress", "blocked", "cancelled"},
    "in progress": {"review", "blocked", "rejected", "cancelled"},
    "review": {"done", "rejected", "in progress", "blocked"},
    "blocked": {"ready", "in progress", "review", "cancelled"},
    "done": set(), "rejected": set(), "cancelled": set(),
}
NEEDS_NOTES = {"rejected", "cancelled"}
PLACEHOLDER = re.compile(r"^\s*No tasks yet\.?\s*$", re.I)
HEAD = "# Task Ledger\n\nWritten only through `python tools/ledger.py`. Statuses: docs/ai-handoff-protocol.md, \"Task lifecycle\".\n\n"


def root() -> Path:
    return Path(__file__).resolve().parent.parent


def ledger_path() -> Path:
    return root() / "state" / "tasks.md"


def split_row(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def join_row(cells: list[str]) -> str:
    return "| " + " | ".join(c.replace("|", "/").replace("\n", " ") for c in cells) + " |"


def load(path: Path):
    """-> lines, columns (COLS), rows (padded to COLS), header index, end index. Older ledgers gain new columns."""
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(HEAD + join_row(COLS) + "\n" + "|---" * len(COLS) + "|\n", encoding="utf-8", newline="\n")
    lines = path.read_text(encoding="utf-8-sig").split("\n")
    head = next((i for i, l in enumerate(lines) if l.startswith("| ID ")), None)
    if head is None:
        sys.exit(f"{path}: table header '| ID | ...' not found")
    old = split_row(lines[head])
    end = head + 2  # header + separator
    while end < len(lines) and lines[end].startswith("|"):
        end += 1
    rows = []
    for l in lines[head + 2:end]:
        cells = dict(zip(old, split_row(l)))
        rows.append([cells.get(c, "") for c in COLS])
    return lines, COLS, rows, head, end


def save(path: Path, lines, head, end, rows):
    out = lines[:head] + [join_row(COLS), "|---" * len(COLS) + "|"] + [join_row(r) for r in rows] + lines[end:]
    if rows:  # drop the "No tasks yet." placeholder once there is a row
        out = [l for l in out if not PLACEHOLDER.match(l)]
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")


def verified(tid: str, sha: str) -> bool:
    """A passing `gate.py verify` record for this task on this commit (protocol: Acceptance)."""
    p = root() / "tasks" / ".runtime" / f"{tid}.verify.json"
    if not p.exists() or not sha:
        return False
    recs = json.loads(p.read_text(encoding="utf-8"))
    last = [r for r in recs if r.get("sha") and (r["sha"].startswith(sha) or sha.startswith(r["sha"]))]
    return bool(last) and last[-1]["ok"]


def main() -> None:
    # ledger text is UTF-8 (emoji, Cyrillic); a cp1251/cp866 console or pipe must not crash the print
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("add", "set"):
        p = sub.add_parser(name)
        p.add_argument("id")
        for opt in FIELD:
            p.add_argument(f"--{opt}")
    sh = sub.add_parser("show")
    sh.add_argument("id", nargs="?")
    a = ap.parse_args()

    path = ledger_path()
    lines, cols, rows, head, end = load(path)
    idx = {r[0]: i for i, r in enumerate(rows)}

    if a.cmd == "show":
        for r in rows:
            if a.id is None or r[0] == a.id:
                print(" | ".join(r))
        return

    if not re.fullmatch(r"T-\d+", a.id):
        sys.exit(f"bad task id: {a.id} (expected T-NNN)")
    if a.status and a.status not in NEXT:
        sys.exit(f"bad status: {a.status}; allowed: {', '.join(NEXT)}")

    if a.cmd == "add":
        if a.id in idx:
            sys.exit(f"{a.id} already exists (IDs are never reused)")
        if (a.status or "ready") not in ("ready", "blocked"):
            sys.exit("a new task starts as ready or blocked")
        row = [""] * len(cols)
        row[0], row[cols.index("Status")] = a.id, "ready"
        rows.append(row)
        i = len(rows) - 1
    else:
        if a.id not in idx:
            sys.exit(f"{a.id} not in ledger")
        i = idx[a.id]
        cur = rows[i][cols.index("Status")]
        if a.status and a.status != cur and cur in NEXT and a.status not in NEXT[cur]:
            sys.exit(f"{a.id}: {cur} -> {a.status} is not allowed; from {cur}: {', '.join(sorted(NEXT[cur])) or 'final'}")
        if a.status in NEEDS_NOTES and not a.notes:
            sys.exit(f"{a.status} needs --notes (reason; for rejected also the successor task)")
        if a.status == "done":
            sha = a.commit or rows[i][cols.index("Commit / artifact")]
            if not verified(a.id, sha):
                sys.exit(f"{a.id}: no passing verify on commit '{sha}'. Run: python tools/gate.py verify {a.id}")

    for opt, col in FIELD.items():
        v = getattr(a, opt)
        if v is not None:
            rows[i][cols.index(col)] = v
    rows[i][cols.index("Updated")] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")

    save(path, lines, head, end, rows)
    print(join_row(rows[i]))


if __name__ == "__main__":
    main()
