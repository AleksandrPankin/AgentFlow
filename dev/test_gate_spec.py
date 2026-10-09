"""Regression check of tools/gate.py, Product definition (2.4.0): `spec` lint and the preflight rules for `Spec:`.

  python dev/test_gate_spec.py [<AgentFlow root>]     default: the folder above dev/

Builds a throwaway git repository in the temp folder from tools/, tasks/_template.md and templates/product/,
runs every case, prints PASS / FAIL per case, exits 1 on any failure. Template development only: never copied into projects.
"""
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
box = Path(tempfile.mkdtemp(prefix="af24-"))
shutil.copytree(SRC / "tools", box / "tools", ignore=shutil.ignore_patterns("__pycache__"))
(box / "tasks").mkdir()
shutil.copy(SRC / "tasks" / "_template.md", box / "tasks" / "_template.md")
shutil.copy(SRC / "AGENTS.md", box / "AGENTS.md")
subprocess.run(["git", "init", "-q", "-b", "main", str(box)], check=True)
subprocess.run(["git", "-C", str(box), "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"], check=True)

TASK = """# T-001: test

Role: developer
Tool: claude
Stage: 1
{spec}
Depends on: none
Branch: t-001-test
Worktree: {worktree}
Independent check: none - sandbox

## Goal

Test.

## Read first

- README.md

## Allowed files

- `{allowed}`

## Do not touch

- `tools/`

## Acceptance criteria

- [ ] AC-001: it works

## Checks

- `python -c "print(1)"` - AC-001

## Result
"""

fails = 0


def task(spec, allowed="src/a.py", worktree="D:\\tmp\\box-t-001-test", result=""):
    (box / "tasks" / "T-001-test.md").write_text(TASK.format(spec=spec, allowed=allowed, worktree=worktree) + result, encoding="utf-8")


def git(*args, cwd=None):
    return subprocess.run(["git", "-C", str(cwd or box), "-c", "user.email=t@t", "-c", "user.name=t", *args],
                          capture_output=True, text=True, check=True).stdout.strip()


def ledger(*args):
    subprocess.run([sys.executable, str(box / "tools" / "ledger.py"), *args], capture_output=True, check=True)


