#!/usr/bin/env bash
# =============================================================================
# tests/probar_migracion_analizador.sh — el analizador de solo lectura
# =============================================================================
# El analizador se ejecutará por PRIMERA VEZ en el servidor de producción del
# PO: no hay servidor de pruebas. Lo único que puede dar confianza antes de eso
# es demostrar aquí sus tres reglas, en vez de afirmarlas:
#
#   1. NO ESCRIBE: se suma sha256 del árbol entero (contenido, rutas y modos)
#      antes y después. Tiene que ser idéntica.
#   2. NO LLAMA AL PANEL NI A LA RED: delante del PATH van órdenes falsas que
#      registran su invocación. El registro tiene que quedar VACÍO.
#   3. NO IMPRIME SECRETOS: el árbol falso lleva marcadores sembrados en cada
#      sitio donde hay un secreto de verdad. Ninguno puede aparecer ni en la
#      salida ni en los archivos generados.
#
# Todo el árbol es inventado: example.org, 203.0.113.10 (RFC 5737), cuentas
# "cuenta1" y "cuenta2", bases y claves que no existen en ninguna parte.
#
# Se prueba el PAQUETE, que es lo que el PO ejecutará, no analizar.sh suelto.
# =============================================================================
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_migracion_analizador.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_migracion_analizador =="

MIG="$BANCO_RAIZ/tools/migracion-caliente"

# Órdenes que el analizador NO debe invocar jamás. Cada una se sustituye por un
# falso que apunta su nombre en un registro.
PROHIBIDAS=(
  v-list-users v-list-user v-list-web-domains v-list-web-domain
  v-list-databases v-list-mail-domains v-list-mail-accounts v-list-dns-domains
  v-list-cron-jobs v-list-sys-config v-list-sys-php v-list-user-backups
  v-add-web-domain v-change-web-domain-backend-tpl v-update-user-disk
  mysql mysqldump ssh scp curl wget rclone restic doveadm
  systemctl service crontab sudo
)

