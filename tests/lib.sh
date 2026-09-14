#!/usr/bin/env bash
# =============================================================================
# tests/lib.sh — biblioteca mínima del banco de pruebas (ADR 0009)
# =============================================================================
# La cargan las suites (tests/probar_*.sh). Nada de esto se ejecuta contra un
# servidor: los perfiles que crea viven siempre dentro de $BANCO_TMP, y
# backupctl_prueba se niega a usar uno que no lo esté.
#
# Las afirmaciones se cuentan desde un ARCHIVO ($BANCO_TMP/.resultados), no
# desde variables: una variable que cambia dentro de "$(...)" no sobrevive al
# subshell (docs/desarrollo/arquitectura.md, «Detalles que no son obvios»); un
# archivo, sí. Con esto una llamada a backupctl_prueba dentro de una
# sustitución de comandos sigue contando aunque se niegue a ejecutar.
# =============================================================================

[[ -n "${BC_PRUEBA_LIB_LOADED:-}" ]] && return 0
BC_PRUEBA_LIB_LOADED=1

# -----------------------------------------------------------------------------
# Salvaguarda de entorno — falla en CERRADO, no en abierto
# -----------------------------------------------------------------------------
# BANCO_TMP y BANCO_RAIZ sostienen todas las demás salvaguardas de este
# archivo (backupctl_prueba, nueva_prueba): si cualquiera de las dos está
# vacía, no es absoluta, o no es un directorio, cualquier comparación de rutas
# posterior puede degenerar en "acepta cualquiera" (revisión de la ronda
# #008: con $BANCO_TMP="", el patrón "$base"/*|"$base" se volvía /*|"", que
# aceptaba cualquier ruta absoluta). Se comprueba ANTES de cualquier mkdir o
# rm, y de nuevo dentro de nueva_prueba (defensa en profundidad).
bc_comprobar_entorno_banco() {
  local nombre valor real
  for nombre in BANCO_TMP BANCO_RAIZ; do
    valor="${!nombre:-}"
    if [[ -z "$valor" ]]; then
      echo "tests/lib.sh: \$$nombre no está definida o está vacía: se aborta." >&2
      exit 2
    fi
    if [[ "$valor" != /* ]]; then
      echo "tests/lib.sh: \$$nombre no es una ruta absoluta ('$valor'): se aborta." >&2
      exit 2
    fi
    if [[ ! -d "$valor" ]]; then
      echo "tests/lib.sh: \$$nombre no es un directorio existente ('$valor'): se aborta." >&2
      exit 2
    fi
  done

  real="$(realpath -e -- "$BANCO_TMP" 2>/dev/null || true)"
  case "$real" in
    /tmp/backupctl-pruebas.*) ;;
    *)
      echo "tests/lib.sh: \$BANCO_TMP ('$BANCO_TMP', resuelto '$real') no está dentro de /tmp/backupctl-pruebas.*: se aborta." >&2
      exit 2
      ;;
  esac
}

bc_comprobar_entorno_banco

mkdir -p "$BANCO_TMP/registro" "$BANCO_TMP/guion"
: > "$BANCO_TMP/.resultados"

# -----------------------------------------------------------------------------
# Afirmaciones
# -----------------------------------------------------------------------------
afirmar_codigo() {
  local esperado="$1" obtenido="$2" desc="$3"
  if [[ "$esperado" == "$obtenido" ]]; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$desc" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc (esperado código $esperado, obtenido $obtenido)" >&2
    printf 'FALLO\t%s (esperado codigo %s, obtenido %s)\n' "$desc" "$esperado" "$obtenido" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_igual() {
  local a="$1" b="$2" desc="$3"
  if [[ "$a" == "$b" ]]; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$desc" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc (esperado '$b', obtenido '$a')" >&2
    printf 'FALLO\t%s (esperado %s, obtenido %s)\n' "$desc" "$b" "$a" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_contiene() {
  local archivo="$1" patron="$2" desc="$3"
  if [[ -f "$archivo" ]] && grep -qE -- "$patron" "$archivo"; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$desc" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc (no se encontró '$patron' en $archivo)" >&2
    printf 'FALLO\t%s (no se encontro %s en %s)\n' "$desc" "$patron" "$archivo" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_no_contiene() {
  local archivo="$1" patron="$2" desc="$3"
  if [[ ! -f "$archivo" ]]; then
    echo "  FALLO: $desc (no existe $archivo)" >&2
    printf 'FALLO\t%s (no existe %s)\n' "$desc" "$archivo" >> "$BANCO_TMP/.resultados"
  elif grep -qE -- "$patron" "$archivo"; then
    echo "  FALLO: $desc (se encontró '$patron' en $archivo)" >&2
    printf 'FALLO\t%s (se encontro %s en %s)\n' "$desc" "$patron" "$archivo" >> "$BANCO_TMP/.resultados"
  else
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$desc" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_intacto() {
  local archivo="$1" copia="$2" desc="$3"
  if cmp -s "$archivo" "$copia"; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$desc" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc ($archivo difiere de $copia)" >&2
    printf 'FALLO\t%s (%s difiere de %s)\n' "$desc" "$archivo" "$copia" >> "$BANCO_TMP/.resultados"
  fi
}

# Cuenta SIEMPRE desde el archivo. Una suite sin ninguna afirmación no ha
# probado nada: cuenta como fallo, no como éxito vacío.
fin_de_suite() {
  local total=0 fallos=0
  if [[ -f "$BANCO_TMP/.resultados" ]]; then
    total="$(wc -l < "$BANCO_TMP/.resultados")"
    fallos="$(grep -c '^FALLO' "$BANCO_TMP/.resultados" || true)"
  fi
  echo "  -- $total afirmaciones, $fallos fallidas --" >&2
  if (( total == 0 )); then
    echo "  FALLO: la suite no hizo ninguna afirmación" >&2
    return 1
  fi
  (( fallos == 0 ))
}

# -----------------------------------------------------------------------------
# Aislamiento entre pruebas
# -----------------------------------------------------------------------------
# Cada test_… empieza llamando a esto: deja registro/ y guion/ limpios (sin
# arrastrar invocaciones ni respuestas de la prueba anterior dentro de la
# misma suite) y un directorio propio donde trabajar.
nueva_prueba() {
  local nombre="$1"
  bc_comprobar_entorno_banco
  rm -rf "$BANCO_TMP/registro" "$BANCO_TMP/guion"
  mkdir -p "$BANCO_TMP/registro" "$BANCO_TMP/guion" "$BANCO_TMP/$nombre"
  cd "$BANCO_TMP/$nombre"
}

# -----------------------------------------------------------------------------
# Perfil sintético
# -----------------------------------------------------------------------------
# Declara TODAS las variables de forma explícita: nada se hereda del entorno
# (T13, .agents/context/30-trampas.md). BACKUP_WORK_DIR existe ya al volver de
# esta función: el bloqueo de 'backup' se toma antes de crear directorios y,
# si no existe, sale con 2 (core.sh:188, bin/backupctl:283). MYSQL_PASS lleva
# un valor distintivo para poder comprobar que nunca llega a un registro ni a
# un log (test_profile_password_never_reaches_the_logs).
crear_perfil() {
  local dir="$1"
  mkdir -p "$dir/output/mysql_backups" "$dir/output/HestiaCP" "$dir/logs"
  cat > "$dir/env.sh" <<EOF
export MYSQL_USER="prueba"
export MYSQL_PASS="clave-sintetica-no-real-7Q2"
export MYSQL_HOST=""
export MYSQL_PORT=""
export MYSQL_SOCKET=""
export MYSQL_CHARSET="utf8mb4"
export USER_NAME="prueba"
export DEPLOY_HOST=""
export SCRIPTS_DIR="$dir"
export BACKUP_OUTPUT_DIR="$dir/output/mysql_backups"
export BACKUP_WORK_DIR="$dir/output"
export HESTIA_OUTPUT_DIR="$dir/output/HestiaCP"
export LOG_DIR="$dir/logs"
export BACKUP_RETENTION_DAYS="14"
export LOG_RETENTION_DAYS="30"
export RESTIC_RETENTION_DAYS="90"
export BACKUP_KEEP_MIN="3"
export MIN_FREE_MB="0"
export DISK_SAFETY_FACTOR="1"
export NOTIFY_EMAIL=""
export NOTIFY_COMMAND=""
export HEALTHCHECK_URL=""
EOF
}

# -----------------------------------------------------------------------------
# Ejecución de backupctl bajo prueba
# -----------------------------------------------------------------------------
# Siempre con -p y con la entrada estándar cerrada. Se niega —y lo deja escrito
# en $BANCO_TMP/.resultados, no solo en una variable— si el perfil no está
# dentro de $BANCO_TMP: sin esto, un error en una suite podría acabar usando
# el perfil real (T3). Compara realpath -e/-m de los dos lados: perfil y
# $BANCO_TMP, por si este último llegara por un enlace simbólico. Si
# cualquiera de los dos realpath falla o devuelve vacío, SE NIEGA: ninguna
# rama del case de abajo puede aceptar con una base vacía (ronda #008: con
# base="", "$base"/*|"$base" se volvía /*|"", que aceptaba cualquier ruta).
backupctl_prueba() {
  local perfil_dir="$1"; shift
  local real base negar=1
  real="$(realpath -m -- "$perfil_dir" 2>/dev/null || true)"
  base="$(realpath -e -- "$BANCO_TMP" 2>/dev/null || true)"
  if [[ -n "$real" && -n "$base" ]]; then
    case "$real" in
      "$base"/*|"$base") negar=0 ;;
    esac
  fi
  if (( negar == 0 )); then
    "$BANCO_RAIZ/bin/backupctl" -p "$perfil_dir/env.sh" "$@" </dev/null
    return $?
  fi
  echo "  FALLO: backupctl_prueba se niega a ejecutar: '$perfil_dir' (resuelto: '$real') está fuera de \$BANCO_TMP ('$base')" >&2
  printf 'FALLO\tbackupctl_prueba se niega: %s (resuelto: %s) esta fuera de %s\n' "$perfil_dir" "$real" "$base" >> "$BANCO_TMP/.resultados"
  return 97
}

# -----------------------------------------------------------------------------
# Guiones para las órdenes falsas de MySQL
# -----------------------------------------------------------------------------
# Un único guion de 'mysql' sirve para respaldo, verificación y restauración:
# cubre la conexión, las consultas de inventario y, sin -e, el SQL que llega
# por la entrada estándar (restore.sh). Las respuestas están documentadas en
# el ADR 0009 y .agents/context/40-entorno.md, y confirmadas contra
# lib/mysql.sh, lib/backup.sh y lib/restore.sh — son sintéticas, no salidas
# reales de MySQL.
#
# Parámetros, todos opcionales tras <tmp>:
#   destino_existe    "SELECT COUNT(*) ... schema_name='<x>'" (restore.sh:74,
#                     lib/mysql.sh bc_mysql_table_count) responde esto en vez
#                     de "0": el destino de un --into ya existe.
#   tablas_existentes "SELECT COUNT(*) ... table_type='BASE TABLE'" responde
#                     esto: cuántas tablas tiene ya ese destino.
#   fallar_conexion   "1" hace que "SELECT 1" (bc_mysql_check) escriba un
#                     error en stderr y salga con 1, en vez de conectar.
escribir_guion_mysql() {
  local tmp="$1" destino_existe="${2:-0}" tablas_existentes="${3:-0}" fallar_conexion="${4:-0}"
  mkdir -p "$tmp/guion" "$tmp/registro"
  {
    printf 'BC_DESTINO_EXISTE=%q\n' "$destino_existe"
    printf 'BC_TABLAS_EXISTENTES=%q\n' "$tablas_existentes"
    printf 'BC_FALLAR_CONEXION=%q\n' "$fallar_conexion"
    cat <<'GUION'
consulta=""
for ((_i = 1; _i <= $#; _i++)); do
  if [[ "${!_i}" == "-e" ]]; then
    _j=$(( _i + 1 ))
    consulta="${!_j}"
  fi
done

if [[ -z "$consulta" ]]; then
  # SQL por la entrada estándar: solo lo usa restore (y verify --restore-test,
  # que estas suites no ejercitan). Se numera por orden de llegada.
  n=1
  while [[ -f "$BANCO_TMP/registro/mysql.stdin.$n" ]]; do n=$(( n + 1 )); done
  cat > "$BANCO_TMP/registro/mysql.stdin.$n"
  { printf '%q ' "$@"; echo; } > "$BANCO_TMP/registro/mysql.stdin.$n.args"
  exit 0
fi

case "$consulta" in
  *'SELECT 1'*)
    if [[ "$BC_FALLAR_CONEXION" == "1" ]]; then
      echo "ERROR 1045 (28000): Access denied for user" >&2
      exit 1
    fi
    exit 0 ;;
  *"schema_name='"*) echo "$BC_DESTINO_EXISTE"; exit 0 ;;
  *"table_type='BASE TABLE'"*) echo "$BC_TABLAS_EXISTENTES"; exit 0 ;;
  *'COUNT(*)'*) echo "0"; exit 0 ;;
  *'VERSION()'*) echo "10.11.0-sintetico"; exit 0 ;;
  *'SUM(data_length'*) echo "1024"; exit 0 ;;
  *"NOT IN ('InnoDB')"*) exit 0 ;;
  *'default_character_set_name'*) printf 'utf8mb4\tutf8mb4_general_ci\n'; exit 0 ;;
  *'information_schema.VIEWS'*) exit 0 ;;
  *'information_schema.schemata'*) printf 'blog\ntienda\n'; exit 0 ;;
  *) echo "falso mysql: consulta inesperada: $consulta" >&2; exit 97 ;;
esac
GUION
  } > "$tmp/guion/mysql.sh"
}

# Guion de 'mysqldump'. Sin fallo (db_falla vacío) siempre limpio; con
# db_falla/segmento_falla, ESE volcado concreto escribe un error en stderr y
# sale con 0 — la mentira de --force que hace fallar el respaldo sin que lo
# delate el código de salida (lib/backup.sh:52-60).
escribir_guion_mysqldump() {
  local tmp="$1" db_falla="${2:-}" segmento_falla="${3:-}"
  mkdir -p "$tmp/guion" "$tmp/registro"
  {
    printf 'BC_DB_FALLA=%q\n' "$db_falla"
    printf 'BC_SEGMENTO_FALLA=%q\n' "$segmento_falla"
    cat <<'GUION'
if [[ "${1:-}" == "--help" ]]; then
  exit 0
fi

_no_data=0; _no_create_info=0; _skip_triggers=0; _routines=0; _triggers=0
_db=""
for _a in "$@"; do
  case "$_a" in
    --no-data) _no_data=1 ;;
    --no-create-info) _no_create_info=1 ;;
    --skip-triggers) _skip_triggers=1 ;;
    --routines) _routines=1 ;;
    --triggers) _triggers=1 ;;
    --*) ;;
    *) _db="$_a" ;;
  esac
done

if (( _routines )); then
  echo "-- backupctl-pruebas: funciones sintéticas"
  exit 0
elif (( _triggers )); then
  echo "-- backupctl-pruebas: triggers y eventos sintéticos"
  exit 0
elif (( _no_data && _skip_triggers && ! _no_create_info )); then
  if [[ -n "$BC_DB_FALLA" && "$_db" == "$BC_DB_FALLA" && "$BC_SEGMENTO_FALLA" == "tables" ]]; then
    echo "mysqldump: Got error: 1045: Access denied" >&2
    exit 0
  fi
  echo "CREATE TABLE \`t\` (\`id\` int);"
  exit 0
elif (( _no_create_info && _skip_triggers && ! _no_data )); then
  if [[ -n "$BC_DB_FALLA" && "$_db" == "$BC_DB_FALLA" && "$BC_SEGMENTO_FALLA" == "data" ]]; then
    echo "mysqldump: Got error: 1045: Access denied" >&2
    exit 0
  fi
  echo "INSERT INTO \`t\` VALUES (1);"
  exit 0
else
  echo "falso mysqldump: combinación de opciones inesperada: $*" >&2
  exit 97
fi
GUION
  } > "$tmp/guion/mysqldump.sh"
}
