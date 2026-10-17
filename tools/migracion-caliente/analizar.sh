#!/bin/bash

# ============================================================
# ANALIZADOR DE UN HESTIACP — SOLO LECTURA
# ============================================================
#
# Inventaría todo lo que se puede migrar de un servidor
# HestiaCP y PROPONE un archivo de migración por cuenta, con
# sus avisos. Propone; la persona decide.
#
# Se ejecuta en el servidor de ORIGEN, como root:
#
#   bash analizar.paquete.sh [--rapido] [--usuario <cuenta>]
#
#   --rapido    no cuenta mensajes ni mide tamaños con du. En
#               un servidor con mucho correo, medir puede
#               tardar mucho. El informe dice que se usó.
#   --usuario   solo esa cuenta. Repetible.
#
#
# ============================================================
#
# LAS TRES REGLAS QUE NO SE NEGOCIAN
#
#   1. NO ESCRIBE NADA en el servidor salvo su propio
#      directorio de salida, que crea con mktemp.
#
#   2. NO EJECUTA NINGUNA ORDEN DEL PANEL (v-*) ni habla con
#      la red ni con ninguna base de datos. Las listas del
#      panel escriben en su error.log cuando se les pregunta
#      por algo que no existe, así que no se usan: los .conf
#      se leen como TEXTO.
#
#      Leer como texto, nunca con «source»: hacer source de un
#      archivo ajeno es ejecutarlo, y aquí se corre como root.
#
#   3. NO IMPRIME NINGÚN SECRETO. Solo se emiten las claves
#      que este archivo nombra una por una (lista blanca). Las
#      contraseñas y los hashes no se leen, no se copian y no
#      se escriben: ni FTP_MD5, ni STATS_CRYPT, ni RKEY, ni
#      TWOFA, ni los passwd del correo, ni ninguna contraseña
#      de ninguna aplicación.
#
# ============================================================
#
# Lo que este analizador NO puede saber desde los archivos se
# escribe «no disponible» o «no se pudo determinar», nunca un
# cero ni un vacío: un dato que falta y un dato que vale cero
# no se escriben igual.
#
# ============================================================


# ------------------------------------------------------------
# Rutas del sistema. Son variables para que las pruebas puedan
# apuntar el analizador a un árbol falso; en un servidor se
# quedan con su valor real.
# ------------------------------------------------------------

HESTIA_DIR="${HESTIA_DIR:-/usr/local/hestia}";
HOME_DIR="${HOME_DIR:-/home}";
ETC_DIR="${ETC_DIR:-/etc}";
SPOOL_CRON="${SPOOL_CRON:-/var/spool/cron/crontabs}";
MYSQL_DATADIR="${MYSQL_DATADIR:-/var/lib/mysql}";
SALIDA_BASE="${SALIDA_BASE:-/tmp}";


# Profundidad de búsqueda de las señas de cada aplicación.
#
# 3 niveles bajo la carpeta del dominio alcanza public_html/,
# public_html/<subcarpeta>/ y un nivel más (donde viven
# system/core/ y sites/default/ de los marcos que se buscan).
# Más profundidad, en un servidor con muchos sitios y mucho
# contenido subido, multiplica el tiempo sin encontrar nada
# nuevo.
PROF_MAX=3;


RAPIDO="no";
USUARIOS_PEDIDOS=();

AVISOS=();


# ============================================================
# === ARGUMENTOS ===
# ============================================================

while [ "$#" -gt 0 ]
do

  case "$1" in

    --rapido)
      RAPIDO="si";
      shift;
      ;;

    --usuario)
      if [ -z "${2:-}" ]; then
        echo "ERROR: --usuario necesita un nombre de cuenta." >&2;
        exit 2;
      fi;
      USUARIOS_PEDIDOS+=("$2");
      shift 2;
      ;;

    -h|--help)
      echo "Uso: bash analizar.paquete.sh [--rapido] [--usuario <cuenta>]";
      exit 0;
      ;;

    *)
      echo "ERROR: argumento desconocido: $1" >&2;
      echo "Uso: bash analizar.paquete.sh [--rapido] [--usuario <cuenta>]" >&2;
      exit 2;
      ;;

  esac;

done


# ============================================================
# === UTILIDADES DE LECTURA ===
# ============================================================

aviso() {
  AVISOS+=("$1");
}


# Extrae el valor de CLAVE='valor' de un texto, SIN ejecutarlo.
#
# HestiaCP no escapa las comillas de los valores (50-hestiacp.md),
# así que un valor que contenga una comilla simple sale
# recortado. Recortado, no roto: preferimos un dato a medias y
# visible a un analizador que aborta.
conf_valor() {

  local texto="$1";
  local clave="$2";

  printf '%s\n' "$texto" \
    | grep -oE "(^|[[:space:]])${clave}='[^']*'" \
    | head -1 \
    | sed -e "s/^[[:space:]]*${clave}='//" -e "s/'$//";

}


# "no disponible" si el valor está vacío.
o_no_disponible() {
  if [ -z "$1" ]; then
    printf 'no disponible';
  else
    printf '%s' "$1";
  fi;
}


# Tamaño en bytes de una ruta, o "no disponible".
#
# Con --rapido no se mide: du recorre el árbol entero.
medir() {

  local ruta="$1";

  if [ "$RAPIDO" = "si" ]; then
    printf 'no medido (--rapido)';
    return 0;
  fi;

  if [ ! -e "$ruta" ]; then
    printf 'no disponible';
    return 0;
  fi;

  local bytes;

  bytes="$(du -sb "$ruta" 2>/dev/null | awk '{print $1}')";

  if [ -z "$bytes" ]; then
    printf 'no disponible (sin permiso)';
    return 0;
  fi;

  printf '%s bytes' "$bytes";

}


# Primera línea que casa un patrón, sin leer el archivo entero.
# Solo se usa con patrones que NO pueden traer un secreto.
linea_que_casa() {

  local archivo="$1";
  local patron="$2";

  if [ ! -r "$archivo" ]; then
    return 1;
  fi;

  grep -m1 -E "$patron" "$archivo" 2>/dev/null;

}


# ============================================================
# === EL INTÉRPRETE DE PHP ===
# ============================================================
#
# Hace falta para saber qué base usa cada aplicación, leyendo
# su archivo de configuración con el MISMO programa que usa la
# migración. Sin PHP, ese dato queda «no disponible»: no se
# adivina.
#
# La ruta del PHP que trae HestiaCP está SIN VERIFICAR; si no
# existe, se dice y se sigue.
# ============================================================

PHP_BIN="";

if command -v php >/dev/null 2>&1; then
  PHP_BIN="$(command -v php)";
elif [ -x "$HESTIA_DIR/php/bin/php" ]; then
  PHP_BIN="$HESTIA_DIR/php/bin/php";
fi;


