#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_repo.sh — validación de rutas de repositorio (T24)
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

# Ejecuta bc_hestia_validar_repo <repo> <tipo> en un subproceso aislado y dice
# su código de salida y su salida (stdout+stderr) por dos líneas: "CODIGO:N" y
# el resto es el texto del mensaje.
ejecutar_validar_repo() {
  local repo="$1" tipo="$2"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/hestia.sh"
    bc_hestia_validar_repo "$2" "$3"
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$repo" "$tipo" 2>&1
}

test_remoto_local_con_ruta_relativa_falla() {
  nueva_prueba t1
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:hestiacp/" "local")"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:1" "remoto local + ruta relativa: falla"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "ABSOLUTA" "el mensaje menciona que hace falta una ruta absoluta"
}

test_remoto_s3_con_ruta_relativa_pasa() {
  nueva_prueba t2
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:hestiacp/" "s3")"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "CODIGO:0" "remoto s3 + ruta relativa: pasa (s3 no depende del directorio de trabajo)"
}

test_remoto_local_con_ruta_absoluta_pasa() {
  nueva_prueba t3
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:/IncrementalBackups" "local")"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:0" "remoto local + ruta absoluta: pasa"
}

test_ruta_dentro_de_una_web_falla() {
  nueva_prueba t4
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:/home/stc/web/example.org/public_html/copias" "local")"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" "ruta dentro de /home/*/web/*: falla"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "sitio web" "el mensaje menciona la web"
}

test_ruta_vacia_falla() {
  nueva_prueba t5
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:" "local")"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:1" "ruta vacía: falla"
}

test_tipo_desconocido_pasa_pero_avisa() {
  nueva_prueba t6
  local salida; salida="$(ejecutar_validar_repo "rclone:almacen:hestiacp/" "")"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:0" "tipo desconocido + ruta relativa: pasa"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "AVISO" "pero avisa de que no se pudo determinar el tipo"
}

test_esquema_no_rclone_pasa_sin_avisar() {
  nueva_prueba t7
  local salida; salida="$(ejecutar_validar_repo "sftp:host:/ruta" "")"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "CODIGO:0" "esquema distinto de rclone: pasa"
  afirmar_no_contiene "$BANCO_TMP/t7/salida.log" "AVISO" "y no dice nada: esta función no valida otros esquemas"
}

test_remoto_local_con_ruta_relativa_falla
test_remoto_s3_con_ruta_relativa_pasa
test_remoto_local_con_ruta_absoluta_pasa
test_ruta_dentro_de_una_web_falla
test_ruta_vacia_falla
test_tipo_desconocido_pasa_pero_avisa
test_esquema_no_rclone_pasa_sin_avisar

fin_de_suite
