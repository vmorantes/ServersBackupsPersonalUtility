#!/bin/bash
# Prueba de rechazo de las puertas del estado (ADR 0010: prueba de mutación).
#
# Una puerta que no se ha visto fallar no se ha visto funcionar. Aquí se
# construye un estado sintético válido, se comprueba que pasa, y luego se rompe
# de una forma cada vez, comprobando que cada rotura se detecta.
#
# Todo ocurre en un temporal propio: no toca el estado real del repositorio.
#
# Uso: bash .agents/scripts/probar_puertas_estado.sh

set -u

PUERTAS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/puertas_estado.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

afirmaciones=0
fallidas=0

ok()    { afirmaciones=$((afirmaciones + 1)); printf '  ok: %s\n' "$1"; }
mal()   { afirmaciones=$((afirmaciones + 1)); fallidas=$((fallidas + 1)); printf '  FALLO: %s\n' "$1"; }

# Construye un estado sintético en $TMP/<nombre> y devuelve su ruta.
construir() {
    local caso="$1" lineas="${2:-30}" retomar="${3:-1}" contadores="${4:-si}" tramos="${5:-3}"
    local raiz="$TMP/$caso"
    rm -rf "$raiz"
    mkdir -p "$raiz/estado/tramos"

    {
        echo "# Ahora"
        echo
        local i
        for ((i = 0; i < retomar; i++)); do
            echo "## Al retomar"
            echo
            echo "1. Un paso."
            echo
        done
        if [ "$contadores" = "si" ]; then
            echo "## 3. Contadores"
            echo
            echo "- El próximo: **#082**."
            echo "- El próximo: **A-001**."
            echo
        elif [ "$contadores" = "sin-po" ]; then
            echo "## 3. Contadores"
            echo
            echo "- El próximo: **#082**."
            echo
        fi
        # Relleno hasta la cantidad de líneas pedida.
        for ((i = 0; i < lineas; i++)); do echo "Relleno $i."; done
    } > "$raiz/estado/AHORA.md"

    for ((i = 0; i < tramos; i++)); do
        # Nombre único por tramo: con nombres repetidos la prueba nunca llegaba
        # a la cantidad pedida y el caso de «sin podar» pasaba en falso.
        printf '# Tramo %s\n' "$i" > "$(printf '%s/estado/tramos/2026-01-01-%04d-caso.md' "$raiz" "$i")"
    done

    echo "$raiz"
}

# Ejecuta las puertas sobre una raíz y dice si pasaron.
pasa() { bash "$PUERTAS" "$1" >/dev/null 2>&1; }

printf '\n== puertas del estado: el caso válido\n'
raiz="$(construir valido 30 1 si 3)"
if pasa "$raiz"; then ok "un estado bien formado pasa las puertas"
else mal "un estado bien formado DEBERÍA pasar, y no pasa"; bash "$PUERTAS" "$raiz"; fi

printf '\n== puertas del estado: cada rotura se detecta\n'

raiz="$(construir largo 400 1 si 3)"
if pasa "$raiz"; then mal "un AHORA.md de más de 200 líneas DEBERÍA fallar y pasó"
else ok "se rechaza un AHORA.md por encima del tope de líneas"; fi

raiz="$(construir dos-retomar 30 2 si 3)"
if pasa "$raiz"; then mal "dos bloques «al retomar» DEBERÍAN fallar y pasaron"
else ok "se rechazan dos bloques «al retomar»"; fi

raiz="$(construir sin-retomar 30 0 si 3)"
if pasa "$raiz"; then mal "ningún bloque «al retomar» DEBERÍA fallar y pasó"
else ok "se rechaza un AHORA.md sin bloque «al retomar»"; fi

raiz="$(construir sin-contadores 30 1 no 3)"
if pasa "$raiz"; then mal "sin sección de contadores DEBERÍA fallar y pasó"
else ok "se rechaza un AHORA.md sin sección de contadores"; fi

raiz="$(construir sin-contador-po 30 1 sin-po 3)"
if pasa "$raiz"; then mal "sin el contador A-NNN DEBERÍA fallar y pasó"
else ok "se rechaza un AHORA.md que declara #NNN pero no A-NNN"; fi

raiz="$(construir muchos-tramos 30 1 si 14)"
if pasa "$raiz"; then mal "14 tramos DEBERÍAN fallar y pasaron"
else ok "se rechazan más de 10 tramos sin podar"; fi

raiz="$TMP/sin-archivo"; mkdir -p "$raiz"
if pasa "$raiz"; then mal "la ausencia de AHORA.md DEBERÍA fallar y pasó"
else ok "se rechaza la ausencia de estado/AHORA.md"; fi

printf '\n-- %s afirmaciones, %s fallidas --\n' "$afirmaciones" "$fallidas"
[ "$fallidas" -eq 0 ] || exit 1
