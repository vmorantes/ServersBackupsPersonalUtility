#!/usr/bin/env python3
# =============================================================================
# web/server.py — servidor de la interfaz web de backupctl
# =============================================================================
# Solo biblioteca estándar: nada que instalar.
#
# No implementa ninguna lógica de respaldo. Cada acción llama al propio
# backupctl y retransmite su salida en vivo, de modo que lo que ves aquí es
# exactamente lo que verías en el terminal.
#
# La lista de acciones permitidas es fija y los argumentos se construyen aquí:
# nada de lo que llegue del navegador acaba en una shell.
# =============================================================================

import argparse
import html
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

BC_ROOT = Path(os.environ.get("BC_ROOT", Path(__file__).resolve().parent.parent))
BACKUPCTL = BC_ROOT / "bin" / "backupctl"
WEB_DIR = BC_ROOT / "web"
VERSION = os.environ.get("BC_VERSION", "?")

# Credencial de sesión: se regenera en cada arranque. Sin ella la API no
# responde, así que una página maliciosa abierta en el navegador no puede
# disparar órdenes contra este puerto.
TOKEN = secrets.token_urlsafe(24)

# Nombres de perfil aceptables. Se valida aquí y no en el navegador.
SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]{1,64}$")

# -----------------------------------------------------------------------------
# Lista blanca de acciones
# -----------------------------------------------------------------------------
# clave -> (argv extra, ¿escribe?, descripción)
# Los argumentos variables se validan uno a uno más abajo; nunca se concatenan
# cadenas del navegador en una orden.
ACTIONS = {
    "status":        (["status"],                       False),
    "doctor":        (["doctor"],                       False),
    "list":          (["list"],                         False),
    "inspect":       (["inspect"],                      False),
    "logs":          (["logs", "--list"],               False),
    "logs-errors":   (["logs", "--errors"],             False),
    "logs-full":     (["logs", "--full"],               False),
    "config":        (["config", "--show"],             False),
    "config-check":  (["config", "--check"],            False),
    "cron-show":     (["cron", "--show"],               False),
    "restic-list":   (["restic-list"],                  False),
    "verify":        (["verify"],                       False),
    "verify-quick":  (["verify", "--quick"],            False),

    "backup-dry":    (["backup", "--dry-run"],          False),
    "retention-dry": (["retention", "--dry-run"],       False),
    "deploy-dry":    (["deploy", "--dry-run"],          False),
    "pull-dry":      (["pull", "--dry-run"],            False),

    "backup":        (["backup"],                       True),
    "retention":     (["retention"],                    True),
    "deploy":        (["deploy"],                       True),
    "pull":          (["pull"],                         True),
    "notify-test":   (["notify-test"],                  True),

    "remote-status": (["remote", "status"],             False),
    "remote-doctor": (["remote", "doctor"],             False),
    "remote-list":   (["remote", "list"],               False),
    "remote-logs":   (["remote", "logs", "--errors"],   False),
    "remote-backup": (["remote", "backup"],             True),
    "remote-verify": (["remote", "verify"],             False),
}

# Acciones que aceptan un argumento extra, con su validador
def _valid_db(v):   return bool(re.match(r"^[A-Za-z0-9._\-]{1,64}$", v))
def _valid_zip(v):  return bool(re.match(r"^all_databases_[0-9_]+\.zip$", v))

PARAMS = {
    "inspect":       ("zip", _valid_zip),
    "verify":        ("zip", _valid_zip),
    "verify-quick":  ("zip", _valid_zip),
}

# Acciones con una prueba de restauración: llevan la base de datos como
# argumento y se tratan aparte por ser las más delicadas.
RESTORE_TEST = "verify-restore-test"


def profiles():
    """Lista de perfiles conocidos, leída del propio backupctl."""
    try:
        out = subprocess.run(
            [str(BACKUPCTL), "--no-color", "profiles"],
            capture_output=True, text=True, timeout=20,
        ).stdout
    except Exception:
        return []
    found = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].endswith("env.sh") and SAFE_NAME.match(parts[0]):
            found.append({"name": parts[0], "config": parts[1]})
    return found


def quick_status(name):
    """Resumen de un perfil para el panel. Nunca escribe nada."""
    try:
        r = subprocess.run(
            [str(BACKUPCTL), "--no-color", "-p", name, "status"],
            capture_output=True, text=True, timeout=60,
        )
    except subprocess.TimeoutExpired:
        return {"name": name, "ok": False, "estado": "sin respuesta", "lineas": []}
    except Exception as e:
        return {"name": name, "ok": False, "estado": str(e), "lineas": []}

    lineas = []
    for ln in (r.stdout + r.stderr).splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("=="):
            continue
        # Se conserva el nivel para poder colorear en el navegador
        nivel = "info"
        if "[ERROR]" in ln:  nivel = "error"
        elif "[AVISO]" in ln: nivel = "warn"
        elif "[  OK ]" in ln: nivel = "ok"
        texto = re.sub(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[[^\]]+\]\s*", "", ln)
        lineas.append({"nivel": nivel, "texto": texto})
    return {"name": name, "ok": r.returncode == 0, "lineas": lineas}


