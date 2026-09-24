#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_desactivar.sh — dejar de hacer copias, sin borrar ninguna
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Todo va por el falso del banco (ADR 0009).
#
# Lo que más se vigila aquí es una NEGATIVA: si hay cuentas con copias cuya
# clave no está rescatada, con --yes la orden no pasa de ahí. Desactivar en esa
# situación deja copias que nadie podrá abrir si se pierde la máquina, y es el
# único daño de todo el ciclo que no se ve hasta que ya es tarde.
#
# Lo segundo: que las cuentas se desmarquen DE VERDAD. Borrar el host no toca
# ninguna cuenta, así que darlo por desactivado sin desmarcarlas deja un
# servidor que volverá a respaldar solo en cuanto se registre otro repositorio.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_desactivar.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_desactivar =="

if [[ -d /usr/local/hestia ]]; then
  echo "probar_hestia_desactivar.sh: existe /usr/local/hestia en esta máquina; se aborta." >&2
  exit 2
fi

HESTIA_FALSO="/usr/local/hestia"
CLAVE_SINTETICA='Zx9-clave-sintetica-de-prueba'

conf_global() {
  printf "REPO='rclone:almacen:/IncrementalBackups'\nSNAPSHOTS='30'\nKEEP_DAILY='8'\nKEEP_WEEKLY='5'\nKEEP_MONTHLY='3'\nKEEP_YEARLY='-1'\n"
}
conf_vacio() { printf ''; }
cron_con()   { printf '# tareas\n45 5 * * * sudo %s/bin/v-backup-users-restic\n' "$HESTIA_FALSO"; }
cron_sin()   { printf '# tareas\n'; }
user_si()    { printf "NAME='C'\nBACKUPS_INCREMENTAL='yes'\n"; }
user_no()    { printf "NAME='C'\nBACKUPS_INCREMENTAL='no'\n"; }

escribir_guion() {
  cat > "$BANCO_TMP/guion/ssh.sh" <<'FIN'
orden="${!#}"
llana="${orden//\\/}"
case "$llana" in
  *"id -u"*) exit 0 ;;
  "true")    exit 0 ;;
esac
printf '%s\n' "$llana" >> "$BANCO_TMP/ordenes.txt"

