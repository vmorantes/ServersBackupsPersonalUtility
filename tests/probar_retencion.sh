#!/usr/bin/env bash
# =============================================================================
# tests/probar_retencion.sh — borrado de artefactos antiguos (ADR 0009)
# =============================================================================
# retention no toca MySQL ni abre un log propio: escribe en stdout
# (lib/retention.sh). No hace falta ningún guion de mysql/mysqldump.
set -u
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh"

echo "== probar_retencion =="

# Cinco respaldos con mtime de 30 a 34 días atrás: todos superan
# BACKUP_RETENTION_DAYS=14, pero BACKUP_KEEP_MIN=3 protege a los 3 más
# recientes aunque sean viejos (lib/retention.sh: "mínimo a conservar").
preparar_zips() {
  local dir="$1" i dias f
  mkdir -p "$dir"
  for i in 1 2 3 4 5; do
    dias=$(( 29 + i ))
    f="$dir/all_databases_202608$(printf '%02d' "$i")_000000.zip"
    echo "contenido cualquiera $i" > "$f"
    touch -d "${dias} days ago" "$f"
  done
}

contar_zips() {
  find "$1" -maxdepth 1 -name 'all_databases_*.zip' | wc -l
}

test_retention_dry_run_deletes_nothing() {
  nueva_prueba t1
  local perfil="$BANCO_TMP/t1/perfil"
  crear_perfil "$perfil"
  preparar_zips "$perfil/output/mysql_backups"

  # --dry-run debe ser el PRIMER argumento (bin/backupctl:359).
  backupctl_prueba "$perfil" retention --dry-run >"$BANCO_TMP/t1/salida.log" 2>&1
  afirmar_codigo 0 "$?" "retention --dry-run termina en código 0"
  afirmar_igual "$(contar_zips "$perfil/output/mysql_backups")" "5" "--dry-run no borra ninguno de los 5 respaldos"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" 'simulaci' "la salida menciona la simulación"
}

test_retention_keeps_the_minimum() {
  nueva_prueba t2
  local perfil="$BANCO_TMP/t2/perfil"
  crear_perfil "$perfil"
  preparar_zips "$perfil/output/mysql_backups"

  backupctl_prueba "$perfil" retention >"$BANCO_TMP/t2/salida.log" 2>&1
  afirmar_codigo 0 "$?" "retention termina en código 0"
  afirmar_igual "$(contar_zips "$perfil/output/mysql_backups")" "3" "quedan exactamente los 3 más recientes (BACKUP_KEEP_MIN)"
}

test_retention_dry_run_deletes_nothing
test_retention_keeps_the_minimum

fin_de_suite
