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

# Variante que SÍ distingue la comprobación "id -u" del resto: con
# modo_root=0 simula un destino que no es root pero tiene sudo sin
# contraseña (sudo -n true sale 0), que es justo el camino de A1/C1 donde
# bc_ssh_can_sudo_nopass entra en juego. Como el guion anterior, lee SIEMPRE
# su entrada estándar entera y la registra junto a sus argumentos, para poder
# comprobar qué invocación recibió qué.
escribir_guion_ssh_modo() {
  local tmp="$1" modo_root="${2:-1}"
  mkdir -p "$tmp/guion" "$tmp/registro"
  {
    printf 'BC_MODO_ROOT=%q\n' "$modo_root"
    cat <<'GUION'
n=1
while [[ -f "$BANCO_TMP/registro/ssh.stdin.$n" ]]; do n=$(( n + 1 )); done
cat > "$BANCO_TMP/registro/ssh.stdin.$n"
{ printf '%q ' "$@"; echo; } > "$BANCO_TMP/registro/ssh.stdin.$n.args"
case "$*" in
  *'id -u'*)
    [[ "$BC_MODO_ROOT" == "1" ]] && exit 0 || exit 1
    ;;
  *)
    exit 0
    ;;
esac
GUION
  } > "$tmp/guion/ssh.sh"
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

# T2 en su raíz (ronda de #028/#030, C1): bc_ssh_sudo (no solo
# bc_ssh_sudo_stdin) tiene un llamador real con contenido por heredoc
# (lib/adoptar.sh:1451, bc_adoptar_registrar) — un `< /dev/null` puesto ANTES
# de un heredoc no tiene ningún efecto (bash aplica la ÚLTIMA redirección
# sobre el mismo descriptor), así que ese heredoc SIEMPRE fue el contenido
# real que debía llegar a la orden final. Antes de C1, la comprobación
# interna de "id -u" (sin cerrar su propia entrada) se lo comía entero. Esta
# prueba reproduce ese caso exacto: bc_ssh_sudo "bash -s 'cuenta'" con un
# heredoc de varias líneas, camino ROOT (bc_ssh "$@" hereda el mismo stdin
# que recibió bc_ssh_sudo).
test_bc_ssh_sudo_delivers_heredoc_intact_when_root() {
  nueva_prueba t4
  escribir_guion_ssh_modo "$BANCO_TMP" 1

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    bc_ssh_sudo "bash -s '"'"'cuenta'"'"'" <<'"'"'REMOTO'"'"'
H=/usr/local/hestia
echo linea-una
echo linea-dos
REMOTO
  ' _ "$BANCO_RAIZ" >"$BANCO_TMP/t4/salida.log" 2>&1
  afirmar_codigo 0 "$?" "bc_ssh_sudo (root) termina en código 0"

  # La invocación que importa es la que LLEVA 'cuenta' en sus argumentos (la
  # orden final, "bash -s 'cuenta'"): buscar por "cualquier invocación con
  # contenido" no sirve, porque si la comprobación de "id -u" o "sudo -n
  # true" se comen el heredoc, su propio registro queda con ESE MISMO texto
  # y una comparación solo por contenido no distinguiría el error (esto pasó:
  # las dos primeras versiones de esta prueba no detectaban M27/M27b).
  local recibido="" f
  for f in "$BANCO_TMP"/registro/ssh.stdin.*.args; do
    [[ -f "$f" ]] || continue
    grep -qF 'cuenta' "$f" && recibido="${f%.args}"
  done
  afirmar_igual "$([[ -n "$recibido" ]] && echo si || echo no)" "si" "hubo una invocación con 'bash -s cuenta' en sus argumentos"
  [[ -n "$recibido" ]] || return 0

  local esperado="$BANCO_TMP/t4/esperado.txt"
  printf '%s\n' "H=/usr/local/hestia" "echo linea-una" "echo linea-dos" > "$esperado"
  afirmar_intacto "$recibido" "$esperado" "el heredoc llega ÍNTEGRO a la invocación final (camino root)"
}

# Mismo caso, pero el destino NO es root y tiene sudo sin contraseña: pasa
# por bc_ssh_can_sudo_nopass (elif) y por `bc_ssh "sudo -n $*"`, sin volver a
# redirigir su entrada — hereda la del llamador. Es el camino que A1 (#023)
# señalaba abierto y que C1 cierra en el helper compartido.
test_bc_ssh_sudo_delivers_heredoc_intact_when_nonroot_with_sudo() {
  nueva_prueba t5
  escribir_guion_ssh_modo "$BANCO_TMP" 0

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    bc_ssh_sudo "bash -s '"'"'cuenta'"'"'" <<'"'"'REMOTO'"'"'
H=/usr/local/hestia
echo linea-una
echo linea-dos
REMOTO
  ' _ "$BANCO_RAIZ" >"$BANCO_TMP/t5/salida.log" 2>&1
  afirmar_codigo 0 "$?" "bc_ssh_sudo (no-root, sudo sin contraseña) termina en código 0"

  # Mismo criterio que en t4: identificar la invocación final por sus
  # argumentos ('cuenta'), no por ser la primera con contenido no vacío.
  local recibido="" f
  for f in "$BANCO_TMP"/registro/ssh.stdin.*.args; do
    [[ -f "$f" ]] || continue
    grep -qF 'cuenta' "$f" && recibido="${f%.args}"
  done
  afirmar_igual "$([[ -n "$recibido" ]] && echo si || echo no)" "si" "hubo una invocación con 'bash -s cuenta' en sus argumentos"
  [[ -n "$recibido" ]] || return 0

  local esperado="$BANCO_TMP/t5/esperado.txt"
  printf '%s\n' "H=/usr/local/hestia" "echo linea-una" "echo linea-dos" > "$esperado"
  afirmar_intacto "$recibido" "$esperado" "el heredoc llega ÍNTEGRO a la invocación final (camino no-root con sudo)"
}

test_loading_adoptar_does_not_execute_anything
test_restaurar_conf_sends_the_original_text_verbatim
test_restaurar_conf_deletes_when_it_did_not_exist
test_bc_ssh_sudo_delivers_heredoc_intact_when_root
test_bc_ssh_sudo_delivers_heredoc_intact_when_nonroot_with_sudo

fin_de_suite
