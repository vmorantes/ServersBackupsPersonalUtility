#!/usr/bin/env bash
# =============================================================================
# tests/probar_restauracion.sh — restauración con --into (ADR 0009, T8)
# =============================================================================
# T8 (.agents/context/30-trampas.md): un volcado empieza con
# "USE `base_original`;". Enviado a otra base sin quitar esa cabecera, el USE
# manda y el SQL se aplica a la original. restore.sh reescribe el segmento
# 'database' (CREATE DATABASE Y USE, dos sustituciones del mismo sed) y quita
# el USE del resto (lib/restore.sh:146-180).
#
# El guion de mysql (tests/lib.sh) ya cubre lo que necesita restore: "SELECT
# 1" → 0; el COUNT(*) de existencia del destino → 0 (nunca existe, salvo que
# se pida lo contrario); los COUNT(*) finales → 0; y, sin -e, captura el SQL
# y los argumentos de cada invocación en $BANCO_TMP/registro/mysql.stdin.<n>[.args].
#
# El orden de los segmentos es fijo (BC_RESTORE_ORDER en lib/restore.sh:
# database tables data functions views others) y los seis existen en un
# respaldo limpio, así que las seis invocaciones por stdin quedan numeradas
# 1..6 en ese orden exacto: no hace falta adivinar cuál es cuál.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_restauracion.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_restauracion =="

test_restore_into_never_targets_the_original_database() {
  nueva_prueba t1
  local perfil="$BANCO_TMP/t1/perfil"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio para restaurar"
  [[ -n "$zip" ]] || return 0

  backupctl_prueba "$perfil" restore '' tienda --into copia -y >"$BANCO_TMP/t1/salida.log" 2>&1
  afirmar_codigo 0 "$?" "restore --into 'copia' termina en código 0"

  # Primer segmento aplicado (orden fijo): 'database'. Las DOS sustituciones
  # del sed de lib/restore.sh:157 tienen que haber actuado: ni el CREATE
  # DATABASE ni el USE pueden seguir nombrando la base original.
  afirmar_contiene "$BANCO_TMP/registro/mysql.stdin.1" '^CREATE DATABASE IF NOT EXISTS `copia`' "el segmento database crea 'copia'"
  afirmar_contiene "$BANCO_TMP/registro/mysql.stdin.1" '^USE `copia`;$' "el segmento database usa 'copia'"
  afirmar_no_contiene "$BANCO_TMP/registro/mysql.stdin.1.args" 'copia' "el segmento database no recibe 'copia' como argumento de conexión"

  # Los otros cinco (tables data functions views others) sí seleccionan
  # 'copia' al conectar: 'copia' es el último argumento de la invocación.
  local todas=1 n
  for n in 2 3 4 5 6; do
    grep -qE -- 'copia[[:space:]]*$' "$BANCO_TMP/registro/mysql.stdin.$n.args" 2>/dev/null || todas=0
  done
  afirmar_igual "$todas" "1" "tables/data/functions/views/others reciben 'copia' como último argumento"

  # Ningún SQL enviado, en ninguno de los seis segmentos, menciona la base
  # original en ningún sitio: ni en un USE, ni en un CREATE DATABASE, ni
  # colada en otra sentencia. Antes: que exista al menos un mysql.stdin.<n>
  # (el 1, el del segmento database) — si no hubiera ninguno, el bucle de
  # abajo no encontraría nada que mirar y la afirmación pasaría sin evidencia.
  afirmar_existe "$BANCO_TMP/registro/mysql.stdin.1" "hay al menos una invocación de SQL por stdin que inspeccionar"
  local encontrada_original=0 f
  for f in "$BANCO_TMP"/registro/mysql.stdin.*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.args ]] && continue
    grep -qF '`tienda`' "$f" && encontrada_original=1
  done
  afirmar_igual "$encontrada_original" "0" "ningún SQL recibido menciona \`tienda\` en ningún sitio"
}

# Camino de fallo: si el destino de --into ya existe y no se pasa -y, restore
# se cancela ANTES de tocar el destino (lib/restore.sh:74-81, sin terminal
# bc_confirm devuelve el valor por defecto 'n' sin preguntar — core.sh:83-101).
test_restore_without_yes_refuses_an_existing_target() {
  nueva_prueba t2
  local perfil="$BANCO_TMP/t2/perfil"
  crear_perfil "$perfil"
  # El destino "existe" con 3 tablas: así se activa el bc_confirm.
  escribir_guion_mysql "$BANCO_TMP" 1 3
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio de partida"
  [[ -n "$zip" ]] || return 0

  backupctl_prueba "$perfil" restore '' tienda --into copia >"$BANCO_TMP/t2/salida.log" 2>&1
  afirmar_codigo 2 "$?" "sin -y, un destino existente hace que restore se cancele"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" 'cancelado' "la salida dice 'cancelado'"

  afirmar_existe "$BANCO_TMP/registro" "el directorio de registro existe, para poder contar sobre él"
  local n
  n="$(find "$BANCO_TMP/registro" -maxdepth 1 -name 'mysql.stdin.*' ! -name '*.args' 2>/dev/null | wc -l)"
  afirmar_igual "$n" "0" "no se envió ningún SQL: la cancelación ocurre antes de tocar el destino"
}

# ADR 0012 / T20: restore extrae el respaldo ANTES de comprobar el destino
# (lib/restore.sh:64-69, antes de 73-82). Al cancelarse, ese temporal quedaba
# en $TMPDIR — lo mostró esta misma prueba antes de la corrección. Ahora
# restore_tmp se registra en cuanto se crea (bc_cleanup_register) y
# bc_cleanup_pending lo deshace desde el trap EXIT de bin/backupctl aunque
# bc_die salga con exit, no con return.
test_restore_cancel_leaves_no_extracted_dump() {
  nueva_prueba t3
  local perfil="$BANCO_TMP/t3/perfil"
  crear_perfil "$perfil"
  # El destino "existe" con 3 tablas: así se activa el bc_confirm y, antes de
  # llegar a él, la extracción ya ha ocurrido.
  escribir_guion_mysql "$BANCO_TMP" 1 3
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio de partida"
  [[ -n "$zip" ]] || return 0

  afirmar_existe "${TMPDIR:-}" "\$TMPDIR (el de la suite, no el del sistema) está definido"
  local antes despues
  antes="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'backupctl-restore.*' 2>/dev/null | wc -l)"

  backupctl_prueba "$perfil" restore '' tienda --into copia >/dev/null 2>&1
  afirmar_codigo 2 "$?" "sin -y, un destino existente cancela restore (tras haber extraído)"

  despues="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'backupctl-restore.*' 2>/dev/null | wc -l)"
  afirmar_igual "$despues" "$antes" "la cancelación no deja ningún backupctl-restore.* huérfano en \$TMPDIR"
}

test_restore_into_never_targets_the_original_database
test_restore_without_yes_refuses_an_existing_target
test_restore_cancel_leaves_no_extracted_dump

fin_de_suite