# -----------------------------------------------------------------------------
# El árbol falso
# -----------------------------------------------------------------------------
# Un HestiaCP de mentira: data/users con dos cuentas, homes con sitios web de
# varios marcos, correo en Maildir, y los .conf con el formato CLAVE='valor'
# que describe .agents/context/50-hestiacp.md.
sembrar_arbol() {
  local raiz="$1"

  local H="$raiz/hestia"
  local HOMES="$raiz/home"
  local ETC="$raiz/etc"

  mkdir -p "$H/conf" "$H/data/users/cuenta1/mail" "$H/data/users/cuenta1/dns" \
           "$H/data/users/cuenta2/mail" "$H/data/ips" \
           "$ETC/php/8.1/fpm" "$ETC/php/7.4/fpm" "$ETC/php/8.3/cli" \
           "$raiz/spool" "$raiz/mysql" "$raiz/salida"

  # --- hestia.conf: la VERSION se lee; todo lo demás NO ---
  cat > "$H/conf/hestia.conf" <<'FIN'
VERSION='1.10.5'
WEB_SYSTEM='nginx'
SERVER_SMTP_PASSWD='SECRETO_NO_DEBE_SALIR_1'
PHPMYADMIN_KEY='SECRETO_NO_DEBE_SALIR_2'
FIN

  cat > "$ETC/os-release" <<'FIN'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
ID=debian
FIN

  # --- passwd: el '@' del GECOS es lo que hace que el panel reconozca la
  #     cuenta. cuenta3 existirá en data/users SIN estar aquí.
  cat > "$ETC/passwd" <<'FIN'
root:x:0:0:root:/root:/bin/bash
cuenta1:x:1001:1001:admin@example.org:/home/cuenta1:/bin/bash
cuenta2:x:1002:1002:admin@example.net:/home/cuenta2:/bin/bash
FIN

  # --- IPs ---
  cat > "$H/data/ips/203.0.113.10" <<'FIN'
OWNER='cuenta1'
STATUS='shared'
NAME='eth0'
NAT=''
FIN

  # =========================================================================
  # cuenta1
  # =========================================================================
  cat > "$H/data/users/cuenta1/user.conf" <<'FIN'
PACKAGE='default'
SHELL='bash'
SUSPENDED='no'
RKEY='SECRETO_NO_DEBE_SALIR_3'
TWOFA='SECRETO_NO_DEBE_SALIR_4'
U_DISK='4096'
FIN

  # web.conf: una línea por dominio, con todas sus claves.
  {
    printf "DOMAIN='example.org' IP='203.0.113.10' IP6='' CUSTOM_DOCROOT='' ALIAS='www.example.org' TPL='default' SSL='yes' SSL_FORCE='yes' LETSENCRYPT='yes' FTP_USER='' FTP_MD5='SECRETO_NO_DEBE_SALIR_5' BACKEND='PHP-8_1' PROXY='default' STATS='' STATS_USER='' STATS_CRYPT='SECRETO_NO_DEBE_SALIR_6' U_DISK='100' SUSPENDED='no'\n"
    printf "DOMAIN='joomla.example.org' IP='203.0.113.10' CUSTOM_DOCROOT='' ALIAS='' TPL='default' SSL='yes' SSL_FORCE='no' LETSENCRYPT='yes' FTP_MD5='SECRETO_NO_DEBE_SALIR_7' BACKEND='PHP-8_1' PROXY='default' STATS_CRYPT='SECRETO_NO_DEBE_SALIR_8' U_DISK='50' SUSPENDED='no'\n"
    printf "DOMAIN='intranet.example.org' IP='203.0.113.10' CUSTOM_DOCROOT='' ALIAS='' TPL='default' SSL='no' SSL_FORCE='no' LETSENCRYPT='no' FTP_MD5='SECRETO_NO_DEBE_SALIR_9' BACKEND='PHP-7_4' PROXY='default' U_DISK='30' SUSPENDED='no'\n"
    printf "DOMAIN='estatico.example.org' IP='203.0.113.10' CUSTOM_DOCROOT='' ALIAS='' TPL='default' SSL='no' SSL_FORCE='no' LETSENCRYPT='no' BACKEND='default' PROXY='default' U_DISK='1' SUSPENDED='no'\n"
    printf "DOMAIN='sub.example.org' IP='203.0.113.10' CUSTOM_DOCROOT='' ALIAS='' TPL='default' SSL='no' SSL_FORCE='no' LETSENCRYPT='no' BACKEND='PHP-8_1' PROXY='default' U_DISK='1' SUSPENDED='no'\n"
  } > "$H/data/users/cuenta1/web.conf"

  cat > "$H/data/users/cuenta1/db.conf" <<'FIN'
DB='cuenta1_web' DBUSER='cuenta1_web' HOST='localhost' TYPE='mysql' CHARSET='utf8mb4' U_DISK='10' SUSPENDED='no'
DB='cuenta1_portal' DBUSER='cuenta1_portal' HOST='localhost' TYPE='mysql' CHARSET='utf8mb4' U_DISK='5' SUSPENDED='no'
DB='cuenta1_intranet' DBUSER='cuenta1_intranet' HOST='localhost' TYPE='mysql' CHARSET='utf8' U_DISK='2' SUSPENDED='no'
FIN

  cat > "$H/data/users/cuenta1/mail.conf" <<'FIN'
DOMAIN='example.org' ANTIVIRUS='no' ANTISPAM='yes' DKIM='yes' CATCHALL='' ACCOUNTS='2' U_DISK='3' SUSPENDED='no'
FIN

  cat > "$H/data/users/cuenta1/mail/example.org.conf" <<'FIN'
ACCOUNT='info' ALIAS='contacto' FWD='' FWD_ONLY='no' AUTOREPLY='no' QUOTA='1024' U_DISK='2' SUSPENDED='no'
ACCOUNT='ventas' ALIAS='' FWD='otro@example.net' FWD_ONLY='no' AUTOREPLY='no' QUOTA='unlimited' U_DISK='1' SUSPENDED='no'
FIN

  cat > "$H/data/users/cuenta1/cron.conf" <<'FIN'
MIN='0' HOUR='3' DAY='*' MONTH='*' WDAY='*' CMD='php /home/cuenta1/web/example.org/public_html/cron.php' JOB='1' SUSPENDED='no'
MIN='30' HOUR='4' DAY='*' MONTH='*' WDAY='*' CMD='/usr/bin/php8.1 /home/cuenta1/scripts/limpiar.php' JOB='2' SUSPENDED='no'
FIN

  # Tres zonas a propósito: una normal sin DNSSEC, una con DNSSEC='yes'
  # (que tiene que avisar), y una que figura en dns.conf pero cuyo .conf no
  # se puede leer (tiene que decir "no disponible" sin abortar el análisis).
  cat > "$H/data/users/cuenta1/dns.conf" <<'FIN'
DOMAIN='example.org' IP='203.0.113.10' TPL='default' TTL='14400' EXP='2027-01-01' SOA='ns1.example.org' RECORDS='8' DNSSEC='no' SUSPENDED='no'
DOMAIN='firmada.example.org' IP='203.0.113.10' TPL='default' TTL='14400' EXP='2027-01-01' SOA='ns1.example.org' RECORDS='3' DNSSEC='yes' SUSPENDED='no'
DOMAIN='ilegible.example.org' IP='203.0.113.10' TPL='default' TTL='14400' EXP='2027-01-01' SOA='ns1.example.org' RECORDS='3' DNSSEC='no' SUSPENDED='no'
FIN

  cat > "$H/data/users/cuenta1/dns/example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='A' VALUE='203.0.113.10'
ID='2' RECORD='www' TYPE='A' VALUE='203.0.113.10'
ID='3' RECORD='mail' TYPE='A' VALUE='203.0.113.10'
FIN

  cat > "$H/data/users/cuenta1/dns/firmada.example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='A' VALUE='203.0.113.10'
ID='2' RECORD='mail' TYPE='A' VALUE='203.0.113.10'
FIN

  # Existe, pero sin permiso de lectura: el caso que no debe abortar nada.
  printf "ID='1' RECORD='@' TYPE='A' VALUE='203.0.113.10'\n" \
    > "$H/data/users/cuenta1/dns/ilegible.example.org.conf"
  chmod 000 "$H/data/users/cuenta1/dns/ilegible.example.org.conf"

  # --- cron puesto a mano, que el panel no conoce ---
  printf '# comentario\n0 5 * * * /usr/local/bin/propio.sh\n' > "$raiz/spool/cuenta1"

  # --- Los sitios de cuenta1 ---

  # WordPress
  mkdir -p "$HOMES/cuenta1/web/example.org/public_html"
  cat > "$HOMES/cuenta1/web/example.org/public_html/wp-config.php" <<'FIN'
<?php
define( 'DB_NAME', 'cuenta1_web' );
define( 'DB_USER', 'cuenta1_web' );
define( 'DB_PASSWORD', 'SECRETO_NO_DEBE_SALIR_10' );
define( 'DB_HOST', 'localhost' );
$table_prefix = 'wp_';
FIN

  # Joomla
  mkdir -p "$HOMES/cuenta1/web/joomla.example.org/public_html"
  cat > "$HOMES/cuenta1/web/joomla.example.org/public_html/configuration.php" <<'FIN'
<?php
class JConfig {
	public $host = 'localhost';
	public $user = 'cuenta1_portal';
	public $password = 'SECRETO_NO_DEBE_SALIR_11';
	public $db = 'cuenta1_portal';
	public $dbprefix = 'jos_';
}
FIN

  # CodeIgniter 3.1.7, con entorno 'production' y su database.php propio
  local ci="$HOMES/cuenta1/web/intranet.example.org/public_html"
  mkdir -p "$ci/system/core" "$ci/application/config/production"
  printf "<?php\ndefine('CI_VERSION', '3.1.7');\n" > "$ci/system/core/CodeIgniter.php"
  printf "<?php\ndefine('ENVIRONMENT', 'production');\nrequire_once BASEPATH.'core/CodeIgniter.php';\n" \
    > "$ci/index.php"
  # El general: el que NO se debe reescribir, porque el de production manda.
  cat > "$ci/application/config/database.php" <<'FIN'
<?php
$active_group = 'default';
$db['default'] = array(
	'hostname' => 'localhost',
	'username' => 'general_user',
	'password' => 'SECRETO_NO_DEBE_SALIR_12',
	'database' => 'general_db',
	'dbdriver' => 'mysqli',
);
FIN
  cat > "$ci/application/config/production/database.php" <<'FIN'
<?php
$active_group = 'default';
$db['default'] = array(
	'hostname' => 'localhost',
	'username' => 'cuenta1_intranet',
	'password' => 'SECRETO_NO_DEBE_SALIR_13',
	'database' => 'cuenta1_intranet',
	'dbdriver' => 'mysqli',
);
FIN

  # Un sitio con solo index.html y robots.txt: NO es piecesphp.
  mkdir -p "$HOMES/cuenta1/web/estatico.example.org/public_html"
  printf '<html><body>Hola</body></html>\n' > "$HOMES/cuenta1/web/estatico.example.org/public_html/index.html"
  printf 'User-agent: *\n' > "$HOMES/cuenta1/web/estatico.example.org/public_html/robots.txt"

  # Un subdominio vacío
  mkdir -p "$HOMES/cuenta1/web/sub.example.org/public_html"

  # --- Correo en Maildir, con mensajes contables ---
  local buzon="$HOMES/cuenta1/mail/example.org/info"
  mkdir -p "$buzon/cur" "$buzon/new" "$buzon/tmp" "$buzon/.Sent/cur" "$buzon/.Sent/new"
  printf 'From: a@example.net\n\nuno\n'  > "$buzon/cur/1.msg"
  printf 'From: b@example.net\n\ndos\n'  > "$buzon/cur/2.msg"
  printf 'From: c@example.net\n\ntres\n' > "$buzon/new/3.msg"
  printf 'To: d@example.net\n\ncuatro\n' > "$buzon/.Sent/cur/4.msg"
  # 4 mensajes: 2 en cur/, 1 en new/, 1 en .Sent/cur/. tmp/ no cuenta.
  printf 'basura\n' > "$buzon/tmp/no-es-un-mensaje"

  local buzon2="$HOMES/cuenta1/mail/example.org/ventas"
  mkdir -p "$buzon2/cur" "$buzon2/new"
  printf 'From: e@example.net\n\nuno\n' > "$buzon2/cur/1.msg"
  # 1 mensaje

  mkdir -p "$HOMES/cuenta1/conf/mail/example.org"
  printf 'info@example.org:SECRETO_NO_DEBE_SALIR_14\n' \
    > "$HOMES/cuenta1/conf/mail/example.org/passwd"

  # =========================================================================
  # cuenta2
  # =========================================================================
  cat > "$H/data/users/cuenta2/user.conf" <<'FIN'
PACKAGE='basico'
SHELL='nologin'
SUSPENDED='no'
RKEY='SECRETO_NO_DEBE_SALIR_15'
FIN

  {
    printf "DOMAIN='example.net' IP='203.0.113.10' CUSTOM_DOCROOT='' ALIAS='' TPL='default' SSL='no' SSL_FORCE='no' LETSENCRYPT='no' BACKEND='PHP-7_4' PROXY='default' U_DISK='20' SUSPENDED='no'\n"
    printf "DOMAIN='repes.example.net' IP='203.0.113.10' CUSTOM_DOCROOT='' ALIAS='' TPL='default' SSL='no' SSL_FORCE='no' LETSENCRYPT='no' BACKEND='PHP-7_4' PROXY='default' U_DISK='20' SUSPENDED='no'\n"
    printf "DOMAIN='laravel.example.net' IP='203.0.113.10' CUSTOM_DOCROOT='' ALIAS='' TPL='default' SSL='no' SSL_FORCE='no' LETSENCRYPT='no' BACKEND='PHP-8_1' PROXY='default' U_DISK='20' SUSPENDED='no'\n"
  } > "$H/data/users/cuenta2/web.conf"

  cat > "$H/data/users/cuenta2/db.conf" <<'FIN'
DB='cuenta2_huerfana' DBUSER='cuenta2_huerfana' HOST='localhost' TYPE='mysql' CHARSET='utf8mb4' U_DISK='7' SUSPENDED='no'
FIN

  # CodeIgniter 3 con active_group ajeno
  local ci2="$HOMES/cuenta2/web/example.net/public_html"
  mkdir -p "$ci2/system/core" "$ci2/application/config"
  printf "<?php\ndefine('CI_VERSION', '3.1.9');\n" > "$ci2/system/core/CodeIgniter.php"
  cat > "$ci2/application/config/database.php" <<'FIN'
<?php
$active_group = 'produccion';
$db['produccion'] = array(
	'hostname' => 'localhost',
	'username' => 'otro_user',
	'password' => 'SECRETO_NO_DEBE_SALIR_16',
	'database' => 'otra_db',
	'dbdriver' => 'mysqli',
);
FIN

  # CodeIgniter 3 con una clave repetida
  local ci3="$HOMES/cuenta2/web/repes.example.net/public_html"
  mkdir -p "$ci3/system/core" "$ci3/application/config"
  printf "<?php\ndefine('CI_VERSION', '3.1.7');\n" > "$ci3/system/core/CodeIgniter.php"
  cat > "$ci3/application/config/database.php" <<'FIN'
<?php
$active_group = 'default';
$db['default'] = array(
	'hostname' => 'localhost',
	'username' => 'repe_user',
	'password' => 'SECRETO_NO_DEBE_SALIR_17',
	'database' => 'primera_db',
	'dbdriver' => 'mysqli',
	'database' => 'segunda_db',
);
FIN

  # Laravel
  local lar="$HOMES/cuenta2/web/laravel.example.net/public_html"
  mkdir -p "$lar"
  printf '#!/usr/bin/env php\n<?php\n' > "$lar/artisan"
  cat > "$lar/.env" <<'FIN'
APP_ENV=production
DB_DATABASE=cuenta2_laravel
DB_USERNAME=cuenta2_laravel
DB_PASSWORD=SECRETO_NO_DEBE_SALIR_18
DB_HOST=localhost
FIN

  # Una cuenta en data/users que NO existe en passwd
  mkdir -p "$H/data/users/cuenta3"
  cat > "$H/data/users/cuenta3/user.conf" <<'FIN'
PACKAGE='default'
SHELL='bash'
SUSPENDED='no'
FIN

  # Directorios de datos de MySQL, para que se pueda medir alguno
  mkdir -p "$raiz/mysql/cuenta1_web"
  printf 'no es una base de verdad\n' > "$raiz/mysql/cuenta1_web/tabla.ibd"

  # Un valor con espacios raros y una comilla, para P13
  printf "DOMAIN='example.org' RAREZA='con espacios  y  tal' OTRA='sin cerrar\n" \
    >> "$H/data/users/cuenta1/mail.conf"
}

