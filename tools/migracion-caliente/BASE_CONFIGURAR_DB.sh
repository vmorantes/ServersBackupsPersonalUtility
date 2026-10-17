#!/bin/bash

# ============================================================
# CONFIGURACIÓN SEGURA DE database.php
# ============================================================
#
# ESTE ARCHIVO ES INVOCADO DESDE:
#
#   BASE_GENERAL.sh
#
# NO debe ejecutarse normalmente de forma independiente.
#
# Depende de las siguientes variables definidas por
# BASE_GENERAL.sh:
#
#   USER_DESTINO
#   BASE_DESTINO
#   DOMINIOS
#   DBS
#
#
# ============================================================
#
# CAMPOS PERMITIDOS PARA MODIFICAR:
#
#   db
#   user
#   password
#
# CAMPOS QUE NO DEBEN MODIFICARSE:
#
#   host
#   cualquier otro contenido de database.php
#
#
# Si existen dos bloques de configuración, se considera que
# la ÚLTIMA aparición de cada campo corresponde a producción.
#
# Si existe un solo bloque, se utiliza ese bloque.
#
#
# PROCEDIMIENTO:
#
#   1. Localizar database.php.
#   2. Crear backup.
#   3. Generar archivo esperado.
#   4. Crear Git temporal.
#   5. Auditar BEFORE -> AFTER.
#   6. Verificar que solamente cambien db/user/password.
#   7. Aplicar el archivo esperado.
#   8. Comparar byte a byte.
#   9. Si falla -> rollback automático.
#  10. Registrar histórico.
#
# Las contraseñas NO se escriben en los logs.
#
# ============================================================



# ============================================================
# === VALIDAR VARIABLES RECIBIDAS DESDE BASE_GENERAL ===
# ============================================================

if [ -z "$USER_DESTINO" ]; then

  echo "ERROR: USER_DESTINO no está definido.";
  echo "Este archivo debe ejecutarse desde BASE_GENERAL.sh.";

  return 1 2>/dev/null || exit 1;

fi;


if [ -z "$BASE_DESTINO" ]; then

  echo "ERROR: BASE_DESTINO no está definido.";

  return 1 2>/dev/null || exit 1;

fi;


if [ "${#DOMINIOS[@]}" -eq 0 ]; then

  echo "ERROR: DOMINIOS no está definido.";

  return 1 2>/dev/null || exit 1;

fi;


if [ "${#DBS[@]}" -eq 0 ]; then

  echo "ERROR: DBS no está definido.";

  return 1 2>/dev/null || exit 1;

fi;



# ============================================================
# === VARIABLES TEMPORALES ===
# ============================================================

DB_TMP_BASE="/tmp/database-migration-check-$USER_DESTINO";

DB_RUN_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')";


mkdir -p "$DB_TMP_BASE";



# ============================================================
# === PHP AUXILIAR ===
# ============================================================
#
# Este pequeño programa realiza la modificación exacta.
#
# No se utiliza sed para sustituir todo el archivo porque
# queremos conservar literalmente el resto de database.php.
#
# Para cada campo:
#
#   db
#   user
#   password
#
# se encuentra la ÚLTIMA asignación y solamente se cambia
# su valor.
#
# ============================================================

DB_PHP_HELPER="$DB_TMP_BASE/update_database.php";


cat > "$DB_PHP_HELPER" <<'PHP'
<?php

/*
 * ============================================================
 * ACTUALIZACIÓN CONTROLADA DEL ARCHIVO DE CONFIGURACIÓN
 * ============================================================
 *
 * Argumentos:
 *
 *   1. archivo origen
 *   2. archivo destino
 *   3. db nueva
 *   4. user nuevo
 *   5. password nueva
 *   6. formato
 *
 *
 * Cada formato define, para los tres campos, una expresión
 * con tres grupos:
 *
 *   1 = prefijo   2 = valor actual   3 = sufijo
 *
 * Solamente se sustituye el grupo 2 de la ÚLTIMA aparición.
 *
 * Así se conserva literalmente todo lo demás del archivo:
 * comillas, espaciado, comentarios y orden.
 *
 * ============================================================
 */

