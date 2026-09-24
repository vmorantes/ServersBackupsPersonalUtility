#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_diagnostico.sh — el juicio sobre si los respaldos van
# =============================================================================
# Solo prueba las cuatro funciones PURAS de lib/hestia.sh: reciben texto,
# imprimen "NIVEL<TAB>mensaje" y no conectan a nada. bc_hestia_status entera
# necesita un ssh falso y es otra tanda; lo que NO puede pasar es que el
# juicio viva dentro de ella y quede sin probar (ADR 0017).
#
# Lo que hay detrás de estos veredictos: HestiaCP 1.10.4 registra éxito aunque
# el respaldo incremental falle, así que la única prueba de que un respaldo se
# hizo es una instantánea con fecha.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_diagnostico.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_diagnostico =="

# Ejecuta una de las funciones puras en un subproceso aislado y devuelve su
# línea de veredicto.
veredicto() {
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    "$2" "$3" "$4" "$5"
  ' _ "$BANCO_RAIZ" "$1" "${2:-}" "${3:-}" "${4:-}" 2>&1
}

# Afirma el NIVEL (primer campo) de un veredicto y, opcionalmente, que el
# mensaje contenga un texto.
afirmar_nivel() {
  local linea="$1" esperado="$2" desc="$3" contiene="${4:-}"
  local nivel="${linea%%$'\t'*}"
  afirmar_igual "$nivel" "$esperado" "$desc"
  if [[ -n "$contiene" ]]; then
    local mensaje="${linea#*$'\t'}"
    case "$mensaje" in
      *"$contiene"*) afirmar_igual "si" "si" "$desc: el mensaje menciona '$contiene'" ;;
      *) afirmar_igual "no ('$mensaje')" "si" "$desc: el mensaje menciona '$contiene'" ;;
    esac
  fi
}

# --- cron --------------------------------------------------------------------

test_cron_without_a_line_is_a_failure() {
  nueva_prueba t1
  afirmar_nivel "$(veredicto bc_hestia_diag_cron "" "")" "FALLO" \
    "sin línea de cron: FALLO" "no se ejecuta nunca"
}

# El caso real del PO: "10 25" es la hora 25. El cron de Debian puede rechazar
# el archivo entero, así que el mensaje tiene que decirlo.
test_cron_with_impossible_hour_is_a_failure() {
  nueva_prueba t2
  afirmar_nivel "$(veredicto bc_hestia_diag_cron \
    "10 25 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
    "/var/spool/cron/crontabs/hestiaweb")" "FALLO" \
    "hora 25: FALLO" "archivo ENTERO"
}

test_cron_with_impossible_minute_is_a_failure() {
  nueva_prueba t3
  afirmar_nivel "$(veredicto bc_hestia_diag_cron \
    "75 5 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
    "/var/spool/cron/crontabs/hestiaweb")" "FALLO" \
    "minuto 75: FALLO" "minuto 75"
}

test_cron_without_absolute_path_is_a_failure() {
  nueva_prueba t4
  afirmar_nivel "$(veredicto bc_hestia_diag_cron \
    "30 5 * * * v-backup-users-restic" \
    "/var/spool/cron/crontabs/admin")" "FALLO" \
    "sin ruta absoluta: FALLO" "PATH de cron"
}

test_cron_in_the_wrong_crontab_is_a_warning() {
  nueva_prueba t5
  afirmar_nivel "$(veredicto bc_hestia_diag_cron \
    "30 5 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
    "/var/spool/cron/crontabs/admin")" "AVISO" \
    "en el crontab de una cuenta: AVISO" "v-rebuild-cron-jobs"
}

test_cron_well_formed_is_ok_with_the_time() {
  nueva_prueba t6
  afirmar_nivel "$(veredicto bc_hestia_diag_cron \
    "30 5 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
    "/var/spool/cron/crontabs/hestiaweb")" "OK" \
    "bien puesto: OK" "05:30"
}

# --- instantánea -------------------------------------------------------------

test_snapshot_missing_is_a_failure() {
  nueva_prueba t7
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  afirmar_nivel "$(veredicto bc_hestia_diag_instantanea "" "$ahora" "24")" "FALLO" \
    "sin ninguna copia: FALLO" "no tiene ninguna copia"
}

# El diagnóstico que ningún log del servidor da: tres días con cron diario.
test_snapshot_three_days_old_with_daily_cron_is_a_failure() {
  nueva_prueba t8
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  afirmar_nivel "$(veredicto bc_hestia_diag_instantanea "2026-09-21 03:00:00" "$ahora" "24")" \
    "FALLO" "3 días con cron diario: FALLO" "no hicieron nada"
}

