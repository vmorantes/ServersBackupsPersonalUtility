#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_almacen.sh — el acceso al almacenamiento
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Todo va por el falso del banco (ADR 0009), y
# todas las credenciales de estas pruebas son inventadas.
#
# Este es el paso que escribe credenciales, y el que ya mordió una vez: el
# archivo podía quedar VACÍO mientras la orden decía «escrito». Un servidor con
# ese archivo vacío no sabe llegar a ningún almacenamiento y sus respaldos de
# esa noche no se hacen, sin que nadie lo sepa.
#
# Tres cosas se vigilan por encima del resto:
#   1. Que un archivo vacío tras escribir sea un FALLO ruidoso.
#   2. Que no se pise un remoto que ya existe sin decirlo, y que con --yes ni
#      siquiera se intente.
#   3. Que NINGUNA credencial salga por pantalla ni acabe en el informe.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_almacen.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_almacen =="

if [[ -d /usr/local/hestia ]]; then
  echo "probar_hestia_almacen.sh: existe /usr/local/hestia en esta máquina; se aborta." >&2
  exit 2
fi

HESTIA_FALSO="/usr/local/hestia"
CLAVE_SINTETICA='Zx9-secreto-sintetico-de-prueba'
ID_SINTETICO='AKIA-SINTETICO-DE-PRUEBA'

# Lo que devuelve la lectura de secciones y tipos, en cada momento.
vacio()        { printf ''; }
solo_almacen() { printf '[almacen]\ntype = s3\n'; }
dos_remotos()  { printf '[almacen]\ntype = s3\n[disco]\ntype = local\n'; }
solo_disco()   { printf '[disco]\ntype = local\n'; }

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

  *"command -v rclone"*|*"rclone version"*) printf 'BC_SI\n'; exit 0 ;;

  *"cp -p"*) printf 'BC_COPIA_OK\n'; exit 0 ;;

  # La escritura: marca cuál es el estado siguiente del archivo.
  *umask*|*"awk -v n="*)
    cat "$BANCO_TMP/despues" > "$BANCO_TMP/estado-archivo"
    exit "$(cat "$BANCO_TMP/codigo-escritura")" ;;

  # La lectura de secciones y tipos.
  *"grep -E"*type*)
    valor="$(cat "$BANCO_TMP/estado-archivo")"
    [[ "$valor" == "@ilegible" ]] && exit 1
    cat "$BANCO_TMP/$valor" 2>/dev/null
    printf 'BC_FIN\n'
    exit 0 ;;

  # ¿Responde el remoto?
  *"rclone lsd"*)
    if [[ "$(cat "$BANCO_TMP/responde")" == "si" ]]; then printf 'BC_SI\n'; else printf 'BC_NO\n'; fi
    exit 0 ;;
esac
echo "falso: ninguna respuesta prevista para: $llana" >&2
exit 95
FIN
}

# Prepara el caso.
# $1 caso  $2 archivo ANTES  $3 archivo DESPUÉS  $4 código de escritura
# $5 responde (si|no)
preparar() {
  local caso="$1" antes="$2" despues="$3" codigo="${4:-0}" responde="${5:-si}"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt"
  vacio        > "$BANCO_TMP/vacio"
  solo_almacen > "$BANCO_TMP/solo-almacen"
  dos_remotos  > "$BANCO_TMP/dos-remotos"
  solo_disco   > "$BANCO_TMP/solo-disco"
  printf '%s' "$antes"    > "$BANCO_TMP/estado-archivo"
  printf '%s' "$despues"  > "$BANCO_TMP/despues"
  printf '%s' "$codigo"   > "$BANCO_TMP/codigo-escritura"
  printf '%s' "$responde" > "$BANCO_TMP/responde"
  escribir_guion
}

configurar() {
  local caso="$1" nombre="$2" modo="${3:-}" si="${4:-1}"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/informe.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    HESTIA_DIR="$2"
    BC_HESTIA_RCLONE_CONF="/root/.config/rclone/rclone.conf"
    DEPLOY_HOST="servidor-sintetico"
    DEPLOY_USER="root"
    BC_PROFILE="Sintetico"
    BC_PROFILE_DIR="$3"
    BC_OPT_RC_NAME="$4"
    BC_OPT_RC_TYPE="s3"
    BC_OPT_RC_KEY="$6"
    BC_OPT_RC_SECRET="$7"
    BC_OPT_RC_ENDPOINT="https://s3.example.org"
    BC_ASSUME_YES="$8"
    BC_NO_COLOR=1
    [[ "$5" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_rclone
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$BANCO_TMP/$caso/perfil" "$nombre" "$modo" \
      "$ID_SINTETICO" "$CLAVE_SINTETICA" "$si" 2>&1
}

cuantas_escrituras() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo 0; return 0; }
  grep -c 'umask' "$BANCO_TMP/ordenes.txt" || true
}

