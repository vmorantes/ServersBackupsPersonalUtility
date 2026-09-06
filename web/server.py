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
import tempfile
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
# El navegador manda el NOMBRE de una acción y un diccionario de opciones. Aquí
# se construye el argv real: nada de lo que llega del navegador se concatena en
# una cadena ni pasa por una shell.
#
# Cada opción declara cómo se traduce y con qué validador. Una opción que no
# valide hace que la petición entera se rechace, no que se ignore en silencio.
# -----------------------------------------------------------------------------

def _v_db(v):       return bool(re.match(r"^[A-Za-z0-9._\-]{1,64}$", v))
def _v_dblist(v):   return all(_v_db(x) for x in v.split(",") if x.strip())
def _v_zip(v):      return bool(re.match(r"^all_databases_[0-9_]+\.zip$", v))
def _v_target(v):   return bool(re.match(r"^[A-Za-z0-9._\-]+@[A-Za-z0-9._\-]+$", v))
def _v_path(v):     return bool(re.match(r"^/[A-Za-z0-9._\-/]{0,200}$", v))
def _v_prefix(v):   return bool(re.match(r"^[A-Za-z0-9._\-]{0,32}$", v))
def _v_segments(v):
    ok = {"database", "tables", "data", "views", "functions", "others"}
    return all(x in ok for x in v.split(",") if x.strip())

