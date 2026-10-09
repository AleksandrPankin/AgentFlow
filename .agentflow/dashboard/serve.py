#!/usr/bin/env python3
"""Локальный сервер дашборда: раздаёт .agentflow/dashboard/out/ и пересобирает страницы по кнопке «Обновить».

  python .agentflow/dashboard/serve.py [порт]      по умолчанию 8765; открывает http://127.0.0.1:<порт>/index.html

Слушает только 127.0.0.1. Единственное действие кроме раздачи файлов: POST /rebuild запускает build.py
(без параметров из запроса). Запросы с чужим Host или Origin отклоняются. Остановка: Ctrl+C.
Без сервера дашборд тоже открывается как обычный файл, но кнопка «Обновить» неактивна.
"""
import json
import subprocess
import sys
import threading
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
LOCK = threading.Lock()


def build():
    r = subprocess.run([sys.executable, str(HERE / "build.py")], capture_output=True, text=True, encoding="utf-8", timeout=300)
    return r.returncode == 0, (r.stderr or r.stdout).strip()[-1500:]


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(OUT), **kw)

    def log_message(self, fmt, *args):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _local(self):
        ok = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
        origin = self.headers.get("Origin")
        return self.headers.get("Host") in ok and (origin is None or urlparse(origin).netloc in ok)

    def do_POST(self):
        if urlparse(self.path).path != "/rebuild":
            return self._json(404, {"ok": False, "error": "unknown address"})
        if not self._local():
            return self._json(403, {"ok": False, "error": "foreign host or origin"})
        if not LOCK.acquire(blocking=False):
            return self._json(409, {"ok": False, "error": "a rebuild is already running"})
        try:
            ok, msg = build()
        except Exception as e:  # noqa: BLE001
            ok, msg = False, str(e)
        finally:
            LOCK.release()
        self._json(200 if ok else 500, {"ok": ok, "error": "" if ok else msg})

    def do_GET(self):
        if not self._local():
            return self.send_error(403)
        super().do_GET()


if __name__ == "__main__":
    if not (OUT / "index.html").exists():
        print("страниц ещё нет, собираю...")
        ok, msg = build()
        if not ok:
            sys.exit(msg)
    url = f"http://127.0.0.1:{PORT}/index.html"
    print(f"дашборд: {url}   (Ctrl+C - остановить)")
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError as e:
        sys.exit(f"порт {PORT} занят: {e}")
    webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
