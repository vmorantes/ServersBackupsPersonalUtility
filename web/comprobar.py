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

# 1.b · Toda acción tiene que declarar si toca algo
# Es la regla que pidió el usuario: ninguna acción puede ofrecerse sin decir
# antes si no toca nada, si escribe o si destruye. Se comprueba aquí para que
# no se pueda olvidar al añadir la siguiente.
bloques = re.findall(r'<div class="accion">(.*?)(?=<div class="accion">|</div>\s*</div>\s*<h3|\Z)',
                     html, re.S)
sin_riesgo = []
for b in bloques:
    if not re.search(r'class="(no-toca|escribe|destruye)"', b):
        nombre = re.search(r'>([^<]+)</button>', b)
        sin_riesgo.append(nombre.group(1).strip() if nombre else "(sin nombre)")
if sin_riesgo:
    problemas.append("Acciones que no declaran si tocan algo: " + ", ".join(sin_riesgo))

# 1.c · Toda pestaña tiene que enseñar su estado antes de ofrecer acciones
# Se busca dentro del bloque de cada pestaña, porque una pestaña puede tener
# varias franjas (HestiaCP tiene una por sección) y ninguna se llama como ella.
marcas = [(m.group(1), m.start()) for m in
          re.finditer(r'<div class="tab" data-tab="([^"]+)"', html)]
solo_lectura = {"estado", "registros", "config", "blindaje"}
sin_estado = []
for i, (t, ini) in enumerate(marcas):
    fin = marcas[i + 1][1] if i + 1 < len(marcas) else len(html)
    if t in solo_lectura:
        continue
    if 'class="estado-real"' not in html[ini:fin]:
        sin_estado.append(t)
if sin_estado:
    problemas.append("Pestañas sin estado a la vista: " + ", ".join(sorted(sin_estado)))

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