if ($argc !== 7) {

    fwrite(
        STDERR,
        "Uso: update_database.php SOURCE DESTINATION DB USER PASSWORD FORMATO\n"
    );

    exit(1);
}


$source = $argv[1];
$destination = $argv[2];

$newDb = $argv[3];
$newUser = $argv[4];
$newPassword = $argv[5];

$format = $argv[6];


/*
 * ------------------------------------------------------------
 * FORMATOS SOPORTADOS
 * ------------------------------------------------------------
 *
 * Para añadir uno nuevo basta con agregar una entrada aquí.
 * No hay que tocar nada más del procedimiento.
 *
 * ------------------------------------------------------------
 */

$formats = [];


/*
 * PiecesPHP / CodeIgniter
 *
 *   $config['database']['default']['db'] = 'valor';
 */

$piecesField = function (string $field): string {

    return
        '~(\$config\s*\[\s*[\'"]database[\'"]\s*\]'
        . '\s*\[\s*[\'"]default[\'"]\s*\]'
        . '\s*\[\s*[\'"]' . preg_quote($field, '~') . '[\'"]\s*\]'
        . '\s*=\s*[\'"])(.*?)([\'"]\s*;)~';
};

$formats['piecesphp'] = [
    'db'       => $piecesField('db'),
    'user'     => $piecesField('user'),
    'password' => $piecesField('password'),
];


/*
 * WordPress
 *
 *   define( 'DB_NAME', 'valor' );
 *
 * DB_HOST y table_prefix no se tocan.
 */

$wpField = function (string $constant): string {

    return
        '~(define\s*\(\s*[\'"]' . preg_quote($constant, '~') . '[\'"]'
        . '\s*,\s*[\'"])(.*?)([\'"]\s*\)\s*;)~';
};

$formats['wordpress'] = [
    'db'       => $wpField('DB_NAME'),
    'user'     => $wpField('DB_USER'),
    'password' => $wpField('DB_PASSWORD'),
];


/*
 * Joomla
 *
 *   public $db = 'valor';
 *
 * En configuration.php, dentro de class JConfig.
 */

$joomlaField = function (string $property): string {

    return
        '~((?:public|var)\s+\$' . preg_quote($property, '~')
        . '\s*=\s*[\'"])(.*?)([\'"]\s*;)~';
};

$formats['joomla'] = [
    'db'       => $joomlaField('db'),
    'user'     => $joomlaField('user'),
    'password' => $joomlaField('password'),
];


/*
 * PrestaShop 1.7 y Symfony
 *
 *   'database_name' => 'valor',
 */

$prestaField = function (string $key): string {

    return
        '~([\'"]' . preg_quote($key, '~') . '[\'"]\s*=>\s*[\'"])'
        . '(.*?)([\'"])~';
};

$formats['prestashop'] = [
    'db'       => $prestaField('database_name'),
    'user'     => $prestaField('database_user'),
    'password' => $prestaField('database_password'),
];


/*
 * PrestaShop 1.6
 *
 *   define('_DB_NAME_', 'valor');
 */

$formats['prestashop16'] = [
    'db'       => $wpField('_DB_NAME_'),
    'user'     => $wpField('_DB_USER_'),
    'password' => $wpField('_DB_PASSWD_'),
];


/*
 * Drupal 8, 9 y 10
 *
 *   'database' => 'valor',
 *
 * dentro de $databases['default']['default'].
 */

$formats['drupal'] = [
    'db'       => $prestaField('database'),
    'user'     => $prestaField('username'),
    'password' => $prestaField('password'),
];


/*
 * Laravel y cualquier archivo .env
 *
 *   DB_DATABASE=valor
 *
 * No es PHP: el valor llega hasta el fin de la línea y puede
 * ir con o sin comillas.
 */

$envField = function (string $key): string {

    return
        '~(^[ \t]*' . preg_quote($key, '~') . '[ \t]*=[ \t]*"?)'
        . '([^"\r\n]*)'
        . '("?[ \t]*$)~m';
};