# nombre -> (argv base, [(clave, forma, validador)], ¿escribe?)
#   forma "pos"        -> se añade como argumento posicional
#   forma "--x"        -> se añade como "--x VALOR"
#   forma "flag:--x"   -> se añade "--x" si el valor es verdadero
A = {
    # --- blindaje ----------------------------------------------------------
    "shield":        (["shield"], [], False),
    "hestia-status": (["hestia", "status"], [], False),
    "hestia-verify": (["hestia", "verify"], [], False),
    "hestia-keys":   (["hestia", "keys"], [], True),
    "hestia-donde":  (["hestia", "donde"], [], False),
    "hestia-users":  (["hestia", "users"], [], False),
    "hestia-dbs":    (["hestia", "dbs"], [], False),
    "remote-hestia-dbs": (["remote", "hestia", "dbs"], [], False),
    "hestia-rclone-repo": (["hestia", "rclone", "--desde-repo"], [], True),
    "remote-hestia-donde": (["remote", "hestia", "donde"], [], False),
    "hestia-cron":   (["hestia", "cron"], [("hour", "--hour", lambda v: v.isdigit()),
                                           ("minute", "--minute", lambda v: v.isdigit())], True),
    "hestia-restic": (["hestia", "restic"], [("repo", "--repo", lambda v: bool(re.match(r"^rclone:[A-Za-z0-9._-]+:[A-Za-z0-9._\-/]*$", v)))], True),
    "remote-shield": (["remote", "shield"], [], False),
    "remote-hestia-status": (["remote", "hestia", "status"], [], False),
    "remote-hestia-verify": (["remote", "hestia", "verify"], [], False),
    "remote-hestia-keys":   (["remote", "hestia", "keys"], [], True),
    "remote-hestia-cron":   (["remote", "hestia", "cron"], [], True),

    # --- solo lectura ------------------------------------------------------
    "status":        (["status"], [], False),
    "doctor":        (["doctor"], [], False),
    "list":          (["list"], [], False),
    "list-databases":(["list", "--databases"], [("zip", "pos", _v_zip)], False),
    "inspect":       (["inspect"], [("zip", "pos", _v_zip)], False),
    "logs":          (["logs", "--list"], [], False),
    "logs-errors":   (["logs", "--errors"], [], False),
    "logs-full":     (["logs", "--full"], [], False),
    "config":        (["config", "--show"], [], False),
    "config-check":  (["config", "--check"], [], False),
    "cron-show":     (["cron", "--show"], [], False),
    "restic-list":   (["restic-list"], [], False),
    "verify":        (["verify"], [("zip", "pos", _v_zip)], False),
    "verify-quick":  (["verify", "--quick"], [("zip", "pos", _v_zip)], False),

    # --- ensayos -----------------------------------------------------------
    "backup-dry":    (["backup", "--dry-run"],
                      [("only", "--only", _v_dblist), ("exclude", "--exclude", _v_dblist)], False),
    "restore-dry":   (["restore"],
                      [("zip", "pos", _v_zip), ("db", "pos", _v_db),
                       ("into", "--into", _v_db), ("segments", "--segments", _v_segments),
                       ("_dry", "flag:--dry-run", None)], False),
    "retention-dry": (["retention", "--dry-run"], [], False),
    "restic-dry":    (["restic", "--dry-run"], [], False),
    "deploy-dry":    (["deploy", "--dry-run"], [("target", "pos", _v_target),
                                                ("path", "--path", _v_path)], False),
    "pull-dry":      (["pull", "--dry-run"], [("target", "pos", _v_target),
                                              ("path", "--path", _v_path)], False),
    "migrate-dry":   (["migrate", "--dry-run"],
                      [("to", "--to", _v_target), ("databases", "--databases", _v_dblist),
                       ("prefix", "--prefix", _v_prefix), ("_fresh", "flag:--fresh", None)], False),

    # --- escriben ----------------------------------------------------------
    "backup":        (["backup"],
                      [("only", "--only", _v_dblist), ("exclude", "--exclude", _v_dblist),
                       ("_nodata", "flag:--no-data", None)], True),
    "verify-restore-test": (["verify"],
                      [("zip", "pos", _v_zip), ("db", "--restore-test", _v_db),
                       ("_withdata", "flag:--with-data", None)], True),
    "restore":       (["restore"],
                      [("zip", "pos", _v_zip), ("db", "pos", _v_db),
                       ("into", "--into", _v_db), ("segments", "--segments", _v_segments)], True),
    "retention":     (["retention"], [], True),
    "restic":        (["restic"], [], True),
    "notify-test":   (["notify-test"], [], True),
    "deploy":        (["deploy"], [("target", "pos", _v_target),
                                   ("path", "--path", _v_path)], True),
    "pull":          (["pull"], [("target", "pos", _v_target),
                                 ("path", "--path", _v_path)], True),
    "migrate":       (["migrate"],
                      [("to", "--to", _v_target), ("databases", "--databases", _v_dblist),
                       ("prefix", "--prefix", _v_prefix), ("_fresh", "flag:--fresh", None)], True),
    "cron-install":  (["cron", "--install"], [("hour", "--hour", lambda v: v.isdigit()),
                                              ("minute", "--minute", lambda v: v.isdigit())], True),
    "cron-remove":   (["cron", "--remove"], [], True),

    # --- en el servidor ----------------------------------------------------
    "remote-status": (["remote", "status"], [], False),
    "remote-doctor": (["remote", "doctor"], [], False),
    "remote-list":   (["remote", "list"], [], False),
    "remote-logs":   (["remote", "logs", "--errors"], [], False),
    "remote-config": (["remote", "config", "--show"], [], False),
    "remote-cron":   (["remote", "cron", "--show"], [], False),
    "remote-verify": (["remote", "verify"], [], False),
    "remote-backup": (["remote", "backup"], [], True),
    "remote-retention": (["remote", "retention"], [], True),
    "remote-restic": (["remote", "restic"], [], True),
    "remote-cron-install": (["remote", "cron", "--install"], [], True),
    "remote-cron-remove":  (["remote", "cron", "--remove"], [], True),
    "remote-notify": (["remote", "notify-test"], [], True),
}

# Acciones que en la máquina destino necesitan root. Desde la web no hay
# terminal donde teclear la contraseña de sudo, así que se avisa antes.
NECESITA_ROOT = {"restic", "cron-install", "cron-remove",
                 "remote-restic", "remote-cron-install", "remote-cron-remove"}


