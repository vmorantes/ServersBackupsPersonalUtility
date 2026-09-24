#!/usr/bin/env bash
# =============================================================================
# tests/probar_validacion.sh — validadores de opciones de la línea de órdenes
# =============================================================================
# bc_valido_destino, bc_valido_usuario, bc_valido_usuarios y bc_valido_cuantas
# (lib/core.sh) son funciones PURAS: devuelven 0/1 y no imprimen nada. No hace
# falta ningún guion de ssh ni de mysql para probarlas.
#
# Lo que defienden no es cosmético: estos valores acaban dentro de órdenes que
# el servidor de destino ejecuta como root, y en la línea de `ssh` de esta
# misma máquina (donde un valor que empiece por guion se convierte en una
# opción de ssh, no en un destino).
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_validacion.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_validacion =="

# Ejecuta <validador> <valor> en un subproceso aislado y devuelve "pasa" o
# "falla" por stdout. En subproceso a propósito: si un validador tuviera algún
# efecto (no debería: son puros), no contaminaría a la siguiente prueba.
ejecutar_validador() {
  local fn="$1" valor="$2"
  bash -c '
    source "$1/lib/core.sh"
    if "$2" "$3"; then echo pasa; else echo falla; fi
  ' _ "$BANCO_RAIZ" "$fn" "$valor" 2>&1
}

# Comprueba una tabla de casos de golpe: cuenta cuántos NO dan el resultado
# esperado, y afirma que ese número es cero. Así una tabla de ocho casos es
# una sola afirmación legible, y el mensaje dice cuál falló.
comprobar_tabla() {
  local fn="$1" esperado="$2" desc="$3"; shift 3
  local valor obtenido malos=0 detalle=""
  for valor in "$@"; do
    obtenido="$(ejecutar_validador "$fn" "$valor")"
    if [[ "$obtenido" != "$esperado" ]]; then
      malos=$(( malos + 1 ))
      detalle+=" [$valor]"
    fi
  done
  afirmar_igual "$malos" "0" "$desc (casos que NO dieron '$esperado':${detalle:- ninguno})"
}

test_destino_accepts_valid_targets() {
  nueva_prueba t1
  comprobar_tabla bc_valido_destino pasa "destino: usuario@host y host sueltos se aceptan" \
    "root@servidor.example.org" "servidor.example.org"
}

# El caso que motiva todo: ssh interpreta "-oProxyCommand=..." como una opción
# suya, así que un destino no puede empezar por guion.
test_destino_rejects_leading_dash_and_metacharacters() {
  nueva_prueba t2
  comprobar_tabla bc_valido_destino falla "destino: guion inicial, espacios, ';' y vacío se rechazan" \
    "-oProxyCommand=x" "root@-oProxyCommand" "-v" "root@servidor example" "root@serv;id" ""
}

test_usuario_accepts_valid_accounts() {
  nueva_prueba t3
  comprobar_tabla bc_valido_usuario pasa "usuario: una cuenta normal y una de un solo carácter se aceptan" \
    "cliente07" "a"
}

test_usuario_rejects_metacharacters_and_overlong() {
  nueva_prueba t4
  comprobar_tabla bc_valido_usuario falla "usuario: comillas, ';', espacios, guion inicial y 33 caracteres se rechazan" \
    "x'y" "x;id" "x y" "-x" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

test_usuarios_accepts_valid_lists() {
  nueva_prueba t5
  comprobar_tabla bc_valido_usuarios pasa "usuarios: lista de varias y lista de una se aceptan" \
    "a,b,c" "a"
}

test_usuarios_rejects_empty_items_and_metacharacters() {
  nueva_prueba t6
  comprobar_tabla bc_valido_usuarios falla "usuarios: elementos vacíos y ';' se rechazan" \
    "a,,b" ",a" "a,b;id"
}

test_cuantas_accepts_one_to_three_digits() {
  nueva_prueba t7
  comprobar_tabla bc_valido_cuantas pasa "cuantas: 1 y 999 se aceptan" \
    "1" "999"
}

test_cuantas_rejects_zero_padding_and_out_of_range() {
  nueva_prueba t8
  comprobar_tabla bc_valido_cuantas falla "cuantas: 0, 1000, 01, -1 y 1a se rechazan" \
    "0" "1000" "01" "-1" "1a"
}

# Punto de entrada real: `backupctl adoptar-registrar --usuario-hestia "x;id"`
# tiene que morir en la validación, ANTES de cargar el perfil y sin invocar
# ssh. Se usa backupctl_prueba (perfil sintético dentro del banco, PATH con
# las órdenes falsas delante): si algo llegara a conectar, quedaría registrado
# en registro/ssh.log y esta prueba lo vería.
test_cli_rejects_invalid_hestia_user_before_connecting() {
  nueva_prueba t9
  local perfil="$BANCO_TMP/t9/perfil"
  crear_perfil "$perfil"

  backupctl_prueba "$perfil" adoptar-registrar --to "root@destino-sintetico" \
    --usuario-hestia "x;id" >"$BANCO_TMP/t9/salida.log" 2>&1
  afirmar_codigo 2 "$?" "--usuario-hestia con ';' sale con código 2 (bc_die)"
  afirmar_contiene "$BANCO_TMP/t9/salida.log" "cuenta de HestiaCP no válida" \
    "el mensaje dice qué forma se esperaba"
  afirmar_igual "$([[ -f "$BANCO_TMP/registro/ssh.log" ]] && echo si || echo no)" "no" \
    "ninguna invocación de ssh: se abortó antes de conectar"
}

test_destino_accepts_valid_targets
test_destino_rejects_leading_dash_and_metacharacters
test_usuario_accepts_valid_accounts
test_usuario_rejects_metacharacters_and_overlong
test_usuarios_accepts_valid_lists
test_usuarios_rejects_empty_items_and_metacharacters
test_cuantas_accepts_one_to_three_digits
test_cuantas_rejects_zero_padding_and_out_of_range
test_cli_rejects_invalid_hestia_user_before_connecting

fin_de_suite
