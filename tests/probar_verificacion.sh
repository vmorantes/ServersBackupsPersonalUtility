#!/usr/bin/env bash
# =============================================================================
# tests/probar_verificacion.sh — verificación de respaldos (ADR 0009)
# =============================================================================
# verify (sin --restore-test) no toca MySQL: solo unzip/gzip/find sobre el
# zip. Los guiones de mysql/mysqldump solo hacen falta para GENERAR el
# respaldo de partida.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_verificacion.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

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
  nueva_prueba t1
  local perfil="$BANCO_TMP/t1/perfil"
  local zip; zip="$(generar_respaldo_limpio "$perfil")"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio para verificar"
  [[ -n "$zip" ]] || return 0

  backupctl_prueba "$perfil" verify >"$BANCO_TMP/t1/salida.log" 2>&1
  afirmar_codigo 0 "$?" "verify acepta un respaldo recién hecho, sin alterar"
}

test_verify_detects_an_altered_segment() {
  nueva_prueba t2
  local perfil="$BANCO_TMP/t2/perfil"
  local zip; zip="$(generar_respaldo_limpio "$perfil")"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio para alterar"
  [[ -n "$zip" ]] || return 0

  local extraido="$BANCO_TMP/t2/extraido"
  mkdir -p "$extraido"
  unzip -qq "$zip" -d "$extraido"

  # Se sustituye tienda/data.sql.gz por otro gzip VÁLIDO con distinto
  # contenido: sigue siendo un .gz correcto, pero su suma ya no coincide con
  # la que el propio respaldo declaró en su MANIFEST.
  echo "contenido distinto, sigue siendo un gzip válido" | gzip -9 > "$extraido/tienda/data.sql.gz"
  ( cd "$extraido" && zip -r0 -q "$zip" tienda/data.sql.gz )
  afirmar_codigo 0 "$?" "el reempaquetado del zip alterado termina en código 0"

  backupctl_prueba "$perfil" verify >"$BANCO_TMP/t2/salida.log" 2>&1
  afirmar_codigo 1 "$?" "verify detecta el segmento alterado"
  # El patrón es el del FALLO (lib/verify.sh:110), no una palabra que también
  # sale en el mensaje de éxito (lib/verify.sh:113 dice "sumas ... coinciden").
  afirmar_contiene "$BANCO_TMP/t2/salida.log" 'no coincide' "la salida dice que la suma no coincide"
}

# Un respaldo cuyo propio MANIFEST declara bases con fallos no pasa verify,
# aunque el zip en sí esté íntegro (lib/verify.sh:95-97).
test_verify_rejects_a_backup_with_failed_databases() {
  nueva_prueba t3
  local perfil="$BANCO_TMP/t3/perfil"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP" tienda data

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo con una base fallida para verificar"
  [[ -n "$zip" ]] || return 0

  backupctl_prueba "$perfil" verify >"$BANCO_TMP/t3/salida.log" 2>&1
  afirmar_codigo 1 "$?" "verify rechaza un respaldo que declara bases con fallos"
}

test_verify_accepts_an_untouched_backup
test_verify_detects_an_altered_segment
test_verify_rejects_a_backup_with_failed_databases

fin_de_suite
