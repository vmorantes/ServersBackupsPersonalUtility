#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_cron.sh — programar el respaldo incremental
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Todo va por el `ssh` falso del banco (ADR 0009).
#
# Este es el paso que le costó un servidor al PO: tenía la línea puesta, en el
# crontab de una cuenta, sin ruta absoluta y con la hora 25. Cron no la
# ejecutaba nunca y nada lo decía. Por eso lo que se prueba aquí no es que la
# línea ESTÉ, sino que esté BIEN, y que una línea escrita que el diagnóstico
# rechazaría NO se dé por hecha.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_cron.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_cron =="

# Si esta máquina tuviera un HestiaCP de verdad, bc_hestia_conectar trabajaría
# EN LOCAL en vez de irse por el ssh falso, y estas pruebas tocarían el sistema
# de quien las ejecuta. Se comprueba y se aborta: las salvaguardas no dependen
# de quién llame (ADR 0010).
if [[ -d /usr/local/hestia ]]; then
  echo "probar_hestia_cron.sh: existe /usr/local/hestia en esta máquina; se aborta." >&2
  exit 2
fi

# La ruta REAL de HestiaCP, no una inventada: bc_hestia_diag_cron exige que la
# orden del cron lleve "/usr/local/hestia/bin/" literal, así que una ruta
# sintética haría que el juez rechazara una línea perfectamente buena y la
# prueba mediría otra cosa. Aquí no existe ese directorio (se comprueba abajo),
# así que bc_hestia_conectar se va por SSH al servidor simulado.
HESTIA_FALSO="/usr/local/hestia"
CRONTAB_SIS="/var/spool/cron/crontabs/hestiaweb"

# Crontabs sintéticos.
cron_vacio()    { printf '# tareas de HestiaCP\n10 05 * * * sudo %s/bin/v-backup-users\n' "$HESTIA_FALSO"; }
cron_bueno()    { cron_vacio; printf '45 5 * * * sudo %s/bin/v-backup-users-restic\n' "$HESTIA_FALSO"; }
cron_hora_mala(){ cron_vacio; printf '45 25 * * * sudo %s/bin/v-backup-users-restic\n' "$HESTIA_FALSO"; }

# El guion del `ssh` falso.
#
#   - `id -u` / `true`      -> abrir la conexión y elevar sin sudo
#   - `test -d`             -> el HestiaCP existe
#   - buscar la línea       -> lo que haya en $BANCO_TMP/donde (vacío = nada)
#   - `cat` del crontab     -> siguiente valor de la cola de lecturas
#   - la copia fechada      -> según $BANCO_TMP/copia
#   - la escritura          -> el código de $BANCO_TMP/codigo-escritura
#   - `stat`                -> lo que haya en $BANCO_TMP/permisos
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
  *"test -d"*"/usr/local/hestia"*) exit 0 ;;

  *"grep"*"v-backup-users"*|*"cron.conf"*)
    cat "\$BANCO_TMP/donde"; exit 0 ;;

  *"cp -p"*)
    [[ "\$(cat "\$BANCO_TMP/copia")" == "falla" ]] && exit 1
    [[ "\$(cat "\$BANCO_TMP/copia")" == "sin-original" ]] && { printf 'BC_SIN_ORIGINAL\\n'; exit 0; }
    printf 'BC_COPIA_OK\\n'; exit 0 ;;

  *"stat -c"*)
    printf '%s\\n' "\$(cat "\$BANCO_TMP/permisos")"
    printf 'BC_FIN\\n'; exit 0 ;;

  *"cat "*"hestiaweb"*)
    valor="\$(sed -n '1p' "\$BANCO_TMP/lecturas")"
    sed -i '1d' "\$BANCO_TMP/lecturas"
    [[ "\$valor" == "@ilegible" ]] && exit 1
    [[ "\$valor" == "@vacio" ]] || printf '%s\\n' "\$(cat "\$BANCO_TMP/\$valor")"
    printf 'BC_FIN\\n'; exit 0 ;;

  *"printf"*"hestiaweb"*|*"chown"*)
    exit "\$(cat "\$BANCO_TMP/codigo-escritura")" ;;