# ============================================================
# === COMPROBACIONES PREVIAS ===
# ============================================================

USERS_DIR="$HESTIA_DIR/data/users";

if [ ! -d "$USERS_DIR" ]; then

  echo "ERROR: no existe $USERS_DIR." >&2;
  echo "¿Es este un servidor HestiaCP? HESTIA_DIR=$HESTIA_DIR" >&2;
  echo "No se ha creado ningún archivo." >&2;

  exit 3;

fi;

if [ ! -r "$USERS_DIR" ]; then

  echo "ERROR: no se puede leer $USERS_DIR (hace falta root)." >&2;
  echo "No se ha creado ningún archivo." >&2;

  exit 3;

fi;


ES_ROOT="si";

if [ "$(id -u)" != "0" ]; then
  ES_ROOT="no";
fi;


# ============================================================
# === DIRECTORIO DE SALIDA ===
# ============================================================
#
# Lo único que este analizador escribe en el servidor.
# ============================================================

SALIDA="$(mktemp -d "$SALIDA_BASE/analisis-hestia.XXXXXX")";

if [ -z "$SALIDA" ] || [ ! -d "$SALIDA" ]; then
  echo "ERROR: no se pudo crear el directorio de salida en $SALIDA_BASE." >&2;
  exit 3;
fi;

chmod 700 "$SALIDA";

INFORME="$SALIDA/informe.txt";

: > "$INFORME";
chmod 600 "$INFORME";


# El helper de lectura, si el paquete lo trae embebido o si
# BASE_LEER_CONFIG.sh está al lado (que es el caso cuando se
# ejecuta desde el repositorio, en las pruebas).
HELPER_PHP="";

preparar_helper() {

  if [ -z "$PHP_BIN" ]; then
    return 1;
  fi;

  HELPER_PHP="$SALIDA/.leer_config.php";

  if [ -n "${ANALIZADOR_HELPER_EMBEBIDO:-}" ]; then

    printf '%s\n' "$ANALIZADOR_HELPER_EMBEBIDO" > "$HELPER_PHP";

  else

    local propio;
    propio="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/BASE_LEER_CONFIG.sh";

    if [ ! -r "$propio" ]; then
      HELPER_PHP="";
      return 1;
    fi;

    awk '
      $0 == "cat > \"$LEER_PHP\" <<'"'"'PHP'"'"'" { dentro = 1; next }
      dentro && $0 == "PHP" { exit }
      dentro { print }
    ' "$propio" > "$HELPER_PHP";

  fi;

  if [ ! -s "$HELPER_PHP" ]; then
    HELPER_PHP="";
    return 1;
  fi;

  chmod 600 "$HELPER_PHP";

  return 0;

}

preparar_helper || true;


# Lee de un archivo de configuración de aplicación el nombre de
# la base, el usuario y el host. NUNCA la contraseña: el helper
# no la lee (lo dice su propia cabecera).
#
# Devuelve tres líneas DB=, USER=, HOST=, o nada.
leer_base_de_app() {

  local archivo="$1";
  local tipo="$2";

  if [ -z "$HELPER_PHP" ] || [ ! -r "$archivo" ]; then
    return 1;
  fi;

  "$PHP_BIN" "$HELPER_PHP" "$archivo" "$tipo" 2>/dev/null;

}


# ============================================================
# === CONTRASEÑAS NUEVAS PARA EL DESTINO ===
# ============================================================
#
# 24 caracteres. El juego se queda dentro de lo que la propia
# herramienta considera seguro sin citar (el preg_match de
# escapeValue en BASE_CONFIGURAR_DB.sh): letras, cifras y
# guion. Así la contraseña se escribe literal en el archivo de
# configuración de la aplicación, sin escapes.
#
# De /dev/urandom, sin openssl: no se da por hecho que esté.
# ============================================================

clave_nueva() {

  local n;

  n="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)";

  if [ "${#n}" -ne 24 ]; then
    printf 'REVISAR_CLAVE_NO_GENERADA';
    return 1;
  fi;

  printf '%s' "$n";

}


# ============================================================
# === DATOS DEL SERVIDOR ===
# ============================================================

HESTIA_VERSION="$(
  linea_que_casa "$HESTIA_DIR/conf/hestia.conf" "^VERSION=" \
    | sed -e "s/^VERSION=//" -e "s/^'//" -e "s/'$//"
)";

SISTEMA="$(
  linea_que_casa "$ETC_DIR/os-release" "^PRETTY_NAME=" \
    | sed -e 's/^PRETTY_NAME=//' -e 's/^"//' -e 's/"$//'
)";

PHP_INSTALADOS="";

if [ -d "$ETC_DIR/php" ]; then
  PHP_INSTALADOS="$(
    find "$ETC_DIR/php" -maxdepth 2 -type d -name fpm 2>/dev/null \
      | sed -e "s|^$ETC_DIR/php/||" -e 's|/fpm$||' \
      | sort -V | tr '\n' ' '
  )";
fi;

ESPACIO_LIBRE="$(df -h "$HOME_DIR" 2>/dev/null | awk 'NR==2 {print $4 " libres de " $2}')";


# Las IPs del servidor, con su dueño.
IPS_LISTA=();

