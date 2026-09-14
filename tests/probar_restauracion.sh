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
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh"

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
  # colada en otra sentencia.
  local encontrada_original=0 f
  for f in "$BANCO_TMP"/registro/mysql.stdin.*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.args ]] && continue
    grep -qF '`tienda`' "$f" && encontrada_original=1
  done
  afirmar_igual "$encontrada_original" "0" "ningún SQL recibido menciona \`tienda\` en ningún sitio"
}

test_restore_into_never_targets_the_original_database

fin_de_suite
