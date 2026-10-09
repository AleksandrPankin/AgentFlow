#!/usr/bin/env python3
"""Task gates: Task File parsing, launch preflight, acceptance verify, Stage check.

  python tools/gate.py verify T-007      acceptance evidence for one task; appends to tasks/.runtime/T-007.verify.json
  python tools/gate.py stage 2           every Stage 2 task done and its Checks pass on the main branch
  python tools/gate.py spec              Product definition items in docs/product/: IDs, statuses, priorities,
                                         Must FR without AC, APPROVED with a done owner task, Vision / Brief ceiling

Used by tools/run-task.ps1 (pure logic here, side effects there):
  python tools/gate.py task T-007 --out f.json
  python tools/gate.py preflight T-007 [--manual] [--live T-1,T-2] --out f.json
  python tools/gate.py endcheck T-007 --out f.json
  python tools/gate.py result T-007 --out f.json

Rules: docs/ai-handoff-protocol.md. Exit code: 0 pass, 1 fail, 2 gate error.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ledger  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "tasks"
RUNTIME = TASKS / ".runtime"
PRODUCT = ROOT / "docs" / "product"
SHA = r"[0-9a-fA-F]{7,40}"
VERDICTS = ["pass", "partial", "unverified", "fail"]  # worst last
SPEC_STATUSES = ["APPROVED", "PROPOSED", "DRAFT", "STALE", "SUPERSEDED"]  # best first
IMPLEMENTABLE = ("APPROVED", "PROPOSED")


class TaskError(Exception):
    pass


# --- Task File parsing. HTML comments (template hints) are not content.
def section(text, name):
    m = re.search(rf"(?ms)^## {re.escape(name)}[ \t]*\r?\n(.*?)(?=^## |\Z)", text)
    return re.sub(r"(?s)<!--.*?-->", "", m.group(1)) if m else ""


def field(text, name):
    m = re.search(rf"(?m)^{re.escape(name)}[ \t]*:[ \t]*(.+?)[ \t]*(<!--.*)?$", text)
    return m.group(1).strip() if m else None


def header(text):  # everything above "## Result": the worker must not change it
    return re.sub(r"(?ms)^## Result[ \t]*$.*\Z", "", text.replace("\r\n", "\n"))


def sha256(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def bullets(body):
    return [m.group(1) for m in re.finditer(r"(?m)^[ \t]*-[ \t]+(.+?)[ \t]*$", body)]


def paths(body):  # first token of each bullet that looks like a path: "- `src/a.ts` - why"
    out = []
    for b in bullets(body):
        m = re.match(r"^`([^`]+)`", b)
        tok = m.group(1) if m else b.split()[0]
        if re.search(r"[\\/.*]", tok):
            out.append(re.sub(r"^\./", "", tok.replace("\\", "/")).rstrip("/").lower())
    return out


def commands(body):
    return [m.group(1) for b in bullets(body) if (m := re.search(r"`([^`]+)`", b))]


def glob_match(pattern, path):  # * and ** both match across '/': conservative
    if not re.search(r"[*?]", pattern):
        return False
    rx = "^" + re.sub(r"(\\\*)+", ".*", re.escape(pattern)).replace(r"\?", ".") + "(/.*)?$"
    return re.match(rx, path) is not None


def overlap(a, b):  # same file, one folder contains the other, or a glob matches
    return a == b or a.startswith(b + "/") or b.startswith(a + "/") or glob_match(a, b) or glob_match(b, a)


def task_file(tid):
    hits = sorted(TASKS.glob(f"{tid}-*.md"))
    if not hits:
        raise TaskError(f"Task File tasks/{tid}-*.md not found")
    return hits[0]


def git(*args, cwd=ROOT):
    r = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, encoding="utf-8")
    return r.stdout.strip() if r.returncode == 0 else None


def git_ok(*args, cwd=ROOT):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True).returncode == 0


def main_branch():
    return git("rev-parse", "--abbrev-ref", "HEAD") or "main"


def parse(tid):
    """Fields of one Task File. Raises TaskError when a role-required field is missing or malformed."""
    f = task_file(tid)
    text = f.read_text(encoding="utf-8-sig")
    t = {"id": tid, "file": str(f), "rel": f"tasks/{f.name}", "role": field(text, "Role"),
         "branch": field(text, "Branch"), "worktree": field(text, "Worktree"),
         "depends": re.findall(r"T-\d+", field(text, "Depends on") or ""),
         "allowed": paths(section(text, "Allowed files")), "denied": paths(section(text, "Do not touch")),
         "rebuild": [w for b in bullets(section(text, "Rebuild together")) if re.search(r"[a-z0-9]", w := b.replace("`", "").split()[0].lower())],
         "checks": commands(section(text, "Checks")), "acceptance": bullets(section(text, "Acceptance criteria")),
         "independent": field(text, "Independent check"), "target": "local", "env": {}, "setup": [],
         "headerHash": sha256(header(text)), "result": section(text, "Result"),
         "modelSpec": field(text, "Model"), "effortSpec": field(text, "Effort"), "spec": field(text, "Spec")}
    t["prompt"] = (f"Your role: roles/{t['role']}.md. Your task: {f}. "
                   "Follow docs/ai-handoff-protocol.md, section 'Starting a role session'.")
    setup = section(text, "Setup") + "\n" + section(text, "Port")
    for m in re.finditer(r"(?m)^[ \t]*-[ \t]*(link|copy|env)[ \t]*:[ \t]*(.+?)[ \t]*$", setup):
        if m.group(1) == "env":
            k, _, v = m.group(2).partition("=")
            t["env"][k.strip()] = v.strip()
        else:
            t["setup"].append({"kind": m.group(1), "path": m.group(2)})
    if m := re.search(r"(?m)^[ \t]*PORT[ \t]*=[ \t]*(\d+)", setup):
        t["env"]["PORT"] = m.group(1)

    role = t["role"]
    if role in ("tester", "deployer") and (tg := field(text, "Target")):
        if tg not in ("staging", "prod"):
            raise TaskError(f"Target '{tg}': expected staging or prod")
        t["target"] = tg
    if role == "developer":
        t["workdir"] = t["worktree"]
    elif role == "tester":
        m = re.match(rf"^(T-\d+)\s*@\s*({SHA})$", field(text, "Verifies") or "")
        if not m:
            raise TaskError('tester task needs "Verifies: T-xxx @ <SHA>"')
        t["sha"] = m.group(2).lower()
        cf = task_file(m.group(1))
        ct = cf.read_text(encoding="utf-8-sig")
        t["checked"] = {"id": m.group(1), "file": str(cf), "branch": field(ct, "Branch"),
                        "worktree": field(ct, "Worktree"), "result": section(ct, "Result")}
        if not t["checked"]["worktree"]:
            raise TaskError(f"checked task {cf.name} has no Worktree")
        t["workdir"] = f"{t['checked']['worktree']}.{tid.lower()}"  # disposable checkout of the checked commit
    elif role == "deployer":
        m = re.match(rf"^({SHA})", field(text, "Deploys") or "")
        if not m:
            raise TaskError('deployer task needs "Deploys: <SHA>"')
        t["sha"] = m.group(1).lower()
        if t["target"] == "local":
            raise TaskError('deployer task needs "Target: staging | prod"')
        t["workdir"] = str(ROOT)
    else:
        raise TaskError(f"Role '{role}': expected developer, tester or deployer")
    return t


def resolve_model(t, tool):
    """Task File Model / Effort -> {"model", "effort"} for the launch tool, plus problems. Table: tools/models.json."""
    spec, eff = t.get("modelSpec"), t.get("effortSpec")
    out, bad = {"model": None, "effort": None}, []
    if spec in (None, "default") and eff in (None, "default"):
        return out, bad  # today's behaviour: no flag
    table = json.loads((ROOT / "tools" / "models.json").read_text(encoding="utf-8"))
    conf = table["tools"].get(tool or "")
    if not conf:
        return out, bad  # manual or an unknown tool: the field is informational
    tiers = conf["tiers"]
    if spec not in (None, "default"):
        env = os.environ.get(f"AGENTFLOW_MODEL_{tool.upper()}_{spec.upper()}") if spec in tiers else None
        if spec in tiers:
            out["model"] = env or tiers[spec]
        elif spec in conf["models"]:
            out["model"] = spec
        else:
            bad.append(f"Model '{spec}' is not valid for {tool}: tiers {', '.join(['default'] + list(tiers))}; "
                       f"ids {', '.join(conf['models'])} (tools/models.json)")
    if eff not in (None, "default"):
        if eff not in conf["efforts"]:
            bad.append(f"Effort '{eff}' is not valid for {tool}: {', '.join(['default'] + conf['efforts'])}")
        elif out["model"] in conf.get("noEffort", []):
            bad.append(f"Effort: {out['model']} takes no effort setting; use Effort: default or another model")
        else:
            out["effort"] = eff
    return out, bad


def baseline(t):
    """What the worker must not change during an attempt (protocol: Review isolation)."""
    b = {"taskHash": t["headerHash"]}
    if t["role"] == "tester":
        c = t["checked"]
        b["checkedRef"] = git("rev-parse", "--verify", "--quiet", f"{c['branch']}^{{commit}}") if c["branch"] else None
        wt = Path(c["worktree"])
        b["checkedTree"] = sha256((git("rev-parse", "HEAD", cwd=wt) or "") + (git("status", "--porcelain", cwd=wt) or "")) if wt.exists() else None
        b["checkedFileHash"] = sha256(Path(c["file"]).read_text(encoding="utf-8-sig"))
    return b


def result_field(t, name):
    return field(t["result"], name)


def ledger_rows():
    path = ledger.ledger_path()
    if not path.exists():
        return {}
    _, cols, rows, _, _ = ledger.load(path)
    return {r[0]: dict(zip(cols, r)) for r in rows}


def runtime(tid):
    p = RUNTIME / f"{tid}.json"
    return json.loads(p.read_text(encoding="utf-8-sig")) if p.exists() else None


def last_attempt(tid):
    rt = runtime(tid)
    return rt["attempts"][-1] if rt and rt.get("attempts") else None


# --- Product definition: spec items in docs/product/ (protocol: Product definition). 05-09 explain or report: no items there.
ITEM_HEAD = re.compile(r"^#{1,4}[ \t]+([A-Z]{1,4}-\d+)\b")  # "### FR-012 — title"
ITEM_STATUS = re.compile(r"^[ \t]*[-*][ \t]+\*\*(?:Статус|Status)[ \t]*:?[ \t]*\*\*[ \t]*:?[ \t]*`?([^\s`*.,;]+)")
ITEM_SOURCE = re.compile(r"^[ \t]*[-*][ \t]+\*\*Source[ \t]*:?[ \t]*\*\*[ \t]*:?(.*)$")
ITEM_PRIORITY = re.compile(r"^[ \t]*[-*][ \t]+\*\*(?:Приоритет|Priority)[ \t]*:?[ \t]*\*\*[ \t]*:?[ \t]*`?([^\s`*.,;:—–-]+)")
PRIORITIES = ("must", "should", "could", "won't", "won’t", "later")  # an unknown word is an error, never a silent non-Must
STATUS_KINDS = ("FR", "NFR", "ADR")  # carry their own Статус; an AC takes the worst of its FR / NFR sources
DOCS = ("01_VISION.md", "02_BRIEF.md")  # one status in front matter: a ceiling for every item (weakest link)
SPEC_REF = r"\b(?:[A-Z]{1,4}-\d+|[A-Z]{1,2}\d{2})\b"  # FR-012, ADR-006, B04, AR05
OWN = r"\bOWN-\d+\b"  # owner task: "APPROVED (OWN-012)" names the human's answer


def spec_files():
    return [f for f in sorted(PRODUCT.rglob("*.md")) if not re.match(r"0[5-9]_", f.name)]


def spec_items():
    """{id: {file, line, status, own, sources, priority}} of docs/product/, and problems for IDs defined twice."""
    items, dups = {}, []
    for f in spec_files():
        rel, cur = f.relative_to(ROOT).as_posix(), None
        for n, line in enumerate(f.read_text(encoding="utf-8-sig").splitlines(), 1):
            if re.match(r"^#{1,6}[ \t]", line):
                cur = None
                if m := ITEM_HEAD.match(line):
                    if m.group(1) in items:
                        it = items[m.group(1)]
                        dups.append(f"{m.group(1)} defined twice: {it['file']}:{it['line']} and {rel}:{n}")
                    else:
                        cur = items[m.group(1)] = {"file": rel, "line": n, "status": None, "own": [], "sources": [], "priority": None}
            elif cur is not None:
                if (m := ITEM_STATUS.match(line)) and cur["status"] is None:
                    cur["status"], cur["own"] = m.group(1).upper(), re.findall(OWN, line)
                elif m := ITEM_SOURCE.match(line):
                    cur["sources"] += re.findall(r"\b(?:FR|NFR)-\d+\b", m.group(1))
                elif (m := ITEM_PRIORITY.match(line)) and cur["priority"] is None:
                    cur["priority"] = m.group(1).lower()
    return items, dups


def doc_statuses():
    """{file: {file, line, status, own}} from the front matter of Vision and Brief; a missing file sets no ceiling."""
    docs = {}
    for name in DOCS:
        f = PRODUCT / name
        if not f.exists():
            continue
        lines = f.read_text(encoding="utf-8-sig").splitlines()
        end = lines.index("---", 1) if lines[:1] == ["---"] and "---" in lines[1:] else 0
        n, line = next(((n, l) for n, l in enumerate(lines[1:end], 2) if re.match(r"status[ \t]*:", l)), (1, ""))
        m = re.match(r"status[ \t]*:[ \t]*['\"]?([^\s'\"#]+)", line)
        docs[name] = {"file": f"docs/product/{name}", "line": n, "status": m.group(1).upper() if m else None, "own": re.findall(OWN, line)}
    return docs


def item_status(items, iid, docs):
    """(status, where) deciding whether an item is implementable: its own (FR, NFR, ADR) or the worst of its FR / NFR
    sources (AC), never better than Vision and Brief (weakest link). An invalid status wins and is returned as is."""
    it = items[iid]
    if iid.split("-")[0] in STATUS_KINDS:
        cands = [(it["status"], f"{it['file']}:{it['line']}")]
    else:
        cands = [(items[s]["status"], f"{items[s]['file']}:{items[s]['line']}") for s in it["sources"] if s in items]
    if not cands:
        return None, f"{it['file']}:{it['line']}"
    cands += [(d["status"], f"{d['file']}:{d['line']}") for d in docs.values()]
    invalid = [c for c in cands if c[0] not in SPEC_STATUSES]
    return invalid[0] if invalid else max(cands, key=lambda c: SPEC_STATUSES.index(c[0]))


def spec_status_problems(spec):
    """Items named by a "Spec:" line that are missing or not implementable."""
    if not spec or re.match(r"^(none|spike)\b", spec):
        return []
    items, _ = spec_items()
    docs, bad, text = doc_statuses(), [], None
    for i in re.findall(SPEC_REF, spec):
        if i in items and (i.split("-")[0] in STATUS_KINDS or i.startswith("AC-")):
            st, where = item_status(items, i, docs)
            if st not in IMPLEMENTABLE:
                bad.append(f"Spec {i} is {st if st in SPEC_STATUSES else 'without a valid status'} ({where}), needs PROPOSED or APPROVED")
        elif i not in items:
            text = text if text is not None else "\n".join(f.read_text(encoding="utf-8-sig") for f in spec_files())
            if i.split("-")[0] in STATUS_KINDS + ("AC",) or not re.search(rf"\b{re.escape(i)}\b", text):
                bad.append(f"Spec {i} not found in docs/product/")
    return bad


def spec_problems(t):
    """Preflight with Product definition: Spec items exist and are implementable; no worker changes docs/product/."""
    bad = [f"Allowed files '{a}' is in docs/product/: workers propose spec changes in the Result"
           for a in t["allowed"] if overlap(a, "docs/product")]
    spec = t.get("spec")
    if not spec:
        if t["role"] == "developer":
            bad.append('developer task needs "Spec: <IDs> | none - <reason> | spike - <Q-ID>" (docs/product/ exists)')
        return bad
    if m := re.match(r"^(none|spike)\b", spec):
        if not re.match(r"^(none|spike)[ \t]*-[ \t]*[^<\s]", spec):
            bad.append(f'Spec "{spec}": write "{m.group(1)} - <reason or Q-ID>"')
        return bad
    if not re.findall(SPEC_REF, spec):
        return bad + [f'Spec "{spec}": no item IDs (FR-012, AC-012, ADR-006)']
    return bad + spec_status_problems(spec)


def owner_done():
    """IDs of owner tasks marked done ("- [x] **OWN-012 · ...") in state/owner-tasks.md."""
    f = ROOT / "state" / "owner-tasks.md"
    return set(re.findall(rf"(?m)^[ \t]*[-*][ \t]+\[[xX]\][^\n]*?({OWN})", f.read_text(encoding="utf-8-sig"))) if f.exists() else set()


def spec_lint():
    if not (PRODUCT / "00_INDEX.md").exists():
        print("spec: no docs/product/00_INDEX.md, Product definition is not active")
        return True
    items, bad = spec_items()
    docs, done = doc_statuses(), owner_done()
    bad += [f"{d['file']}:{d['line']}: front matter status '{d['status'] or ''}', expected {' | '.join(SPEC_STATUSES)}"
            for d in docs.values() if d["status"] not in SPEC_STATUSES]
    ceiling = [d for d in docs.values() if d["status"] not in IMPLEMENTABLE]
    for iid, it in items.items():
        at, kind = f"{it['file']}:{it['line']}", iid.split("-")[0]
        if kind in STATUS_KINDS and it["status"] not in SPEC_STATUSES:
            bad.append(f"{iid} ({at}): status '{it['status'] or ''}', expected {' | '.join(SPEC_STATUSES)}")
        if kind in STATUS_KINDS and it["status"] in IMPLEMENTABLE:
            bad += [f"{iid} ({at}) is {it['status']}, but {d['file']} is {d['status'] or 'without a status'}: "
                    "an item is never ahead of Vision and Brief" for d in ceiling]
        if kind in ("FR", "NFR") and it["status"] != "SUPERSEDED" and it["priority"] not in PRIORITIES:
            bad.append(f"{iid} ({at}): priority '{it['priority'] or ''}', expected Must | Should | Could | Won't | Later")
        if iid.startswith("AC-") and not [s for s in it["sources"] if s in items]:
            bad.append(f"{iid} ({at}): Source names no FR / NFR of docs/product/")
    for key, it in list(items.items()) + list(docs.items()):
        if it["status"] == "APPROVED":
            at = f"{it['file']}:{it['line']}"
            if not it["own"]:
                bad.append(f"{key} ({at}): APPROVED needs the owner task that approved it: APPROVED (OWN-###)")
            bad += [f"{key} ({at}): APPROVED by {o}, which is not done ([x]) in state/owner-tasks.md" for o in it["own"] if o not in done]
    covered = {s for i, it in items.items() if i.startswith("AC-") for s in it["sources"]}
    bad += [f"{i} ({it['file']}:{it['line']}): Must without an AC (no AC has Source: {i})" for i, it in items.items()
            if i.startswith("FR-") and it["priority"] == "must" and it["status"] != "SUPERSEDED" and i not in covered]
    count = {s: sum(1 for i, it in items.items() if i.split("-")[0] in STATUS_KINDS and it["status"] == s) for s in SPEC_STATUSES}
    print(f"spec: {'PASS' if not bad else 'FAIL'} ({len(items)} items; " + ", ".join(f"{s} {n}" for s, n in count.items())
          + "".join(f"; {n} {d['status']}" for n, d in docs.items()) + ")")
    for b in bad:
        print(f"  - {b}")
    return not bad


# --- preflight: all problems at once, before anything is created (protocol: Launching workers, rule 9)
def preflight(tid, manual, live, tool=None):
    bad = []
    try:
        t = parse(tid)
    except TaskError as e:
        return None, [str(e)]
    t["launch"], more = resolve_model(t, None if manual else tool)
    bad += more
    tpl = (TASKS / "_template.md").read_text(encoding="utf-8-sig")
    led = ledger_rows()
    status = {k: v.get("Status", "") for k, v in led.items()}
    role, pre_merge = t["role"], t["role"] == "tester" and t["target"] == "local"

    if not manual and role == "deployer":
        bad.append("a Deployer runs in the platform project session (Project rules ## Deploy) or one the human designated: use -Manual")
    if not manual and role == "tester" and t["target"] == "prod":
        bad.append("a live Tester on prod runs only in the session the human designated: use -Manual")
    if role == "developer":
        if not t["branch"] or not t["worktree"]:
            bad.append("developer task needs Branch and Worktree")
        elif not t["branch"].startswith(tid.lower() + "-"):
            bad.append(f"Branch '{t['branch']}' is not named after the task ({tid.lower()}-slug)")
        if not re.match(r"^(tester|none\b.*\S.*)$", t["independent"] or ""):
            bad.append('developer task needs "Independent check: tester | none - <reason>"')
    for s, own in (("Acceptance criteria", t["acceptance"]), ("Checks", bullets(section(Path(t["file"]).read_text(encoding="utf-8-sig"), "Checks")))):
        if not [b for b in own if b not in bullets(section(tpl, s))]:
            bad.append(f"## {s} is empty or still the template text")
    bad += [f"env: {k} is set by the launcher, not by a Task File" for k in t["env"] if k.startswith("AGENTFLOW_")]
    bad += [f"Allowed files '{a}' overlaps Do not touch '{d}'" for a in t["allowed"] for d in t["denied"] if overlap(a, d)]
    for s in t["setup"]:
        if not (ROOT / s["path"]).exists():
            bad.append(f"Setup {s['kind']}: {s['path']} is not in the main folder; build it there first")
    if (PRODUCT / "00_INDEX.md").exists():
        bad += spec_problems(t)

    checked = t.get("checked", {}).get("id")
    for d in t["depends"]:
        if d == checked and pre_merge:
            continue  # pre-merge tester: the checked task is in review, not done
        if status.get(d) != "done":
            bad.append(f"Depends on {d} is '{status.get(d, '')}' in the ledger, needs 'done'")
    if role == "tester":
        c = t["checked"]
        if pre_merge:
            head = git("rev-parse", "--verify", "--quiet", f"{c['branch']}^{{commit}}") if c["branch"] else None
            if not head or not head.startswith(t["sha"]):
                bad.append(f"branch '{c['branch']}' is at '{head}', task verifies {t['sha']}")
            if field(c["result"], "Outcome") != "completed":
                bad.append(f"checked task {checked} has no Result with Outcome: completed")
            elif not (field(c["result"], "Change") or "").lower().startswith(t["sha"][:7]):
                bad.append(f"checked task {checked} Result Change is not {t['sha']}")
        elif not git_ok("merge-base", "--is-ancestor", t["sha"], "HEAD"):
            bad.append(f"commit {t['sha']} is not merged into the main branch")
        if checked in live:
            bad.append(f"checked task {checked} still has a live worker")
    if role == "deployer" and not git_ok("merge-base", "--is-ancestor", t["sha"], "HEAD"):
        bad.append(f"commit {t['sha']} is not merged into the main branch")

    # other tasks: issued and not accepted (ledger) or with a worker process (runtime, also mid-launch or manual)
    open_ids = sorted({k for k, v in status.items() if v in ("in progress", "review")} | set(live))
    for oid in open_ids:
        if oid in (tid, checked):
            continue
        try:
            o = parse(oid)
        except TaskError as e:  # unknown never passes
            bad.append(f"open task {oid}: {e}")
            continue
        bad += [f"Allowed files '{a}' overlaps {oid} '{b}' (not merged yet)" for a in t["allowed"] for b in o["allowed"] if overlap(a, b)]
        bad += [f"Rebuild together '{r}' is shared with {oid}" for r in t["rebuild"] if r in o["rebuild"]]
        if oid in live and t["env"].get("PORT") and t["env"].get("PORT") == o["env"].get("PORT"):
            bad.append(f"PORT={t['env']['PORT']} is used by running {oid}")

    # project rules: "## Preflight" in docs/engineering-rules.md and/or AGENTS.md, for commands that run against local
    #   - deny: <regex>                  no Checks command or Setup line may match
    #   - require: <regex> => <regex>    a Checks command matching the first must match the second
    if t["target"] == "local":
        text = Path(t["file"]).read_text(encoding="utf-8-sig")
        run = t["checks"] + bullets(section(text, "Setup"))
        for src in (ROOT / "docs" / "engineering-rules.md", ROOT / "AGENTS.md"):
            if not src.exists():
                continue
            for r in bullets(section(src.read_text(encoding="utf-8-sig"), "Preflight")):
                try:
                    if m := re.match(r"^deny\s*:\s*`?(.+?)`?$", r):
                        bad += [f"'{c}' matches project deny rule '{m.group(1)}'" for c in run if re.search(m.group(1), c)]
                    elif m := re.match(r"^require\s*:\s*`?(.+?)`?\s*=>\s*`?(.+?)`?$", r):
                        bad += [f"'{c}' must match '{m.group(2)}' (project rule for '{m.group(1)}')"
                                for c in t["checks"] if re.search(m.group(1), c) and not re.search(m.group(2), c)]
                    else:
                        bad.append(f"project Preflight: unknown rule '{r}'")
                except re.error as e:
                    bad.append(f"project Preflight: bad rule '{r}': {e}")
    return t, bad


def endcheck(tid):
    """Compare the end of an attempt with its baseline. Returns the violations."""
    att = last_attempt(tid)
    if not att or "baseline" not in att:
        return ["no attempt baseline in runtime state"]
    t, then = parse(tid), att["baseline"]
    now = baseline(t)
    bad = []
    if now["taskHash"] != then.get("taskHash"):
        bad.append("Task File changed above ## Result")
    if t["role"] == "tester":
        c = t["checked"]
        if now["checkedRef"] != then.get("checkedRef"):
            bad.append(f"review isolation: branch {c['branch']} moved")
        if now["checkedTree"] != then.get("checkedTree"):
            bad.append(f"review isolation: worktree {c['worktree']} changed")
        if now["checkedFileHash"] != then.get("checkedFileHash"):
            bad.append(f"review isolation: Task File of {c['id']} changed")
    return bad


def shell(cmd):
    if os.name == "nt":
        return [shutil.which("pwsh") or "powershell", "-NoProfile", "-Command", cmd]
    return ["sh", "-c", cmd]


def run_checks(t, cwd, log):
    env = {**os.environ, **t["env"], "AGENTFLOW_TARGET": "local"}
    out = []
    with open(log, "a", encoding="utf-8") as fh:
        for c in t["checks"]:
            fh.write(f"\n$ {c}\n")
            fh.flush()
            r = subprocess.run(shell(c), cwd=cwd, env=env, stdout=fh, stderr=subprocess.STDOUT)
            out.append({"cmd": c, "exit": r.returncode})
    return out


def verdict_problems(result):
    v = field(result, "Verdict")
    if v not in VERDICTS:
        return [f"Result Verdict '{v}': expected {' | '.join(VERDICTS)}"], v
    found = re.findall(r"(?m)^[ \t]*-.*?[ \t]-[ \t](pass|partial|unverified|fail)\b", result)  # "- <criterion> - <verdict> - ..."
    worst = max(found, key=VERDICTS.index) if found else None
    if worst and VERDICTS.index(worst) > VERDICTS.index(v):
        return [f"Verdict {v} but a criterion is {worst} (overall = worst criterion)"], v
    return [], v


# --- result: what the worker's "## Result" says, for the launcher's -Wait (protocol: Runtime state)
OUTCOMES = ["completed", "blocked", "failed"]
DEPLOYMENTS = ["deployed", "rolled-back", "not-started"]


def last_result(text):
    """Body of the last "## Result" heading at line start. A worker may quote the heading inside its text."""
    text = text.replace("\r\n", "\n")
    ms = list(re.finditer(r"(?m)^## Result[ \t]*$", text))
    if not ms:
        return ""
    body = re.split(r"(?m)^## ", text[ms[-1].end():], maxsplit=1)[0]
    return re.sub(r"(?s)<!--.*?-->", "", body)


def loose_field(body, name, pattern):
    """Tolerant keyword read: `- **Outcome:** Completed.` counts; a pasted format line ("completed | blocked") does not."""
    for m in re.finditer(rf"(?mi)^[ \t>*_-]*{name}[ \t*_]*:[ \t*_`]*({pattern})\b(.*)$", body):
        if "|" not in m.group(2):
            return m.group(1).lower()
    return None


ROLE_FIELDS = {"developer": ("Change", SHA), "tester": ("Verdict", "|".join(VERDICTS)),
               "deployer": ("Deployment", "|".join(DEPLOYMENTS))}


def result_state(tid):
    """Class of the Result: completed | incomplete | blocked | failed | none, plus the role field (Change / Verdict / Deployment)."""
    text = task_file(tid).read_text(encoding="utf-8-sig")
    role = field(text, "Role")
    body = last_result(text)
    name, pattern = ROLE_FIELDS.get(role, (None, None))
    outcome = loose_field(body, "Outcome", "|".join(OUTCOMES))
    value = loose_field(body, name, pattern) if name else None
    out = {"taskId": tid, "role": role, "outcome": outcome, "roleField": name, "roleValue": value,
           "class": outcome or "none", "problem": None, "formatOk": None, "hash": sha256(body.strip())}
    if outcome == "completed" and name and not value:
        out["class"], out["problem"] = "incomplete", f"Outcome completed but no valid {name}"
    elif outcome in ("blocked", "failed") and not loose_field(body, "(?:Question or reason|Question|Reason)", r"\S+"):
        out["problem"] = f"Outcome {outcome} without Question or reason"
    if outcome:  # would verify read the same? verify is strict: "Outcome: completed" at line start
        strict = section(text, "Result")
        ok = field(strict, "Outcome") == outcome
        if name and value:
            ok = ok and bool(re.match(rf"^(?i:{pattern})\b", field(strict, name) or ""))
        out["formatOk"] = ok
    return out


# --- verify: acceptance evidence for one task (protocol: Acceptance)
def verify(tid):
    t = parse(tid)
    att = last_attempt(tid)
    bad, checks, flagged = [], [], []
    RUNTIME.mkdir(parents=True, exist_ok=True)
    vpath = RUNTIME / f"{tid}.verify.json"
    records = json.loads(vpath.read_text(encoding="utf-8")) if vpath.exists() else []
    n = len(records) + 1
    log = RUNTIME / f"{tid}.verify.{n}.log"

    if not att:
        bad.append("no attempt in runtime state (every attempt starts through tools/run-task.ps1)")
    elif att.get("status") != "exited":
        bad.append(f"last attempt {att.get('n')} is '{att.get('status')}', needs 'exited'")
    if att and att.get("baseline", {}).get("taskHash") != t["headerHash"]:
        bad.append("Task File changed above ## Result since the attempt started")
    outcome = result_field(t, "Outcome")
    if outcome != "completed":
        bad.append(f"Result Outcome is '{outcome}', needs 'completed'")
    sha = t.get("sha")

    if t["role"] == "developer":
        m = re.match(rf"^({SHA})", result_field(t, "Change") or "")
        sha = m.group(1).lower() if m else None
        wt = Path(t["worktree"] or "")
        if not sha:
            bad.append('Result needs "Change: <commit SHA>"')
        elif (head := git("rev-parse", "--verify", "--quiet", f"{t['branch']}^{{commit}}")) is None or not head.startswith(sha):
            bad.append(f"branch {t['branch']} is at '{head}', Result Change is {sha}")
        elif not wt.exists() or not (git("rev-parse", "HEAD", cwd=wt) or "").startswith(sha) or git("status", "--porcelain", cwd=wt):
            bad.append(f"worktree {wt} must exist, be clean and at {sha}")
        else:
            changed = [p.lower() for p in (git("diff", "--name-only", f"{main_branch()}...{sha}") or "").splitlines() if p]
            bad += [f"changed file outside Allowed files: {p}" for p in changed if not any(overlap(a, p) for a in t["allowed"])]
            flagged = [p for p in changed if any(p in c.replace("\\", "/").lower() for c in t["checks"])]
            checks = run_checks(t, wt, log)
            bad += [f"check failed (exit {c['exit']}): {c['cmd']}" for c in checks if c["exit"]]
            ind = t["independent"] or ""
            if ind.startswith("tester"):
                ok_testers = [k for k, row in ledger_rows().items() if row.get("Status") == "done" and row.get("Role") == "tester"
                              and _verifies(k) == (tid, sha[:7])]
                if not ok_testers:
                    bad.append(f"independent check pending: no done tester task with Verdict pass for {tid} @ {sha[:7]}")
            elif not ind.startswith("none"):
                bad.append('Task File needs "Independent check: tester | none - <reason>"')
    elif t["role"] == "tester":
        vb, v = verdict_problems(t["result"])
        bad += vb
    elif t["role"] == "deployer":
        if result_field(t, "Deployment") != "deployed":
            bad.append(f"Result Deployment is '{result_field(t, 'Deployment')}', needs 'deployed'")
        if not re.search(r"\bpass\b", result_field(t, "Smoke") or ""):
            bad.append("Result Smoke is not pass")
        if t["target"] == "prod":
            ap = result_field(t, "Approval") or ""
            if not re.search(rf"source=human\b.*target=prod\b.*sha={sha[:7]}.*at=\S+", ap):
                bad.append(f'prod needs "Approval: source=human target=prod sha={sha[:7]}... at=<time>" from the human in the Deployer session')

    rec = {"n": n, "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "attempt": att.get("n") if att else None,
           "role": t["role"], "sha": sha, "target": t["target"], "ok": not bad, "problems": bad, "checks": checks,
           "checksTouchedByTask": flagged, "log": str(log) if checks else None}
    records.append(rec)
    vpath.write_text(json.dumps(records, indent=2), encoding="utf-8")
    print(f"{tid} verify #{n}: {'PASS' if not bad else 'FAIL'} (sha {sha}, attempt {rec['attempt']})")
    for b in bad:
        print(f"  - {b}")
    for c in checks:
        print(f"  check exit {c['exit']}: {c['cmd']}")
    if flagged:
        print(f"  note: Checks use files changed by this task ({', '.join(flagged)}): read that diff before accepting")
    return not bad


def _verifies(tid):  # (checked id, sha7) of a tester task whose Result Verdict is pass, else None
    try:
        t = parse(tid)
    except TaskError:
        return None
    if t["role"] != "tester" or field(t["result"], "Verdict") != "pass":
        return None
    return t["checked"]["id"], t["sha"][:7]


def stage(n):
    rows = [r for r in ledger_rows().values() if r.get("Stage") == str(n) and r.get("Status") not in ("rejected", "cancelled")]
    bad = [f"{r['ID']} is '{r['Status']}', needs 'done'" for r in rows if r["Status"] != "done"]
    if not rows:
        bad.append(f"no tasks for Stage {n} in the ledger")
    log = RUNTIME / f"stage-{n}.log"
    RUNTIME.mkdir(parents=True, exist_ok=True)
    log.write_text("", encoding="utf-8")
    for r in rows:
        try:
            t = parse(r["ID"])
        except TaskError as e:
            bad.append(f"{r['ID']}: {e}")
            continue
        if t["role"] == "developer":
            bad += [f"{r['ID']} check failed on {main_branch()} (exit {c['exit']}): {c['cmd']}" for c in run_checks(t, ROOT, log) if c["exit"]]
    print(f"Stage {n}: {'PASS' if not bad else 'FAIL'} ({len(rows)} tasks, log {log})")
    for b in bad:
        print(f"  - {b}")
    return not bad


def write(out, obj):
    data = json.dumps(obj, indent=2)
    if out:
        Path(out).write_text(data, encoding="utf-8")
    else:
        print(data)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("task", "preflight", "endcheck", "verify", "result"):
        p = sub.add_parser(name)
        p.add_argument("id")
        p.add_argument("--out")
        if name == "preflight":
            p.add_argument("--manual", action="store_true")
            p.add_argument("--live", default="")
        if name in ("task", "preflight"):
            p.add_argument("--tool")
    sub.add_parser("stage").add_argument("n")
    sub.add_parser("spec")
    a = ap.parse_args()
    try:
        if a.cmd == "task":
            t = parse(a.id)
            t["baseline"] = baseline(t)
            t["launch"] = resolve_model(t, a.tool)[0]  # problems are refused by preflight before any launch
            write(a.out, t)
        elif a.cmd == "preflight":
            t, bad = preflight(a.id, a.manual, {x for x in a.live.split(",") if x}, a.tool)
            write(a.out, {"ok": not bad, "problems": bad, "task": t})
            return 0 if not bad else 1
        elif a.cmd == "endcheck":
            write(a.out, {"violations": endcheck(a.id)})
        elif a.cmd == "result":
            write(a.out, result_state(a.id))
        elif a.cmd == "verify":
            return 0 if verify(a.id) else 1
        elif a.cmd == "stage":
            return 0 if stage(a.n) else 1
        elif a.cmd == "spec":
            return 0 if spec_lint() else 1
    except TaskError as e:
        print(f"gate: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