# Suma de TODO el árbol: ruta, modo y contenido de cada archivo, más la lista
# de directorios con su modo. Si el analizador escribe, borra, o cambia un
# permiso de cualquier cosa, esta suma cambia.
suma_del_arbol() {
  local raiz="$1"
  {
    find "$raiz" -type f -printf '%m %P\n' 2>/dev/null | LC_ALL=C sort
    find "$raiz" -type d -printf 'D %m %P\n' 2>/dev/null | LC_ALL=C sort
    find "$raiz" -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r cat 2>/dev/null
  } | sha256sum | awk '{print $1}'
}

# Monta las órdenes falsas y devuelve el PATH que las antepone.
montar_falsos() {
  local dir="$1" registro="$2"
  mkdir -p "$dir"
  : > "$registro"
  local orden
  for orden in "${PROHIBIDAS[@]}"; do
    {
      printf '#!/usr/bin/env bash\n'
      printf 'printf "%%s %%s\\n" "%s" "$*" >> %q\n' "$orden" "$registro"
      printf 'exit 0\n'
    } > "$dir/$orden"
    chmod +x "$dir/$orden"
  done
  printf '%s' "$dir:$PATH"
}

# Ejecuta el PAQUETE sobre el árbol falso. Deja stdout y stderr en archivos.
# Devuelve el código de salida.
correr_analizador() {
  local raiz="$1" paquete="$2" ruta_path="$3" salida_std="$4" salida_err="$5"
  shift 5
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$ruta_path" \
    LANG=C.UTF-8 \
    HESTIA_DIR="$raiz/hestia" \
    HOME_DIR="$raiz/home" \
    ETC_DIR="$raiz/etc" \
    SPOOL_CRON="$raiz/spool" \
    MYSQL_DATADIR="$raiz/mysql" \
    SALIDA_BASE="$raiz/salida" \
    bash "$paquete" "$@" > "$salida_std" 2> "$salida_err"
}

# El directorio de salida que creó el analizador.
dir_de_salida() {
  find "$1/salida" -maxdepth 1 -type d -name 'analisis-hestia.*' 2>/dev/null | head -1
}