def build_argv(profile, action, opts):
    """Construye el argv real. Devuelve (argv, error)."""
    if not SAFE_NAME.match(profile or ""):
        return None, "perfil no válido"
    spec = A.get(action)
    if spec is None:
        return None, "acción no permitida"

    base, campos, _escribe = spec
    argv = [str(BACKUPCTL), "--no-color", "-y", "-p", profile] + list(base)
    opts = opts if isinstance(opts, dict) else {}
    posicionales = []

    for clave, forma, validador in campos:
        v = opts.get(clave)
        if forma.startswith("flag:"):
            if v:
                argv.append(forma.split(":", 1)[1])
            continue
        if v is None or v == "":
            # Un posicional vacío sigue haciendo falta para no desplazar los
            # siguientes: backupctl acepta '' como "el más reciente".
            if forma == "pos":
                posicionales.append("")
            continue
        v = str(v).strip()
        if validador and not validador(v):
            return None, f"valor no válido para '{clave}'"
        if forma == "pos":
            posicionales.append(v)
        else:
            argv += [forma, v]

    # Los posicionales van detrás de las opciones, y se recortan los vacíos
    # finales para no pasar argumentos de más.
    while posicionales and posicionales[-1] == "":
        posicionales.pop()
    argv += posicionales
    return argv, None


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


def profile_meta(name):
    """Valores efectivos del perfil: sirven para saber si es local o remoto."""
    try:
        r = subprocess.run(
            [str(BACKUPCTL), "--no-color", "-p", name, "config", "--show"],
            capture_output=True, text=True, timeout=20)
    except Exception:
        return {}
    meta = {}
    for ln in r.stdout.splitlines():
        parts = ln.split(None, 1)
        if len(parts) == 2 and parts[0].isupper():
            meta[parts[0]] = parts[1].strip()
    return meta


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

    # Un perfil que describe un servidor remoto se mide en el servidor, no aquí.
    # Sin esta distinción el panel pinta de rojo rutas que en tu equipo no
    # existen y nunca deberían existir, y ese ruido tapa los problemas reales.
    meta = profile_meta(name)
    destino = meta.get("DEPLOY_HOST", "")
    if destino.startswith("("):        # "(sin configurar)"
        destino = ""
    salida = meta.get("BACKUP_OUTPUT_DIR", "")
    # No se exige DEPLOY_HOST: un perfil cuyo directorio de respaldos no existe
    # en esta máquina describe otra, tenga o no destino configurado. Es la señal
    # honesta, y además así se detectan los perfiles a los que todavía les falta
    # el DEPLOY_HOST.
    es_remoto = bool(salida) and not os.path.isdir(salida)

    return {
        "name": name,
        "ok": r.returncode == 0,
        "lineas": lineas,
        "destino": destino,
        "remoto": es_remoto,
    }


