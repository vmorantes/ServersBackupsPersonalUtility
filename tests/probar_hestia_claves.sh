#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_claves.sh — rescatar las claves, y saber si cambiaron
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Todo va por el falso del banco (ADR 0009), y
# todas las claves de estas pruebas son inventadas.
#
# Dos cosas se vigilan por encima de todo:
#
#   1. Que una clave CAMBIADA se detecte. Cuando el panel no encuentra la
#      contraseña de una cuenta genera una nueva, y la nueva NO abre las copias
#      hechas con la anterior. Pasar eso por alto es perder respaldos sin que
#      nadie se entere.
#   2. Que NINGUNA clave salga por pantalla ni acabe en el informe. El informe
#      va al directorio del perfil, que está versionado.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_claves.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_claves =="

if [[ -d /usr/local/hestia ]]; then
  echo "probar_hestia_claves.sh: existe /usr/local/hestia en esta máquina; se aborta." >&2
  exit 2
fi

HESTIA_FALSO="/usr/local/hestia"

# Claves sintéticas, reconocibles a propósito: si alguna aparece en la salida o
# en el informe, se ve a la legua.
CLAVE_UNO='Zx9-clave-sintetica-de-cliente07'
CLAVE_UNO_NUEVA='Qw2-clave-sintetica-CAMBIADA-07'
CLAVE_DOS='Rt4-clave-sintetica-de-cliente08'

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

  *"find "*"-name restic.conf"*)
    cat "$BANCO_TMP/lista-conf"; exit 0 ;;

  *"v-list-users"*) cat "$BANCO_TMP/lista-usuarios"; exit 0 ;;

  *"cat "*data/users/*/restic.conf*)
    cuenta="${llana#*data/users/}"; cuenta="${cuenta%%/*}"
    cat "$BANCO_TMP/clave-$cuenta" 2>/dev/null
    exit 0 ;;

  *"cat "*conf/restic.conf*)
    cat "$BANCO_TMP/conf-global"; exit 0 ;;

  *"cat "*rclone.conf*)
    printf '[almacen]\ntype = s3\n'; exit 0 ;;

  *BC_SI*|*rclone\ lsf*|*"test -f"*|*"test -d"*)
    # Sondas: la respuesta la decide $BANCO_TMP/repo-<cuenta>
    cuenta=""
    case "$llana" in *"/IncrementalBackups/"*)
      cuenta="${llana#*/IncrementalBackups/}"; cuenta="${cuenta%%/*}" ;;
    esac
    if [[ "$(cat "$BANCO_TMP/repo-$cuenta" 2>/dev/null || echo no)" == "si" ]]; then
      printf 'BC_SI\n'
    else
      printf 'BC_NO\n'
    fi
    exit 0 ;;
esac
echo "falso: ninguna respuesta prevista para: $llana" >&2
exit 95
FIN
}

# Prepara el caso: qué cuentas hay, qué clave tiene cada una y cuáles tienen
# repositorio.
preparar() {
  local caso="$1"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil/output/HestiaCP" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt" "$BANCO_TMP"/clave-* "$BANCO_TMP"/repo-*
  printf "REPO='rclone:almacen:/IncrementalBackups'\nSNAPSHOTS='30'\n" > "$BANCO_TMP/conf-global"
  : > "$BANCO_TMP/lista-conf"
  : > "$BANCO_TMP/lista-usuarios"
  escribir_guion
}

# Da de alta una cuenta con su clave (o sin ella) y si tiene repositorio.
# $1 cuenta   $2 clave ('' = no tiene)   $3 repositorio (si|no)
cuenta_con() {
  local u="$1" clave="$2" repo="$3"
  printf '%s\n' "$u" >> "$BANCO_TMP/lista-usuarios"
  printf '%s' "$repo" > "$BANCO_TMP/repo-$u"
  if [[ -n "$clave" ]]; then
    printf '%s\n' "$clave" > "$BANCO_TMP/clave-$u"
    printf '%s\n' "$HESTIA_FALSO/data/users/$u/restic.conf" >> "$BANCO_TMP/lista-conf"
  fi
}

rescatar() {
  local caso="$1" modo="${2:-}"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/informe.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    HESTIA_DIR="$2"
    HESTIA_OUTPUT_DIR="$3/output/HestiaCP"
    DEPLOY_HOST="servidor-sintetico"
    DEPLOY_USER="root"
    BC_PROFILE="Sintetico"
    BC_PROFILE_DIR="$3"
    BC_VERSION="pruebas"
    RESTIC_RETENTION_DAYS=90
    BC_ASSUME_YES=1
    BC_NO_COLOR=1
    [[ "$4" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_keys
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$BANCO_TMP/$caso/perfil" "$modo" 2>&1
}

rescates_de() {
  find "$BANCO_TMP/$1/perfil/output/HestiaCP" -name 'Restic_Configs_*.txt' 2>/dev/null | sort
}

informe_de() {
  find "$BANCO_TMP/$1/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- primer rescate ----------------------------------------------------------
# --- la huella: qué cuenta como cambio y qué no ------------------------------
#
# Un falso «LA CONTRASEÑA HA CAMBIADO» es caro porque asusta con lo que más
# asusta. Pero normalizar de más es peor: escondería un cambio de verdad.

huella_de() {
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    printf "[%s]" "$(bc_hestia_huella "$2")"
  ' _ "$BANCO_RAIZ" "$1" 2>&1
}

test_trailing_whitespace_is_not_a_change() {
  nueva_prueba t8
  local base; base="$(huella_de "$CLAVE_UNO")"
  afirmar_igual "$(huella_de "$CLAVE_UNO
")" "$base" "un salto de línea al final no es un cambio"
  afirmar_igual "$(huella_de "$CLAVE_UNO   ")" "$base" "ni unos espacios al final"
}

test_anything_else_is_a_change() {
  nueva_prueba t9
  local base; base="$(huella_de "$CLAVE_UNO")"
  local espacio_delante; espacio_delante="$(huella_de " $CLAVE_UNO")"
  local otra;            otra="$(huella_de "$CLAVE_UNO_NUEVA")"
  afirmar_igual "$([[ "$espacio_delante" == "$base" ]] && echo igual || echo distinta)" \
    "distinta" "un espacio DELANTE sí es un cambio: no se normaliza de más"
  afirmar_igual "$([[ "$otra" == "$base" ]] && echo igual || echo distinta)" \
    "distinta" "y otra clave, por supuesto"
}

test_a_first_rescue_has_nothing_to_compare_with() {
  nueva_prueba t1
  preparar t1
  cuenta_con cliente07 "$CLAVE_UNO" si
  local salida; salida="$(rescatar t1)"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "este es el primero" \
    "se dice que no hay con qué comparar"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "No había rescate anterior de esta cuenta" \
    "y por cuenta también"
  afirmar_igual "$(rescates_de t1 | grep -c .)" "1" "queda un archivo de rescate"
}

# --- segundo rescate, claves iguales -----------------------------------------
test_a_second_rescue_with_the_same_keys_says_so() {
  nueva_prueba t2
  preparar t2
  cuenta_con cliente07 "$CLAVE_UNO" si
  rescatar t2 >/dev/null
  # El nombre del rescate lleva la hora: se espera un segundo para que el
  # segundo archivo no pueda coincidir con el primero.
  sleep 1
  local salida; salida="$(rescatar t2)"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "la misma clave que en el rescate anterior" \
    "se confirma que lo guardado sigue sirviendo"
  afirmar_igual "$(rescates_de t2 | grep -c .)" "2" \
    "y el rescate anterior NO se ha sobrescrito: hay dos archivos"
}

# --- LA PRUEBA DE LA RONDA: una clave cambió ---------------------------------
test_a_changed_key_is_a_named_serious_warning() {
  nueva_prueba t3
  preparar t3
  cuenta_con cliente07 "$CLAVE_UNO" si
  rescatar t3 >/dev/null
  sleep 1
  # El panel ha generado una contraseña nueva para esa cuenta.
  printf '%s\n' "$CLAVE_UNO_NUEVA" > "$BANCO_TMP/clave-cliente07"
  local salida; salida="$(rescatar t3)"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:1" "no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "cliente07: LA CONTRASEÑA HA CAMBIADO" \
    "se dice con nombre y apellidos"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "NO se abren con" \
    "y qué copias dejan de abrirse"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "No borres" \
    "y que no se borre el rescate anterior"
  afirmar_igual "$(rescates_de t3 | grep -c .)" "2" "los dos rescates siguen ahí"
}

# --- cuenta con copias y sin clave -------------------------------------------
test_an_account_with_backups_and_no_key_is_a_named_failure() {
  nueva_prueba t4
  preparar t4
  cuenta_con cliente07 "$CLAVE_UNO" si
  cuenta_con cliente08 "" si          # tiene repositorio y NO tiene clave
  local salida; salida="$(rescatar t4)"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"

  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" "no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "TIENEN COPIAS Y NO SE HA RESCATADO SU CLAVE" \
    "se avisa"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "cliente08" "con el nombre de la cuenta"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "no las abrirá nadie" "y qué significa"
}

# Una cuenta SIN copias y sin clave no es un problema: todavía no ha respaldado.
test_an_account_without_backups_and_no_key_is_not_a_problem() {
  nueva_prueba t5
  preparar t5
  cuenta_con cliente07 "$CLAVE_UNO" si
  cuenta_con cliente09 "" no
  local salida; salida="$(rescatar t5)"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:0" "termina bien"
  afirmar_no_contiene "$BANCO_TMP/t5/salida.log" "cliente09" \
    "una cuenta sin copias y sin clave no se nombra como problema"
}

# --- NINGUNA CLAVE A LA VISTA ------------------------------------------------
#
# El informe va al directorio del perfil, que está versionado. Una clave ahí es
# una clave publicada.
test_no_key_ever_reaches_the_screen_or_the_report() {
  nueva_prueba t6
  preparar t6
  cuenta_con cliente07 "$CLAVE_UNO" si
  cuenta_con cliente08 "$CLAVE_DOS" si
  local salida; salida="$(rescatar t6)"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_no_contiene "$BANCO_TMP/t6/salida.log" "$CLAVE_UNO" \
    "la clave NO aparece por pantalla"
  afirmar_no_contiene "$BANCO_TMP/t6/salida.log" "$CLAVE_DOS" \
    "ni la de la otra cuenta"

  local informe; informe="$(informe_de t6)"
  afirmar_igual "$([[ -n "$informe" ]] && echo si || echo no)" "si" "se guardó un informe"
  afirmar_no_contiene "$informe" "$CLAVE_UNO" "la clave NO aparece en el informe"
  afirmar_no_contiene "$informe" "$CLAVE_DOS" "ni la de la otra cuenta"
  afirmar_contiene "$informe" "Clave de cliente07" "pero sí consta que se rescató"

  # Y donde SÍ tiene que estar, está: en el archivo de rescate, que para eso es.
  afirmar_contiene "$(rescates_de t6 | sed -n '1p')" "$CLAVE_UNO" \
    "la clave sí está en el archivo de rescate, que es su sitio"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_writes_nothing() {
  nueva_prueba t7
  preparar t7
  cuenta_con cliente07 "$CLAVE_UNO" si
  local salida; salida="$(rescatar t7 ensayo)"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"

  afirmar_contiene "$BANCO_TMP/t7/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "PASARÍA" "se ve que es una simulación"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "Se rescatarían las claves de 1" \
    "y se ve qué se rescataría"
  afirmar_igual "$(rescates_de t7 | grep -c .)" "0" "no se escribe ningún rescate"
  afirmar_igual "$([[ -n "$(informe_de t7)" ]] && echo si || echo no)" "no" \
    "ni se archiva ningún informe"
}

test_trailing_whitespace_is_not_a_change
test_anything_else_is_a_change
test_a_first_rescue_has_nothing_to_compare_with
test_a_second_rescue_with_the_same_keys_says_so
test_a_changed_key_is_a_named_serious_warning
test_an_account_with_backups_and_no_key_is_a_named_failure
test_an_account_without_backups_and_no_key_is_not_a_problem
test_no_key_ever_reaches_the_screen_or_the_report
test_a_dry_run_writes_nothing

fin_de_suite
