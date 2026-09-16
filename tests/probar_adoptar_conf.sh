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

# Simula la respuesta del centinela SI/NO/basura de bc_ad_leer_conf_destino
# (C2, ronda #028/#030): cualquier invocación cuyos argumentos contengan
# "test -e" imprime $respuesta tal cual (así se puede simular también una
# respuesta inesperada); un "cat" posterior imprime $contenido_cat si se dio.
# Todo lo demás se registra y sale 0, como el resto de guiones de esta suite.
escribir_guion_ssh_centinela() {
  local tmp="$1" respuesta="$2" contenido_cat="${3:-}"
  mkdir -p "$tmp/guion" "$tmp/registro"
  {
    printf 'BC_CENTINELA=%q\n' "$respuesta"
    printf 'BC_CONTENIDO_CAT=%q\n' "$contenido_cat"
    cat <<'GUION'
n=1
while [[ -f "$BANCO_TMP/registro/ssh.stdin.$n" ]]; do n=$(( n + 1 )); done
cat > "$BANCO_TMP/registro/ssh.stdin.$n"
{ printf '%q ' "$@"; echo; } > "$BANCO_TMP/registro/ssh.stdin.$n.args"
case "$*" in
  *'test -e'*)
    printf '%s\n' "$BC_CENTINELA"
    exit 0
    ;;
  *'cat '*)
    [[ -n "$BC_CONTENIDO_CAT" ]] && printf '%s' "$BC_CONTENIDO_CAT"
    exit 0
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
    BC_AD_CONF_ESCRITO=1
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

# C2 (ronda #028/#030): bc_ad_leer_conf_destino con centinela SI, con
# contenido real que debe quedar en BC_AD_CONF_ORIGINAL.
test_leer_conf_destino_si_existe_lee_el_contenido() {
  nueva_prueba t6
  escribir_guion_ssh_centinela "$BANCO_TMP" "SI" "REPO='s3:viejo/restic'
KEEP_DAILY='7'"

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    bc_ad_leer_conf_destino
    printf "EXISTIA=%s\nORIGINAL=%s\n" "$BC_AD_CONF_EXISTIA" "$BC_AD_CONF_ORIGINAL"
  ' _ "$BANCO_RAIZ" </dev/null >"$BANCO_TMP/t6/salida.log" 2>&1
  afirmar_codigo 0 "$?" "bc_ad_leer_conf_destino (SI) termina en código 0"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "^EXISTIA=1$" "BC_AD_CONF_EXISTIA queda en 1"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "REPO='s3:viejo/restic'" "BC_AD_CONF_ORIGINAL trae el contenido leído"
}

# Centinela NO: no hay nada que leer, EXISTIA queda en 0 y ORIGINAL vacío.
test_leer_conf_destino_no_existe() {
  nueva_prueba t7
  escribir_guion_ssh_centinela "$BANCO_TMP" "NO"

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    bc_ad_leer_conf_destino
    printf "EXISTIA=%s\nORIGINAL=[%s]\n" "$BC_AD_CONF_EXISTIA" "$BC_AD_CONF_ORIGINAL"
  ' _ "$BANCO_RAIZ" </dev/null >"$BANCO_TMP/t7/salida.log" 2>&1
  afirmar_codigo 0 "$?" "bc_ad_leer_conf_destino (NO) termina en código 0"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "^EXISTIA=0$" "BC_AD_CONF_EXISTIA queda en 0"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "^ORIGINAL=\[\]$" "BC_AD_CONF_ORIGINAL queda vacío"
}

# ALTA de #023/#028 (A3): una respuesta que no es ni "SI" ni "NO" (fallo de
# red, sudo pidiendo algo, cualquier corte) NO se trata como "no existe":
# bc_die ANTES de leer ni de tocar nada. Ni un solo "cat" debe haberse
# enviado.
test_leer_conf_destino_respuesta_basura_aborta() {
  nueva_prueba t8
  escribir_guion_ssh_centinela "$BANCO_TMP" "esto-no-es-SI-ni-NO"

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    bc_ad_leer_conf_destino
  ' _ "$BANCO_RAIZ" </dev/null >"$BANCO_TMP/t8/salida.log" 2>&1
  afirmar_codigo 2 "$?" "una respuesta que no es SI ni NO aborta (bc_die, código 2)"

  local hay_cat=0 f
  for f in "$BANCO_TMP"/registro/ssh.stdin.*.args; do
    [[ -f "$f" ]] || continue
    grep -qF 'cat' "$f" && hay_cat=1
  done
  afirmar_igual "$hay_cat" "0" "ninguna invocación con 'cat' se envió: se abortó antes de leer"
}