def probe(name):
    """¿En qué punto está este servidor? Responde en un par de segundos y sin
    escribir nada, para poder decirle al usuario cuál es el siguiente paso en
    lugar de dejarle adivinando entre una pared de botones."""
    meta = profile_meta(name)
    host = meta.get("DEPLOY_HOST", "")
    if host.startswith("("):
        host = ""
    # DEPLOY_USER cae a USER_NAME si no está declarado, igual que en el propio
    # backupctl: sin esto el destino saldría como "@servidor" y ssh fallaría con
    # su mensaje de uso, que no dice nada útil.
    user = meta.get("DEPLOY_USER", "") or meta.get("USER_NAME", "")
    path = meta.get("DEPLOY_PATH", "/home/admin/scripts")
    salida = meta.get("BACKUP_OUTPUT_DIR", "")
    local = bool(salida) and os.path.isdir(salida)

    r = {"destino": (f"{user}@{host}" if host else ""), "ruta": path,
         "local": local, "ssh": "sin-destino", "backupctl": "?",
         "siguiente": "", "detalle": "", "plan": []}

    if not host:
        r["siguiente"] = ("Falta el servidor en la configuración. Ponlo en la "
                          "pestaña Configuración: DEPLOY_HOST.")
        return r
    if not user:
        r["ssh"] = "sin-destino"
        r["siguiente"] = "Falta DEPLOY_USER en la configuración."
        return r

    destino = r["destino"]
    try:
        c = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
             "-o", "StrictHostKeyChecking=accept-new", destino,
             f"test -x '{path}/bin/backupctl' && echo SI || echo NO"],
            capture_output=True, text=True, timeout=20)
    except Exception as e:
        r["ssh"] = "error"; r["detalle"] = str(e)
        r["siguiente"] = "No se pudo intentar la conexión."
        return r

    if c.returncode != 0:
        err = (c.stderr or "").strip()
        r["detalle"] = err.splitlines()[-1] if err else "sin detalle"
        if "Permission denied" in err or "publickey" in err:
            r["ssh"] = "sin-clave"
            # En HestiaCP los usuarios del panel tienen shell 'nologin': por SSH
            # no se puede entrar como ellos por mucha clave que se instale. Si
            # el usuario configurado no es root, ese suele ser el problema real.
            if user not in ("root",):
                r["ssh"] = "usuario-malo"
                r["siguiente"] = (
                    f"El perfil intenta entrar como «{user}», que es un usuario del "
                    f"panel de HestiaCP y no tiene consola. Pulsa «Configurar acceso "
                    f"por clave» aquí abajo: entra como root, y el perfil se corrige "
                    f"solo.")
                return r
            # Nada de mandar al terminal: el botón que lo resuelve está justo
            # debajo de este mensaje.
            r["siguiente"] = ("Pulsa «Configurar acceso por clave» aquí abajo. "
                              "Te pedirá la contraseña del servidor UNA vez y "
                              "dejará el acceso resuelto para siempre.")
        else:
            r["ssh"] = "error"
            r["siguiente"] = ("No se llega al servidor. Revisa el nombre en la "
                              "pestaña Configuración y que el servidor esté encendido.")
        return r

    r["ssh"] = "ok"
    r["backupctl"] = "si" if c.stdout.strip() == "SI" else "no"

    # Plan ordenado: qué falta y en qué orden. Es la diferencia entre "aquí
    # tienes cincuenta botones" y "haz esto ahora".
    r["plan"] = plan_pasos(name, destino, path, r["backupctl"] == "si")
    pend = [x for x in r["plan"] if not x["hecho"]]
    r["siguiente"] = pend[0]["hacer"] if pend else "Todo listo: este servidor está blindado."
    return r