test_snapshot_slightly_late_is_a_warning() {
  nueva_prueba t9
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  afirmar_nivel "$(veredicto bc_hestia_diag_instantanea "2026-09-23 03:00:00" "$ahora" "24")" \
    "AVISO" "33 horas con cron diario: AVISO"
}

test_snapshot_recent_is_ok() {
  nueva_prueba t10
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  afirmar_nivel "$(veredicto bc_hestia_diag_instantanea "2026-09-24 03:00:00" "$ahora" "24")" \
    "OK" "de esta madrugada: OK" "9 horas"
}

# Una fecha ilegible NO es «no hay copias»: son dos cosas distintas y
# confundirlas es justo lo que hace que un diagnóstico mienta.
test_snapshot_unreadable_date_is_blindness_not_a_warning() {
  nueva_prueba t11
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  afirmar_nivel "$(veredicto bc_hestia_diag_instantanea "no-es-una-fecha" "$ahora" "24")" \
    "CIEGO" "fecha ilegible: CIEGO, ni FALLO ni AVISO" "no se pudo leer"
}

# --- cuenta ------------------------------------------------------------------

# El estado exacto del incidente del 2026-09-23.
test_account_marked_with_key_but_no_repo_is_a_failure() {
  nueva_prueba t12
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "1" "0" "1")" "FALLO" \
    "marcada, con clave y sin repositorio: FALLO" "ya no lo creará solo"
}

test_account_marked_without_key_or_repo_is_ok() {
  nueva_prueba t13
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "0" "0" "1")" "OK" \
    "marcada y sin nada todavía: OK" "todavía no ha respaldado"
}

test_account_unmarked_with_repo_is_a_warning() {
  nueva_prueba t14
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "0" "1" "0")" "AVISO" \
    "sin marcar pero con copias: AVISO" "YA NO se respalda"
}

test_account_unmarked_without_repo_is_a_warning() {
  nueva_prueba t15
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "0" "0" "0")" "AVISO" \
    "sin marcar y sin repositorio: AVISO"
}

test_account_marked_with_repo_is_ok() {
  nueva_prueba t16
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "1" "1" "1")" "OK" \
    "marcada y con repositorio: OK"
}

# El repositorio está ahí, con copias dentro, y HestiaCP no tiene su
# contraseña: al siguiente respaldo generará una nueva, que NO abre lo que ya
# hay. Esto no es «todo en orden», es una pérdida programada.
test_account_marked_with_repo_but_no_key_is_a_failure() {
  nueva_prueba t22
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "0" "1" "1")" "FALLO" \
    "marcada, con repositorio y sin contraseña: FALLO" "no abriría las copias que ya hay"
}

# El caso que ninguna prueba cubría: la cuenta no entra en los respaldos, pero
# arrastra una contraseña de repositorio. Es la PRECONDICIÓN del incidente del
# 2026-09-23: marcarla sin apartar esa contraseña no crea ningún repositorio.
test_orphan_key_on_an_unmarked_account_is_named() {
  nueva_prueba t35
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "1" "0" "0")" "AVISO" \
    "sin marcar pero con contraseña guardada: AVISO" "NO lo creará"
}

# Lo mismo cuando ni siquiera hay un repositorio registrado en el servidor.
test_orphan_key_without_a_registered_repo_is_named() {
  nueva_prueba t36
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "1" "-" "0")" "AVISO" \
    "sin marcar, con contraseña y sin repositorio registrado: AVISO" "NO lo creará"
}

# --- sin repositorio registrado ('-') ----------------------------------------
#
# La línea «Ruta del repositorio» ya dijo que no hay ninguno. El veredicto de
# cada cuenta habla solo de lo que sí se sabe, y NO repite «no se pudo
# comprobar si su repositorio existe» una vez por cuenta.

test_no_registered_repo_does_not_repeat_the_unknown() {
  nueva_prueba t37
  local linea; linea="$(veredicto bc_hestia_diag_cuenta "1" "-" "1")"
  afirmar_nivel "$linea" "AVISO" "marcada y con contraseña, sin repositorio registrado: AVISO"
  case "${linea#*$'\t'}" in
    *"su repositorio existe"*) afirmar_igual "repite" "no repite" \
      "no repite lo que ya dijo la línea de la ruta" ;;
    *) afirmar_igual "no repite" "no repite" \
      "no repite lo que ya dijo la línea de la ruta" ;;
  esac
}

