#!/usr/bin/env bash
# =============================================================================
# lib/mysql.sh — acceso a MySQL / MariaDB
# =============================================================================
# Encapsula la conexión, el listado de objetos y las primitivas de volcado.
# Todo lo que hable con la base de datos pasa por aquí.
# =============================================================================

[[ -n "${BC_MYSQL_LOADED:-}" ]] && return 0
BC_MYSQL_LOADED=1

BC_DEFAULTS_FILE=""

# -----------------------------------------------------------------------------
# Fichero de credenciales
# -----------------------------------------------------------------------------
# Se usa --defaults-extra-file en lugar de -p en la línea de órdenes por un
# motivo funcional: con -p, el cliente escribe en stderr "Using a password on
# the command line interface can be insecure" en CADA invocación. Son 6
# volcados por base de datos, así que con 76 bases serían ~456 líneas de ruido
# — y la detección de errores se basa precisamente en leer stderr. Con el
# fichero, stderr queda limpio y cualquier línea que aparezca ahí es señal real
# de fallo.
#
# De paso centraliza usuario, host, puerto, socket y charset en un solo sitio.
# -----------------------------------------------------------------------------
bc_mysql_init() {
  [[ -n "$BC_DEFAULTS_FILE" && -f "$BC_DEFAULTS_FILE" ]] && return 0
  BC_DEFAULTS_FILE="$(mktemp "${TMPDIR:-/tmp}/.backupctl-my.XXXXXXXX")"
  {
    echo "[client]"
    echo "user=$MYSQL_USER"
    [[ -n "$MYSQL_PASS"   ]] && echo "password=$MYSQL_PASS"
    [[ -n "$MYSQL_HOST"   ]] && echo "host=$MYSQL_HOST"
    [[ -n "$MYSQL_PORT"   ]] && echo "port=$MYSQL_PORT"
    [[ -n "$MYSQL_SOCKET" ]] && echo "socket=$MYSQL_SOCKET"
    echo "default-character-set=$MYSQL_CHARSET"
  } > "$BC_DEFAULTS_FILE"
  bc_debug "fichero de credenciales: $BC_DEFAULTS_FILE"
}

bc_mysql_cleanup() {
  [[ -n "$BC_DEFAULTS_FILE" && -f "$BC_DEFAULTS_FILE" ]] && rm -f "$BC_DEFAULTS_FILE"
  BC_DEFAULTS_FILE=""
}

# Se usa --defaults-file y NO --defaults-extra-file.
#
# La diferencia importa: --defaults-extra-file se lee ANTES que ~/.my.cnf, así
# que un `password=` en /root/.my.cnf —habitual en servidores con HestiaCP—
# pisa el nuestro y la conexión falla con "Access denied" pese a tener la
# contraseña correcta. Con --defaults-file solo se lee nuestro archivo y el
# resultado es el mismo en cualquier máquina y con cualquier usuario.
#
# La contrapartida es que tampoco se leen /etc/mysql/my.cnf ni similares: por
# eso el fichero incluye host, puerto y socket cuando el perfil los declara.
bc_mysql()     { bc_mysql_init; mysql     --defaults-file="$BC_DEFAULTS_FILE" "$@"; }
bc_mysqldump() { bc_mysql_init; mysqldump --defaults-file="$BC_DEFAULTS_FILE" "$@"; }

# Consulta que devuelve valores en crudo, sin cabeceras ni marco
bc_mysql_q() { bc_mysql -s --skip-column-names -e "$1"; }

# -----------------------------------------------------------------------------
# Conexión
# -----------------------------------------------------------------------------
# Comprueba de verdad que se puede conectar, y explica el motivo si no. Es la
# diferencia entre "no se encontraron bases de datos" (confuso) y "acceso
# denegado para el usuario X" (accionable).
bc_mysql_check() {
  bc_mysql_init
  local errf; errf="$(mktemp)"
  if bc_mysql -e "SELECT 1" >/dev/null 2>"$errf"; then
    rm -f "$errf"; return 0
  fi
  bc_err "no se pudo conectar a MySQL como '$MYSQL_USER':"
  sed 's/^/        /' "$errf" >&2
  rm -f "$errf"
  return 1
}

bc_mysql_version() { bc_mysql_q "SELECT VERSION()" 2>/dev/null || echo "desconocida"; }

# Privilegios del usuario configurado: sirve para diagnosticar por qué falla un
# volcado antes de que falle.
bc_mysql_grants() { bc_mysql_q "SHOW GRANTS" 2>/dev/null || true; }

