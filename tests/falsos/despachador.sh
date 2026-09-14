#!/usr/bin/env bash
# =============================================================================
# tests/falsos/despachador.sh — orden falsa genérica (ADR 0009)
# =============================================================================
# Un enlace simbólico por orden peligrosa (ssh, mysql, mysqldump...) apunta
# aquí; tests/ejecutar.sh los crea en tiempo de ejecución. Registra la
# invocación y responde según el guion que la prueba haya dejado en
# $BANCO_TMP/guion/<orden>.sh.
#
# NUNCA lee la entrada estándar por su cuenta: backup llama a mysql/mysqldump
# dentro de un 'while read ... done <<<"$dbs"' (lib/backup.sh:353-357), y un
# falso que consumiera stdin se comería esa lista. Solo la lee el guion que
# la necesite explícitamente (el de mysql, para el SQL de restore).
#
# Sin guion, nunca inventa un éxito: falla con un mensaje claro.
# =============================================================================
set -u

if [[ -z "${BANCO_TMP:-}" || ! -d "$BANCO_TMP" ]]; then
  echo "falso $(basename "$0"): \$BANCO_TMP no está definido o no es un directorio; no se registra nada." >&2
  exit 96
fi

orden="$(basename "$0")"

mkdir -p "$BANCO_TMP/registro"
{ printf '%q ' "$orden" "$@"; echo; } >> "$BANCO_TMP/registro/$orden.log"

guion="$BANCO_TMP/guion/$orden.sh"
if [[ -f "$guion" ]]; then
  # shellcheck source=/dev/null
  source "$guion"
else
  echo "falso $orden: sin guion para: $*" >&2
  exit 97
fi
