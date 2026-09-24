#!/usr/bin/env bash
# =============================================================================
# tests/probar_perfil.sh — carga y validación de un perfil (ADR 0009)
# =============================================================================
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_perfil.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_perfil =="

# 'config --check' no toca MySQL: no hace falta ningún guion de mysql/mysqldump.
test_config_check_accepts_the_synthetic_profile() {
  nueva_prueba t1
  local perfil="$BANCO_TMP/t1/perfil"
  crear_perfil "$perfil"

  backupctl_prueba "$perfil" config --check >"$BANCO_TMP/t1/salida.log" 2>&1
  afirmar_codigo 0 "$?" "config --check acepta el perfil sintético"
}

test_config_check_requires_mysql_user() {
  nueva_prueba t2
  local perfil="$BANCO_TMP/t2/perfil"
  crear_perfil "$perfil"
  # Se sustituye la línea sin tocar el resto del perfil.
  sed -i 's/^export MYSQL_USER=.*/export MYSQL_USER=""/' "$perfil/env.sh"

  backupctl_prueba "$perfil" config --check >"$BANCO_TMP/t2/salida.log" 2>&1
  afirmar_codigo 1 "$?" "config --check exige MYSQL_USER"
}

# USER_NAME sale del env.sh, que se edita a mano, y acaba dentro de un
# `chown -R` que el servidor ejecuta como root (lib/deploy.sh). Un valor con
# un ';' tiene que morir en `config --check`, aquí, y no del otro lado de la
# conexión.
test_config_check_rejects_user_name_with_metacharacters() {
  nueva_prueba t3
  local perfil="$BANCO_TMP/t3/perfil"
  crear_perfil "$perfil"
  sed -i 's/^export USER_NAME=.*/export USER_NAME="x; id"/' "$perfil/env.sh"

  backupctl_prueba "$perfil" config --check >"$BANCO_TMP/t3/salida.log" 2>&1
  afirmar_codigo 1 "$?" "config --check rechaza un USER_NAME con ';'"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "USER_NAME" \
    "el mensaje nombra la variable del perfil que está mal"
}

test_config_check_accepts_the_synthetic_profile
test_config_check_requires_mysql_user
test_config_check_rejects_user_name_with_metacharacters

fin_de_suite