test_no_registered_repo_and_unmarked_says_only_that() {
  nueva_prueba t38
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "0" "-" "0")" "AVISO" \
    "sin marcar y sin repositorio registrado: AVISO" "no entra en los respaldos"
}

# --- la doble sonda del repositorio ------------------------------------------
#
# bc_hestia_juzgar_repo recibe las dos respuestas y decide. Es pura: no sondea
# nada. Lo que vigila es el desastre concreto de una sonda sola: si el
# almacenamiento no responde y eso se lee como «el repositorio no existe», el
# diagnóstico acaba recomendando apartar una contraseña que sí abre copias
# reales.

test_repo_probe_account_answers_means_it_exists() {
  nueva_prueba t39
  afirmar_igual "$(veredicto bc_hestia_juzgar_repo "1" "?")" "1" \
    "la cuenta responde: existe, sin preguntar al padre"
}

test_repo_probe_parent_answers_and_account_does_not_means_it_is_gone() {
  nueva_prueba t40
  afirmar_igual "$(veredicto bc_hestia_juzgar_repo "0" "1")" "0" \
    "el padre responde y la cuenta no: de verdad no existe"
}

test_repo_probe_neither_answers_is_unknown() {
  nueva_prueba t41
  afirmar_igual "$(veredicto bc_hestia_juzgar_repo "0" "0")" "?" \
    "ni el padre ni la cuenta responden: no se afirma nada"
  afirmar_igual "$(veredicto bc_hestia_juzgar_repo "?" "?")" "?" \
    "las dos sondas fallan: no se afirma nada"
  afirmar_igual "$(veredicto bc_hestia_juzgar_repo "0" "?")" "?" \
    "la cuenta dice que no y el padre no contesta: no se afirma nada"
}

# --- lo que no se pudo leer ('?') --------------------------------------------
#
# Un '?' es «no se pudo preguntar», no «no». Las tres pruebas siguientes
# comprueban dos cosas a la vez: que el nivel NO es OK, y que el mensaje dice
# cuál de los tres datos falta. Lo segundo es lo que distingue este veredicto
# de los que salen al tratar el '?' como un 0, que también son AVISO pero
# afirman algo que nadie comprobó.

test_account_with_unreadable_key_is_blindness() {
  nueva_prueba t23
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "?" "1" "1")" "CIEGO" \
    "contraseña ilegible: CIEGO, ni OK ni AVISO" "si tiene contraseña de repositorio"
}

test_account_with_unreadable_repo_is_blindness() {
  nueva_prueba t24
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "1" "?" "1")" "CIEGO" \
    "repositorio no sondeable: CIEGO, ni OK ni AVISO" "si su repositorio existe"
}

test_account_with_unreadable_mark_is_blindness() {
  nueva_prueba t25
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "1" "1" "?")" "CIEGO" \
    "marca ilegible: CIEGO, ni OK ni AVISO" "si está marcada para respaldo incremental"
}

test_account_with_nothing_readable_is_blindness() {
  nueva_prueba t26
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "?" "?" "?")" "CIEGO" \
    "los tres datos ilegibles: CIEGO, ni OK ni AVISO" "no se pudo comprobar"
}

# El '?' tampoco puede colarse como 0 cuando el 0 daría un veredicto peor: sin
# saber si está marcada, no se puede decir «esta cuenta no entra».
test_unreadable_mark_is_not_treated_as_zero() {
  nueva_prueba t27
  afirmar_nivel "$(veredicto bc_hestia_diag_cuenta "0" "0" "?")" "CIEGO" \
    "marca ilegible y nada más: no se afirma que no entre" "si está marcada para respaldo incremental"
}

# --- la orden que compone la sonda -------------------------------------------
#
# bc_hestia_sondear_orden es pura: compone el texto que se ejecutaría en el
# servidor. Aquí NO se conecta a nada: el texto se ejecuta con `bash -c` en
# esta misma máquina, con órdenes inocuas (true, false, exit 2).

# Devuelve el texto compuesto para una orden dada.
orden_sonda() {
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    bc_hestia_sondear_orden "$2"
  ' _ "$BANCO_RAIZ" "$1" 2>&1
}