# -----------------------------------------------------------------------------
# Construir el paquete una vez, y comprobarlo
# -----------------------------------------------------------------------------
PAQUETE="$BANCO_TMP/analizar.paquete.sh"

test_the_package_builds_and_embeds_the_reader() {
  nueva_prueba an0

  # Se construye con el constructor del repositorio, en un directorio propio,
  # para no depender de que alguien haya dejado un paquete viejo ahí.
  local d="$BANCO_TMP/an0"
  cp "$MIG/analizar.sh" "$MIG/BASE_LEER_CONFIG.sh" "$MIG/construir-analizador.sh" "$d/"

  ( cd "$d" && bash construir-analizador.sh ) > "$d/construir.txt" 2>&1
  afirmar_codigo 0 "$?" "el constructor del paquete termina bien"

  afirmar_existe "$d/analizar.paquete.sh" "el paquete se escribió"
  cp "$d/analizar.paquete.sh" "$PAQUETE"

  afirmar_contiene "$PAQUETE" "ANALIZADOR_HELPER_EMBEBIDO" \
    "el paquete trae el lector de configuraciones embebido"
  afirmar_contiene "$PAQUETE" "leer_config.php ARCHIVO FORMATO" \
    "lo embebido es el lector de verdad, extraído de BASE_LEER_CONFIG.sh"

  bash -n "$PAQUETE"
  afirmar_codigo 0 "$?" "el paquete pasa bash -n"

  # El sello. Construido fuera de un repositorio de git, el commit no se
  # puede saber: tiene que decir "desconocido" y NO fallar, que es la
  # degradación que pide la instrucción.
  afirmar_contiene "$PAQUETE" "^ANALIZADOR_COMMIT=" \
    "S1: el paquete lleva el commit del que sale"
  afirmar_contiene "$PAQUETE" "^ANALIZADOR_CONSTRUIDO=" \
    "S1: y la fecha de construcción"
  afirmar_contiene "$PAQUETE" "^ANALIZADOR_SHA256='analizar.sh [0-9a-f]{64} / BASE_LEER_CONFIG.sh [0-9a-f]{64}'" \
    "S1: y las sumas de los dos archivos que entran en él"
  afirmar_contiene "$PAQUETE" "ANALIZADOR_COMMIT='desconocido'" \
    "S1: fuera de un repositorio, el commit es 'desconocido' y no falla"
}

# -----------------------------------------------------------------------------
# S1 y S2: el sello, con un git falso
# -----------------------------------------------------------------------------
# Un git de verdad aquí daría un resultado distinto según cómo esté el árbol
# del repositorio en ese momento, y la prueba cambiaría de sentido sola. Con un
# git falso se controla la respuesta: es la misma idea que las demás órdenes
# falsas del banco.
#
# Así además se prueba el caso que de verdad importa —un paquete construido con
# cambios sin commitear— sin tocar el árbol real ni el estado de git.
construir_con_git_falso() {
  local d="$1" sucio="$2"

  mkdir -p "$d/bin"
  cp "$MIG/analizar.sh" "$MIG/BASE_LEER_CONFIG.sh" "$MIG/construir-analizador.sh" "$d/"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'args="$*"\n'
    # Se ignora el "-C <dir>" de delante: aquí no hay repositorio al que ir.
    printf 'case "$args" in\n'
    printf '  *"rev-parse --git-dir"*)    echo ".git"; exit 0 ;;\n'
    printf '  *"rev-parse --short HEAD"*) echo "abc1234"; exit 0 ;;\n'
    printf '  *"status --porcelain"*)\n'
    if [[ "$sucio" == "sucio" ]]; then
      printf '    echo " M analizar.sh"; exit 0 ;;\n'
    else
      printf '    exit 0 ;;\n'
    fi
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$d/bin/git"
  chmod +x "$d/bin/git"

  ( cd "$d" && PATH="$d/bin:$PATH" bash construir-analizador.sh ) > "$d/construir.txt" 2>&1
}

test_the_seal_records_the_commit_and_flags_uncommitted_changes() {
  nueva_prueba an11

  # --- Árbol limpio: el commit, a secas ---
  local limpio="$BANCO_TMP/an11/limpio"
  mkdir -p "$limpio"
  construir_con_git_falso "$limpio" "limpio"
  afirmar_codigo 0 "$?" "S1: el constructor termina bien con git disponible"

  afirmar_contiene "$limpio/analizar.paquete.sh" "ANALIZADOR_COMMIT='abc1234'" \
    "S1: con el árbol limpio, el sello lleva el commit a secas"

  # --- Con cambios sin commitear: el commit, marcado ---
  local sucio="$BANCO_TMP/an11/sucio"
  mkdir -p "$sucio"
  construir_con_git_falso "$sucio" "sucio"
  afirmar_codigo 0 "$?" "S2: el constructor termina bien con cambios sin commitear"

  afirmar_contiene "$sucio/analizar.paquete.sh" "ANALIZADOR_COMMIT='abc1234\+cambios'" \
    "S2: con cambios sin commitear, el commit lleva '+cambios'"

  # --- Y el sello llega al informe y a las propuestas ---
  local d="$BANCO_TMP/an11"
  local raiz="$d/arbol"
  sembrar_arbol "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  correr_analizador "$raiz" "$sucio/analizar.paquete.sh" "$ruta_path" \
    "$d/stdout.txt" "$d/stderr.txt"
  afirmar_codigo 0 "$?" "S1: el paquete sellado se ejecuta igual"

  local sal
  sal="$(dir_de_salida "$raiz")"

  afirmar_contiene "$sal/informe.txt" "Analizador, commit  : abc1234\+cambios" \
    "S1: el informe dice de qué versión del analizador sale"
  afirmar_contiene "$sal/informe.txt" "Paquete construido  : [0-9]{4}-[0-9]{2}-[0-9]{2}" \
    "S1: y cuándo se construyó el paquete"
  afirmar_contiene "$sal/informe.txt" "Sumas               : analizar.sh [0-9a-f]{64}" \
    "S1: y las sumas de lo que lleva dentro"
  afirmar_contiene "$sal/migracion-cuenta1.sh" "Analizador, commit: abc1234\+cambios" \
    "S1: cada propuesta también dice de qué versión sale"
  afirmar_contiene "$d/stdout.txt" "Analizador, commit : abc1234\+cambios" \
    "S1: y el resumen en pantalla, para verlo sin abrir el informe"

  afirmar_igual "$(wc -c < "$d/registro.txt" | tr -d ' ')" "0" \
    "S1: el paquete sellado sigue sin invocar ninguna orden prohibida"
}

