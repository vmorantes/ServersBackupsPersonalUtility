#!/usr/bin/env bash
# =============================================================================
# tests/probar_migracion_codeigniter3.sh — el tipo codeigniter3 de la
# migración caliente
# =============================================================================
# Prueba los DOS helpers PHP de tools/migracion-caliente/ —el que lee las
# credenciales de una aplicación y el que las reescribe— contra archivos
# database.php sintéticos en $BANCO_TMP. Nada de esto toca un servidor, una
# base de datos ni un proyecto real: los helpers se extraen de su heredoc y se
# ejecutan con php sobre archivos inventados.
#
# Los helpers se localizan por la LÍNEA DE APERTURA de su heredoc, nunca por
# número de línea: cualquier añadido a esos archivos desplaza los números y
# dejaría esta suite extrayendo basura (o nada) sin que se notara.
#
# El helper de escritura NO modifica el archivo que lee: escribe un archivo
# "esperado" aparte. Así, cada vez que aquí se comprueba que «el original
# queda intacto», se está comprobando lo que de verdad protege al database.php
# de un servidor: que el archivo esperado no llegue a existir.
# =============================================================================
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_migracion_codeigniter3.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_migracion_codeigniter3 =="

MIG="$BANCO_RAIZ/tools/migracion-caliente"

# Commit anterior a este tipo: de ahí sale el helper con el que se comparan
# los tipos existentes (prueba de no regresión).
BASE_SIN_CI3="76042f6"

# -----------------------------------------------------------------------------
# Extracción de los helpers
# -----------------------------------------------------------------------------
# Imprime el cuerpo del heredoc cuya línea de apertura es exactamente $2. El
# cierre es la línea que contiene solo "PHP".
extraer_helper() {
  local archivo="$1" apertura="$2" destino="$3"
  awk -v ap="$apertura" '
    $0 == ap { dentro = 1; next }
    dentro && $0 == "PHP" { exit }
    dentro { print }
  ' "$archivo" > "$destino"
}

APERTURA_ESCRIBIR='cat > "$DB_PHP_HELPER" <<'"'"'PHP'"'"''
APERTURA_LEER='cat > "$LEER_PHP" <<'"'"'PHP'"'"''

ESCRIBIR="$BANCO_TMP/update_database.php"
LEER="$BANCO_TMP/leer_config.php"

extraer_helper "$MIG/BASE_CONFIGURAR_DB.sh" "$APERTURA_ESCRIBIR" "$ESCRIBIR"
extraer_helper "$MIG/BASE_LEER_CONFIG.sh"   "$APERTURA_LEER"     "$LEER"

# -----------------------------------------------------------------------------
# Datos sintéticos
# -----------------------------------------------------------------------------
# Todo inventado: ninguna base, usuario, dominio ni clave de aquí existe.
DB_NUEVA="ejemplo_db"
USER_NUEVO="ejemplo_user"
CLAVE_NUEVA="clave-de-prueba"

# El database.php típico de un CodeIgniter 3.1.7, con tabuladores, el
# defined('BASEPATH') de arriba y las claves que la herramienta no toca.
caso_array() {
  cat > "$1" <<'FIN'
<?php
defined('BASEPATH') OR exit('No direct script access allowed');

$active_group = 'default';
$query_builder = TRUE;

$db['default'] = array(
	'dsn'	=> '',
	'hostname' => 'localhost',
	'username' => 'viejo_user',
	'password' => 'clave-vieja',
	'database' => 'viejo_db',
	'dbdriver' => 'mysqli',
	'dbprefix' => '',
	'pconnect' => FALSE,
	'db_debug' => (ENVIRONMENT !== 'production'),
	'char_set' => 'utf8',
	'dbcollat' => 'utf8_general_ci',
);
FIN
}

caso_clave() {
  cat > "$1" <<'FIN'
<?php
$active_group = 'default';
$db['default']['hostname'] = 'localhost';
$db['default']['username'] = 'viejo_user';
$db['default']['password'] = 'clave-vieja';
$db['default']['database'] = 'viejo_db';
$db['default']['dbdriver'] = 'mysqli';
FIN
}