cuenta=""
case "$llana" in
  *data/users/*) cuenta="${llana#*data/users/}"; cuenta="${cuenta%%/*}" ;;
  *v-change-user-config-value*)
    cuenta="${llana#*v-change-user-config-value }"; cuenta="${cuenta%% *}" ;;
  *"/IncrementalBackups/"*)
    cuenta="${llana#*/IncrementalBackups/}"; cuenta="${cuenta%%/*}" ;;
esac

case "$llana" in
  *"test -d"*"/usr/local/hestia"*) exit 0 ;;

  *"v-list-users"*) cat "$BANCO_TMP/lista-usuarios"; exit 0 ;;

  *"cp -p"*) printf 'BC_COPIA_OK\n'; exit 0 ;;

  # Sonda del repositorio de una cuenta
  *"rclone lsf"*)
    if [[ "$(cat "$BANCO_TMP/repo-$cuenta" 2>/dev/null || echo no)" == "si" ]]; then
      printf 'BC_SI\n'
    else
      printf 'BC_NO\n'
    fi
    exit 0 ;;

  # Sonda de la marca de una cuenta
  *"grep -q"*BACKUPS_INCREMENTAL*)
    if [[ "$(cat "$BANCO_TMP/marca-$cuenta" 2>/dev/null || echo no)" == "si" ]]; then
      printf 'BC_SI\n'
    else
      printf 'BC_NO\n'
    fi
    exit 0 ;;

  *"sed -i"*v-backup-users*)
    printf 'sin-cron' > "$BANCO_TMP/estado-cron"
    exit "$(cat "$BANCO_TMP/codigo-cron" 2>/dev/null || echo 0)" ;;

  *v-delete-backup-host-restic*)
    printf 'sin-host' > "$BANCO_TMP/estado-host"
    exit "$(cat "$BANCO_TMP/codigo-host" 2>/dev/null || echo 0)" ;;

  *v-change-user-config-value*)
    if [[ "$(cat "$BANCO_TMP/codigo-cuenta-$cuenta" 2>/dev/null || echo 0)" == "0" ]]; then
      printf 'no' > "$BANCO_TMP/marca-actual-$cuenta"
    fi
    exit "$(cat "$BANCO_TMP/codigo-cuenta-$cuenta" 2>/dev/null || echo 0)" ;;

  *"cat "*crontabs/hestiaweb*)
    if [[ "$(cat "$BANCO_TMP/estado-cron")" == "sin-cron" ]]; then
      cat "$BANCO_TMP/cron-sin"
    else
      cat "$BANCO_TMP/cron-con"
    fi
    printf 'BC_FIN\n'; exit 0 ;;

  *"cat "*conf/restic.conf*)
    if [[ "$(cat "$BANCO_TMP/estado-host")" == "sin-host" ]]; then
      cat "$BANCO_TMP/conf-vacio"
    else
      cat "$BANCO_TMP/conf-global"
    fi
    printf 'BC_FIN\n'; exit 0 ;;

  *"cat "*user.conf*)
    if [[ "$(cat "$BANCO_TMP/marca-actual-$cuenta" 2>/dev/null || echo si)" == "no" ]]; then
      cat "$BANCO_TMP/user-no"
    else
      cat "$BANCO_TMP/user-si"
    fi
    printf 'BC_FIN\n'; exit 0 ;;
esac
echo "falso: ninguna respuesta prevista para: $llana" >&2
exit 95
FIN
}

# Prepara el caso.
preparar() {
  local caso="$1"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil/output/HestiaCP" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt" "$BANCO_TMP"/marca-* "$BANCO_TMP"/repo-* "$BANCO_TMP"/codigo-*
  : > "$BANCO_TMP/lista-usuarios"
  printf 'con-cron' > "$BANCO_TMP/estado-cron"
  printf 'con-host' > "$BANCO_TMP/estado-host"
  conf_global > "$BANCO_TMP/conf-global"
  conf_vacio  > "$BANCO_TMP/conf-vacio"
  cron_con    > "$BANCO_TMP/cron-con"
  cron_sin    > "$BANCO_TMP/cron-sin"
  user_si     > "$BANCO_TMP/user-si"
  user_no     > "$BANCO_TMP/user-no"
  escribir_guion
}

# $1 cuenta  $2 marcada (si|no)  $3 tiene copias (si|no)  $4 clave rescatada (si|no)
cuenta_con() {
  local u="$1" marcada="$2" repo="$3" rescatada="$4" caso="$5"
  printf '%s\n' "$u" >> "$BANCO_TMP/lista-usuarios"
  printf '%s' "$marcada" > "$BANCO_TMP/marca-$u"
  printf '%s' "$repo"    > "$BANCO_TMP/repo-$u"
  if [[ "$rescatada" == "si" ]]; then
    local f="$BANCO_TMP/$caso/perfil/output/HestiaCP/Restic_Configs_20260101-000000.txt"
    { printf '# %s:\n' "$u"; printf '%s\n' "$CLAVE_SINTETICA"; printf '\n=====================\n\n'; } >> "$f"
  fi
}

desactivar() {
  local caso="$1" modo="${2:-}" si="${3:-1}"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/informe.sh"
    source "$1/lib/ssh.sh"
    source "$1/lib/hestia.sh"
    HESTIA_DIR="$2"
    HESTIA_OUTPUT_DIR="$3/output/HestiaCP"
    DEPLOY_HOST="servidor-sintetico"
    DEPLOY_USER="root"
    BC_PROFILE="Sintetico"
    BC_PROFILE_DIR="$3"
    RESTIC_RETENTION_DAYS=90
    BC_ASSUME_YES="$5"
    BC_NO_COLOR=1
    [[ "$4" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_desactivar
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$BANCO_TMP/$caso/perfil" "$modo" "$si" 2>&1
}

se_pidio() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo no; return 0; }
  if grep -qF -- "$1" "$BANCO_TMP/ordenes.txt"; then echo si; else echo no; fi
}

cuantas_escrituras() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo 0; return 0; }
  grep -cE 'sed -i|v-delete-backup-host-restic|v-change-user-config-value' \
    "$BANCO_TMP/ordenes.txt" || true
}

informe_de() {
  find "$BANCO_TMP/$1/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- LA PRUEBA DE LA RONDA ---------------------------------------------------
#
# Copias sin clave rescatada, y con --yes (que es como llama la web): la orden
# no pasa de ahí.
test_with_yes_and_unrescued_keys_it_refuses() {
  nueva_prueba t1
  preparar t1
  cuenta_con cliente07 si si no t1      # tiene copias y NO está rescatada
  local salida; salida="$(desactivar t1 "" 1)"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_igual "$(cuantas_escrituras)" "0" \
    "NINGUNA orden de escritura enviada al servidor"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:1" "y la orden se niega"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "SU CLAVE NO ESTÁ RESCATADA" "diciendo cuáles"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "cliente07" "con su nombre"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "hestia keys" "y qué hacer"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "Un aviso que nadie lee no protege nada" \
    "y por qué no basta con avisar"
}

# Sin --yes, se avisa ANTES de preguntar y se pide confirmación explícita. En
# el banco no hay terminal, así que la confirmación se responde con el valor
# por defecto, que es NO: no se toca nada.
test_without_yes_it_asks_first() {
  nueva_prueba t2
  preparar t2
  cuenta_con cliente07 si si no t2
  local salida; salida="$(desactivar t2 "" 0)"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "SU CLAVE NO ESTÁ RESCATADA" \
    "se avisa antes de preguntar"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "Cancelado" \
    "y sin un sí explícito no se sigue"
  afirmar_igual "$(cuantas_escrituras)" "0" "sin tocar nada"
}

# --- todo rescatado: las tres cosas ------------------------------------------
test_with_everything_rescued_all_three_are_done() {
  nueva_prueba t3
  preparar t3
  cuenta_con cliente07 si si si t3
  local salida; salida="$(desactivar t3 "" 1)"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "Programación quitada del cron" "1: el cron"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "Host de respaldo borrado" "2: el host"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "desmarcada, y comprobado" "3: la cuenta"
  afirmar_igual "$(se_pidio "v-change-user-config-value cliente07")" "si" \
    "se desmarcó la cuenta de verdad"
}

# --- una cuenta falla --------------------------------------------------------
test_a_failing_account_is_reported_as_still_marked() {
  nueva_prueba t4
  preparar t4
  cuenta_con cliente07 si si si t4
  printf '3' > "$BANCO_TMP/codigo-cuenta-cliente07"
  local salida; salida="$(desactivar t4 "" 1)"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"

  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:1" "no se da por desactivado"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "SIGUEN MARCADAS" "se dice que siguen marcadas"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "EMPEZARÁN A RESPALDAR SOLAS" \
    "y qué pasará si se registra otro repositorio"
}

# --- el informe --------------------------------------------------------------
test_the_report_says_nothing_is_deleted_and_how_to_undo() {
  nueva_prueba t5
  preparar t5
  cuenta_con cliente07 si si si t5
  desactivar t5 "" 1 >/dev/null
  local informe; informe="$(informe_de t5)"

  afirmar_igual "$([[ -n "$informe" ]] && echo si || echo no)" "si" "se guardó un informe"
  afirmar_contiene "$informe" "NO se borran" "dice que las copias NO se borran"
  afirmar_contiene "$informe" "ninguno: no se borra nada" "y que no se libera espacio"
  afirmar_contiene "$informe" "rclone:almacen:/IncrementalBackups" \
    "guarda el repositorio que había"
  afirmar_contiene "$informe" "SNAPSHOTS=30 KEEP_DAILY=8" "y la retención que tenía"
  afirmar_contiene "$informe" "hestia restic --repo" "y cómo volver a activarlo"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_changes_nothing() {
  nueva_prueba t6
  preparar t6
  cuenta_con cliente07 si si si t6
  local salida; salida="$(desactivar t6 ensayo 1)"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "PASARÍA" "se ve que es una simulación"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "Se desmarcarían 1 cuenta" "y qué se desactivaría"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "NO se borraría ninguna copia" \
    "diciendo que no se borra nada"
  afirmar_igual "$(cuantas_escrituras)" "0" "sin tocar nada"
  afirmar_igual "$([[ -n "$(informe_de t6)" ]] && echo si || echo no)" "no" \
    "y sin archivar ningún informe"
}

# Una cuenta sin copias no bloquea nada aunque no tenga clave rescatada:
# no hay nada que pudiera quedarse ilegible.
test_an_account_without_backups_does_not_block() {
  nueva_prueba t7
  preparar t7
  cuenta_con cliente09 si no no t7
  local salida; salida="$(desactivar t7 "" 1)"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"

  afirmar_contiene "$BANCO_TMP/t7/salida.log" "CODIGO:0" "no se bloquea"
  afirmar_no_contiene "$BANCO_TMP/t7/salida.log" "SU CLAVE NO ESTÁ RESCATADA" \
    "y no se avisa de una cuenta que no tiene copias"
}

test_with_yes_and_unrescued_keys_it_refuses
test_without_yes_it_asks_first
test_with_everything_rescued_all_three_are_done
test_a_failing_account_is_reported_as_still_marked
test_the_report_says_nothing_is_deleted_and_how_to_undo
test_a_dry_run_changes_nothing
test_an_account_without_backups_does_not_block

fin_de_suite
