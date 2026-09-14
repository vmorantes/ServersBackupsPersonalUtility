#!/usr/bin/env python3
"""
Genera los subagentes de Claude Code (.claude/agents/) y de Antigravity
(.agents/agents/) a partir de las personas de .agents/personas/.

Una persona es el cuerpo del prompt, compartido por las dos herramientas;
lo que cambia entre ellas (nombres de herramientas, modelos, frontmatter)
vive en AGENTES, más abajo. A cada cuerpo se le añade _comun.md: las reglas
que no cambian con el rol.

Los archivos generados no se editan a mano: se sobrescriben. Para cambiar
un agente se edita su persona o AGENTES y se vuelve a generar.

Uso:
    python3 .agents/scripts/generar_agentes.py           # genera
    python3 .agents/scripts/generar_agentes.py --check   # falla si algo está desfasado

Nota sobre `effort`: la documentación de Claude Code solo lo lista para
skills, pero el cargador de subagentes lo acepta (verificado en el binario
de Claude Code 2.1.238). Ver ADR 0002.
"""
import json
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]
PERSONAS = RAIZ / ".agents" / "personas"
COMUN = PERSONAS / "_comun.md"
SALIDA_CLAUDE = RAIZ / ".claude" / "agents"
SALIDA_ANTIGRAVITY = RAIZ / ".agents" / "agents"

AVISO = "<!-- Generado por .agents/scripts/generar_agentes.py desde .agents/personas/. No editar a mano. -->\n\n"

# Herramientas por perfil de permisos, en el vocabulario de cada herramienta.
SOLO_LECTURA = {"claude": ["Read", "Grep", "Glob"], "antigravity": ["view_file", "grep_search"]}
LECTURA_WEB = {
    "claude": ["Read", "Grep", "Glob", "WebFetch", "WebSearch"],
    "antigravity": ["view_file", "grep_search", "read_url_content", "search_web"],
}
LECTURA_SHELL = {
    "claude": ["Read", "Grep", "Glob", "Bash"],
    "antigravity": ["view_file", "grep_search", "run_command"],
}
LECTURA_SHELL_WEB = {
    "claude": ["Read", "Grep", "Glob", "Bash", "WebFetch", "WebSearch"],
    "antigravity": ["view_file", "grep_search", "run_command", "read_url_content", "search_web"],
}
ESCRITURA_DOCS = {
    "claude": ["Read", "Grep", "Glob", "Write", "Edit"],
    "antigravity": ["view_file", "grep_search", "replace_file_content", "write_to_file"],
}
ESCRITURA_SHELL = {
    "claude": ["Read", "Grep", "Glob", "Write", "Edit", "Bash"],
    "antigravity": ["view_file", "grep_search", "replace_file_content", "write_to_file", "run_command"],
}

# Modelo y esfuerzo por agente. Criterio (ADR 0002):
# - opus: donde un error cuesta producción (decidir, revisar, auditar, causa raíz).
# - sonnet: trabajo acotado con criterio (tests, documentación, verificación).
# - haiku: búsqueda mecánica.
# - fable: nunca, por decisión del PO.
# Antigravity: "pro" para lo que en Claude es opus, "flash" para el resto.
AGENTES = {
    "architect": {
        "description": "Decisiones de diseño y arquitectura para cambios sustanciales (fases propose/design de SDD). Use PROACTIVELY antes de escribir código en cualquier cambio estructural: una orden nueva de backupctl, cambios en el formato del respaldo, en deploy/pull/migrate, en lo que se escribe en un servidor o en HestiaCP, o cualquier cosa que contradiga un ADR o docs/desarrollo/decisiones.md. No para cambios de una o dos líneas.",
        "herramientas": LECTURA_WEB,
        "claude": {"model": "opus", "effort": "high"},
        "antigravity": {"model": "pro"},
    },
    "explorer": {
        "description": "Búsqueda y navegación de código, solo lectura. Use PROACTIVELY antes de cambios que toquen más de un archivo, para ubicar el código relevante sin inflar el contexto principal.",
        "herramientas": SOLO_LECTURA,
        "claude": {"model": "haiku", "effort": "low"},
        "antigravity": {"model": "flash"},
    },
    "code-reviewer": {
        "description": "Revisa diffs buscando bugs, seguridad y desviaciones de convenciones. Use PROACTIVELY después de escribir o modificar código en bin/, lib/, web/ o tools/ y antes de commitear. Solo reporta.",
        "herramientas": LECTURA_SHELL,
        "claude": {"model": "opus", "effort": "high"},
        "antigravity": {"model": "pro"},
    },
    "security-auditor": {
        "description": "Auditoría de seguridad de backupctl: lo que corre con sudo o como root en un servidor, el manejo de credenciales (MySQL, Restic, rclone, SSH), el escapado de lo que viaja por ssh o llega a mysql, la web local (web/server.py) y lo que se escribe en HestiaCP. Use PROACTIVELY antes de dar por lista una versión que el PO vaya a desplegar, y siempre que cambien lib/deploy.sh, remote.sh, ssh.sh, sshkey.sh, shield.sh, adoptar.sh, hestia.sh, restic.sh, setup.sh o web/server.py.",
        "herramientas": LECTURA_SHELL_WEB,
        "claude": {"model": "opus", "effort": "xhigh"},
        "antigravity": {"model": "pro"},
    },
    "debugger": {
        "description": "Investiga un fallo concreto hasta su causa raíz, reproduciéndolo con datos sintéticos. Use cuando haya un error reportado o un comportamiento incorrecto, no para exploración general. No arregla.",
        "herramientas": LECTURA_SHELL,
        "claude": {"model": "opus", "effort": "high"},
        "antigravity": {"model": "pro"},
    },
    "test-writer": {
        "description": "Escribe pruebas sin servidor, sin MySQL real y sin HestiaCP (órdenes falsas delante en el PATH, perfiles sintéticos, temporales) para código ya implementado y las corre. Use PROACTIVELY después de implementar una función o un fix que no tenga prueba.",
        "herramientas": ESCRITURA_SHELL,
        "claude": {"model": "sonnet", "effort": "medium"},
        "antigravity": {"model": "flash"},
    },
    "doc-writer": {
        "description": "Escribe y actualiza documentación para personas y para agentes. Use PROACTIVELY después de un cambio que deja README.md, docs/ (sitio MkDocs), CHANGELOG.md o .agents/context/ desactualizado.",
        "herramientas": ESCRITURA_DOCS,
        "claude": {"model": "sonnet", "effort": "medium"},
        "antigravity": {"model": "flash"},
    },
    "context-curator": {
        "description": "Audita la documentación contra el código: detecta lo falso, lo muerto y lo podable (context, roadmap, estado/tramos, HERENCIA). Use PROACTIVELY al cerrar un tramo o cuando un cambio de código haya movido rutas o funciones. Solo propone.",
        "herramientas": LECTURA_SHELL,
        "claude": {"model": "sonnet", "effort": "medium"},
        "antigravity": {"model": "flash"},
    },
    "hestia-verifier": {
        "description": "Verifica afirmaciones sobre HestiaCP (comandos v-*, sus argumentos y salida json, rutas como /usr/local/hestia/conf/, respaldos del panel, Restic por usuario, cron del panel) contra su código fuente en la etiqueta de la versión objetivo. Use PROACTIVELY antes de dictar o escribir código que dependa de un comportamiento de HestiaCP no citado en .agents/context/50-hestiacp.md.",
        "herramientas": LECTURA_WEB,
        "claude": {"model": "sonnet", "effort": "high"},
        "antigravity": {"model": "flash"},
    },
}


