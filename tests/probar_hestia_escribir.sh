#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_escribir.sh — escribir en el servidor y COMPROBARLO
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. El `ssh` falso del banco (ADR 0009) responde lo
# que cada prueba le deje escrito y registra todo lo que se le pide.
#
# Lo que se vigila es el contrato de bc_hestia_escribir_y_confirmar, y sobre
# todo dos cosas que no se ven leyendo el código:
#   - SIN_CONFIRMAR existe. La orden devuelve 0 y la relectura enseña lo mismo
#     que antes. Es lo que pasa DE VERDAD cuando HestiaCP registra un éxito que
#     no ocurrió (ADR 0017), y no puede acabar contado como HECHO.
#   - Con el ANTES ilegible no se envía NINGUNA orden de escritura. Eso se
#     comprueba en el registro del ssh falso, no en un código de salida.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_escribir.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_escribir =="

MARCA_LECTURA="leer-la-marca"
MARCA_ESCRITURA="escribir-la-marca"

# El guion del `ssh` falso.
#
# Apunta cada orden remota —cruda y sin el escapado— y responde:
#   - a la comprobación `id -u` de bc_ssh_sudo, que sí somos root, para que la
#     orden viaje sin prefijo `sudo` y la prueba vea lo que se compuso;
#   - a una LECTURA, sacando el siguiente valor de la cola $BANCO_TMP/lecturas.
#     Imprime el valor y el centinela BC_FIN, que es lo que haría el shell del
#     servidor de verdad. Un valor '@ilegible' no imprime nada y sale con 1:
#     así se simula que la lectura no llegó a ocurrir.
#   - a una ESCRITURA, con el código que haya en $BANCO_TMP/codigo-escritura.
escribir_guion_ssh() {
  cat > "$BANCO_TMP/guion/ssh.sh" <<FIN
orden="\${!#}"
case "\$orden" in
  *"id -u"*) exit 0 ;;
esac
llana="\${orden//\\\\/}"
printf '%s\\n' "\$llana" >> "\$BANCO_TMP/ordenes-llanas.txt"

case "\$llana" in
  *"$MARCA_LECTURA"*)
    valor="\$(sed -n '1p' "\$BANCO_TMP/lecturas")"
    sed -i '1d' "\$BANCO_TMP/lecturas"
    [[ "\$valor" == "@ilegible" ]] && exit 1
    [[ "\$valor" == "@vacio" ]] || printf '%s\\n' "\$valor"
    printf 'BC_FIN\\n'
    exit 0
    ;;
  *"$MARCA_ESCRITURA"*)
    exit "\$(cat "\$BANCO_TMP/codigo-escritura")"
    ;;
esac
echo "falso ssh: ninguna respuesta prevista para: \$llana" >&2
exit 95
FIN
}

# Prepara un caso y ejecuta bc_hestia_escribir_y_confirmar.
# $1 caso   $2 lo que devuelve la lectura ANTES   $3 la de DESPUÉS
# $4 código con el que sale la orden de escritura
# Valores especiales para $2 y $3: '@ilegible' (la lectura no ocurre) y
# '@vacio' (la lectura ocurre y devuelve nada).
escribir() {
  local caso="$1" antes="$2" despues="$3" codigo="$4"
  rm -f "$BANCO_TMP/ordenes-llanas.txt"
  mkdir -p "$BANCO_TMP/guion" "$BANCO_TMP/$caso"
  printf '%s\n%s\n' "$antes" "$despues" > "$BANCO_TMP/lecturas"
  printf '%s' "$codigo" > "$BANCO_TMP/codigo-escritura"
  escribir_guion_ssh
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    BC_HESTIA_REMOTO=1
    BC_SSH_TARGET="root@servidor-sintetico"
    BC_SSH_CTL="$4/ctl"
    # El juez del paso: el criterio se cumple cuando el texto dice "yes". Con
    # el después vacío se le pregunta si el ANTES ya cumplía.
    juez() {
      local antes="${1:-}" despues="${2:-}"
      if [[ -z "$despues" ]]; then [[ "$antes" == *yes* ]]
      else [[ "$despues" == *yes* ]]
      fi
    }
    bc_hestia_escribir_y_confirmar "paso de prueba" "$2" "$3" juez
  ' _ "$BANCO_RAIZ" "$MARCA_ESCRITURA" "$MARCA_LECTURA" "$BANCO_TMP" 2>/dev/null
}

# Saca un campo de los datos devueltos. Separador: el carácter de unidad
# (0x1F), igual que en el diagnóstico.
campo() {
  local datos="$1" nombre="$2" clave valor
  while IFS=$'\x1f' read -r clave valor; do
    [[ "$clave" == "$nombre" ]] && { printf '%s' "$valor"; return 0; }
  done <<<"$datos"
  return 0
}

# ¿Se le pidió al servidor algo que contenga este texto?
se_pidio() {
  [[ -f "$BANCO_TMP/ordenes-llanas.txt" ]] || { echo no; return 0; }
  if grep -qF -- "$1" "$BANCO_TMP/ordenes-llanas.txt"; then echo si; else echo no; fi
}

# --- SIN_CAMBIO --------------------------------------------------------------
#
# Lo que ya cumple no se toca. Y no es un éxito disfrazado: es «no había nada
# que cambiar», que para quien lo lee es una información distinta.
test_what_already_complies_is_not_touched() {
  nueva_prueba t1
  local datos; datos="$(escribir t1 "BACKUPS_INCREMENTAL='yes'" "BACKUPS_INCREMENTAL='yes'" 0)"
  afirmar_igual "$(campo "$datos" estado)" "SIN_CAMBIO" "ya cumplía: SIN_CAMBIO"
  afirmar_igual "$(se_pidio "$MARCA_ESCRITURA")" "no" \
    "no se envió ninguna orden de escritura al servidor"
  afirmar_igual "$(campo "$datos" codigo)" "" "sin código de orden: no se ejecutó ninguna"
}

