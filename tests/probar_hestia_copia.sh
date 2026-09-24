#!/usr/bin/env bash
# =============================================================================
# tests/probar_hestia_copia.sh — la primera copia, comprobada
# =============================================================================
# AQUÍ NO HAY NINGÚN SERVIDOR. Todo va por el `ssh` falso del banco (ADR 0009).
#
# Este es el paso que cierra el ciclo, y la prueba que le da sentido a toda la
# suite es una: la orden dice que el respaldo fue BIEN y no aparece ninguna
# copia nueva. Eso pasa de verdad —la orden del panel usa una constante de
# error que no existe, así que un respaldo que falla registra éxito— y es la
# razón por la que el veredicto sale de la diferencia de instantáneas y no del
# código de salida.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_hestia_copia.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_hestia_copia =="

# Con un HestiaCP de verdad en esta máquina, bc_hestia_conectar trabajaría en
# LOCAL en vez de irse por el falso, y estas pruebas tocarían el sistema de
# quien las ejecuta.
if [[ -d /usr/local/hestia ]]; then
  echo "probar_hestia_copia.sh: existe /usr/local/hestia en esta máquina; se aborta." >&2
  exit 2
fi

HESTIA_FALSO="/usr/local/hestia"

# Listas de instantáneas sintéticas, con la forma real: un array en una sola
# línea, fecha en UTC con 'Z' y identificador corto.
lista_una() {
  printf '[{"time":"2026-09-23T21:25:50.972078216Z","short_id":"200953a7","paths":["/home/cliente07"]}]'
}
lista_dos() {
  printf '[{"time":"2026-09-23T21:25:50.972078216Z","short_id":"200953a7","paths":["/home/cliente07"]},'
  printf '{"time":"2026-09-24T03:10:00.111111111Z","short_id":"bb11cc22","summary":{"data_added":5242880}}]'
}
lista_vacia() { printf '[]'; }

escribir_guion() {
  cat > "$BANCO_TMP/guion/ssh.sh" <<'FIN'
orden="${!#}"
llana="${orden//\\/}"
case "$llana" in
  *"id -u"*) exit 0 ;;
  "true")    exit 0 ;;
esac
printf '%s\n' "$llana" >> "$BANCO_TMP/ordenes.txt"

case "$llana" in
  *"test -d"*"/usr/local/hestia"*) exit 0 ;;

  *v-list-user-backups-restic*)
    valor="$(sed -n '1p' "$BANCO_TMP/lecturas")"
    # Una lectura que falla se INTENTA DOS VECES: bc_hestia_read reintenta
    # elevando privilegios cuando no obtiene nada. Si la cola se consumiera en
    # el primer intento, el segundo devolvería la respuesta del DESPUÉS y la
    # prueba mediría otra cosa. Se consume cuando el intento ha terminado.
    if [[ "$valor" == "@ilegible" ]]; then
      if [[ -s "$BANCO_TMP/reintento" ]]; then
        : > "$BANCO_TMP/reintento"
        sed -i '1d' "$BANCO_TMP/lecturas"
      else
        printf 'x' > "$BANCO_TMP/reintento"
      fi
      exit 1
    fi
    sed -i '1d' "$BANCO_TMP/lecturas"
    cat "$BANCO_TMP/$valor"
    exit 0 ;;

  *v-backup-user-restic*)
    cat "$BANCO_TMP/salida-orden" 2>/dev/null
    exit "$(cat "$BANCO_TMP/codigo-orden")" ;;
esac
echo "falso: ninguna respuesta prevista para: $llana" >&2
exit 95
FIN
}

# Prepara el caso.
# $1 caso  $2 lista ANTES  $3 lista DESPUÉS  $4 código de la orden
preparar() {
  local caso="$1" antes="$2" despues="$3" codigo="$4"
  local dir="$BANCO_TMP/$caso"
  rm -rf "$dir"; mkdir -p "$dir/perfil" "$BANCO_TMP/guion"
  rm -f "$BANCO_TMP/ordenes.txt"
  printf '%s\n%s\n' "$antes" "$despues" > "$BANCO_TMP/lecturas"
  printf '%s' "$codigo" > "$BANCO_TMP/codigo-orden"
  printf 'Backup completed\n' > "$BANCO_TMP/salida-orden"
  : > "$BANCO_TMP/reintento"
  lista_una   > "$BANCO_TMP/lista-una"
  lista_dos   > "$BANCO_TMP/lista-dos"
  lista_vacia > "$BANCO_TMP/lista-vacia"
  escribir_guion
}