caso_otro_grupo() {
  cat > "$1" <<'FIN'
<?php
$active_group = 'default';

$db['default'] = array(
	'hostname' => 'localhost',
	'username' => 'viejo_user',
	'password' => 'clave-vieja',
	'database' => 'viejo_db',
	'dbdriver' => 'mysqli',
);

$db['otro'] = array(
	'hostname' => 'otro-host',
	'username' => 'intocable_user',
	'password' => 'intocable-clave',
	'database' => 'intocable_db',
	'dbdriver' => 'mysqli',
);
FIN
}

caso_active_group_ajeno() {
  cat > "$1" <<'FIN'
<?php
$active_group = 'produccion';
$db['default']['hostname'] = 'localhost';
$db['default']['username'] = 'viejo_user';
$db['default']['password'] = 'clave-vieja';
$db['default']['database'] = 'viejo_db';
FIN
}

caso_sin_active_group() {
  cat > "$1" <<'FIN'
<?php
$db['default']['hostname'] = 'localhost';
$db['default']['username'] = 'viejo_user';
$db['default']['password'] = 'clave-vieja';
$db['default']['database'] = 'viejo_db';
FIN
}

caso_sin_password() {
  cat > "$1" <<'FIN'
<?php
$active_group = 'default';
$db['default'] = array(
	'hostname' => 'localhost',
	'username' => 'viejo_user',
	'database' => 'viejo_db',
	'dbdriver' => 'mysqli',
);
FIN
}

# Comillas dobles y espaciado irregular alrededor de los corchetes, del = y
# del punto y coma.
caso_comillas_dobles() {
  cat > "$1" <<'FIN'
<?php
$db [ "default" ] [ "hostname" ] = "localhost";
$db [ "default" ] [ "database" ]   =   "viejo_db" ;
$db [ "default" ] [ "username" ]=  "viejo_user";
$db [ "default" ] [ "password" ] =    "clave-vieja";
FIN
}

# La misma clave dos veces DENTRO del grupo default. En PHP gana la última:
# la que la aplicación usa de verdad es 'segunda_db'.
caso_duplicada() {
  cat > "$1" <<'FIN'
<?php
$active_group = 'default';
$db['default'] = array(
	'database' => 'primera_db',
	'username' => 'viejo_user',
	'password' => 'clave-vieja',
	'database' => 'segunda_db',
);
FIN
}

caso_wordpress() {
  cat > "$1" <<'FIN'
<?php
define( 'DB_NAME', 'viejo_db' );
define( 'DB_USER', 'viejo_user' );
define( 'DB_PASSWORD', 'clave-vieja' );
define( 'DB_HOST', 'localhost' );
$table_prefix = 'wp_';
FIN
}

caso_joomla() {
  cat > "$1" <<'FIN'
<?php
class JConfig {
	public $host = 'localhost';
	public $user = 'viejo_user';
	public $password = 'clave-vieja';
	public $db = 'viejo_db';
	public $dbprefix = 'jos_';
}
FIN
}

# -----------------------------------------------------------------------------
# Utilidades
# -----------------------------------------------------------------------------
# Cuántas líneas cambiaron entre dos archivos (lado izquierdo del diff).
lineas_cambiadas() {
  diff "$1" "$2" 2>/dev/null | grep -c '^<' || true
}

# "si" / "no": si existe la ruta. Para afirmar_igual, que compara cadenas.
existe_si_no() {
  if [[ -e "$1" ]]; then echo "si"; else echo "no"; fi
}

# Aplica a un archivo las tres sustituciones que el helper debería hacer, y
# nada más. Lo que salga de aquí es el archivo esperado byte a byte: si el
# helper cambia una coma de más, afirmar_intacto lo ve.
esperado_tres_valores() {
  local origen="$1" destino="$2"
  sed -e "s/viejo_db/$DB_NUEVA/" \
      -e "s/viejo_user/$USER_NUEVO/" \
      -e "s/clave-vieja/$CLAVE_NUEVA/" \
      "$origen" > "$destino"
}

# -----------------------------------------------------------------------------
# ESCRITURA
# -----------------------------------------------------------------------------

