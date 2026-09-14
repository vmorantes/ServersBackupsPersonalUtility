#!/usr/bin/env bash
# =============================================================================
# tests/probar_perfil.sh — carga y validación de un perfil (ADR 0009)
# =============================================================================
set -u
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh"

echo "== probar_perfil =="

# 'config --check' no toca MySQL: no hace falta ningún guion de mysql/mysqldump.
test_config_check_accepts_the_synthetic_profile() {
  local perfil="$BANCO_TMP/perfil1"
  crear_perfil "$perfil"

  backupctl_prueba "$perfil" config --check >"$BANCO_TMP/salida1.log" 2>&1
  afirmar_codigo 0 "$?" "config --check acepta el perfil sintético"
}

test_config_check_requires_mysql_user() {
  local perfil="$BANCO_TMP/perfil2"
  crear_perfil "$perfil"
  # Se sustituye la línea sin tocar el resto del perfil.
  sed -i 's/^export MYSQL_USER=.*/export MYSQL_USER=""/' "$perfil/env.sh"

  backupctl_prueba "$perfil" config --check >"$BANCO_TMP/salida2.log" 2>&1
  afirmar_codigo 1 "$?" "config --check exige MYSQL_USER"
}

test_config_check_accepts_the_synthetic_profile
test_config_check_requires_mysql_user

fin_de_suite