# -----------------------------------------------------------------------------
# Escapado
# -----------------------------------------------------------------------------
# Literal SQL. No es solo higiene: un nombre de base de datos con comilla simple
# rompería la consulta.
bc_sql_quote() {
  local s=${1//\\/\\\\}
  s=${s//\'/\\\'}
  printf "'%s'" "$s"
}
# Identificador entre acentos graves
bc_sql_ident() {
  local s=${1//\`/\`\`}
  printf '`%s`' "$s"
}
# Nombre válido como carpeta: MySQL admite '/' dentro del nombre de una BD
bc_safe_name() { printf '%s' "${1//\//_}"; }

# -----------------------------------------------------------------------------
# Inventario
# -----------------------------------------------------------------------------
bc_mysql_databases() {
  bc_mysql_q "SELECT schema_name
              FROM information_schema.schemata
              WHERE schema_name NOT IN $EXCLUDE_DBS
              ORDER BY schema_name"
}

bc_mysql_db_charset() {
  bc_mysql_q "SELECT default_character_set_name, default_collation_name
              FROM information_schema.schemata
              WHERE schema_name = $(bc_sql_quote "$1")"
}

bc_mysql_views() {
  bc_mysql_q "SELECT TABLE_NAME FROM information_schema.VIEWS
              WHERE TABLE_SCHEMA = $(bc_sql_quote "$1") ORDER BY TABLE_NAME"
}

bc_mysql_table_count() {
  bc_mysql_q "SELECT COUNT(*) FROM information_schema.tables
              WHERE table_schema = $(bc_sql_quote "$1") AND table_type='BASE TABLE'"
}

# Tamaño de una base de datos en bytes
bc_mysql_db_size() {
  bc_mysql_q "SELECT IFNULL(SUM(data_length+index_length),0)
              FROM information_schema.tables
              WHERE table_schema = $(bc_sql_quote "$1")"
}

# Tamaño total de lo que se va a respaldar. Se usa para estimar si cabe en disco.
bc_mysql_total_size() {
  bc_mysql_q "SELECT IFNULL(SUM(data_length+index_length),0)
              FROM information_schema.tables
              WHERE table_schema NOT IN $EXCLUDE_DBS"
}

# Tablas cuyo motor no es transaccional. --single-transaction no garantiza
# coherencia en ellas: conviene saberlo, no es motivo para abortar.
bc_mysql_non_innodb() {
  bc_mysql_q "SELECT CONCAT(table_schema,'.',table_name,' (',engine,')')
              FROM information_schema.tables
              WHERE engine IS NOT NULL AND engine NOT IN ('InnoDB')
                AND table_schema NOT IN $EXCLUDE_DBS
              LIMIT 50"
}

# -----------------------------------------------------------------------------
# Opciones de mysqldump
# -----------------------------------------------------------------------------
#   --single-transaction  instantánea coherente sin bloquear (solo InnoDB)
#   --force               continúa aunque falle un objeto: preferimos un volcado
#                         parcial CON AVISO a no tener nada. El fallo se detecta
#                         igualmente leyendo stderr.
#   --no-tablespaces      omite TABLESPACE (exigiría el privilegio PROCESS)
#   --hex-blob            binarios en hexadecimal: evita que un BLOB corrompa el
#                         .sql al restaurar
#   --default-character-set  evita la corrupción silenciosa de emojis y
#                         caracteres multibyte si el cliente negocia latin1
# -----------------------------------------------------------------------------
BC_DUMP_OPTS=()
bc_mysqldump_opts() {
  if (( ${#BC_DUMP_OPTS[@]} > 0 )); then printf '%s\n' "${BC_DUMP_OPTS[@]}"; return; fi

  BC_DUMP_OPTS=(
    --single-transaction
    --force
    --no-tablespaces
    --hex-blob
    "--default-character-set=$MYSQL_CHARSET"
  )

  # Opciones que solo existen en algunas versiones del cliente
  local help; help="$(mysqldump --help 2>/dev/null || true)"
  # Cliente MySQL 8 contra servidor MariaDB: sin esto falla al leer estadísticas
  grep -q -- '--column-statistics' <<<"$help" && BC_DUMP_OPTS+=(--column-statistics=0)
  # Evita que el volcado arrastre SET @@GLOBAL.GTID_PURGED, que impide
  # restaurarlo en un servidor distinto: clave para la migración.
  grep -q -- '--set-gtid-purged' <<<"$help" && BC_DUMP_OPTS+=(--set-gtid-purged=OFF)

  printf '%s\n' "${BC_DUMP_OPTS[@]}"
}

# -----------------------------------------------------------------------------
# Eliminación de DEFINER — el corazón de la portabilidad
# -----------------------------------------------------------------------------
# Un volcado con DEFINER=`usuario`@`host` solo se restaura si ese usuario existe
# en el servidor de destino. Al quitarlo, el objeto pasa a pertenecer a quien
# restaura, que es lo que hace posible migrar a otra máquina.
#
# Además se cambia SQL SECURITY DEFINER por INVOKER: quitar el DEFINER pero
# dejar SECURITY DEFINER deja la vista o rutina en un estado ambiguo.
#
# NO se aplica a los datos: una fila que contenga el texto "DEFINER=" quedaría
# alterada, y data.sql es con diferencia el archivo más grande (pasarlo por sed
# alargaría el respaldo sin ninguna ganancia).
# -----------------------------------------------------------------------------
bc_strip_definers() {
  sed -E \
    -e 's/DEFINER=`[^`]*`@`[^`]*`[[:space:]]*//g' \
    -e "s/DEFINER='[^']*'@'[^']*'[[:space:]]*//g" \
    -e 's#/\*![0-9]{5} DEFINER=[^*]*\*/##g' \
    -e 's/SQL SECURITY DEFINER/SQL SECURITY INVOKER/g'
}
