#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_registro.sh — registrar el host de respaldo, de punta a
# punta
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Es el primer paso que ESCRIBE, así que lo que se
# prueba no es solo el resultado: es también QUÉ se le pidió al servidor y en
# qué orden. Todo va por el `ssh` falso del banco (ADR 0009), que apunta cada
# orden y responde lo que la prueba le deje escrito.
#
# Se usa un repositorio con RUTA LOCAL (/IncrementalBackups) a propósito: así
# no entran en juego las comprobaciones de rclone, que ya tienen sus propias
# pruebas, y queda a la vista lo de esta ronda — la copia fechada, la
# escritura, la relectura, el juicio y el informe.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_registro.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_registro =="

HESTIA_FALSO="/usr/local/hestia-sintetico"
CONF_FALSO="$HESTIA_FALSO/conf/restic.conf"
REPO_PEDIDO="/IncrementalBackups"

# El restic.conf que deja una configuración ya puesta con lo que se va a pedir.
conf_igual() {
  printf "REPO='%s'\nSNAPSHOTS='30'\nKEEP_DAILY='8'\nKEEP_WEEKLY='5'\nKEEP_MONTHLY='3'\nKEEP_YEARLY='-1'" \
    "$REPO_PEDIDO"
}
# Y uno con otra cosa.
conf_distinto() {
  printf "REPO='/OtraRuta'\nSNAPSHOTS='10'\nKEEP_DAILY='2'\nKEEP_WEEKLY='1'\nKEEP_MONTHLY='1'\nKEEP_YEARLY='-1'"
}

# El guion del `ssh` falso.
#
# Responde a cada cosa que la función pide, en el orden en que la pide:
#   - `id -u`            -> somos root (así la orden viaja sin prefijo sudo)
#   - `test -d`          -> el HestiaCP existe (bc_hestia_conectar)
#   - `true`             -> bc_ssh_init abre la conexión
#   - `cat` del conf     -> saca el siguiente valor de la cola de lecturas
#   - la copia fechada   -> según $BANCO_TMP/copia (ok|falla)
#   - la orden de alta   -> el código de $BANCO_TMP/codigo-escritura
#   - restic             -> según $BANCO_TMP/restic (si|no|ilegible)
escribir_guion_ssh() {
  cat > "$BANCO_TMP/guion/ssh.sh" <<FIN
orden="\${!#}"
llana="\${orden//\\\\/}"
case "\$llana" in
  *"id -u"*) exit 0 ;;
  "true")    exit 0 ;;
esac
printf '%s\\n' "\$llana" >> "\$BANCO_TMP/ordenes.txt"

case "\$llana" in
  *"test -d"*"hestia-sintetico"*) exit 0 ;;

  *"cp -p"*)
    if [[ "\$(cat "\$BANCO_TMP/copia")" == "falla" ]]; then exit 1; fi
    printf 'BC_COPIA_OK\\n'; exit 0 ;;

  *"cat "*"restic.conf"*)
    valor="\$(sed -n '1p' "\$BANCO_TMP/lecturas")"
    sed -i '1d' "\$BANCO_TMP/lecturas"
    [[ "\$valor" == "@ilegible" ]] && exit 1
    [[ "\$valor" == "@vacio" ]] || printf '%s\\n' "\$(cat "\$BANCO_TMP/\$valor")"
    printf 'BC_FIN\\n'
    exit 0 ;;

  *"v-add-backup-host-restic"*)
    exit "\$(cat "\$BANCO_TMP/codigo-escritura")" ;;

  *"restic version"*)
    case "\$(cat "\$BANCO_TMP/restic")" in
      si)       printf 'BC_SI\\n' ;;
      no)       printf 'BC_NO\\n' ;;
      *)        exit 1 ;;
    esac
    exit 0 ;;
esac
echo "falso ssh: ninguna respuesta prevista para: \$llana" >&2
exit 95
FIN
}

# Prepara y ejecuta el registro.
# $1 caso   $2 archivo con el conf ANTES (o @vacio/@ilegible)
# $3 el de DESPUÉS   $4 código de la orden   $5 copia (ok|falla)
# $6 restic (si|no|ilegible)   $7 extra: "ensayo" para --dry-run
registrar() {
  local caso="$1" antes="$2" despues="$3" codigo="$4" copia="$5" restic="$6" modo="${7:-}"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt"
  printf '%s\n%s\n' "$antes" "$despues" > "$BANCO_TMP/lecturas"
  printf '%s' "$codigo" > "$BANCO_TMP/codigo-escritura"
  printf '%s' "$copia"  > "$BANCO_TMP/copia"
  printf '%s' "$restic" > "$BANCO_TMP/restic"
  conf_igual    > "$BANCO_TMP/conf-igual"
  conf_distinto > "$BANCO_TMP/conf-distinto"
  escribir_guion_ssh

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/informe.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    HESTIA_DIR="$2"
    HESTIA_CONF_RESTIC="$2/conf/restic.conf"
    DEPLOY_HOST="servidor-sintetico"
    DEPLOY_USER="root"
    BC_PROFILE="Sintetico"
    BC_PROFILE_DIR="$3"
    BC_OPT_REPO="$4"
    BC_ASSUME_YES=1
    BC_NO_COLOR=1
    [[ "$5" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_restic
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$dir/perfil" "$REPO_PEDIDO" "$modo" 2>&1
}

# ¿Se le pidió al servidor algo que contenga este texto?
se_pidio() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo no; return 0; }
  if grep -qF -- "$1" "$BANCO_TMP/ordenes.txt"; then echo si; else echo no; fi
}

