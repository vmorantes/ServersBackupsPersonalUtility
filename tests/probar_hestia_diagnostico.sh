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
test_snapshot_unreadable_date_is_a_warning_not_a_failure() {
  nueva_prueba t11
  local ahora; ahora="$(date -d "2026-09-24 12:00:00" +%s)"
  afirmar_nivel "$(veredicto bc_hestia_diag_instantanea "no-es-una-fecha" "$ahora" "24")" \
    "AVISO" "fecha ilegible: AVISO, no FALLO" "no se pudo leer"
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
test_snapshot_unreadable_date_is_a_warning_not_a_failure
test_account_marked_with_key_but_no_repo_is_a_failure
test_account_marked_without_key_or_repo_is_ok
test_account_unmarked_with_repo_is_a_warning
test_account_unmarked_without_repo_is_a_warning
test_account_marked_with_repo_is_ok
test_repo_path_missing_is_a_failure
test_repo_path_relative_with_local_remote_is_a_failure
test_repo_path_inside_a_website_is_a_failure
test_repo_path_with_wrapper_remote_is_a_warning
test_repo_path_absolute_on_s3_is_ok

fin_de_suite
