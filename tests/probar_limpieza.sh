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

# bc_cleanup_eval restaura el errexit de quien llama TAL COMO ESTABA, no lo
# impone: bc_cleanup_all hace `set +e` antes de bc_cleanup_pending
# (bin/backupctl), así que debe seguir en +e después. Se mira $- (sin
# provocar ningún fallo real: "true" siempre sale bien).
test_cleanup_eval_preserves_the_callers_errexit() {
  nueva_prueba t6
  local estado_mas="$BANCO_TMP/t6/mas.txt" estado_menos="$BANCO_TMP/t6/menos.txt"

  # Caso 1: quien llama tiene errexit DESACTIVADO en el momento de limpiar.
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    set +e
    bc_cleanup_register a "true"
    bc_cleanup_run a
    case "$-" in *e*) echo on ;; *) echo off ;; esac > "$2"
  ' _ "$BANCO_RAIZ" "$estado_menos" >/dev/null 2>&1
  afirmar_existe "$estado_menos" "el caso 'set +e' dejó su archivo de estado"
  afirmar_igual "$(cat "$estado_menos" 2>/dev/null || true)" "off" "tras limpiar, sigue en 'set +e' (no se activa errexit)"

  # Caso 2: quien llama tiene errexit ACTIVADO en el momento de limpiar.
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    bc_cleanup_register a "true"
    bc_cleanup_run a
    case "$-" in *e*) echo on ;; *) echo off ;; esac > "$2"
  ' _ "$BANCO_RAIZ" "$estado_mas" >/dev/null 2>&1
  afirmar_existe "$estado_mas" "el caso 'set -e' dejó su archivo de estado"
  afirmar_igual "$(cat "$estado_mas" 2>/dev/null || true)" "on" "tras limpiar, sigue en 'set -e' (se restaura errexit)"
}

# Reproduce el `trap … EXIT` real de bin/backupctl (52) y su trampa INT/TERM
# (53): una señal TERM también tiene que dejar las limpiezas pendientes
# hechas, no solo bc_die (ronda de #022: T20 hablaba de "muere con exit o por
# señal", y hasta ahora solo se probaba lo primero).
test_pending_cleanups_run_on_sigterm() {
  nueva_prueba t7
  local traza="$BANCO_TMP/t7/traza.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    trap bc_cleanup_pending EXIT
    trap "exit 130" INT TERM
    bc_cleanup_register a "echo A >> $(printf %q "$2")"
    bc_cleanup_register b "echo B >> $(printf %q "$2")"
    kill -TERM "$$"
  ' _ "$BANCO_RAIZ" "$traza" >/dev/null 2>&1
  afirmar_codigo 130 "$?" "el proceso sale con 130 (el código de la señal, como bin/backupctl:53)"
  afirmar_existe "$traza" "la traza de limpiezas existe"
  local contenido
  contenido="$(tr '\n' ',' < "$traza" 2>/dev/null || true)"
  afirmar_igual "$contenido" "B,A," "las dos limpiezas corrieron (orden inverso) pese a la señal"
}

# bc_cleanup_run ahora ejecuta la limpieza ANTES de quitar la clave del
# registro (ronda de #022): si el proceso muere A MITAD de esa ejecución —
# aquí, simulado con un "exit 3" dentro de la propia orden—, la clave SIGUE
# registrada y bc_cleanup_pending, desde el trap EXIT, la reintenta. La orden
# usa un marcador en disco para distinguir "primera vez" (corta) de "reintento"
# (termina y dice OK), y así queda constancia de que el reintento sí corrió.
test_cleanup_run_retries_if_interrupted() {
  nueva_prueba t8
  local marcador="$BANCO_TMP/t8/marcador" traza="$BANCO_TMP/t8/traza.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    trap bc_cleanup_pending EXIT
    orden="if [ -e $(printf %q "$2") ]; then echo OK >> $(printf %q "$3"); else touch $(printf %q "$2"); exit 3; fi"
    bc_cleanup_register k "$orden"
    bc_cleanup_run k
    echo "no deberia llegar aqui" >> "$3"
  ' _ "$BANCO_RAIZ" "$marcador" "$traza" >/dev/null 2>&1
  afirmar_codigo 3 "$?" "la primera pasada corta el proceso con el código simulado (3)"
  afirmar_existe "$traza" "la traza existe: el reintento desde el trap EXIT llegó a correr"
  afirmar_igual "$(cat "$traza" 2>/dev/null || true)" "OK" "el reintento completó la limpieza sin volver a cortar"
}

# C3 (ronda #028/#030): distinto de t8 (que simula que el PROCESO muere a
# mitad de la limpieza) — aquí la orden TERMINA, pero en error ("false" al
# final). bc_cleanup_run no debe darla por hecha: la clave sigue registrada y
# bc_cleanup_pending, al salir, la reintenta una vez más — así que la orden
# tiene que verse ejecutada DOS veces, y bc_cleanup_pending debe avisar por
# stderr nombrando la clave que falló.
test_cleanup_run_retries_on_failure() {
  nueva_prueba t9
  local traza="$BANCO_TMP/t9/traza.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    trap bc_cleanup_pending EXIT
    bc_cleanup_register k "echo intento >> $(printf %q "$2"); false"
    bc_cleanup_run k
    exit 0
  ' _ "$BANCO_RAIZ" "$traza" >"$BANCO_TMP/t9/salida.log" 2>&1
  afirmar_codigo 0 "$?" "el proceso de prueba sale con código 0 (bc_cleanup_run no propaga el fallo)"
  afirmar_existe "$traza" "la traza existe: bc_cleanup_run SÍ ejecutó la orden que falla"
  local veces
  veces="$(grep -c '^intento$' "$traza" 2>/dev/null || true)"
  afirmar_igual "${veces:-0}" "2" "la orden corrió DOS veces: bc_cleanup_run y, al salir, bc_cleanup_pending"
  afirmar_contiene "$BANCO_TMP/t9/salida.log" "la limpieza 'k' terminó en error" "bc_cleanup_pending avisa nombrando la clave que falló"
}