# El fallo que esto vigila: bc_ssh_sudo ANTEPONE texto a la orden
# (`ssh "sudo -n $*"`, lib/ssh.sh). Un texto que se parsea suelto puede ser un
# error de sintaxis detrás de `sudo -n`, y el servidor no dice nada: la salida
# vacía se leería como «no se pudo preguntar» en TODAS las cuentas.
test_probe_text_survives_a_sudo_prefix() {
  nueva_prueba t28
  local texto; texto="$(orden_sonda "test -f /etc/hosts")"
  bash -n -c "sudo -n $texto" 2>"$BANCO_TMP/t28.err"
  afirmar_codigo 0 "$?" "el texto de la sonda se parsea detrás de 'sudo -n'"
  afirmar_igual "$(cat "$BANCO_TMP/t28.err")" "" \
    "sin errores de sintaxis detrás de 'sudo -n'"
}

test_probe_reports_yes_no_and_error_apart() {
  nueva_prueba t29
  afirmar_igual "$(bash -c "$(orden_sonda 'true')")"      "BC_SI"  "orden que sale con 0: BC_SI"
  afirmar_igual "$(bash -c "$(orden_sonda 'false')")"     "BC_NO"  "orden que sale con 1: BC_NO"
  # El caso real: `grep` sale con 2 cuando el archivo no existe o no se puede
  # leer, y con 1 cuando simplemente no hay coincidencia. Confundirlos es
  # afirmar «esta cuenta no está marcada» sin haber leído su user.conf.
  afirmar_igual "$(bash -c "$(orden_sonda "grep -q x /no/existe/ninguno 2>/dev/null")")" \
    "BC_ERR" "grep sobre un archivo que no existe: BC_ERR, no BC_NO"
}

# Una tubería dentro de la sonda (la del repositorio con rclone) no puede
# romper la composición.
test_probe_accepts_a_pipeline() {
  nueva_prueba t30
  afirmar_igual "$(bash -c "$(orden_sonda "printf 'x\n' | grep -q .")")" "BC_SI" \
    "una tubería dentro de la sonda: BC_SI"
}

# --- lectura de instantáneas (json) ------------------------------------------
#
# Aquí tampoco se conecta a nada: se monta un HESTIA_DIR sintético con un
# v-list-user-backups-restic falso que imprime una salida enlatada, y
# bc_hestia_read lo ejecuta en esta misma máquina (BC_HESTIA_REMOTO=0).

# Monta el HestiaCP falso y devuelve la salida de <función> <usuario>.
con_hestia_falso() {
  local salida_enlatada="$1" fn="$2"
  local raiz="$BANCO_TMP/hestia-falso"
  rm -rf "$raiz"; mkdir -p "$raiz/bin"
  printf '%s\n' '#!/usr/bin/env bash' "cat <<'FIN'" "$salida_enlatada" "FIN" \
    > "$raiz/bin/v-list-user-backups-restic"
  chmod +x "$raiz/bin/v-list-user-backups-restic"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    HESTIA_DIR="$2"
    BC_HESTIA_REMOTO=0
    "$3" cliente07
  ' _ "$BANCO_RAIZ" "$raiz" "$fn" 2>&1
}

# Un array de restic con dos instantáneas, en UNA sola línea: es como sale de
# `restic --json snapshots`, que serializa el array entero de golpe.
BC_JSON_DOS='[{"time":"2026-09-22T03:00:00.123456+02:00","short_id":"a1b2c3d4","paths":["/home/cliente07"]},{"time":"2026-09-24T03:00:00.654321+02:00","short_id":"e5f6a7b8","paths":["/home/cliente07"]}]'

test_last_snapshot_is_the_most_recent_trimmed() {
  nueva_prueba t31
  afirmar_igual "$(con_hestia_falso "$BC_JSON_DOS" bc_hestia_restic_ultima)" \
    "2026-09-24 03:00:00" "la última instantánea es la más reciente, recortada a segundos"
}

test_snapshot_count_does_not_depend_on_lines() {
  nueva_prueba t32
  afirmar_igual "$(con_hestia_falso "$BC_JSON_DOS" bc_hestia_restic_cuantas)" \
    "2" "dos instantáneas en una sola línea se cuentan como 2"
}

# Sin copias, restic devuelve un array vacío: son cero, no «no se pudo leer».
test_empty_array_means_none() {
  nueva_prueba t33
  afirmar_igual "$(con_hestia_falso "[]" bc_hestia_restic_ultima)" "ninguna" \
    "array vacío: ninguna instantánea"
  afirmar_igual "$(con_hestia_falso "[]" bc_hestia_restic_cuantas)" "0" \
    "array vacío: cero instantáneas"
}

