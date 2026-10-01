#!/usr/bin/env python3
"""Edit the Task Ledger (state/tasks.md) without one-off scripts.

  python tools/ledger.py add T-007 --title "Fix login" --stage 2 --role developer \
      --tool Codex --status ready --depends "T-006" --notes "..."
  python tools/ledger.py set T-007 --status review --commit abc1234
  python tools/ledger.py show [T-007]

Only the Orchestrator (or a Single Mode session) runs this. Values are written as given;
a '|' inside a value is replaced with '/'. Task IDs are never reused: 'add' fails on an existing ID.
"""
import argparse
import re
import sys
from pathlib import Path

COLS = ["ID", "Title", "Stage", "Role", "Tool", "Status", "Depends on", "Commit / artifact", "Notes"]
FIELD = {  # CLI option -> column
    "title": "Title", "stage": "Stage", "role": "Role", "tool": "Tool", "status": "Status",
    "depends": "Depends on", "commit": "Commit / artifact", "notes": "Notes",
}
STATUSES = {"ready", "in progress", "review", "done", "rework", "blocked", "cancelled"}
PLACEHOLDER = re.compile(r"^\s*No tasks yet\.?\s*$", re.I)


def ledger_path() -> Path:
    return Path(__file__).resolve().parent.parent / "state" / "tasks.md"


def split_row(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def join_row(cells: list[str]) -> str:
    return "| " + " | ".join(c.replace("|", "/").replace("\n", " ") for c in cells) + " |"


def load(path: Path):
    lines = path.read_text(encoding="utf-8").split("\n")
    head = next((i for i, l in enumerate(lines) if l.startswith("| ID ")), None)
    if head is None:
        sys.exit(f"{path}: table header '| ID | ...' not found")
    end = head + 2  # header + separator
    while end < len(lines) and lines[end].startswith("|"):
        end += 1
    return lines, head, end


def save(path: Path, lines, head, end, rows):
    out = lines[: head + 2] + [join_row(r) for r in rows] + lines[end:]
    # drop the "No tasks yet." placeholder once there is a row
    if rows:
        out = [l for l in out if not PLACEHOLDER.match(l)]
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")


def main() -> None:
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
    lines, head, end = load(path)
    rows = [split_row(l) for l in lines[head + 2 : end]]
    rows = [r + [""] * (len(COLS) - len(r)) for r in rows]
    idx = {r[0]: i for i, r in enumerate(rows)}

    if a.cmd == "show":
        for r in rows:
            if a.id is None or r[0] == a.id:
                print(" | ".join(r))
        return

    if not re.fullmatch(r"T-\d+", a.id):
        sys.exit(f"bad task id: {a.id} (expected T-NNN)")
    if a.status and a.status not in STATUSES:
        sys.exit(f"bad status: {a.status}; allowed: {', '.join(sorted(STATUSES))}")

    if a.cmd == "add":
        if a.id in idx:
            sys.exit(f"{a.id} already exists (IDs are never reused)")
        row = [""] * len(COLS)
        row[0] = a.id
        rows.append(row)
        i = len(rows) - 1
    else:
        if a.id not in idx:
            sys.exit(f"{a.id} not in ledger")
        i = idx[a.id]

    for opt, col in FIELD.items():
        v = getattr(a, opt)
        if v is not None:
            rows[i][COLS.index(col)] = v

    save(path, lines, head, end, rows)
    print(join_row(rows[i]))


if __name__ == "__main__":
    main()
