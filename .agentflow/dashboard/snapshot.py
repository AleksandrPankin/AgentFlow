#!/usr/bin/env python3
"""Версии самого дашборда: сохранить, посмотреть список, откатиться.

  python .agentflow/dashboard/snapshot.py save [название]    сохранить текущие исходники и страницы как новую версию
  python .agentflow/dashboard/snapshot.py list               список версий
  python .agentflow/dashboard/snapshot.py restore vN         вернуть исходники версии vN (текущее состояние перед этим
                                                  само сохраняется как «before-restore»), затем пересобрать

Версия = копия build.py, шаблонов, common.*, filterbar.* + готовые out/index.html и out/graph.html.
Открыть старую версию, не откатываясь: .agentflow/dashboard/versions/vN-.../index.html и graph.html.
Версии лежат в .agentflow/dashboard/versions/ и в .gitignore; сами исходники коммитятся вместе с шаблоном.
Перед каждой заметной правкой дашборда сохраняй версию.
"""
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
VERS = HERE / "versions"
OUT = HERE / "out"
SOURCES = ["build.py", "template.html", "graph_template.html", "filterbar.css", "filterbar.js", "common.css", "common.js"]
PAGES = ["index.html", "graph.html"]


def numbers():
    out = []
    for d in VERS.glob("v*"):
        m = re.match(r"v(\d+)", d.name)
        if m:
            out.append(int(m.group(1)))
    return sorted(out)


def save(name=""):
    VERS.mkdir(exist_ok=True)
    n = (numbers() or [0])[-1] + 1
    slug = re.sub(r"[^\w-]+", "-", name.strip(), flags=re.U).strip("-")
    d = VERS / (f"v{n}-{datetime.now():%Y%m%d-%H%M}" + (f"-{slug}" if slug else ""))
    d.mkdir()
    for f in SOURCES:
        if (HERE / f).exists():
            shutil.copy2(HERE / f, d / f)
    for f in PAGES:
        if (OUT / f).exists():
            shutil.copy2(OUT / f, d / f)
    (d / "NOTE.txt").write_text(name or "(без названия)", encoding="utf-8")
    print("сохранено:", d.name)
    return d


def lst():
    if not VERS.exists():
        print("версий пока нет")
        return
    for d in sorted(VERS.glob("v*"), key=lambda p: int(re.match(r"v(\d+)", p.name).group(1))):
        note = (d / "NOTE.txt").read_text(encoding="utf-8") if (d / "NOTE.txt").exists() else ""
        print(f"{d.name:45} {note}")


def restore(v):
    m = next((d for d in VERS.glob(f"{v}-*") if d.is_dir()), None) or next((d for d in VERS.glob(f"{v}") if d.is_dir()), None)
    if not m:
        sys.exit(f"версия {v} не найдена; см. list")
    save("before-restore")
    for f in SOURCES:
        shutil.copy2(m / f, HERE / f)
    subprocess.run([sys.executable, str(HERE / "build.py")], check=True)
    print("восстановлено из", m.name)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "save":
        save(" ".join(sys.argv[2:]))
    elif cmd == "list":
        lst()
    elif cmd == "restore" and len(sys.argv) > 2:
        restore(sys.argv[2])
    else:
        print(__doc__)