copiar() {
  local caso="$1" usuarios="$2" modo="${3:-}"
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
    BC_OPT_USERS="$4"
    BC_ASSUME_YES=1
    BC_NO_COLOR=1
    [[ "$5" == "ensayo" ]] && BC_OPT_DRY=1
    bc_hestia_copia
    echo "CODIGO:$?"
  ' _ "$BANCO_RAIZ" "$HESTIA_FALSO" "$BANCO_TMP/$caso/perfil" "$usuarios" "$modo" 2>&1
}

# Cuántos respaldos se lanzaron DE VERDAD. Es el número que importa en los
# casos donde no debe lanzarse ninguno.
cuantos_respaldos() {
  [[ -f "$BANCO_TMP/ordenes.txt" ]] || { echo 0; return 0; }
  grep -c 'bin/v-backup-user-restic' "$BANCO_TMP/ordenes.txt" || true
}

informe_de() {
  find "$BANCO_TMP/$1/perfil/informes" -name '*.md' 2>/dev/null | sed -n '1p'
}

# --- aparece una instantánea nueva -------------------------------------------
test_a_new_snapshot_is_the_proof() {
  nueva_prueba t1
  preparar t1 lista-una lista-dos 0
  local salida; salida="$(copiar t1 cliente07)"
  echo "$salida" > "$BANCO_TMP/t1/salida.log"

  afirmar_contiene "$BANCO_TMP/t1/salida.log" "CODIGO:0" "termina bien"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "HECHA y comprobada" "lo da por hecho"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "bb11cc22" "y dice el identificador de la nueva"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "Fecha:" "con su fecha"
  afirmar_contiene "$BANCO_TMP/t1/salida.log" "Tardó:" "y cuánto tardó"

  local informe; informe="$(informe_de t1)"
  afirmar_contiene "$informe" "Cuenta cliente07 — copias \| 1 \| 2 \|" \
    "el informe: cuántas había y cuántas hay"
  afirmar_contiene "$informe" "5.0 MiB" "el informe: lo que ocupó lo añadido"
  afirmar_contiene "$informe" "no sobrescribe nada" "y que no hay nada que deshacer"
}

# --- LA PRUEBA QUE DA SENTIDO AL PASO ----------------------------------------
test_a_successful_command_without_a_new_snapshot_is_not_a_backup() {
  nueva_prueba t2
  preparar t2 lista-una lista-una 0
  local salida; salida="$(copiar t2 cliente07)"
  echo "$salida" > "$BANCO_TMP/t2/salida.log"

  afirmar_contiene "$BANCO_TMP/t2/salida.log" "CODIGO:1" \
    "la orden dijo que bien, pero NO se da por bueno"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "SALIÓ BIEN CUANDO HA FALLADO" \
    "y el mensaje nombra el fallo del panel con todas las letras"
  afirmar_contiene "$BANCO_TMP/t2/salida.log" "Sigue habiendo 1 copia" \
    "y dice cuántas copias sigue habiendo"
}

# --- la orden falla y no aparece nada ----------------------------------------
test_a_failed_command_without_a_snapshot_is_a_failure() {
  nueva_prueba t3
  preparar t3 lista-una lista-una 15
  local salida; salida="$(copiar t3 cliente07)"
  echo "$salida" > "$BANCO_TMP/t3/salida.log"

  afirmar_contiene "$BANCO_TMP/t3/salida.log" "CODIGO:1" "falla"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "falló \(código 15\)" "con el código de la orden"
  afirmar_contiene "$BANCO_TMP/t3/salida.log" "Backup completed" "y lo que respondió"
}

