#!/usr/bin/env bash
# =============================================================================
# tests/probar_respaldo.sh — respaldo de bases de datos (ADR 0009)
# =============================================================================
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_respaldo.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

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

  # No basta con que ALGUNA línea lleve --defaults-file: ninguna línea de
  # volcado (todo lo que no sea la comprobación "mysqldump --help") puede
  # carecer de él, o la contraseña habría podido colarse por otra vía. Antes
  # de leerlo, se exige que el registro exista: si no, grep/wc darían "0"
  # líneas sin coincidir y la afirmación pasaría sin haber comprobado nada.
  afirmar_existe "$BANCO_TMP/registro/mysqldump.log" "hay un registro de mysqldump que inspeccionar"
  local sin_defaults
  sin_defaults="$(grep -v -- '--help' "$BANCO_TMP/registro/mysqldump.log" | grep -cv -- 'defaults-file' || true)"
  afirmar_igual "${sin_defaults:-0}" "0" "todas las líneas de volcado (salvo --help) usan --defaults-file"
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

  # Ahora la conexión a MySQL falla desde el primer SELECT 1. Antes de ese
  # segundo intento se anota el TAMAÑO de cada backup_*.log que ya existía:
  # bc_start_logging nombra el archivo con resolución de segundo
  # (bin/backupctl:280), así que este segundo intento puede caer en el MISMO
  # archivo que el respaldo limpio de arriba si los dos ocurren en el mismo
  # segundo — como pasa aquí, al ser todo sintético. Comparar tamaños en vez
  # de "¿apareció un archivo nuevo?" cubre los dos casos.
  escribir_guion_mysql "$BANCO_TMP" 0 0 1
  local mapa_previo="$BANCO_TMP/t3/logs_previos.tsv" f tam
  : > "$mapa_previo"
  for f in "$perfil"/logs/backup_*.log; do
    [[ -f "$f" ]] || continue
    tam="$(stat -c %s "$f" 2>/dev/null || echo 0)"
    printf '%s\t%s\n' "$f" "$tam" >> "$mapa_previo"
  done

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  afirmar_codigo 2 "$?" "sin conexión a MySQL, el respaldo se aborta con código 2"
  afirmar_intacto "$zip" "$referencia" "el respaldo previo queda byte a byte igual"

  local n
  n="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | wc -l)"
  afirmar_igual "$n" "1" "sigue habiendo exactamente 1 zip"

  afirmar_existe "$perfil/output" "BACKUP_WORK_DIR existe, para poder comprobar que no queda ningún temp_sql_*"
  n="$(find "$perfil/output" -maxdepth 1 -type d -name 'temp_sql_*' | wc -l)"
  afirmar_igual "$n" "0" "no queda ningún directorio temp_sql_* huérfano"

  # El archivo que este intento tocó: uno nuevo (no estaba en el mapa previo)
  # o uno existente cuyo tamaño creció. Cualquier otro backup_*.log —el del
  # respaldo limpio, si quedó aparte— se ignora.
  local log_tocado="" tam_previo_tocado=0 previo
  for f in "$perfil"/logs/backup_*.log; do
    [[ -f "$f" ]] || continue
    tam="$(stat -c %s "$f" 2>/dev/null || echo 0)"
    previo="$(awk -F'\t' -v arch="$f" '$1==arch {print $2}' "$mapa_previo")"
    if [[ -z "$previo" ]]; then
      log_tocado="$f"; tam_previo_tocado=0; break
    elif (( tam > previo )); then
      log_tocado="$f"; tam_previo_tocado="$previo"; break
    fi
  done
  afirmar_igual "$([[ -n "$log_tocado" ]] && echo si || echo no)" "si" "el segundo intento escribió en un log"

  local contenido_nuevo="$BANCO_TMP/t3/log_nuevo.txt"
  : > "$contenido_nuevo"
  [[ -n "$log_tocado" ]] && tail -c "+$((tam_previo_tocado + 1))" "$log_tocado" > "$contenido_nuevo"
  afirmar_contiene "$contenido_nuevo" 'revisa MYSQL_USER' "lo que el segundo intento añadió al log dice 'revisa MYSQL_USER'"
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
  afirmar_codigo 0 "$?" "el respaldo de la prueba de fuga termina en código 0"
  afirmar_igual "$([[ -s "$BANCO_TMP/registro/mysqldump.log" ]] && echo si || echo no)" "si" "hay invocaciones de mysqldump que inspeccionar"

  grep -rqF 'clave-sintetica-no-real-7Q2' "$BANCO_TMP/registro" "$perfil/logs" 2>/dev/null
  afirmar_codigo 1 "$?" "la contraseña del perfil no aparece en ningún registro ni log (grep -rF debe fallar)"
}

test_clean_backup_produces_a_verified_zip
test_dump_error_with_exit_zero_fails_the_backup
test_backup_without_mysql_leaves_previous_backups_untouched
test_profile_password_never_reaches_the_logs

fin_de_suite
