#!/bin/bash

# ============================================================
# MIGRACIÓN COMPLETA DE BASES DE DATOS
# ============================================================
#
# ESTE ARCHIVO ES INVOCADO DESDE:
#
#   BASE_GENERAL.sh
#
# NO debe ejecutarse de forma independiente.
#
# Depende de las siguientes variables definidas por
# BASE_GENERAL.sh:
#
#   USER_DESTINO
#   BASE_DESTINO
#   IP_ORIGEN
#   SSH_ORIGEN
#   DBS
#
#
# ============================================================
#
# QUÉ HACE
#
#   Trae desde el servidor ORIGEN el contenido COMPLETO de
#   cada base de datos y lo deposita en la base equivalente
#   del servidor DESTINO, aunque:
#
#     - la base se llame distinto
#     - el usuario se llame distinto
#     - la contraseña sea distinta
#
#   Se migra:
#
#     tablas, datos, índices, claves foráneas,
#     vistas, procedimientos, funciones,
#     triggers, eventos,
#     charset y collation de la base
#
#   Se descarta:
#
#     DEFINER de vistas, rutinas, triggers y eventos
#     usuarios y grants del servidor origen
#
#
# POR QUÉ NO SE USA --databases
#
#   mysqldump, cuando recibe el nombre de la base como
#   argumento suelto, NO escribe CREATE DATABASE ni USE.
#
#   El dump resultante es "anónimo" y puede importarse en
#   una base con otro nombre.
#
#   Con --databases o --all-databases el dump quedaría
#   amarrado al nombre original y sobreescribiría la base
#   equivocada.
#
#
# CREDENCIALES
#
#   El acceso al MySQL del ORIGEN se resuelve en dos pasos
#   independientes:
#
#   1. PRIVILEGIO DEL SISTEMA
#
#      El usuario SSH puede ser root o un sudoer.
#
#        ORIGEN_SUDO="auto"  detecta cuál es el caso
#        ORIGEN_SUDO="true"  fuerza sudo
#        ORIGEN_SUDO="false" no usa sudo
#
#      Si sudo pide contraseña, se solicita UNA sola vez al
#      inicio y se entrega por STDIN mediante sudo -S.
#      Nunca aparece en la línea de comandos ni en los logs.
#
#   2. AUTENTICACIÓN DE MYSQL
#
#        socket : se conecta como el usuario del sistema.
#                 Requiere ser root (o llegar a root por
#                 sudo), que es el caso normal en HestiaCP.
#
#        cnf    : usa un defaults-file ya existente en el
#                 origen, por ejemplo /root/.my.cnf.
#
#        user   : usa un usuario y contraseña de MySQL.
#                 Se escriben en un defaults-file temporal
#                 en el origen con permisos 600 y se borra
#                 al terminar.
#
#      Con el modo "user" no hace falta sudo, siempre que
#      ese usuario tenga privilegios suficientes.
#
#   DESTINO : el cliente local, con el privilegio que
#             resuelva BASE_PRIVILEGIOS.sh.
#
#   Ninguna contraseña se pasa por línea de comandos ni se
#   escribe en los logs.
#
#   Si defines contraseñas en este archivo, protégelo:
#
#     chmod 600 BASE_MIGRAR_DB.sh
#
# ============================================================



# ============================================================
# === OPCIONES DE ESTE MÓDULO ===
# ============================================================

# ------------------------------------------------------------
# Vaciar la base destino antes de importar.
#
# true:
#
#   Elimina tablas, vistas, rutinas y eventos que existan
#   en el destino antes de importar.
#
#   Esto evita que sobrevivan objetos huérfanos de una
#   corrida anterior.
#
# false:
#
#   Solamente se aplica lo que el dump traiga.
# ------------------------------------------------------------

DB_LIMPIAR_DESTINO="${DB_LIMPIAR_DESTINO:-true}";


# ------------------------------------------------------------
# Convertir SQL SECURITY DEFINER en SQL SECURITY INVOKER.
#
# Al quitar el DEFINER, MySQL asigna como definer al usuario
# que importa (root del destino).
#
# Con SQL SECURITY DEFINER eso significa que la aplicación
# ejecutaría esas rutinas con permisos de root.
#
# true  -> ejecutan con los permisos del usuario de la app.
# false -> se conserva el comportamiento original.
# ------------------------------------------------------------