# --- la orden falla y SÍ aparece la instantánea ------------------------------
#
# Manda el servidor, no la orden. Es la misma regla del ADR 0017 al revés.
test_a_failed_command_with_a_new_snapshot_is_done() {
  nueva_prueba t4
  preparar t4 lista-una lista-dos 15
  local salida; salida="$(copiar t4 cliente07)"
  echo "$salida" > "$BANCO_TMP/t4/salida.log"

  afirmar_contiene "$BANCO_TMP/t4/salida.log" "CODIGO:0" \
    "la orden salió con 15, pero la copia está: manda el servidor"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "HECHA y comprobada" "se da por hecha"
  afirmar_contiene "$BANCO_TMP/t4/salida.log" "manda el servidor" \
    "y se dice que la orden falló, para que conste"
}

# --- no se puede leer el antes -----------------------------------------------
test_an_unreadable_before_launches_nothing() {
  nueva_prueba t5
  preparar t5 @ilegible lista-dos 0
  local salida; salida="$(copiar t5 cliente07)"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_igual "$(cuantos_respaldos)" "0" \
    "NINGÚN respaldo lanzado: sin el antes no se puede demostrar nada"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:1" "y no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "no demostraría nada" "diciendo por qué"
}

# --- no se puede leer el después ---------------------------------------------
test_an_unreadable_after_says_it_was_launched() {
  nueva_prueba t6
  preparar t6 lista-una @ilegible 0
  local salida; salida="$(copiar t6 cliente07)"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"

  afirmar_igual "$(cuantos_respaldos)" "1" "el respaldo SÍ se lanzó"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "CODIGO:1" "y no se da por bueno"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "SE LANZÓ" "se dice que se lanzó"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "No sabemos si se hizo" "y que no se sabe el resultado"
}

# --- sin --usuarios ----------------------------------------------------------
test_without_accounts_nothing_is_launched() {
  nueva_prueba t7
  preparar t7 lista-una lista-dos 0
  local salida; salida="$(copiar t7 "")"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"

  afirmar_igual "$(cuantos_respaldos)" "0" "no se lanza nada"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "CODIGO:1" "y se sale con error"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "hestia copia --usuarios" "explicando cómo elegir"
}

# --- ensayo ------------------------------------------------------------------
test_a_dry_run_launches_nothing() {
  nueva_prueba t8
  preparar t8 lista-una lista-dos 0
  local salida; salida="$(copiar t8 cliente07 ensayo)"
  echo "$salida" > "$BANCO_TMP/t8/salida.log"

  afirmar_contiene "$BANCO_TMP/t8/salida.log" "CODIGO:0" "el ensayo termina bien"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "PASARÍA" "se ve que es una simulación"
  afirmar_contiene "$BANCO_TMP/t8/salida.log" "tiene 1 copia" "y se ve el punto de partida"
  afirmar_igual "$(cuantos_respaldos)" "0" "sin lanzar ningún respaldo"
  afirmar_igual "$([[ -n "$(informe_de t8)" ]] && echo si || echo no)" "no" \
    "y sin archivar ningún informe"
}

# --- una cuenta sin ninguna copia previa -------------------------------------
test_a_first_ever_backup_is_detected() {
  nueva_prueba t9
  preparar t9 lista-vacia lista-una 0
  local salida; salida="$(copiar t9 cliente07)"
  echo "$salida" > "$BANCO_TMP/t9/salida.log"

  afirmar_contiene "$BANCO_TMP/t9/salida.log" "CODIGO:0" "la primera copia de todas cuenta igual"
  afirmar_contiene "$BANCO_TMP/t9/salida.log" "200953a7" "con su identificador"
}

test_a_new_snapshot_is_the_proof
test_a_successful_command_without_a_new_snapshot_is_not_a_backup
test_a_failed_command_without_a_snapshot_is_a_failure
test_a_failed_command_with_a_new_snapshot_is_done
test_an_unreadable_before_launches_nothing
test_an_unreadable_after_says_it_was_launched
test_without_accounts_nothing_is_launched
test_a_dry_run_launches_nothing
test_a_first_ever_backup_is_detected

fin_de_suite
