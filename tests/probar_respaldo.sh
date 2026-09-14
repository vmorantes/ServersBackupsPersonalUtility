#!/usr/bin/env bash
# =============================================================================
# tests/probar_respaldo.sh — respaldo de bases de datos (ADR 0009)
# =============================================================================
set -u
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh"

echo "== probar_respaldo =="

test_clean_backup_produces_a_verified_zip() {
  local perfil="$BANCO_TMP/perfil1"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >"$BANCO_TMP/salida1.log" 2>&1
  afirmar_codigo 0 "$?" "el respaldo limpio termina en código 0"

  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "se generó un all_databases_*.zip"
  [[ -n "$zip" ]] || return 0

  unzip -p "$zip" MANIFEST.txt > "$BANCO_TMP/manifest1.txt" 2>/dev/null
  afirmar_contiene "$BANCO_TMP/manifest1.txt" '^bases_con_fallos: 0$' "el manifiesto declara 0 bases con fallos"

  local sumas
  sumas="$(grep -cE '^[0-9a-f]{64}  ' "$BANCO_TMP/manifest1.txt" || true)"
  afirmar_igual "$sumas" "12" "el manifiesto trae 12 sumas SHA-256 (2 bases x 6 segmentos)"

  afirmar_contiene "$BANCO_TMP/registro/mysqldump.log" "defaults-file" "cada volcado usa --defaults-file"
}

# LA GARANTÍA CENTRAL (lib/backup.sh:52-60): mysqldump con --force sale con 0
# aunque no haya podido volcar una tabla. bc_dump_segment detecta el error
# leyendo stderr, no el código de salida.
test_dump_error_with_exit_zero_fails_the_backup() {
  local perfil="$BANCO_TMP/perfil2"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP" tienda data

  backupctl_prueba "$perfil" backup >"$BANCO_TMP/salida2.log" 2>&1
  afirmar_codigo 1 "$?" "el volcado que miente con --force hace fallar el respaldo"

  local log
  log="$(find "$perfil/logs" -maxdepth 1 -name 'backup_*.log' | head -1)"
  afirmar_contiene "$log" "FALLO en 'tienda'" "el log del respaldo señala la base con fallo"

  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "el respaldo incompleto igual publica un zip"
  [[ -n "$zip" ]] || return 0

  unzip -p "$zip" MANIFEST.txt > "$BANCO_TMP/manifest2.txt" 2>/dev/null
  afirmar_contiene "$BANCO_TMP/manifest2.txt" '^bases_con_fallos: 1$' "el manifiesto declara 1 base con fallos"
  afirmar_contiene "$BANCO_TMP/manifest2.txt" '^lista_fallos: tienda$' "el manifiesto nombra 'tienda' en la lista de fallos"
}

test_clean_backup_produces_a_verified_zip
test_dump_error_with_exit_zero_fails_the_backup

fin_de_suite