def gate(*args):
    r = subprocess.run([sys.executable, str(box / "tools" / "gate.py"), *args], capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout + r.stderr


def preflight():
    code, out = gate("preflight", "T-001", "--tool", "claude")
    return code, json.loads(out)["problems"] if out.strip().startswith("{") else [out]


def case(name, ok_expected, problems_or_out, ok, needle=None):
    global fails
    text = " | ".join(problems_or_out) if isinstance(problems_or_out, list) else problems_or_out
    good = ok == ok_expected and (needle is None or needle in text)
    fails += not good
    print(f"{'PASS' if good else 'FAIL'}  {name}: ok={ok}  {text.strip()[:220]}")


def pf(name, ok_expected, spec, allowed="src/a.py", needle=None):
    task(spec, allowed)
    code, probs = preflight()
    case(name, ok_expected, probs, code == 0, needle)


def prd(text):
    (box / "docs" / "product" / "03_PRD.md").write_text(text, encoding="utf-8")


def front(name, status):  # front matter status of Vision or Brief
    f = box / "docs" / "product" / name
    f.write_text(re.sub(r"(?m)^status:.*$", f"status: {status}", f.read_text(encoding="utf-8"), count=1), encoding="utf-8")


def owner(lines):  # state/owner-tasks.md holding these task lines
    (box / "state").mkdir(exist_ok=True)
    (box / "state" / "owner-tasks.md").write_text("# Задачи на владельца\n\n" + lines, encoding="utf-8")


def lint(name, ok_expected, needle=None):
    code, out = gate("spec")
    case(name, ok_expected, out, code == 0, needle)


# 1. no product layer
pf("no docs/product, no Spec line", True, "")
pf("no docs/product, template Spec line", True, "Spec: <FR-###, AC-###, ADR-###> | none - <reason> | spike - <Q-ID>")
code, out = gate("spec")
case("spec without docs/product", True, out, code == 0, "not active")

# 2. product layer from the templates
shutil.copytree(SRC / "templates" / "product", box / "docs" / "product")
code, out = gate("spec")
case("spec on fresh templates", True, out, code == 0, "DRAFT 2")
pf("developer without Spec", False, "", needle="needs \"Spec:")
pf("template Spec placeholder", False, "Spec: <FR-###, AC-###, ADR-###> | none - <reason> | spike - <Q-ID>", needle="no item IDs")
pf("Spec none - reason", True, "Spec: none - tooling chore")
pf("Spec spike - Q-T-001", True, "Spec: spike - Q-T-001")
pf("Spec none without reason", False, "Spec: none - <reason>", needle="write \"none")
pf("Spec FR-001 DRAFT", False, "Spec: FR-001, AC-001", needle="FR-001 is DRAFT")
pf("Spec AC-001 follows DRAFT FR", False, "Spec: AC-001", needle="AC-001 is DRAFT")
pf("Spec unknown FR-099", False, "Spec: FR-099", needle="FR-099 not found")
pf("Allowed files in docs/product", False, "Spec: none - x", allowed="docs/product/03_PRD.md", needle="is in docs/product/")
pf("Allowed files docs/** glob", False, "Spec: none - x", allowed="docs/**", needle="is in docs/product/")

# 3. statuses; Vision and Brief are a ceiling for every item (weakest link)
base = (SRC / "templates" / "product" / "03_PRD.md").read_text(encoding="utf-8")
prd(base.replace("- **Статус:** DRAFT\n- **Source:** B04 / UC-001", "- **Статус:** PROPOSED\n- **Source:** B04 / UC-001"))
pf("Spec FR-001 PROPOSED, Vision DRAFT", False, "Spec: FR-001", needle="01_VISION.md")
lint("spec: PROPOSED FR under a DRAFT Vision", False, "never ahead of Vision and Brief")
front("01_VISION.md", "PROPOSED")
pf("Spec AC-001, Brief DRAFT", False, "Spec: AC-001", needle="02_BRIEF.md")
front("02_BRIEF.md", "PROPOSED")
pf("Spec FR-001 PROPOSED + AC-001", True, "Spec: FR-001, AC-001")
pf("Spec with B04, AR05, UC-001", True, "Spec: FR-001, B04, AR05, UC-001")
pf("Spec with unknown B99", False, "Spec: FR-001, B99", needle="B99 not found")
prd(base.replace("- **Статус:** DRAFT\n- **Source:** B04 / UC-001", "- **Статус:** APPROVED\n- **Source:** B04 / UC-001"))
pf("Spec FR-001 APPROVED", True, "Spec: FR-001, AC-001")
lint("spec: APPROVED without an owner task", False, "needs the owner task")
prd(base.replace("- **Статус:** DRAFT\n- **Source:** B04 / UC-001", "- **Статус:** APPROVED (OWN-001)\n- **Source:** B04 / UC-001"))
owner("- [ ] **OWN-001 · Проверить срез.**\n")
lint("spec: APPROVED by an open owner task", False, "OWN-001, which is not done")
owner("- [x] **OWN-001 · Проверить срез.** 2026-10-09: ок\n")
lint("spec: APPROVED by a done owner task", True)
front("02_BRIEF.md", "APPROVED")
lint("spec: Brief APPROVED without an owner task", False, "02_BRIEF.md (docs/product/02_BRIEF.md")
front("02_BRIEF.md", "APPROVED (OWN-001)")
lint("spec: Brief APPROVED by a done owner task", True)
front("02_BRIEF.md", "PROPOSED")
prd(base.replace("- **Статус:** DRAFT\n- **Source:** B04 / UC-001", "- **Статус:** STALE\n- **Source:** B04 / UC-001"))
pf("Spec FR-001 STALE", False, "Spec: FR-001", needle="FR-001 is STALE")
pf("Spec AC-001 of STALE FR", False, "Spec: AC-001", needle="AC-001 is STALE")

# 4. ADR file
(box / "docs" / "product" / "decisions").mkdir()
(box / "docs" / "product" / "decisions" / "ADR-001.md").write_text("# ADR-001 — X\n\n- **Статус:** PROPOSED\n- **Source:** FR-001\n", encoding="utf-8")
pf("Spec ADR-001 PROPOSED", True, "Spec: ADR-001")
(box / "docs" / "product" / "decisions" / "ADR-001.md").write_text("# ADR-001 — X\n\n- **Статус:** DRAFT\n", encoding="utf-8")
pf("Spec ADR-001 DRAFT", False, "Spec: ADR-001", needle="ADR-001 is DRAFT")

# 5. spec lint failures
prd(base + "\n### FR-001 — again\n\n- **Статус:** DRAFT\n")
code, out = gate("spec")
case("spec: duplicate FR-001", False, out, code == 0, "defined twice")
prd(base + "\n### FR-002 — no status\n\n- **Source:** B04\n")
code, out = gate("spec")
case("spec: FR without status", False, out, code == 0, "FR-002")
prd(base + "\n### FR-003 — must, no AC\n\n- **Статус:** PROPOSED\n- **Source:** B04\n- **Приоритет:** Must\n")
code, out = gate("spec")
case("spec: Must FR without AC", False, out, code == 0, "FR-003")
prd(base + "\n### FR-004 — should\n\n- **Статус:** PROPOSED\n- **Source:** B04\n- **Приоритет:** Should\n")
code, out = gate("spec")
case("spec: Should FR without AC is fine", True, out, code == 0)
prd(base + "\n### AC-002 — orphan\n\n- **Source:** FR-404\n")
code, out = gate("spec")
case("spec: AC without existing FR", False, out, code == 0, "AC-002")
prd(base.replace("- **Статус:** DRAFT\n- **Source:** B04 / UC-001", "- **Статус:** Approved-ish\n- **Source:** B04 / UC-001"))
code, out = gate("spec")
case("spec: invalid status word", False, out, code == 0, "FR-001")
for name, value, needle in (("Must with a comment", "Must — ядро MVP", "Must without an AC"), ("must in lower case", "must", "Must without an AC"),
                            ("unknown word", "Обязательно", "priority 'обязательно'")):
    prd(base + f"\n### FR-005 — x\n\n- **Статус:** PROPOSED\n- **Source:** B04\n- **Приоритет:** {value}\n")
    lint(f"spec: priority {name}", False, needle)
prd(base + "\n### FR-006 — no priority\n\n- **Статус:** PROPOSED\n- **Source:** B04\n")
lint("spec: FR without a priority", False, "FR-006 (")

# 6. acceptance re-checks the spec; the main folder stays on the main branch
proposed = base.replace("- **Статус:** DRAFT\n- **Source:** B04 / UC-001", "- **Статус:** PROPOSED\n- **Source:** B04 / UC-001")
prd(proposed)
git("checkout", "-q", "-b", "side")
pf("preflight, main folder on a side branch", False, "Spec: FR-001", needle="main folder is on 'side'")
git("checkout", "-q", "main")
wt = box.parent / f"{box.name}-t-001-test"
git("worktree", "add", "-q", str(wt), "-b", "t-001-test")
(wt / "src").mkdir()
(wt / "src" / "a.py").write_text("x = 1\n", encoding="utf-8")
git("add", "src/a.py", cwd=wt)
git("commit", "-q", "-m", "[T-001] feat: a", cwd=wt)
sha = git("rev-parse", "HEAD", cwd=wt)
task("Spec: FR-001, AC-001", worktree=str(wt), result=f"Outcome: completed\nChange: {sha} on t-001-test\n")
(box / "tasks" / ".runtime").mkdir(parents=True, exist_ok=True)
gate("task", "T-001", "--out", str(box / "t.json"))
baseline = json.loads((box / "t.json").read_text(encoding="utf-8"))["baseline"]
(box / "tasks" / ".runtime" / "T-001.json").write_text(json.dumps({"taskId": "T-001", "attempts": [{"n": 1, "status": "exited", "baseline": baseline}]}), encoding="utf-8")
code, out = gate("verify", "T-001")
case("verify, FR-001 PROPOSED", True, out, code == 0)
prd(proposed.replace("PROPOSED", "STALE", 1))
code, out = gate("verify", "T-001")
case("verify, FR-001 went STALE during the attempt", False, out, code == 0, "FR-001 is STALE")
prd(proposed)
gate("verify", "T-001")
for args in (("add", "T-001", "--stage", "1", "--role", "developer"), ("set", "T-001", "--status", "in progress"),
             ("set", "T-001", "--status", "review"), ("set", "T-001", "--status", "done", "--commit", sha)):
    ledger(*args)
code, out = gate("stage", "1")
case("stage 1", True, out, code == 0)
prd(proposed.replace("PROPOSED", "STALE", 1))
code, out = gate("stage", "1")
case("stage 1, a done task's FR-001 STALE", False, out, code == 0, "T-001: Spec FR-001 is STALE")
prd(proposed)
git("checkout", "-q", "side")
code, out = gate("stage", "1")
case("stage 1, main folder on a side branch", False, out, code == 0, "main folder is on 'side'")
git("checkout", "-q", "main")
git("worktree", "remove", "--force", str(wt))

for p in (wt, box):  # git objects are read-only on Windows: make them writable, then delete (onexc: Python 3.12+)
    if p.exists():
        shutil.rmtree(p, onexc=lambda f, path, _: (os.chmod(path, stat.S_IWRITE), f(path)))
print(f"\n{'ALL PASS' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