# --- HECHO -------------------------------------------------------------------
test_a_confirmed_write_is_done() {
  nueva_prueba t2
  local datos; datos="$(escribir t2 "BACKUPS_INCREMENTAL='no'" "BACKUPS_INCREMENTAL='yes'" 0)"
  afirmar_igual "$(campo "$datos" estado)" "HECHO" "se escribió y la relectura lo confirma"
  afirmar_igual "$(campo "$datos" antes)" "BACKUPS_INCREMENTAL='no'" "el antes queda registrado"
  afirmar_igual "$(campo "$datos" despues)" "BACKUPS_INCREMENTAL='yes'" "y el después también"
  afirmar_igual "$(campo "$datos" etiqueta)" "paso de prueba" "con la etiqueta del paso"
}

# --- SIN_CONFIRMAR -----------------------------------------------------------
#
# EL CASO QUE EXISTE PORQUE HESTIACP REGISTRA ÉXITOS QUE NO OCURRIERON (ADR
# 0017): la orden devuelve 0 y la relectura enseña exactamente lo mismo que
# antes. Contarlo como HECHO sería repetir el fallo que nos trajo hasta aquí;
# contarlo como FALLO mandaría al usuario a reintentar, cuando lo que tiene que
# hacer es ir a mirar por qué el servidor dice una cosa y enseña otra.
test_a_write_that_reports_success_but_changes_nothing() {
  nueva_prueba t3
  local datos; datos="$(escribir t3 "BACKUPS_INCREMENTAL='no'" "BACKUPS_INCREMENTAL='no'" 0)"
  afirmar_igual "$(campo "$datos" estado)" "SIN_CONFIRMAR" \
    "la orden dijo que bien y la relectura no lo confirma"
  afirmar_igual "$(campo "$datos" codigo)" "0" "el código de la orden se guarda como dato: 0"
  afirmar_igual "$(se_pidio "$MARCA_ESCRITURA")" "si" "sí se escribió, y hay que decirlo"
}

# --- FALLO -------------------------------------------------------------------
test_a_failed_write_that_changed_nothing_is_a_failure() {
  nueva_prueba t4
  local datos; datos="$(escribir t4 "BACKUPS_INCREMENTAL='no'" "BACKUPS_INCREMENTAL='no'" 3)"
  afirmar_igual "$(campo "$datos" estado)" "FALLO" "la orden falló y nada cambió"
  afirmar_igual "$(campo "$datos" codigo)" "3" "con su código, como dato"
}

# Una orden que falla pero cuyo cambio SÍ se ve es HECHO: lo que manda es el
# estado del servidor, no lo que diga la orden. Es t3 del revés, y por el
# mismo motivo.
test_a_failing_command_whose_change_is_visible_is_done() {
  nueva_prueba t5
  local datos; datos="$(escribir t5 "BACKUPS_INCREMENTAL='no'" "BACKUPS_INCREMENTAL='yes'" 3)"
  afirmar_igual "$(campo "$datos" estado)" "HECHO" \
    "la orden salió con 3, pero el cambio está: manda el servidor"
}

# --- CIEGO -------------------------------------------------------------------
#
# Sin saber qué había no se puede ni informar ni deshacer: NO se escribe.
test_an_unreadable_before_writes_nothing() {
  nueva_prueba t6
  local datos; datos="$(escribir t6 "@ilegible" "BACKUPS_INCREMENTAL='yes'" 0)"
  afirmar_igual "$(campo "$datos" estado)" "CIEGO" "el antes no se pudo leer: CIEGO"
  afirmar_igual "$(se_pidio "$MARCA_ESCRITURA")" "no" \
    "y NO se envió ninguna orden de escritura al servidor"
}

# Si el que no se puede leer es el DESPUÉS, también es CIEGO, pero queda dicho
# que sí se escribió: eso es lo que el usuario necesita para ir a mirar.
test_an_unreadable_after_says_it_did_write() {
  nueva_prueba t7
  local datos; datos="$(escribir t7 "BACKUPS_INCREMENTAL='no'" "@ilegible" 0)"
  afirmar_igual "$(campo "$datos" estado)" "CIEGO" "el después no se pudo leer: CIEGO"
  afirmar_igual "$(campo "$datos" antes)" "BACKUPS_INCREMENTAL='no'" \
    "pero el antes sigue registrado"
  afirmar_igual "$(campo "$datos" codigo)" "0" "y consta que la orden llegó a ejecutarse"
  afirmar_igual "$(se_pidio "$MARCA_ESCRITURA")" "si" "porque se escribió"
}

# Un valor VACÍO que se lee bien NO es ceguera. Sin esta distinción, un archivo
# de configuración vacío parecería un servidor que no responde.
test_an_empty_value_is_not_blindness() {
  nueva_prueba t8
  local datos; datos="$(escribir t8 "@vacio" "BACKUPS_INCREMENTAL='yes'" 0)"
  afirmar_igual "$(campo "$datos" estado)" "HECHO" "un antes vacío se lee bien y se escribe"
  afirmar_igual "$(campo "$datos" antes)" "" "y el antes queda como lo que era: vacío"
}

test_what_already_complies_is_not_touched
test_a_confirmed_write_is_done
test_a_write_that_reports_success_but_changes_nothing
test_a_failed_write_that_changed_nothing_is_a_failure
test_a_failing_command_whose_change_is_visible_is_done
test_an_unreadable_before_writes_nothing
test_an_unreadable_after_says_it_did_write
test_an_empty_value_is_not_blindness

fin_de_suite
