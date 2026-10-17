#!/usr/bin/env bash
# =============================================================================
# tests/probar_migracion_cron.sh — los cronjobs de la migración caliente
# =============================================================================
# Lo que esto cierra: un trabajo de cron que estaba SUSPENDIDO en el servidor
# viejo se creaba ACTIVO en el nuevo. v-add-cron-job lo crea activo, la
# herramienta no suspende nada después (no hay ninguna llamada a
# v-suspend-cron-job en todo el directorio), y lo único que hacía con el estado
# del origen era anotarlo en el registro. Los trabajos que alguien apaga a
# propósito son justo los que duelen al despertarse: los que facturan, los que
# envían correo, los que llaman a una API.
#
# Aquí no se habla con ningún servidor. BASE_MIGRAR_CRON.sh tiene la recogida
# (que hace ssh al origen con origen_exec) en un bloque SEPARADO del recorrido
# que crea los trabajos. Se extrae por marcadores solo el recorrido y el
# resumen, se le siembra el mapa de cronjobs ya «recogido», y la orden del
# panel se sustituye por un falso que apunta sus argumentos.
#
# K4 es el control del defecto: el mismo bloque, extraído del commit en que
# todavía estaba mal, migra los DOS trabajos.
# =============================================================================
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_migracion_cron.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_migracion_cron =="

MIG="$BANCO_RAIZ/tools/migracion-caliente"

# Commit con el bloque TODAVÍA defectuoso, para el control K4.
BASE_CON_DEFECTO="cf0e16d"

# -----------------------------------------------------------------------------
# Extracción del recorrido, sin la recogida
# -----------------------------------------------------------------------------
# Desde el encabezado de «RECORRER» hasta el final del archivo: eso incluye el
# bucle que decide y crea, y el resumen. La recogida por ssh queda fuera.
extraer_recorrido() {
  local archivo="$1" destino="$2"
  awk '
    index($0, "=== RECORRER ===") > 0 { dentro = 1 }
    dentro { print }
  ' "$archivo" > "$destino"
}

# El andamio: todo lo que el recorrido espera encontrado ya, y nada más.
#
# cron_valor y cron_reescribir se copian del propio archivo, por marcadores,
# para no tener aquí una segunda versión que se desincronice.
escribir_andamio() {
  local d="$1" archivo_cron="$2"

  awk '
    $0 == "cron_valor() {" { dentro = 1 }
    dentro { print }
    dentro && $0 == "}" { exit }
  ' "$archivo_cron" > "$d/funciones.sh"

  awk '
    $0 == "cron_reescribir() {" { dentro = 1 }
    dentro { print }
    dentro && $0 == "}" { exit }
  ' "$archivo_cron" >> "$d/funciones.sh"

  cat > "$d/andamio.sh" <<'FIN'
# Lo que el recorrido da por hecho que ya existe.
USER_DESTINO="cuentaejemplo"
HESTIA_BIN="/usr/local/hestia/bin"

# El directorio de la corrida, que en un servidor es
# /home/<cuenta>/migraciones/<fecha>/. Aquí, el del banco.
DIR_CORRIDA="$BC_DIR"

# priv_local es el prefijo de privilegio que la herramienta pone delante de
# algunas órdenes locales. Con ":" delante, la orden de cambiar el dueño del
# directorio de la corrida se vuelve un no-op: en el banco no hay nada cuyo
# dueño cambiar, y esa orden no es lo que se está probando.
priv_local=(":")

CRON_LOG="$BC_DIR/cronjobs.log"
CRON_PENDIENTES="$BC_DIR/cronjobs_pendientes.sh"
: > "$CRON_LOG"
: > "$CRON_PENDIENTES"

CRON_TOTAL=2
CRONJOBS_USUARIOS=("cuentaejemplo")

declare -A CRON_POR_USUARIO
CRON_POR_USUARIO[cuentaejemplo]="$BC_CRON_CONF"

CRON_DECISION="${BC_MODO:-todos}"

# La orden del panel, falsa: apunta sus argumentos y no hace nada.
hestia() {
  printf '%s\n' "$*" >> "$BC_DIR/invocaciones.txt"
  return 0
}

hestia_texto() { printf 'error %s' "$1"; }

source "$BC_DIR/funciones.sh"
FIN
}

