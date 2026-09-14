#!/usr/bin/env bash
# =============================================================================
# tests/lib.sh — biblioteca mínima del banco de pruebas (ADR 0009)
# =============================================================================
# La cargan las suites (tests/probar_*.sh). Nada de esto se ejecuta contra un
# servidor: los perfiles que crea viven siempre dentro de $BANCO_TMP, y
# backupctl_prueba se niega a usar uno que no lo esté.
# =============================================================================

[[ -n "${BC_PRUEBA_LIB_LOADED:-}" ]] && return 0
BC_PRUEBA_LIB_LOADED=1

BC_ASSERT_TOTAL=0
BC_ASSERT_FALLOS=0

# -----------------------------------------------------------------------------
# Afirmaciones
# -----------------------------------------------------------------------------
afirmar_codigo() {
  local esperado="$1" obtenido="$2" desc="$3"
  BC_ASSERT_TOTAL=$(( BC_ASSERT_TOTAL + 1 ))
  if [[ "$esperado" == "$obtenido" ]]; then
    echo "  ok: $desc"
  else
    BC_ASSERT_FALLOS=$(( BC_ASSERT_FALLOS + 1 ))
    echo "  FALLO: $desc (esperado código $esperado, obtenido $obtenido)"
  fi
}

afirmar_igual() {
  local a="$1" b="$2" desc="$3"
  BC_ASSERT_TOTAL=$(( BC_ASSERT_TOTAL + 1 ))
  if [[ "$a" == "$b" ]]; then
    echo "  ok: $desc"
  else
    BC_ASSERT_FALLOS=$(( BC_ASSERT_FALLOS + 1 ))
    echo "  FALLO: $desc (esperado '$b', obtenido '$a')"
  fi
}

afirmar_contiene() {
  local archivo="$1" patron="$2" desc="$3"
  BC_ASSERT_TOTAL=$(( BC_ASSERT_TOTAL + 1 ))
  if [[ -f "$archivo" ]] && grep -qE -- "$patron" "$archivo"; then
    echo "  ok: $desc"
  else
    BC_ASSERT_FALLOS=$(( BC_ASSERT_FALLOS + 1 ))
    echo "  FALLO: $desc (no se encontró '$patron' en $archivo)"
  fi
}

afirmar_no_contiene() {
  local archivo="$1" patron="$2" desc="$3"
  BC_ASSERT_TOTAL=$(( BC_ASSERT_TOTAL + 1 ))
  if [[ ! -f "$archivo" ]]; then
    BC_ASSERT_FALLOS=$(( BC_ASSERT_FALLOS + 1 ))
    echo "  FALLO: $desc (no existe $archivo)"
  elif grep -qE -- "$patron" "$archivo"; then
    BC_ASSERT_FALLOS=$(( BC_ASSERT_FALLOS + 1 ))
    echo "  FALLO: $desc (se encontró '$patron' en $archivo)"
  else
    echo "  ok: $desc"
  fi
}

afirmar_intacto() {
  local archivo="$1" copia="$2" desc="$3"
  BC_ASSERT_TOTAL=$(( BC_ASSERT_TOTAL + 1 ))
  if cmp -s "$archivo" "$copia"; then
    echo "  ok: $desc"
  else
    BC_ASSERT_FALLOS=$(( BC_ASSERT_FALLOS + 1 ))
    echo "  FALLO: $desc ($archivo difiere de $copia)"
  fi
}

fin_de_suite() {
  echo "  -- $BC_ASSERT_TOTAL afirmaciones, $BC_ASSERT_FALLOS fallidas --"
  (( BC_ASSERT_FALLOS == 0 ))
}

# -----------------------------------------------------------------------------
# Perfil sintético
# -----------------------------------------------------------------------------
# Declara TODAS las variables de forma explícita: nada se hereda del entorno
# (T13, .agents/context/30-trampas.md). BACKUP_WORK_DIR existe ya al volver de
# esta función: el bloqueo de 'backup' se toma antes de crear directorios y,
# si no existe, sale con 2 (core.sh:188, bin/backupctl:283).
crear_perfil() {
  local dir="$1"
  mkdir -p "$dir/output/mysql_backups" "$dir/output/HestiaCP" "$dir/logs"
  cat > "$dir/env.sh" <<EOF
export MYSQL_USER="prueba"
export MYSQL_PASS="falsa"
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
# Siempre con -p y con la entrada estándar cerrada. Se niega —y cuenta como
# afirmación fallida— si el perfil no está dentro de $BANCO_TMP: sin esto, un
# error en una suite podría acabar usando el perfil real (T3).
backupctl_prueba() {
  local perfil_dir="$1"; shift
  local real
  real="$(realpath -m -- "$perfil_dir" 2>/dev/null || true)"
  case "$real" in
    "$BANCO_TMP"/*|"$BANCO_TMP")
      "$BANCO_RAIZ/bin/backupctl" -p "$perfil_dir/env.sh" "$@" </dev/null
      return $?
      ;;
    *)
      BC_ASSERT_TOTAL=$(( BC_ASSERT_TOTAL + 1 ))
      BC_ASSERT_FALLOS=$(( BC_ASSERT_FALLOS + 1 ))
      echo "  FALLO: backupctl_prueba se niega a ejecutar: '$perfil_dir' (resuelto: '$real') está fuera de \$BANCO_TMP" >&2
      return 97
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Guiones para las órdenes falsas de MySQL
# -----------------------------------------------------------------------------
# Un único guion de 'mysql' sirve para respaldo, verificación y restauración:
# cubre la conexión, las consultas de inventario y, sin -e, el SQL que llega
# por la entrada estándar (restore.sh). Las respuestas están documentadas en
# el ADR 0009 y confirmadas contra lib/mysql.sh, lib/backup.sh y
# lib/restore.sh — son sintéticas, no salidas reales de MySQL.
escribir_guion_mysql() {
  local tmp="$1"
  mkdir -p "$tmp/guion" "$tmp/registro"
  cat > "$tmp/guion/mysql.sh" <<'GUION'
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
  *'SELECT 1'*) exit 0 ;;
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