def plan_pasos(name, destino, path, hay_ctl):
    """Estado de cada pieza del blindaje, en el orden en que hay que montarlas."""
    pasos = [
        {"titulo": "backupctl instalado en el servidor", "hecho": hay_ctl,
         "hacer": "Pestaña Servidor → «Instalar en el servidor»."},
    ]
    if not hay_ctl:
        for t, h in [("Respaldo de bases de datos programado", "Pestaña Programación."),
                     ("Respaldos incrementales (Restic) configurados", "Pestaña HestiaCP."),
                     ("Claves de recuperación rescatadas", "Pestaña HestiaCP.")]:
            pasos.append({"titulo": t, "hecho": False, "hacer": h})
        return pasos

    def remoto(*args):
        try:
            return subprocess.run(
                ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", destino, *args],
                capture_output=True, text=True, timeout=25)
        except Exception:
            return None

    # ¿Cron del respaldo de bases de datos?
    c = remoto(f"crontab -l 2>/dev/null | grep -c backupctl || true")
    cron_bd = bool(c and c.stdout.strip() not in ("", "0"))
    pasos.append({"titulo": "Respaldo de bases de datos programado", "hecho": cron_bd,
                  "hacer": "Pestaña Programación → «Programar en el servidor»."})

    # ¿Restic configurado y con cron?
    c = remoto("cat /usr/local/hestia/data/users/conf/restic.conf 2>/dev/null || true")
    restic = bool(c and "REPO=" in (c.stdout or ""))
    pasos.append({"titulo": "Respaldos incrementales (Restic) configurados", "hecho": restic,
                  "hacer": "Pestaña HestiaCP → configurar el remoto y registrar el host."})

    c = remoto("crontab -l 2>/dev/null | grep -c v-backup-users-restic || true")
    cron_restic = bool(c and c.stdout.strip() not in ("", "0"))
    pasos.append({"titulo": "Cron de Restic activo", "hecho": cron_restic,
                  "hacer": "Pestaña HestiaCP → «Activar su cron». HestiaCP no lo hace solo."})

    # ¿Claves rescatadas en el repositorio?
    meta = profile_meta(name)
    salida = meta.get("HESTIA_OUTPUT_DIR", "")
    tiene = False
    if salida and os.path.isdir(salida):
        f = os.listdir(salida)
        tiene = any(x.startswith("Restic_Configs_") for x in f) and any(x.startswith("rclone_") for x in f)
    pasos.append({"titulo": "Claves de recuperación rescatadas", "hecho": tiene,
                  "hacer": "Pestaña HestiaCP → «Traer las claves del servidor»."})
    return pasos


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

        if u.path == "/api/probe":
            name = parse_qs(u.query).get("profile", [""])[0]
            if not SAFE_NAME.match(name or ""):
                return self._json({"error": "perfil no válido"}, 400)
            return self._json(probe(name))

        if u.path == "/api/config-raw":
            name = parse_qs(u.query).get("profile", [""])[0]
            if not SAFE_NAME.match(name or ""):
                return self._json({"error": "perfil no válido"}, 400)
            r = subprocess.run(
                [str(BACKUPCTL), "--no-color", "-p", name, "config", "--path"],
                capture_output=True, text=True, timeout=20)
            ruta = Path(r.stdout.strip())
            # El archivo tiene que estar dentro del repositorio: corta cualquier
            # intento de leer otra cosa a través del nombre de perfil.
            try:
                ruta.resolve().relative_to(BC_ROOT.resolve())
            except ValueError:
                return self._json({"error": "ruta fuera del repositorio"}, 400)
            if not ruta.is_file():
                return self._json({"error": "no se encontró el env.sh"}, 404)
            return self._json({"ruta": str(ruta), "contenido": ruta.read_text()})

        return self._send(404, "no encontrado", "text/plain; charset=utf-8")

    # --- POST: ejecutar una acción, retransmitiendo la salida ---------------
    def do_POST(self):
        ruta = urlparse(self.path).path
        if ruta not in ("/api/run", "/api/setup", "/api/config-save",
                        "/api/sshkey", "/api/rclone"):
            return self._send(404, "no encontrado", "text/plain; charset=utf-8")
        if not self._auth_ok():
            return self._json({"error": "no autorizado"}, 403)

        try:
            n = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._json({"error": "petición ilegible"}, 400)

        if ruta == "/api/config-save":
            return self._guardar_config(payload)
        if ruta == "/api/setup":
            return self._alta(payload)
        if ruta == "/api/sshkey":
            return self._instalar_clave(payload)
        if ruta == "/api/rclone":
            return self._rclone(payload)

        argv, err = build_argv(payload.get("profile"),
                               payload.get("action"),
                               payload.get("opts"))
        if argv is None:
            return self._json({"error": err}, 400)

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


    # --- Guardar el env.sh de un perfil ------------------------------------
    def _guardar_config(self, payload):
        name = payload.get("profile") or ""
        contenido = payload.get("contenido")
        if not SAFE_NAME.match(name) or not isinstance(contenido, str):
            return self._json({"error": "petición no válida"}, 400)
        if len(contenido) > 64_000:
            return self._json({"error": "archivo demasiado grande"}, 400)

        ruta = BC_ROOT / name / "env.sh"
        try:
            ruta.resolve().relative_to(BC_ROOT.resolve())
        except ValueError:
            return self._json({"error": "ruta fuera del repositorio"}, 400)
        if not ruta.is_file():
            return self._json({"error": "no existe ese env.sh"}, 404)

        # Se valida la sintaxis ANTES de tocar el archivo bueno: un env.sh roto
        # deja el perfil inservible y todas las órdenes fallando.
        tmp = ruta.with_suffix(".sh.nuevo")
        tmp.write_text(contenido)
        chk = subprocess.run(["bash", "-n", str(tmp)],
                             capture_output=True, text=True)
        if chk.returncode != 0:
            tmp.unlink(missing_ok=True)
            return self._json({"error": "error de sintaxis:\n" + chk.stderr.strip()}, 400)

        shutil.copy2(ruta, ruta.with_suffix(".sh.anterior"))
        tmp.replace(ruta)
        return self._json({"ok": True, "ruta": str(ruta)})

    # --- Instalar la clave SSH en el servidor -------------------------------
    def _instalar_clave(self, payload):
        name = payload.get("profile") or ""
        destino = (payload.get("target") or "").strip()
        clave = payload.get("password")
        if not SAFE_NAME.match(name):
            return self._json({"error": "perfil no válido"}, 400)
        if destino and not re.match(r"^[A-Za-z0-9._\-]+@[A-Za-z0-9._\-]+$", destino):
            return self._json({"error": "destino no válido"}, 400)
        if not isinstance(clave, str) or not clave:
            return self._json({"error": "falta la contraseña"}, 400)

        # La contraseña va a un archivo 0600 que solo lee el ayudante de ssh.
        # Pasarla por la línea de órdenes la haría visible en `ps`; por el
        # entorno, en /proc/PID/environ.
        fd, tmp = tempfile.mkstemp()
        try:
            os.chmod(tmp, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(clave)
            clave = None

            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()

            argv = [str(BACKUPCTL), "--no-color", "-p", name, "sshkey"]
            if destino:
                argv.append(destino)
            env = dict(os.environ, BC_NO_COLOR="1", BC_SSH_PASSWORD_FILE=tmp)
            p = subprocess.Popen(argv, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, text=True,
                                 bufsize=1, env=env)
            for line in p.stdout:
                self.wfile.write(line.encode("utf-8", "replace")); self.wfile.flush()
            p.wait()
            self.wfile.write(f"\n__FIN__{p.returncode}\n".encode())
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            try:
                self.wfile.write(f"[ERROR] {e}\n".encode())
            except Exception:
                pass
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass

    # --- Configurar el remoto de rclone ------------------------------------
    def _rclone(self, payload):
        name = payload.get("profile") or ""
        if not SAFE_NAME.match(name):
            return self._json({"error": "perfil no válido"}, 400)
        remoto = (payload.get("name") or "").strip()
        if not re.match(r"^[A-Za-z0-9._-]{1,64}$", remoto):
            return self._json({"error": "nombre de remoto no válido"}, 400)
        tipo = payload.get("type") or "s3"
        if tipo not in ("s3", "local"):
            return self._json({"error": "tipo no válido"}, 400)

        # Las credenciales viajan por el entorno del proceso hijo, nunca por
        # argv: en argv serían visibles en `ps` para toda la máquina.
        env = dict(os.environ, BC_NO_COLOR="1",
                   BC_OPT_RC_NAME=remoto, BC_OPT_RC_TYPE=tipo,
                   BC_OPT_RC_KEY=payload.get("key", "") or "",
                   BC_OPT_RC_SECRET=payload.get("secret", "") or "",
                   BC_OPT_RC_ENDPOINT=payload.get("endpoint", "") or "",
                   BC_OPT_RC_REGION=payload.get("region", "") or "")

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            p = subprocess.Popen(
                [str(BACKUPCTL), "--no-color", "-y", "-p", name, "hestia", "rclone"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL, text=True, bufsize=1, env=env)
            for line in p.stdout:
                self.wfile.write(line.encode("utf-8", "replace")); self.wfile.flush()
            p.wait()
            self.wfile.write(f"\n__FIN__{p.returncode}\n".encode())
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            try: self.wfile.write(f"[ERROR] {e}\n".encode())
            except Exception: pass

    # --- Alta de un perfil, retransmitiendo la salida -----------------------
    def _alta(self, payload):
        campos = {
            "BC_SETUP_NAME":        payload.get("name", ""),
            "BC_SETUP_HOST":        payload.get("host", ""),
            "BC_SETUP_SSH_USER":    payload.get("ssh_user", "admin"),
            "BC_SETUP_OWNER":       payload.get("owner", ""),
            "BC_SETUP_PATH":        payload.get("path", ""),
            "BC_SETUP_DB_USER":     payload.get("db_user", ""),
            "BC_SETUP_DB_PASS":     payload.get("db_pass", ""),
            "BC_SETUP_HEALTHCHECK": payload.get("healthcheck", ""),
            "BC_SETUP_CREATE_DB":   "si" if payload.get("crear_db") else "no",
            "BC_SETUP_ADMIN_USER":  payload.get("admin_user", ""),
            "BC_SETUP_ADMIN_PASS":  payload.get("admin_pass", ""),
            "BC_SETUP_DEPLOY":      "si" if payload.get("desplegar") else "no",
            # Respaldos incrementales: opcional, y si viene se monta en el
            # mismo flujo del alta en lugar de dejarlo para otra pantalla.
            "BC_SETUP_RC_NAME":     payload.get("rc_name", ""),
            "BC_SETUP_RC_TYPE":     payload.get("rc_type", "s3"),
            "BC_SETUP_RC_KEY":      payload.get("rc_key", ""),
            "BC_SETUP_RC_SECRET":   payload.get("rc_secret", ""),
            "BC_SETUP_RC_ENDPOINT": payload.get("rc_endpoint", ""),
            "BC_SETUP_RC_REGION":   payload.get("rc_region", ""),
            "BC_SETUP_REPO":        payload.get("repo", ""),
        }
        if not SAFE_NAME.match(campos["BC_SETUP_NAME"]):
            return self._json({"error": "nombre de perfil no válido"}, 400)
        if not campos["BC_SETUP_HOST"]:
            return self._json({"error": "falta el servidor"}, 400)

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

        # Las credenciales van por el entorno del proceso hijo, no por la línea
        # de órdenes: así no aparecen en `ps` para el resto de la máquina.
        env = dict(os.environ, BC_NO_COLOR="1", **{k: str(v) for k, v in campos.items()})
        try:
            p = subprocess.Popen([str(BACKUPCTL), "--no-color", "-y", "setup"],
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, text=True,
                                 bufsize=1, env=env)
            for line in p.stdout:
                self.wfile.write(line.encode("utf-8", "replace")); self.wfile.flush()
            p.wait()
            self.wfile.write(f"\n__FIN__{p.returncode}\n".encode())
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            self.wfile.write(f"[ERROR] {e}\n".encode())


def main():
    ap = argparse.ArgumentParser(description="Interfaz web de backupctl")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--open", action="store_true")
    a = ap.parse_args()

    if not BACKUPCTL.is_file():
        sys.exit(f"ERROR: no se encontró {BACKUPCTL}")

    # Un puerto ocupado es lo más común al reabrir la interfaz, casi siempre
    # porque quedó una instancia anterior. Un rastreo de Python no ayuda a nadie:
    # se explica quién lo tiene y cómo salir del paso.
    try:
        srv = ThreadingHTTPServer((a.host, a.port), Handler)
    except OSError as e:
        if getattr(e, "errno", None) != 98:
            sys.exit(f"ERROR: no se pudo abrir {a.host}:{a.port} — {e}")
        print()
        print(f"  El puerto {a.port} ya está ocupado.")
        quien = shutil.which("ss") or shutil.which("lsof")
        if quien and quien.endswith("ss"):
            r = subprocess.run([quien, "-ltnp"], capture_output=True, text=True)
            for ln in r.stdout.splitlines():
                if f":{a.port} " in ln or f":{a.port}\t" in ln:
                    print("  Lo tiene: " + ln.strip())
        print()
        print("  Puede ser una interfaz web que dejaste abierta. Opciones:")
        print()
        print(f"    backupctl web --port {a.port + 1}      usar otro puerto")
        print( "    pkill -f web/server.py            cerrar la anterior")
        print()
        sys.exit(1)

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