# Una salida que no es json (un mensaje de error, una tabla) NO puede leerse
# como «esta cuenta no tiene copias».
test_non_json_output_is_not_read_as_no_backups() {
  nueva_prueba t34
  afirmar_igual "$(con_hestia_falso "Fatal: unable to open config file" bc_hestia_restic_ultima)" \
    "no disponible" "salida que no es json: no disponible, no 'ninguna'"
}

# --- el cierre del diagnóstico -----------------------------------------------
#
# Dos cosas que no pueden confundirse: un AVISO es algo que se miró y no gusta;
# un dato ciego es algo que NO se pudo mirar. Si los dos se cuentan juntos y
# ninguno cambia el código de salida, un cron que solo mira `$?` lee «los
# respaldos van bien» de un diagnóstico que no pudo leer nada.

# Devuelve el código de salida de bc_hestia_codigo_diag.
codigo_diag() {
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    bc_hestia_codigo_diag "$2" "$3"
  ' _ "$BANCO_RAIZ" "$1" "$2" >/dev/null 2>&1
  echo $?
}

test_exit_code_is_zero_when_everything_was_read_and_fine() {
  nueva_prueba t42
  afirmar_igual "$(codigo_diag 0 0)" "0" "sin fallos y sin ciegos: 0"
}

test_warnings_alone_do_not_change_the_exit_code() {
  nueva_prueba t43
  afirmar_igual "$(codigo_diag 0 0)" "0" \
    "los avisos ni se pasan: no cambian el código"
}

test_a_failure_changes_the_exit_code() {
  nueva_prueba t44
  afirmar_igual "$(codigo_diag 1 0)" "1" "un fallo: 1"
}

# El caso del que va todo esto: no hubo ningún fallo porque no se pudo mirar.
test_a_blind_reading_changes_the_exit_code() {
  nueva_prueba t45
  afirmar_igual "$(codigo_diag 0 1)" "1" \
    "sin fallos pero con un dato sin leer: 1, no 0"
}

# Y el resumen tiene que DECIRLO, no solo devolver un número.
test_summary_counts_blind_readings_apart() {
  nueva_prueba t46
  local salida
  salida="$(bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    BC_NO_COLOR=1
    bc_hestia_resumen_diag 2 1 3
  ' _ "$BANCO_RAIZ" 2>&1)"
  case "$salida" in
    *"3 dato(s) que no se pudieron leer"*)
      afirmar_igual "si" "si" "el resumen cuenta los datos ciegos aparte" ;;
    *) afirmar_igual "no ('$salida')" "si" "el resumen cuenta los datos ciegos aparte" ;;
  esac
  case "$salida" in
    *INCOMPLETO*) afirmar_igual "si" "si" "el resumen dice que el diagnóstico está incompleto" ;;
    *) afirmar_igual "no" "si" "el resumen dice que el diagnóstico está incompleto" ;;
  esac
}

test_summary_says_nothing_about_blindness_when_there_is_none() {
  nueva_prueba t47
  local salida
  salida="$(bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    BC_NO_COLOR=1
    bc_hestia_resumen_diag 0 1 0
  ' _ "$BANCO_RAIZ" 2>&1)"
  case "$salida" in
    *INCOMPLETO*) afirmar_igual "lo dice" "no lo dice" \
      "sin datos ciegos no se habla de diagnóstico incompleto" ;;
    *) afirmar_igual "no lo dice" "no lo dice" \
      "sin datos ciegos no se habla de diagnóstico incompleto" ;;
  esac
}

# --- cómo se cuenta un veredicto ciego ---------------------------------------
#
# Un CIEGO se PINTA como un aviso —al usuario le da igual el nombre interno—
# pero no se CUENTA como tal. Si se contara junto a los avisos, el resumen
# diría «3 avisos» de un diagnóstico que no pudo mirar tres cosas, y el código
# de salida no cambiaría.

# Pinta un veredicto y devuelve "fallos avisos ciegos" después de hacerlo.
contar_veredicto() {
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    BC_NO_COLOR=1
    f=0; a=0; c=0
    if [[ "$3" == "con" ]]; then
      # Se calla todo: lo que se mira son los contadores.
      bc_hestia_pintar_veredicto "x" "$2" f a c >/dev/null 2>&1
    else
      # La llamada corta debe morir diciéndolo, y bc_die escribe por stderr:
      # aquí solo se calla la salida normal.
      bc_hestia_pintar_veredicto "x" "$2" f a >/dev/null
    fi
    echo "$f $a $c"
  ' _ "$BANCO_RAIZ" "$1" "${2:-con}" 2>&1
  # La salida lleva stdout y stderr juntos a propósito: una llamada mal hecha
  # muere por bc_die, que escribe por stderr, y eso es lo que hay que ver.
}

