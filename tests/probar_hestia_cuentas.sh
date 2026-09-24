#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_cuentas.sh — marcar cuentas para respaldo incremental
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Todo va por el `ssh` falso del banco (ADR 0009).
#
# Este es el paso más peligroso de los ocho, y lo que más se vigila aquí es un
# NO: que a una cuenta SIN la clave BACKUPS_INCREMENTAL no se le envíe NINGUNA
# orden. En HestiaCP 1.10.4, pedir que se cambie una clave que no existe
# dispara una reconstrucción completa de la cuenta —usuario del sistema,
# permisos, usermod, jaula de sftp, colas— y encima puede no escribir nada.
# Eso no puede pasar como efecto colateral de «quiero respaldos».
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_cuentas.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_cuentas =="

# Con un HestiaCP de verdad en esta máquina, bc_hestia_conectar trabajaría en
# LOCAL en vez de irse por el ssh falso, y estas pruebas tocarían el sistema de
# quien las ejecuta.
if [[ -d /usr/local/hestia ]]; then
  echo "probar_hestia_cuentas.sh: existe /usr/local/hestia en esta máquina; se aborta." >&2
  exit 2
fi

HESTIA_FALSO="/usr/local/hestia"

# user.conf sintéticos, en los tres estados que importan.
conf_no()        { printf "NAME='Cliente'\nPACKAGE='default'\nBACKUPS_INCREMENTAL='no'\nSHELL='nologin'\n"; }
conf_si()        { printf "NAME='Cliente'\nPACKAGE='default'\nBACKUPS_INCREMENTAL='yes'\nSHELL='nologin'\n"; }
conf_sin_clave() { printf "NAME='Cliente'\nPACKAGE='default'\nSHELL='nologin'\n"; }

# El guion del `ssh` falso.
#
# Cada cuenta tiene su propio archivo de respuestas en $BANCO_TMP/conf-<cuenta>,
# y una cola por cuenta en $BANCO_TMP/cola-<cuenta> para poder devolver una cosa
# antes de escribir y otra después.
escribir_guion_ssh() {
  cat > "$BANCO_TMP/guion/ssh.sh" <<'FIN'
orden="${!#}"
llana="${orden//\\/}"
case "$llana" in
  *"id -u"*) exit 0 ;;
  "true")    exit 0 ;;
esac
printf '%s\n' "$llana" >> "$BANCO_TMP/ordenes.txt"