esac
echo "falso ssh: ninguna respuesta prevista para: \$llana" >&2
exit 95
FIN
}

# Prepara y ejecuta la programación.
# $1 caso  $2 lo que encuentra la búsqueda ("" = nada)  $3 crontab ANTES
# $4 crontab DESPUÉS  $5 código de escritura  $6 copia  $7 permisos  $8 modo
programar() {
  local caso="$1" donde="$2" antes="$3" despues="$4" codigo="$5" copia="$6" \
        permisos="$7" modo="${8:-}"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt"
  printf '%s' "$donde"     > "$BANCO_TMP/donde"
  printf '%s\n%s\n' "$antes" "$despues" > "$BANCO_TMP/lecturas"
  printf '%s' "$codigo"    > "$BANCO_TMP/codigo-escritura"
  printf '%s' "$copia"     > "$BANCO_TMP/copia"
  printf '%s' "$permisos"  > "$BANCO_TMP/permisos"
  cron_vacio     > "$BANCO_TMP/cron-vacio"
  cron_bueno     > "$BANCO_TMP/cron-bueno"
  cron_hora_mala > "$BANCO_TMP/cron-hora-mala"
  escribir_guion_ssh

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
    BC_ASSUME_YES=1
    BC_NO_COLOR=1
    [[ "$4" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_cron
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$dir/perfil" "$modo" 2>&1
}

se_pidio() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo no; return 0; }
  if grep -qF -- "$1" "$BANCO_TMP/ordenes.txt"; then echo si; else echo no; fi
}

# Cuántas órdenes de ESCRITURA en el crontab se enviaron. Es el número que
# importa: dos respaldos a la vez sobre el mismo repositorio es peor que uno
# mal puesto.
cuantas_escrituras() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo 0; return 0; }
  grep -c 'chown hestiaweb' "$BANCO_TMP/ordenes.txt" || true
}