test_blind_verdicts_are_counted_apart_from_warnings() {
  nueva_prueba t48
  afirmar_igual "$(contar_veredicto "$(printf 'CIEGO\tno se pudo leer')")" "0 0 1" \
    "un veredicto ciego suma a ciegos, no a avisos"
  afirmar_igual "$(contar_veredicto "$(printf 'AVISO\talgo que no gusta')")" "0 1 0" \
    "un aviso sigue sumando a avisos"
  afirmar_igual "$(contar_veredicto "$(printf 'FALLO\talgo roto')")" "1 0 0" \
    "un fallo sigue sumando a fallos"
}

# Una llamada a la que le falta el contador de ciegos NO cuenta mal en
# silencio: se muere y lo dice. Quien no quiera contar ahí pasa una variable
# llamada `sin_contar`, que se ve al leer la llamada.
test_a_short_call_fails_loudly_instead_of_miscounting() {
  nueva_prueba t49
  local salida
  salida="$(contar_veredicto "$(printf 'CIEGO\tno se pudo leer')" sin)"
  case "$salida" in
    *"5 argumentos"*) afirmar_igual "si" "si" "una llamada corta dice qué le falta" ;;
    *) afirmar_igual "no ('$salida')" "si" "una llamada corta dice qué le falta" ;;
  esac
  case "$salida" in
    *"0 0 0"*|*"0 1 0"*) afirmar_igual "siguió contando" "se detuvo" \
      "una llamada corta no sigue como si nada" ;;
    *) afirmar_igual "se detuvo" "se detuvo" "una llamada corta no sigue como si nada" ;;
  esac
}

# --- el informe entero, sin servidor -----------------------------------------
#
# Esto es lo que demuestra que partir bc_hestia_diagnosticar sirvió de algo:
# bc_hestia_pintar_diagnostico recibe los datos ya leídos y no toca nada
# remoto, así que el informe COMPLETO —veredictos, contadores, resumen y
# código de salida— se puede probar aquí, con datos inventados y sin ssh.

# Ejecuta el pintado con un conjunto de datos sintético. Devuelve la salida
# completa y, en la última línea, "CODIGO:N".
pintar_diagnostico() {
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    BC_NO_COLOR=1
    bc_hestia_pintar_diagnostico "$2"
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$2" 2>&1
}

# Construye una línea de datos con los campos separados por tabuladores.
reg() { local IFS=$'\t'; printf '%s\n' "$*"; }

# Un servidor sano: repositorio en s3 con ruta absoluta, cron bien puesto y una
# cuenta con copia de esta madrugada.
test_a_healthy_server_reports_zero_of_everything() {
  nueva_prueba t51
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  local datos
  datos="$(
    reg repo "rclone:almacen:/IncrementalBackups" "s3"
    reg cron "30 5 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
        "/var/spool/cron/crontabs/hestiaweb"
    reg cada_h 24 leido
    reg ahora "$ahora"
    reg cuentas si
    reg cuenta cliente07 1 1 1 "2026-09-24 03:00:00"
  )"
  local salida; salida="$(pintar_diagnostico "" "$datos")"
  echo "$salida" > "$BANCO_TMP/t51/salida.log"
  afirmar_contiene "$BANCO_TMP/t51/salida.log" "0 fallo\(s\) · 0 aviso\(s\) · 0 dato\(s\)" \
    "servidor sano: los tres contadores a cero"
  afirmar_contiene "$BANCO_TMP/t51/salida.log" "CODIGO:0" "y código de salida 0"
  afirmar_no_contiene "$BANCO_TMP/t51/salida.log" "INCOMPLETO" \
    "sin ceguera no se habla de diagnóstico incompleto"
}

