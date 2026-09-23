#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_retencion.sh — texto de la retención de Restic (T26)
# =============================================================================
# Solo prueba bc_hestia_texto_anuales_registro: es una función PURA (sin ssh,
# sin efectos), extraída de bc_hestia_restic para poder probar el texto que
# genera sin conectar a nada. bc_hestia_restic entera conecta y pide
# confirmación (bc_hestia_conectar, bc_confirm): no se ejercita aquí.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_retencion.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_retencion =="

# T26: v-backup-user-restic (HestiaCP 1.10.4) solo añade --keep-yearly si
# KEEP_YEARLY >= 0; con -1 no hay tramo anual. La tabla de bc_hestia_restic
# no puede seguir diciendo "ilimitadas" (mentira: no es "sin límite", es "no
# hay regla").
test_anuales_menos_uno_dice_sin_regla_no_ilimitadas() {
  nueva_prueba t1
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/hestia.sh"
    bc_hestia_texto_anuales_registro "-1"
  ' _ "$BANCO_RAIZ" > "$BANCO_TMP/t1/salida.log"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "sin regla anual" "con y=-1, el texto dice 'sin regla anual'"
  afirmar_no_contiene "$BANCO_TMP/t1/salida.log" "ilimitad" "con y=-1, el texto NO dice 'ilimitadas'"
}

# Con un valor real (no -1), el texto es el número tal cual, sin adornos.
test_anuales_con_valor_real_devuelve_el_numero() {
  nueva_prueba t2
  local salida
  salida="$(bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/hestia.sh"
    bc_hestia_texto_anuales_registro "5"
  ' _ "$BANCO_RAIZ")"
  afirmar_igual "$salida" "5" "con y=5, el texto es exactamente '5'"
}

test_anuales_menos_uno_dice_sin_regla_no_ilimitadas
test_anuales_con_valor_real_devuelve_el_numero

fin_de_suite