informe_de() {
  find "$BANCO_TMP/$1/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- no había nada -----------------------------------------------------------
test_a_first_remote_is_written_and_confirmed() {
  nueva_prueba t1
  preparar t1 vacio solo-almacen 0 si
  local salida; salida="$(configurar t1 almacen)"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "comprobado leyendo la configuración" \
    "dice que lo comprobó, no solo que lo hizo"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "El remoto responde" "y que responde"

  local informe; informe="$(informe_de t1)"
  afirmar_contiene "$informe" "Remoto pedido" "el informe: qué se pidió"
  afirmar_contiene "$informe" "almacen s3" "el informe: los remotos que quedaron"
  afirmar_contiene "$informe" "Cómo deshacerlo" "el informe: cómo deshacerlo"
}

# --- LA TRAMPA QUE YA MORDIÓ: el archivo queda vacío -------------------------
test_an_empty_file_after_writing_is_a_loud_failure() {
  nueva_prueba t2
  # Se añade un remoto que NO existía: así la prueba mide lo que dice medir —el
  # archivo vacío tras escribir— y no se queda en la confirmación de sustituir.
  preparar t2 solo-almacen vacio 0 si
  local salida; salida="$(configurar t2 disco "" 1)"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "CODIGO:1" "no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "HA QUEDADO VACÍO" "y se dice a gritos"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "NO se harán" \
    "diciendo qué significa para esta noche"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "Recupéralo AHORA" "y cómo recuperarlo"
}

# --- pisar un remoto que ya existe -------------------------------------------
test_with_yes_it_refuses_to_replace_an_existing_remote() {
  nueva_prueba t3
  preparar t3 dos-remotos dos-remotos 0 si
  local salida; salida="$(configurar t3 almacen "" 1)"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_igual "$(cuantas_escrituras)" "0" "NINGUNA escritura enviada al servidor"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:1" "la orden se niega"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "YA EXISTE" "diciendo que ya existe"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "no pisa un remoto que ya existe" \
    "y por qué con --yes no se hace"
}

test_without_yes_it_names_the_remote_and_asks() {
  nueva_prueba t4
  preparar t4 dos-remotos dos-remotos 0 si
  local salida; salida="$(configurar t4 almacen "" 0)"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"

  afirmar_contiene "$BANCO_TMP/t4/salida.log" "El remoto 'almacen' YA EXISTE" \
    "se nombra el remoto que se sustituiría"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "solo estarán en la copia fechada" \
    "y qué pasa con sus credenciales"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "Cancelado" \
    "y sin un sí explícito no se escribe"
  afirmar_igual "$(cuantas_escrituras)" "0" "sin tocar nada"
}

# --- se pierde un remoto que estaba ------------------------------------------
test_a_lost_remote_is_a_failure() {
  nueva_prueba t5
  # Se añade un remoto nuevo y, al releer, «almacen» ha desaparecido.
  preparar t5 dos-remotos solo-disco 0 si
  local salida; salida="$(configurar t5 nuevo "" 1)"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:1" "no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "HAN DESAPARECIDO REMOTOS" "se avisa"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "almacen" "con el nombre del que falta"
}

# --- escrito pero no responde ------------------------------------------------
test_a_written_remote_that_does_not_answer_is_not_done() {
  nueva_prueba t6
  preparar t6 vacio solo-almacen 0 no
  local salida; salida="$(configurar t6 almacen)"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:1" \
    "un remoto que no responde no es una configuración buena"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "NO responde" "y se dice"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "los respaldos fallarán" "y qué significa"
}

# --- NINGUNA CREDENCIAL A LA VISTA -------------------------------------------
test_no_credential_reaches_the_screen_or_the_report() {
  nueva_prueba t7
  preparar t7 vacio solo-almacen 0 si
  local salida; salida="$(configurar t7 almacen)"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"

  afirmar_no_contiene "$BANCO_TMP/t7/salida.log" "$CLAVE_SINTETICA" \
    "el secreto NO aparece por pantalla"
  afirmar_no_contiene "$BANCO_TMP/t7/salida.log" "$ID_SINTETICO" "ni el identificador"

  local informe; informe="$(informe_de t7)"
  afirmar_igual "$([[ -n "$informe" ]] && echo si || echo no)" "si" "se guardó un informe"
  afirmar_no_contiene "$informe" "$CLAVE_SINTETICA" "el secreto NO aparece en el informe"
  afirmar_no_contiene "$informe" "$ID_SINTETICO" "ni el identificador"
  afirmar_contiene "$informe" "almacen" "pero sí el nombre del remoto, que no es secreto"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_writes_nothing() {
  nueva_prueba t8
  preparar t8 solo-disco solo-almacen 0 si
  local salida; salida="$(configurar t8 almacen ensayo)"
  echo "$salida" > "$BANCO_TMP/t8/salida.log"

  afirmar_contiene "$BANCO_TMP/t8/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "PASARÍA" "se ve que es una simulación"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "Se añadiría el remoto 'almacen'" "y el plan"
  afirmar_igual "$(cuantas_escrituras)" "0" "sin escribir nada"
  afirmar_igual "$([[ -n "$(informe_de t8)" ]] && echo si || echo no)" "no" \
    "ni archivar ningún informe"
}

# --- no se puede leer el estado de partida -----------------------------------
test_an_unreadable_before_writes_nothing() {
  nueva_prueba t9
  preparar t9 @ilegible solo-almacen 0 si
  local salida; salida="$(configurar t9 almacen)"
  echo "$salida" > "$BANCO_TMP/t9/salida.log"

  afirmar_igual "$(cuantas_escrituras)" "0" "no se escribe nada"
  afirmar_contiene "$BANCO_TMP/t9/salida.log" "CODIGO:1" "y se sale con error"
  afirmar_contiene "$BANCO_TMP/t9/salida.log" "podría dejar fuera alguno" "diciendo por qué"
}

test_a_first_remote_is_written_and_confirmed
test_an_empty_file_after_writing_is_a_loud_failure
test_with_yes_it_refuses_to_replace_an_existing_remote
test_without_yes_it_names_the_remote_and_asks
test_a_lost_remote_is_a_failure
test_a_written_remote_that_does_not_answer_is_not_done
test_no_credential_reaches_the_screen_or_the_report
test_a_dry_run_writes_nothing
test_an_unreadable_before_writes_nothing

fin_de_suite