# Sin empaquetar, ejecutando analizar.sh desde el repositorio, el sello lo dice
# en vez de callar: un informe siempre puede decir de dónde viene.
test_unpackaged_run_says_so() {
  nueva_prueba an12
  local d="$BANCO_TMP/an12"
  local raiz="$d/arbol"
  sembrar_arbol "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  correr_analizador "$raiz" "$MIG/analizar.sh" "$ruta_path" "$d/stdout.txt" "$d/stderr.txt"
  afirmar_codigo 0 "$?" "analizar.sh suelto, desde el repositorio, se ejecuta"

  local sal
  sal="$(dir_de_salida "$raiz")"
  afirmar_contiene "$sal/informe.txt" "Analizador, commit  : sin empaquetar" \
    "el informe de una corrida sin empaquetar lo dice"

  # Y aun sin paquete encuentra el lector, porque está a su lado.
  afirmar_contiene "$sal/informe.txt" "base que usa   : cuenta1_web" \
    "sin paquete, el lector se extrae de BASE_LEER_CONFIG.sh que está al lado"
}

# -----------------------------------------------------------------------------
# P1, P2, P3, P4: la corrida completa y las tres reglas
# -----------------------------------------------------------------------------
# Una sola corrida sirve para las cuatro: se mide el árbol antes, se corre, y
# se comprueba todo sobre el resultado.
CORRIDA="" # directorio de la corrida completa, para las pruebas siguientes
SALIDA_DIR=""

test_full_run_is_read_only_quiet_and_secret_free() {
  nueva_prueba an1
  local d="$BANCO_TMP/an1"
  CORRIDA="$d"

  local raiz="$d/arbol"
  sembrar_arbol "$raiz"

  local registro="$d/registro-prohibidas.txt"
  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$registro")"

  local antes
  antes="$(suma_del_arbol "$raiz")"

  correr_analizador "$raiz" "$PAQUETE" "$ruta_path" "$d/stdout.txt" "$d/stderr.txt"
  local rc=$?

  # --- P1 ---
  afirmar_codigo 0 "$rc" "P1: el analizador termina con código 0"

  SALIDA_DIR="$(dir_de_salida "$raiz")"
  afirmar_igual "$(test -n "$SALIDA_DIR" && echo si || echo no)" "si" \
    "P1: creó su directorio de salida"
  afirmar_igual "$(stat -c '%a' "$SALIDA_DIR" 2>/dev/null)" "700" \
    "P1: el directorio de salida es 700"
  afirmar_existe "$SALIDA_DIR/informe.txt" "P1: escribió informe.txt"
  afirmar_igual "$(stat -c '%a' "$SALIDA_DIR/informe.txt" 2>/dev/null)" "600" \
    "P1: informe.txt es 600"
  afirmar_existe "$SALIDA_DIR/migracion-cuenta1.sh" "P1: propuesta de cuenta1"
  afirmar_existe "$SALIDA_DIR/migracion-cuenta2.sh" "P1: propuesta de cuenta2"
  afirmar_igual "$(stat -c '%a' "$SALIDA_DIR/migracion-cuenta1.sh" 2>/dev/null)" "600" \
    "P1: las propuestas son 600"

  # Los temporales internos no se quedan.
  afirmar_igual "$(find "$SALIDA_DIR" -maxdepth 1 -name '.*' -type f 2>/dev/null | wc -l | tr -d ' ')" "0" \
    "P1: no deja archivos temporales en la salida"

  # --- P2: SOLO LECTURA ---
  # La suma se toma excluyendo el directorio de salida, que es lo único que
  # el analizador tiene permitido crear.
  local despues
  despues="$(cd "$d" && mv "$SALIDA_DIR" "$d/salida-apartada" && suma_del_arbol "$raiz")"
  afirmar_igual "$despues" "$antes" \
    "P2: el árbol del servidor queda byte a byte y modo a modo idéntico"
  mv "$d/salida-apartada" "$SALIDA_DIR"

  # Y nada más que el directorio de salida apareció en SALIDA_BASE.
  afirmar_igual "$(find "$raiz/salida" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')" "1" \
    "P2: en SALIDA_BASE solo está el directorio de salida"

  # --- P3: NI PANEL NI RED ---
  afirmar_igual "$(wc -c < "$registro" | tr -d ' ')" "0" \
    "P3: no invocó ninguna orden del panel, de red, de base de datos ni sudo ($(cat "$registro" | tr '\n' ' '))"

  # Estática, además de la dinámica: ninguna llamada a una v-* en el código.
  local hallazgos
  hallazgos="$(grep -nE '(^|[^a-zA-Z0-9_./-])v-[a-z][a-z-]*' "$MIG/analizar.sh" | grep -v '^[0-9]*:#' || true)"
  afirmar_igual "$(printf '%s' "$hallazgos" | grep -c . || true)" "0" \
    "P3: ninguna línea de código del analizador nombra una orden v-* ($hallazgos)"

  # --- P4: NINGÚN SECRETO ---
  local fugas
  fugas="$(grep -rl "SECRETO_NO_DEBE_SALIR" "$SALIDA_DIR" 2>/dev/null || true)"
  afirmar_igual "$(printf '%s' "$fugas" | grep -c . || true)" "0" \
    "P4: ningún secreto en los archivos generados ($fugas)"

  afirmar_no_contiene "$d/stdout.txt" "SECRETO_NO_DEBE_SALIR" \
    "P4: ningún secreto por la salida estándar"
  afirmar_no_contiene "$d/stderr.txt" "SECRETO_NO_DEBE_SALIR" \
    "P4: ningún secreto por la salida de error"

  # Y el resumen final dice cómo borrar lo que sí lleva contraseñas nuevas.
  afirmar_contiene "$d/stdout.txt" "Cópialos a tu equipo y borra este directorio" \
    "P1: el resumen dice que hay que borrar el directorio"
}

# -----------------------------------------------------------------------------
# P5: los tipos, con su evidencia
# -----------------------------------------------------------------------------
test_application_types_are_detected_with_evidence() {
  nueva_prueba an2
  local inf="$SALIDA_DIR/informe.txt"

  afirmar_contiene "$inf" "aplicación     : wordpress" "P5: detecta WordPress"
  afirmar_contiene "$inf" "wp-config.php" "P5: y escribe su evidencia"

  afirmar_contiene "$inf" "aplicación     : joomla" "P5: detecta Joomla"
  afirmar_contiene "$inf" "configuration.php" "P5: y escribe su evidencia"

  afirmar_contiene "$inf" "aplicación     : codeigniter3" "P5: detecta CodeIgniter 3"
  afirmar_contiene "$inf" "CI_VERSION 3.1.7" "P5: y la versión que lo demuestra"

  afirmar_contiene "$inf" "aplicación     : laravel" "P5: detecta Laravel"

  # El sitio con solo index.html NO es piecesphp.
  afirmar_contiene "$inf" "evidencia      : no se pudo determinar" \
    "P5: un sitio con solo index.html queda sin determinar"
  afirmar_no_contiene "$inf" "piecesphp" \
    "P5: no se da por hecho el tipo por defecto en ningún sitio"

  # La base que cada aplicación tiene escrita, leída con el helper.
  afirmar_contiene "$inf" "base que usa   : cuenta1_web" \
    "P5: lee la base del WordPress"
  afirmar_contiene "$inf" "base que usa   : cuenta1_portal" \
    "P5: lee la base del Joomla"
}

