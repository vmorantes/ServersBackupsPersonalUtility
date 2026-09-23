#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_repo.sh — validación de repositorios de Restic (T24)
# =============================================================================
# Solo prueba bc_hestia_validar_repo: es una función PURA (sin ssh, sin
# efectos). No hace falta ningún guion de ssh/rclone.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_repo.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_repo =="

# Ejecuta bc_hestia_validar_repo <repo> <tipo> en un subproceso aislado y
# devuelve por stdout "CODIGO:N" seguido del texto del mensaje (stdout+stderr
# mezclados).
ejecutar_validar_repo() {
  local repo="$1" tipo="$2"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/hestia.sh"
    bc_hestia_validar_repo "$2" "$3"
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$repo" "$tipo" 2>&1
}

test_single_quote_is_rejected() {
  nueva_prueba t1
  local salida; salida="$(ejecutar_validar_repo "rclone:x'y:/hestiacp" "local")"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:1" "un repositorio con comilla simple se rechaza"
}

test_shell_metacharacters_are_rejected() {
  nueva_prueba t2
  local caso repo malos=0 f=1
  for caso in ";" '$(' '`' " "; do
    repo="rclone:almacen:/hestiacp${caso}x"
    local salida; salida="$(ejecutar_validar_repo "$repo" "local")"
    echo "$salida" > "$BANCO_TMP/t2/salida-$f.log"
    grep -qF "CODIGO:1" "$BANCO_TMP/t2/salida-$f.log" || malos=$(( malos + 1 ))
    f=$(( f + 1 ))
  done
  afirmar_igual "$malos" "0" "';', '\$(', backtick y espacio se rechazan siempre (0 casos que NO se rechazaron)"
}

test_rclone_repo_without_second_colon_is_rejected() {
  nueva_prueba t3
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen" "local")"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:1" "'rclone:almacen' sin segundo ':' se rechaza"
}

test_rclone_repo_with_empty_remote_name_is_rejected() {
  nueva_prueba t4
  local salida; salida="$(ejecutar_validar_repo "rclone::/x" "local")"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" "'rclone::/x' (nombre de remoto vacío) se rechaza"
}

test_bare_local_path_inside_a_website_is_rejected() {
  nueva_prueba t5
  local salida; salida="$(ejecutar_validar_repo "/home/u/web/sitio/copias" "")"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:1" "una ruta local (sin esquema) dentro de una web se rechaza"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "sitio web" "el mensaje menciona la web"
}

test_exact_web_directory_is_rejected() {
  nueva_prueba t6
  local salida; salida="$(ejecutar_validar_repo "/home/u/web" "")"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:1" "'/home/u/web' exacto (sin nada detrás) se rechaza"
}

# H8: ninguna de estas formas debía poder esquivar la comprobación de la web.
test_glob_evasion_attempts_are_rejected() {
  nueva_prueba t7
  local caso repo malos=0 f=1
  for repo in "//home/u/web/x" "/home/u/./web/x" "/home/u/otro/../web/x"; do
    local salida; salida="$(ejecutar_validar_repo "$repo" "")"
    echo "$salida" > "$BANCO_TMP/t7/salida-$f.log"
    grep -qF "CODIGO:1" "$BANCO_TMP/t7/salida-$f.log" || malos=$(( malos + 1 ))
    f=$(( f + 1 ))
  done
  afirmar_igual "$malos" "0" "'//...', '/./' y '/../' se rechazan siempre (0 casos que NO se rechazaron)"
}

# H4: el tipo se compara en minúsculas.
test_type_local_uppercase_with_relative_path_is_rejected() {
  nueva_prueba t8
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:hestiacp/" "Local")"
  echo "$salida" > "$BANCO_TMP/t8/salida.log"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "CODIGO:1" "tipo 'Local' (mayúscula) + ruta relativa: se rechaza igual"
}

# H4: un remoto envolvente (alias) con ruta absoluta pasa, pero avisando de
# que la ruta absoluta no garantiza nada — la raíz del remoto real manda.
test_type_alias_with_absolute_path_passes_with_warning() {
  nueva_prueba t9
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:/IncrementalBackups" "alias")"
  echo "$salida" > "$BANCO_TMP/t9/salida.log"
  afirmar_contiene "$BANCO_TMP/t9/salida.log" "CODIGO:0" "tipo alias + ruta absoluta: pasa"
  afirmar_contiene "$BANCO_TMP/t9/salida.log" "AVISO" "pero avisa de que la ruta absoluta no garantiza nada"
}

# H5: sin poder determinar el tipo, una ruta relativa se RECHAZA (antes se
# avisaba y se seguía; con -y ese aviso no protege a nadie).
test_unknown_type_with_relative_path_is_rejected() {
  nueva_prueba t10
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:hestiacp/" "")"
  echo "$salida" > "$BANCO_TMP/t10/salida.log"
  afirmar_contiene "$BANCO_TMP/t10/salida.log" "CODIGO:1" "tipo desconocido + ruta relativa: se rechaza"
}

test_type_s3_with_relative_path_passes_without_warning() {
  nueva_prueba t11
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:mi-bucket/hestiacp" "s3")"
  echo "$salida" > "$BANCO_TMP/t11/salida.log"
  afirmar_contiene "$BANCO_TMP/t11/salida.log" "CODIGO:0" "tipo s3 + ruta relativa: pasa"
  afirmar_no_contiene "$BANCO_TMP/t11/salida.log" "AVISO" "y no avisa: s3 no depende del directorio de trabajo"
}

test_absolute_path_without_scheme_passes() {
  nueva_prueba t12
  local salida; salida="$(ejecutar_validar_repo "/IncrementalBackups" "")"
  echo "$salida" > "$BANCO_TMP/t12/salida.log"
  afirmar_contiene "$BANCO_TMP/t12/salida.log" "CODIGO:0" "'/IncrementalBackups' sin esquema: pasa"
}

test_single_quote_is_rejected
test_shell_metacharacters_are_rejected
test_rclone_repo_without_second_colon_is_rejected
test_rclone_repo_with_empty_remote_name_is_rejected
test_bare_local_path_inside_a_website_is_rejected
test_exact_web_directory_is_rejected
test_glob_evasion_attempts_are_rejected
test_type_local_uppercase_with_relative_path_is_rejected
test_type_alias_with_absolute_path_passes_with_warning
test_unknown_type_with_relative_path_is_rejected
test_type_s3_with_relative_path_passes_without_warning
test_absolute_path_without_scheme_passes

fin_de_suite