DB_FORZAR_INVOKER="${DB_FORZAR_INVOKER:-true}";


# ------------------------------------------------------------
# Comparar el número de filas de cada tabla entre origen
# y destino después de importar.
#
# En bases muy grandes esto puede tardar.
# ------------------------------------------------------------

DB_VERIFICAR_FILAS="${DB_VERIFICAR_FILAS:-true}";


# ------------------------------------------------------------
# Conservar el archivo .sql.gz descargado.
#
# Se guarda en la carpeta de la corrida, dentro del home del
# usuario, con permisos 600. No es accesible por web.
# ------------------------------------------------------------

DB_CONSERVAR_DUMP="${DB_CONSERVAR_DUMP:-true}";



# ============================================================
# === VALIDAR VARIABLES RECIBIDAS ===
# ============================================================

if [ -z "$USER_DESTINO" ]; then
  echo "ERROR: USER_DESTINO no está definido.";
  return 1 2>/dev/null || exit 1;
fi;


if [ -z "$BASE_DESTINO" ]; then
  echo "ERROR: BASE_DESTINO no está definido.";
  return 1 2>/dev/null || exit 1;
fi;


if [ -z "$IP_ORIGEN" ]; then
  echo "ERROR: IP_ORIGEN no está definido.";
  return 1 2>/dev/null || exit 1;
fi;


if [ -z "$SSH_ORIGEN" ]; then
  echo "ERROR: SSH_ORIGEN no está definido.";
  return 1 2>/dev/null || exit 1;
fi;


if [ "${#DBS[@]}" -eq 0 ]; then
  echo "ERROR: DBS no está definido.";
  return 1 2>/dev/null || exit 1;
fi;


if ! declare -F origen_exec >/dev/null; then

  echo "ERROR: BASE_PRIVILEGIOS.sh no ha sido cargado.";
  echo "BASE_GENERAL.sh debe hacer source de ese archivo primero.";

  return 1 2>/dev/null || exit 1;

fi;





# ============================================================
# === FUNCIONES AUXILIARES ===
# ============================================================

# ------------------------------------------------------------
# Escapa un valor para usarlo dentro de comillas simples
# en SQL.
# ------------------------------------------------------------

sql_quote() {

  local value="$1";

  echo "${value//\'/\'\'}";

}



# ============================================================
# === DETECTAR CAPACIDADES DE mysqldump EN EL ORIGEN ===
# ============================================================
#
# Las opciones disponibles cambian entre MySQL y MariaDB y
# entre versiones.
#
#   --no-tablespaces      evita necesitar el privilegio PROCESS
#   --column-statistics   solo existe en el cliente MySQL 8
#   --set-gtid-purged     no existe en MariaDB
#
# ============================================================

echo;
echo "============================================================";
echo "PREPARANDO MIGRACIÓN DE BASES DE DATOS";
echo "============================================================";
echo;
echo "Origen SSH : $SSH_TARGET";
echo "Bases      : ${#DBS[@]}";



DUMP_HELP="$(
  origen_exec "mysqldump --help" "" < /dev/null 2>/dev/null
)";


if [ -z "$DUMP_HELP" ]; then

  echo;
  echo "ERROR: No se pudo ejecutar mysqldump en el origen.";
  echo "Verificar el acceso SSH y que mysqldump exista.";

  return 1 2>/dev/null || exit 1;

fi;


DUMP_OPTS="--single-transaction";
DUMP_OPTS="$DUMP_OPTS --quick";
DUMP_OPTS="$DUMP_OPTS --routines";
DUMP_OPTS="$DUMP_OPTS --events";
DUMP_OPTS="$DUMP_OPTS --triggers";
DUMP_OPTS="$DUMP_OPTS --hex-blob";
DUMP_OPTS="$DUMP_OPTS --default-character-set=utf8mb4";


if echo "$DUMP_HELP" | grep -q -- '--no-tablespaces'; then
  DUMP_OPTS="$DUMP_OPTS --no-tablespaces";
fi;


if echo "$DUMP_HELP" | grep -q -- '--column-statistics'; then
  DUMP_OPTS="$DUMP_OPTS --column-statistics=0";
fi;


if echo "$DUMP_HELP" | grep -q -- '--set-gtid-purged'; then
  DUMP_OPTS="$DUMP_OPTS --set-gtid-purged=OFF";