# Dos trabajos: uno activo y uno suspendido en el origen.
CRON_CONF="$(
  printf "MIN='0' HOUR='3' DAY='*' MONTH='*' WDAY='*' CMD='/usr/bin/php8.1 /home/cuentaejemplo/activo.php' JOB='1' SUSPENDED='no'\n"
  printf "MIN='30' HOUR='4' DAY='*' MONTH='*' WDAY='*' CMD='/usr/bin/php8.1 /home/cuentaejemplo/suspendido.php' JOB='2' SUSPENDED='yes'\n"
)"

# Ejecuta el recorrido de $1 con el modo $2, en el directorio $3.
correr_recorrido() {
  local recorrido="$1" modo="$2" d="$3"

  env -i \
    PATH="$PATH" \
    LANG=C.UTF-8 \
    HOME="$d" \
    BC_DIR="$d" \
    BC_CRON_CONF="$CRON_CONF" \
    BC_MODO="$modo" \
    bash -c '
      set -u
      source "$1/andamio.sh"
      source "$2"
    ' _ "$d" "$recorrido" > "$d/salida.txt" 2>&1
}

# -----------------------------------------------------------------------------
# K1, K2, K3: el suspendido no se migra, se dice, y se cuenta
# -----------------------------------------------------------------------------
test_suspended_job_is_not_migrated() {
  nueva_prueba cron1
  local d="$BANCO_TMP/cron1"

  extraer_recorrido "$MIG/BASE_MIGRAR_CRON.sh" "$d/recorrido.sh"
  afirmar_contiene "$d/recorrido.sh" "v-add-cron-job" \
    "se extrajo el recorrido que crea los cronjobs"
  afirmar_no_contiene "$d/recorrido.sh" "origen_exec" \
    "y la extracción NO incluye la recogida por ssh"

  escribir_andamio "$d" "$MIG/BASE_MIGRAR_CRON.sh"

  correr_recorrido "$d/recorrido.sh" "todos" "$d"
  afirmar_codigo 0 "$?" "K1: el recorrido termina bien"

  # K1: el falso registra SOLO el activo.
  afirmar_existe "$d/invocaciones.txt" "K1: se invocó la creación al menos una vez"
  afirmar_igual "$(grep -c 'v-add-cron-job' "$d/invocaciones.txt" 2>/dev/null || true)" "1" \
    "K1: la orden del panel se invocó UNA sola vez ($(cat "$d/invocaciones.txt" 2>/dev/null | tr '\n' ' '))"
  afirmar_contiene "$d/invocaciones.txt" "activo.php" \
    "K1: y fue para el trabajo activo"
  afirmar_no_contiene "$d/invocaciones.txt" "suspendido.php" \
    "K1: el suspendido NO se creó"

  # K2: lo dice, con el CMD.
  afirmar_contiene "$d/salida.txt" "NO MIGRADO \(estaba suspendido en el origen\)" \
    "K2: la salida lo dice con esas palabras"
  afirmar_contiene "$d/salida.txt" "NO MIGRADO \(estaba suspendido en el origen\): 30 4 \* \* \* /usr/bin/php8.1 /home/cuentaejemplo/suspendido.php" \
    "K2: con su programación y su CMD"

  # K3: el resumen cuenta 1.
  afirmar_contiene "$d/salida.txt" "1 trabajo\(s\) suspendido\(s\) en el origen no se migraron" \
    "K3: el resumen cuenta 1"
  afirmar_contiene "$d/salida.txt" "recréalos a mano solo si hacen falta" \
    "K3: y dice qué hacer"
  afirmar_contiene "$d/cronjobs.log" "suspendidos en el origen, no migrados: 1" \
    "K3: y queda contado en el registro de la corrida"
  afirmar_contiene "$d/cronjobs_pendientes.sh" "SUSPENDIDO en el origen: no se migró" \
    "K3: y su orden queda anotada en los pendientes, para recrearlo"

  # El activo sí se migró, que es la otra mitad de lo que importa.
  afirmar_contiene "$d/salida.txt" "MIGRADO" \
    "K1: el activo sí se migró"
}