# C1 y C2. Forma de array: cambia los tres valores y NADA más. El archivo
# esperado se reconstruye con sed y se compara byte a byte, que es la única
# forma de afirmar que no se movió un tabulador ni un comentario.
test_write_array_form_changes_only_the_three_values() {
  nueva_prueba ci3_c1
  local d="$BANCO_TMP/ci3_c1"

  caso_array "$d/database.php"
  esperado_tres_valores "$d/database.php" "$d/esperado.php"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "C1: forma array, el helper termina bien"

  afirmar_existe "$d/salida.php" "C1: se escribió el archivo esperado"
  afirmar_contiene "$d/stdout.txt" "^FORMAT=codeigniter3$" \
    "C1: el helper declara el formato codeigniter3"
  afirmar_contiene "$d/stdout.txt" "^DB_ASSIGNMENTS=1$" \
    "C1: una sola asignación de la base"
  afirmar_contiene "$d/stdout.txt" "^USER_ASSIGNMENTS=1$" \
    "C1: una sola asignación del usuario"
  afirmar_contiene "$d/stdout.txt" "^PASSWORD_ASSIGNMENTS=1$" \
    "C1: una sola asignación de la contraseña"

  afirmar_intacto "$d/salida.php" "$d/esperado.php" \
    "C2: forma array, el resto del archivo queda byte a byte igual"
  afirmar_igual "$(lineas_cambiadas "$d/database.php" "$d/salida.php")" "3" \
    "C2: cambian exactamente tres líneas"
  afirmar_contiene "$d/salida.php" "'dbdriver' => 'mysqli'" \
    "C2: dbdriver sigue intacto"
  afirmar_contiene "$d/salida.php" "defined\('BASEPATH'\)" \
    "C2: la primera línea de CodeIgniter sigue intacta"
}

# C3. Forma clave a clave.
test_write_key_by_key_form() {
  nueva_prueba ci3_c3
  local d="$BANCO_TMP/ci3_c3"

  caso_clave "$d/database.php"
  esperado_tres_valores "$d/database.php" "$d/esperado.php"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "C3: forma clave a clave, el helper termina bien"

  afirmar_intacto "$d/salida.php" "$d/esperado.php" \
    "C3: forma clave a clave, el resto queda byte a byte igual"
  afirmar_contiene "$d/salida.php" "\\\$db\['default'\]\['database'\] = '$DB_NUEVA';" \
    "C3: la base nueva quedó escrita"
  afirmar_contiene "$d/salida.php" "\\\$db\['default'\]\['hostname'\] = 'localhost';" \
    "C3: hostname no se toca"
}

# C4. Con un segundo grupo en el mismo archivo, solo se reescribe default.
# Es lo que impide migrar media aplicación: $db['otro'] puede ser la base de
# un cron o de una réplica.
test_write_leaves_other_group_untouched() {
  nueva_prueba ci3_c4
  local d="$BANCO_TMP/ci3_c4"

  caso_otro_grupo "$d/database.php"
  esperado_tres_valores "$d/database.php" "$d/esperado.php"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "C4: con otro grupo presente, el helper termina bien"

  afirmar_intacto "$d/salida.php" "$d/esperado.php" \
    "C4: solo cambian los tres valores del grupo default"
  afirmar_contiene "$d/salida.php" "'username' => 'intocable_user'" \
    "C4: el usuario del otro grupo sigue intacto"
  afirmar_contiene "$d/salida.php" "'password' => 'intocable-clave'" \
    "C4: la contraseña del otro grupo sigue intacta"
  afirmar_contiene "$d/salida.php" "'database' => 'intocable_db'" \
    "C4: la base del otro grupo sigue intacta"
  afirmar_igual "$(lineas_cambiadas "$d/database.php" "$d/salida.php")" "3" \
    "C4: cambian exactamente tres líneas, no seis"
}

# C5. El camino de fallo que más importa: otro grupo activo. No se escribe
# NADA y el mensaje dice qué revisar.
test_write_refuses_when_active_group_is_not_default() {
  nueva_prueba ci3_c5
  local d="$BANCO_TMP/ci3_c5"

  caso_active_group_ajeno "$d/database.php"
  local antes
  antes="$(sha256sum < "$d/database.php")"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 1 "$?" "C5: con active_group ajeno, el helper falla"

  afirmar_contiene "$d/stderr.txt" \
    "active_group es 'produccion', no 'default': revisar a mano" \
    "C5: el mensaje dice cuál es el grupo activo y qué hacer"
  afirmar_igual "$(existe_si_no "$d/salida.php")" "no" \
    "C5: el archivo esperado NO se creó"
  afirmar_igual "$(sha256sum < "$d/database.php")" "$antes" \
    "C5: el database.php original queda idéntico"
}