# La mezcla: un fallo, un aviso y ceguera en la misma pasada. Los tres números
# tienen que salir por separado.
test_a_mixed_report_counts_the_three_things_apart() {
  nueva_prueba t52
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  local datos
  datos="$(
    reg repo "rclone:almacen:/IncrementalBackups" "alias"
    reg cron "30 5 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
        "/var/spool/cron/crontabs/hestiaweb"
    reg cada_h 24 leido
    reg ahora "$ahora"
    reg cuentas si
    reg cuenta uno 1 0 1 "2026-09-24 03:00:00"
    reg cuenta dos "?" "?" 1 "2026-09-24 03:00:00"
    reg cuenta tres 1 1 1 "__ILEGIBLE__"
  )"
  local salida; salida="$(pintar_diagnostico "" "$datos")"
  echo "$salida" > "$BANCO_TMP/t52/salida.log"
  afirmar_contiene "$BANCO_TMP/t52/salida.log" "1 fallo\(s\) · 1 aviso\(s\) · 3 dato\(s\)" \
    "un fallo (cuenta 'uno'), un aviso (remoto envolvente) y tres datos ciegos"
  afirmar_contiene "$BANCO_TMP/t52/salida.log" "CODIGO:1" "código de salida 1"
  afirmar_contiene "$BANCO_TMP/t52/salida.log" "INCOMPLETO" "y dice que está incompleto"
}

# Sin fallos, pero con algo sin leer: el caso que antes salía con 0.
test_blindness_alone_is_enough_to_exit_with_one() {
  nueva_prueba t53
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  local datos
  datos="$(
    reg repo "rclone:almacen:/IncrementalBackups" "s3"
    reg cron "30 5 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
        "/var/spool/cron/crontabs/hestiaweb"
    reg cada_h 24 leido
    reg ahora "$ahora"
    reg cuentas si
    reg cuenta uno 1 "?" 1 "2026-09-24 03:00:00"
  )"
  local salida; salida="$(pintar_diagnostico "" "$datos")"
  echo "$salida" > "$BANCO_TMP/t53/salida.log"
  afirmar_contiene "$BANCO_TMP/t53/salida.log" "0 fallo\(s\) · 0 aviso\(s\) · 1 dato\(s\)" \
    "sin fallos ni avisos, con un dato sin leer"
  afirmar_contiene "$BANCO_TMP/t53/salida.log" "CODIGO:1" "aun así, código de salida 1"
}

# Si no se pudo leer la lista de cuentas, el informe se corta ahí, lo dice, y
# no sale con 0.
test_an_unreadable_account_list_stops_the_report() {
  nueva_prueba t54
  local datos
  datos="$(
    reg repo "rclone:almacen:/IncrementalBackups" "s3"
    reg cron "30 5 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
        "/var/spool/cron/crontabs/hestiaweb"
    reg cada_h 24 leido
    reg ahora 0
    reg cuentas no
  )"
  local salida; salida="$(pintar_diagnostico "" "$datos")"
  echo "$salida" > "$BANCO_TMP/t54/salida.log"
  afirmar_contiene "$BANCO_TMP/t54/salida.log" "[Nn]o se pudo leer la lista de cuentas" \
    "se dice que no se pudieron leer las cuentas"
  afirmar_contiene "$BANCO_TMP/t54/salida.log" "1 dato\(s\)" "y cuenta como ceguera"
  afirmar_contiene "$BANCO_TMP/t54/salida.log" "CODIGO:1" "y el código de salida es 1"
}

# La periodicidad asumida se DICE. Sin esa línea, un usuario tomaría por leído
# un 24 que nadie leyó.
test_an_assumed_period_is_said_out_loud() {
  nueva_prueba t55
  local datos
  datos="$(
    reg repo "/IncrementalBackups" ""
    reg cron "" ""
    reg cada_h 24 asumido
    reg ahora 0
    reg cuentas si
  )"
  local salida; salida="$(pintar_diagnostico "" "$datos")"
  echo "$salida" > "$BANCO_TMP/t55/salida.log"
  afirmar_contiene "$BANCO_TMP/t55/salida.log" "se asume una vez al día" \
    "la periodicidad asumida se dice"
}

# --- ruta del repositorio ----------------------------------------------------

test_repo_path_missing_is_a_failure() {
  nueva_prueba t17
  afirmar_nivel "$(veredicto bc_hestia_diag_ruta_repo "" "")" "FALLO" \
    "sin repositorio registrado: FALLO"
}

# El incidente del 2026-09-23: ruta relativa con un remoto local.
test_repo_path_relative_with_local_remote_is_a_failure() {
  nueva_prueba t18
  afirmar_nivel "$(veredicto bc_hestia_diag_ruta_repo "rclone:almacen:hestiacp/" "local")" \
    "FALLO" "ruta relativa con remoto local: FALLO" "RELATIVA"
}

