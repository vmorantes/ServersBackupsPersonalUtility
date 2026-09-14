#!/usr/bin/env bash
# =============================================================================
# tests/probar_restauracion.sh — restauración con --into (ADR 0009, T8)
# =============================================================================
# T8 (.agents/context/30-trampas.md): un volcado empieza con
# "USE `base_original`;". Enviado a otra base sin quitar esa cabecera, el USE
# manda y el SQL se aplica a la original. restore.sh la quita con sed antes de
# enviar cada segmento (lib/restore.sh:157,163).
#
# El guion de mysql (tests/lib.sh) ya cubre lo que necesita restore: "SELECT
# 1" → 0; el COUNT(*) de existencia del destino → 0 (nunca existe); los
# COUNT(*) finales → 0; y, sin -e, captura el SQL y los argumentos de cada
# invocación en $BANCO_TMP/registro/mysql.stdin.<n>[.args].
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
  local perfil="$BANCO_TMP/perfil1"
  crear_perfil "$perfil"
  escribir_guion_mysql "$BANCO_TMP"
  escribir_guion_mysqldump "$BANCO_TMP"

  backupctl_prueba "$perfil" backup >/dev/null 2>&1
  local zip
  zip="$(find "$perfil/output/mysql_backups" -maxdepth 1 -name 'all_databases_*.zip' | head -1)"
  afirmar_igual "$([[ -n "$zip" ]] && echo si || echo no)" "si" "hay un respaldo limpio para restaurar"
  [[ -n "$zip" ]] || return 0

  backupctl_prueba "$perfil" restore '' tienda --into copia -y >"$BANCO_TMP/salida_restore.log" 2>&1
  afirmar_codigo 0 "$?" "restore --into 'copia' termina en código 0"

  # Ninguna de las invocaciones de SQL por stdin lleva la cabecera USE de la
  # base original: ni el segmento 'database' (se reescribe a 'copia') ni el
  # resto (se elimina por completo).
  local encontrado_use_original=0 f
  for f in "$BANCO_TMP"/registro/mysql.stdin.*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.args ]] && continue
    grep -qE '^USE `tienda`;$' "$f" && encontrado_use_original=1
  done
  afirmar_igual "$encontrado_use_original" "0" "ningún SQL recibido lleva la cabecera USE de 'tienda'"

  # Primer segmento aplicado (orden fijo): 'database'. No recibe la base como
  # argumento de conexión — crea y usa 'copia' dentro del propio SQL.
  afirmar_contiene "$BANCO_TMP/registro/mysql.stdin.1" 'copia' "el segmento database crea o usa 'copia'"
  afirmar_no_contiene "$BANCO_TMP/registro/mysql.stdin.1.args" 'copia' "el segmento database no recibe 'copia' como argumento de conexión"

  # Los otros cinco (tables data functions views others) sí seleccionan
  # 'copia' al conectar: 'copia' es el último argumento de la invocación.
  local todas=1 n
  for n in 2 3 4 5 6; do
    grep -qE -- 'copia[[:space:]]*$' "$BANCO_TMP/registro/mysql.stdin.$n.args" 2>/dev/null || todas=0
  done
  afirmar_igual "$todas" "1" "tables/data/functions/views/others reciben 'copia' como último argumento"
}

test_restore_into_never_targets_the_original_database

fin_de_suite
