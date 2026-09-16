"""
Patrones de mención a IA que no pueden aparecer en lo que se entrega
(regla 40-salvaguardas.md, sección 4). Compartido por la guarda de hooks
y por menciones_ia.py, para que los dos juzguen igual.
"""
import re

# Sin distinguir mayúsculas.
_INSENSIBLES = [
    r"co-authored-by",
    r"generated (with|by)",
    r"generad[oa] (con|por|mediante) (ia|ai|inteligencia artificial|un modelo|claude|chatgpt)",
    # "claude" como palabra, pero no las rutas .claude/ ni CLAUDE.md: la
    # documentación para personas puede señalar dónde vive la configuración.
    r"(?<![.\w/])claude(?!\w|\.md)",
    r"\banthropic\b",
    r"\bchatgpt\b",
    r"\bopenai\b",
    r"\bgpt-?[0-9]",
    r"\bcopilot\b",
    r"\bgemini\b",
    r"\bllm\b",
    # Nombres de los subagentes del proyecto: en un comentario de código dicen quién lo
    # escribió o revisó (regla 40 §4). Fuera de .agents/ y .claude/ no tienen sitio.
    r"\b(security-auditor|code-reviewer|hestia-verifier|test-writer|doc-writer|context-curator)\b",
    r"\bsubagentes?\b",
    r"inteligencia artificial",
    r"artificial intelligence",
    "\U0001F916",  # emoji de robot
]
# Distinguiendo mayúsculas: "IA"/"AI" como palabra suelta; en minúscula
# serían falsos positivos ("ia" dentro de otra palabra ya lo evita \b, pero
# "ai" aparece en abreviaturas legítimas).
_SENSIBLES = [r"\bIA\b", r"\bAI\b"]

PATRONES = [re.compile(p, re.IGNORECASE) for p in _INSENSIBLES] + [re.compile(p) for p in _SENSIBLES]

# Rutas entregables, relativas a la raíz. Fuera de ellas (.agents/, .claude/,
# AGENTS.md, estado/) hablar de agentes es el tema, no una firma. Los
# directorios de perfil son del PO y no se revisan.
PREFIJOS_ENTREGABLES = ("bin/", "lib/", "web/", "tools/", "config/", "docs/", "tests/")
ARCHIVOS_ENTREGABLES = ("README.md", "CHANGELOG.md", "UtilCommands.md", "mkdocs.yml", ".gitignore", ".gitattributes")

# Último commit anterior a la adopción del modelo arquitecto-coder (ADR 0001).
# 31 de los commits hasta aquí llevan una línea Co-Authored-By de un
# asistente; ya están en el remoto y reescribirlos es decisión del PO
# (roadmap). La comprobación de mensajes empieza después de este commit.
BASE_COMMITS = "4435064"


def es_entregable(ruta_relativa):
    ruta = ruta_relativa.replace("\\", "/")
    return ruta.startswith(PREFIJOS_ENTREGABLES) or ruta in ARCHIVOS_ENTREGABLES


def buscar(texto):
    """Devuelve [(número de línea, fragmento)] de cada coincidencia."""
    hallazgos = []
    for n, linea in enumerate(texto.splitlines(), 1):
        for patron in PATRONES:
            m = patron.search(linea)
            if m:
                hallazgos.append((n, m.group(0)))
                break
    return hallazgos