$formats['laravel'] = [
    'db'       => $envField('DB_DATABASE'),
    'user'     => $envField('DB_USERNAME'),
    'password' => $envField('DB_PASSWORD'),
];


if (!isset($formats[$format])) {

    fwrite(
        STDERR,
        "Formato desconocido: {$format}\n"
        . "Disponibles: " . implode(', ', array_keys($formats)) . "\n"
    );

    exit(1);
}


$patterns = $formats[$format];


if (!is_file($source)) {

    fwrite(
        STDERR,
        "No existe el archivo origen: {$source}\n"
    );

    exit(1);
}


$content = file_get_contents($source);


if ($content === false) {

    fwrite(
        STDERR,
        "No se pudo leer: {$source}\n"
    );

    exit(1);
}


/*
 * ------------------------------------------------------------
 * Reemplazar la última asignación de un campo.
 * ------------------------------------------------------------
 *
 * Se conserva:
 *
 *   prefijo + nuevo valor + sufijo
 *
 * de modo que solamente cambia el valor.
 * ------------------------------------------------------------
 */

/*
 * ------------------------------------------------------------
 * Escapar el valor según cómo esté citado en el archivo.
 * ------------------------------------------------------------
 *
 * Sin esto, una contraseña con apóstrofo rompe el archivo, y
 * la comprobación byte a byte NO lo detecta: compara el
 * esperado contra el real, y ambos quedarían rotos igual.
 *
 * La comilla de apertura es el último carácter del prefijo.
 * ------------------------------------------------------------
 */

function escapeValue(string $prefix, string $value): string
{
    $quote = substr($prefix, -1);


    /*
     * Comillas simples de PHP: solo \ y '
     */

    if ($quote === "'") {

        $value = str_replace('\\', '\\\\', $value);

        return str_replace("'", "\\'", $value);
    }


    /*
     * Comillas dobles: además $, que interpolaría tanto en
     * PHP como en un archivo .env.
     */

    if ($quote === '"') {

        $value = str_replace('\\', '\\\\', $value);
        $value = str_replace('"', '\\"', $value);

        return str_replace('$', '\\$', $value);
    }


    /*
     * Sin comillas: es un .env.
     *
     * Si el valor tiene algo que rompería la línea, se cita.
     */

    if (preg_match('~[^A-Za-z0-9_.:/@-]~', $value)) {

        $value = str_replace('\\', '\\\\', $value);
        $value = str_replace('"', '\\"', $value);

        return '"' . $value . '"';
    }


    return $value;
}


function replaceLastAssignment(
    string $content,
    string $pattern,
    string $field,
    string $newValue,
    int &$count
): string {

    preg_match_all(
        $pattern,
        $content,
        $matches,
        PREG_OFFSET_CAPTURE
    );


    $count = count($matches[0]);


    if ($count === 0) {

        throw new RuntimeException(
            "No se encontró ninguna asignación para '{$field}'."
        );

    }


    /*
     * Última aparición.
     */

    $index = $count - 1;


    $fullMatch = $matches[0][$index][0];

    $offset = $matches[0][$index][1];

    $prefix = $matches[1][$index][0];

    $suffix = $matches[3][$index][0];


    $replacement =
        $prefix
        . escapeValue($prefix, $newValue)
        . $suffix;


    return substr_replace(
        $content,
        $replacement,
        $offset,
        strlen($fullMatch)
    );
}


try {

    /*
     * DB
     */

    $dbCount = 0;

    $content = replaceLastAssignment(
        $content,
        $patterns['db'],
        'db',
        $newDb,
        $dbCount
    );


    /*
     * USER
     */

    $userCount = 0;

    $content = replaceLastAssignment(
        $content,
        $patterns['user'],
        'user',
        $newUser,
        $userCount
    );


    /*
     * PASSWORD
     */

    $passwordCount = 0;

    $content = replaceLastAssignment(
        $content,
        $patterns['password'],
        'password',
        $newPassword,
        $passwordCount
    );


    /*
     * Guardar archivo esperado.
     */

    if (
        file_put_contents(
            $destination,
            $content
        ) === false
    ) {

        throw new RuntimeException(
            "No se pudo escribir el archivo esperado."
        );

    }


    /*
     * Solamente mostramos información NO sensible.
     */

    echo "FORMAT={$format}\n";
    echo "DB_ASSIGNMENTS={$dbCount}\n";
    echo "USER_ASSIGNMENTS={$userCount}\n";
    echo "PASSWORD_ASSIGNMENTS={$passwordCount}\n";


} catch (Throwable $e) {

    fwrite(
        STDERR,
        "ERROR: " . $e->getMessage() . "\n"
    );

    exit(1);
}
PHP


