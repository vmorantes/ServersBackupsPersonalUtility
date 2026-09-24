#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_sonda.sh — la sonda del repositorio, contra un servidor
# simulado
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Lo que hay es el `ssh` falso del banco (ADR
# 0009): un enlace al despachador que registra cada invocación y responde
# según el guion que deje la prueba. bc_hestia_sondear_repo cree que está
# hablando con una máquina; lo que se comprueba es QUÉ PIDE y CUÁNTAS VECES.
#
# Por qué hace falta esto y no basta con probar las funciones puras: el juicio
# (bc_hestia_juzgar_repo) ya está cubierto en probar_hestia_diagnostico, pero
# nada vigilaba que la segunda sonda se lance SOLO cuando la primera falla, ni
# que la ruta del padre se componga bien, ni que lo que viaja vaya escapado.
# Eso solo se ve mirando lo que sale por el cable.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_sonda.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_sonda =="

# Guion del `ssh` falso. Recibe los argumentos de ssh; el ÚLTIMO es la orden
# remota. Hace dos cosas: dejar la orden cruda en un archivo (para poder
# afirmar sobre ella sin el escapado del registro del despachador) y responder
# lo que la prueba haya pedido en $BANCO_TMP/respuestas.
#
# La comprobación `id -u` es de bc_ssh_sudo: contestando que sí somos root, la
# orden viaja sin prefijo `sudo` y la prueba mira exactamente lo que compone
# bc_hestia_sondear_repo.
escribir_guion_ssh() {
  cat > "$BANCO_TMP/guion/ssh.sh" <<'FIN'
orden="${!#}"
case "$orden" in
  *"id -u"*) exit 0 ;;
esac
llana="${orden//\\/}"
printf '%s\n' "$orden" >> "$BANCO_TMP/ordenes.txt"
printf '%s\n' "$llana"  >> "$BANCO_TMP/ordenes-llanas.txt"
while IFS='|' read -r patron respuesta codigo; do
  [[ -z "$patron" ]] && continue
  case "$llana" in
    *"$patron"*)
      [[ -n "$respuesta" ]] && printf '%s\n' "$respuesta"
      exit "${codigo:-0}"
      ;;
  esac
done < "$BANCO_TMP/respuestas.llanas"
echo "falso ssh: ninguna respuesta prevista para: $orden" >&2
exit 95
FIN
}

# Prepara el caso, ejecuta bc_hestia_sondear_repo y devuelve su resultado.
# $1 nombre del caso   $2 repositorio   $3 cuenta
# Después, en $BANCO_TMP/ordenes.txt quedan las órdenes remotas, una por línea.
sondear() {
  local caso="$1" repo="$2" u="$3"
  rm -f "$BANCO_TMP/ordenes.txt" "$BANCO_TMP/ordenes-llanas.txt"
  mkdir -p "$BANCO_TMP/guion" "$BANCO_TMP/$caso"
  escribir_guion_ssh
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    BC_HESTIA_REMOTO=1
    BC_SSH_TARGET="root@servidor-sintetico"
    BC_SSH_CTL="$4/ctl"
    bc_hestia_sondear_repo "$2" "$3"
  ' _ "$BANCO_RAIZ" "$repo" "$u" "$BANCO_TMP" 2>/dev/null
}

# Tabla de respuestas del servidor simulado: "patrón|lo que imprime|código".
# El patrón se busca dentro de la orden remota.
responder() {
  printf '%s\n' "$@" > "$BANCO_TMP/respuestas.llanas"
}

# Cuántas órdenes remotas se enviaron (sin contar la comprobación de root).
cuantas_ordenes() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo 0; return 0; }
  grep -c . "$BANCO_TMP/ordenes.txt" || true
}

# ¿Alguna de las órdenes enviadas contiene este texto? Se mira la versión SIN
# el escapado (el guion del ssh falso guarda las dos): lo que se afirma aquí es
# qué se pidió, no cómo se escribió. Del escapado se ocupa t5, que ejecuta la
# orden cruda.
alguna_orden_con() {
  [[ -f "$BANCO_TMP/ordenes-llanas.txt" ]] || { echo no; return 0; }
  if grep -qF -- "$1" "$BANCO_TMP/ordenes-llanas.txt"; then echo si; else echo no; fi
}

REPO="rclone:almacen:/IncrementalBackups"

# Si el repositorio de la cuenta está, no hay ninguna razón para molestar al
# padre. Una sonda de más contra el almacenamiento por cada cuenta, en un
# servidor con veinte, se nota.
test_no_second_probe_when_the_account_repo_answers() {
  nueva_prueba t1
  responder "/IncrementalBackups/cliente07/config|BC_SI|0"
  afirmar_igual "$(sondear t1 "$REPO" cliente07)" "1" \
    "la cuenta responde: existe"
  afirmar_igual "$(cuantas_ordenes)" "1" \
    "una sola orden remota: no se preguntó al padre"
}

