#!/usr/bin/env python3
"""
Comprobación de coherencia de la interfaz web.

Existe porque este fallo ya se ha colado dos veces: acciones definidas en el
servidor sin ningún botón que las invoque, y manejadores de JavaScript
apuntando a elementos que ya no existen. Lo segundo es peor, porque un solo id
ausente lanza un TypeError que aborta el script entero y deja la pantalla en
blanco sin ninguna pista.

    python3 web/comprobar.py        devuelve 1 si hay incoherencias
"""
import importlib.util
import os
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
os.environ.setdefault("BC_ROOT", str(RAIZ))

spec = importlib.util.spec_from_file_location("srv", RAIZ / "web" / "server.py")
srv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(srv)

html = (RAIZ / "web" / "index.html").read_text()
js = (RAIZ / "web" / "app.js").read_text()

problemas = []

# 1 · Acciones del servidor sin forma de invocarlas
invocadas = set(re.findall(r'data-act="([^"]+)"', html))
invocadas |= set(re.findall(r"ejecutar\('([a-z-]+)'", js))
huerfanas = sorted(set(srv.A) - invocadas)
if huerfanas:
    problemas.append("Acciones definidas y sin botón: " + ", ".join(huerfanas))

# 2 · Botones que llaman a acciones inexistentes
propias = {"setup", "sshkey", "hestia rclone"}      # van por endpoints propios
fantasma = sorted(invocadas - set(srv.A) - propias)
if fantasma:
    problemas.append("Botones que invocan acciones inexistentes: " + ", ".join(fantasma))

# 3 · Manejadores apuntando a elementos que no existen
ids = set(re.findall(r'id="([^"]+)"', html))
refs = set(re.findall(r"on\('#([A-Za-z0-9_-]+)'", js))
refs |= set(re.findall(r"\$\('#([A-Za-z0-9_-]+)'\)\.(?:value|checked|hidden|focus|innerHTML|textContent)", js))
ausentes = sorted(refs - ids)
if ausentes:
    problemas.append("El JavaScript usa ids que no existen: " + ", ".join("#" + x for x in ausentes))

# 4 · Cada acción debe explicar qué hace
sin_desc = len(re.findall(r'accion-desc"></div>', html))
if sin_desc:
    problemas.append(f"{sin_desc} acciones sin descripción de lo que hacen")

if problemas:
    print("Incoherencias en la interfaz web:")
    for p in problemas:
        print("  ✗ " + p)
    sys.exit(1)

print(f"Interfaz coherente: {len(srv.A)} acciones, todas con botón y descripción.")
