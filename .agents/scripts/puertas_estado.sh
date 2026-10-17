#!/bin/bash
# Puertas del estado versionado (skill `cerrar-jornada` §4).
#
# Un ritual que se cumple porque alguien se acuerda es un ritual que un día no se
# cumple. Esto comprueba por máquina lo que antes se miraba a mano.
#
# No conecta a nada ni lee credenciales: solo cuenta líneas y busca secciones.
#
# Uso: bash .agents/scripts/puertas_estado.sh [RAIZ]
#      RAIZ por omisión: la raíz del repositorio.
#
# Sale con 1 si alguna puerta falla. Su prueba de rechazo, en las dos
# direcciones: .agents/scripts/probar_puertas_estado.sh

set -u

RAIZ="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AHORA="$RAIZ/estado/AHORA.md"
TRAMOS="$RAIZ/estado/tramos"

TOPE_LINEAS=200
MAX_TRAMOS=10

fallos=0
fallo() { printf 'FALLO: %s\n' "$1"; fallos=$((fallos + 1)); }

# --- Puerta 0: el archivo existe -------------------------------------------
# Sin él no hay estado, y las demás puertas no significarían nada.
if [ ! -f "$AHORA" ]; then
    fallo "no existe estado/AHORA.md: sin él, una sesión nueva empieza a ciegas"
    exit 1
fi

# --- Puerta 1: el tope de líneas -------------------------------------------
# Un archivo que una sesión nueva no lee entero no es estado, es archivo.
lineas=$(wc -l < "$AHORA")
if [ "$lineas" -gt "$TOPE_LINEAS" ]; then
    fallo "estado/AHORA.md tiene $lineas líneas, por encima del tope de $TOPE_LINEAS: poda, no subas el tope"
else
    echo "ok: estado/AHORA.md, $lineas líneas (tope $TOPE_LINEAS)"
fi

# --- Puerta 2: un solo bloque «al retomar» ---------------------------------
# Dos bloques de arranque significa que uno de los dos está rancio.
retomar=$(grep -ciE '^#{1,3} +al retomar' "$AHORA" || true)
if [ "$retomar" -eq 1 ]; then
    echo "ok: un solo bloque «al retomar»"
elif [ "$retomar" -eq 0 ]; then
    fallo "estado/AHORA.md no tiene ningún bloque «al retomar»: es lo primero que lee una sesión nueva"
else
    fallo "estado/AHORA.md tiene $retomar bloques «al retomar»: sobra uno, y el rancio se lee como verdad"
fi

# --- Puerta 3: los dos contadores, declarados ------------------------------
# No se puede comprobar por máquina que el número sea el correcto; sí que esté
# declarado y con su forma. Un contador ausente se pierde en la primera
# compactación, y es el dato que más se pierde.
if ! grep -qiE '^#{1,3} +.*contador' "$AHORA"; then
    fallo "estado/AHORA.md no tiene sección de contadores (regla 30)"
else
    antes="$fallos"
    grep -qE '#[0-9]{3,}' "$AHORA" \
        || fallo "estado/AHORA.md no declara el contador #NNN de la cadena con el coder"
    grep -qE '\bA-[0-9]{3,}' "$AHORA" \
        || fallo "estado/AHORA.md no declara el contador A-NNN de los mensajes al PO"
    [ "$fallos" -eq "$antes" ] && echo "ok: los dos contadores declarados"
fi

# --- Puerta 4: el contador no se queda atrás -------------------------------
# La puerta 3 comprueba que el contador está declarado, no que acierte. Esto
# compara lo declarado con lo que registran los tramos, que es la única fuente
# independiente que hay.
#
# Por qué existe: AHORA.md declaró «último usado #081» desde el 2026-09-24,
# mientras estado/tramos/2026-09-23-2300-fases-1-y-2.md registraba rondas hasta
# el #097. Los dos documentos se contradijeron durante casi un mes y nadie lo
# vio. Una sesión nueva que se fíe del número bajo reutiliza números ya usados,
# y entonces «el mensaje #083» deja de identificar un mensaje.
#
# Solo se lee de AHORA.md el patrón «Último usado: **#NNN**», no todos sus
# números: el propio archivo cita números viejos al explicar la reparación.
declarado=$(grep -oE 'Último usado: \*\*#[0-9]+\*\*' "$AHORA" | head -1 | grep -oE '[0-9]+')
if [ -z "$declarado" ]; then
    fallo "estado/AHORA.md no declara cuál fue el último #NNN usado (se busca «Último usado: **#NNN**»): sin ese dato una sesión nueva no sabe por qué número seguir"
else
    mayor=""
    mayor_archivo=""
    if [ -d "$TRAMOS" ]; then
        while IFS= read -r archivo; do
            n=$(grep -ohE '#[0-9]{3,}' "$archivo" | tr -d '#' | sed 's/^0*//' | sort -n | tail -1)
            [ -n "$n" ] || continue
            if [ -z "$mayor" ] || [ "$n" -gt "$mayor" ]; then
                mayor="$n"
                mayor_archivo="$archivo"
            fi
        done < <(find "$TRAMOS" -maxdepth 1 -type f -name '*.md' | sort)
    fi

    declarado_n=$(printf '%s' "$declarado" | sed 's/^0*//')
    : "${declarado_n:=0}"

    if [ -z "$mayor" ]; then
        echo "ok: AHORA.md declara #$declarado; no hay ningún #NNN en los tramos con el que contrastarlo"
    elif [ "$mayor" -gt "$declarado_n" ]; then
        fallo "el contador se quedó atrás: estado/AHORA.md declara #$declarado como último usado, pero $(basename "$mayor_archivo") registra #$mayor. Una sesión nueva seguirá por #$((declarado_n + 1)) y reutilizará números ya usados: a partir de ahí, citar «el mensaje #NNN» deja de identificar un mensaje. Corrige AHORA.md, no el tramo"
    else
        echo "ok: el contador no se quedó atrás (AHORA.md #$declarado, mayor en los tramos #$mayor)"
    fi
fi

# --- Puerta 5: los tramos, podados -----------------------------------------
# Regla 60: se conservan los 10 más recientes. Documentación muerta la lee un
# agente como verdad.
if [ -d "$TRAMOS" ]; then
    n=$(find "$TRAMOS" -maxdepth 1 -type f -name '*.md' | wc -l)
    if [ "$n" -gt "$MAX_TRAMOS" ]; then
        fallo "estado/tramos/ tiene $n archivos, por encima de $MAX_TRAMOS: poda los más viejos cuyo contenido ya esté en la bitácora, un ADR o el CHANGELOG"
    else
        echo "ok: estado/tramos/, $n archivos (máximo $MAX_TRAMOS)"
    fi
else
    echo "ok: no hay estado/tramos/ todavía"
fi

exit $([ "$fallos" -eq 0 ] && echo 0 || echo 1)
