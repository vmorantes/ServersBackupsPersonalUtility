#!/usr/bin/env bash
# =============================================================================
# tests/probar_adoptar_conf.sh — devolver restic.conf del destino (T2, ADR 0012)
# =============================================================================
# Carga SOLO lib/core.sh, lib/ssh.sh y lib/adoptar.sh: es lo único que
# necesita bc_ad_restaurar_conf, sin el resto de backupctl ni MySQL.
#
# El guion de ssh imita al ssh REAL: lee SIEMPRE su entrada estándar entera
# (como haría el cliente real, reenviándola al servidor) y la guarda junto a
# sus argumentos; sale 0, como si el destino respondiera siendo root. Con
# eso, bc_ssh_sudo/bc_ssh_sudo_stdin toman siempre el camino "ya somos root":
# una llamada a ssh por la comprobación de "id -u", y otra por la orden real.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_adoptar_conf.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_adoptar_conf =="

escribir_guion_ssh() {
  local tmp="$1"
  mkdir -p "$tmp/guion" "$tmp/registro"
  cat > "$tmp/guion/ssh.sh" <<'GUION'
n=1
while [[ -f "$BANCO_TMP/registro/ssh.stdin.$n" ]]; do n=$(( n + 1 )); done
cat > "$BANCO_TMP/registro/ssh.stdin.$n"
{ printf '%q ' "$@"; echo; } > "$BANCO_TMP/registro/ssh.stdin.$n.args"
exit 0
GUION
}

# lib/adoptar.sh solo declara funciones y variables vacías al cargarse
# (guarda BC_ADOPTAR_LOADED, sin mkdir ni red): comprobado igual que
# probar_limpieza.sh comprueba lib/core.sh.
test_loading_adoptar_does_not_execute_anything() {
  nueva_prueba t1
  local marcador="$BANCO_TMP/t1/no-deberia-existir"
  ( source "$BANCO_RAIZ/lib/core.sh"; source "$BANCO_RAIZ/lib/ssh.sh"; source "$BANCO_RAIZ/lib/adoptar.sh" )
  afirmar_igual "$([[ -e "$marcador" ]] && echo si || echo no)" "no" "cargar core+ssh+adoptar no ejecuta nada"
}

# CRÍTICO DE SEGURIDAD (T2, hallazgo de la ronda de #022): antes de este
# arreglo, bc_ad_restaurar_conf escribía con bc_ssh_sudo, cuya comprobación
# interna de "id -u" no cierra su entrada estándar — se comía el restic.conf
# original y el destino se quedaba con el archivo VACÍO, mientras la orden
# informaba de éxito. Con bc_ssh_sudo_stdin, la comprobación SÍ va con
# </dev/null y el contenido llega intacto a la invocación real.
test_restaurar_conf_sends_the_original_text_verbatim() {
  nueva_prueba t2
  escribir_guion_ssh "$BANCO_TMP"
  local original="linea uno
linea dos con 'comillas' y REPO='s3:ejemplo/restic'
linea tres"

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    BC_AD_DESTINO="destino-sintetico"
    BC_AD_CONF_EXISTIA=1
    BC_AD_CONF_ORIGINAL="$2"
    bc_ad_restaurar_conf
  ' _ "$BANCO_RAIZ" "$original" </dev/null >"$BANCO_TMP/t2/salida.log" 2>&1
  afirmar_codigo 0 "$?" "bc_ad_restaurar_conf termina en código 0"

  local escritura="" f
  for f in "$BANCO_TMP"/registro/ssh.stdin.*.args; do
    [[ -f "$f" ]] || continue
    grep -qF 'restic.conf' "$f" && grep -qF 'cat' "$f" && escritura="${f%.args}"
  done
  afirmar_igual "$([[ -n "$escritura" ]] && echo si || echo no)" "si" "hubo una invocación de ssh que escribe restic.conf"
  [[ -n "$escritura" ]] || return 0

  local esperado="$BANCO_TMP/t2/esperado.txt"
  printf '%s\n' "$original" > "$esperado"
  afirmar_intacto "$escritura" "$esperado" "el texto recibido es EXACTAMENTE el original (bc_ad_restaurar_conf añade un salto de línea final con printf '%s\\n')"
}

# Cuando el destino NO tenía restic.conf propio, se borra el temporal — y
# nunca se manda un "cat >" con contenido que no viene a cuento.
test_restaurar_conf_deletes_when_it_did_not_exist() {
  nueva_prueba t3
  escribir_guion_ssh "$BANCO_TMP"

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    BC_AD_DESTINO="destino-sintetico"
    BC_AD_CONF_EXISTIA=0
    BC_AD_CONF_ORIGINAL=""
    bc_ad_restaurar_conf
  ' _ "$BANCO_RAIZ" </dev/null >"$BANCO_TMP/t3/salida.log" 2>&1
  afirmar_codigo 0 "$?" "bc_ad_restaurar_conf termina en código 0"

  # printf '%q' escapa los espacios de cada argumento (queda "rm\ -f\ ..."),
  # así que se busca por trozos sin espacio, no por la frase completa.
  local hay_borrado=0 hay_escritura=0 f
  for f in "$BANCO_TMP"/registro/ssh.stdin.*.args; do
    [[ -f "$f" ]] || continue
    grep -qF 'restic.conf' "$f" || continue
    grep -qF 'rm' "$f" && hay_borrado=1
    grep -qF 'cat' "$f" && hay_escritura=1
  done
  afirmar_igual "$hay_borrado" "1" "se envió el borrado del restic.conf temporal"
  afirmar_igual "$hay_escritura" "0" "ningún 'cat >' se envió (no había nada que devolver)"
}

test_loading_adoptar_does_not_execute_anything
test_restaurar_conf_sends_the_original_text_verbatim
test_restaurar_conf_deletes_when_it_did_not_exist

fin_de_suite