fi;


echo "Opciones   : $DUMP_OPTS";



# ============================================================
# === PROCESAR CADA BASE DE DATOS ===
# ============================================================
#
# Formato esperado de DBS:
#
#   DOMINIO|DB_ORIGEN|DB_DESTINO|DB_USER_DESTINO|DB_PASS
#
# ============================================================

DB_MIGRACION_ERRORES=0;

DB_MIGRACION_FALLIDAS=();


for entry in "${DBS[@]}"
do

  IFS='|' read -r site db_origen db_destino db_user db_pass <<< "$entry";

  # ----------------------------------------------------------
  # Las bases sueltas vienen con el sitio marcado con @.
  # Solo cambia la etiqueta de los archivos: todo lo que
  # genera la corrida va al mismo sitio.
  # ----------------------------------------------------------

  case "$site" in
    @*) ETIQUETA="${site#@}";;
    *)  ETIQUETA="$site";;
  esac;


  PRIVATE="$DIR_CORRIDA";


  echo;
  echo "============================================================";
  echo "MIGRANDO BASE DE DATOS: $ETIQUETA";
  echo "============================================================";
  echo "  Origen  : $db_origen";
  echo "  Destino : $db_destino";
  echo "  Usuario : $db_user";
  echo "  Pass    : [NO SE MUESTRA]";


  if [ -z "$db_origen" ]; then

    echo "ERROR: No hay base de origen definida para $ETIQUETA.";
    DB_MIGRACION_ERRORES=$((DB_MIGRACION_ERRORES + 1));
    DB_MIGRACION_FALLIDAS+=("$site");
    continue;

  fi;



  TIMESTAMP="$(date '+%Y%m%d_%H%M%S')";

  DUMP_FILE="$PRIVATE/${ETIQUETA}_${db_origen}.sql.gz";

  LOG="$PRIVATE/${ETIQUETA}_database.log";


  mkdir -p "$PRIVATE";

  touch "$LOG";

  chmod 600 "$LOG";


  ESC_ORIGEN="$(sql_quote "$db_origen")";
  ESC_DESTINO="$(sql_quote "$db_destino")";


  {
    echo "============================================================";
    echo "MIGRACIÓN DE BASE DE DATOS";
    echo "============================================================";
    echo;
    echo "Fecha           : $(date '+%Y-%m-%d %H:%M:%S')";
    echo "Origen de la entrada: $ETIQUETA";
    echo "Servidor origen : $SSH_TARGET";
    echo "Base origen     : $db_origen";
    echo "Base destino    : $db_destino";
    echo "Usuario destino : $db_user";
    echo "Password        : [NO SE REGISTRA]";
    echo;
    echo "EQUIVALENCIA:";
    echo "  $ETIQUETA: $db_origen -> $db_destino";
    echo;
  } >> "$LOG";



  # ==========================================================
  # === VERIFICAR QUE LA BASE ORIGEN EXISTE ===
  # ==========================================================

  ORIGEN_INFO="$(
    sql_origen <<SQL
SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME = '$ESC_ORIGEN';
SQL
  )";


  if [ -z "$ORIGEN_INFO" ]; then

    echo "ERROR: La base '$db_origen' no existe en el origen.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: La base de origen no existe.";
      echo;
    } >> "$LOG";

    DB_MIGRACION_ERRORES=$((DB_MIGRACION_ERRORES + 1));
    DB_MIGRACION_FALLIDAS+=("$site");
    continue;

  fi;


  ORIGEN_CHARSET="$(echo "$ORIGEN_INFO" | awk '{print $1}')";
  ORIGEN_COLLATION="$(echo "$ORIGEN_INFO" | awk '{print $2}')";


  echo "Charset origen: $ORIGEN_CHARSET / $ORIGEN_COLLATION";



  # ==========================================================
  # === VERIFICAR QUE LA BASE DESTINO EXISTE ===
  # ==========================================================
  #
  # Debe haberla creado v-add-database en BASE_GENERAL.sh.
  #
  # ==========================================================

  DESTINO_EXISTE="$(
    sql_destino <<SQL