def build_argv(profile, action, arg):
    """Construye el argv real. Devuelve None si algo no está permitido."""
    if not SAFE_NAME.match(profile or ""):
        return None

    if action == RESTORE_TEST:
        if not arg or not _valid_db(arg):
            return None
        return [str(BACKUPCTL), "--no-color", "-y", "-p", profile,
                "verify", "--restore-test", arg, "--with-data"]

    spec = ACTIONS.get(action)
    if spec is None:
        return None
    extra, _writes = spec
    argv = [str(BACKUPCTL), "--no-color", "-y", "-p", profile] + list(extra)

    if action in PARAMS and arg:
        _kind, validator = PARAMS[action]
        if not validator(arg):
            return None
        argv.append(arg)
    return argv


class Handler(BaseHTTPRequestHandler):
    server_version = "backupctl-web"

    # El registro por defecto ensucia el terminal; se resume
    def log_message(self, fmt, *args):
        if os.environ.get("BC_DEBUG") == "1":
            sys.stderr.write("  web: " + fmt % args + "\n")

    # --- utilidades --------------------------------------------------------
    def _auth_ok(self):
        # El Host debe ser local: corta los ataques por reasignación de DNS
        host = (self.headers.get("Host") or "").split(":")[0]
        if host not in ("127.0.0.1", "localhost", "[::1]", "::1"):
            return False
        tok = self.headers.get("X-Backupctl-Token")
        if not tok:
            tok = parse_qs(urlparse(self.path).query).get("t", [""])[0]
        return secrets.compare_digest(tok or "", TOKEN)

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Content-Type-Options", "nosniff")
        # Sin recursos externos: la página es autocontenida
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; style-src 'self' 'unsafe-inline'")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _static(self, name):
        path = WEB_DIR / name
        if not path.is_file():
            return self._send(404, "no encontrado", "text/plain; charset=utf-8")
        types = {".html": "text/html; charset=utf-8",
                 ".css": "text/css; charset=utf-8",
                 ".js": "application/javascript; charset=utf-8"}
        self._send(200, path.read_bytes(), types.get(path.suffix, "text/plain"))

    # --- GET ---------------------------------------------------------------
    def do_GET(self):
        u = urlparse(self.path)

        if u.path in ("/", "/index.html"):
            return self._static("index.html")
        if u.path in ("/app.css", "/app.js"):
            return self._static(u.path.lstrip("/"))

        if not self._auth_ok():
            return self._json({"error": "no autorizado"}, 403)

        if u.path == "/api/profiles":
            return self._json({"perfiles": profiles(), "version": VERSION})

        if u.path == "/api/overview":
            names = [p["name"] for p in profiles()]
            if not names:
                return self._json({"perfiles": []})
            # En paralelo: con varios VPS, en serie se haría eterno
            with ThreadPoolExecutor(max_workers=min(8, len(names))) as ex:
                res = list(ex.map(quick_status, names))
            return self._json({"perfiles": res})

        if u.path == "/api/backups":
            name = parse_qs(u.query).get("profile", [""])[0]
            if not SAFE_NAME.match(name or ""):
                return self._json({"error": "perfil no válido"}, 400)
            r = subprocess.run(
                [str(BACKUPCTL), "--no-color", "-p", name, "list"],
                capture_output=True, text=True, timeout=60)
            filas = []
            for ln in r.stdout.splitlines():
                if ln.startswith("all_databases_"):
                    c = ln.split()
                    if len(c) >= 5:
                        filas.append({"archivo": c[0], "tamano": c[1],
                                      "fecha": c[2] + " " + c[3],
                                      "edad": c[4],
                                      "bd": c[5] if len(c) > 5 else "?"})
            return self._json({"respaldos": filas})

        return self._send(404, "no encontrado", "text/plain; charset=utf-8")

    # --- POST: ejecutar una acción, retransmitiendo la salida ---------------
    def do_POST(self):
        if urlparse(self.path).path != "/api/run":
            return self._send(404, "no encontrado", "text/plain; charset=utf-8")
        if not self._auth_ok():
            return self._json({"error": "no autorizado"}, 403)

        try:
            n = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._json({"error": "petición ilegible"}, 400)

        argv = build_argv(payload.get("profile"),
                          payload.get("action"),
                          payload.get("arg"))
        if argv is None:
            return self._json({"error": "acción no permitida"}, 400)

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

        env = dict(os.environ, BC_NO_COLOR="1")
        try:
            p = subprocess.Popen(argv, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL,
                                 text=True, bufsize=1, env=env)
        except Exception as e:
            self.wfile.write(f"[ERROR] no se pudo ejecutar: {e}\n".encode())
            return

        try:
            for line in p.stdout:
                self.wfile.write(line.encode("utf-8", "replace"))
                self.wfile.flush()
            p.wait()
            self.wfile.write(f"\n__FIN__{p.returncode}\n".encode())
        except (BrokenPipeError, ConnectionResetError):
            # El navegador cerró la pestaña: se corta la orden en curso
            p.terminate()


def main():
    ap = argparse.ArgumentParser(description="Interfaz web de backupctl")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--open", action="store_true")
    a = ap.parse_args()

    if not BACKUPCTL.is_file():
        sys.exit(f"ERROR: no se encontró {BACKUPCTL}")

    srv = ThreadingHTTPServer((a.host, a.port), Handler)
    url = f"http://{a.host}:{a.port}/?t={TOKEN}"

    print()
    print("  backupctl web " + VERSION)
    print("  " + "─" * 62)
    print(f"  Abre esta dirección en el navegador:")
    print()
    print(f"    {url}")
    print()
    print("  La credencial de la URL se regenera en cada arranque.")
    print("  Escuchando solo en " + a.host + ". Ctrl-C para parar.")
    print()

    if a.open:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()

    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n  Parado.")
        srv.shutdown()


if __name__ == "__main__":
    main()
