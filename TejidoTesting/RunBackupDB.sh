#!/bin/bash
# =============================================================================
# Respaldo modular de bases de datos MySQL
# =============================================================================
# Genera por cada BD:
#   database.sql  — CREATE DATABASE con Charset/Collation exactos
#   tables.sql    — Estructura de tablas (sin datos, sin triggers)
#   data.sql      — Datos (sin estructura, sin triggers)
#   views.sql     — Definiciones de vistas (CREATE VIEW)
#   functions.sql — Rutinas (funciones y procedimientos almacenados)
#   others.sql    — Triggers y eventos
#
# Todos los archivos se comprimen a .gz y se empaquetan en un .zip final.
# Los DEFINERs se eliminan de todos los dumps para evitar errores de permisos
# al restaurar en un entorno diferente.
# =============================================================================

# Mover al directorio del script para que las rutas relativas sean predecibles
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

source ./env.sh

# -----------------------------------------------------------------------------
# Configuración — ajustar antes de ejecutar
# -----------------------------------------------------------------------------

USER="$MYSQL_USER"
PASS="$MYSQL_PASS" # Dejar vacío si el usuario no tiene contraseña

# Bases de datos del sistema que nunca se respaldan
EXCLUDE_DBS="('information_schema','performance_schema','mysql','sys','phpmyadmin')"

# Directorio final donde quedará el .zip
OUTPUT_DIR="/home/$USER_NAME/scripts/output/mysql_backups"

# Carpeta temporal con sufijo de timestamp para evitar colisiones si el script
# corre dos veces de forma simultánea
TEMP_DIR="/home/$USER_NAME/scripts/output/temp_sql_$(date +%s)"

# Nombre del archivo .zip final
ZIP_NAME="all_databases_$(date +%Y%m%d_%H%M%S).zip"

# Opciones comunes a todos los llamados de mysqldump:
#   --single-transaction  — snapshot consistente sin LOCK TABLES (InnoDB)
#   --force               — continúa aunque falle un objeto concreto
#   --no-tablespaces      — omite TABLESPACE (requeriría PROCESS privilege)
DUMP_COMMON="--single-transaction --force --no-tablespaces"

# Flag de contraseña: si PASS está vacío no se pasa -p para evitar el warning
# "Using a password on the command line interface can be insecure" innecesario,
# y también para que funcionen usuarios sin contraseña (ej. root local via socket).
if [[ -n "$PASS" ]]; then
  PASS_FLAG="-p$PASS"
else
  PASS_FLAG=""
fi

# Wrappers que incluyen las credenciales correctas en cada llamado
mysql_cmd()     { mysql     -u"$USER" $PASS_FLAG "$@"; }
mysqldump_cmd() { mysqldump -u"$USER" $PASS_FLAG "$@"; }

# Pipeline que elimina el DEFINER de rutinas/vistas/triggers.
# Se aplica a TODOS los segmentos para garantizar portabilidad.
SED_CLEAN="sed \
  -e 's/DEFINER=[^ ]* / /g' \
  -e 's/DEFINER=[^ ]*\*/* /g' \
  -e 's/DEFINER=[^ ]*PROCEDURE/PROCEDURE/g' \
  -e 's/DEFINER=[^ ]*FUNCTION/FUNCTION/g' \
  -e 's/DEFINER=[^ ]*EVENT/EVENT/g' \
  -e 's/DEFINER=[^ ]*TRIGGER/TRIGGER/g' \
  -e 's/DEFINER=[^ ]*VIEW/VIEW/g' \
  -e 's/\/\*!50013 DEFINER=[^*]*\*\///g'"

# -----------------------------------------------------------------------------
# Preparación de directorios
# -----------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "Directorio temporal: $TEMP_DIR"
echo "Destino final:       $OUTPUT_DIR/$ZIP_NAME"
echo ""

