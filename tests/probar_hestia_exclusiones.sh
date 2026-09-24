#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_exclusiones.sh — qué se queda fuera del respaldo
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Todo va por el falso del banco (ADR 0009).
#
# Lo que más se vigila es un NO: un valor con una comilla, un punto y coma, un
# dólar o un espacio NO se escribe, y no se escribe NADA. Ese archivo lo carga
# HestiaCP con `source`: es bash que se ejecuta con los privilegios del
# respaldo la noche siguiente. Un valor mal validado ahí no es un dato feo, es
# una orden que corre en el servidor.
#
# Y lo segundo: que un '*' no se enseñe como un valor más. Significa que esa
# parte entera queda fuera de la copia, y quien lo lea tiene que entenderlo sin
# saber qué es un archivo de configuración.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_exclusiones.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_exclusiones =="

if [[ -d /usr/local/hestia ]]; then
  echo "probar_hestia_exclusiones.sh: existe /usr/local/hestia en esta máquina; se aborta." >&2
  exit 2
fi

HESTIA_FALSO="/usr/local/hestia"

# Archivos de exclusiones sintéticos.
sin_nada()      { printf ''; }
con_bases()     { printf "DB='tienda,blog'\n"; }
con_asterisco() { printf "DB='*'\n"; }
con_rara()      { printf "DB='tienda'\nUDIR='algo'\nLO_QUE_SEA='x'\n"; }

escribir_guion() {
  cat > "$BANCO_TMP/guion/ssh.sh" <<'FIN'
orden="${!#}"
llana="${orden//\\/}"
case "$llana" in
  *"id -u"*) exit 0 ;;
  "true")    exit 0 ;;
esac
printf '%s\n' "$llana" >> "$BANCO_TMP/ordenes.txt"

case "$llana" in
  *"test -d"*"/usr/local/hestia"*) exit 0 ;;

  *"v-list-users"*) cat "$BANCO_TMP/lista-usuarios"; exit 0 ;;

  *"cp -p"*) printf 'BC_COPIA_OK\n'; exit 0 ;;

  # La escritura: lo que llega por la entrada estándar pasa a ser el archivo.
  *"cat > "*backup-excludes.conf*)
    cat > "$BANCO_TMP/escrito"
    printf 'escrito' > "$BANCO_TMP/estado"
    exit "$(cat "$BANCO_TMP/codigo-escritura")" ;;

  *"cat "*backup-excludes.conf*)
    # El centinela va antes de TODO, como lo pone el envoltorio de verdad, y
    # solo se salta cuando se simula que la lectura no llegó a ocurrir. Estaba
    # dentro de una de las dos ramas, así que la relectura de después de
    # escribir no lo llevaba y parecía una lectura imposible.
    valor="$(cat "$BANCO_TMP/archivo")"
    [[ "$(cat "$BANCO_TMP/estado")" != "escrito" && "$valor" == "@ilegible" ]] && exit 1
    printf 'BC_INI\n'
    if [[ "$(cat "$BANCO_TMP/estado")" == "escrito" ]]; then
      cat "$BANCO_TMP/escrito"
    else
      cat "$BANCO_TMP/$valor"
    fi
    exit 0 ;;
esac
echo "falso: ninguna respuesta prevista para: $llana" >&2
exit 95
FIN
}

# $1 caso  $2 archivo de partida  $3 código de la escritura
preparar() {
  local caso="$1" archivo="$2" codigo="${3:-0}"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt" "$BANCO_TMP/escrito"
  printf 'cliente07\n' > "$BANCO_TMP/lista-usuarios"
  printf '%s' "$archivo" > "$BANCO_TMP/archivo"
  printf 'sin-escribir' > "$BANCO_TMP/estado"
  printf '%s' "$codigo" > "$BANCO_TMP/codigo-escritura"
  sin_nada      > "$BANCO_TMP/sin-nada"
  con_bases     > "$BANCO_TMP/con-bases"
  con_asterisco > "$BANCO_TMP/con-asterisco"
  con_rara      > "$BANCO_TMP/con-rara"
  escribir_guion
}

exclusiones() {
  local caso="$1" excluir="${2:-}" modo="${3:-}"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/informe.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    HESTIA_DIR="$2"
    DEPLOY_HOST="servidor-sintetico"
    DEPLOY_USER="root"
    BC_PROFILE="Sintetico"
    BC_PROFILE_DIR="$3"
    BC_OPT_USERS="cliente07"
    BC_OPT_EXCLUIR="$4"
    BC_ASSUME_YES=1
    BC_NO_COLOR=1
    [[ "$5" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_exclusiones
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$BANCO_TMP/$caso/perfil" "$excluir" "$modo" 2>&1
}

cuantas_escrituras() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo 0; return 0; }
  grep -c 'cat > ' "$BANCO_TMP/ordenes.txt" || true
}