# En modo "preguntar", el suspendido ni se pregunta: se informa y se salta.
# Si llegara a preguntar, el read de /dev/tty colgaría o fallaría; que el
# recorrido termine bien sin tty es parte de lo que se comprueba.
test_suspended_job_is_not_even_asked_about() {
  nueva_prueba cron2
  local d="$BANCO_TMP/cron2"

  extraer_recorrido "$MIG/BASE_MIGRAR_CRON.sh" "$d/recorrido.sh"
  escribir_andamio "$d" "$MIG/BASE_MIGRAR_CRON.sh"

  # Solo el suspendido: así, si preguntara, se vería.
  CRON_CONF="$(
    printf "MIN='30' HOUR='4' DAY='*' MONTH='*' WDAY='*' CMD='/usr/bin/php8.1 /home/cuentaejemplo/suspendido.php' JOB='2' SUSPENDED='yes'\n"
  )" correr_recorrido "$d/recorrido.sh" "preguntar" "$d"

  afirmar_no_contiene "$d/salida.txt" "¿Migrar este cronjob?" \
    "el suspendido no se pregunta en modo preguntar"
  afirmar_contiene "$d/salida.txt" "NO MIGRADO \(estaba suspendido en el origen\)" \
    "se informa y se salta"
  afirmar_igual "$(test -s "$d/invocaciones.txt" && echo si || echo no)" "no" \
    "no se invocó la creación ni una vez"
}

# -----------------------------------------------------------------------------
# K4 — CONTROL DEL DEFECTO
# -----------------------------------------------------------------------------
test_the_old_block_migrated_both() {
  nueva_prueba cron3
  local d="$BANCO_TMP/cron3"

  git -C "$BANCO_RAIZ" show \
    "$BASE_CON_DEFECTO:tools/migracion-caliente/BASE_MIGRAR_CRON.sh" \
    > "$d/BASE_MIGRAR_CRON.anterior.sh" 2>/dev/null

  afirmar_existe "$d/BASE_MIGRAR_CRON.anterior.sh" \
    "K4: se recuperó el módulo de $BASE_CON_DEFECTO"

  extraer_recorrido "$d/BASE_MIGRAR_CRON.anterior.sh" "$d/recorrido.sh"
  afirmar_contiene "$d/recorrido.sh" "v-add-cron-job" \
    "K4: el recorrido anterior se extrajo de verdad"
  afirmar_no_contiene "$d/recorrido.sh" "NO MIGRADO" \
    "K4: y no tenía el arreglo"

  escribir_andamio "$d" "$d/BASE_MIGRAR_CRON.anterior.sh"

  correr_recorrido "$d/recorrido.sh" "todos" "$d"
  afirmar_codigo 0 "$?" "K4: el recorrido anterior termina bien"

  afirmar_igual "$(grep -c 'v-add-cron-job' "$d/invocaciones.txt" 2>/dev/null || true)" "2" \
    "K4: el bloque ANTERIOR creaba los DOS trabajos (el defecto)"
  afirmar_contiene "$d/invocaciones.txt" "suspendido.php" \
    "K4: incluido el que estaba suspendido en el origen"
}

# -----------------------------------------------------------------------------
# La herramienta no suspende nada en ninguna parte
# -----------------------------------------------------------------------------
# Es la razón por la que omitir era la única salida segura para el lunes: si
# algún día se crea suspendido, esta afirmación cambiará, y es el sitio donde
# hay que venir a leer por qué.
test_the_tool_never_suspends_anything() {
  nueva_prueba cron4
  local d="$BANCO_TMP/cron4"
  local hallazgos="$d/hallazgos.txt"

  grep -rn "v-suspend" "$MIG" --include='BASE_*.sh' > "$hallazgos" 2>/dev/null || true

  afirmar_igual "$(wc -l < "$hallazgos" | tr -d ' ')" "0" \
    "la herramienta no llama a ninguna orden de suspender: por eso el suspendido se omite ($(cat "$hallazgos" | tr '\n' ' '))"
}

test_suspended_job_is_not_migrated
test_suspended_job_is_not_even_asked_about
test_the_old_block_migrated_both
test_the_tool_never_suspends_anything

fin_de_suite