# -----------------------------------------------------------------------------
# P6: CodeIgniter — entorno, grupo activo, claves repetidas
# -----------------------------------------------------------------------------
test_codeigniter_environment_and_guards() {
  nueva_prueba an3
  local inf="$SALIDA_DIR/informe.txt"
  local prop1="$SALIDA_DIR/migracion-cuenta1.sh"

  afirmar_contiene "$inf" "application/config/production/database.php" \
    "P6: ruta_db apunta al database.php del entorno activo"
  afirmar_contiene "$inf" "ENVIRONMENT es 'production'" \
    "P6: y lo avisa, diciendo por qué ese manda"
  # Relativa a la carpeta del DOMINIO, como las de CFG_RUTA_POR_TIPO en
  # BASE_CONFIG.sh (que son "public_html/..."), no a public_html.
  afirmar_contiene "$prop1" 'ruta_db="public_html/application/config/production/database.php"' \
    "P6: la propuesta lleva esa ruta_db, relativa a la carpeta del dominio"

  # La base que se lee es la del entorno activo, no la del general.
  afirmar_contiene "$inf" "base que usa   : cuenta1_intranet" \
    "P6: lee la base del database.php que la aplicación usa de verdad"
  afirmar_no_contiene "$prop1" "general_db" \
    "P6: no propone la base del database.php general, que no se usa"

  afirmar_contiene "$inf" "active_group es produccion, no default" \
    "P6: avisa del grupo activo ajeno"
  afirmar_contiene "$inf" "la clave database aparece 2 veces" \
    "P6: avisa de la clave repetida"
}

# -----------------------------------------------------------------------------
# P7: PHP explícito y el centinela
# -----------------------------------------------------------------------------
test_php_version_is_explicit_or_refused() {
  nueva_prueba an4
  local inf="$SALIDA_DIR/informe.txt"
  local prop1="$SALIDA_DIR/migracion-cuenta1.sh"

  afirmar_contiene "$prop1" 'php="PHP-8_1"' "P7: PHP-8_1 se propone tal cual"
  afirmar_contiene "$prop1" 'php="PHP-7_4"' "P7: PHP-7_4 se propone tal cual"

  afirmar_contiene "$prop1" 'php="" \\' \
    "P7: con BACKEND default, php queda VACÍO (el centinela)"
  afirmar_contiene "$inf" "BACKEND es «default»" \
    "P7: y el informe avisa de ese dominio"
  afirmar_contiene "$prop1" "la versión real de PHP" \
    "P7: la propuesta explica por qué está vacío"
  afirmar_no_contiene "$prop1" 'php="default"' \
    "P7: nunca se propone 'default' como si fuera una versión"
}

# -----------------------------------------------------------------------------
# P8: el correo se cuenta exacto
# -----------------------------------------------------------------------------
test_mail_messages_are_counted_exactly() {
  nueva_prueba an5
  local inf="$SALIDA_DIR/informe.txt"

  # info: 2 en cur/, 1 en new/, 1 en .Sent/cur/ = 4. El de tmp/ no cuenta.
  afirmar_contiene "$inf" "mensajes : 4" \
    "P8: cuenta 4 mensajes en el buzón con carpetas, sin contar tmp/"
  # ventas: 1
  afirmar_contiene "$inf" "mensajes : 1" \
    "P8: cuenta 1 mensaje en el otro buzón"
  afirmar_contiene "$inf" "cuota    : unlimited" \
    "P8: la cuota 'unlimited' se escribe tal cual"
}

# -----------------------------------------------------------------------------
# P9: las propuestas son bash válido, y cfg_validar las juzga
# -----------------------------------------------------------------------------
# Tal como salen, cfg_validar las RECHAZA: es lo que impide usarlas sin
# revisarlas. Con el centinela de php resuelto, las ACEPTA.
test_proposals_are_rejected_as_generated_and_accepted_once_reviewed() {
  nueva_prueba an6
  local d="$BANCO_TMP/an6"
  local prop="$SALIDA_DIR/migracion-cuenta1.sh"

  bash -n "$prop"
  afirmar_codigo 0 "$?" "P9: la propuesta de cuenta1 pasa bash -n"
  bash -n "$SALIDA_DIR/migracion-cuenta2.sh"
  afirmar_codigo 0 "$?" "P9: la propuesta de cuenta2 pasa bash -n"

  local registro="$d/registro.txt"
  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$registro")"

  # Tal cual sale: cfg_validar tiene que rechazarla.
  env -i PATH="$ruta_path" LANG=C.UTF-8 HOME="$d" bash -c '
    cd "$1"
    USER_DESTINO="cuenta1"
    source "$2/BASE_CONFIG.sh"
    source "$3"
    cfg_validar
  ' _ "$d" "$MIG" "$prop" > "$d/tal-cual.txt" 2>&1
  afirmar_codigo 1 "$?" \
    "P9: tal como sale, cfg_validar la RECHAZA"
  afirmar_contiene "$d/tal-cual.txt" "no tiene php definido" \
    "P9: y dice qué falta, nombrando el dominio"

  # Revisada: se resuelve el centinela de php y la IP de destino.
  sed -e 's/^  php="" \\/  php="PHP-8_1" \\/' \
      -e 's/^IP_DESTINO="";/IP_DESTINO="203.0.113.20";/' \
      "$prop" > "$d/revisada.sh"

  env -i PATH="$ruta_path" LANG=C.UTF-8 HOME="$d" bash -c '
    cd "$1"
    USER_DESTINO="cuenta1"
    source "$2/BASE_CONFIG.sh"
    source "$3"
    cfg_validar
  ' _ "$d" "$MIG" "$d/revisada.sh" > "$d/revisada.txt" 2>&1
  afirmar_codigo 0 "$?" \
    "P9: con el php resuelto, cfg_validar la ACEPTA ($(cat "$d/revisada.txt" | tr '\n' ' '))"

  afirmar_igual "$(wc -c < "$registro" | tr -d ' ')" "0" \
    "P9: cargar la propuesta no invocó ninguna orden prohibida"

  # La cabecera obligatoria.
  afirmar_contiene "$prop" "PROPUESTA GENERADA POR EL ANALIZADOR — revisar antes de usar" \
    "P9: la propuesta se presenta como propuesta"
  afirmar_contiene "$prop" "HestiaCP de origen: 1.10.5" \
    "P9: y dice de qué versión de HestiaCP salió"
  afirmar_contiene "$prop" "AVISOS DE ESTA CUENTA" \
    "P9: y lleva los avisos de su cuenta"
  afirmar_contiene "$prop" 'forzar_ssl="false"' \
    "P9: forzar_ssl siempre en false"
}

