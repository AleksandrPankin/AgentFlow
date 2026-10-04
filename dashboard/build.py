#!/usr/bin/env python3
"""Builds dashboard/out/index.html and out/graph.html from state/tasks.md, tasks/T-*.md and git history.

Run from anywhere:  python dashboard/build.py
Read-only for the project: writes only dashboard/out/ (git-ignored). Data contract between this script and the
page templates: dashboard/README.md. Versions of the dashboard itself: dashboard/snapshot.py.
"""
import json, re, subprocess, sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = HERE / "out"
LEDGER = ROOT / "state" / "tasks.md"
TASKS = ROOT / "tasks"
PROJECT = ROOT.name

LEDGER_STATUSES = {"ready", "in progress", "review", "done", "rejected", "blocked", "cancelled"}  # protocol, "Task lifecycle"
LEGACY_STATUS = {"failed": "rejected", "partial": "review", "rework": "rejected"}  # AgentFlow 1.x ledger words
FINAL = {"done", "rejected", "cancelled"}
RESULT_LABEL = {  # Result `Outcome:` (2.x) or `Status:` (1.x) in a Task File -> label. Not acceptance.
    "completed": "Completed by worker", "done": "Completed by worker", "partial": "Partially completed",
    "blocked": "Worker blocked", "failed": "Worker failed", "rolled back": "Deployment rolled back",
}
NO_REPORT = "No report"
ROLES = {"developer", "tester", "deployer"}
AGENTS = (("claude", "Claude Code"), ("codex", "Codex"), ("antigravity", "Antigravity"), ("agy", "Antigravity"))