def yaml_texto(valor):
    # Las descripciones llevan ": " y eso rompe un escalar YAML sin comillas.
    # Una cadena JSON es un escalar YAML válido entre comillas dobles.
    return json.dumps(valor, ensure_ascii=False)


def frontmatter_claude(nombre, cfg):
    lineas = [
        "---",
        f"name: {nombre}",
        f"description: {yaml_texto(cfg['description'])}",
        f"tools: {', '.join(cfg['herramientas']['claude'])}",
        f"model: {cfg['claude']['model']}",
        f"effort: {cfg['claude']['effort']}",
        "---",
    ]
    return "\n".join(lineas) + "\n\n"


def frontmatter_antigravity(nombre, cfg):
    herramientas = "\n".join(f"  - {h}" for h in cfg["herramientas"]["antigravity"])
    lineas = [
        "---",
        f"name: {nombre}",
        f"description: {yaml_texto(cfg['description'])}",
        f"tools:\n{herramientas}",
        "subagent: true",
        "mainAgent: false",
        f"model: {cfg['antigravity']['model']}",
        "commandExecutionPolicy: sandbox",
        "---",
    ]
    return "\n".join(lineas) + "\n\n"


def esperados():
    """Devuelve {ruta: contenido} de todo lo que debe existir generado."""
    comun = COMUN.read_text(encoding="utf-8")
    salida = {}
    for nombre, cfg in AGENTES.items():
        if cfg["claude"]["model"] == "fable":
            raise SystemExit(f"{nombre}: fable está vetado por el PO")
        cuerpo = (PERSONAS / f"{nombre}.md").read_text(encoding="utf-8").rstrip("\n") + "\n" + comun
        salida[SALIDA_CLAUDE / f"{nombre}.md"] = frontmatter_claude(nombre, cfg) + AVISO + cuerpo
        salida[SALIDA_ANTIGRAVITY / f"{nombre}.md"] = frontmatter_antigravity(nombre, cfg) + AVISO + cuerpo
    return salida


def personas_sin_config():
    """Personas que existen en disco pero no están en AGENTES: se olvidarían en silencio."""
    return sorted(
        p.stem for p in PERSONAS.glob("*.md") if not p.name.startswith("_") and p.stem not in AGENTES
    )


def sobrantes(esperado):
    """Archivos generados que ya no corresponden a ningún agente."""
    actuales = set(SALIDA_CLAUDE.glob("*.md")) | set(SALIDA_ANTIGRAVITY.glob("*.md"))
    return sorted(str(p.relative_to(RAIZ)) for p in actuales - set(esperado))


def main():
    comprobar = "--check" in sys.argv[1:]
    esperado = esperados()
    problemas = [f"persona sin configurar en AGENTES: {n}" for n in personas_sin_config()]

    if comprobar:
        for ruta, contenido in esperado.items():
            if not ruta.exists() or ruta.read_text(encoding="utf-8") != contenido:
                problemas.append(f"desfasado: {ruta.relative_to(RAIZ)}")
        problemas += [f"sobrante: {r}" for r in sobrantes(esperado)]
        for p in problemas:
            print(p)
        if problemas:
            print("Regenera con: python3 .agents/scripts/generar_agentes.py")
            return 1
        print(f"agentes al día: {len(AGENTES)}")
        return 0

    SALIDA_CLAUDE.mkdir(parents=True, exist_ok=True)
    SALIDA_ANTIGRAVITY.mkdir(parents=True, exist_ok=True)
    for ruta, contenido in esperado.items():
        ruta.write_text(contenido, encoding="utf-8")
        print(f"generado: {ruta.relative_to(RAIZ)}")
    for r in sobrantes(esperado):
        print(f"AVISO sobrante, bórralo a mano si ya no se usa: {r}")
    for p in problemas:
        print(f"AVISO {p}")
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