# active_group ausente: CodeIgniter usa 'default', y la herramienta también.
test_write_treats_missing_active_group_as_default() {
  nueva_prueba ci3_sinag
  local d="$BANCO_TMP/ci3_sinag"

  caso_sin_active_group "$d/database.php"
  esperado_tres_valores "$d/database.php" "$d/esperado.php"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "sin active_group: se trata como default y reescribe"
  afirmar_intacto "$d/salida.php" "$d/esperado.php" \
    "sin active_group: cambian solo los tres valores"
}

# C6. Falta una clave: falla en voz alta, sin escribir. Es el camino que el
# ADR 0018 daba por supuesto para piecesphp y que aquí queda demostrado.
test_write_fails_loudly_when_a_key_is_missing() {
  nueva_prueba ci3_c6
  local d="$BANCO_TMP/ci3_c6"

  caso_sin_password "$d/database.php"
  local antes
  antes="$(sha256sum < "$d/database.php")"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 1 "$?" "C6: sin la clave password, el helper falla"

  afirmar_contiene "$d/stderr.txt" "No se encontró ninguna asignación para 'password'" \
    "C6: el mensaje nombra la clave que falta"
  afirmar_igual "$(existe_si_no "$d/salida.php")" "no" \
    "C6: el archivo esperado NO se creó"
  afirmar_igual "$(sha256sum < "$d/database.php")" "$antes" \
    "C6: el database.php original queda idéntico"
}

# C7. Comillas dobles y espaciado irregular.
test_write_handles_double_quotes_and_odd_spacing() {
  nueva_prueba ci3_c7
  local d="$BANCO_TMP/ci3_c7"

  caso_comillas_dobles "$d/database.php"
  esperado_tres_valores "$d/database.php" "$d/esperado.php"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "C7: comillas dobles y espacios raros, termina bien"

  afirmar_intacto "$d/salida.php" "$d/esperado.php" \
    "C7: se conserva el espaciado original, byte a byte"
  afirmar_contiene "$d/salida.php" '\]   =   "'"$DB_NUEVA"'" ;' \
    "C7: el espaciado alrededor del = y del ; sigue igual"
}

# C8. Una contraseña con los caracteres que la propia herramienta considera
# seguros sin citar (el preg_match de escapeValue): se escribe literal, sin
# escapar nada, dentro de las comillas simples del archivo.
test_write_writes_allowed_characters_verbatim() {
  nueva_prueba ci3_c8
  local d="$BANCO_TMP/ci3_c8"
  local clave='Cl4ve.de-prueba_x:9/@A'

  caso_clave "$d/database.php"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$clave" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "C8: clave con caracteres permitidos, termina bien"

  afirmar_contiene "$d/salida.php" "\['password'\] = '$clave';" \
    "C8: la clave se escribe literal, sin escapes"
  afirmar_no_contiene "$d/salida.php" '\\\\' \
    "C8: no se colaron barras invertidas"
}

# Regla 3.5, documentada porque el resultado NO es el que se espera a primera
# vista: el helper se queda con la ÚLTIMA aparición de cada campo, pero en la
# forma de array el patrón está anclado a "$db['default'] = array(", así que
# solo puede casar UNA vez por grupo y reescribe la PRIMERA clave duplicada.
# En PHP gana la última, que es la que la aplicación usa de verdad. Esta
# prueba fija ese comportamiento para que un cambio futuro no lo mueva en
# silencio; el riesgo está reportado aparte.
test_write_with_duplicate_key_rewrites_the_first_one() {
  nueva_prueba ci3_dup
  local d="$BANCO_TMP/ci3_dup"

  caso_duplicada "$d/database.php"

  php "$ESCRIBIR" "$d/database.php" "$d/salida.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" codeigniter3 \
      > "$d/stdout.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "3.5: con la clave duplicada, el helper termina bien"

  afirmar_contiene "$d/stdout.txt" "^DB_ASSIGNMENTS=1$" \
    "3.5: el patrón casa una sola vez dentro del grupo"
  afirmar_contiene "$d/salida.php" "'database' => '$DB_NUEVA'," \
    "3.5: se reescribe la PRIMERA aparición"
  afirmar_contiene "$d/salida.php" "'database' => 'segunda_db'," \
    "3.5: la SEGUNDA aparición, que es la que PHP usa, queda sin tocar"
}

