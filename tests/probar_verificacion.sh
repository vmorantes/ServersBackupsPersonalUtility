#!/usr/bin/env bash
# =============================================================================
# tests/probar_verificacion.sh — verificación de respaldos (ADR 0009)
# =============================================================================
# verify (sin --restore-test) no toca MySQL: solo unzip/gzip/find sobre el
# zip. Los guiones de mysql/mysqldump solo hacen falta para GENERAR el
# respaldo de partida.
set -u
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh"

echo "== probar_verificacion =="

generar_respaldo_limpio() {
  local perfil="$1"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP"
  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1
}

test_verify_accepts_an_untouched_backup() {
  local perfil="$BANCO_TMP/perfil1"
  local zip; zip="$(generar_respaldo_limpio "$perfil")"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio para verificar"
  [[ -n "$zip" ]] || return 0

  backupctl_prueba "$perfil" verify >"$BANCO_TMP/salida_verify1.log" 2>&1
  afirmar_codigo 0 "$?" "verify acepta un respaldo recién hecho, sin alterar"
}

test_verify_detects_an_altered_segment() {
  local perfil="$BANCO_TMP/perfil2"
  local zip; zip="$(generar_respaldo_limpio "$perfil")"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio para alterar"
  [[ -n "$zip" ]] || return 0

  local extraido="$BANCO_TMP/extraido2"
  mkdir -p "$extraido"
  unzip -qq "$zip" -d "$extraido"

  # Se sustituye tienda/data.sql.gz por otro gzip VÁLIDO con distinto
  # contenido: sigue siendo un .gz correcto, pero su suma ya no coincide con
  # la que el propio respaldo declaró en su MANIFEST.
  echo "contenido distinto, sigue siendo un gzip válido" | gzip -9 > "$extraido/tienda/data.sql.gz"
  ( cd "$extraido" && zip -r0 -q "$zip" tienda/data.sql.gz )

  backupctl_prueba "$perfil" verify >"$BANCO_TMP/salida_verify2.log" 2>&1
  afirmar_codigo 1 "$?" "verify detecta el segmento alterado"
  afirmar_contiene "$BANCO_TMP/salida_verify2.log" 'suma' "la salida menciona la suma que no coincide"
}

test_verify_accepts_an_untouched_backup
test_verify_detects_an_altered_segment

fin_de_suite