if [ -d "$HESTIA_DIR/data/ips" ]; then

  for ip_archivo in "$HESTIA_DIR/data/ips"/*
  do

    [ -r "$ip_archivo" ] || continue;

    ip_nombre="$(basename "$ip_archivo")";
    ip_texto="$(cat "$ip_archivo" 2>/dev/null)";

    IPS_LISTA+=(
      "$ip_nombre|$(conf_valor "$ip_texto" OWNER)|$(conf_valor "$ip_texto" NAT)"
    );

  done;

fi;


# ============================================================
# === DETECCIÓN DEL TIPO DE APLICACIÓN ===
# ============================================================
#
# SOLO CON EVIDENCIA: cada detección guarda la ruta que la
# demuestra. Sin evidencia, «no se pudo determinar». Con dos,
# «ambiguo». En los dos casos el tipo propuesto es "ninguno",
# que no reescribe nada.
#
# Un sitio con solo index.html y robots.txt NO es piecesphp:
# dar por hecho el tipo por defecto fue uno de los problemas de
# la migración del 2026-10-02.
# ============================================================

# Devuelve: tipo|evidencia|ruta_db_relativa|notas
detectar_tipo() {

  local dir_dominio="$1";
  local raiz="$2";

  local encontrados=();
  local evidencias=();
  local ruta_db="";
  local notas="";

  local hallazgo;

  # --- WordPress ---
  hallazgo="$(find "$raiz" -maxdepth "$PROF_MAX" -name wp-config.php -type f 2>/dev/null | head -1)";
  if [ -n "$hallazgo" ]; then
    encontrados+=("wordpress");
    evidencias+=("$hallazgo");
  fi;

  # --- Joomla: configuration.php CON la clase. El nombre solo
  #     no basta: cualquier proyecto puede tener uno.
  local candidato;
  for candidato in $(find "$raiz" -maxdepth "$PROF_MAX" -name configuration.php -type f 2>/dev/null)
  do
    if grep -lq "class JConfig" "$candidato" 2>/dev/null; then
      encontrados+=("joomla");
      evidencias+=("$candidato");
      break;
    fi;
  done;

  # --- CodeIgniter: la versión se lee de UNA sola línea de
  #     system/core/CodeIgniter.php, nunca el archivo entero.
  local ci_core;
  ci_core="$(find "$raiz" -maxdepth "$PROF_MAX" -path '*/system/core/CodeIgniter.php' -type f 2>/dev/null | head -1)";

  if [ -n "$ci_core" ]; then

    local ci_version;
    ci_version="$(
      linea_que_casa "$ci_core" "CI_VERSION" \
        | sed -nE "s/.*CI_VERSION['\"]?[[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" \
        | head -1
    )";

    local ci_base;
    ci_base="$(dirname "$(dirname "$(dirname "$ci_core")")")";

    case "$ci_version" in

      3.*)
        if [ -f "$ci_base/application/config/database.php" ]; then
          encontrados+=("codeigniter3");
          evidencias+=("$ci_core (CI_VERSION $ci_version)");
          ruta_db="${ci_base#$dir_dominio/}/application/config/database.php";
        else
          notas="CodeIgniter $ci_version sin application/config/database.php";
        fi;
        ;;

      "")
        notas="hay system/core/CodeIgniter.php pero no se pudo leer CI_VERSION";
        ;;

      *)
        notas="CodeIgniter $ci_version, que NO es 3.x: la herramienta no sabe reconfigurarlo";
        ;;

    esac;

  fi;

  # --- Laravel ---
  hallazgo="$(find "$raiz" -maxdepth "$PROF_MAX" -name artisan -type f 2>/dev/null | head -1)";
  if [ -n "$hallazgo" ] && [ -f "$(dirname "$hallazgo")/.env" ]; then
    encontrados+=("laravel");
    evidencias+=("$hallazgo");
  fi;

  # --- Drupal: settings.php y core/ ---
  hallazgo="$(find "$raiz" -maxdepth "$PROF_MAX" -path '*/sites/default/settings.php' -type f 2>/dev/null | head -1)";
  if [ -n "$hallazgo" ]; then
    local dru_base;
    dru_base="$(dirname "$(dirname "$(dirname "$hallazgo")")")";
    if [ -d "$dru_base/core" ]; then
      encontrados+=("drupal");
      evidencias+=("$hallazgo");
    fi;
  fi;

  # --- PrestaShop, por las rutas que usa BASE_CONFIG.sh ---
  hallazgo="$(find "$raiz" -maxdepth "$PROF_MAX" -path '*/app/config/parameters.php' -type f 2>/dev/null | head -1)";
  if [ -n "$hallazgo" ]; then
    encontrados+=("prestashop");
    evidencias+=("$hallazgo");
  fi;

  hallazgo="$(find "$raiz" -maxdepth "$PROF_MAX" -path '*/config/settings.inc.php' -type f 2>/dev/null | head -1)";
  if [ -n "$hallazgo" ]; then
    encontrados+=("prestashop16");
    evidencias+=("$hallazgo");
  fi;


  case "${#encontrados[@]}" in

    0)
      printf 'ninguno|no se pudo determinar||%s' "$notas";
      ;;

    1)
      printf '%s|%s|%s|%s' \
        "${encontrados[0]}" "${evidencias[0]}" "$ruta_db" "$notas";
      ;;

    *)
      printf 'ninguno|ambiguo: %s||%s' \
        "$(printf '%s ' "${encontrados[@]}")" "$notas";
      ;;

  esac;

}


# El entorno activo de un CodeIgniter y su ruta_db definitiva.
#
# Si el proyecto tiene application/config/<ENTORNO>/database.php
# para el entorno activo, ESE manda sobre el general: apuntar al
# general reescribiría un archivo que la aplicación no usa, y la
# migración parecería correcta.
#
# Devuelve: ruta_db|aviso
entorno_codeigniter() {

  local dir_dominio="$1";
  local ruta_db="$2";

  # El directorio application/config, que es donde cuelgan los
  # directorios de entorno. ruta_db ya apunta al database.php
  # general, así que su directorio es exactamente ese.
  local app_dir;
  app_dir="$dir_dominio/$(dirname "$ruta_db")";

  local index;
  index="$(find "$dir_dominio" -maxdepth "$PROF_MAX" -name index.php -type f 2>/dev/null | head -1)";

  local entorno="";

  if [ -n "$index" ]; then
    entorno="$(
      linea_que_casa "$index" "define\(['\"]ENVIRONMENT['\"]" \
        | sed -nE "s/.*ENVIRONMENT['\"][[:space:]]*,[[:space:]]*['\"]?([A-Za-z0-9_-]+).*/\1/p" \
        | head -1
    )";
  fi;

  local dirs_entorno;
  dirs_entorno="$(find "$app_dir" -mindepth 2 -maxdepth 2 -name database.php -type f 2>/dev/null | head -5)";

  if [ -z "$dirs_entorno" ]; then
    printf '%s|' "$ruta_db";
    return 0;
  fi;

  if [ -n "$entorno" ] && [ -f "$app_dir/$entorno/database.php" ]; then

    printf '%s|%s' \
      "${app_dir#$dir_dominio/}/$entorno/database.php" \
      "ENVIRONMENT es '$entorno' y existe application/config/$entorno/database.php: ESE es el que manda, y es el que se reescribe";

    return 0;

  fi;

  printf '%s|%s' \
    "$ruta_db" \
    "hay directorios de entorno bajo application/config/ y no se pudo saber cuál está activo: REVISAR A MANO cuál database.php usa";

}


# Avisos de un database.php de CodeIgniter 3: grupo activo y
# claves repetidas. La herramienta se negará en los dos casos;
# mejor saberlo ahora que el lunes.
#
# NO se imprime ningún valor del archivo: solo el nombre del
# grupo activo y el recuento de claves.
avisos_codeigniter() {

  local archivo="$1";

  [ -r "$archivo" ] || return 0;

  local grupo;
  grupo="$(
    linea_que_casa "$archivo" '\$active_group' \
      | sed -nE "s/.*\\\$active_group[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\1/p" \
      | head -1
  )";

  if [ -n "$grupo" ] && [ "$grupo" != "default" ]; then
    printf 'active_group es %s, no default: la herramienta se negará\n' "$grupo";
  fi;

  local clave n;

  for clave in database username password hostname
  do

    n="$(grep -cE "['\"]${clave}['\"][[:space:]]*(=>|\])" "$archivo" 2>/dev/null)";

    if [ -n "$n" ] && [ "$n" -gt 1 ]; then
      printf 'la clave %s aparece %s veces: la herramienta se negará\n' "$clave" "$n";
    fi;

  done;

}


