#!/usr/bin/env bash
# =============================================================================
# tests/probar_limpieza.sh — registro de limpieza que sobrevive a exit (ADR 0012)
# =============================================================================
# No usa backupctl_prueba ni ningún perfil: prueba lib/core.sh directamente,
# con un `bash -c` que reproduce el `trap … EXIT` de bin/backupctl (52) sin
# cargar el resto de módulos. mysql/mysqldump/ssh no intervienen aquí.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_limpieza.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_limpieza =="

# lib/core.sh dice de sí mismo que «no ejecuta nada por sí mismo» (su propia
# cabecera). Lo comprobamos: cargarlo en un subshell no debe dejar rastro.
test_loading_core_does_not_execute_anything() {
  nueva_prueba t1
  local marcador="$BANCO_TMP/t1/no-deberia-existir"
  ( source "$BANCO_RAIZ/lib/core.sh" )
  afirmar_igual "$([[ -e "$marcador" ]] && echo si || echo no)" "no" "cargar core.sh no ejecuta nada"
}

# Reproduce el camino real: tres limpiezas registradas y una salida por
# bc_die (exit, no return). Las tres tienen que correr, en orden INVERSO al
# de registro (ADR 0012: lo último creado es lo primero en deshacerse).
test_pending_cleanups_run_in_reverse_order_on_bc_die() {
  nueva_prueba t2
  local traza="$BANCO_TMP/t2/traza.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    trap bc_cleanup_pending EXIT
    bc_cleanup_register a "echo A >> $(printf %q "$2")"
    bc_cleanup_register b "echo B >> $(printf %q "$2")"
    bc_cleanup_register c "echo C >> $(printf %q "$2")"
    bc_die "salida deliberada de la prueba"
  ' _ "$BANCO_RAIZ" "$traza" >/dev/null 2>&1
  afirmar_codigo 2 "$?" "el proceso de prueba sale con el código de bc_die (2)"
  afirmar_existe "$traza" "la traza de limpiezas existe"
  local contenido
  contenido="$(tr '\n' ',' < "$traza" 2>/dev/null || true)"
  afirmar_igual "$contenido" "C,B,A," "las limpiezas corrieron en orden inverso al registro"
}

# bc_cleanup_run ejecuta YA y quita la clave: al salir (bc_cleanup_pending vía
# el trap EXIT) no debe volver a correr.
test_cleanup_run_executes_once_and_not_again_on_exit() {
  nueva_prueba t3
  local traza="$BANCO_TMP/t3/traza.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    trap bc_cleanup_pending EXIT
    bc_cleanup_register x "echo X >> $(printf %q "$2")"
    bc_cleanup_run x
    exit 0
  ' _ "$BANCO_RAIZ" "$traza" >/dev/null 2>&1
  afirmar_codigo 0 "$?" "el proceso de prueba sale con código 0"
  afirmar_existe "$traza" "la traza existe (bc_cleanup_run sí ejecutó la limpieza)"
  local veces
  veces="$(grep -c '^X$' "$traza" 2>/dev/null || true)"
  afirmar_igual "${veces:-0}" "1" "bc_cleanup_run ejecutó la limpieza UNA vez, no otra al salir"
}

# bc_cleanup_forget quita la clave SIN ejecutar su limpieza.
test_cleanup_forget_does_not_execute() {
  nueva_prueba t4
  local traza="$BANCO_TMP/t4/traza.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    trap bc_cleanup_pending EXIT
    bc_cleanup_register y "echo Y >> $(printf %q "$2")"
    bc_cleanup_forget y
    exit 0
  ' _ "$BANCO_RAIZ" "$traza" >/dev/null 2>&1
  afirmar_igual "$([[ -e "$traza" ]] && echo si || echo no)" "no" "bc_cleanup_forget no ejecuta la limpieza"
}

# Una limpieza que falla no debe impedir las siguientes (ni las que ya
# estaban antes en el orden de ejecución inverso).
test_a_failing_cleanup_does_not_block_the_rest() {
  nueva_prueba t5
  local traza="$BANCO_TMP/t5/traza.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    trap bc_cleanup_pending EXIT
    bc_cleanup_register a "echo A >> $(printf %q "$2")"
    bc_cleanup_register b "false"
    bc_cleanup_register c "echo C >> $(printf %q "$2")"
    bc_die "salida deliberada de la prueba"
  ' _ "$BANCO_RAIZ" "$traza" >/dev/null 2>&1
  afirmar_existe "$traza" "la traza existe pese al fallo intermedio"
  local contenido
  contenido="$(tr '\n' ',' < "$traza" 2>/dev/null || true)"
  afirmar_igual "$contenido" "C,A," "A y C corrieron pese a que B (entre medias) falló"
}

test_loading_core_does_not_execute_anything
test_pending_cleanups_run_in_reverse_order_on_bc_die
test_cleanup_run_executes_once_and_not_again_on_exit
test_cleanup_forget_does_not_execute
test_a_failing_cleanup_does_not_block_the_rest

fin_de_suite