SELECT SCHEMA_NAME
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME = '$ESC_DESTINO';
SQL
  )";


  if [ -z "$DESTINO_EXISTE" ]; then

    echo "ERROR: La base '$db_destino' no existe en el destino.";
    echo "Debe crearse primero con v-add-database.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: La base de destino no existe.";
      echo;
    } >> "$LOG";

    DB_MIGRACION_ERRORES=$((DB_MIGRACION_ERRORES + 1));
    DB_MIGRACION_FALLIDAS+=("$site");
    continue;

  fi;



  # ==========================================================
  # === ALINEAR CHARSET Y COLLATION DE LA BASE ===
  # ==========================================================
  #
  # El dump no trae CREATE DATABASE, así que la base destino
  # conservaría el charset por defecto de Hestia.
  #
  # Las tablas traen su propio charset, pero el de la base
  # afecta a lo que se cree después.
  #
  # ==========================================================

  echo "Alineando charset de la base destino...";


  sql_destino <<SQL >/dev/null
ALTER DATABASE \`$db_destino\`
CHARACTER SET $ORIGEN_CHARSET
COLLATE $ORIGEN_COLLATION;
SQL


  {
    echo "Charset alineado: $ORIGEN_CHARSET / $ORIGEN_COLLATION";
    echo;
  } >> "$LOG";



  # ==========================================================
  # === VACIAR LA BASE DESTINO ===
  # ==========================================================

  if [ "$DB_LIMPIAR_DESTINO" = "true" ]; then

    echo "Vaciando base destino...";


    DROP_SQL="$(
      sql_destino <<SQL
SELECT CONCAT('DROP TABLE IF EXISTS \`', TABLE_NAME, '\`;')
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '$ESC_DESTINO' AND TABLE_TYPE = 'BASE TABLE'
UNION ALL
SELECT CONCAT('DROP VIEW IF EXISTS \`', TABLE_NAME, '\`;')
FROM information_schema.VIEWS
WHERE TABLE_SCHEMA = '$ESC_DESTINO'
UNION ALL
SELECT CONCAT('DROP ', ROUTINE_TYPE, ' IF EXISTS \`', ROUTINE_NAME, '\`;')
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = '$ESC_DESTINO'
UNION ALL
SELECT CONCAT('DROP EVENT IF EXISTS \`', EVENT_NAME, '\`;')
FROM information_schema.EVENTS
WHERE EVENT_SCHEMA = '$ESC_DESTINO';
SQL
    )";


    if [ -n "$DROP_SQL" ]; then

      {
        echo "SET FOREIGN_KEY_CHECKS = 0;";
        echo "$DROP_SQL";
        echo "SET FOREIGN_KEY_CHECKS = 1;";
      } | mysql_destino "$db_destino";

    fi;


    {
      echo "Base destino vaciada antes de importar.";
      echo;
    } >> "$LOG";

  fi;



  # ==========================================================
  # === DESCARGAR EL DUMP ===
  # ==========================================================
  #
  # El DEFINER se elimina en el mismo flujo, antes de que el
  # SQL llegue al servidor destino.
  #
  # ssh -C comprime el transporte.
  #
  # El subshell evita que set -o pipefail afecte al resto de
  # la migración.
  #
  # ==========================================================

  echo "Descargando dump...";


  SED_ARGS=(
    -E
    -e 's/DEFINER=`[^`]*`@`[^`]*`//g'
    -e "s/DEFINER='[^']*'@'[^']*'//g"
    -e 's/DEFINER="[^"]*"@"[^"]*"//g'
  );


  if [ "$DB_FORZAR_INVOKER" = "true" ]; then
    SED_ARGS+=( -e 's/SQL SECURITY DEFINER/SQL SECURITY INVOKER/g' );
  fi;


  (
    set -o pipefail;

    origen_exec \
      "mysqldump $MYSQL_ORIGEN_OPTS $DUMP_OPTS $(printf '%q' "$db_origen")" \
      "-C" < /dev/null 2>/dev/null |
    sed "${SED_ARGS[@]}" |
    gzip > "$DUMP_FILE";
  );


  if [ "$?" -ne 0 ]; then

    echo "ERROR: Falló la descarga del dump.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: Falló mysqldump o la transferencia.";
      echo;
    } >> "$LOG";

    rm -f "$DUMP_FILE";

    DB_MIGRACION_ERRORES=$((DB_MIGRACION_ERRORES + 1));
    DB_MIGRACION_FALLIDAS+=("$site");
    continue;

  fi;


  chmod 600 "$DUMP_FILE";


  DUMP_SIZE="$(stat -c '%s' "$DUMP_FILE" 2>/dev/null)";


  if [ -z "$DUMP_SIZE" ] || [ "$DUMP_SIZE" -lt 100 ]; then

    echo "ERROR: El dump está vacío o es demasiado pequeño.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: Dump vacío.";
      echo;
    } >> "$LOG";

    DB_MIGRACION_ERRORES=$((DB_MIGRACION_ERRORES + 1));
    DB_MIGRACION_FALLIDAS+=("$site");
    continue;

  fi;


  echo "Dump descargado: $DUMP_FILE";


  {
    echo "Dump: $DUMP_FILE";
    echo "Tamaño comprimido: $DUMP_SIZE bytes";
    echo;
  } >> "$LOG";



  # ==========================================================
  # === IMPORTAR ===
  # ==========================================================
  #
  # No se fuerza --default-character-set en el cliente:
  # el propio dump trae SET NAMES.
  #
  # ==========================================================

  echo "Importando...";


  # ----------------------------------------------------------
  # El estado de la importación se toma de la tubería, no de
  # la asignación.
  #
  # La versión anterior hacía IMPORT_ERR="$( ... | ... )" y
  # después leía ${PIPESTATUS[1]}. Para ese momento PIPESTATUS
  # ya describía la asignación, que es un solo comando, así
  # que el índice 1 venía vacío y la comprobación nunca se
  # llegaba a hacer: un fallo de importación habría pasado
  # inadvertido.
  #
  # Con el subshell y pipefail, $? es el fallo de cualquiera
  # de los dos lados de la tubería.
  # ----------------------------------------------------------

  IMPORT_ERR_FILE="$(mktemp)";

  chmod 600 "$IMPORT_ERR_FILE";


  (
    set -o pipefail;

    gunzip -c "$DUMP_FILE" |
    mysql_destino "$db_destino" >/dev/null 2>"$IMPORT_ERR_FILE";
  );


  IMPORT_RESULT=$?;


  IMPORT_ERR="$(cat "$IMPORT_ERR_FILE" 2>/dev/null)";

  rm -f "$IMPORT_ERR_FILE";


  if [ -n "$IMPORT_ERR" ]; then

    {
      echo "Salida del importador:";
      echo "$IMPORT_ERR";
      echo;
    } >> "$LOG";

  fi;


  if [ "$IMPORT_RESULT" -ne 0 ]; then

    echo "ERROR: Falló la importación. Revisar $LOG";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: Falló la importación.";
      echo;
    } >> "$LOG";

    DB_MIGRACION_ERRORES=$((DB_MIGRACION_ERRORES + 1));
    DB_MIGRACION_FALLIDAS+=("$site");
    continue;

  fi;



  # ==========================================================
  # === VERIFICAR INVENTARIO DE OBJETOS ===
  # ==========================================================

  echo "Verificando...";


  INVENTARIO_SQL_ORIGEN="
SELECT
  (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA='$ESC_ORIGEN' AND TABLE_TYPE='BASE TABLE'),
  (SELECT COUNT(*) FROM information_schema.VIEWS
     WHERE TABLE_SCHEMA='$ESC_ORIGEN'),
  (SELECT COUNT(*) FROM information_schema.ROUTINES
     WHERE ROUTINE_SCHEMA='$ESC_ORIGEN' AND ROUTINE_TYPE='PROCEDURE'),
  (SELECT COUNT(*) FROM information_schema.ROUTINES
     WHERE ROUTINE_SCHEMA='$ESC_ORIGEN' AND ROUTINE_TYPE='FUNCTION'),
  (SELECT COUNT(*) FROM information_schema.TRIGGERS
     WHERE TRIGGER_SCHEMA='$ESC_ORIGEN'),
  (SELECT COUNT(*) FROM information_schema.EVENTS
     WHERE EVENT_SCHEMA='$ESC_ORIGEN');
";


  INVENTARIO_SQL_DESTINO="${INVENTARIO_SQL_ORIGEN//$ESC_ORIGEN/$ESC_DESTINO}";


  INV_ORIGEN="$(sql_origen <<< "$INVENTARIO_SQL_ORIGEN")";
  INV_DESTINO="$(sql_destino <<< "$INVENTARIO_SQL_DESTINO")";


  {
    echo "INVENTARIO";
    echo "  tablas / vistas / procedimientos / funciones / triggers / eventos";
    echo "  origen  : $INV_ORIGEN";
    echo "  destino : $INV_DESTINO";
    echo;
  } >> "$LOG";


  echo "  origen  : $INV_ORIGEN";
  echo "  destino : $INV_DESTINO";


  INVENTARIO_OK="true";


  if [ "$INV_ORIGEN" != "$INV_DESTINO" ]; then

    INVENTARIO_OK="false";

    echo "AVISO: El inventario de objetos no coincide.";

  fi;



  # ==========================================================
  # === VERIFICAR FILAS POR TABLA ===
  # ==========================================================

  FILAS_OK="true";


  if [ "$DB_VERIFICAR_FILAS" = "true" ]; then

    TABLAS="$(
      sql_destino <<SQL
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '$ESC_DESTINO' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
SQL
    )";


    COUNT_SQL="";


    while read -r tabla
    do

      [ -z "$tabla" ] && continue;

      tabla_sql="${tabla//\`/\`\`}";
      tabla_txt="${tabla//\'/\'\'}";

      if [ -n "$COUNT_SQL" ]; then
        COUNT_SQL="$COUNT_SQL UNION ALL ";
      fi;

      COUNT_SQL="$COUNT_SQL SELECT '$tabla_txt', COUNT(*) FROM \`$tabla_sql\`";

    done <<< "$TABLAS";


    if [ -n "$COUNT_SQL" ]; then

      COUNT_SQL="$COUNT_SQL;";


      FILAS_ORIGEN="$(
        sql_origen "$db_origen" <<< "$COUNT_SQL" | sort
      )";


      FILAS_DESTINO="$(
        sql_destino "$db_destino" <<< "$COUNT_SQL" | sort
      )";


      if [ "$FILAS_ORIGEN" != "$FILAS_DESTINO" ]; then

        FILAS_OK="false";

        echo "AVISO: El conteo de filas no coincide.";

        {
          echo "DIFERENCIAS DE FILAS (origen | destino)";
          diff <(echo "$FILAS_ORIGEN") <(echo "$FILAS_DESTINO");
          echo;
        } >> "$LOG";

      else

        {
          echo "Conteo de filas: coincide en todas las tablas.";
          echo;
        } >> "$LOG";

      fi;

    fi;

  fi;



  # ==========================================================
  # === RESULTADO ===
  # ==========================================================

  if [ "$INVENTARIO_OK" = "true" ] && [ "$FILAS_OK" = "true" ]; then

    echo "RESULTADO: OK";

    {
      echo "RESULTADO: OK";
      echo;
    } >> "$LOG";

  else

    echo "RESULTADO: REVISAR";
    echo "Log: $LOG";

    {
      echo "RESULTADO: REVISAR";
      echo "La importación terminó sin error, pero la";
      echo "verificación encontró diferencias.";
      echo;
    } >> "$LOG";

    DB_MIGRACION_ERRORES=$((DB_MIGRACION_ERRORES + 1));
    DB_MIGRACION_FALLIDAS+=("$site");

  fi;



  # ==========================================================
  # === LIMPIEZA DEL DUMP ===
  # ==========================================================

  if [ "$DB_CONSERVAR_DUMP" != "true" ]; then

    rm -f "$DUMP_FILE";

    {
      echo "Dump eliminado según configuración.";
      echo;
    } >> "$LOG";

  fi;


  # El chown solo es necesario si el script no corre como
  # el propio usuario del panel.

  if [ "$USUARIO_LOCAL" != "$USER_DESTINO" ]; then

    "${priv_local[@]}" chown -R \
      "$USER_DESTINO":"$USER_DESTINO" "$PRIVATE" 2>/dev/null;

  fi;

done;



# ============================================================
# === RESUMEN ===
# ============================================================

echo;
echo "============================================================";
echo "MIGRACIÓN DE BASES DE DATOS TERMINADA";
echo "============================================================";


if [ "$DB_MIGRACION_ERRORES" -ne 0 ]; then

  echo;
  echo "Bases con error o diferencias: $DB_MIGRACION_ERRORES";
  echo "Revisar los logs en:";
  echo;
  echo "  $DIR_CORRIDA";
  echo;

else

  echo;
  echo "Todas las bases se migraron y verificaron correctamente.";
  echo;

fi;