# C2: si EXISTIA=0 y ESCRITO=0 (adoptar nunca llegó a escribir el temporal),
# bc_ad_restaurar_conf no debe mandar ningún "rm": no hay nada que borrar.
test_restaurar_conf_no_manda_rm_si_nunca_se_escribio() {
  nueva_prueba t9
  escribir_guion_ssh "$BANCO_TMP"

  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    BC_AD_DESTINO="destino-sintetico"
    BC_AD_CONF_EXISTIA=0
    BC_AD_CONF_ESCRITO=0
    bc_ad_restaurar_conf
  ' _ "$BANCO_RAIZ" </dev/null >"$BANCO_TMP/t9/salida.log" 2>&1
  afirmar_codigo 0 "$?" "bc_ad_restaurar_conf (EXISTIA=0, ESCRITO=0) termina en código 0"

  local hay_rm=0 f
  for f in "$BANCO_TMP"/registro/ssh.stdin.*.args; do
    [[ -f "$f" ]] || continue
    grep -qF 'rm' "$f" && hay_rm=1
  done
  afirmar_igual "$hay_rm" "0" "ningún 'rm' se envió: adoptar nunca llegó a escribir el temporal"
}

# S2 (ronda #032): bc_ad_informar_bases_faltan es una función PURA (sin
# ssh): con "N M" bien formado, calcula y avisa con los números; con
# CUALQUIER otra cosa (texto suelto, vacío, o un intento de inyectar una
# sustitución de órdenes dentro de una expansión aritmética, el hallazgo de
# una revisión anterior sobre esta misma función), un aviso genérico SIN
# tocar $(( )) sobre el texto crudo. La prueba del intento de inyección
# comprueba que el marcador NUNCA se crea: si $(( )) llegara a evaluar el
# texto tal cual, sí se crearía.
test_informar_bases_faltan_con_numeros_bien_formados() {
  nueva_prueba t10
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    nuevo="cuenta-prueba"
    bc_ad_informar_bases_faltan "$nuevo" "13 0"
  ' _ "$BANCO_RAIZ" >"$BANCO_TMP/t10/salida.log" 2>&1
  afirmar_codigo 0 "$?" "con '13 0' no revienta"
  afirmar_contiene "$BANCO_TMP/t10/salida.log" "faltan 13 de 13 bases" "el mensaje trae los dos números (13 esperadas, 0 logradas, faltan 13)"
}

test_informar_bases_faltan_con_texto_no_numerico() {
  nueva_prueba t11
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    nuevo="cuenta-prueba"
    bc_ad_informar_bases_faltan "$nuevo" "hola"
  ' _ "$BANCO_RAIZ" >"$BANCO_TMP/t11/salida.log" 2>&1
  afirmar_codigo 0 "$?" "con 'hola' no revienta"
  afirmar_contiene "$BANCO_TMP/t11/salida.log" "no se pudo leer cuántas bases faltan" "aviso genérico, sin aritmética"
}

test_informar_bases_faltan_con_texto_vacio() {
  nueva_prueba t12
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    nuevo="cuenta-prueba"
    bc_ad_informar_bases_faltan "$nuevo" ""
  ' _ "$BANCO_RAIZ" >"$BANCO_TMP/t12/salida.log" 2>&1
  afirmar_codigo 0 "$?" "con texto vacío no revienta"
  afirmar_contiene "$BANCO_TMP/t12/salida.log" "no se pudo leer cuántas bases faltan" "aviso genérico, sin aritmética"
}

# El texto malicioso va en comillas simples DENTRO del script (el truco
# '\''...'\''): así el bash INTERNO recibe "a[$(touch ...)]" como texto
# literal, sin que NADA lo ejecute antes de llegar a
# bc_ad_informar_bases_faltan. Si en vez de esto se pusiera entre comillas
# dobles, el propio bash de la prueba ejecutaría el "touch" al construir el
# argumento — y la prueba dejaría de probar lo que dice probar (se detectó
# así, construyéndolo mal la primera vez).
test_informar_bases_faltan_con_intento_de_inyeccion() {
  nueva_prueba t13
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/adoptar.sh"
    nuevo="cuenta-prueba"
    bc_ad_informar_bases_faltan "$nuevo" '\''a[$(touch MARCA-INYECCION)]'\''
  ' _ "$BANCO_RAIZ" >"$BANCO_TMP/t13/salida.log" 2>&1
  afirmar_codigo 0 "$?" "con el intento de inyección no revienta"
  afirmar_contiene "$BANCO_TMP/t13/salida.log" "no se pudo leer cuántas bases faltan" "aviso genérico, sin aritmética"
  afirmar_igual "$([[ -e "$BANCO_TMP/t13/MARCA-INYECCION" ]] && echo si || echo no)" "no" "el marcador NO se creó: \$(( )) nunca tocó el texto crudo"
}