def split_row(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def tool_family(raw):
    """the agent that did the work (not the role): Claude Code / Codex / Antigravity; a handoff `a -> b` counts the last one"""
    s = raw.lower()
    if "→" in s or "->" in s:
        s = re.split(r"→|->", s)[-1]
    for key, label in AGENTS:
        if key in s:
            return label
    return raw.strip() or "Not set"


def field(text, name):
    m = re.search(rf"^{re.escape(name)}:[ \t]*(.*?)[ \t]*(?:<!--.*)?$", text, re.M)
    return m.group(1).strip() if m else ""


def section(text, name):
    m = re.search(rf"^## {re.escape(name)}\s*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1).strip() if m else ""


def git_dates():
    """file -> (first commit, last commit) for tasks/*.md"""
    out = subprocess.run(["git", "log", "--format=@%aI", "--name-only", "--", "tasks"],
                         cwd=ROOT, capture_output=True, text=True, encoding="utf-8").stdout
    first, last, cur = {}, {}, None
    for line in out.splitlines():
        if line.startswith("@"):
            cur = line[1:]
        elif line.strip() and cur:
            f = line.strip()
            last.setdefault(f, cur)  # the log runs newest to oldest
            first[f] = cur
    return first, last


def short(s, n):
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def parse_deps(s):
    return sorted(set(re.findall(r"T-\d{3}", s)))


def norm_status(raw):
    k = raw.strip().lower()
    return k if k in LEDGER_STATUSES else LEGACY_STATUS.get(k) or raw.strip()


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8").stdout


def ledger_rows(text):
    lines = text.split("\n")
    head = next((i for i, l in enumerate(lines) if l.startswith("| ID ")), None)
    if head is None:
        return {}
    cols = split_row(lines[head])
    out = {}
    for l in lines[head + 2:]:
        if not l.startswith("| T-"):
            break
        r = dict(zip(cols, split_row(l)))
        out[r["ID"]] = r
    return out


def history():
    """Replays the git history of state/tasks.md: statuses and dependencies over time."""
    log = git("log", "--reverse", "--format=%H\t%aI\t%s", "--", "state/tasks.md").strip().splitlines()
    timeline, edges, open_edges, commits = {}, [], {}, []
    prev_status, prev_deps = {}, {}
    for l in log:
        h, ts, subj = l.split("\t", 2)
        commits.append([ts, subj])
        cur = ledger_rows(git("show", f"{h}:state/tasks.md"))
        for tid, r in cur.items():
            st = norm_status(r.get("Status", ""))
            if prev_status.get(tid) != st:
                timeline.setdefault(tid, []).append([ts, st])
                prev_status[tid] = st
            deps = set(re.findall(r"T-\d{3}", r.get("Depends on", ""))) - {tid}
            old = prev_deps.get(tid, set())
            for d in deps - old:
                open_edges[(d, tid)] = ts
            for d in old - deps:
                edges.append({"from": d, "to": tid, "kind": "dep", "t0": open_edges.pop((d, tid), ts), "t1": ts})
            prev_deps[tid] = deps
    for (d, tid), t0 in open_edges.items():
        edges.append({"from": d, "to": tid, "kind": "dep", "t0": t0, "t1": None})
    return timeline, edges, commits


def successor_edges(tasks):
    """dead task -> its successor: `-> T-xxx` in the dead task's Notes (protocol convention), or "successor of / replaces / retry of T-xxx" on the new one"""
    pairs = set()
    for t in tasks.values():
        if t["status"] in ("rejected", "cancelled"):
            for m in re.findall(r"(?:->|→)\s*(T-\d{3})", t["notes"]):
                if m in tasks and m != t["id"]:
                    pairs.add((t["id"], m))
        for m in re.findall(r"(?:successor of|replaces|rework of|retry of|re-?issue of)\s*`?(T-\d{3})", t["title"] + " " + t["notes"], re.I):
            if m in tasks and m != t["id"] and tasks[m]["status"] in ("rejected", "cancelled"):
                pairs.add((m, t["id"]))
    return [{"from": a, "to": b, "kind": "succ"} for a, b in sorted(pairs)]


def check_edges(tasks):
    out = []
    for t in tasks.values():
        if t["role"] == "tester":
            m = [x for x in re.findall(r"T-\d{3}", t["title"]) if x != t["id"] and x in tasks]
            if m:
                out.append({"from": t["id"], "to": m[0], "kind": "check"})
    return out


def chains(tasks, succ):
    parent = {i: i for i in tasks}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for e in succ:
        parent[find(e["from"])] = find(e["to"])
    return {i: find(i) for i in tasks}


def terminal_end(tl):
    """time of entering the trailing run of final statuses; None if the task is not closed"""
    if not tl or tl[-1][1] not in FINAL:
        return None
    i = len(tl) - 1
    while i > 0 and tl[i - 1][1] in FINAL:
        i -= 1
    return tl[i][0]


OWN_RE = re.compile(
    r"(remarks?|bugs?|requests?|review|feedback)\s+(from|by)\s+(the\s+)?(owner|human|user)"
    r"|(owner|human|user)\s+(\d{4}-\d\d-\d\d\s+)?(request(ed|s)?|report(ed|s)?|wants?|asked|found|noticed|chose|demanded|said|wrote)"
    r"|owner-reported|owner review|human review", re.I)


def origins(tasks, goal_text):
    """Who set the task - an estimate from the text: tester/deployer (links to their report) > human (their remark) > orchestrator."""
    for t in tasks.values():
        txt = t["title"] + " " + t["notes"]
        why = None
        if t["role"] != "tester":
            for ref in sorted(set(re.findall(r"T-\d{3}", txt))):
                r = tasks.get(ref)
                if r and r["id"] != t["id"] and r["role"] in ("tester", "deployer") and r["c0"] < t["c0"]:
                    t["origin"], why = r["role"], f"finding in {ref} ({r['role']})"
                    break
        if why is None:
            m = OWN_RE.search(txt + " " + goal_text.get(t["id"], ""))
            if m:
                t["origin"], why = "human", "\"" + m.group(0).strip() + "\""
        if why is None:
            t["origin"], why = "orchestrator", "default: the Orchestrator writes the Task File"
        t["originWhy"] = why


SKIP_RE = re.compile(r"package-lock\.json|\.lock$|\.lockb$|\.(png|jpe?g|gif|webp|svg|ico|mp4|webm|pdf|woff2?|zip)$", re.I)  # lockfiles and binary assets: not counted
DOC_RE = re.compile(r"^(docs|tasks|state|runbook|screenshots)/|\.md$", re.I)


def sizes():
    """change size per worker commit (subject starts with [T-NNN]); code = everything except docs/tasks/state/runbook and *.md"""
    out = git("log", "--all", "--numstat", "--format=@%H|%s")
    res, cur = {}, None
    for line in out.splitlines():
        if line.startswith("@"):
            subj = line[1:].split("|", 1)[1] if "|" in line else ""
            m = re.match(r"\[(T-\d{3})\]", subj)
            cur = res.setdefault(m.group(1), {"commits": 0, "files": set(), "codeFiles": set(), "add": 0, "del": 0, "codeAdd": 0, "codeDel": 0}) if m else None
            if cur is not None:
                cur["commits"] += 1
        elif cur is not None and line.count("\t") >= 2:
            a, d, path = line.split("\t", 2)
            if SKIP_RE.search(path):
                continue
            a = int(a) if a.isdigit() else 0
            d = int(d) if d.isdigit() else 0
            cur["files"].add(path); cur["add"] += a; cur["del"] += d
            if not DOC_RE.search(path):
                cur["codeFiles"].add(path); cur["codeAdd"] += a; cur["codeDel"] += d
    for v in res.values():
        v["files"] = len(v["files"]); v["codeFiles"] = len(v["codeFiles"])
    return res


def size_class(z):
    if not z or not z["files"]:
        return "—"
    n = z["codeAdd"] + z["codeDel"]
    return "docs" if n == 0 else "S" if n < 50 else "M" if n < 300 else "L" if n < 1000 else "XL"


COMMIT_LINE = re.compile(r"^[ \t]*(?:[-*][ \t]+)?(Commit|Change)[ \t]*:[ \t]*(.+?)[ \t]*$", re.M)
SHA_RE = re.compile(r"\b(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b")


def report_commit(res):
    """The commit the worker named explicitly in a `Commit:` or `Change:` line of the report.
    Taken only if all such lines hold exactly one hash; otherwise (none, or several) there is no value."""
    clean = re.sub(r"<!--.*?-->", "", res, flags=re.S)
    found, first = [], None
    for label, rest in COMMIT_LINE.findall(clean):
        lead = re.match(r"[`'\"]?([0-9a-f]{7,40})", rest)          # a hash right after the label; all-digit hashes allowed here
        for sha in ([lead.group(1)] if lead else []) + SHA_RE.findall(rest):
            if sha not in found:
                found.append(sha)
            first = first or (label, rest)
    if len(found) != 1:
        return None
    return {"sha": found[0], "label": first[0] + ":", "line": first[1][:200]}


def main():
    text = LEDGER.read_text(encoding="utf-8-sig")
    head = next(i for i, l in enumerate(text.split("\n")) if l.startswith("| ID "))
    lines = text.split("\n")
    cols = split_row(lines[head])
    rows = []
    for l in lines[head + 2:]:
        if not l.startswith("| T-"):
            break
        rows.append(dict(zip(cols, split_row(l))))

    files = {p.name.split("-")[0] + "-" + p.name.split("-")[1]: p for p in TASKS.glob("T-*.md")}
    first, last = git_dates()
    tasks = {}
    goalText = {}
    for r in rows:
        tid = r["ID"]
        p = files.get(tid)
        body = p.read_text(encoding="utf-8-sig") if p else ""
        res = section(body, "Result")
        res_raw = (field(res, "Outcome") or field(res, "Status")).lower()
        res_key = next((k for k in RESULT_LABEL if res_raw.startswith(k)), "")
        ind_raw = field(body, "Independent check").lower()
        ind = "tester" if ind_raw.startswith("tester") else "none" if ind_raw.startswith("none") else ""
        status = norm_status(r["Status"])
        rel = f"tasks/{p.name}" if p else ""
        upd = r.get("Updated", "")
        created = first.get(rel, "")[:10]
        t = {
            "id": tid, "title": r["Title"], "stage": r["Stage"] or "—",
            "role": r["Role"].strip().lower(), "tool": tool_family(r["Tool"]),
            "toolRaw": r["Tool"],
            "status": status, "final": status in FINAL,
            "result": RESULT_LABEL.get(res_key, NO_REPORT),
            "outcomeSrc": "Outcome" if field(res, "Outcome") else ("Status" if field(res, "Status") else ""),
            "outcomeRaw": (field(res, "Outcome") or field(res, "Status"))[:240],
            "reportCommit": report_commit(res),
            "ind": ind, "verdict": field(res, "Verdict").lower().split()[0] if field(res, "Verdict") else "",
            "deps": parse_deps(r.get("Depends on", "")), "commit": r.get("Commit / artifact", ""),
            "notes": r.get("Notes", ""), "file": rel,
            "created": created or (upd[:10] if upd else ""),
            "updated": upd[:10] or (last.get(rel, "")[:10]),
            "goal": short(section(body, "Goal"), 900),
            "goalFull": re.sub(r"<!--.*?-->", "", section(body, "Goal"), flags=re.S).strip(),
            "resultFull": re.sub(r"<!--.*?-->", "", res, flags=re.S).strip(),
            "body": re.sub(r"[ \t]+", " ", body),
            "resultText": short(res, 1200),
            "attemptsHint": body.count("Attempt "),
        }
        t["c0"] = 0
        goalText[tid] = body.split("## Result")[0][:2500]
        tasks[tid] = t

    # who checked: a tester task names the checked task as the first T-NNN in its title
    verdicts = {}
    for t in tasks.values():
        if t["role"] == "tester":
            m = [x for x in re.findall(r"T-\d{3}", t["title"]) if x != t["id"]]
            if m:
                verdicts.setdefault(m[0], []).append((t["id"], t["verdict"], t["status"]))
    for t in tasks.values():
        t["checkedBy"] = verdicts.get(t["id"], [])
        if t["role"] != "developer":
            t["check"] = "—"
        elif t["checkedBy"]:
            vs = [v for _, v, st in t["checkedBy"] if st != "cancelled"]
            if "fail" in vs: t["check"] = "Tester: fail"
            elif "partial" in vs or "unverified" in vs: t["check"] = "Tester: partial"
            elif "pass" in vs: t["check"] = "Tester: pass"
            else: t["check"] = "Tester assigned"
        elif t["ind"] == "tester": t["check"] = "Tester needed, no report"
        elif t["ind"] == "none": t["check"] = "No independent check"
        else: t["check"] = "Not set (older task)"
        t["blockedBy"] = [d for d in t["deps"] if d in tasks and not tasks[d]["final"] and tasks[d]["status"] != "done"]
        t["blocks"] = []
        t["waitsOwner"] = (not t["final"]) and bool(re.search(r"owner|human", t["notes"], re.I)) and t["status"] in ("blocked", "ready", "review")
    for t in tasks.values():
        for d in t["deps"]:
            if d in tasks:
                tasks[d]["blocks"].append(t["id"])

    timeline, dep_edges, commits = history()
    for t in tasks.values():
        tl = timeline.get(t["id"]) or [[datetime.fromisoformat(t["created"] or datetime.now().strftime("%Y-%m-%d")).astimezone().isoformat(), t["status"]]]
        t["timeline"] = tl
        t["createdAt"] = min([tl[0][0]] + ([first[t["file"]]] if t["file"] in first else []), key=lambda x: datetime.fromisoformat(x))
        t["endAt"] = terminal_end(tl)
    for t in tasks.values():
        t["c0"] = datetime.fromisoformat(t["createdAt"]).timestamp()
    origins(tasks, goalText)
    succ = successor_edges(tasks)
    ch = chains(tasks, succ)
    for t in tasks.values():
        t["chain"] = ch[t["id"]]
    allc = [l.split("|", 1) for l in git("log", "--all", "--format=%aI|%s").splitlines() if "|" in l]
    pings = sorted(ts for ts, _ in allc)
    work = {}  # worker commits: subject starts with [T-NNN]
    for ts, subj in allc:
        m = re.match(r"\[(T-\d{3})\]", subj)
        if m:
            work.setdefault(m.group(1), []).append(ts)
    for t in tasks.values():
        t["work"] = sorted(work.get(t["id"], []))
    sz = sizes()
    for t in tasks.values():
        t["size"] = sz.get(t["id"]) if sz.get(t["id"], {}).get("files") else None
        t["sizeCls"] = size_class(t["size"])
        t["sizeN"] = (t["size"]["codeAdd"] + t["size"]["codeDel"]) if t["size"] else 0
    graph = {"project": PROJECT, "generated": datetime.now().strftime("%Y-%m-%d %H:%M"), "now": datetime.now().astimezone().isoformat(timespec="seconds"),
             "tasks": list(tasks.values()), "edges": dep_edges + succ + check_edges(tasks), "commits": commits, "pings": pings}
    payload = json.dumps(graph, ensure_ascii=False).replace("</", "<\\/")  # both pages get the same data
    OUT.mkdir(exist_ok=True)
    for tpl_name, out_name in (("graph_template.html", "graph.html"), ("template.html", "index.html")):
        page = render(tpl_name).replace("__PROJECT__", PROJECT).replace("__DATA__", payload)
        (OUT / out_name).write_text(page, encoding="utf-8")
    print(f"{len(tasks)} tasks, {len(dep_edges)} dependencies, {len(succ)} replacements, {len(pings)} commits -> {OUT}")


def render(name):
    """a page template with the shared CSS/JS inlined, so each page is one self-contained file"""
    page = (HERE / name).read_text(encoding="utf-8")
    for marker, src in (("/*FILTERBAR_CSS*/", "filterbar.css"), ("/*FILTERBAR_JS*/", "filterbar.js"),
                        ("/*COMMON_CSS*/", "common.css"), ("/*COMMON_JS*/", "common.js")):
        page = page.replace(marker, (HERE / src).read_text(encoding="utf-8"))
    return page


if __name__ == "__main__":
    sys.exit(main())