# ============================================================
# === QUÉ CUENTAS SE ANALIZAN ===
# ============================================================
#
# Como hace el panel: las que tienen user.conf Y un '@' en su
# GECOS de passwd. Las que cumplen solo una de las dos cosas se
# listan en AVISOS: o sobra un directorio, o falta un usuario
# del sistema.
# ============================================================

CUENTAS=();

for conf_usuario in "$USERS_DIR"/*/user.conf
do

  [ -r "$conf_usuario" ] || continue;

  cuenta="$(basename "$(dirname "$conf_usuario")")";

  if [ "${#USUARIOS_PEDIDOS[@]}" -gt 0 ]; then

    pedida="no";

    for u in "${USUARIOS_PEDIDOS[@]}"
    do
      [ "$u" = "$cuenta" ] && pedida="si";
    done;

    [ "$pedida" = "si" ] || continue;

  fi;

  linea_passwd="$(grep -E "^${cuenta}:" "$ETC_DIR/passwd" 2>/dev/null | head -1)";

  if [ -z "$linea_passwd" ]; then

    aviso "$cuenta: tiene user.conf pero NO existe como usuario del sistema en passwd. REVISAR A MANO.";

  else

    case "$(printf '%s' "$linea_passwd" | cut -d: -f5)" in
      *@*)
        CUENTAS+=("$cuenta");
        ;;
      *)
        aviso "$cuenta: tiene user.conf pero su GECOS en passwd no lleva '@'. El panel no la trata como cuenta suya: REVISAR A MANO antes de migrarla.";
        ;;
    esac;

  fi;

done


if [ "${#CUENTAS[@]}" -eq 0 ]; then
  aviso "No se encontró ninguna cuenta que el panel reconozca. Revisa HESTIA_DIR y los nombres pasados con --usuario.";
fi


# ============================================================
# === AVISOS DEL SERVIDOR ENTERO ===
# ============================================================

if [ "$ES_ROOT" = "no" ]; then
  aviso "El análisis NO se ejecutó como root: lo que no se pudo leer aparece como «no disponible (sin permiso)». Vuelve a ejecutarlo como root para un inventario completo.";
fi

if [ -z "$PHP_BIN" ]; then
  aviso "No se encontró ningún intérprete de PHP (ni 'php' en el PATH ni $HESTIA_DIR/php/bin/php): la base que usa cada aplicación queda «no disponible», y los bd de las propuestas hay que rellenarlos a mano.";
elif [ -z "$HELPER_PHP" ]; then
  aviso "Hay PHP pero no se pudo preparar el lector de configuraciones: la base que usa cada aplicación queda «no disponible».";
fi

if [ "$RAPIDO" = "si" ]; then
  aviso "Se usó --rapido: NO se han medido tamaños ni contado mensajes de correo. Donde debería haber un tamaño dice «no medido (--rapido)».";
fi

if [ ! -d "$MYSQL_DATADIR" ]; then
  aviso "No existe $MYSQL_DATADIR: el tamaño de las bases de datos queda «no disponible». Esa ruta está SIN VERIFICAR para este servidor.";
fi

if [ ! -d "$SPOOL_CRON" ]; then
  aviso "No existe $SPOOL_CRON: no se puede saber si hay trabajos de cron puestos a mano, fuera del panel. Esa ruta está SIN VERIFICAR para este servidor.";
fi


# ============================================================
# === EL CUERPO DEL INFORME, CUENTA POR CUENTA ===
# ============================================================

CUERPO="$SALIDA/.cuerpo.txt";
: > "$CUERPO";
chmod 600 "$CUERPO";

seccion=1;

for cuenta in "${CUENTAS[@]}"
do

  seccion=$((seccion + 1));

  echo "  analizando $cuenta…" >&2;

  dir_cuenta="$USERS_DIR/$cuenta";
  home_cuenta="$HOME_DIR/$cuenta";

  texto_usuario="$(cat "$dir_cuenta/user.conf" 2>/dev/null)";

  avisos_cuenta=();
  dominios_propuesta="";
  correo_propuesta="";
  bases_propuesta="";
  bases_usadas=" ";

  {
    echo "============================================================";
    echo "$seccion. CUENTA: $cuenta";
    echo "============================================================";
    echo;
    echo "  PACKAGE   : $(o_no_disponible "$(conf_valor "$texto_usuario" PACKAGE)")";
    echo "  SHELL     : $(o_no_disponible "$(conf_valor "$texto_usuario" SHELL)")";
    echo "  SUSPENDED : $(o_no_disponible "$(conf_valor "$texto_usuario" SUSPENDED)")";
    echo "  home      : $(medir "$home_cuenta")";
    echo "  web/      : $(medir "$home_cuenta/web")";
    echo "  mail/     : $(medir "$home_cuenta/mail")";
    echo;
  } >> "$CUERPO"


  # --- La IP de la cuenta ---
  ip_cuenta="";

  for fila in "${IPS_LISTA[@]}"
  do

    IFS='|' read -r f_ip f_owner f_nat <<< "$fila";

    if [ "$f_owner" = "$cuenta" ]; then

      if [ -n "$ip_cuenta" ]; then
        avisos_cuenta+=("la cuenta tiene más de una IP asignada; se propuso $ip_cuenta. Comprueba cuál corresponde");
      else
        ip_cuenta="$f_ip";
        if [ -n "$f_nat" ]; then
          avisos_cuenta+=("la IP $f_ip tiene NAT ($f_nat): la pública no es la del panel. Comprueba cuál va en IP_ORIGEN");
        fi;
      fi;

    fi;

  done;

  if [ -z "$ip_cuenta" ]; then

    if [ "${#IPS_LISTA[@]}" -gt 0 ]; then
      IFS='|' read -r ip_cuenta _ _ <<< "${IPS_LISTA[0]}";
      avisos_cuenta+=("ninguna IP de data/ips/ pertenece a esta cuenta: se propuso $ip_cuenta, la primera del servidor. REVISAR");
    else
      ip_cuenta="REVISAR_IP_ORIGEN";
      avisos_cuenta+=("no se pudo leer ninguna IP del servidor: IP_ORIGEN queda como centinela");
    fi;

  fi;


  # ========================================================
  # DOMINIOS WEB
  # ========================================================

  conf_web="$dir_cuenta/web.conf";

  {
    echo "  --- Dominios web ---";
    echo;
  } >> "$CUERPO"

  if [ ! -r "$conf_web" ]; then

    {
      echo "  no disponible (no hay web.conf legible)";
      echo;
    } >> "$CUERPO"

  else

    while IFS= read -r linea
    do

      dominio="$(conf_valor "$linea" DOMAIN)";
      [ -n "$dominio" ] || continue;

      d_alias="$(conf_valor "$linea" ALIAS)";
      d_ip="$(conf_valor "$linea" IP)";
      d_backend="$(conf_valor "$linea" BACKEND)";
      d_proxy="$(conf_valor "$linea" PROXY)";
      d_ssl="$(conf_valor "$linea" SSL)";
      d_ssl_force="$(conf_valor "$linea" SSL_FORCE)";
      d_le="$(conf_valor "$linea" LETSENCRYPT)";
      d_docroot="$(conf_valor "$linea" CUSTOM_DOCROOT)";
      d_susp="$(conf_valor "$linea" SUSPENDED)";

      # La versión de PHP sale del nombre de la plantilla
      # (50-hestiacp.md). "default" NO se traduce a una versión:
      # a qué equivale en un servidor concreto está SIN VERIFICAR,
      # y en la migración del 2026-10-02 fue 8.2 en el viejo y 8.5
      # en el nuevo. Antes que inventarla, se deja vacía y la
      # herramienta se niega.
      case "$d_backend" in

        *PHP-[0-9]_[0-9])
          d_php_version="$(printf '%s' "$d_backend" | sed -nE 's/^.*PHP-([0-9])_([0-9])$/\1.\2/p')";
          d_php_propuesto="$d_backend";
          ;;

        *)
          d_php_version="$(o_no_disponible "$d_backend"): versión real SIN VERIFICAR, comprobar en el panel";
          d_php_propuesto="";
          avisos_cuenta+=("$dominio: BACKEND es «$(o_no_disponible "$d_backend")», así que la versión real de PHP no se puede saber desde los archivos. La propuesta deja php VACÍO a propósito: la herramienta se niega a ejecutar hasta que se escriba");
          ;;

      esac;

      dir_dominio="$home_cuenta/web/$dominio";

      if [ -n "$d_docroot" ] && [ -d "$d_docroot" ]; then
        raiz_busqueda="$d_docroot";
      elif [ -d "$dir_dominio/public_html" ]; then
        raiz_busqueda="$dir_dominio/public_html";
      else
        raiz_busqueda="$dir_dominio";
      fi;

      IFS='|' read -r d_tipo d_evidencia d_ruta_db d_notas \
        <<< "$(detectar_tipo "$dir_dominio" "$raiz_busqueda")";

      d_aviso_entorno="";

      if [ "$d_tipo" = "codeigniter3" ] && [ -n "$d_ruta_db" ]; then

        IFS='|' read -r d_ruta_db d_aviso_entorno \
          <<< "$(entorno_codeigniter "$dir_dominio" "$d_ruta_db")";

        [ -n "$d_aviso_entorno" ] && avisos_cuenta+=("$dominio: $d_aviso_entorno");

        while IFS= read -r a
        do
          [ -n "$a" ] && avisos_cuenta+=("$dominio: $a");
        done <<< "$(avisos_codeigniter "$dir_dominio/$d_ruta_db")";

      fi;

      [ -n "$d_notas" ] && avisos_cuenta+=("$dominio: $d_notas");

      case "$d_evidencia" in

        "no se pudo determinar")
          avisos_cuenta+=("$dominio: no se pudo determinar qué aplicación es. La propuesta lleva tipo=\"ninguno\": la base se migra, pero NO se reescribe ninguna configuración");
          ;;

        ambiguo*)
          avisos_cuenta+=("$dominio: $d_evidencia. La propuesta lleva tipo=\"ninguno\": decidir a mano");
          ;;

      esac;

      # La base que la aplicación tiene escrita: nombre, usuario
      # y host. La contraseña no se lee (el helper no la lee).
      d_db="no disponible";
      d_db_user="no disponible";
      d_db_host="no disponible";

      archivo_db="";

      if [ "$d_tipo" != "ninguno" ]; then

        if [ -n "$d_ruta_db" ]; then
          archivo_db="$dir_dominio/$d_ruta_db";
        else
          case "$d_tipo" in
            wordpress)    archivo_db="$raiz_busqueda/wp-config.php";;
            joomla)       archivo_db="$raiz_busqueda/configuration.php";;
            laravel)      archivo_db="$raiz_busqueda/.env";;
            drupal)       archivo_db="$raiz_busqueda/sites/default/settings.php";;
            prestashop)   archivo_db="$raiz_busqueda/app/config/parameters.php";;
            prestashop16) archivo_db="$raiz_busqueda/config/settings.inc.php";;
          esac;
        fi;

        if [ -n "$archivo_db" ] && [ -r "$archivo_db" ]; then

          salida_helper="$(leer_base_de_app "$archivo_db" "$d_tipo" || true)";

          v="$(printf '%s\n' "$salida_helper" | sed -n 's/^DB=//p'   | head -1)";
          [ -n "$v" ] && d_db="$v";
          v="$(printf '%s\n' "$salida_helper" | sed -n 's/^USER=//p' | head -1)";
          [ -n "$v" ] && d_db_user="$v";
          v="$(printf '%s\n' "$salida_helper" | sed -n 's/^HOST=//p' | head -1)";
          [ -n "$v" ] && d_db_host="$v";

        fi;

      fi;

      [ "$d_db" != "no disponible" ] && bases_usadas="$bases_usadas$d_db ";

      {
        echo "  $dominio";
        echo "      alias          : $(o_no_disponible "$d_alias")";
        echo "      IP             : $(o_no_disponible "$d_ip")";
        echo "      PHP            : $d_php_version";
        echo "      proxy (PROXY)  : $(o_no_disponible "$d_proxy")";
        echo "      SSL            : $(o_no_disponible "$d_ssl") / forzado: $(o_no_disponible "$d_ssl_force") / Let's Encrypt: $(o_no_disponible "$d_le")";
        echo "      docroot propio : $(o_no_disponible "$d_docroot")";
        echo "      suspendido     : $(o_no_disponible "$d_susp")";
        echo "      tamaño         : $(medir "$dir_dominio")";
        echo "      aplicación     : $d_tipo";
        echo "      evidencia      : $(o_no_disponible "$d_evidencia")";
        echo "      ruta_db        : $(o_no_disponible "$d_ruta_db")";
        echo "      base que usa   : $d_db (usuario: $d_db_user, host: $d_db_host)";
        echo;
      } >> "$CUERPO"


      # --- El bloque de este dominio en la propuesta ---

      corto_bd="";

      if [ "$d_db" != "no disponible" ]; then
        corto_bd="$(printf '%s' "$d_db" | sed -e "s/^${cuenta}_//")";
      fi;

      {
        echo;
        echo "# ------------------------------------------------------------";
        echo "# $dominio";

        if [ "$d_tipo" != "ninguno" ]; then
          echo "# Aplicación detectada: $d_tipo";
          echo "# Evidencia: $d_evidencia";
        else
          echo "# REVISAR: tipo sin determinar ($d_evidencia). Va como \"ninguno\":";
          echo "# la base se migra, pero ninguna configuración se reescribe, así que";
          echo "# las credenciales nuevas se escriben A MANO tras la fase 1.";
        fi;

        [ -n "$d_aviso_entorno" ] && echo "# REVISAR: $d_aviso_entorno";

        echo "# ------------------------------------------------------------";

        if [ -z "$d_php_propuesto" ]; then
          echo "#";
          echo "# REVISAR: en el origen BACKEND era \"$(o_no_disponible "$d_backend")\". La versión real de PHP";
          echo "# no se puede saber leyendo los archivos del panel. Se deja VACÍA a";
          echo "# propósito: así la herramienta se niega a ejecutar y nombra este";
          echo "# dominio, en vez de levantarlo con una versión inventada.";
          echo "#";
        fi;

        echo "dominio \"$dominio\" \\";
        echo "  php=\"$d_php_propuesto\" \\";
        echo "  tipo=\"$d_tipo\" \\";

        [ -n "$d_ruta_db" ] && echo "  ruta_db=\"$d_ruta_db\" \\";

        if [ "$d_ssl" = "yes" ] || [ "$d_le" = "yes" ]; then
          echo "  ssl=\"true\" \\";
        else
          echo "  ssl=\"false\" \\";
        fi;

        # forzar_ssl siempre en false: forzar HTTPS no comprueba
        # que el certificado exista, y un dominio redirigido a un
        # HTTPS sin certificado deja de responder. Se fuerza a
        # mano, tras comprobar que está emitido.
        if [ -n "$corto_bd" ]; then

          echo "  forzar_ssl=\"false\" \\";
          echo "  bd=\"$corto_bd\" \\";
          echo "  bd_user=\"$corto_bd\" \\";

          if [ "$d_tipo" = "ninguno" ]; then
            echo "  bd_origen=\"$d_db\" \\";
          fi;

          echo "  bd_pass=\"$(clave_nueva)\";";

        else

          echo "  forzar_ssl=\"false\";";
          echo "# REVISAR: no se pudo saber qué base usa este sitio. Si tiene una,";
          echo "# añade bd, bd_user y bd_pass (y bd_origen con tipo=\"ninguno\").";

        fi;

      } >> "$SALIDA/.dominios-$cuenta.txt"

    done < "$conf_web"

  fi;


  # ========================================================
  # BASES DE DATOS
  # ========================================================
  #
  # Las que ninguna aplicación usa van a la propuesta como
  # bases sueltas: sin dominio no hay archivo del que deducir
  # su nombre viejo, así que llevan origen= obligatorio.
  # ========================================================

  conf_db="$dir_cuenta/db.conf";

  {
    echo "  --- Bases de datos ---";
    echo;
  } >> "$CUERPO"

  if [ ! -r "$conf_db" ]; then

    {
      echo "  no disponible (no hay db.conf legible)";
      echo;
    } >> "$CUERPO"

  else

    while IFS= read -r linea
    do

      b_db="$(conf_valor "$linea" DB)";
      [ -n "$b_db" ] || continue;

      b_user="$(conf_valor "$linea" DBUSER)";
      b_tipo="$(conf_valor "$linea" TYPE)";
      b_charset="$(conf_valor "$linea" CHARSET)";
      b_susp="$(conf_valor "$linea" SUSPENDED)";

      if [ -d "$MYSQL_DATADIR/$b_db" ]; then
        b_tam="$(medir "$MYSQL_DATADIR/$b_db")";
      else
        b_tam="no disponible";
      fi;

      case "$bases_usadas" in
        *" $b_db "*) b_usada="sí";;
        *)           b_usada="no";;
      esac;

      {
        echo "  $b_db";
        echo "      usuario        : $(o_no_disponible "$b_user")";
        echo "      motor / juego  : $(o_no_disponible "$b_tipo") / $(o_no_disponible "$b_charset")";
        echo "      suspendida     : $(o_no_disponible "$b_susp")";
        echo "      tamaño         : $b_tam";
        echo "      la usa un sitio: $b_usada";
        echo;
      } >> "$CUERPO"

      if [ "$b_usada" = "no" ]; then

        avisos_cuenta+=("la base $b_db no la usa ninguna aplicación detectada: va a la propuesta como base suelta. Comprueba si de verdad hace falta migrarla");

        corto_suelta="$(printf '%s' "$b_db" | sed -e "s/^${cuenta}_//")";

        {
          echo;
          echo "# REVISAR: ninguna aplicación detectada usa esta base.";
          echo "base_de_datos \"$corto_suelta\" \\";
          echo "  origen=\"$b_db\" \\";
          echo "  user=\"$corto_suelta\" \\";
          echo "  pass=\"$(clave_nueva)\";";
        } >> "$SALIDA/.bases-$cuenta.txt"

      fi;

    done < "$conf_db"

  fi;


  # ========================================================
  # CORREO
  # ========================================================

  conf_mail="$dir_cuenta/mail.conf";

  {
    echo "  --- Correo ---";
    echo;
  } >> "$CUERPO"

  if [ ! -r "$conf_mail" ]; then

    {
      echo "  no disponible (no hay mail.conf legible)";
      echo;
    } >> "$CUERPO"

  else

    dominios_mail_vistos=" ";

    while IFS= read -r linea
    do

      m_dom="$(conf_valor "$linea" DOMAIN)";
      [ -n "$m_dom" ] || continue;

      # Un mail.conf con el mismo dominio dos veces (archivo a
      # medio escribir, o una línea pegada a mano) saldría dos
      # veces en el informe, como si hubiera dos dominios.
      case "$dominios_mail_vistos" in
        *" $m_dom "*)
          aviso "$cuenta: el dominio de correo $m_dom aparece más de una vez en mail.conf. Se analizó una sola vez: REVISAR ese archivo a mano";
          continue;
          ;;
      esac;

      dominios_mail_vistos="$dominios_mail_vistos$m_dom ";

      # ¿Tiene también sitio web? Un dominio de correo sin web
      # se declara con web="false" y solo se migra su correo.
      tiene_web="no";

      if [ -r "$conf_web" ] && grep -qF "DOMAIN='$m_dom'" "$conf_web" 2>/dev/null; then
        tiene_web="sí";
      fi;

      {
        echo "  $m_dom (sitio web: $tiene_web)";
      } >> "$CUERPO"

      cuentas_mail="$dir_cuenta/mail/$m_dom.conf";

      if [ ! -r "$cuentas_mail" ]; then

        echo "      no disponible (no hay mail/$m_dom.conf legible)" >> "$CUERPO";

      else

        while IFS= read -r linea_c
        do

          c_cuenta="$(conf_valor "$linea_c" ACCOUNT)";

          if [ -z "$c_cuenta" ]; then
            # Algunas versiones no repiten ACCOUNT en la línea:
            # el nombre va al principio, antes del primer ':'.
            c_cuenta="$(printf '%s' "$linea_c" | sed -nE 's/^([A-Za-z0-9._-]+):.*/\1/p')";
          fi;

          [ -n "$c_cuenta" ] || continue;

          c_alias="$(conf_valor "$linea_c" ALIAS)";
          c_fwd="$(conf_valor "$linea_c" FWD)";
          c_quota="$(conf_valor "$linea_c" QUOTA)";

          buzon="$HOME_DIR/$cuenta/mail/$m_dom/$c_cuenta";

          if [ "$RAPIDO" = "si" ]; then
            c_mensajes="no contado (--rapido)";
            c_tam="no medido (--rapido)";
          elif [ -d "$buzon" ]; then
            # Maildir: un archivo por mensaje, bajo cur/ y new/,
            # también en las carpetas .Sent, .Trash…
            c_mensajes="$(
              find "$buzon" \( -path '*/cur/*' -o -path '*/new/*' \) -type f 2>/dev/null \
                | wc -l | tr -d ' '
            )";
            c_tam="$(medir "$buzon")";
          else
            c_mensajes="no disponible";
            c_tam="no disponible";
          fi;

          {
            echo "      $c_cuenta";
            echo "          alias    : $(o_no_disponible "$c_alias")";
            echo "          reenvío  : $(o_no_disponible "$c_fwd")";
            echo "          cuota    : $(o_no_disponible "$c_quota")";
            echo "          mensajes : $c_mensajes";
            echo "          tamaño   : $c_tam";
          } >> "$CUERPO"

        done < "$cuentas_mail"

      fi;

      echo >> "$CUERPO";

      if [ "$tiene_web" = "no" ]; then

        avisos_cuenta+=("$m_dom tiene correo pero NO sitio web: en la propuesta va con web=\"false\", que migra solo el correo");

        {
          echo;
          echo "# ------------------------------------------------------------";
          echo "# $m_dom: correo sin sitio web.";
          echo "# Con web=\"false\" no se crea dominio web, ni PHP, ni se copian";
          echo "# archivos, ni SSL: solo se migra el correo.";
          echo "# ------------------------------------------------------------";
          echo "dominio \"$m_dom\" \\";
          echo "  web=\"false\" \\";
          echo "  correo=\"true\";";
        } >> "$SALIDA/.correo-$cuenta.txt"

      fi;

    done < "$conf_mail"

  fi;


  # ========================================================
  # CRON
  # ========================================================

  conf_cron="$dir_cuenta/cron.conf";

  {
    echo "  --- Trabajos de cron ---";
    echo;
  } >> "$CUERPO"

  if [ ! -r "$conf_cron" ]; then

    {
      echo "  no disponible (no hay cron.conf legible)";
      echo;
    } >> "$CUERPO"

  else

    while IFS= read -r linea
    do

      k_cmd="$(conf_valor "$linea" CMD)";
      [ -n "$k_cmd" ] || continue;

      k_prog="$(conf_valor "$linea" MIN) $(conf_valor "$linea" HOUR) $(conf_valor "$linea" DAY) $(conf_valor "$linea" MONTH) $(conf_valor "$linea" WDAY)";
      k_susp="$(conf_valor "$linea" SUSPENDED)";

      {
        echo "  [$k_prog]  $k_cmd";
        echo "      suspendido     : $(o_no_disponible "$k_susp")";
      } >> "$CUERPO"

      # Un intérprete llamado por nombre corto depende del PATH
      # de cron, que en el servidor nuevo puede resolver a otra
      # versión —o a nada—. Es el punto 4 de las mejoras.
      for interprete in php python python3 node perl
      do
        case " $k_cmd " in
          *" $interprete "*)
            avisos_cuenta+=("el cron «$k_cmd» llama a «$interprete» por nombre corto, sin ruta: en el servidor nuevo puede resolver a otra versión o a nada. Poner la ruta absoluta");
            ;;
        esac;
      done;

      echo >> "$CUERPO";

    done < "$conf_cron"

  fi;

  # Trabajos puestos a mano con crontab -e: el panel no los
  # conoce y la migración no los llevaría. No se imprime su
  # contenido, solo cuántas líneas hay.
  if [ -r "$SPOOL_CRON/$cuenta" ]; then

    lineas_spool="$(grep -cvE '^[[:space:]]*(#|$)' "$SPOOL_CRON/$cuenta" 2>/dev/null)";

    if [ -n "$lineas_spool" ] && [ "$lineas_spool" -gt 0 ]; then
      avisos_cuenta+=("hay $lineas_spool línea(s) de cron en $SPOOL_CRON/$cuenta que el panel NO conoce (puestas con crontab -e). La migración no las lleva: revisarlas a mano");
    fi;

  fi;


  # ========================================================
  # DNS
  # ========================================================

  conf_dns="$dir_cuenta/dns.conf";

  {
    echo "  --- Zonas DNS ---";
    echo;
  } >> "$CUERPO"

  if [ ! -r "$conf_dns" ]; then

    {
      echo "  no disponible (no hay dns.conf legible)";
      echo;
    } >> "$CUERPO"

  else

    hay_zonas="no";

    while IFS= read -r linea
    do

      z_dom="$(conf_valor "$linea" DOMAIN)";
      [ -n "$z_dom" ] || continue;

      hay_zonas="si";

      if [ -r "$dir_cuenta/dns/$z_dom.conf" ]; then
        z_regs="$(grep -c "RECORD=" "$dir_cuenta/dns/$z_dom.conf" 2>/dev/null)";
      else
        z_regs="no disponible";
      fi;

      echo "  $z_dom: $z_regs registros" >> "$CUERPO";

    done < "$conf_dns"

    echo >> "$CUERPO";

    if [ "$hay_zonas" = "si" ]; then
      avisos_cuenta+=("esta cuenta tiene zonas DNS en este servidor. Si el servidor también SIRVE el DNS, apagarlo deja las zonas sin responder: comprueba quién es el DNS autoritativo antes del corte");
    fi;

  fi;


  # ========================================================
  # LA PROPUESTA DE ESTA CUENTA
  # ========================================================

  propuesta="$SALIDA/migracion-$cuenta.sh";

  {
    echo "#!/bin/bash";
    echo;
    echo "# ============================================================";
    echo "# PROPUESTA GENERADA POR EL ANALIZADOR — revisar antes de usar";
    echo "# ============================================================";
    echo "#";
    echo "# Generada el       : $(date '+%Y-%m-%d %H:%M:%S')";
    echo "# Cuenta            : $cuenta";
    echo "# HestiaCP de origen: $(o_no_disponible "$HESTIA_VERSION")";
    echo "#";
    echo "# Esto es una PROPUESTA, no una migración lista. Nada de aquí";
    echo "# se ha ejecutado contra ningún servidor: sale de leer los";
    echo "# archivos del panel. Cada línea que empieza por REVISAR pide";
    echo "# una decisión que el analizador no puede tomar.";
    echo "#";
    echo "# Las contraseñas bd_pass son NUEVAS y aleatorias, para las";
    echo "# bases del servidor de DESTINO. No son las del origen.";
    echo "#";

    if [ "${#avisos_cuenta[@]}" -gt 0 ]; then
      echo "# ------------------------------------------------------------";
      echo "# AVISOS DE ESTA CUENTA (${#avisos_cuenta[@]})";
      echo "# ------------------------------------------------------------";
      echo "#";
      for a in "${avisos_cuenta[@]}"
      do
        echo "#   - $a";
      done;
      echo "#";
    fi;

    echo "# ============================================================";
    echo;
    echo;
    echo "FASE=\"plan\";";
    echo "CONFIRMAR=\"true\";";
    echo;
    echo "USER_ORIGEN=\"$cuenta\";";
    echo "USER_DESTINO=\"$cuenta\";";
    echo;
    echo "IP_ORIGEN=\"$ip_cuenta\";";
    echo;
    echo "# REVISAR: el servidor de destino todavía no está aquí. Sin esta IP";
    echo "# la herramienta no arranca.";
    echo "IP_DESTINO=\"PENDIENTE_IP_DESTINO\";";
    echo;
    echo "SSH_ORIGEN=\"root\";";
    echo "SSH_DESTINO=\"root\";";
    echo;
    echo "CRONJOBS=\"preguntar\";";
    echo "CRONJOBS_USUARIOS=();";
    echo;
    echo;
    echo "# ============================================================";
    echo "# === DOMINIOS ===";
    echo "# ============================================================";
    echo "#";
    echo "# forzar_ssl va en \"false\" en todos: forzar HTTPS no comprueba";
    echo "# que el certificado exista, y un dominio redirigido a un HTTPS";
    echo "# sin certificado deja de responder. Se fuerza a mano, dominio";
    echo "# por dominio, tras comprobar que está emitido.";
    echo "#";
    echo "# php se declara SIEMPRE con la plantilla exacta: \"default\" no";
    echo "# es la misma versión en los dos servidores.";
    echo "# ============================================================";

    [ -f "$SALIDA/.dominios-$cuenta.txt" ] && cat "$SALIDA/.dominios-$cuenta.txt";

    if [ -f "$SALIDA/.correo-$cuenta.txt" ]; then
      echo;
      echo;
      echo "# ============================================================";
      echo "# === DOMINIOS DE SOLO CORREO ===";
      echo "# ============================================================";
      cat "$SALIDA/.correo-$cuenta.txt";
    fi;

    if [ -f "$SALIDA/.bases-$cuenta.txt" ]; then
      echo;
      echo;
      echo "# ============================================================";
      echo "# === BASES SUELTAS ===";
      echo "# ============================================================";
      echo "#";
      echo "# Bases que ninguna aplicación detectada usa. No se reescribe";
      echo "# ninguna configuración, así que origen= es obligatorio.";
      echo "# ============================================================";
      cat "$SALIDA/.bases-$cuenta.txt";
    fi;

  } > "$propuesta"

  chmod 600 "$propuesta";

  rm -f "$SALIDA/.dominios-$cuenta.txt" \
        "$SALIDA/.correo-$cuenta.txt" \
        "$SALIDA/.bases-$cuenta.txt";

  # Los avisos de la cuenta, al bloque global, con su nombre.
  for a in "${avisos_cuenta[@]}"
  do
    aviso "$cuenta / $a";
  done;