# -----------------------------------------------------------------------------
# T1: la IP de destino se deja VACÍA, y eso basta para que se rechace
# -----------------------------------------------------------------------------
# Antes, el centinela era el texto "PENDIENTE_IP_DESTINO", que la herramienta
# NO rechaza: BASE_GENERAL.sh solo comprueba que IP_DESTINO no esté vacía, y no
# valida su formato en ninguna parte. Así que una cuenta en la que ningún
# dominio tuviera BACKEND="default" —y por tanto sin ningún php="" que
# cfg_validar rechazara— se podía ejecutar tal como salía del analizador, con
# una IP que era una palabra.
#
# cuenta2 es exactamente ese caso: todos sus dominios traen PHP-7_4 o PHP-8_1.
# Por eso la prueba va contra su propuesta, no contra la de cuenta1.
#
# La comprobación que rechaza la IP vacía NO está en cfg_validar, sino en el
# bloque de validaciones iniciales de BASE_GENERAL.sh, así que se extrae ese
# bloque por sus marcadores y se ejecuta aislado. El bloque no conecta a nada:
# son comprobaciones de variables.
test_empty_destination_ip_is_rejected_even_without_a_php_sentinel() {
  nueva_prueba an13
  local d="$BANCO_TMP/an13"
  local prop2="$SALIDA_DIR/migracion-cuenta2.sh"

  afirmar_contiene "$prop2" '^IP_DESTINO="";' \
    "T1: la propuesta deja IP_DESTINO vacía"
  afirmar_no_contiene "$prop2" "PENDIENTE_IP_DESTINO" \
    "T1: ya no se emite el centinela de texto"
  afirmar_contiene "$prop2" "Vacía a propósito: la" \
    "T1: y explica por qué está vacía"

  # Y esta cuenta NO tiene ningún php vacío: su rechazo solo puede venir de
  # la IP. Si alguna vez lo tuviera, esta prueba dejaría de probar lo que dice.
  afirmar_no_contiene "$prop2" 'php="" ' \
    "T1: cuenta2 no tiene ningún dominio con php vacío (es el caso que importa)"

  # El bloque de validaciones iniciales, por marcadores.
  awk '
    index($0, "=== VALIDACIONES INICIALES ===") > 0 { dentro = 1; next }
    dentro && index($0, "ya fueron validados") > 0 { exit }
    dentro { print }
  ' "$MIG/BASE_GENERAL.sh" > "$d/validaciones.sh"

  afirmar_contiene "$d/validaciones.sh" 'IP_DESTINO no está definido' \
    "T1: se extrajo el bloque de validaciones que rechaza la IP vacía"

  local registro="$d/registro.txt"
  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$registro")"

  # Tal como sale: el bloque tiene que rechazarla.
  env -i PATH="$ruta_path" LANG=C.UTF-8 HOME="$d" bash -c '
    cd "$1"
    FASE="plan"
    source "$2/BASE_CONFIG.sh"
    source "$3"
    source "$1/validaciones.sh"
    echo "NO SE DETUVO"
  ' _ "$d" "$MIG" "$prop2" > "$d/tal-cual.txt" 2>&1
  afirmar_codigo 1 "$?" \
    "T1: tal como sale, la cuenta sin php vacío se RECHAZA por la IP"
  afirmar_contiene "$d/tal-cual.txt" "ERROR: IP_DESTINO no está definido" \
    "T1: y el mensaje dice qué falta"
  afirmar_no_contiene "$d/tal-cual.txt" "NO SE DETUVO" \
    "T1: la ejecución se detuvo ahí, no siguió"

  # Con la IP puesta, pasa.
  sed -e 's/^IP_DESTINO="";/IP_DESTINO="203.0.113.20";/' "$prop2" > "$d/revisada.sh"

  env -i PATH="$ruta_path" LANG=C.UTF-8 HOME="$d" bash -c '
    cd "$1"
    FASE="plan"
    source "$2/BASE_CONFIG.sh"
    source "$3"
    source "$1/validaciones.sh"
    echo "PASO"
  ' _ "$d" "$MIG" "$d/revisada.sh" > "$d/revisada.txt" 2>&1
  afirmar_contiene "$d/revisada.txt" "PASO" \
    "T1: con la IP escrita, las validaciones iniciales la aceptan"

  afirmar_igual "$(wc -c < "$registro" | tr -d ' ')" "0" \
    "T1: nada de esto invocó una orden prohibida"
}

# -----------------------------------------------------------------------------
# P10: cron, base huérfana, usuario sin '@'
# -----------------------------------------------------------------------------
test_warnings_for_cron_orphan_database_and_unknown_user() {
  nueva_prueba an7
  local inf="$SALIDA_DIR/informe.txt"
  local prop2="$SALIDA_DIR/migracion-cuenta2.sh"

  afirmar_contiene "$inf" "llama a «php» por nombre corto" \
    "P10: avisa del cron que llama al intérprete sin ruta"
  afirmar_no_contiene "$inf" "llama a «php8.1»" \
    "P10: no avisa del cron que sí lleva la ruta absoluta"

  afirmar_contiene "$inf" "que el panel NO conoce" \
    "P10: avisa de los cron puestos a mano, sin imprimirlos"
  afirmar_no_contiene "$inf" "propio.sh" \
    "P10: y no imprime su contenido"

  afirmar_contiene "$inf" "la base cuenta2_huerfana no la usa ninguna aplicación" \
    "P10: avisa de la base que ninguna aplicación usa"
  afirmar_contiene "$prop2" 'base_de_datos "huerfana"' \
    "P10: y la propone como base suelta, con su nombre corto"
  afirmar_contiene "$prop2" 'origen="cuenta2_huerfana"' \
    "P10: con origen, que es obligatorio en una base suelta"

  afirmar_contiene "$inf" "cuenta3" \
    "P10: avisa de la cuenta de data/users que no está en passwd"
}

# -----------------------------------------------------------------------------
# P11: --rapido
# -----------------------------------------------------------------------------
test_rapido_skips_measuring_and_says_so() {
  nueva_prueba an8
  local d="$BANCO_TMP/an8"
  local raiz="$d/arbol"
  sembrar_arbol "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  correr_analizador "$raiz" "$PAQUETE" "$ruta_path" "$d/stdout.txt" "$d/stderr.txt" --rapido
  afirmar_codigo 0 "$?" "P11: con --rapido termina bien"

  local sal
  sal="$(dir_de_salida "$raiz")"
  afirmar_contiene "$sal/informe.txt" "no medido \(--rapido\)" \
    "P11: los tamaños dicen que no se midieron"
  afirmar_contiene "$sal/informe.txt" "no contado \(--rapido\)" \
    "P11: los mensajes dicen que no se contaron"
  afirmar_contiene "$sal/informe.txt" "Se usó --rapido" \
    "P11: y el aviso está arriba, en AVISOS"
  afirmar_no_contiene "$sal/informe.txt" "mensajes : 4" \
    "P11: no hay recuentos de mensajes"
}

# -----------------------------------------------------------------------------
# P12: sin HestiaCP, no se crea nada
# -----------------------------------------------------------------------------
test_missing_hestia_dir_creates_nothing() {
  nueva_prueba an9
  local d="$BANCO_TMP/an9"
  mkdir -p "$d/arbol/salida"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  correr_analizador "$d/arbol" "$PAQUETE" "$ruta_path" "$d/stdout.txt" "$d/stderr.txt"
  local rc=$?

  afirmar_igual "$(test "$rc" -ne 0 && echo si || echo no)" "si" \
    "P12: sin HESTIA_DIR sale con código distinto de 0 (fue $rc)"
  afirmar_contiene "$d/stderr.txt" "No se ha creado ningún archivo" \
    "P12: y lo dice"
  afirmar_igual "$(find "$d/arbol/salida" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')" "0" \
    "P12: no creó ningún directorio de salida"
}