test_repo_path_inside_a_website_is_a_failure() {
  nueva_prueba t19
  afirmar_nivel "$(veredicto bc_hestia_diag_ruta_repo "rclone:almacen:/home/u/web/sitio/copias" "local")" \
    "FALLO" "ruta dentro de una web: FALLO" "sitio web"
}

test_repo_path_with_wrapper_remote_is_a_warning() {
  nueva_prueba t20
  afirmar_nivel "$(veredicto bc_hestia_diag_ruta_repo "rclone:almacen:/IncrementalBackups" "alias")" \
    "AVISO" "remoto envolvente: AVISO"
}

# El mismo caso, ya como veredicto: no puede salir OK, y tampoco es un aviso
# sobre algo que se miró. Es ceguera.
test_repo_path_with_unreadable_remote_type_is_blindness() {
  nueva_prueba t50
  afirmar_nivel "$(veredicto bc_hestia_diag_ruta_repo "rclone:almacen:/IncrementalBackups" "?")" \
    "CIEGO" "tipo del remoto ilegible: CIEGO, nunca OK" "no se pudo leer el tipo"
}

test_repo_path_absolute_on_s3_is_ok() {
  nueva_prueba t21
  afirmar_nivel "$(veredicto bc_hestia_diag_ruta_repo "rclone:almacen:/IncrementalBackups" "s3")" \
    "OK" "ruta absoluta en s3: OK"
}

test_cron_without_a_line_is_a_failure
test_cron_with_impossible_hour_is_a_failure
test_cron_with_impossible_minute_is_a_failure
test_cron_without_absolute_path_is_a_failure
test_cron_in_the_wrong_crontab_is_a_warning
test_cron_well_formed_is_ok_with_the_time
test_snapshot_missing_is_a_failure
test_snapshot_three_days_old_with_daily_cron_is_a_failure
test_snapshot_slightly_late_is_a_warning
test_snapshot_recent_is_ok
test_snapshot_unreadable_date_is_blindness_not_a_warning
test_account_marked_with_key_but_no_repo_is_a_failure
test_account_marked_without_key_or_repo_is_ok
test_account_unmarked_with_repo_is_a_warning
test_account_unmarked_without_repo_is_a_warning
test_account_marked_with_repo_is_ok
test_account_marked_with_repo_but_no_key_is_a_failure
test_orphan_key_on_an_unmarked_account_is_named
test_orphan_key_without_a_registered_repo_is_named
test_no_registered_repo_does_not_repeat_the_unknown
test_no_registered_repo_and_unmarked_says_only_that
test_repo_probe_account_answers_means_it_exists
test_repo_probe_parent_answers_and_account_does_not_means_it_is_gone
test_repo_probe_neither_answers_is_unknown
test_account_with_unreadable_key_is_blindness
test_account_with_unreadable_repo_is_blindness
test_account_with_unreadable_mark_is_blindness
test_account_with_nothing_readable_is_blindness
test_unreadable_mark_is_not_treated_as_zero
test_probe_text_survives_a_sudo_prefix
test_probe_reports_yes_no_and_error_apart
test_probe_accepts_a_pipeline
test_last_snapshot_is_the_most_recent_trimmed
test_snapshot_count_does_not_depend_on_lines
test_empty_array_means_none
test_non_json_output_is_not_read_as_no_backups
test_blind_verdicts_are_counted_apart_from_warnings
test_a_short_call_fails_loudly_instead_of_miscounting
test_exit_code_is_zero_when_everything_was_read_and_fine
test_warnings_alone_do_not_change_the_exit_code
test_a_failure_changes_the_exit_code
test_a_blind_reading_changes_the_exit_code
test_summary_counts_blind_readings_apart
test_summary_says_nothing_about_blindness_when_there_is_none
test_a_healthy_server_reports_zero_of_everything
test_a_mixed_report_counts_the_three_things_apart
test_blindness_alone_is_enough_to_exit_with_one
test_an_unreadable_account_list_stops_the_report
test_an_assumed_period_is_said_out_loud
test_repo_path_missing_is_a_failure
test_repo_path_relative_with_local_remote_is_a_failure
test_repo_path_inside_a_website_is_a_failure
test_repo_path_with_wrapper_remote_is_a_warning
test_repo_path_with_unreadable_remote_type_is_blindness
test_repo_path_absolute_on_s3_is_ok

fin_de_suite
