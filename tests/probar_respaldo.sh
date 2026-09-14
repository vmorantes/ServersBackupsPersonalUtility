#!/usr/bin/env bash
# =============================================================================
# tests/probar_respaldo.sh — respaldo de bases de datos (ADR 0009)
# =============================================================================
set -u
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh"

echo "== probar_respaldo =="

test_clean_backup_produces_a_verified_zip() {
  nueva_prueba t1
  local perfil="$BANCO_TMP/t1/perfil"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >"$BANCO_TMP/t1/salida.log" 2>&1
  afirmar_codigo 0 "$?" "el respaldo limpio termina en código 0"

  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "se generó un all_databases_*.zip"
  [[ -n "$zip" ]] || return 0

  unzip -p "$zip" MANIFEST.txt > "$BANCO_TMP/t1/manifest.txt" 2>/dev/null
  afirmar_contiene "$BANCO_TMP/t1/manifest.txt" '^bases_con_fallos: 0$' "el manifiesto declara 0 bases con fallos"

  local sumas
  sumas="$(grep -cE '^[0-9a-f]{64}  ' "$BANCO_TMP/t1/manifest.txt" || true)"
  afirmar_igual "$sumas" "12" "el manifiesto trae 12 sumas SHA-256 (2 bases x 6 segmentos)"

  afirmar_contiene "$BANCO_TMP/registro/mysqldump.log" "defaults-file" "cada volcado usa --defaults-file"
}

# LA GARANTÍA CENTRAL (lib/backup.sh:52-60): mysqldump con --force sale con 0
# aunque no haya podido volcar una tabla. bc_dump_segment detecta el error
# leyendo stderr, no el código de salida.
test_dump_error_with_exit_zero_fails_the_backup() {
  nueva_prueba t2
  local perfil="$BANCO_TMP/t2/perfil"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP" tienda data

  backupctl_prueba "$perfil" backup >"$BANCO_TMP/t2/salida.log" 2>&1
  afirmar_codigo 1 "$?" "el volcado que miente con --force hace fallar el respaldo"

  local log
  log="$(find "$perfil/logs" -maxdepth 1 -name 'backup_*.log' | head -1)"
  afirmar_contiene "$log" "FALLO en 'tienda'" "el log del respaldo señala la base con fallo"

  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "el respaldo incompleto igual publica un zip"
  [[ -n "$zip" ]] || return 0

  unzip -p "$zip" MANIFEST.txt > "$BANCO_TMP/t2/manifest.txt" 2>/dev/null
  afirmar_contiene "$BANCO_TMP/t2/manifest.txt" '^bases_con_fallos: 1$' "el manifiesto declara 1 base con fallos"
  afirmar_contiene "$BANCO_TMP/t2/manifest.txt" '^lista_fallos: tienda$' "el manifiesto nombra 'tienda' en la lista de fallos"
}

# Camino de fallo: sin conexión a MySQL, backup se aborta ANTES de tocar nada
# del área de trabajo (lib/backup.sh:264-270, antes de crear BC_TEMP_DIR) y
# sin tocar lo que ya existía en BACKUP_OUTPUT_DIR.
test_backup_without_mysql_leaves_previous_backups_untouched() {
  nueva_prueba t3
  local perfil="$BANCO_TMP/t3/perfil"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo previo de partida"
  [[ -n "$zip" ]] || return 0

  local referencia="$BANCO_TMP/t3/referencia.zip"
  cp -a "$zip" "$referencia"

  # Ahora la conexión a MySQL falla desde el primer SELECT 1.
  escribir_guion_mysql "$BANCO_TMP" 0 0 1

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  afirmar_codigo 2 "$?" "sin conexión a MySQL, el respaldo se aborta con código 2"
  afirmar_intacto "$zip" "$referencia" "el respaldo previo queda byte a byte igual"

  local n
  n="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | wc -l)"
  afirmar_igual "$n" "1" "sigue habiendo exactamente 1 zip"

  n="$(find "$perfil/output" -maxdepth 1 -type d -name 'temp_sql_*' | wc -l)"
  afirmar_igual "$n" "0" "no queda ningún directorio temp_sql_* huérfano"

  local hay_mensaje=0 f
  for f in "$perfil"/logs/backup_*.log; do
    [[ -f "$f" ]] || continue
    grep -q 'revisa MYSQL_USER' "$f" && hay_mensaje=1
  done
  afirmar_igual "$hay_mensaje" "1" "el log del segundo intento dice 'revisa MYSQL_USER'"
}

# Credenciales: nunca en la línea de órdenes ni en un registro
# (20-convenciones.md). MYSQL_PASS va por el archivo --defaults-file
# (lib/mysql.sh:27-59), nunca como argumento; esto lo comprueba desde fuera.
test_profile_password_never_reaches_the_logs() {
  nueva_prueba t4
  local perfil="$BANCO_TMP/t4/perfil"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >/dev/null 2>&1

  grep -rqF 'clave-sintetica-no-real-7Q2' "$BANCO_TMP/registro" "$perfil/logs" 2>/dev/null
  afirmar_codigo 1 "$?" "la contraseña del perfil no aparece en ningún registro ni log (grep -rF debe fallar)"
}

test_clean_backup_produces_a_verified_zip
test_dump_error_with_exit_zero_fails_the_backup
test_backup_without_mysql_leaves_previous_backups_untouched
test_profile_password_never_reaches_the_logs

fin_de_suite
