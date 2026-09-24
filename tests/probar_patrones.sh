#!/usr/bin/env bash
# =============================================================================
# tests/probar_patrones.sh — patrones de código prohibidos
# =============================================================================
# `$(orden | grep -c . || echo 0)` duplica el "0": grep -c YA imprime "0" en
# su propia salida cuando no hay coincidencias (y sale con 1), así que el
# "|| echo 0" que sigue se ejecuta TAMBIÉN y añade una segunda línea. Quien
# capture eso en una variable y la compare con `(( n > 0 ))` revienta con
# "integer expression expected": son dos líneas, no un número. El arreglo es
# `|| true` (grep -c ya puso el "0") más `"${var:-0}"` donde se usa, para el
# caso —distinto— de que la propia orden no llegara a imprimir nada.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_patrones.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_patrones =="

# Estática: ninguna línea de bin/ ni lib/ combina "grep -c" con "|| echo".
# grep -qrE, no -l/-c: solo importa si existe AL MENOS una línea así, y con
# -l bastaría un archivo para "pasar" sin decir cuántas líneas son.
test_no_grep_c_with_echo_fallback_in_deliverables() {
  nueva_prueba t1
  local hallazgos="$BANCO_TMP/t1/hallazgos.txt"
  : > "$hallazgos"
  grep -rnE 'grep[[:space:]]+-c[A-Za-z]*[^|]*\|\|[[:space:]]*echo' \
    "$BANCO_RAIZ/bin" "$BANCO_RAIZ/lib" > "$hallazgos" 2>/dev/null || true
  afirmar_igual "$(wc -l < "$hallazgos" | tr -d ' ')" "0" \
    "ninguna línea de bin/ o lib/ combina 'grep -c' con '|| echo' ($(cat "$hallazgos" 2>/dev/null | tr '\n' ' | '))"
}

# Funcional: con 0 bases de datos (mysql falso sin ninguna), ni doctor ni
# status deben reventar con "integer expression expected" — el síntoma real
# del patrón de arriba cuando algo lo reintroduce.
escribir_guion_mysql_sin_bases() {
  local tmp="$1"
  mkdir -p "$tmp/guion" "$tmp/registro"
  cat > "$tmp/guion/mysql.sh" <<'GUION'
consulta=""
for ((_i = 1; _i <= $#; _i++)); do
  if [[ "${!_i}" == "-e" ]]; then
    _j=$(( _i + 1 ))
    consulta="${!_j}"
  fi
done
case "$consulta" in
  *'SELECT 1'*) exit 0 ;;
  *'VERSION()'*) echo "10.11.0-sintetico"; exit 0 ;;
  *'SHOW GRANTS'*) echo "GRANT ALL PRIVILEGES ON *.* TO 'prueba'@'%'"; exit 0 ;;
  *'information_schema.schemata'*) exit 0 ;;
  *"NOT IN ('InnoDB')"*) exit 0 ;;
  *) echo "falso mysql (sin bases): consulta inesperada: $consulta" >&2; exit 97 ;;
esac
GUION
}

test_doctor_with_zero_databases_does_not_crash() {
  nueva_prueba t2
  local perfil="$BANCO_TMP/t2/perfil"
  crear_perfil "$perfil"
  escribir_guion_mysql_sin_bases "$BANCO_TMP"

  backupctl_prueba "$perfil" doctor >"$BANCO_TMP/t2/salida.log" 2>&1
  local rc=$?
  # doctor puede terminar en 0 o en 1 (según lo que encuentre): lo único que
  # NO puede pasar es reventar con el error de bash de comparar dos líneas
  # como si fueran un número.
  afirmar_no_contiene "$BANCO_TMP/t2/salida.log" "integer expression expected" \
    "doctor con 0 bases no revienta con 'integer expression expected'"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "0 bases de datos" \
    "doctor informa de 0 bases de datos, no de dos líneas"
  (( rc == 0 || rc == 1 )) \
    && printf 'ok\t%s\n' "doctor termina en un código esperado (0 o 1), no revienta" >> "$BANCO_TMP/.resultados" \
    || printf 'FALLO\t%s\n' "doctor termina en código inesperado: $rc" >> "$BANCO_TMP/.resultados"
  echo "  $([[ $rc == 0 || $rc == 1 ]] && echo ok || echo FALLO): doctor termina en un código esperado (0 o 1)" >&2
}

# --snapshot en la CLI llegaba SIN validar hasta una
# orden remota como root (v-restore-user-full-restic, entre comillas
# simples): una comilla en el valor rompe el entrecomillado. Mismo criterio
# que _v_snapshot en web/server.py: 'latest' o un hash hexadecimal de 8-64.
# Con un valor que no casa, backupctl_prueba no debería ni conectar: si algo
# llegara a invocar ssh, sería la prueba de que la validación no cortó a
# tiempo.
test_snapshot_option_rejects_shell_metacharacters() {
  nueva_prueba t3
  local perfil="$BANCO_TMP/t3/perfil"
  crear_perfil "$perfil"

  backupctl_prueba "$perfil" adoptar --to "root@destino-sintetico" --snapshot "x'y" \
    >"$BANCO_TMP/t3/salida.log" 2>&1
  afirmar_codigo 2 "$?" "adoptar --snapshot con una comilla se aborta (bc_die, código 2)"
  afirmar_igual "$([[ -f "$BANCO_TMP/registro/ssh.log" ]] && echo si || echo no)" "no" \
    "ninguna invocación de ssh llegó a registrarse: se abortó antes de conectar"
}

# S1: con la limpieza ignorando la señal del terminal, un ssh que se cuelga
# de verdad (la red se fue, no un Ctrl-C) ya no depende de que el operador
# interrumpa: ServerAliveInterval/CountMax hacen que la propia conexión se
# cierre sola en, como mucho, unos 60 segundos.
test_bc_ssh_init_has_server_alive_options() {
  nueva_prueba t4
  afirmar_contiene "$BANCO_RAIZ/lib/ssh.sh" "ServerAliveInterval=15" \
    "bc_ssh_init lleva ServerAliveInterval"
  afirmar_contiene "$BANCO_RAIZ/lib/ssh.sh" "ServerAliveCountMax=4" \
    "bc_ssh_init lleva ServerAliveCountMax"
}

test_no_grep_c_with_echo_fallback_in_deliverables
test_doctor_with_zero_databases_does_not_crash
test_snapshot_option_rejects_shell_metacharacters
test_bc_ssh_init_has_server_alive_options

fin_de_suite
