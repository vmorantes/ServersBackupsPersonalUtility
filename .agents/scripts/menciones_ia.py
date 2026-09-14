#!/usr/bin/env python3
"""
Busca menciones a IA en lo que se entrega: archivos entregables (bin/, lib/,
web/, tools/, config/, docs/, README.md...) y mensajes de commit posteriores
a la adopción (patrones.BASE_COMMITS). Regla:
.agents/rules/40-salvaguardas.md, sección 4.

Uso:
    python3 .agents/scripts/menciones_ia.py                 # árbol + todos los commits
    python3 .agents/scripts/menciones_ia.py --mensaje "texto"   # un mensaje suelto
    python3 .agents/scripts/menciones_ia.py --archivo RUTA      # mensaje de commit (hook commit-msg)
"""
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "guardas"))
from patrones import BASE_COMMITS, buscar, es_entregable  # noqa: E402

RAIZ = os.path.realpath(os.path.join(AQUI, "..", ".."))


def git(*args):
    return subprocess.run(["git", "-C", RAIZ, *args], capture_output=True, text=True, check=True).stdout


def archivos_entregables():
    # Versionados y nuevos no ignorados: lo que un commit podría llevarse.
    lista = git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split("\0")
    return sorted({r for r in lista if r and es_entregable(r) and os.path.isfile(os.path.join(RAIZ, r))})


def main():
    args = sys.argv[1:]
    problemas = []
    if args[:1] == ["--mensaje"]:
        problemas += [f"mensaje:{n}: {m!r}" for n, m in buscar(" ".join(args[1:]))]
    elif args[:1] == ["--archivo"] and len(args) > 1:
        # Mensaje de commit tal como lo entrega git al hook commit-msg: las
        # líneas que empiezan por '#' son comentarios de git y no se commitean.
        with open(args[1], encoding="utf-8") as f:
            texto = "\n".join(l for l in f.read().splitlines() if not l.startswith("#"))
        problemas += [f"mensaje:{n}: {m!r}" for n, m in buscar(texto)]
    else:
        for ruta in archivos_entregables():
            try:
                with open(os.path.join(RAIZ, ruta), encoding="utf-8") as f:
                    texto = f.read()
            except (UnicodeDecodeError, OSError):
                continue
            problemas += [f"{ruta}:{n}: {m!r}" for n, m in buscar(texto)]
        # Solo los commits posteriores a BASE_COMMITS (ver patrones.py). Si esa
        # base no está en la historia de esta rama, se revisa todo: mejor un
        # falso positivo que dejar de mirar.
        base = subprocess.run(["git", "-C", RAIZ, "merge-base", "--is-ancestor", BASE_COMMITS, "HEAD"], capture_output=True)
        rango = [f"{BASE_COMMITS}..HEAD"] if base.returncode == 0 else []
        for linea in git("log", "--format=%h%x00%B%x1e", *rango).split("\x1e"):
            if "\0" not in linea:
                continue
            h, cuerpo = linea.strip().split("\0", 1)
            problemas += [f"commit {h}:{n}: {m!r}" for n, m in buscar(cuerpo)]
    for p in problemas:
        print(p)
    print(f"menciones a IA en entregables: {len(problemas)}")
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
