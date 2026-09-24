#!/usr/bin/env python3
"""
Guarda PreToolUse de Claude Code (enganchada en .claude/settings.json).

Lee de stdin el JSON de la llamada a herramienta y la bloquea (código de
salida 2, motivo por stderr) si viola una salvaguarda de
.agents/rules/40-salvaguardas.md. Es una red, no la regla: que algo pase
por aquí no lo autoriza.

Criterio de diseño: ante la duda, bloquear. Un falso positivo cuesta una
pregunta al PO; un falso negativo puede costar un servidor de producción o
una credencial copiada en una transcripción. Las pruebas están en
probar_guardia.py.

Ojo: si este archivo no llega a ejecutarse (un error de sintaxis), Claude
Code trata el fallo como no bloqueante y DEJA PASAR la llamada. Por eso
verificar.sh corre probar_guardia.py en cada ronda.
"""
import glob
import json
import os
import re
import shlex
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patrones import buscar, es_entregable  # noqa: E402

RAIZ = os.path.realpath(
    os.environ.get("CLAUDE_PROJECT_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
)
HOME = os.path.expanduser("~")
# Directorio desde el que se lanza la llamada; main() lo toma del JSON del hook.
CWD = RAIZ

# Dónde se puede escribir fuera del repositorio: temporales y la memoria
# nativa de Claude Code.
ESCRIBIBLES_EXTRA = ("/tmp/", os.path.join(HOME, ".claude", "projects") + "/")

PROHIBIDOS = {
    # Escalada de privilegios.
    "sudo", "su", "pkexec", "doas",
    # Servidores remotos.
    "ssh", "scp", "sftp", "sshpass", "ssh-copy-id", "mosh", "telnet", "ftp", "lftp", "ncftp",
    # Bases de datos: backupctl habla con MySQL; los agentes no.
    "mysql", "mariadb", "mysqldump", "mariadb-dump", "mysqladmin", "mysqlcheck", "mysqlimport",
    "psql", "mongo", "mongosh", "redis-cli", "sqlcmd",
    # Paquetes y sistema.
    "apt", "apt-get", "aptitude", "dpkg", "snap", "flatpak", "yum", "dnf",
    "systemctl", "service", "crontab", "mkfs", "fdisk", "parted", "dd",
    "shutdown", "reboot", "poweroff", "halt", "chown", "useradd", "userdel",
    "usermod", "passwd", "visudo", "iptables", "ufw", "nft",
    # Escritorio del PO (tools/backupctl-escritorio.sh los usa).
    "update-desktop-database", "gtk-update-icon-cache", "xdg-open",
}
ENVOLTORIOS = {"env", "nohup", "time", "command", "exec", "nice", "timeout", "xargs", "watch", "setsid"}
SHELLS = {"bash", "sh", "dash", "zsh", "source", "."}

# Almacenamiento remoto: con las claves de un perfil, restic y rclone hablan
# con el S3 real. Solo se permite preguntarles la versión o la ayuda.
ALMACEN_REMOTO = {"restic", "rclone"}
SOLO_INFORMATIVO = (["version"], ["--version"], ["help"], ["--help"], ["-h"])

# Órdenes de backupctl que no cargan perfil ni tocan nada (bin/backupctl:233-268).
BACKUPCTL_SEGURAS = {"help", "version", "profiles"}

# Archivos con credenciales o datos del PO. Los env.sh de los perfiles (y las
# copias que dejan pull y la web), las claves rescatadas de HestiaCP, el
# ESTADO.md que genera pull (lleva el diff del env.sh) y la configuración de
# git (la URL del remoto lleva un token).
SECRETO = re.compile(
    r"(^|/)env\.sh(\.anterior|\.nuevo)?$|(^|/)output/HestiaCP(/|$)|(^|/)ESTADO\.md$|(^|/)\.git/config$"
)
PATRONES_SECRETOS = (
    "env.sh*", "*/env.sh*", "servers/*/env.sh*",
    "*/output/HestiaCP", "*/output/HestiaCP/**", "servers/*/output/HestiaCP/**",
    "*/ESTADO.md", "servers/*/ESTADO.md", ".git/config",
)
# Comandos que pueden recibir esas rutas sin mostrar su contenido.
INOCUOS_CON_SECRETOS = {"ls", "stat", "test", "[", "wc", "file", "du", "cmp", "sha256sum", "md5sum"}
GIT_INOCUOS_CON_SECRETOS = {"status", "ls-files", "check-ignore"}

OPCIONES_CON_VALOR = {
    "-e", "-f", "-m", "-A", "-B", "-C", "-g", "-t", "-T", "--glob", "--type", "--type-not",
    "--max-count", "--context", "--after-context", "--before-context", "--regexp", "--file",
}
SOLO_NOMBRES = {"-l", "-L", "-c", "-q", "--files-with-matches", "--files-without-match", "--count", "--quiet", "--silent"}

REDIRECCION_AL_SISTEMA = re.compile(r"(>>?|\btee\b(\s+-a)?)\s*[\"']?(/etc|/usr|/root|/boot|/bin|/sbin|/lib|/var|/opt|/srv)/")
RUTAS_DEL_SISTEMA = re.compile(r"(^|[\s>=\"'])(/etc|/usr|/root|/boot|/bin|/sbin|/lib|/var/lib|/opt|/srv)(/|\s|$|[\"'])")


class Bloqueo(Exception):
    pass


def bloquear(motivo):
    raise Bloqueo(motivo)


def dentro_de(ruta, base):
    ruta = os.path.realpath(ruta)
    base = os.path.realpath(base)
    return ruta == base or ruta.startswith(base + os.sep)


def absoluta(ruta):
    return os.path.realpath(os.path.join(CWD, os.path.expanduser(ruta)))


def ruta_escribible(ruta):
    a = absoluta(ruta)
    return dentro_de(a, RAIZ) or any(a.startswith(p) for p in ESCRIBIBLES_EXTRA)


# --- Credenciales -------------------------------------------------------------

def es_secreto(ruta):
    """Una ruta existente del repositorio que guarda credenciales o datos del PO."""
    a = absoluta(ruta)
    if not dentro_de(a, RAIZ) or not os.path.exists(a):
        return False
    return bool(SECRETO.search(os.path.relpath(a, RAIZ).replace(os.sep, "/")))


def secretos():
    encontrados = set()
    for patron in PATRONES_SECRETOS:
        for p in glob.glob(os.path.join(RAIZ, patron), recursive=True):
            if SECRETO.search(os.path.relpath(p, RAIZ).replace(os.sep, "/")):
                encontrados.add(os.path.realpath(p))
    return encontrados


def contiene_secretos(ruta):
    a = absoluta(ruta)
    return os.path.isdir(a) and any(dentro_de(s, a) for s in secretos())


def expandir(fragmento):
    if any(c in fragmento for c in "*?["):
        return glob.glob(os.path.join(CWD, os.path.expanduser(fragmento)))
    return [fragmento]


def menciona_secreto(token):
    """
    ¿El argumento apunta a un archivo con credenciales? Se mira el token y los
    trozos con forma de ruta que lleve dentro (HEAD:ruta, --file=ruta,
    open('ruta')), y lo que expandiría un glob.
    """
    for trozo in {token, *re.findall(r"[\w./~*?\[\]-]+", token)}:
        for ruta in expandir(trozo):
            if es_secreto(ruta):
                return True
    return False


def solo_nombres(args):
    for a in args:
        if a in SOLO_NOMBRES:
            return True
        if a.startswith("-") and not a.startswith("--") and any(c in a[1:] for c in "lLcq"):
            return True
    return False


def posicionales(args, saltar_patron):
    resultado = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            resultado += args[i + 1:]
            break
        if a in OPCIONES_CON_VALOR:
            i += 2
            continue
        if not a.startswith("-"):
            resultado.append(a)
        i += 1
    return resultado[1:] if saltar_patron and resultado else resultado


def revisar_busqueda(cmd, args):
    """grep -r, rg, ag, ack y find -exec: recorren directorios y muestran contenido."""
    if cmd in ("grep", "egrep", "fgrep"):
        recursivo = any(
            a in ("-r", "-R", "--recursive", "--dereference-recursive")
            or (a.startswith("-") and not a.startswith("--") and any(c in a[1:] for c in "rR"))
            for a in args
        )
        if not recursivo:
            return
    elif cmd == "find":
        if not any(a in ("-exec", "-execdir", "-ok", "-okdir") for a in args):
            return
        i = next(i for i, a in enumerate(args) if a in ("-exec", "-execdir", "-ok", "-okdir"))
        ejecutado = args[i + 1:i + 3]
        if ejecutado[:1] and (ejecutado[0] in INOCUOS_CON_SECRETOS or ejecutado == ["bash", "-n"]):
            return
        objetivos = [a for a in args[:i] if not a.startswith(("-", "(", "!"))][:1] or ["."]
        for o in objetivos:
            if contiene_secretos(o):
                bloquear(f"find -exec sobre {o!r}, que contiene archivos con credenciales: limita la búsqueda a bin/ lib/ web/ tools/ docs/ config/ .agents/.")
        return
    elif cmd not in ("rg", "ag", "ack"):
        return
    if solo_nombres(args):
        return
    patron_explicito = any(a in ("-e", "-f", "--regexp", "--file") or a.startswith(("--regexp=", "--file=")) for a in args)
    objetivos = posicionales(args, saltar_patron=not patron_explicito) or ["."]
    for o in objetivos:
        for ruta in expandir(o):
            if contiene_secretos(ruta):
                bloquear(
                    f"{cmd} recursivo sobre {o!r} mostraría credenciales de un perfil (env.sh, output/HestiaCP): "
                    "limítalo a bin/ lib/ web/ tools/ docs/ config/ .agents/, o usa -l para ver solo nombres."
                )


# --- Órdenes del propio proyecto -------------------------------------------------

def revisar_backupctl(args):
    if any(a in ("-h", "--help", "-V", "--version") for a in args):
        return
    posicional = []
    i = 0
    while i < len(args):
        if args[i] in ("-p", "--profile"):
            i += 2
            continue
        if not args[i].startswith("-"):
            posicional.append(args[i])
        i += 1
    if posicional[:1] and posicional[0] in BACKUPCTL_SEGURAS:
        return
    orden = posicional[0] if posicional else "(menú interactivo)"
    bloquear(
        f"backupctl {orden}: carga un perfil con credenciales reales y puede conectar, escribir o usar sudo "
        "(ningún --dry-run está libre de efectos). Solo help, version y profiles; lo demás se prueba desde el "
        "banco de pruebas (.agents/context/40-entorno.md) o lo ejecuta el PO."
    )


def sin_redirecciones(args):
    """
    Quita las redirecciones, que no son argumentos de la orden. shlex parte
    '2>&1' en '2', '>&', '1' y '>/dev/null' en '>', '/dev/null': cada operador
    se lleva su destino (el token siguiente) y el descriptor numérico que lo
    precede, si lo hay.
    """
    limpios = []
    i = 0
    while i < len(args):
        if re.fullmatch(r"[<>&]+", args[i]):
            if limpios and limpios[-1].isdigit():
                limpios.pop()
            i += 2
            continue
        limpios.append(args[i])
        i += 1
    return limpios


def revisar_proyecto(cmd, args, partes):
    """Lanzar backupctl, su web o su lanzador de escritorio."""
    args = sin_redirecciones(args)
    if cmd in SHELLS:
        if "-n" in args:
            return
        guion = next((a for a in args if not a.startswith("-")), None)
        if guion is None:
            return
        nombre = os.path.basename(guion)
        resto = args[args.index(guion) + 1:]
    else:
        nombre, resto = cmd, args
    if nombre == "backupctl":
        revisar_backupctl(resto)
    if nombre == "backupctl-escritorio.sh" and resto not in ([], ["estado"], ["-h"], ["--help"]):
        bloquear("tools/backupctl-escritorio.sh escribe en ~/.local/share y lanza procesos: lo ejecuta el PO.")
    if cmd.startswith("python") and any(os.path.basename(a) == "server.py" for a in args):
        bloquear("web/server.py levanta un servidor que ejecuta backupctl con -y y hace ssh a los perfiles: lo lanza el PO.")
    if cmd == "mkdocs" and args[:1] in (["serve"], ["gh-deploy"]):
        bloquear(f"mkdocs {args[0]}: deja un servidor en marcha o publica en GitHub Pages; lo decide el PO.")


# --- Git ---------------------------------------------------------------------------

def revisar_git(args):
    if not args:
        return
    # Salta opciones globales: git -C ruta ..., git -c k=v ...
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in ("-C", "-c") else 1
    if i >= len(args):
        return
    sub, resto = args[i], args[i + 1:]

    if sub == "push":
        bloquear("git push solo lo hace el PO, o el coder con su orden expresa para esa subida (00-core.md, ADR 0003).")
    if sub in ("fetch", "pull", "ls-remote", "clone"):
        bloquear(f"git {sub} usa la credencial del remoto (va dentro de su URL): lo hace el PO.")
    if sub == "remote" and resto:
        bloquear("git remote con argumentos muestra o cambia la URL del remoto, que lleva un token: prohibido.")
    if sub in ("rebase", "filter-branch", "filter-repo", "replace"):
        bloquear(f"git {sub} reescribe historia: prohibido (40-salvaguardas.md).")
    if sub == "reset" and ("--hard" in resto or "--merge" in resto or "--keep" in resto):
        bloquear("git reset --hard descarta trabajo sin retorno: prohibido.")
    if sub == "clean" and (
        "--force" in resto or any(a.startswith("-") and not a.startswith("--") and "f" in a[1:] for a in resto)
    ):
        bloquear("git clean -f borra lo no versionado sin retorno: prohibido.")
    if sub == "checkout" and ("--" in resto or "." in resto or "-f" in resto or "--force" in resto):
        bloquear("git checkout -- / . / -f descarta cambios locales: prohibido.")
    if sub == "restore" and "--staged" not in resto:
        bloquear("git restore sobre el árbol descarta cambios: prohibido (solo --staged).")
    if sub == "branch":
        # ADR 0011: el coder borra ramas locales YA FUSIONADAS con -d (git se niega si no lo
        # están). Forzar (-D, --force), renombrar y tocar ramas remotas siguen siendo del PO.
        if any(a in ("-D", "-M", "-m", "--move", "-C", "-c", "--copy") for a in resto):
            bloquear("forzar el borrado, renombrar o copiar ramas requiere permiso del PO (ADR 0011).")
        borra = any(a in ("-d", "--delete") for a in resto)
        if borra and any(a in ("-f", "--force", "-r", "--remotes", "-a", "--all") for a in resto):
            bloquear("borrar ramas forzando o ramas remotas requiere permiso del PO (ADR 0011).")
    if sub == "stash" and resto[:1] in (["drop"], ["clear"]):
        bloquear("git stash drop/clear pierde trabajo: prohibido.")
    if sub == "config":
        lectura = any(a in ("--get", "--list", "-l", "--get-all", "--get-regexp", "--show-origin") for a in resto)
        if not lectura:
            bloquear("git config es configuración del PO: no se toca.")
        if any(a in ("--list", "-l", "--get-regexp") or a.startswith(("remote.", "url.", "credential")) for a in resto):
            bloquear("esa lectura de git config mostraría la URL del remoto, que lleva un token: prohibido.")
    if sub == "add" and any(a in (".", "-A", "--all", "*", ":/", "-u", "--update") for a in resto):
        bloquear("git add . / -A / -u está prohibido: añade rutas explícitas (30-protocolo-coder.md).")
    if sub == "grep" and not solo_nombres(resto):
        if not any(a.startswith((":!", ":^", ":(exclude")) for a in resto):
            rutas = resto[resto.index("--") + 1:] if "--" in resto else posicionales(resto, saltar_patron=True)
            for r in rutas or ["."]:
                if contiene_secretos(r) or es_secreto(r):
                    bloquear("git grep sobre el repositorio entero mostraría credenciales de un perfil: pasa rutas de código o ':!*/env.sh*' ':!*/output/'.")
    if sub not in GIT_INOCUOS_CON_SECRETOS and not (sub == "log" and not any(a in ("-p", "-u", "--patch") for a in resto)):
        for a in resto:
            # Una exclusión de pathspec (':!*/env.sh*') nombra el secreto para apartarlo.
            if a.startswith((":!", ":^", ":(exclude")):
                continue
            if menciona_secreto(a):
                bloquear(f"git {sub} sobre {a!r}: es un archivo con credenciales o del PO (40-salvaguardas.md §6).")
    if sub == "commit":
        if "--amend" in resto:
            bloquear("git commit --amend reescribe historia: prohibido.")
        mensaje = []
        for j, a in enumerate(resto):
            if a in ("-m", "--message") and j + 1 < len(resto):
                mensaje.append(resto[j + 1])
            elif a.startswith("--message="):
                mensaje.append(a.split("=", 1)[1])
            elif a.startswith("-m") and len(a) > 2:
                mensaje.append(a[2:])
            elif a in ("-F", "--file") and j + 1 < len(resto):
                try:
                    with open(absoluta(resto[j + 1]), encoding="utf-8") as f:
                        mensaje.append(f.read())
                except OSError:
                    pass
        hallazgos = buscar("\n".join(mensaje))
        if hallazgos:
            bloquear(f"el mensaje de commit menciona IA ({hallazgos[0][1]!r}): prohibido (40-salvaguardas.md §4).")


def revisar_rm(args):
    recursivo = any(a in ("-r", "-R", "--recursive") or (a.startswith("-") and not a.startswith("--") and ("r" in a or "R" in a)) for a in args)
    objetivos = [a for a in args if not a.startswith("-")]
    for o in objetivos:
        if o in ("/", "~", "*", ".", "..", "/*", "~/*") or o.startswith(("~", "$HOME", "${HOME}")) or ".." in o.split("/"):
            bloquear(f"rm sobre {o!r}: prohibido.")
        if o.startswith("$"):
            bloquear(f"rm sobre una ruta en variable ({o!r}): no se puede comprobar, prohibido.")
        if os.path.isabs(o) and not ruta_escribible(o):
            bloquear(f"rm fuera del repositorio y de /tmp ({o!r}): prohibido.")
    if recursivo and not objetivos:
        bloquear("rm recursivo sin objetivo claro: prohibido.")


# --- Bash --------------------------------------------------------------------------

SEPARADORES = {";", "&&", "||", "|", "&", "|&", ";;", "(", ")"}


def segmentos(comando):
    """
    Devuelve una lista de comandos simples, cada uno como lista de tokens.

    Parte por líneas y, dentro de cada una, por los operadores de control
    (; && || | & paréntesis) que estén FUERA de comillas: un '|' dentro del
    patrón de un grep no separa nada. Las líneas de un heredoc se analizan
    como si fueran comandos: da falsos positivos posibles, nunca negativos.
    """
    resultado = []
    for linea in comando.replace("`", "\n").splitlines():
        try:
            lex = shlex.shlex(linea, posix=True, punctuation_chars=True)
            lex.whitespace_split = True
            partes = list(lex)
        except ValueError:
            # Comillas sin cerrar (típico de un heredoc): se trocea a lo bruto.
            partes = re.split(r"\s+", linea.strip())
        actual = []
        for p in partes:
            if p in SEPARADORES:
                if actual:
                    resultado.append(actual)
                actual = []
            else:
                actual.append(p)
        if actual:
            resultado.append(actual)
    return resultado


def tokens(partes):
    partes = [p for p in partes if p]
    # Quita asignaciones de entorno iniciales y envoltorios (env, nohup...).
    while partes and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", partes[0]) or partes[0] in ENVOLTORIOS):
        partes = partes[1:]
        # timeout 10 cmd / nice -n 5 cmd: descarta argumentos numéricos y flags del envoltorio.
        while partes and (partes[0].startswith("-") or partes[0].isdigit()):
            partes = partes[1:]
    return partes


ES_COMMIT = re.compile(r"\bgit(\s+-[cC]\s+\S+)*\s+commit\b")

# El valor de -m / --message de un commit: comillas simples, dobles o $'...'.
VALOR_MENSAJE = re.compile(
    r"""(-m|--message)(=|\s+)('(?:[^']|'\\'')*'|"(?:\\.|[^"\\])*"|\$'(?:\\.|[^'\\])*')""",
    re.S,
)


def sin_mensajes_de_commit(comando):
    """Sustituye el TEXTO del mensaje de un commit por un marcador.

    Un mensaje de varias líneas se parte por saltos de línea igual que una
    secuencia de órdenes, así que una línea del cuerpo que empiece por el
    nombre de una herramienta prohibida se analizaba como si fuera esa orden:
    describir en un commit lo que hace `v-list-...` quedaba bloqueado. El
    mensaje no se ejecuta; es texto. Lo que sí se ejecuta —una sustitución
    `$(...)` dentro del mensaje, o lo que venga después de `&&`— se sigue
    revisando, porque esto solo tapa el literal entrecomillado.

    La comprobación de menciones a IA se hace aparte, sobre el comando
    entero: esa sí tiene que mirar el texto.
    """
    if not ES_COMMIT.search(comando):
        return comando
    return VALOR_MENSAJE.sub(lambda m: f"{m.group(1)}{m.group(2)}'MENSAJE'", comando)


def revisar_bash(comando, profundidad=0):
    if profundidad > 3:
        bloquear("comando anidado demasiado profundo para revisarlo: prohibido por prudencia.")
    if re.search(r"(curl|wget)\b[^|]*\|\s*(sudo\s+)?(ba|z|da)?sh\b", comando):
        bloquear("descargar y ejecutar un script remoto está prohibido.")
    # El análisis por órdenes ignora el texto de un mensaje de commit; todo lo
    # demás del comando se revisa igual.
    analizable = sin_mensajes_de_commit(comando)
    if REDIRECCION_AL_SISTEMA.search(analizable):
        bloquear("escribir en rutas del sistema está prohibido (40-salvaguardas.md §2).")
    # Un mensaje de commit puede llegar por heredoc o $(cat ...), fuera del
    # alcance del análisis por argumentos: se examina el comando entero.
    # Solo ante una invocación real de "git [opciones globales] commit": la
    # palabra "commit" en una ruta (git-hooks/commit-msg) no cuenta.
    if ES_COMMIT.search(comando):
        hallazgos = buscar(comando)
        if hallazgos:
            bloquear(f"el commit menciona IA ({hallazgos[0][1]!r}): prohibido (40-salvaguardas.md §4).")
    # Sustituciones de comandos: dentro de comillas dobles shlex las deja como
    # un solo token y no llegarían a analizarse. Se revisan por separado.
    for interior in re.findall(r"\$\(([^()]*)\)", comando):
        revisar_bash(interior, profundidad + 1)

    for seg in segmentos(analizable):
        partes = tokens(seg)
        if not partes:
            continue
        cmd = os.path.basename(partes[0])
        args = partes[1:]

        if cmd in PROHIBIDOS or cmd.startswith("mkfs"):
            bloquear(f"'{cmd}' está prohibido para agentes (40-salvaguardas.md). Pídeselo al PO.")
        if re.match(r"^v-[a-z]", cmd) or partes[0].startswith("/usr/local/hestia/"):
            bloquear("los comandos de HestiaCP no se ejecutan desde aquí: solo el PO en su servidor.")
        if cmd in ALMACEN_REMOTO and args not in SOLO_INFORMATIVO:
            bloquear(f"{cmd} habla con el almacenamiento remoto real (S3) con las claves de un perfil: lo hace el PO.")
        if cmd == "rsync" and any(re.match(r"^[^/\s]+:", a) for a in args):
            bloquear("rsync a un host remoto: prohibido.")
        if cmd in ("pip", "pip3") and args[:1] in (["install"], ["uninstall"]):
            bloquear("instalar dependencias requiere permiso del PO (00-core.md).")
        if cmd.startswith("python") and "-m" in args and any(a in ("pip", "ensurepip") for a in args):
            bloquear("instalar dependencias requiere permiso del PO (00-core.md).")
        if cmd in ("npm", "pnpm", "yarn", "bun") and (
            any(a in ("-g", "--global", "global") for a in args) or args[:1] in (["install"], ["i"], ["add"])
        ):
            bloquear("instalar dependencias requiere permiso del PO (00-core.md).")
        if cmd == "composer" and args[:1] in (["global"], ["require"], ["install"], ["update"]):
            bloquear("instalar dependencias requiere permiso del PO (00-core.md).")
        if cmd == "chmod" and any(RUTAS_DEL_SISTEMA.search(" " + a) for a in args):
            bloquear("cambiar permisos en rutas del sistema está prohibido.")
        if cmd in SHELLS and "-c" in args:
            i = args.index("-c")
            if i + 1 < len(args):
                revisar_bash(args[i + 1], profundidad + 1)
        if cmd == "git":
            revisar_git(args)
        else:
            if not (cmd in INOCUOS_CON_SECRETOS or (cmd in SHELLS and "-n" in args)):
                for a in args:
                    if menciona_secreto(a):
                        bloquear(
                            f"{cmd} sobre {a!r}: archivo con credenciales o datos del PO. La estructura de un perfil "
                            "está en config/env.sh.example (40-salvaguardas.md §6)."
                        )
            revisar_busqueda(cmd, args)
        if cmd == "rm":
            revisar_rm(args)
        if cmd in ("mv", "cp", "ln", "install", "tee", "truncate", "touch", "mkdir"):
            destinos = [a for a in args if not a.startswith("-")]
            # Relativo se resuelve contra el cwd de la llamada; "~/..." contra HOME.
            if destinos and not ruta_escribible(destinos[-1]):
                bloquear(f"{cmd} hacia fuera del repositorio y de /tmp ({destinos[-1]!r}): prohibido.")
        revisar_proyecto(cmd, args, partes)


# --- Herramientas de archivos -----------------------------------------------------------

def revisar_escritura(entrada):
    ruta = entrada.get("file_path") or entrada.get("notebook_path") or ""
    if not ruta:
        return
    if not ruta_escribible(ruta):
        bloquear(f"escritura fuera del repositorio y de /tmp ({ruta}): prohibido.")
    if es_secreto(ruta):
        bloquear(f"{ruta} es un archivo con credenciales o del PO: no lo edita ningún agente.")
    a = absoluta(ruta)
    if not dentro_de(a, RAIZ):
        return
    relativa = os.path.relpath(a, RAIZ)
    if not es_entregable(relativa):
        return
    textos = [entrada.get("content") or "", entrada.get("new_string") or "", entrada.get("new_source") or ""]
    textos += [e.get("new_string", "") for e in entrada.get("edits") or []]
    hallazgos = buscar("\n".join(textos))
    if hallazgos:
        bloquear(f"{relativa} es entregable y el texto menciona IA ({hallazgos[0][1]!r}): prohibido (40-salvaguardas.md §4).")


def revisar_lectura(herramienta, entrada):
    if herramienta == "Read":
        ruta = entrada.get("file_path") or ""
        if ruta and es_secreto(ruta):
            bloquear(f"{ruta} guarda credenciales o datos del PO: no se lee. La estructura está en config/env.sh.example.")
    elif herramienta == "Grep":
        ruta = entrada.get("path") or "."
        if entrada.get("output_mode") == "content" and (es_secreto(ruta) or contiene_secretos(ruta)):
            bloquear("Grep con contenido sobre un directorio con credenciales de un perfil: limita path a código o usa files_with_matches.")


def main():
    global CWD
    try:
        datos = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("guardia: entrada ilegible, se bloquea por prudencia.", file=sys.stderr)
        return 2
    CWD = os.path.realpath(datos.get("cwd") or RAIZ)
    herramienta = datos.get("tool_name", "")
    entrada = datos.get("tool_input") or {}
    try:
        if herramienta == "Bash":
            revisar_bash(entrada.get("command", ""))
        elif herramienta in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
            revisar_escritura(entrada)
        elif herramienta in ("Read", "Grep"):
            revisar_lectura(herramienta, entrada)
    except Bloqueo as b:
        print(f"Bloqueado por la guarda del proyecto: {b}", file=sys.stderr)
        return 2
    except Exception as e:  # noqa: BLE001 — un fallo interno no debe dejar pasar nada
        print(f"guardia: error interno ({type(e).__name__}: {e}); se bloquea por prudencia.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