# Ctrl-C se manda al GRUPO DE PROCESOS entero, no solo al padre: un manejador
# que solo marca una variable difiere la señal EN EL PADRE, pero el hijo en
# primer plano (el ssh real que devuelve restic.conf) la recibe igual y
# muere a mitad de la escritura. Con `trap '' INT TERM` (ignorar, no un
# manejador), los hijos heredan esa misma disposición vía exec y sobreviven.
#
# bc_cleanup_all vive en bin/backupctl, que no se puede cargar aquí (ejecuta
# su propio despacho de argumentos). En vez de copiar su cuerpo a mano —y
# arriesgarse a que las dos versiones diverjan sin que nada lo note—, se
# EXTRAE la función tal cual está en el archivo real con sed y se evalúa: si
# bin/backupctl cambia (o alguien revierte el arreglo), esta prueba lo ve
# directamente, sin mantenimiento aparte.
#
# La reproducción corre en SU PROPIO grupo de procesos (`set -m` + `kill` a
# -PID, NUNCA `kill -INT 0`): un "0" desnudo manda la señal al grupo de quien
# LLAMA, que aquí sería tests/ejecutar.sh — comprobado aparte, en aislado, y
# corta el banco entero, no solo esta prueba.
test_cleanup_all_lets_foreground_child_survive_group_signal() {
  nueva_prueba t10
  local marca="$BANCO_TMP/t10/marca"
  local orden_hijo
  orden_hijo="bash -c $(printf '%q' "sleep 1; echo completo > $(printf '%q' "$marca")")"
  ( set -m
    bash -c '
      set -Eeuo pipefail
      trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
      source "$1/lib/core.sh"
      source "$1/lib/mysql.sh"
      eval "$(sed -n "/^bc_cleanup_all() {/,/^}/p" "$1/bin/backupctl")"
      trap "rc=\$?; bc_cleanup_all; exit \$rc" EXIT
      trap "BC_DELIBERATE_EXIT=1; exit 130" INT TERM
      bc_cleanup_register hijo "$2"
      exit 0
    ' _ "$BANCO_RAIZ" "$orden_hijo" >/dev/null 2>&1 &
    local pid=$!
    sleep 0.3
    kill -INT -"$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  )
  afirmar_contiene "$marca" "completo" "el hijo en primer plano de la limpieza sobrevive a la señal del grupo"
}

# Complementaria de la anterior: con `trap ''` los hijos SÍ heredan SIGINT
# ignorada (política invertida a propósito respecto a una ronda anterior:
# ver 30-trampas.md T20). El bit de SIGINT en la máscara SigIgn de
# /proc/self/status es 0x2 (bit 1, señal número 2).
test_cleanup_all_children_inherit_ignored_sigint() {
  nueva_prueba t11
  local sigign="$BANCO_TMP/t11/sigign.txt"
  bash -c '
    set -Eeuo pipefail
    trap "bc_trap_err \"\$BASH_COMMAND\"" ERR
    source "$1/lib/core.sh"
    source "$1/lib/mysql.sh"
    eval "$(sed -n "/^bc_cleanup_all() {/,/^}/p" "$1/bin/backupctl")"
    trap "rc=\$?; bc_cleanup_all; exit \$rc" EXIT
    trap "BC_DELIBERATE_EXIT=1; exit 130" INT TERM
    bc_cleanup_register k "bash -c '"'"'grep ^SigIgn: /proc/self/status'"'"' > $(printf %q "$2")"
    exit 0
  ' _ "$BANCO_RAIZ" "$sigign" >/dev/null 2>&1
  afirmar_existe "$sigign" "el hijo dejó su propio registro de SigIgn"
  [[ -f "$sigign" ]] || return 0

  local hex valor
  hex="$(awk '{print $2}' "$sigign" 2>/dev/null || true)"
  valor=$(( 16#${hex:-0} ))
  afirmar_igual "$(( valor & 2 ))" "2" "el hijo SÍ hereda SIGINT ignorada (bit 0x2 de SigIgn puesto)"
}

test_loading_core_does_not_execute_anything
test_pending_cleanups_run_in_reverse_order_on_bc_die
test_cleanup_run_executes_once_and_not_again_on_exit
test_cleanup_forget_does_not_execute
test_a_failing_cleanup_does_not_block_the_rest
test_cleanup_eval_preserves_the_callers_errexit
test_pending_cleanups_run_on_sigterm
test_cleanup_run_retries_if_interrupted
test_cleanup_run_retries_on_failure
test_cleanup_all_lets_foreground_child_survive_group_signal
test_cleanup_all_children_inherit_ignored_sigint

fin_de_suite