# ¿De qué cuenta habla esta orden? data/users/<cuenta>/user.conf
cuenta=""
case "$llana" in
  *data/users/*) cuenta="${llana#*data/users/}"; cuenta="${cuenta%%/*}" ;;
  *v-change-user-config-value*)
    cuenta="${llana#*v-change-user-config-value }"; cuenta="${cuenta%% *}" ;;
esac

case "$llana" in
  *"test -d"*"/usr/local/hestia"*) exit 0 ;;

  *"v-list-users"*) cat "$BANCO_TMP/lista-usuarios"; exit 0 ;;

  *"cp -p"*)
    [[ "$(cat "$BANCO_TMP/copia-$cuenta" 2>/dev/null || echo ok)" == "falla" ]] && exit 1
    printf 'BC_COPIA_OK\n'; exit 0 ;;

  *"v-change-user-config-value"*)
    exit "$(cat "$BANCO_TMP/codigo-$cuenta" 2>/dev/null || echo 0)" ;;

  *"cat "*user.conf*)
    cola="$BANCO_TMP/cola-$cuenta"
    if [[ -s "$cola" ]]; then
      valor="$(sed -n '1p' "$cola")"; sed -i '1d' "$cola"
    else
      valor="$(cat "$BANCO_TMP/conf-$cuenta")"
    fi
    [[ "$valor" == "@ilegible" ]] && exit 1
    cat "$BANCO_TMP/$valor" 2>/dev/null || printf '%s\n' "$valor"
    printf 'BC_FIN\n'
    exit 0 ;;
esac
echo "falso ssh: ninguna respuesta prevista para: $llana" >&2
exit 95
FIN
}

# Define el estado de una cuenta: qué devuelve su user.conf antes y después.
# $1 cuenta   $2 estado inicial (conf-no|conf-si|conf-sin-clave|@ilegible)
# $3 estado tras escribir (opcional: por defecto, el mismo)
#
# TRES respuestas en la cola, no dos: el user.conf de cada cuenta se lee dos
# veces ANTES de escribir —una para la foto que se le enseña al usuario antes
# de confirmar, y otra dentro de la primitiva, justo antes de tocar— y una
# tercera después. Con solo dos, la segunda lectura devolvía ya el resultado y
# la prueba medía otra cosa.
cuenta_con() {
  local u="$1" antes="$2" despues="${3:-$2}"
  printf '%s' "$antes" > "$BANCO_TMP/conf-$u"
  printf '%s\n%s\n%s\n' "$antes" "$antes" "$despues" > "$BANCO_TMP/cola-$u"
}

# Prepara el caso y ejecuta el paso.
# $1 caso   $2 lista de cuentas (separadas por espacios)   $3 modo
preparar() {
  local caso="$1"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt"
  rm -f "$BANCO_TMP"/cola-* "$BANCO_TMP"/conf-* "$BANCO_TMP"/copia-* "$BANCO_TMP"/codigo-*
  conf_no        > "$BANCO_TMP/conf-no"
  conf_si        > "$BANCO_TMP/conf-si"
  conf_sin_clave > "$BANCO_TMP/conf-sin-clave"
  printf '%s\n' "$2" | tr ' ' '\n' | sed '/^$/d' > "$BANCO_TMP/lista-usuarios"
  escribir_guion_ssh
}

marcar() {
  local caso="$1" modo="${2:-}"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/informe.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    HESTIA_DIR="$2"
    DEPLOY_HOST="servidor-sintetico"
    DEPLOY_USER="root"
    BC_PROFILE="Sintetico"
    BC_PROFILE_DIR="$3"
    BC_ASSUME_YES=1
    BC_NO_COLOR=1
    [[ "$4" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_cuentas
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$BANCO_TMP/$caso/perfil" "$modo" 2>&1
}

# Cuántas órdenes de cambio se enviaron, en total o para una cuenta.
cuantos_cambios() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo 0; return 0; }
  grep -c "v-change-user-config-value${1:+ $1}" "$BANCO_TMP/ordenes.txt" || true
}

informe_de() {
  find "$BANCO_TMP/$1/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- cuenta con la clave, en 'no' --------------------------------------------
test_an_unmarked_account_is_marked_and_confirmed() {
  nueva_prueba t1
  preparar t1 "cliente07"
  cuenta_con cliente07 conf-no conf-si
  local salida; salida="$(marcar t1)"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "comprobado leyendo su user.conf" \
    "dice que lo comprobó, no solo que lo hizo"
  afirmar_igual "$(cuantos_cambios cliente07)" "1" "una sola orden para esa cuenta"

  local informe; informe="$(informe_de t1)"
  afirmar_contiene "$informe" "\| Cuenta cliente07 — respaldo incremental \| no \| yes \|" \
    "el informe: qué había y qué hay, por cuenta"
  afirmar_contiene "$informe" "Cómo deshacerlo" "el informe: cómo deshacerlo"
}

# --- cuenta ya marcada --------------------------------------------------------
test_an_already_marked_account_is_not_touched() {
  nueva_prueba t2
  preparar t2 "cliente07"
  cuenta_con cliente07 conf-si
  local salida; salida="$(marcar t2)"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "ya está marcada" "lo dice"
  afirmar_igual "$(cuantos_cambios)" "0" "NINGUNA orden enviada al servidor"
}

# --- LA PRUEBA QUE IMPORTA: cuenta sin la clave ------------------------------
#
# Pedirle a HestiaCP que cambie una clave que no existe dispara una
# reconstrucción completa de la cuenta. No se intenta. Punto.
test_an_account_without_the_key_is_never_touched() {
  nueva_prueba t3
  preparar t3 "cliente07"
  cuenta_con cliente07 conf-sin-clave
  local salida; salida="$(marcar t3)"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_igual "$(cuantos_cambios)" "0" \
    "NINGUNA orden enviada al servidor por una cuenta sin la clave"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:1" "y no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "NO SE PUEDEN MARCAR" "se dice cuáles son"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "RECONSTRUCCIÓN COMPLETA" \
    "y por qué no se intenta"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "v-update-user-package" \
    "se nombra la alternativa"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "esa la ejecutas tú" \
    "y que la ejecuta el usuario, no esta orden"
}

# --- una falla y las demás siguen --------------------------------------------
test_one_failing_account_does_not_stop_the_others() {
  nueva_prueba t4
  preparar t4 "uno dos tres"
  cuenta_con uno  conf-no conf-si
  cuenta_con dos  conf-no conf-no      # la orden dice que bien y no cambia nada
  cuenta_con tres conf-no conf-si
  local salida; salida="$(marcar t4)"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"

  afirmar_igual "$(cuantos_cambios uno)"  "1" "se intentó la primera"
  afirmar_igual "$(cuantos_cambios dos)"  "1" "y la que falla"
  afirmar_igual "$(cuantos_cambios tres)" "1" "y la de después TAMBIÉN"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "2 cuenta\(s\) marcada\(s\), 1 con problemas" \
    "el resumen cuenta las dos cosas"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" \
    "pero el resultado global lo refleja"
}

# --- la copia fechada de una cuenta falla ------------------------------------
test_an_account_whose_backup_copy_fails_is_not_touched() {
  nueva_prueba t5
  preparar t5 "uno dos"
  cuenta_con uno conf-no conf-si
  cuenta_con dos conf-no conf-si
  printf 'falla' > "$BANCO_TMP/copia-uno"
  local salida; salida="$(marcar t5)"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_igual "$(cuantos_cambios uno)" "0" \
    "sin copia a la que volver, esa cuenta NO se toca"
  afirmar_igual "$(cuantos_cambios dos)" "1" "y la otra sí se intenta"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "no se pudo copiar su user.conf" "y se dice"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:1" "el resultado global lo refleja"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_shows_which_accounts_and_why() {
  nueva_prueba t6
  preparar t6 "uno dos tres"
  cuenta_con uno   conf-no
  cuenta_con dos   conf-si
  cuenta_con tres  conf-sin-clave
  local salida; salida="$(marcar t6 ensayo)"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "SE TOCARÍAN \(1\): uno" "dice cuáles se tocarían"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "Ya marcadas, no se tocan \(1\): dos" \
    "cuáles ya están"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "NO SE PUEDEN MARCAR desde aquí \(1\): tres" \
    "y cuáles no se pueden, con el motivo"
  afirmar_igual "$(cuantos_cambios)" "0" "sin tocar nada"
  afirmar_igual "$([[ -n "$(informe_de t6)" ]] && echo si || echo no)" "no" \
    "y sin archivar ningún informe"
}

test_an_unmarked_account_is_marked_and_confirmed
test_an_already_marked_account_is_not_touched
test_an_account_without_the_key_is_never_touched
test_one_failing_account_does_not_stop_the_others
test_an_account_whose_backup_copy_fails_is_not_touched
test_a_dry_run_shows_which_accounts_and_why

fin_de_suite