# -----------------------------------------------------------------------------
# P13: un valor raro en un .conf no rompe nada
# -----------------------------------------------------------------------------
# El árbol que siembra esta suite ya lleva, en mail.conf, una línea con
# espacios dobles y una comilla sin cerrar. HestiaCP no escapa los valores
# (50-hestiacp.md), así que esto puede pasar de verdad.
test_odd_values_do_not_break_the_report() {
  nueva_prueba an10
  local inf="$SALIDA_DIR/informe.txt"

  afirmar_existe "$inf" "P13: el informe se escribió a pesar del valor raro"
  afirmar_contiene "$inf" "2. CUENTA: cuenta1" \
    "P13: la sección de cuenta1 está completa"
  afirmar_contiene "$inf" "3. CUENTA: cuenta2" \
    "P13: y la de cuenta2 también: el valor raro no cortó el recorrido"
  afirmar_contiene "$inf" "Zonas DNS" \
    "P13: y las secciones posteriores al mail.conf raro siguen ahí"
}

# -----------------------------------------------------------------------------
# Z1..Z5: las zonas DNS salen copiadas, y el árbol sigue intacto
# -----------------------------------------------------------------------------
# Exportar una zona es lo único que hace el analizador con el DNS: COPIA el
# .conf del origen a su propia salida. La copia tiene que ser byte a byte (una
# zona reescrita "a su manera" dejaría de servir para recrearla) y el original
# tiene que quedar igual, con la misma suma de todo el árbol.
test_dns_zones_are_exported_byte_for_byte() {
  nueva_prueba anz
  local d="$BANCO_TMP/anz"
  local raiz="$d/arbol"
  sembrar_arbol "$raiz"

  local registro="$d/registro.txt"
  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$registro")"

  local antes
  antes="$(suma_del_arbol "$raiz")"

  correr_analizador "$raiz" "$PAQUETE" "$ruta_path" "$d/stdout.txt" "$d/stderr.txt"
  afirmar_codigo 0 "$?" "Z1: el analizador termina bien con zonas que exportar"

  local sal
  sal="$(dir_de_salida "$raiz")"
  local zonas="$sal/zonas/cuenta1"

  # --- Z1: la copia, byte a byte ---
  afirmar_existe "$zonas/example.org.conf" "Z1: la zona se exportó"
  afirmar_intacto "$zonas/example.org.conf" \
    "$raiz/hestia/data/users/cuenta1/dns/example.org.conf" \
    "Z1: la zona exportada es byte a byte la del origen"
  afirmar_intacto "$zonas/firmada.example.org.conf" \
    "$raiz/hestia/data/users/cuenta1/dns/firmada.example.org.conf" \
    "Z1: la segunda zona también"

  afirmar_igual "$(stat -c '%a' "$sal/zonas" 2>/dev/null)" "700" \
    "Z1: zonas/ es 700"
  afirmar_igual "$(stat -c '%a' "$zonas" 2>/dev/null)" "700" \
    "Z1: zonas/<cuenta>/ es 700"
  afirmar_igual "$(stat -c '%a' "$zonas/example.org.conf" 2>/dev/null)" "600" \
    "Z1: la zona exportada es 600"

  # --- Z2: el origen no se tocó ---
  # El directorio de salida vive dentro del árbol falso (SALIDA_BASE), así que
  # se aparta antes de volver a sumar: lo que se mide es el servidor, no lo
  # que el analizador escribió en su propia salida.
  local despues
  despues="$(mv "$sal" "$d/salida-apartada" && suma_del_arbol "$raiz")"
  afirmar_igual "$despues" "$antes" \
    "Z2: el árbol de origen sigue con la misma suma sha256"
  sal="$d/salida-apartada"
  zonas="$sal/zonas/cuenta1"
  afirmar_igual "$(wc -c < "$registro" | tr -d ' ')" "0" \
    "Z2: exportar zonas no invocó ninguna orden prohibida"

  # --- Z3: la zona ilegible ---
  afirmar_igual "$(test -e "$zonas/ilegible.example.org.conf" && echo si || echo no)" "no" \
    "Z3: de una zona ilegible NO se escribe un archivo a medias"
  afirmar_contiene "$sal/informe.txt" "ilegible.example.org: no disponible registros" \
    "Z3: el informe dice que la zona ilegible no está disponible"
  afirmar_contiene "$sal/informe.txt" "no disponible \(la zona no se puede leer\)" \
    "Z3: y por qué no se exportó"

  # --- Z4: el informe dice dónde quedó cada zona y cómo usarlas ---
  afirmar_contiene "$sal/informe.txt" "exportada a zonas/cuenta1/example.org.conf" \
    "Z4: el informe nombra la ruta de cada zona exportada"
  afirmar_contiene "$sal/informe.txt" "recrear-zonas.sh --cuenta" \
    "Z4: y cómo recrearlas en el destino"
  afirmar_contiene "$sal/informe.txt" "SIN --aplicar" \
    "Z4: diciendo que primero se corre sin aplicar nada"
  afirmar_contiene "$d/stdout.txt" "Zonas DNS          : .*/zonas/<cuenta>/" \
    "Z4: y el resumen en pantalla señala el directorio"

  # --- Z5: DNSSEC ---
  afirmar_contiene "$sal/informe.txt" \
    "la zona firmada.example.org usa DNSSEC en el origen" \
    "Z5: DNSSEC='yes' produce su aviso"
  afirmar_contiene "$sal/informe.txt" "DS del registrador dejará de coincidir" \
    "Z5: y el aviso dice qué se rompe"
  afirmar_no_contiene "$sal/informe.txt" "la zona example.org usa DNSSEC" \
    "Z5: DNSSEC='no' no produce aviso"
  afirmar_no_contiene "$sal/informe.txt" "la zona ilegible.example.org usa DNSSEC" \
    "Z5: ni una zona sin DNSSEC activo"
}

test_the_package_builds_and_embeds_the_reader
test_dns_zones_are_exported_byte_for_byte
test_full_run_is_read_only_quiet_and_secret_free
test_application_types_are_detected_with_evidence
test_codeigniter_environment_and_guards
test_php_version_is_explicit_or_refused
test_mail_messages_are_counted_exactly
test_proposals_are_rejected_as_generated_and_accepted_once_reviewed
test_empty_destination_ip_is_rejected_even_without_a_php_sentinel
test_warnings_for_cron_orphan_database_and_unknown_user
test_rapido_skips_measuring_and_says_so
test_missing_hestia_dir_creates_nothing
test_odd_values_do_not_break_the_report
test_the_seal_records_the_commit_and_flags_uncommitted_changes
test_unpackaged_run_says_so

fin_de_suite