# El informe generado en el perfil del caso (vacío si no hay ninguno).
informe_de() {
  local caso="$1"
  find "$BANCO_TMP/$caso/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- servidor sin configurar -------------------------------------------------
#
# El caso normal la primera vez. Y el que destapó el fallo del separador: con
# el «antes» vacío, el valor nuevo se colaba en la columna del viejo y el
# informe decía que ya estaba puesto lo que se acababa de poner.
test_an_unconfigured_server_is_written_and_confirmed() {
  nueva_prueba t1
  local salida; salida="$(registrar t1 "@vacio" "conf-igual" 0 ok si)"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "comprobado leyéndolo de vuelta" \
    "y dice que lo comprobó, no solo que lo hizo"
  afirmar_igual "$(se_pidio "v-add-backup-host-restic")" "si" "se envió la orden de alta"

  local informe; informe="$(informe_de t1)"
  afirmar_igual "$([[ -n "$informe" ]] && echo si || echo no)" "si" "se guardó un informe"
  afirmar_contiene "$informe" "\| Repositorio \|  \| $REPO_PEDIDO \|" \
    "el informe: repositorio, antes vacío y después con la ruta"
  afirmar_contiene "$informe" "\| Retención \|  \| SNAPSHOTS=30 KEEP_DAILY=8" \
    "el informe: la retención, aparte del repositorio"
  afirmar_contiene "$informe" "v-add-backup-host-restic" "el informe: la orden ejecutada"
  afirmar_contiene "$informe" "Cómo deshacerlo" "el informe: cómo deshacerlo"
}

# --- ya configurado igual ----------------------------------------------------
test_an_already_configured_server_is_not_touched() {
  nueva_prueba t2
  local salida; salida="$(registrar t2 "conf-igual" "conf-igual" 0 ok si)"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "No había nada que cambiar" \
    "lo dice tal cual, no como si lo hubiera hecho"
  afirmar_igual "$(se_pidio "v-add-backup-host-restic")" "no" \
    "NINGUNA orden de escritura enviada al servidor"
}

# --- la orden dice que bien y no cambió nada ---------------------------------
#
# El caso que existe porque HestiaCP registra éxitos que no ocurrieron.
test_a_write_that_reports_success_but_changes_nothing_fails_the_command() {
  nueva_prueba t3
  local salida; salida="$(registrar t3 "conf-distinto" "conf-distinto" 0 ok si)"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:1" \
    "la orden NO termina con 0 aunque HestiaCP dijera que fue bien"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "NO lo confirma" "y lo dice con claridad"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "ni llegó a escribir" \
    "y dice que la orden ni llegó a escribir, que es lo que se ve"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "La configuración anterior está en" \
    "y dice dónde está la copia"
}

# --- la copia fechada falla --------------------------------------------------
#
# Sin poder volver atrás no se toca un servidor de producción.
test_a_failed_backup_copy_stops_everything() {
  nueva_prueba t4
  local salida; salida="$(registrar t4 "conf-distinto" "conf-igual" 0 falla si)"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"

  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" "la orden falla"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "no se pudo dejar una copia" "y dice por qué"
  afirmar_igual "$(se_pidio "v-add-backup-host-restic")" "no" \
    "NINGUNA orden de escritura enviada al servidor"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_writes_nothing_and_files_nothing() {
  nueva_prueba t5
  local salida; salida="$(registrar t5 "conf-distinto" "conf-distinto" 0 ok si ensayo)"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "PASARÍA" "se ve que es una simulación"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "pasaría de '/OtraRuta' a '$REPO_PEDIDO'" \
    "y se ve el plan: de qué a qué"
  afirmar_igual "$(se_pidio "v-add-backup-host-restic")" "no" \
    "ninguna orden de escritura enviada"
  afirmar_igual "$(se_pidio "cp -p")" "no" "ni copia fechada: no hay nada que proteger"
  afirmar_igual "$([[ -n "$(informe_de t5)" ]] && echo si || echo no)" "no" \
    "y NO se archiva ningún informe de algo que no ha pasado"
}

# --- restic no responde ------------------------------------------------------
#
# Que el archivo haya quedado bien no prueba que el servidor pueda respaldar:
# la orden de HestiaCP no comprueba el resultado de instalar restic y escribe
# la configuración igualmente.
test_a_registered_host_without_restic_is_not_a_success() {
  nueva_prueba t6
  local salida; salida="$(registrar t6 "@vacio" "conf-igual" 0 ok no)"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:1" \
    "no se da por bueno un servidor que no puede respaldar"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "restic NO responde" "y dice exactamente qué falta"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "NO se arregla repitiendo esta orden" \
    "y que repetir la orden no lo arregla"
}

# --- no se puede leer el estado de partida -----------------------------------
test_an_unreadable_state_writes_nothing() {
  nueva_prueba t7
  local salida; salida="$(registrar t7 "@ilegible" "conf-igual" 0 ok si)"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"

  afirmar_contiene "$BANCO_TMP/t7/salida.log" "CODIGO:1" "la orden falla"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "NO se ha tocado nada" \
    "y deja claro que el servidor quedó como estaba"
  afirmar_igual "$(se_pidio "v-add-backup-host-restic")" "no" \
    "ninguna orden de escritura enviada"
}

test_an_unconfigured_server_is_written_and_confirmed
test_an_already_configured_server_is_not_touched
test_a_write_that_reports_success_but_changes_nothing_fails_the_command
test_a_failed_backup_copy_stops_everything
test_a_dry_run_writes_nothing_and_files_nothing
test_a_registered_host_without_restic_is_not_a_success
test_an_unreadable_state_writes_nothing

fin_de_suite