chmod 700 "$DB_PHP_HELPER";



# ============================================================
# === PROCESAR CADA BASE DE DATOS ===
# ============================================================

for entry in "${DBS[@]}"
do

  # ----------------------------------------------------------
  # Leer:
  #
  #   dominio | bd_origen | bd_destino | user | password
  #
  # bd_origen no se usa aquí: solo interesa a
  # BASE_MIGRAR_DB.sh, que es quien lee del servidor
  # anterior. Se lee para descartarlo.
  # ----------------------------------------------------------

  IFS='|' read -r site origen_db new_db new_user new_password <<< "$entry";


  # ----------------------------------------------------------
  # Las bases sueltas no tienen aplicación asociada, así que
  # no hay ninguna configuración que reescribir.
  # ----------------------------------------------------------

  case "$site" in
    @*) continue;;
  esac;




  echo;
  echo "============================================================";
  echo "CONFIGURANDO DATABASE.PHP: $site";
  echo "============================================================";


  # ----------------------------------------------------------
  # Rutas
  # ----------------------------------------------------------

  SITE_BASE="$BASE_DESTINO/$site";

  # ----------------------------------------------------------
  # La ruta de database.php es configurable por dominio con la
  # clave ruta_db. Si no se declaró, cfg devuelve el valor de
  # fábrica: public_html/app/config/database.php
  # ----------------------------------------------------------

  # ----------------------------------------------------------
  # El tipo de aplicación decide qué patrón se reescribe y,
  # si no se declaró ruta_db, dónde se busca el archivo.
  # ----------------------------------------------------------

  # ----------------------------------------------------------
  # Si la base de este dominio no llegó a migrarse, NO se
  # toca su configuración.
  #
  # Reescribirla apuntaría la aplicación a una base que no
  # existe, que es peor que dejarla como estaba: el sitio
  # viejo sigue funcionando hasta que se resuelva.
  # ----------------------------------------------------------

  DB_FALLO="false";

  for fallida in ${DB_MIGRACION_FALLIDAS[@]+"${DB_MIGRACION_FALLIDAS[@]}"}
  do
    if [ "$fallida" = "$site" ]; then
      DB_FALLO="true";
    fi;
  done;


  if [ "$DB_FALLO" = "true" ]; then

    echo "OMITIDO: la migración de su base de datos falló.";
    echo "La configuración se deja intacta a propósito:";
    echo "apuntarla a una base inexistente sería peor.";

    continue;

  fi;


  TIPO_APP="$(cfg "$site" tipo)";

  if [ -z "$TIPO_APP" ]; then
    TIPO_APP="piecesphp";
  fi;


  if [ "$TIPO_APP" = "ninguno" ]; then

    echo "Sin archivo de configuración que reescribir.";
    echo "Las credenciales nuevas deben aplicarse a mano.";

    continue;

  fi;


  RUTA_DB="$(cfg "$site" ruta_db)";

  if [ -z "$RUTA_DB" ]; then
    RUTA_DB="public_html/app/config/database.php";
  fi;

  FILE="$SITE_BASE/$RUTA_DB";

  # ----------------------------------------------------------
  # Backup y log van a la carpeta de la corrida, junto a los
  # dumps y a los logs de las demás bases.
  # ----------------------------------------------------------

  PRIVATE="$DIR_CORRIDA";

  TIMESTAMP="$(date '+%Y%m%d_%H%M%S')";

  BACKUP="$PRIVATE/${site}_database.php.bk";

  EXPECTED="$DB_TMP_BASE/${site}.expected.php";

  GIT_DIR="$DB_TMP_BASE/git_$site";

  LOG="$PRIVATE/${site}_config.log";



  # ==========================================================
  # === PREPARAR PRIVATE ===
  # ==========================================================

  mkdir -p "$PRIVATE";


  touch "$LOG";

  chmod 600 "$LOG";


  {
    echo "============================================================";
    echo "HISTORIAL DE ACTUALIZACIÓN database.php";
    echo "============================================================";
    echo;
    echo "Fecha       : $(date '+%Y-%m-%d %H:%M:%S')";
    echo "Dominio     : $site";
    echo "Usuario     : $USER_DESTINO";
    echo "Archivo     : $FILE";
    echo "Backup      : $BACKUP";
    echo "Base nueva  : $new_db";
    echo "Usuario DB  : $new_user";
    echo "Password    : [NO SE REGISTRA]";
    echo;
  } >> "$LOG";



  # ==========================================================
  # === VERIFICAR database.php ===
  # ==========================================================

  if [ ! -f "$FILE" ]; then

    echo "ERROR: No existe database.php.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: No existe database.php.";
      echo;
    } >> "$LOG";

    continue;

  fi;



  # ==========================================================
  # === CREAR BACKUP ===
  # ==========================================================

  if ! cp -a "$FILE" "$BACKUP"; then

    echo "ERROR: No se pudo crear el backup.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: No se pudo crear el backup.";
      echo;
    } >> "$LOG";

    continue;

  fi;


  chmod 600 "$BACKUP";


  echo "Backup creado: $BACKUP";


  {
    echo "Backup creado correctamente.";
    echo;
  } >> "$LOG";



  # ==========================================================
  # === GENERAR ARCHIVO ESPERADO ===
  # ==========================================================
  #
  # IMPORTANTE:
  #
  # En este punto database.php REAL todavía no ha sido
  # modificado.
  #
  # Se genera primero una copia EXPECTED.
  #
  # ==========================================================

  rm -f "$EXPECTED";


  PHP_RESULT="$DB_TMP_BASE/${site}.php_result";

  PHP_ERROR="$DB_TMP_BASE/${site}.php_error";


  if ! php \
      "$DB_PHP_HELPER" \
      "$BACKUP" \
      "$EXPECTED" \
      "$new_db" \
      "$new_user" \
      "$new_password" \
      "$TIPO_APP" \
      > "$PHP_RESULT" \
      2> "$PHP_ERROR"
  then

    echo "ERROR: No se pudo generar el archivo esperado.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: Falló la generación del archivo esperado.";
      echo;
      echo "Error PHP:";
      cat "$PHP_ERROR";
      echo;
      echo "database.php original NO fue modificado.";
    } >> "$LOG";

    continue;

  fi;



  # ==========================================================
  # === REGISTRAR CANTIDAD DE ASIGNACIONES ===
  # ==========================================================

  DB_COUNT="$(
    grep '^DB_ASSIGNMENTS=' "$PHP_RESULT" |
    cut -d= -f2
  )";


  USER_COUNT="$(
    grep '^USER_ASSIGNMENTS=' "$PHP_RESULT" |
    cut -d= -f2
  )";


  PASSWORD_COUNT="$(
    grep '^PASSWORD_ASSIGNMENTS=' "$PHP_RESULT" |
    cut -d= -f2
  )";


  {
    echo "Asignaciones encontradas:";
    echo "  db       : $DB_COUNT";
    echo "  user     : $USER_COUNT";
    echo "  password : $PASSWORD_COUNT";
    echo;
  } >> "$LOG";


  echo "Asignaciones: db=$DB_COUNT user=$USER_COUNT password=$PASSWORD_COUNT";



  # ==========================================================
  # === VALIDAR ESTRUCTURA ENCONTRADA ===
  # ==========================================================

  if [ "$DB_COUNT" -lt 1 ] || \
     [ "$USER_COUNT" -lt 1 ] || \
     [ "$PASSWORD_COUNT" -lt 1 ]; then

    echo "ERROR: No se encontraron todas las asignaciones.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: No se encontraron db, user y password.";
      echo "database.php original NO fue modificado.";
      echo;
    } >> "$LOG";

    continue;

  fi;



  # ==========================================================
  # === GIT VOLÁTIL ===
  # ==========================================================
  #
  # Git sirve como evidencia de la transformación esperada.
  #
  # BEFORE:
  #
  #   backup
  #
  # AFTER:
  #
  #   expected
  #
  # El repositorio se elimina al finalizar.
  #
  # ==========================================================

  rm -rf "$GIT_DIR";

  mkdir -p "$GIT_DIR";


  git -C "$GIT_DIR" init -q;


  git -C "$GIT_DIR" config \
    user.name \
    "database-migration";


  git -C "$GIT_DIR" config \
    user.email \
    "database-migration@localhost";



  # ----------------------------------------------------------
  # BEFORE
  # ----------------------------------------------------------

  cp -a "$BACKUP" "$GIT_DIR/database.php";


  git -C "$GIT_DIR" add database.php;


  if ! git -C "$GIT_DIR" commit \
      -q \
      -m "BEFORE: $site"
  then

    echo "ERROR: Git no pudo crear BEFORE.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: Git no pudo crear el commit BEFORE.";
      echo "database.php original NO fue modificado.";
      echo;
    } >> "$LOG";

    rm -rf "$GIT_DIR";

    continue;

  fi;



  # ----------------------------------------------------------
  # AFTER esperado
  # ----------------------------------------------------------

  cp -a "$EXPECTED" "$GIT_DIR/database.php";


  git -C "$GIT_DIR" add database.php;


  if ! git -C "$GIT_DIR" commit \
      -q \
      -m "AFTER: $site"
  then

    echo "ERROR: Git no pudo crear AFTER.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: Git no pudo crear el commit AFTER.";
      echo "database.php original NO fue modificado.";
      echo;
    } >> "$LOG";

    rm -rf "$GIT_DIR";

    continue;

  fi;



  # ==========================================================
  # === OBTENER DIFF ===
  # ==========================================================

  GIT_DIFF="$DB_TMP_BASE/${site}.diff";


  git -C "$GIT_DIR" diff \
    --no-ext-diff \
    --unified=3 \
    HEAD~1 HEAD \
    -- database.php \
    > "$GIT_DIFF";



  # ==========================================================
  # === REDACTAR PASSWORD DEL DIFF ===
  # ==========================================================
  #
  # El diff real contiene la contraseña vieja y nueva.
  #
  # Nunca se registra ese contenido.
  #
  # ==========================================================

  REDACTED_DIFF="$DB_TMP_BASE/${site}.redacted.diff";


  sed -E \
    "s/^([+-].*password.*)$/\1 [PASSWORD OCULTA]/I" \
    "$GIT_DIFF" \
    > "$REDACTED_DIFF";


  {
    echo "============================================================";
    echo "GIT DIFF - CAMBIO ESPERADO";
    echo "============================================================";
    echo;
    cat "$REDACTED_DIFF";
    echo;
  } >> "$LOG";



  # ==========================================================
  # === VALIDAR QUE NO EXISTAN CAMBIOS NO PERMITIDOS ===
  # ==========================================================
  #
  # Como el archivo EXPECTED fue generado exclusivamente
  # mediante el reemplazo de db/user/password, esta validación
  # sirve como segunda evidencia independiente.
  #
  # ==========================================================

  INVALID_DIFF="$DB_TMP_BASE/${site}.invalid.diff";


  # ----------------------------------------------------------
  # Qué líneas SÍ pueden haber cambiado, según la aplicación.
  #
  # El patrón depende del tipo: buscar el de PiecesPHP en un
  # wp-config.php marcaría como sospechoso un cambio legítimo.
  # ----------------------------------------------------------

  case "$TIPO_APP" in

    piecesphp)    PATRON_PERMITIDO='database.*default.*(db|user|password)';;
    wordpress)    PATRON_PERMITIDO='DB_NAME|DB_USER|DB_PASSWORD';;
    joomla)       PATRON_PERMITIDO='\$(db|user|password)[ \t]*=';;
    prestashop)   PATRON_PERMITIDO='database_(name|user|password)';;
    prestashop16) PATRON_PERMITIDO='_DB_(NAME|USER|PASSWD)_';;
    laravel)      PATRON_PERMITIDO='DB_(DATABASE|USERNAME|PASSWORD)';;
    drupal)       PATRON_PERMITIDO='(database|username|password)';;
    *)            PATRON_PERMITIDO='database.*default.*(db|user|password)';;

  esac;


  # ----------------------------------------------------------
  # El if va en una sola línea a propósito.
  #
  # mawk, que es el awk por defecto en Debian y Ubuntu, no
  # acepta un salto de línea justo después del paréntesis de
  # apertura. Con la condición repartida en varias líneas,
  # mawk aborta con un error de sintaxis, el archivo de
  # salida queda vacío y ESTA VALIDACIÓN PASA SIEMPRE sin
  # comprobar nada.
  # ----------------------------------------------------------

  awk -v permitido="$PATRON_PERMITIDO" '
    /^[-+][^-+]/ {
      line = $0;
      if (line ~ permitido) next;
      if (line ~ /^---/) next;
      if (line ~ /^\+\+\+/) next;
      print line;
    }
  ' "$GIT_DIFF" > "$INVALID_DIFF";


  if [ "$?" -ne 0 ]; then

    echo "ERROR: falló la validación del diff.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: awk no pudo analizar el diff.";
      echo;
      echo "database.php original NO fue modificado.";
    } >> "$LOG";

    rm -rf "$GIT_DIR";

    continue;

  fi;



  if [ -s "$INVALID_DIFF" ]; then

    echo "ERROR: Git detectó cambios no permitidos.";

    {
      echo "RESULTADO: ERROR";
      echo "Motivo: El diff contiene cambios fuera de db/user/password.";
      echo;
      echo "Cambios no permitidos:";
      cat "$INVALID_DIFF";
      echo;
      echo "database.php original NO fue modificado.";
    } >> "$LOG";

    rm -rf "$GIT_DIR";

    continue;

  fi;


  echo "Git: diff válido. Solamente db/user/password.";



  # ==========================================================
  # === APLICAR ARCHIVO ESPERADO ===
  # ==========================================================

  echo "Aplicando cambios...";


  if ! cp -a "$EXPECTED" "$FILE"; then

    echo "ERROR: No se pudo aplicar el archivo esperado.";
    echo "Iniciando rollback...";


    {
      echo "RESULTADO: ERROR";
      echo "Motivo: No se pudo aplicar el archivo esperado.";
      echo;
      echo "Iniciando rollback...";
    } >> "$LOG";


    cp -a "$BACKUP" "$FILE";


    if cmp -s "$FILE" "$BACKUP"; then

      echo "Rollback: CORRECTO.";

      echo "Rollback: CORRECTO." >> "$LOG";

    else

      echo "ALERTA CRÍTICA: Rollback incorrecto.";

      echo "Rollback: ERROR CRÍTICO." >> "$LOG";

    fi;


    rm -rf "$GIT_DIR";

    continue;

  fi;



  # ==========================================================
  # === VALIDACIÓN BYTE A BYTE ===
  # ==========================================================
  #
  # El archivo REAL debe ser idéntico al archivo EXPECTED.
  #
  # Si no lo es:
  #
  #   -> no asumimos nada
  #   -> restauramos backup
  #
  # ==========================================================

  if cmp -s "$FILE" "$EXPECTED"; then

    echo "VALIDACIÓN: OK.";
    echo "database.php coincide exactamente con lo esperado.";


    {
      echo "============================================================";
      echo "VALIDACIÓN FINAL";
      echo "============================================================";
      echo;
      echo "Resultado: OK";
      echo;
      echo "database.php real = database.php esperado";
      echo;
      echo "Campos permitidos:";
      echo "  - db";
      echo "  - user";
      echo "  - password";
      echo;
      echo "host y cualquier otro contenido permanecen sin cambios.";
      echo;
      echo "Backup conservado:";
      echo "$BACKUP";
      echo;
    } >> "$LOG";


    # --------------------------------------------------------
    # Comprobar si realmente hubo cambios.
    #
    # Que sean idénticos no es un error:
    # significa que los valores ya coincidían.
    # --------------------------------------------------------

    if cmp -s "$FILE" "$BACKUP"; then

      echo "INFO: No había cambios efectivos.";

      {
        echo "Observación:";
        echo "El archivo final es idéntico al backup.";
        echo "Las credenciales ya coincidían con las de destino.";
        echo;
      } >> "$LOG";

    else

      echo "Cambio aplicado correctamente.";

      {
        echo "Cambio aplicado correctamente.";
        echo;
      } >> "$LOG";

    fi;


    # --------------------------------------------------------
    # Conservar backup y log.
    # --------------------------------------------------------

    chmod 600 "$BACKUP";
    chmod 600 "$LOG";


  else

    # ========================================================
    # === ERROR CRÍTICO: ROLLBACK ===
    # ========================================================

    echo;
    echo "ERROR CRÍTICO: database.php no coincide con lo esperado.";
    echo "Iniciando rollback automático...";


    {
      echo "============================================================";
      echo "ERROR CRÍTICO";
      echo "============================================================";
      echo;
      echo "database.php real NO coincide byte a byte con EXPECTED.";
      echo;
      echo "Diff entre EXPECTED y REAL:";
      diff -u "$EXPECTED" "$FILE" |
        sed -E \
          "s/^([+-].*password.*)$/\1 [PASSWORD OCULTA]/I";
      echo;
      echo "Iniciando rollback automático.";
      echo;
    } >> "$LOG";


    if cp -a "$BACKUP" "$FILE"; then

      if cmp -s "$FILE" "$BACKUP"; then

        echo "Rollback: CORRECTO.";

        {
          echo "Rollback: CORRECTO.";
          echo "database.php fue restaurado exactamente desde el backup.";
          echo;
          echo "RESULTADO FINAL: ERROR CONTROLADO - RESTAURADO";
        } >> "$LOG";

      else

        echo "ALERTA CRÍTICA: rollback no coincide con backup.";

        {
          echo "Rollback: ERROR CRÍTICO.";
          echo "El archivo restaurado NO coincide con el backup.";
          echo;
          echo "RESULTADO FINAL: ERROR CRÍTICO";
        } >> "$LOG";

      fi;

    else

      echo "ALERTA CRÍTICA: No se pudo restaurar el backup.";

      {
        echo "Rollback: FALLÓ.";
        echo;
        echo "RESULTADO FINAL: ERROR CRÍTICO";
      } >> "$LOG";

    fi;

  fi;



  # ==========================================================
  # === LIMPIEZA TEMPORAL ===
  # ==========================================================

  rm -rf "$GIT_DIR";

  rm -f "$EXPECTED";
  rm -f "$GIT_DIFF";
  rm -f "$REDACTED_DIFF";
  rm -f "$INVALID_DIFF";
  rm -f "$PHP_RESULT";
  rm -f "$PHP_ERROR";


  echo;
  echo "Historial: $LOG";
  echo "FIN: $site";

done;



# ============================================================
# === LIMPIEZA GLOBAL ===
# ============================================================

rm -f "$DB_PHP_HELPER";


# No eliminamos inmediatamente el directorio temporal si
# contiene algo inesperado; primero eliminamos únicamente
# nuestros archivos conocidos.

find "$DB_TMP_BASE" \
  -mindepth 1 \
  -maxdepth 1 \
  -type f \
  -delete;


# Los repositorios Git temporales que hayan quedado por algún
# error también se eliminan al terminar.

find "$DB_TMP_BASE" \
  -mindepth 1 \
  -maxdepth 1 \
  -type d \
  -name 'git_*' \
  -exec rm -rf {} +;


echo;
echo "============================================================";
echo "CONFIGURACIÓN DE database.php FINALIZADA";
echo "============================================================";
echo;
