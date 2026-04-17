#!/bin/bash

# Mover a directorio del script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
cd "$DIR"

source ./env.sh

# Configuración
USER="$MYSQL_USER"
PASS="$MYSQL_PASS"
EXCLUDE_DBS="('information_schema','performance_schema','mysql','sys','phpmyadmin')"
OUTPUT_DIR="/home/$USER_NAME/scripts/output/mysql_backups"
TEMP_DIR="/home/$USER_NAME/scripts/output/temp_sql_$(date +%s)" # Carpeta temporal única
ZIP_NAME="all_databases_$(date +%Y%m%d_%H%M%S).zip"

# Preparar directorios
mkdir -p "$OUTPUT_DIR"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "Creando temporales en: $TEMP_DIR"

# Obtener lista de bases de datos
DBS=$(mysql -u$USER -p$PASS -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN $EXCLUDE_DBS" -s --skip-column-names)

# Usar while para procesar cada base de datos como una línea completa
echo "$DBS" | while read -r DB; do
    echo "Respaldando: $DB..."
    DB_PATH="$TEMP_DIR/$DB"
    mkdir -p "$DB_PATH"

    # Extraer Charset y Collation originales
    DB_INFO=$(mysql -u$USER -p$PASS -e "SELECT default_character_set_name, default_collation_name FROM information_schema.schemata WHERE schema_name = '$DB'" -s --skip-column-names)
    CHARSET=$(echo "$DB_INFO" | awk '{print $1}')
    COLLATE=$(echo "$DB_INFO" | awk '{print $2}')

    # Header común para todos los archivos con comillas invertidas de seguridad
    HEADER="USE \`$DB\`;"
    SED_CLEAN="sed -e 's/DEFINER=[^*]*\*/\*/g' -e 's/DEFINER[ ]*=[ ]*[^*]*//g'"

    # 1. database.sql (Con Charset y Collation exactos)
    echo "CREATE DATABASE IF NOT EXISTS \`$DB\` CHARACTER SET $CHARSET COLLATE $COLLATE;" > "$DB_PATH/database.sql"
    echo "$HEADER" >> "$DB_PATH/database.sql"

    # Función para generar archivos con USE al principio
    dump_segment() {
        local file=$1
        local options=$2
        echo "$HEADER" > "$DB_PATH/$file"
        # Evaluamos el dump, limpiamos definers y quitamos headers de comentarios de mysqldump para un archivo más limpio
        # --single-transaction evita LOCK TABLES
        # --force permite que el script siga aunque falte una tabla o el definer sea inválido
        mysqldump -u$USER -p$PASS --single-transaction --force $options "$DB" | eval "$SED_CLEAN" >> "$DB_PATH/$file"
    }

    # 2. tables.sql (Estructura de tablas)
    dump_segment "tables.sql" "--no-data --skip-triggers --no-create-db"

    # 3. data.sql (Datos)
    dump_segment "data.sql" "--no-create-info --skip-triggers --no-create-db"

    # 4. views.sql (Vistas)
    # Identificar vistas para no dumpear tablas de nuevo
    VIEWS=$(mysql -u$USER -p$PASS -e "SELECT TABLE_NAME FROM information_schema.VIEWS WHERE TABLE_SCHEMA = '$DB'" -s --skip-column-names)
    echo "$HEADER" > "$DB_PATH/views.sql"
    if [ ! -z "$VIEWS" ]; then
        # Procesar vistas una a una para evitar errores con espacios en los nombres
        echo "$VIEWS" | while read -r VIEW_NAME; do
            mysqldump -u$USER -p$PASS --single-transaction --force --no-data --no-create-info --skip-triggers "$DB" "$VIEW_NAME" | eval "$SED_CLEAN" >> "$DB_PATH/views.sql"
        done
    fi

    # 5. functions.sql (Rutinas)
    dump_segment "functions.sql" "--no-create-info --no-data --no-create-db --routines --skip-triggers"

    # 6. others.sql (Triggers y Eventos)
    dump_segment "others.sql" "--no-create-info --no-data --no-create-db --triggers --events"

done

# Empaquetar en el directorio de salida
cd "$TEMP_DIR"

# 1. Comprimir todos los .sql a .gz de forma masiva (muy rápido)
echo "Comprimiendo archivos SQL a .gz..."
find . -name "*.sql" -exec gzip {} \;

# 2. Crear el ZIP final con los archivos ya gzipeados
FINAL_ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
echo "Creando zip final: $FINAL_ZIP_PATH..."
zip -r9 "$FINAL_ZIP_PATH" . > /dev/null

cd "$DIR"

# Limpiar carpeta temporal
rm -rf "$TEMP_DIR"

echo "Respaldo completado en $OUTPUT_DIR/$ZIP_NAME"