# -----------------------------------------------------------------------------
# LECTURA
# -----------------------------------------------------------------------------

# L1. Forma de array: las tres líneas que el helper de lectura imprime.
test_read_array_form() {
  nueva_prueba ci3_l1
  local d="$BANCO_TMP/ci3_l1"

  caso_array "$d/database.php"

  php "$LEER" "$d/database.php" codeigniter3 > "$d/salida.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "L1: forma array, la lectura termina bien"

  afirmar_contiene "$d/salida.txt" "^DB=viejo_db$"      "L1: lee la base del origen"
  afirmar_contiene "$d/salida.txt" "^USER=viejo_user$"  "L1: lee el usuario del origen"
  afirmar_contiene "$d/salida.txt" "^HOST=localhost$"   "L1: lee el host del origen"
  afirmar_no_contiene "$d/salida.txt" "clave-vieja" \
    "L1: la contraseña no se lee ni se imprime"
}

# L2. Forma clave a clave.
test_read_key_by_key_form() {
  nueva_prueba ci3_l2
  local d="$BANCO_TMP/ci3_l2"

  caso_clave "$d/database.php"

  php "$LEER" "$d/database.php" codeigniter3 > "$d/salida.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "L2: forma clave a clave, la lectura termina bien"

  afirmar_contiene "$d/salida.txt" "^DB=viejo_db$"     "L2: lee la base"
  afirmar_contiene "$d/salida.txt" "^USER=viejo_user$" "L2: lee el usuario"
  afirmar_contiene "$d/salida.txt" "^HOST=localhost$"  "L2: lee el host"
}

# L3. Un segundo grupo no contamina la lectura: si se leyera el de otro
# grupo, la migración traería la base equivocada sin ningún error.
test_read_is_not_contaminated_by_another_group() {
  nueva_prueba ci3_l3
  local d="$BANCO_TMP/ci3_l3"

  caso_otro_grupo "$d/database.php"

  php "$LEER" "$d/database.php" codeigniter3 > "$d/salida.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "L3: con otro grupo presente, la lectura termina bien"

  afirmar_contiene "$d/salida.txt" "^DB=viejo_db$" \
    "L3: lee la base del grupo default, no la del otro"
  afirmar_no_contiene "$d/salida.txt" "intocable" \
    "L3: nada del otro grupo aparece en la salida"
}

# L4. Otro grupo activo: la lectura falla y no devuelve ni un valor.
test_read_refuses_when_active_group_is_not_default() {
  nueva_prueba ci3_l4
  local d="$BANCO_TMP/ci3_l4"

  caso_active_group_ajeno "$d/database.php"

  php "$LEER" "$d/database.php" codeigniter3 > "$d/salida.txt" 2> "$d/stderr.txt"
  afirmar_codigo 1 "$?" "L4: con active_group ajeno, la lectura falla"

  afirmar_contiene "$d/stderr.txt" \
    "active_group es 'produccion', no 'default': revisar a mano" \
    "L4: el mensaje es el mismo que en la escritura"
  afirmar_igual "$(wc -c < "$d/salida.txt" | tr -d ' ')" "0" \
    "L4: no se devuelve ningún valor"
}

# L5. active_group ausente: se lee default.
test_read_treats_missing_active_group_as_default() {
  nueva_prueba ci3_l5
  local d="$BANCO_TMP/ci3_l5"

  caso_sin_active_group "$d/database.php"

  php "$LEER" "$d/database.php" codeigniter3 > "$d/salida.txt" 2> "$d/stderr.txt"
  afirmar_codigo 0 "$?" "L5: sin active_group, la lectura termina bien"
  afirmar_contiene "$d/salida.txt" "^DB=viejo_db$" \
    "L5: sin active_group se lee el grupo default"
}