informe_de() {
  find "$BANCO_TMP/$1/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- leer y mostrar ----------------------------------------------------------
test_nothing_excluded_says_everything_is_backed_up() {
  nueva_prueba t1
  preparar t1 sin-nada
  local salida; salida="$(exclusiones t1)"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "se respalda TODO" "lo dice en cristiano"
  afirmar_igual "$(cuantas_escrituras)" "0" "y no escribe nada"
}

test_excluded_items_are_shown_as_what_they_mean() {
  nueva_prueba t2
  preparar t2 con-bases
  local salida; salida="$(exclusiones t2)"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "NO se respaldan 2 de sus bases de datos" \
    "no se enseña la clave, se enseña lo que significa"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "tienda, blog" "con los nombres"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "LOS DOS respaldos" \
    "y que afecta al clásico y al incremental"
}

# --- LA SECCIÓN ENTERA FUERA -------------------------------------------------
test_an_asterisk_is_not_just_another_value() {
  nueva_prueba t3
  preparar t3 con-asterisco
  local salida; salida="$(exclusiones t3)"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_contiene "$BANCO_TMP/t3/salida.log" "NO se respalda NADA de sus bases de datos" \
    "un '\*' se dice como lo que es"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "esa parte entera queda fuera de la copia" \
    "y qué significa"
}

# --- LA PRUEBA DE LA RONDA: un valor peligroso -------------------------------
#
# Ese archivo se EJECUTA. Un valor con un ';' no es un dato feo: es una orden
# que corre en el servidor la noche siguiente.
test_a_dangerous_value_is_never_written() {
  nueva_prueba t4
  local malos=0 v
  for v in "tienda;id" "tienda'x" "tienda\$(id)" "tienda otra" "tienda
blog" ""; do
    preparar t4 con-bases
    exclusiones t4 "DB=$v" > "$BANCO_TMP/t4/salida-$malos.log" 2>&1
    [[ "$(cuantas_escrituras)" == "0" ]] || malos=$(( malos + 1 ))
  done
  afirmar_igual "$malos" "0" "ninguno de los seis valores peligrosos llegó a escribirse"

  preparar t4 con-bases
  local salida; salida="$(exclusiones t4 "DB=tienda;id")"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" "y la orden falla"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "NO se puede escribir ahí" "diciéndolo"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "como CÓDIGO" "y por qué: ese archivo se ejecuta"
}

# --- una clave que no conocemos ----------------------------------------------
test_an_unknown_key_stops_the_rewrite() {
  nueva_prueba t5
  preparar t5 con-rara
  local salida; salida="$(exclusiones t5 "DB=tienda,blog")"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_igual "$(cuantas_escrituras)" "0" "no se reescribe nada"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:1" "y se sale con error"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "claves que esta herramienta no conoce" "se dice"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "LO_QUE_SEA" "con el nombre de la clave"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "puso a propósito" "y por qué no se toca"
}

# --- escribir está DESACTIVADO a propósito -----------------------------------
#
# Las dos pruebas que había aquí —escribir una exclusión válida, y que una
# idéntica no se reescriba— comprobaban un camino que existe, está escrito y
# funciona, pero que hoy NO se ofrece: falta poder decir qué consigue de verdad
# cada exclusión en cada tipo de respaldo. Se quitan en vez de dejarlas rojas o
# de relajarlas, y en su lugar se comprueba lo único que hoy es cierto: que la
# orden se niega a escribir y explica por qué.
#
# Para volver a ponerlas: el código de escritura sigue en lib/hestia.sh, con su
# propio comentario de por qué está desactivado y qué falta para activarlo.
test_writing_is_refused_and_says_why() {
  nueva_prueba t6
  preparar t6 sin-nada
  local salida; salida="$(exclusiones t6 "DB=tienda,blog")"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_igual "$(cuantas_escrituras)" "0" "no se escribe nada"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:1" "y se sale con error"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "todavía no está disponible" "diciéndolo"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "NO impide que sus" \
    "y el motivo: en el incremental, excluir una web no saca sus archivos de la copia"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "una base de datos SÍ" \
    "y que con una base de datos es al revés"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_writes_nothing() {
  nueva_prueba t8
  preparar t8 sin-nada
  local salida; salida="$(exclusiones t8 "DB=tienda" ensayo)"
  echo "$salida" > "$BANCO_TMP/t8/salida.log"

  afirmar_contiene "$BANCO_TMP/t8/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "PASARÍA" "se ve que es una simulación"
  afirmar_igual "$(cuantas_escrituras)" "0" "sin escribir nada"
  afirmar_igual "$([[ -n "$(informe_de t8)" ]] && echo si || echo no)" "no" \
    "ni archivar ningún informe"
}

test_nothing_excluded_says_everything_is_backed_up
test_excluded_items_are_shown_as_what_they_mean
test_an_asterisk_is_not_just_another_value
test_a_dangerous_value_is_never_written
test_an_unknown_key_stops_the_rewrite
test_writing_is_refused_and_says_why
test_a_dry_run_writes_nothing

fin_de_suite