informe_de() {
  find "$BANCO_TMP/$1/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- no había nada -----------------------------------------------------------
test_a_missing_schedule_is_added_and_confirmed() {
  nueva_prueba t1
  local salida
  salida="$(programar t1 "" "cron-vacio" "cron-bueno" 0 ok "600 hestiaweb:hestiaweb")"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "comprobado leyéndolo de vuelta" \
    "dice que lo comprobó, no solo que lo hizo"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "permisos y el dueño correctos" \
    "y que los permisos están bien"
  afirmar_igual "$(cuantas_escrituras)" "1" "una sola escritura en el crontab"

  local informe; informe="$(informe_de t1)"
  afirmar_igual "$([[ -n "$informe" ]] && echo si || echo no)" "si" "se guardó un informe"
  afirmar_contiene "$informe" "\| Línea programada \|  \| 45 5 \* \* \* " \
    "el informe: antes sin línea, después con ella"
  afirmar_contiene "$informe" "Cómo deshacerlo" "el informe: cómo deshacerlo"
  afirmar_contiene "$informe" "600 hestiaweb:hestiaweb" "el informe: permisos y dueño"
}

# --- ya estaba bien ----------------------------------------------------------
test_a_correct_schedule_is_left_alone() {
  nueva_prueba t2
  local existente="$CRONTAB_SIS:45 5 * * * sudo $HESTIA_FALSO/bin/v-backup-users-restic"
  local salida; salida="$(programar t2 "$existente" "cron-bueno" "cron-bueno" 0 ok "600 hestiaweb:hestiaweb")"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "está bien puesta" "y lo dice"
  afirmar_igual "$(cuantas_escrituras)" "0" "NINGUNA escritura enviada al servidor"
}

# --- ya estaba, pero en el crontab de una cuenta -----------------------------
#
# El caso real del PO. No se duplica, y no se da por bueno: se dice dónde está
# y qué le pasa.
test_a_schedule_in_the_wrong_crontab_is_reported_not_duplicated() {
  nueva_prueba t3
  local existente="/var/spool/cron/crontabs/admin:45 5 * * * sudo $HESTIA_FALSO/bin/v-backup-users-restic"
  local salida; salida="$(programar t3 "$existente" "cron-vacio" "cron-bueno" 0 ok "600 hestiaweb:hestiaweb")"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_igual "$(cuantas_escrituras)" "0" "NO se añade una segunda programación"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:1" "y no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "crontabs/admin" "se dice DÓNDE está la que hay"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "tiene un problema" "y QUÉ problema tiene"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "Decide tú" "y que la decisión es del usuario"
}

# El otro caso del PO: la línea está en el sitio correcto, pero con la hora 25.
test_an_impossible_hour_in_the_existing_line_is_reported() {
  nueva_prueba t4
  local existente="$CRONTAB_SIS:45 25 * * * sudo $HESTIA_FALSO/bin/v-backup-users-restic"
  local salida; salida="$(programar t4 "$existente" "cron-hora-mala" "cron-bueno" 0 ok "600 hestiaweb:hestiaweb")"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"

  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" "una hora imposible no es «ya está»"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "hora 25" "y se dice cuál es el valor imposible"
  afirmar_igual "$(cuantas_escrituras)" "0" "sin añadir una segunda"
}

# --- se escribe y queda mal --------------------------------------------------
#
# LA PRUEBA QUE IMPORTA: la orden dice que fue bien, la línea ESTÁ, y el
# diagnóstico la rechaza. Que esté no basta.
test_a_written_line_that_the_diagnosis_rejects_is_not_done() {
  nueva_prueba t5
  local salida; salida="$(programar t5 "" "cron-vacio" "cron-hora-mala" 0 ok "600 hestiaweb:hestiaweb")"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:1" \
    "la línea está, pero está mal: NO es HECHO"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "NO queda bien" "y lo dice"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "El crontab anterior está en" \
    "y dice dónde está la copia"
}

# --- permisos equivocados ----------------------------------------------------
#
# Un crontab con otros permisos lo ignora cron ENTERO, y eso no se distingue
# de «no hay respaldo» hasta que pasan semanas.
test_wrong_permissions_are_not_a_success() {
  nueva_prueba t6
  local salida; salida="$(programar t6 "" "cron-vacio" "cron-bueno" 0 ok "644 root:root")"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:1" \
    "con permisos equivocados no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "permisos o dueño equivocados" "y se dice"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "ignorar el archivo ENTERO" \
    "y por qué importa tanto"
}

# --- la copia fechada falla --------------------------------------------------
test_a_failed_backup_copy_stops_everything() {
  nueva_prueba t7
  local salida; salida="$(programar t7 "" "cron-vacio" "cron-bueno" 0 falla "600 hestiaweb:hestiaweb")"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"

  afirmar_contiene "$BANCO_TMP/t7/salida.log" "CODIGO:1" "la orden falla"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "no se pudo dejar una copia" "y dice por qué"
  afirmar_igual "$(cuantas_escrituras)" "0" "NINGUNA escritura enviada al servidor"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_writes_nothing_and_files_nothing() {
  nueva_prueba t8
  local salida; salida="$(programar t8 "" "cron-vacio" "cron-bueno" 0 ok "600 hestiaweb:hestiaweb" ensayo)"
  echo "$salida" > "$BANCO_TMP/t8/salida.log"

  afirmar_contiene "$BANCO_TMP/t8/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "PASARÍA" "se ve que es una simulación"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "NO hay ninguna programación" "y se ve el plan"
  afirmar_igual "$(cuantas_escrituras)" "0" "ninguna escritura enviada"
  afirmar_igual "$(se_pidio "cp -p")" "no" "ni copia fechada"
  afirmar_igual "$([[ -n "$(informe_de t8)" ]] && echo si || echo no)" "no" \
    "y NO se archiva ningún informe de algo que no ha pasado"
}

test_a_missing_schedule_is_added_and_confirmed
test_a_correct_schedule_is_left_alone
test_a_schedule_in_the_wrong_crontab_is_reported_not_duplicated
test_an_impossible_hour_in_the_existing_line_is_reported
test_a_written_line_that_the_diagnosis_rejects_is_not_done
test_wrong_permissions_are_not_a_success
test_a_failed_backup_copy_stops_everything
test_a_dry_run_writes_nothing_and_files_nothing

fin_de_suite