# -----------------------------------------------------------------------------
# NO REGRESIÓN (3.3)
# -----------------------------------------------------------------------------
# El gancho de guardas se añadió a código compartido por los siete tipos
# anteriores. Esto compara el helper de HOY con el de antes del cambio,
# extraído del commit $BASE_SIN_CI3, con la misma entrada: salida y archivo
# resultante tienen que ser idénticos. Si alguna vez dejan de serlo, el tipo
# nuevo habrá cambiado el comportamiento de los que el PO ya usó en
# producción.
comparar_con_helper_anterior() {
  local etiqueta="$1" tipo="$2" generar_caso="$3"
  local d="$BANCO_TMP/ci3_nr_$tipo"
  mkdir -p "$d"

  local anterior="$d/update_database_anterior.php"
  git -C "$BANCO_RAIZ" show \
    "$BASE_SIN_CI3:tools/migracion-caliente/BASE_CONFIGURAR_DB.sh" \
    > "$d/BASE_CONFIGURAR_DB.anterior.sh" 2>/dev/null

  afirmar_existe "$d/BASE_CONFIGURAR_DB.anterior.sh" \
    "$etiqueta: se recuperó el archivo de $BASE_SIN_CI3"

  extraer_helper "$d/BASE_CONFIGURAR_DB.anterior.sh" "$APERTURA_ESCRIBIR" "$anterior"

  # Si la extracción fallara, el archivo quedaría vacío y las comparaciones
  # de abajo pasarían en verde comparando nada con nada.
  afirmar_contiene "$anterior" "update_database.php SOURCE DESTINATION" \
    "$etiqueta: el helper anterior se extrajo de verdad"
  afirmar_no_contiene "$anterior" "codeigniter3" \
    "$etiqueta: el helper anterior no conocía codeigniter3"

  "$generar_caso" "$d/config.php"

  php "$anterior" "$d/config.php" "$d/salida_anterior.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" "$tipo" \
      > "$d/stdout_anterior.txt" 2> "$d/stderr_anterior.txt"
  local rc_anterior=$?

  php "$ESCRIBIR" "$d/config.php" "$d/salida_nueva.php" \
      "$DB_NUEVA" "$USER_NUEVO" "$CLAVE_NUEVA" "$tipo" \
      > "$d/stdout_nueva.txt" 2> "$d/stderr_nueva.txt"
  local rc_nueva=$?

  afirmar_codigo "$rc_anterior" "$rc_nueva" \
    "$etiqueta: mismo código de salida antes y después del gancho"
  afirmar_intacto "$d/stdout_nueva.txt" "$d/stdout_anterior.txt" \
    "$etiqueta: misma salida estándar"
  afirmar_intacto "$d/stderr_nueva.txt" "$d/stderr_anterior.txt" \
    "$etiqueta: misma salida de error"
  afirmar_intacto "$d/salida_nueva.php" "$d/salida_anterior.php" \
    "$etiqueta: el archivo resultante es byte a byte el mismo"
}

test_existing_types_are_unchanged() {
  nueva_prueba ci3_nr
  comparar_con_helper_anterior "3.3 wordpress" wordpress caso_wordpress
  comparar_con_helper_anterior "3.3 joomla"    joomla    caso_joomla
}

# -----------------------------------------------------------------------------
# PATRON_PERMITIDO (3.4)
# -----------------------------------------------------------------------------
# La validación del diff decide si un cambio en el database.php es legítimo.
# Con el patrón equivocado, un cambio CORRECTO se marca como sospechoso y la
# migración se detiene sin motivo. Aquí se extraen del archivo el programa awk
# REAL y el patrón REAL del tipo, para que la prueba no se quede probando una
# copia que se desincroniza.
test_patron_permitido_accepts_both_forms_and_rejects_a_foreign_line() {
  nueva_prueba ci3_awk
  local d="$BANCO_TMP/ci3_awk"

  # El programa awk: entre la línea que lo abre y la que lo cierra con el
  # nombre del archivo de diff.
  awk '
    index($0, "awk -v permitido=") > 0 { dentro = 1; next }
    dentro && index($0, "GIT_DIFF") > 0 { exit }
    dentro { print }
  ' "$MIG/BASE_CONFIGURAR_DB.sh" > "$d/validar.awk"

  afirmar_contiene "$d/validar.awk" 'permitido' \
    "3.4: se extrajo el programa awk real de la validación"

  # El patrón del tipo, de su propia rama del case.
  local patron
  patron="$(sed -n "s/^[[:space:]]*codeigniter3)[[:space:]]*PATRON_PERMITIDO='\(.*\)';;.*/\1/p" \
            "$MIG/BASE_CONFIGURAR_DB.sh")"

  afirmar_igual "$(test -n "$patron" && echo si || echo no)" "si" \
    "3.4: el case tiene una rama para codeigniter3 ($patron)"

  # Diff de la forma de array: la línea que cambia no lleva ningún $db.
  cat > "$d/diff_array.txt" <<'FIN'