# -----------------------------------------------------------------------------
# Obtener la lista de bases de datos a respaldar (excluye las del sistema)
# -----------------------------------------------------------------------------
DBS=$(mysql_cmd \
  -e "SELECT schema_name
      FROM information_schema.schemata
      WHERE schema_name NOT IN $EXCLUDE_DBS" \
  -s --skip-column-names 2>/dev/null)

if [ -z "$DBS" ]; then
  echo "ERROR: No se encontraron bases de datos para respaldar." >&2
  echo "       Verifica las credenciales y los permisos de MySQL."  >&2
  exit 1
fi

# Contar y mostrar cuántas BDs se procesarán antes de empezar
DB_COUNT=$(echo "$DBS" | grep -c '.')
echo "Bases de datos a respaldar: $DB_COUNT"
echo "$DBS" | sed 's/^/  - /'
echo ""

# =============================================================================
# Bucle principal — se usa process substitution (<(...)) en lugar de pipe
# para que el while corra en el shell actual y pueda propagar errores/variables
# =============================================================================
while IFS= read -r DB; do

  # Saltamos líneas vacías que pudiera generar mysql en ciertos entornos
  [ -z "$DB" ] && continue

  echo "=== Respaldando: $DB ==="

  # Directorio individual por BD; comillas para soportar nombres con espacios
  DB_PATH="$TEMP_DIR/$DB"
  mkdir -p "$DB_PATH"

  # ---------------------------------------------------------------------------
  # Obtener Charset y Collation originales de la BD
  # ---------------------------------------------------------------------------
  DB_INFO=$(mysql_cmd \
    -e "SELECT default_character_set_name, default_collation_name
        FROM information_schema.schemata
        WHERE schema_name = '$DB'" \
    -s --skip-column-names 2>/dev/null)

  CHARSET=$(echo "$DB_INFO" | awk '{print $1}')
  COLLATE=$(echo "$DB_INFO" | awk '{print $2}')

  # Cabecera USE que se antepone a cada segmento para que el archivo sea
  # auto-contenido y restaurable con: mysql < archivo.sql
  HEADER="USE \`$DB\`;"

  # ---------------------------------------------------------------------------
  # Función auxiliar: vuelca un segmento con las opciones dadas, prepende
  # el header USE y aplica la limpieza de DEFINERs.
  # Uso: dump_segment <nombre_archivo> <opciones_extra_mysqldump>
  # Soporta nombres de BD con espacios gracias a las comillas en "$DB"
  # ---------------------------------------------------------------------------
  dump_segment() {
    local file="$1"
    local options="$2"
    # El header va primero; el dump se añade a continuación
    echo "$HEADER" > "$DB_PATH/$file"
    # shellcheck disable=SC2086   # Las opciones deben expandirse sin comillas
    mysqldump_cmd $DUMP_COMMON $options "$DB" \
      2>/dev/null | eval "$SED_CLEAN" >> "$DB_PATH/$file"
  }

  # ---------------------------------------------------------------------------
  # 1. database.sql — Sentencia CREATE DATABASE con charset/collation exactos
  #    No depende de mysqldump; se construye directamente.
  # ---------------------------------------------------------------------------
  echo "  [1/6] database.sql"
  {
    echo "CREATE DATABASE IF NOT EXISTS \`$DB\`"
    echo "  CHARACTER SET $CHARSET"
    echo "  COLLATE $COLLATE;"
    echo "$HEADER"
  } > "$DB_PATH/database.sql"

  # ---------------------------------------------------------------------------
  # 2. tables.sql — Estructura de tablas (DDL puro, sin datos ni triggers)
  # ---------------------------------------------------------------------------
  echo "  [2/6] tables.sql"
  dump_segment "tables.sql" \
    "--no-data --skip-triggers --no-create-db"

  # ---------------------------------------------------------------------------
  # 3. data.sql — Filas de todas las tablas (sin DDL ni triggers)
  # ---------------------------------------------------------------------------
  echo "  [3/6] data.sql"
  dump_segment "data.sql" \
    "--no-create-info --skip-triggers --no-create-db"

  # ---------------------------------------------------------------------------
  # 4. views.sql — Definiciones de vistas (CREATE VIEW)
  #
  #    IMPORTANTE: las vistas son objetos de solo-estructura; mysqldump las
  #    exporta con --no-data (como cualquier tabla).  NO se usa --no-create-info
  #    porque esa flag es la que contiene la sentencia CREATE VIEW.
  #
  #    Se listan las vistas primero para volcar cada una individualmente,
  #    lo que permite manejar nombres con espacios de forma segura.
  # ---------------------------------------------------------------------------
  echo "  [4/6] views.sql"
  echo "$HEADER" > "$DB_PATH/views.sql"

  # Obtener nombres de vistas; IFS vacío + read -r preservan espacios
  VIEWS=$(mysql_cmd \
    -e "SELECT TABLE_NAME
        FROM information_schema.VIEWS
        WHERE TABLE_SCHEMA = '$DB'" \
    -s --skip-column-names 2>/dev/null)

  if [[ -n "$VIEWS" ]]; then
    while IFS= read -r VIEW_NAME; do
      [ -z "$VIEW_NAME" ] && continue
      echo "    Vista: $VIEW_NAME"
      # Volcamos solo la vista indicada; --no-data exporta el CREATE VIEW
      # Sin --no-create-info (eso suprimiría la definición de la vista)
      mysqldump_cmd $DUMP_COMMON \
        --no-data --no-create-db --skip-triggers \
        "$DB" "$VIEW_NAME" \
        2>/dev/null | eval "$SED_CLEAN" >> "$DB_PATH/views.sql"
    done < <(echo "$VIEWS")
  else
    echo "    (sin vistas)"
  fi

  # ---------------------------------------------------------------------------
  # 5. functions.sql — Rutinas: funciones y procedimientos almacenados
  #    --routines activa el dump de rutinas; sin --no-create-info mysqldump
  #    incluiría también las tablas; usamos --no-data + --no-create-info
  #    para que solo salgan las rutinas.
  # ---------------------------------------------------------------------------
  echo "  [5/6] functions.sql"
  dump_segment "functions.sql" \
    "--no-create-info --no-data --no-create-db --routines --skip-triggers"

  # ---------------------------------------------------------------------------
  # 6. others.sql — Triggers y eventos
  #    --triggers + --events; igual que en functions, suprimimos tablas y datos.
  # ---------------------------------------------------------------------------
  echo "  [6/6] others.sql"
  dump_segment "others.sql" \
    "--no-create-info --no-data --no-create-db --triggers --events"

  echo "  OK: $DB"
  echo ""

done < <(echo "$DBS")

# =============================================================================
# Empaquetado — comprimir y zipar
# =============================================================================
cd "$TEMP_DIR"

# Paso 1: comprimir cada .sql a .gz individualmente
# Esto reduce el tamaño del zip final, ya que el contenido ya llega comprimido.
echo "Comprimiendo archivos SQL a .gz..."
find . -name "*.sql" -exec gzip -9 {} \;

# Paso 2: empaquetar los .gz en un zip único para facilitar la descarga/transferencia
FINAL_ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
echo "Creando zip final: $FINAL_ZIP_PATH"
# -0: no re-comprimir (los .gz ya están comprimidos; re-comprimir no gana nada
#     y consumiría CPU sin reducir el tamaño del archivo final)
zip -r0 "$FINAL_ZIP_PATH" . > /dev/null

cd "$DIR"

# =============================================================================
# Limpieza
# =============================================================================
rm -rf "$TEMP_DIR"

echo ""
echo "Respaldo completado: $OUTPUT_DIR/$ZIP_NAME"