done


# ============================================================
# === MONTAR EL INFORME: AVISOS ARRIBA ===
# ============================================================

{
  echo "============================================================";
  echo "ANÁLISIS DE UN SERVIDOR HESTIACP";
  echo "============================================================";
  echo;
  echo "Fecha               : $(date '+%Y-%m-%d %H:%M:%S')";
  echo "Versión de HestiaCP : $(o_no_disponible "$HESTIA_VERSION")";
  echo "Sistema             : $(o_no_disponible "$SISTEMA")";
  echo "PHP instalados      : $(o_no_disponible "$PHP_INSTALADOS")";
  echo "Disco de $HOME_DIR  : $(o_no_disponible "$ESPACIO_LIBRE")";
  echo "Intérprete de PHP   : $(o_no_disponible "$PHP_BIN")";
  echo "Modo                : $([ "$RAPIDO" = "si" ] && echo "--rapido (sin medir ni contar)" || echo "completo")";
  echo;
  echo "Este análisis no ha escrito nada en el servidor fuera de su propio";
  echo "directorio de salida, no ha ejecutado ninguna orden del panel y no";
  echo "ha leído ninguna contraseña.";
  echo;
  echo;
  echo "============================================================";
  echo "1. AVISOS — lo que pide una decisión humana";
  echo "============================================================";
  echo;

  if [ "${#AVISOS[@]}" -eq 0 ]; then
    echo "  Ninguno.";
  else
    n=0;
    for a in "${AVISOS[@]}"
    do
      n=$((n + 1));
      echo "  $n. $a";
      echo;
    done;
  fi;

  echo;
  echo "============================================================";
  echo "SERVIDOR";
  echo "============================================================";
  echo;

  if [ "${#IPS_LISTA[@]}" -eq 0 ]; then
    echo "  IPs: no disponible";
  else
    echo "  IPs:";
    for fila in "${IPS_LISTA[@]}"
    do
      IFS='|' read -r f_ip f_owner f_nat <<< "$fila";
      echo "    $f_ip  dueño: $(o_no_disponible "$f_owner")  NAT: $(o_no_disponible "$f_nat")";
    done;
  fi;

  echo;
  echo "  Cuentas analizadas: ${#CUENTAS[@]}";
  echo;
  echo;

  cat "$CUERPO";

} >> "$INFORME"

rm -f "$CUERPO" "$HELPER_PHP";


# ============================================================
# === RESUMEN EN PANTALLA ===
# ============================================================

echo;
echo "Análisis terminado.";
echo "  Cuentas analizadas : ${#CUENTAS[@]}";
echo "  Avisos             : ${#AVISOS[@]}";
echo "  Informe            : $INFORME";
echo "  Propuestas         : $SALIDA/migracion-<cuenta>.sh";
echo;
echo "Los archivos migracion-*.sh llevan contraseñas NUEVAS para las bases";
echo "del destino. Cópialos a tu equipo y borra este directorio:";
echo "rm -r $SALIDA";
echo;

exit 0;