--- a/database.php
+++ b/database.php
-	'username' => 'viejo_user',
-	'password' => 'clave-vieja',
-	'database' => 'viejo_db',
+	'username' => 'ejemplo_user',
+	'password' => 'clave-de-prueba',
+	'database' => 'ejemplo_db',
FIN

  cat > "$d/diff_clave.txt" <<'FIN'
--- a/database.php
+++ b/database.php
-$db['default']['database'] = 'viejo_db';
+$db['default']['database'] = 'ejemplo_db';
FIN

  # Una línea ajena: esto SÍ tiene que quedar marcado.
  cat > "$d/diff_ajeno.txt" <<'FIN'
--- a/database.php
+++ b/database.php
-	'dbdriver' => 'mysqli',
+	'dbdriver' => 'postgre',
FIN

  awk -v permitido="$patron" -f "$d/validar.awk" "$d/diff_array.txt" > "$d/sobra_array.txt"
  afirmar_igual "$(wc -c < "$d/sobra_array.txt" | tr -d ' ')" "0" \
    "3.4: el cambio en forma de array se ACEPTA"

  awk -v permitido="$patron" -f "$d/validar.awk" "$d/diff_clave.txt" > "$d/sobra_clave.txt"
  afirmar_igual "$(wc -c < "$d/sobra_clave.txt" | tr -d ' ')" "0" \
    "3.4: el cambio en forma clave a clave se ACEPTA"

  awk -v permitido="$patron" -f "$d/validar.awk" "$d/diff_ajeno.txt" > "$d/sobra_ajeno.txt"
  afirmar_contiene "$d/sobra_ajeno.txt" "dbdriver" \
    "3.4: un cambio en una línea ajena se RECHAZA"
}

# -----------------------------------------------------------------------------
# REGISTRO EN LOS CUATRO SITIOS
# -----------------------------------------------------------------------------
# Un tipo registrado a medias falla de forma asimétrica: leería bien y
# escribiría mal, o al revés, y solo se vería en el servidor.
test_type_is_registered_everywhere() {
  nueva_prueba ci3_reg

  afirmar_contiene "$MIG/BASE_CONFIG.sh" \
    'CFG_RUTA_POR_TIPO\[codeigniter3\]="public_html/application/config/database.php"' \
    "registro: BASE_CONFIG.sh tiene la ruta por defecto"
  afirmar_contiene "$MIG/BASE_LEER_CONFIG.sh" "'codeigniter3' =>" \
    "registro: BASE_LEER_CONFIG.sh tiene el formato de lectura"
  afirmar_contiene "$MIG/BASE_CONFIGURAR_DB.sh" "\\\$formats\['codeigniter3'\]" \
    "registro: BASE_CONFIGURAR_DB.sh tiene el formato de escritura"
  afirmar_contiene "$MIG/BASE_CONFIGURAR_DB.sh" "codeigniter3) PATRON_PERMITIDO=" \
    "registro: BASE_CONFIGURAR_DB.sh tiene su rama de validación del diff"
  afirmar_contiene "$MIG/crear.sh" "'codeigniter3'" \
    "registro: crear.sh lo ofrece en la lista de tipos"
  afirmar_contiene "$MIG/crear.sh" 'value="codeigniter3">CodeIgniter 3' \
    "registro: crear.sh lo ofrece en el selector con su etiqueta"
}

test_write_array_form_changes_only_the_three_values
test_write_key_by_key_form
test_write_leaves_other_group_untouched
test_write_refuses_when_active_group_is_not_default
test_write_treats_missing_active_group_as_default
test_write_fails_loudly_when_a_key_is_missing
test_write_handles_double_quotes_and_odd_spacing
test_write_writes_allowed_characters_verbatim
test_write_with_duplicate_key_rewrites_the_first_one
test_read_array_form
test_read_key_by_key_form
test_read_is_not_contaminated_by_another_group
test_read_refuses_when_active_group_is_not_default
test_read_treats_missing_active_group_as_default
test_existing_types_are_unchanged
test_patron_permitido_accepts_both_forms_and_rejects_a_foreign_line
test_type_is_registered_everywhere

fin_de_suite