# El padre responde y la cuenta no: la ausencia es real.
test_parent_is_asked_when_the_account_repo_is_missing() {
  nueva_prueba t2
  responder \
    "/IncrementalBackups/cliente07/config|BC_NO|0" \
    "/IncrementalBackups/|BC_SI|0"
  afirmar_igual "$(sondear t2 "$REPO" cliente07)" "0" \
    "el padre responde y la cuenta no: no existe"
  afirmar_igual "$(cuantas_ordenes)" "2" "se preguntó dos veces"
  afirmar_igual "$(alguna_orden_con "lsf almacen:/IncrementalBackups/ >/dev/null")" "si" \
    "la segunda sonda pregunta por la ruta del padre, sin la cuenta"
}

# Ni el padre ni la cuenta: no se afirma nada.
test_nothing_is_claimed_when_the_parent_does_not_answer() {
  nueva_prueba t3
  responder \
    "/IncrementalBackups/cliente07/config|BC_NO|0" \
    "/IncrementalBackups/||1"
  afirmar_igual "$(sondear t3 "$REPO" cliente07)" "?" \
    "el padre no contesta: no se afirma nada"
}

# H15: un repositorio global recién registrado está VACÍO. Listarlo sin error
# ya demuestra que el almacenamiento responde, y por eso la sonda del padre
# mira si la orden termina bien, no si devuelve líneas.
test_an_empty_parent_that_lists_fine_means_the_repo_is_absent() {
  nueva_prueba t4
  responder \
    "/IncrementalBackups/cliente07/config|BC_NO|0" \
    "/IncrementalBackups/|BC_SI|0"
  afirmar_igual "$(sondear t4 "$REPO" cliente07)" "0" \
    "padre vacío pero listado sin error: el repositorio de la cuenta no existe"
  afirmar_igual "$(alguna_orden_con "lsf almacen:/IncrementalBackups/ >/dev/null")" "si" \
    "la sonda del padre solo mira si el listado termina bien"
  afirmar_igual "$(alguna_orden_con "almacen:/IncrementalBackups/ 2>/dev/null |")" "no" \
    "la sonda del padre no filtra su salida: un padre vacío también cuenta"
}

# Lo que viaja a una orden remota va escapado. Esta cuenta no la produciría
# nunca la validación de la línea de órdenes, pero la sonda no puede confiar en
# eso: el valor viene del panel.
#
# No se afirma sobre el texto: se EJECUTA la orden cruda —la misma cadena que
# recibiría el shell del servidor— con un `id` falso por delante. Si el ';' de
# la cuenta se hubiera convertido en un separador de órdenes, ese `id` dejaría
# su marca. Así la prueba no depende de cómo escape printf, solo de que el
# resultado sea una única orden.
test_what_travels_cannot_inject_a_second_command() {
  nueva_prueba t5
  responder "config|BC_NO|0" "/IncrementalBackups/|BC_NO|0"
  # El nombre lleva un ';' A CADA LADO de la orden colada: con uno solo, lo
  # que quedaría detrás sería 'id/config', que no es una orden y haría que la
  # prueba pasara incluso sin escapar nada.
  sondear t5 "$REPO" 'x;id;z' >/dev/null

  local dir="$BANCO_TMP/t5/bin"; mkdir -p "$dir"
  local marca="$BANCO_TMP/t5/se-ejecuto-id"
  printf '%s\n' '#!/usr/bin/env bash' "touch \"$marca\"" > "$dir/id"
  chmod +x "$dir/id"

  local cruda; cruda="$(sed -n '1p' "$BANCO_TMP/ordenes.txt")"
  PATH="$dir:$PATH" bash -c "$cruda" >/dev/null 2>&1 || true

  afirmar_igual "$([[ -e "$marca" ]] && echo si || echo no)" "no" \
    "el ';' de la cuenta no ejecuta una segunda orden en el servidor"
}

# Una ruta local no sale de la máquina por rclone: se mira el sistema de
# archivos del servidor, y el padre se comprueba con test -d, que un
# directorio vacío también cumple.
test_a_local_repo_asks_the_filesystem() {
  nueva_prueba t6
  responder \
    "/copias/cliente07/config|BC_NO|0" \
    "test -d /copias|BC_SI|0"
  afirmar_igual "$(sondear t6 /copias cliente07)" "0" \
    "ruta local: el padre existe y el de la cuenta no"
  afirmar_igual "$(alguna_orden_con "test -f /copias/cliente07/config")" "si" \
    "la sonda de la cuenta usa test -f sobre el config del repositorio"
}

# Un esquema que no se puede sondear sin la contraseña no inventa un 0, y no
# manda nada al servidor.
test_an_unprobeable_scheme_asks_nothing() {
  nueva_prueba t7
  responder "nada|BC_NO|0"
  afirmar_igual "$(sondear t7 "sftp:copias.example.org:/respaldos" cliente07)" "?" \
    "esquema no sondeable: no se afirma nada"
  afirmar_igual "$(cuantas_ordenes)" "0" "no se envió ninguna orden al servidor"
}

test_no_second_probe_when_the_account_repo_answers
test_parent_is_asked_when_the_account_repo_is_missing
test_nothing_is_claimed_when_the_parent_does_not_answer
test_an_empty_parent_that_lists_fine_means_the_repo_is_absent
test_what_travels_cannot_inject_a_second_command
test_a_local_repo_asks_the_filesystem
test_an_unprobeable_scheme_asks_nothing

fin_de_suite