# S3 (ronda #032): la clave que borra el directorio de trabajo remoto
# (adoptar_ws, lib/adoptar.sh) llevaba un "|| true" incrustado en la propia
# orden registrada: eso hacía que bc_cleanup_eval SIEMPRE viera código 0,
# aunque el "rm -rf" remoto fallara de verdad — sin reintento y sin aviso,
# con la clave Restic, la contraseña y el rclone.conf rescatado quedando en
# el destino sin que nadie se enterase.
#
# La línea real (`bc_cleanup_register adoptar_ws "..."`) se EXTRAE de
# lib/adoptar.sh con grep y se ejecuta tal cual, en vez de reproducirla a
# mano: así, si alguien vuelve a poner el "|| true" ahí, esta prueba lo nota
# directamente, sin poder desincronizarse de la línea real (mismo criterio
# que las pruebas de bc_cleanup_all, que extraen la función con sed).
test_adoptar_ws_cleanup_retries_when_remote_rm_fails() {
  nueva_prueba t14
  mkdir -p "$BANCO_TMP/guion" "$BANCO_TMP/registro"
  cat > "$BANCO_TMP/guion/ssh.sh" <<'GUION'
n=1
while [[ -f "$BANCO_TMP/registro/ssh.stdin.$n" ]]; do n=$(( n + 1 )); done
cat > "$BANCO_TMP/registro/ssh.stdin.$n"
{ printf '%q ' "$@"; echo; } > "$BANCO_TMP/registro/ssh.stdin.$n.args"
case "$*" in
  *'rm -rf'*) exit 1 ;;
  *) exit 0 ;;
esac
GUION

  local linea_real
  linea_real="$(grep -F 'bc_cleanup_register adoptar_ws' "$BANCO_RAIZ/lib/adoptar.sh")"
  if [[ -z "$linea_real" ]]; then
    afirmar_igual "no" "si" "se encontró 'bc_cleanup_register adoptar_ws' en lib/adoptar.sh"
    return 0
  fi

  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    trap bc_cleanup_pending EXIT
    BC_SSH_TARGET="destino-sintetico"
    BC_SSH_CTL="$BANCO_TMP/socket-sintetico"
    ws="/root/.adoptar.ABCDEFGH"
    eval "$2"
    bc_cleanup_run adoptar_ws
    exit 0
  ' _ "$BANCO_RAIZ" "$linea_real" >"$BANCO_TMP/t14/salida.log" 2>&1
  afirmar_codigo 0 "$?" "el proceso de prueba sale con código 0 (bc_cleanup_run no propaga el fallo)"

  # printf '%q' escapa el espacio de "rm -rf" (queda "rm\ -rf\ ..."), así
  # que se busca por la ruta de $ws, que no tiene espacios y solo aparece en
  # la invocación de "rm -rf" (la comprobación de "id -u" no la menciona).
  local veces=0 f
  for f in "$BANCO_TMP"/registro/ssh.stdin.*.args; do
    [[ -f "$f" ]] || continue
    grep -qF '.adoptar.ABCDEFGH' "$f" && veces=$(( veces + 1 ))
  done
  afirmar_igual "$veces" "2" "el 'rm -rf' remoto se intentó DOS veces: bc_cleanup_run y, al salir, bc_cleanup_pending"
  afirmar_contiene "$BANCO_TMP/t14/salida.log" "la limpieza 'adoptar_ws' terminó en error" "bc_cleanup_pending avisa nombrando la clave"
}

test_loading_adoptar_does_not_execute_anything
test_restaurar_conf_sends_the_original_text_verbatim
test_restaurar_conf_deletes_when_it_did_not_exist
test_bc_ssh_sudo_delivers_heredoc_intact_when_root
test_bc_ssh_sudo_delivers_heredoc_intact_when_nonroot_with_sudo
test_leer_conf_destino_si_existe_lee_el_contenido
test_leer_conf_destino_no_existe
test_leer_conf_destino_respuesta_basura_aborta
test_restaurar_conf_no_manda_rm_si_nunca_se_escribio
test_informar_bases_faltan_con_numeros_bien_formados
test_informar_bases_faltan_con_texto_no_numerico
test_informar_bases_faltan_con_texto_vacio
test_informar_bases_faltan_con_intento_de_inyeccion
test_adoptar_ws_cleanup_retries_when_remote_rm_fails

fin_de_suite
