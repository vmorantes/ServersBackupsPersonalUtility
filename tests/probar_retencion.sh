#!/usr/bin/env bash
# =============================================================================
# tests/probar_retencion.sh — borrado de artefactos antiguos (ADR 0009)
# =============================================================================
# retention no toca MySQL ni abre un log propio: escribe en stdout
# (lib/retention.sh). No hace falta ningún guion de mysql/mysqldump.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_retencion.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

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

  # No basta con contar: hay que ver QUIÉN quedó. preparar_zips da a i=1,2,3
  # los mtimes más recientes (30, 31 y 32 días); si retention conservara los
  # más VIEJOS en vez de los más nuevos, el recuento seguiría dando 3.
  local restantes esperados
  restantes="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' -printf '%f\n' | sort)"
  esperados="$(printf '%s\n' \
    all_databases_20260801_000000.zip \
    all_databases_20260802_000000.zip \
    all_databases_20260803_000000.zip | sort)"
  afirmar_igual "$restantes" "$esperados" "los supervivientes son exactamente los 3 de mtime más reciente"
}

test_retention_dry_run_deletes_nothing
test_retention_keeps_the_minimum

fin_de_suite
