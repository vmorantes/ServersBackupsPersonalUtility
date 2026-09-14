#!/bin/bash
# Verificación del proyecto. La corre el coder antes de cada reporte.
# No conecta a nada, no ejecuta backupctl más allá de su ayuda, no toca nada
# fuera del repositorio ni lee los env.sh de los perfiles: solo comprueba
# sintaxis y coherencia. Sale con 1 si algo falla.
#
# Uso: bash .agents/scripts/verificar.sh

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ" || exit 1
# comprobar.py y la guarda importan módulos: que no reescriban ningún .pyc
# (web/__pycache__/ está versionado).
export PYTHONDONTWRITEBYTECODE=1

fallos=0
paso() { printf '\n== %s\n' "$1"; }
fallo() { printf 'FALLO: %s\n' "$1"; fallos=$((fallos + 1)); }

# Archivos del proyecto (versionados y nuevos no ignorados), sin los env.sh de
# los perfiles: son del PO y llevan credenciales.
listar() {
    git ls-files -z --cached --others --exclude-standard -- "$@" | tr '\0' '\n' |
        grep -Ev '(^|/)env\.sh$' | while read -r f; do [ -f "$f" ] && echo "$f"; done
}

paso "Sintaxis bash (bash -n)"
n=0
while read -r f; do
    [ -z "$f" ] && continue
    n=$((n + 1))
    bash -n "$f" || fallo "bash -n $f"
done < <({ echo bin/backupctl; listar '*.sh'; })
echo "scripts revisados: $n"

paso "Finales de línea LF en scripts (un CRLF rompe el shebang)"
crlf=$({ echo bin/backupctl; listar '*.sh' '*.py'; } | while read -r f; do grep -lq $'\r' "$f" && echo "$f"; done)
[ -z "$crlf" ] && echo "sin CRLF" || fallo "con CRLF: $crlf"

paso "Bit de ejecución de bin/backupctl en el índice"
modo=$(git ls-files -s bin/backupctl | awk '{print $1}')
[ "$modo" = "100755" ] && echo "100755" || fallo "bin/backupctl está como '$modo' (docs/desarrollo/repositorio.md)"

paso "Sintaxis Python"
n=0
while read -r f; do
    [ -z "$f" ] && continue
    n=$((n + 1))
    python3 -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$f" || fallo "python $f"
done < <(listar '*.py')
echo "scripts Python revisados: $n"

paso "Sintaxis JavaScript de la web"
if command -v node >/dev/null; then
    node --check web/app.js && echo "web/app.js correcto" || fallo "node --check web/app.js"
else
    echo "NO COMPROBADO: node no está instalado (instalarlo es decisión del PO)"
fi

paso "Coherencia de la interfaz web (web/comprobar.py)"
python3 -B web/comprobar.py || fallo "web/comprobar.py"

paso "La ayuda de backupctl arranca"
./bin/backupctl --help >/dev/null 2>&1 && echo "arranca" || fallo "bin/backupctl --help"

paso "Subagentes generados al día"
python3 .agents/scripts/generar_agentes.py --check || fallo "agentes desfasados"

paso "Puente de reglas y skills (.claude -> .agents)"
for enlace in .claude/rules/* .claude/skills/*; do
    if [ ! -L "$enlace" ]; then
        fallo "$enlace no es un symlink (se materializó como copia)"
    elif [ ! -e "$enlace" ]; then
        fallo "$enlace apunta a algo que no existe"
    fi
done
for regla in .agents/rules/*.md; do
    [ -L ".claude/rules/$(basename "$regla")" ] || fallo "falta el symlink .claude/rules/$(basename "$regla")"
done
for skill in .agents/skills/*/; do
    [ -L ".claude/skills/$(basename "$skill")" ] || fallo "falta el symlink .claude/skills/$(basename "$skill")"
done
modos=$(git ls-files -s .claude/rules .claude/skills | awk '$1 != "120000" {print $4}')
[ -z "$modos" ] || fallo "en el índice sin modo 120000: $modos"
echo "enlaces revisados: $(find .claude/rules .claude/skills -mindepth 1 -maxdepth 1 | wc -l)"

paso "Guarda de hooks"
python3 .agents/scripts/guardas/probar_guardia.py || fallo "la guarda no se comporta como se espera"

paso "Menciones a IA en entregables y commits posteriores a la adopción"
python3 .agents/scripts/menciones_ia.py || fallo "hay menciones a IA"

paso "Pruebas del proyecto"
if [ -f tests/ejecutar.sh ]; then
    bash tests/ejecutar.sh || fallo "tests/ejecutar.sh"
else
    echo "NO HAY: no existe banco de pruebas todavía (roadmap)"
fi

printf '\n'
if [ "$fallos" -eq 0 ]; then
    echo "VERIFICACIÓN OK"
else
    echo "VERIFICACIÓN FALLIDA: $fallos fallo(s)"
    exit 1
fi
