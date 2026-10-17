#!/bin/bash

# ============================================================
# MIGRACIÓN GENERAL HESTIACP
# ============================================================
#
# ARCHIVO PRINCIPAL DE LA MIGRACIÓN.
#
# Es el único punto de entrada:
#
#   bash BASE_GENERAL.sh;
#
#
# ============================================================
#
# ARCHIVOS QUE CARGA
#
#   Todos los BASE_*.sh; ver docs/desarrollo.md.
#
# Todos reciben las variables definidas aquí y no deben
# ejecutarse de forma aislada.
#
#
# ============================================================
#
# LA MIGRACIÓN OCURRE EN DOS FASES
#
#   FASE 1  ──▶  apuntar DNS  ──▶  FASE 2
#
#   FASE 1 (antes de mover el DNS)
#
#     Crea dominios, bases de datos, PHP, aliases, DNS y mail,
#     copia archivos, importa las bases y reescribe
#     database.php.
#
#     Al terminar el sitio nuevo está completo, pero nadie lo
#     está visitando todavía.
#
#   FASE "verificar" (cuando se quiera)
#
#     Solo lee. Revisa que cada aplicación tenga escritas las
#     credenciales correctas y que conecten de verdad.
#
#   FASE 2 (después de mover el DNS)
#
#     Vuelve a sincronizar los archivos para arrastrar lo que
#     haya cambiado durante la propagación, emite el SSL y
#     fuerza HTTPS.
#
#   El SSL no cabe en la fase 1: Let's Encrypt valida contra
#   el dominio, y mientras el dominio resuelva al servidor
#   viejo la emisión no puede funcionar.
#
# ============================================================



# ============================================================
# === CARGAR LA CONFIGURACIÓN DE ESTA MIGRACIÓN ===
# ============================================================
#
# Los datos específicos NO viven en este archivo.
#
# Viven en un archivo de migración aparte, que se pasa como
# argumento:
#
#   bash BASE_GENERAL.sh migracion-cliente.sh;
#
# Si no se pasa ninguno, se usa MIGRACION.sh.
#
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";

CONFIG_SCRIPT="$SCRIPT_DIR/BASE_CONFIG.sh";
PRIV_SCRIPT="$SCRIPT_DIR/BASE_PRIVILEGIOS.sh";
MIGRAR_DB_SCRIPT="$SCRIPT_DIR/BASE_MIGRAR_DB.sh";
DB_SCRIPT="$SCRIPT_DIR/BASE_CONFIGURAR_DB.sh";
MAIL_SCRIPT="$SCRIPT_DIR/BASE_MIGRAR_MAIL.sh";
CRON_SCRIPT="$SCRIPT_DIR/BASE_MIGRAR_CRON.sh";
COMPROBAR_SCRIPT="$SCRIPT_DIR/BASE_COMPROBAR.sh";
VERIFICAR_SCRIPT="$SCRIPT_DIR/BASE_VERIFICAR.sh";
LEER_SCRIPT="$SCRIPT_DIR/BASE_LEER_CONFIG.sh";
PLAN_SCRIPT="$SCRIPT_DIR/BASE_PLAN.sh";

# ------------------------------------------------------------
# Los argumentos tal como llegaron, antes de cualquier shift,
# para poder relanzar este mismo archivo con sudo.
# ------------------------------------------------------------

ARGS_ORIGINALES=("$@");


MIGRACION="${1:-$SCRIPT_DIR/MIGRACION.sh}";


# ------------------------------------------------------------
# La fase se puede pasar como segundo argumento, y entonces
# manda sobre la que diga el archivo de migración.
#
# Así una misma migración se recorre entera sin editar nada:
#
#   bash BASE_GENERAL.sh migracion.sh plan
#   bash BASE_GENERAL.sh migracion.sh 1
#   bash BASE_GENERAL.sh migracion.sh verificar
#   bash BASE_GENERAL.sh migracion.sh 2
# ------------------------------------------------------------

FASE_ARGUMENTO="${2:-}";


# ------------------------------------------------------------
# Filtros opcionales, después de la fase:
#
#   bash BASE_GENERAL.sh migracion.sh 1 --dominio example.org
#   bash BASE_GENERAL.sh migracion.sh 1 --base legacy
#
# Se pueden repetir. Sirven para repetir lo que falló sin
# volver a pasar por todo lo demás.
# ------------------------------------------------------------

SOLO_DOMINIOS=();
SOLO_BASES=();

if [ "$#" -gt 2 ]; then

  shift 2;

  while [ "$#" -gt 0 ]
  do

    case "$1" in

      --dominio)
        SOLO_DOMINIOS+=("$2");
        shift 2;
        ;;

      --base)
        SOLO_BASES+=("$2");
        shift 2;
        ;;

      *)
        echo "ERROR: argumento desconocido: $1";
        echo;
        echo "Uso:";
        echo "  bash BASE_GENERAL.sh migracion.sh [fase] [--dominio X] [--base Y]";
        exit 1;
        ;;

    esac;

  done;

fi;


if [ ! -f "$CONFIG_SCRIPT" ]; then
  echo "ERROR: No existe $CONFIG_SCRIPT";
  exit 1;
fi;


# ------------------------------------------------------------
# Primero las funciones dominio() / predeterminados() / cfg(),
# porque el archivo de migración las usa.
# ------------------------------------------------------------

# shellcheck source=/dev/null
source "$CONFIG_SCRIPT";


if [ ! -f "$MIGRACION" ]; then

  echo;
  echo "ERROR: No existe el archivo de migración:";
  echo "$MIGRACION";
  echo;
  echo "Uso:";
  echo "  bash BASE_GENERAL.sh [archivo-de-migracion]";
  echo;

  exit 1;

fi;


# shellcheck source=/dev/null
source "$MIGRACION";


if [ -n "$FASE_ARGUMENTO" ]; then
  FASE="$FASE_ARGUMENTO";
fi;


if ! cfg_validar; then
  exit 1;
fi;


# ------------------------------------------------------------
# Aplicar los filtros, si los hay.
# ------------------------------------------------------------

if [ "${#SOLO_DOMINIOS[@]}" -gt 0 ] || [ "${#SOLO_BASES[@]}" -gt 0 ]; then

  cfg_filtrar SOLO_DOMINIOS SOLO_BASES || exit 1;

fi;


cfg_construir_dbs;


# ============================================================
# === VALIDACIONES INICIALES ===
# ============================================================

case "$FASE" in
  1|2|sincronizar|plan|verificar)
    ;;
  *)
    echo "ERROR: FASE debe ser 1, 2, sincronizar, plan o verificar.";
    echo;
    echo "Se puede pasar como argumento:";
    echo "  bash BASE_GENERAL.sh migracion.sh plan";
    exit 1;
    ;;
esac;


if [ -z "$USER_DESTINO" ]; then
  echo "ERROR: USER_DESTINO no está definido.";
  exit 1;
fi;


if [ -z "$USER_ORIGEN" ]; then
  echo "ERROR: USER_ORIGEN no está definido.";
  exit 1;
fi;


if [ -z "$IP_ORIGEN" ]; then
  echo "ERROR: IP_ORIGEN no está definido.";
  exit 1;
fi;


if [ -z "$IP_DESTINO" ]; then
  echo "ERROR: IP_DESTINO no está definido.";
  exit 1;
fi;


if [ -z "$SSH_ORIGEN" ]; then
  echo "ERROR: SSH_ORIGEN no está definido.";
  exit 1;
fi;


# ------------------------------------------------------------
# Origen y destino tienen que ser sitios distintos.
#
# Con la misma IP y el mismo usuario, el origen y el destino
# serían la MISMA carpeta y la MISMA base de datos.
#
# Entonces rsync --delete sincronizaría un directorio consigo
# mismo, y la migración de bases vaciaría la base justo antes
# de volcarla. Es la única forma de que esta herramienta
# destruya datos del origen, así que se comprueba.
# ------------------------------------------------------------

if [ "$IP_ORIGEN" = "$IP_DESTINO" ] && [ "$USER_ORIGEN" = "$USER_DESTINO" ]; then

  echo;
  echo "ERROR: el origen y el destino son el mismo sitio.";
  echo;
  echo "  IP      : $IP_ORIGEN";
  echo "  usuario : $USER_ORIGEN";
  echo;
  echo "Con la misma IP y el mismo usuario, el origen y el";
  echo "destino serían la misma carpeta y la misma base.";
  echo;
  echo "Revisar USER_ORIGEN, USER_DESTINO, IP_ORIGEN e IP_DESTINO.";
  echo;

  exit 1;

fi;


# Los dominios, sus características y DBS ya fueron validados
# por cfg_validar.


# ------------------------------------------------------------
# Si no somos root pero hay sudo, la migración entera se
# relanza con sudo.
#
# Todo lo que escribe en disco (la carpeta de la corrida, los
# volcados, las copias) va al home del usuario del panel, que
# otro usuario no puede escribir. Relanzar una vez es más
# simple que anteponer sudo a cada escritura.
#
# sudo pide la contraseña él mismo si hace falta. El agente
# SSH se conserva, y BASE_PRIVILEGIOS.sh usa las llaves de
# SUDO_USER.
# ------------------------------------------------------------

if [ "$(id -u)" -ne 0 ] &&
   [ "${PRIV_LOCAL:-auto}" != "none" ] &&
   command -v sudo >/dev/null 2>&1; then

  echo "Relanzando con sudo...";

  exec sudo --preserve-env=SSH_AUTH_SOCK \
    bash "$SCRIPT_DIR/BASE_GENERAL.sh" "${ARGS_ORIGINALES[@]}";

fi;


# ------------------------------------------------------------
# Herramientas que necesita cada fase en este servidor.
#
# Va después del relanzamiento, porque algunas (chpasswd)
# solo están en el PATH de root, y antes de conectar a nada.
# curl no se comprueba: sin él, verificar se salta el HTTP.
# ------------------------------------------------------------

comprobar_herramientas() {

  local necesarias=();
  local faltan=();
  local h;


  case "$FASE" in
    plan)        necesarias=(ssh php mysql getent awk);;
    1)           necesarias=(ssh php mysql getent awk rsync gzip git chpasswd);;
    sincronizar) necesarias=(ssh rsync);;
    2)           necesarias=(ssh getent);;
    verificar)   necesarias=(ssh php mysql getent);;
  esac;


  for h in "${necesarias[@]}"
  do

    if ! command -v "$h" >/dev/null 2>&1; then
      faltan+=("$h");
    fi;

  done;


  if [ "${#faltan[@]}" -gt 0 ]; then

    echo;
    echo "ERROR: faltan herramientas en este servidor:";

    for h in "${faltan[@]}"
    do
      echo "  $h";
    done;

    echo;

    exit 1;

  fi;

}


comprobar_herramientas;



# ============================================================
# === VARIABLES DERIVADAS ===
# ============================================================

BASE_DESTINO="/home/$USER_DESTINO/web";
BASE_ORIGEN="/home/$USER_ORIGEN/web";


# ------------------------------------------------------------
# Todo lo que genera una migración va a una carpeta por
# corrida, no repartido por los private/ de cada dominio.
#
#   /home/USUARIO/migraciones/20260909_142000/
#     example.org_database.php.bk
#     example.org_database.log
#     example.org_viejo_web.sql.gz
#     legacy_admin_legacy.sql.gz
#
# Así los backups, los dumps y los logs de una misma
# ejecución quedan juntos, incluidas las bases que no
# cuelgan de ningún dominio.
#
# El enlace "ultima" apunta siempre a la más reciente.
# ------------------------------------------------------------

CORRIDA="$(date '+%Y%m%d_%H%M%S')";

DIR_MIGRACIONES="/home/$USER_DESTINO/migraciones";

DIR_CORRIDA="$DIR_MIGRACIONES/$CORRIDA";



# ============================================================
# === CARGAR RESOLUCIÓN DE PRIVILEGIOS ===
# ============================================================
#
# Debe cargarse ANTES de cualquier operación, porque define
# las funciones que el resto del archivo utiliza:
#
#   hestia          comandos v-* (CLI o API)
#   hestia_salida   comandos v-* que devuelven datos
#   mysql_destino   cliente MySQL local
#   sql_destino     consulta local por STDIN
#   origen_exec     comando en el servidor origen
#   sql_origen      consulta al MySQL del origen
#
# Y las variables:
#
#   priv_local          prefijo local (array, puede ir vacío)
#   SSH_TARGET          usuario@ip del origen
#   RSYNC_OPTS          opciones según el privilegio disponible
#   RSYNC_PATH_REMOTO   valor para --rsync-path
#
# ============================================================

if [ ! -f "$PRIV_SCRIPT" ]; then

  echo;
  echo "ERROR: No existe:";
  echo "$PRIV_SCRIPT";
  echo;

  exit 1;

fi;


# shellcheck source=/dev/null
source "$PRIV_SCRIPT";


# ------------------------------------------------------------
# Si falla, BASE_PRIVILEGIOS.sh ya imprimió su propio ERROR.
# ------------------------------------------------------------

if [ "$?" -ne 0 ]; then

  exit 1;

fi;


if [ ! -f "$LEER_SCRIPT" ]; then

  echo;
  echo "ERROR: No existe:";
  echo "$LEER_SCRIPT";
  echo;

  exit 1;

fi;


# shellcheck source=/dev/null
source "$LEER_SCRIPT";


if [ ! -f "$PLAN_SCRIPT" ]; then

  echo;
  echo "ERROR: No existe:";
  echo "$PLAN_SCRIPT";
  echo;

  exit 1;

fi;


# shellcheck source=/dev/null
source "$PLAN_SCRIPT";



# ============================================================
# === FUNCIONES DE CONFIGURACIÓN ===
# ============================================================

# ------------------------------------------------------------
# Comprueba si un dominio resuelve hacia IP_DESTINO.
#
# getent ahostsv4 usa el resolvedor del sistema y funciona
# también con dominios que resuelven mediante CNAME.
# ------------------------------------------------------------

resuelve_a_destino() {

  local domain="$1";
  local ips;

  ips="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u)";

  if echo "$ips" | grep -Fxq "$IP_DESTINO"; then
    return 0;
  fi;


  if [ -n "$ips" ]; then
    echo "  IP(s) detectada(s):";
    echo "$ips" | sed 's/^/    /';
  else
    echo "  No se pudo resolver el dominio.";
  fi;

  return 1;

}


# ------------------------------------------------------------
# ¿Es una IP de Cloudflare?
#
# Con el proxy de Cloudflare activo (la nube naranja), el
# dominio resuelve a sus IP y nunca a IP_DESTINO, así que el
# certificado no se puede emitir.
#
# Rangos copiados de https://www.cloudflare.com/ips-v4 el
# 2026-09-18. Se comparan como enteros, en bash puro.
# ------------------------------------------------------------

CLOUDFLARE_RANGOS=(
  173.245.48.0/20
  103.21.244.0/22
  103.22.200.0/22
  103.31.4.0/22
  141.101.64.0/18
  108.162.192.0/18
  190.93.240.0/20
  188.114.96.0/20
  197.234.240.0/22
  198.41.128.0/17
  162.158.0.0/15
  104.16.0.0/13
  104.24.0.0/14
  172.64.0.0/13
  131.0.72.0/22
);


ip_a_entero() {

  local a b c d;

  IFS=. read -r a b c d <<< "$1";

  echo $(( (a << 24) + (b << 16) + (c << 8) + d ));

}


es_ip_cloudflare() {

  local ip;
  local rango;
  local red;
  local bits;
  local mascara;

  case "$1" in
    *[!0-9.]*|'') return 1;;
  esac;

  ip="$(ip_a_entero "$1")";


  for rango in "${CLOUDFLARE_RANGOS[@]}"
  do

    red="$(ip_a_entero "${rango%/*}")";
    bits="${rango#*/}";

    mascara=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ));

    if [ $(( ip & mascara )) -eq "$red" ]; then
      return 0;
    fi;

  done;

  return 1;

}


resuelve_a_cloudflare() {

  local ip;

  for ip in $(getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u)
  do

    if es_ip_cloudflare "$ip"; then
      return 0;
    fi;

  done;

  return 1;

}


# ------------------------------------------------------------
# Lee de HestiaCP si el dominio ya tiene SSL y si ese
# certificado lo emitió Let's Encrypt.
#
# Devuelve "SSL|LETSENCRYPT", por ejemplo "yes|yes".
# ------------------------------------------------------------

estado_certificado() {

  local site="$1";
  local info;
  local ssl;
  local le;

  info="$(hestia_salida v-list-web-domain "$USER_DESTINO" "$site" json 2>/dev/null)";

  ssl="$(
    echo "$info" |
    grep -Eo '"SSL"[[:space:]]*:[[:space:]]*"?(yes|no|true|false|[01])"?' |
    head -n 1 | grep -Eo '(yes|no|true|false|[01])"?$' | tr -d '"'
  )";

  le="$(
    echo "$info" |
    grep -Eo '"LETSENCRYPT"[[:space:]]*:[[:space:]]*"?(yes|no|true|false|[01])"?' |
    head -n 1 | grep -Eo '(yes|no|true|false|[01])"?$' | tr -d '"'
  )";

  printf '%s|%s\n' "$ssl" "$le";

}


# ------------------------------------------------------------
# ¿Ya tiene un certificado de Let's Encrypt emitido?
#
# Reemitirlo sin necesidad consume cuota: Let's Encrypt
# permite 5 certificados duplicados por semana para el mismo
# conjunto de dominios. Agotarla deja el dominio sin poder
# emitir durante días.
#
# La renovación automática ya la gestiona HestiaCP.
# ------------------------------------------------------------

tiene_certificado() {

  local e;

  e="$(estado_certificado "$1")";

  case "${e%%|*}" in
    yes|true|1) ;;
    *) return 1;;
  esac;

  case "${e##*|}" in
    yes|true|1) return 0;;
    *) return 1;;
  esac;

}


# ------------------------------------------------------------
# Crea la carpeta de esta corrida.
#
# Solo la llaman las fases que ejecutan algo. Ni "plan" ni
# "verificar" deben escribir nada en el disco.
# ------------------------------------------------------------

preparar_corrida() {

  if [ "$CORRIDA_LISTA" = "true" ]; then
    return 0;
  fi;


  mkdir -p "$DIR_CORRIDA";

  chmod 700 "$DIR_MIGRACIONES" 2>/dev/null;
  chmod 700 "$DIR_CORRIDA";

  ln -sfn "$DIR_CORRIDA" "$DIR_MIGRACIONES/ultima";

  "${priv_local[@]}" chown -R "$USER_DESTINO":"$USER_DESTINO" \
    "$DIR_MIGRACIONES" 2>/dev/null;


  CORRIDA_LISTA="true";


  echo;
  echo "Backups, dumps y logs de esta corrida:";
  echo;
  echo "  $DIR_CORRIDA";

}


CORRIDA_LISTA="false";


# ------------------------------------------------------------
# Apunta cómo deshacer algo que se acaba de crear.
#
# Solo se registra lo que esta corrida creó de verdad. Un
# objeto que ya existía (E_EXISTS) NO se registra: borrarlo
# sería destruir algo que no habíamos puesto nosotros.
#
# Las líneas salen comentadas a propósito. Deshacer una
# migración a medias es una decisión, no un botón.
# ------------------------------------------------------------

deshacer_registrar() {

  local descripcion="$1";
  local comando="$2";

  local archivo="$DIR_CORRIDA/deshacer.sh";


  if [ ! -f "$archivo" ]; then

    {
      echo "#!/bin/bash";
      echo;
      echo "# ============================================================";
      echo "# DESHACER ESTA CORRIDA";
      echo "# ============================================================";
      echo "#";
      echo "# Generado el $(date '+%Y-%m-%d %H:%M:%S')";
      echo "#";
      echo "# Solo aparece lo que ESTA corrida creó. Lo que ya existía";
      echo "# antes no está aquí: no lo pusimos nosotros.";
      echo "#";
      echo "# Los archivos copiados NO se pueden deshacer desde aquí:";
      echo "# rsync no guarda lo que sobrescribió.";
      echo "#";
      echo "# Las líneas están comentadas. Léelas, descomenta lo que";
      echo "# quieras deshacer y ejecuta. En orden inverso al de";
      echo "# creación, que es como están escritas.";
      echo "# ============================================================";
      echo;
    } > "$archivo";

    chmod 700 "$archivo";

  fi;


  {
    echo "# $descripcion";
    echo "# $comando";
    echo;
  } >> "$archivo";

}


# ------------------------------------------------------------
# Sincroniza los archivos de un dominio desde el origen.
#
# Se usa en las dos fases: en la fase 2 arrastra lo que haya
# cambiado durante la propagación del DNS.
#
# --delete elimina en destino lo que ya no existe en origen.
# ------------------------------------------------------------

migrar_archivos() {

  local site="$1";


  # ----------------------------------------------------------
  # Un dominio solo de correo no tiene public_html.
  # ----------------------------------------------------------

  if ! cfg_si "$site" web; then

    return 0;

  fi;

  echo;
  echo "============================================================";
  echo "SINCRONIZANDO: $site";
  echo "============================================================";


  # ----------------------------------------------------------
  # Los permisos pueden declararse por dominio con la clave
  # chmod. RSYNC_OPTS ya trae el valor global, así que este
  # --chmod va después y es el que manda.
  # ----------------------------------------------------------

  # ----------------------------------------------------------
  # --log-file deja constancia de cada archivo transferido y
  # de cada borrado, que es lo que --delete hace y no se ve
  # en pantalla.
  # ----------------------------------------------------------

  local log_archivos;

  log_archivos="$DIR_CORRIDA/${site}_archivos.log";


  rsync $RSYNC_OPTS \
    -e "$RSYNC_SSH" \
    --chmod="$(cfg "$site" chmod)" \
    --delete \
    --info=progress2 \
    --log-file="$log_archivos" \
    --rsync-path="$RSYNC_PATH_REMOTO" \
    "$SSH_TARGET:$BASE_ORIGEN/$(cfg "$site" origen)/public_html/" \
    "$BASE_DESTINO/$site/public_html/";


  if [ "$?" -ne 0 ]; then

    echo;
    echo "ERROR: rsync falló para $site.";
    echo "La migración continúa con el siguiente dominio.";

    return 1;

  fi;


  # ----------------------------------------------------------
  # El propietario solamente hay que ajustarlo si este script
  # no se está ejecutando como el usuario del panel.
  #
  # Los permisos ya los aplicó rsync con --chmod, así que no
  # hace falta chmod aquí.
  # ----------------------------------------------------------

  if [ "$USUARIO_LOCAL" != "$USER_DESTINO" ]; then

    "${priv_local[@]}" chown -Rf \
      "$USER_DESTINO":"$(cfg "$site" grupo)" \
      "$BASE_DESTINO/$site/public_html" 2>/dev/null;

  fi;


  # ----------------------------------------------------------
  # Resumen legible a partir del log de rsync.
  # ----------------------------------------------------------

  local enviados;
  local borrados;

  enviados="$(grep -c ' >f' "$log_archivos" 2>/dev/null)";
  borrados="$(grep -c '\*deleting' "$log_archivos" 2>/dev/null)";

  echo "OK: $site  ($enviados archivos, $borrados borrados)";


  {
    echo;
    echo "RESUMEN";
    echo "  archivos transferidos : $enviados";
    echo "  archivos borrados     : $borrados";
    echo "  origen  : $SSH_TARGET:$BASE_ORIGEN/$(cfg "$site" origen)/public_html/";
    echo "  destino : $BASE_DESTINO/$site/public_html/";
    echo "  permisos: $(cfg "$site" chmod)";
  } >> "$log_archivos";


  return 0;

}



# ============================================================
# === MOSTRAR RESUMEN ===
# ============================================================

echo;
echo "============================================================";
echo "MIGRACIÓN HESTIACP - FASE $FASE";
echo "============================================================";
echo;
echo "Usuario destino : $USER_DESTINO";
echo "Usuario origen  : $USER_ORIGEN";
echo "IP origen       : $IP_ORIGEN";
echo "IP destino      : $IP_DESTINO";
echo;
echo "Archivo         : $MIGRACION";
echo;
echo "Dominios:";

cfg_resumen;

echo;
echo "Bases de datos a migrar: ${#DBS[@]}";
echo;



# ############################################################
# ###                                                      ###
# ###                 V E R I F I C A C I Ó N              ###
# ###                                                      ###
# ############################################################
#
# Solo lee. No modifica nada.
#
# Comprueba que cada aplicación tenga escritas las
# credenciales correctas y que esas credenciales conecten.
#
# ############################################################

if [ "$FASE" = "verificar" ]; then

  if [ ! -f "$VERIFICAR_SCRIPT" ]; then

    echo;
    echo "ERROR: No existe:";
    echo "$VERIFICAR_SCRIPT";
    echo;

    exit 1;

  fi;


  # shellcheck source=/dev/null
  source "$VERIFICAR_SCRIPT";

  leer_config_cleanup;

  if [ "${VERIF_PROBLEMAS:-0}" -gt 0 ]; then
    exit 1;
  fi;

  exit 0;

fi;



# ############################################################
# ###                                                      ###
# ###             S I N C R O N I Z A R                    ###
# ###                                                      ###
# ############################################################
#
# Vuelve a traer los archivos del servidor viejo.
#
# Está pensada para ejecutarse JUSTO ANTES de apuntar el DNS,
# tantas veces como haga falta, para arrastrar lo que haya
# cambiado desde la fase 1.
#
# Usa --delete, así que el destino queda idéntico al origen.
#
# NO debe ejecutarse después del corte de DNS: en cuanto el
# tráfico entra al servidor nuevo, ahí empiezan a escribirse
# subidas, caché y sesiones que en el viejo no existen, y
# --delete se las llevaría por delante.
#
# ############################################################

if [ "$FASE" = "sincronizar" ]; then

  echo;
  echo "============================================================";
  echo "SINCRONIZANDO ARCHIVOS";
  echo "============================================================";
  echo;
  preparar_corrida;

  echo "El destino quedará idéntico al origen: lo que no exista";
  echo "en el servidor viejo se borrará en el nuevo.";
  echo;
  echo "Hacer esto DESPUÉS de apuntar el DNS destruiría lo que";
  echo "hayan escrito los visitantes en el servidor nuevo.";


  if ! confirmar_plan; then

    leer_config_cleanup;

    exit 1;

  fi;


  for site in "${DOMINIOS[@]}"
  do

    migrar_archivos "$site";

  done;


  echo;
  echo "============================================================";
  echo "SINCRONIZACIÓN COMPLETADA";
  echo "============================================================";
  echo;
  echo "Se puede repetir hasta el momento de apuntar el DNS.";
  echo;

  leer_config_cleanup;

  exit 0;

fi;



# ############################################################
# ###                                                      ###
# ###          E Q U I V A L E N C I A S   Y   P L A N     ###
# ###                                                      ###
# ############################################################
#
# Todo lo que hay aquí es de SOLO LECTURA.
#
# Se ejecuta antes de tocar nada para que el plan pueda decir
# la verdad sobre lo que va a pasar.
#
# ############################################################

if [ "$FASE" = "1" ] || [ "$FASE" = "plan" ]; then

# ------------------------------------------------------------
# correo="auto": se decide mirando las cuentas del origen.
# Antes de las comprobaciones, que miden los buzones de los
# dominios con correo.
# ------------------------------------------------------------

cfg_resolver_correo;


# ------------------------------------------------------------
# Comprobaciones previas. Solo leen.
# ------------------------------------------------------------

if [ -f "$COMPROBAR_SCRIPT" ]; then

  # shellcheck source=/dev/null
  source "$COMPROBAR_SCRIPT";


  if [ "${COMPROBAR_ERRORES:-0}" -ne 0 ] && [ "$FASE" = "1" ]; then

    leer_config_cleanup;

    exit 1;

  fi;

fi;




# ============================================================
# === EQUIVALENCIAS DE BASE DE DATOS ===
# ============================================================
#
# Antes de crear nada se lee la configuración que tiene AHORA
# la aplicación en el servidor viejo.
#
# Con eso se arma la equivalencia real de la migración:
#
#   cómo estaba          ->   cómo va a quedar
#
#
# Sirve para dos cosas:
#
#   1. Si no se declaró bd_origen, se descubre solo. Es el
#      dato que había que ir a mirar a mano.
#
#   2. Si sí se declaró, se contrasta. Un bd_origen
#      equivocado significaría importar la base de otro
#      sitio, así que es un error que detiene la migración.
#
# ============================================================

echo;
echo "============================================================";
echo "EQUIVALENCIAS DE BASE DE DATOS";
echo "============================================================";

EQUIV_ERRORES=0;


for site in "${DOMINIOS[@]}"
do

  if [ -z "$(cfg "$site" bd)" ]; then
    continue;
  fi;


  echo;
  echo "$site";


  TIPO_APP="$(cfg "$site" tipo)";

  DECLARADO_DB="$(cfg "$site" bd_origen)";
  DECLARADO_USER="$(cfg "$site" bd_user_origen)";


  # ----------------------------------------------------------
  # Con tipo=ninguno no hay archivo que leer.
  # ----------------------------------------------------------

  if [ "$TIPO_APP" = "ninguno" ]; then

    if [ -z "$DECLARADO_DB" ]; then

      echo "  ERROR: tipo=ninguno exige declarar bd_origen.";
      echo "  No hay archivo del que deducirlo.";

      EQUIV_ERRORES=$((EQUIV_ERRORES + 1));

      continue;

    fi;

    echo "  db   : $DECLARADO_DB  ->  $(cfg "$site" bd_final)";
    echo "  user : (sin leer)  ->  $(cfg "$site" bd_user_final)";

    continue;

  fi;


  RUTA_ORIGEN="$(cfg "$site" ruta_db_origen)";

  if [ -z "$RUTA_ORIGEN" ]; then
    RUTA_ORIGEN="$(cfg "$site" ruta_db)";
  fi;


  ARCHIVO_ORIGEN="$BASE_ORIGEN/$(cfg "$site" origen)/$RUTA_ORIGEN";


  LEIDO="$(leer_config_origen "$ARCHIVO_ORIGEN" "$TIPO_APP")";


  if [ -z "$LEIDO" ]; then

    echo "  No se pudo leer:";
    echo "    $ARCHIVO_ORIGEN";


    if [ -z "$DECLARADO_DB" ]; then

      echo "  ERROR: y tampoco se declaró bd_origen.";

      EQUIV_ERRORES=$((EQUIV_ERRORES + 1));

    else

      echo "  Se usará lo declarado: $DECLARADO_DB";

    fi;

    continue;

  fi;


  VIEJO_DB="$(valor_de "$LEIDO" DB)";
  VIEJO_USER="$(valor_de "$LEIDO" USER)";
  VIEJO_HOST="$(valor_de "$LEIDO" HOST)";


  # ----------------------------------------------------------
  # Contrastar contra lo declarado.
  # ----------------------------------------------------------

  if [ -n "$DECLARADO_DB" ] && [ "$DECLARADO_DB" != "$VIEJO_DB" ]; then

    echo "  ERROR: bd_origen declarado no coincide con el archivo.";
    echo "    declarado : $DECLARADO_DB";
    echo "    archivo   : $VIEJO_DB";
    echo;
    echo "  Importar la base equivocada es peor que no importar";
    echo "  ninguna, así que la migración se detiene.";

    EQUIV_ERRORES=$((EQUIV_ERRORES + 1));

    continue;

  fi;


  if [ -n "$DECLARADO_USER" ] && [ "$DECLARADO_USER" != "$VIEJO_USER" ]; then

    echo "  AVISO: bd_user_origen declarado no coincide.";
    echo "    declarado : $DECLARADO_USER";
    echo "    archivo   : $VIEJO_USER";

  fi;


  # ----------------------------------------------------------
  # Si no se declaró, el archivo manda.
  # ----------------------------------------------------------

  if [ -z "$DECLARADO_DB" ]; then

    CFG_VALORES[$site|bd_origen]="$VIEJO_DB";

    echo "  bd_origen deducido del servidor viejo.";

  fi;


  CFG_VALORES[$site|bd_user_origen]="$VIEJO_USER";


  # ----------------------------------------------------------
  # La equivalencia.
  # ----------------------------------------------------------

  echo "  db   : $VIEJO_DB  ->  $(cfg "$site" bd_final)";
  echo "  user : $VIEJO_USER  ->  $(cfg "$site" bd_user_final)";
  echo "  host : $VIEJO_HOST  ->  localhost";
  echo "  pass : cambia";

done;


if [ "$EQUIV_ERRORES" -ne 0 ]; then

  echo;
  echo "============================================================";
  echo "ERRORES EN LAS EQUIVALENCIAS: $EQUIV_ERRORES";
  echo "============================================================";
  echo;
  echo "No se ha modificado nada. Corregir y volver a ejecutar.";
  echo;

  exit 1;

fi;


# Reconstruir DBS con los bd_origen ya resueltos.

cfg_construir_dbs;



fi;



# ============================================================
# === MOSTRAR EL PLAN ===
# ============================================================

mostrar_plan;


if [ "$FASE" = "plan" ]; then

  echo;
  echo "Esto era solo el plan. No se ha ejecutado nada.";
  echo;
  echo "Para ejecutarlo, repetir el comando con la fase 1 o 2.";
  echo;

  leer_config_cleanup;

  exit 0;

fi;


if ! confirmar_plan; then

  leer_config_cleanup;

  exit 1;

fi;



# ############################################################
# ###                                                      ###
# ###                      F A S E   1                     ###
# ###                                                      ###
# ############################################################

if [ "$FASE" = "1" ]; then



# ============================================================
# === CREAR EL USUARIO DEL PANEL ===
# ============================================================
#
# Si USER_DESTINO no existe, se crea con los datos de
# USER_ORIGEN en el servidor viejo: contacto, nombre,
# paquete y contraseña.
#
# La contraseña se crea aleatoria, solo para pasar
# v-add-user, y después se sustituye por el hash de
# /etc/shadow del origen. Nunca se imprime.
#
# Las comprobaciones previas ya pararon la fase si no se
# puede crear (sin root, en modo API o CREAR_USUARIO=false).
#
# ============================================================

if ! usuario_destino_existe; then

  echo;
  echo "============================================================";
  echo "CREANDO USUARIO DEL PANEL: $USER_DESTINO";
  echo "============================================================";


  USUARIO_CONF="$(
    origen_exec \
      "cat /usr/local/hestia/data/users/$USER_ORIGEN/user.conf" \
      "" </dev/null 2>/dev/null
  )";


  # --------------------------------------------------------
  # user.conf tiene una clave por línea: CLAVE='valor'. Se
  # toma la línea entera y se quita la última comilla, así
  # que un apóstrofo dentro del valor (O'Brien) no lo corta.
  # --------------------------------------------------------

  usuario_valor() {
    local linea;
    linea="$(echo "$USUARIO_CONF" | grep -m 1 "^$1='")";
    linea="${linea#"$1='"}";
    echo "${linea%\'}";
  }


  USUARIO_CONTACTO="$(usuario_valor CONTACT)";
  USUARIO_NOMBRE="$(usuario_valor NAME)";
  USUARIO_PAQUETE="$(usuario_valor PACKAGE)";


  if [ -z "$USUARIO_CONTACTO" ]; then

    echo;
    echo "ERROR: no se pudo leer el correo de contacto de";
    echo "$USER_ORIGEN en el origen:";
    echo "  /usr/local/hestia/data/users/$USER_ORIGEN/user.conf";
    echo;

    leer_config_cleanup;

    exit 1;

  fi;


  if [ -z "$USUARIO_PAQUETE" ] ||
     [ ! -f "/usr/local/hestia/data/packages/$USUARIO_PAQUETE.pkg" ]; then

    echo "AVISO: el paquete '$USUARIO_PAQUETE' no existe aquí; se usa default.";

    USUARIO_PAQUETE="default";

  fi;


  echo "  contacto : $USUARIO_CONTACTO";
  echo "  nombre   : $USUARIO_NOMBRE";
  echo "  paquete  : $USUARIO_PAQUETE";
  echo "  password : [NO SE MUESTRA]";


  USUARIO_TEMPORAL="$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-20)Aa1.";

  hestia v-add-user \
    "$USER_DESTINO" \
    "$USUARIO_TEMPORAL" \
    "$USUARIO_CONTACTO" \
    "$USUARIO_PAQUETE" \
    "$USUARIO_NOMBRE";

  CODIGO=$?;

  USUARIO_TEMPORAL="";

  if [ "$CODIGO" -ne 0 ]; then
    echo "  $(hestia_texto "$CODIGO")";
  fi;


  # ----------------------------------------------------------
  # La misma contraseña que en el origen: su hash de shadow,
  # en /etc/shadow y en el campo MD5 de user.conf, que es lo
  # que hace v-change-user-password.
  #
  # awk con -v y no sed: el hash lleva $ y /.
  # ----------------------------------------------------------

  USUARIO_HASH="$(
    origen_exec \
      "awk -F: -v u=$(printf '%q' "$USER_ORIGEN") '\$1==u{print \$2}' /etc/shadow" \
      "" </dev/null 2>/dev/null
  )";


  case "$USUARIO_HASH" in

    ''|'!'*|'*'*)

      echo;
      echo "AVISO: no se pudo leer la contraseña de $USER_ORIGEN en el origen.";
      echo "$USER_DESTINO queda con una contraseña aleatoria. Cambiarla con:";
      echo;
      echo "  v-change-user-password $USER_DESTINO 'NUEVA'";
      ;;

    *)

      USUARIO_CONF_DESTINO="/usr/local/hestia/data/users/$USER_DESTINO/user.conf";

      printf '%s:%s\n' "$USER_DESTINO" "$USUARIO_HASH" |
        "${priv_local[@]}" chpasswd -e;

      if [ -f "$USUARIO_CONF_DESTINO" ]; then

        USUARIO_TMP="$(mktemp)";

        awk -v h="$USUARIO_HASH" '
          /^MD5=/ { print "MD5='"'"'" h "'"'"'"; next }
          { print }
        ' "$USUARIO_CONF_DESTINO" > "$USUARIO_TMP" &&
        [ -s "$USUARIO_TMP" ] &&
        cat "$USUARIO_TMP" > "$USUARIO_CONF_DESTINO";

        rm -f "$USUARIO_TMP";

      fi;

      echo "  contraseña: la misma que en el origen";
      ;;

  esac;

  USUARIO_HASH="";


  preparar_corrida;

  if [ "$CODIGO" -eq 0 ]; then
    deshacer_registrar \
      "usuario $USER_DESTINO, creado por esta corrida (borra TODO lo suyo)" \
      "v-delete-user $USER_DESTINO";
  fi;


  if ! usuario_destino_existe; then

    echo;
    echo "ERROR: el usuario $USER_DESTINO sigue sin existir.";
    echo "No se puede crear nada a su nombre.";
    echo;

    leer_config_cleanup;

    exit 1;

  fi;

fi;


preparar_corrida;


# ------------------------------------------------------------
# Errores de la fase 1: cada comando de HestiaCP que falla
# (salvo E_EXISTS), cada rsync fallido, y los que cuenten
# las bases, el correo y los cronjobs.
# ------------------------------------------------------------

FASE_ERRORES=0;

contar_hestia() {

  if [ "$1" -ne 0 ] && [ "$1" -ne 4 ]; then
    FASE_ERRORES=$((FASE_ERRORES + 1));
  fi;

}



# ============================================================
# === CONFIGURAR DOMINIOS EN HESTIACP ===
# ============================================================

echo;
echo "============================================================";
echo "CONFIGURANDO DOMINIOS";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if ! cfg_si "$site" web; then
    echo;
    echo "OMITIDO (solo correo): $site";
    continue;
  fi;


  echo;
  echo "AGREGANDO: $site";

  hestia v-add-domain "$USER_DESTINO" "$site";

  CODIGO=$?;

  contar_hestia "$CODIGO";

  if [ "$CODIGO" -ne 0 ]; then
    echo "  $(hestia_texto "$CODIGO")";
  else
    deshacer_registrar \
      "dominio $site, creado por esta corrida" \
      "v-delete-domain $USER_DESTINO $site";
  fi;

done;



# ============================================================
# === CONFIGURAR BASES DE DATOS EN HESTIACP ===
# ============================================================
#
# Se utiliza DBS como fuente única.
#
# Formato:
#
#   dominio|bd_origen|bd_destino|usuario|password
#
# ============================================================

echo;
echo "============================================================";
echo "CONFIGURANDO BASES DE DATOS";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if [ -z "$(cfg "$site" bd)" ]; then
    continue;
  fi;


  # ----------------------------------------------------------
  # v-add-database recibe los nombres CORTOS: HestiaCP les
  # antepone el usuario del panel.
  #
  # Los nombres finales, que son los que verá la aplicación,
  # se muestran para poder contrastarlos.
  # ----------------------------------------------------------

  echo;
  echo "BASE DE DATOS: $site";
  echo "  ORIGEN : $(cfg "$site" bd_origen)";
  echo "  DB     : $(cfg "$site" bd_corto)  ->  $(cfg "$site" bd_final)";
  echo "  USER   : $(cfg "$site" bd_user_corto)  ->  $(cfg "$site" bd_user_final)";
  echo "  PASS   : [NO SE MUESTRA]";

  hestia v-add-database \
    "$USER_DESTINO" \
    "$(cfg "$site" bd_corto)" \
    "$(cfg "$site" bd_user_corto)" \
    "$(cfg "$site" bd_pass)";

  CODIGO=$?;

  contar_hestia "$CODIGO";

  if [ "$CODIGO" -ne 0 ]; then
    echo "  $(hestia_texto "$CODIGO")";
  else
    deshacer_registrar \
      "base $(cfg "$site" bd_final) de $site, creada por esta corrida" \
      "v-delete-database $USER_DESTINO $(cfg "$site" bd_corto)";
  fi;

done;



# ------------------------------------------------------------
# Bases que no cuelgan de ningún dominio.
# ------------------------------------------------------------

for base in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
do

  echo;
  echo "BASE SUELTA: $base";
  echo "  ORIGEN : $(bdcfg "$base" origen)";
  echo "  DB     : $(bdcfg "$base" corto)  ->  $(bdcfg "$base" final)";
  echo "  USER   : $(bdcfg "$base" user_corto)  ->  $(bdcfg "$base" user_final)";
  echo "  PASS   : [NO SE MUESTRA]";

  hestia v-add-database \
    "$USER_DESTINO" \
    "$(bdcfg "$base" corto)" \
    "$(bdcfg "$base" user_corto)" \
    "$(bdcfg "$base" pass)";

  CODIGO=$?;

  contar_hestia "$CODIGO";

  if [ "$CODIGO" -ne 0 ]; then
    echo "  $(hestia_texto "$CODIGO")";
  else
    deshacer_registrar \
      "base suelta $(bdcfg "$base" final), creada por esta corrida" \
      "v-delete-database $USER_DESTINO $(bdcfg "$base" corto)";
  fi;

done;



# ============================================================
# === LIMPIAR ARCHIVOS PREDETERMINADOS DE HESTIA ===
# ============================================================

echo;
echo "============================================================";
echo "LIMPIANDO ARCHIVOS PREDETERMINADOS";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if ! cfg_si "$site" web; then
    continue;
  fi;


  SITE_PUBLIC="$BASE_DESTINO/$site/public_html";

  echo "Limpiando: $site";

  rm -f "$SITE_PUBLIC/index.html";
  rm -f "$SITE_PUBLIC/robots.txt";

done;



# ============================================================
# === LIMPIAR ALIASES WWW ===
# ============================================================
#
# Se intenta eliminar:
#
#   www.subdominio
#
# para cada dominio que tenga dicha variante.
#
# Si el alias no existe, Hestia devuelve E_NOTEXIST.
# Eso no implica un problema con la migración.
#
# ============================================================

echo;
echo "============================================================";
echo "LIMPIANDO ALIASES WWW";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if ! cfg_si "$site" web; then
    continue;
  fi;


  ALIAS_WWW="$(cfg "$site" alias_www)";


  # ----------------------------------------------------------
  # auto: solo los subdominios tienen alias www que sobre.
  # ----------------------------------------------------------

  if [ "$ALIAS_WWW" = "auto" ]; then

    case "$site" in
      *.*.*) ALIAS_WWW="true";;
      *)     ALIAS_WWW="false";;
    esac;

  fi;


  if [ "$ALIAS_WWW" = "true" ]; then

    alias="www.$site";

    echo "Eliminando alias: $alias";

    hestia v-delete-web-domain-alias \
      "$USER_DESTINO" \
      "$site" \
      "$alias";

    CODIGO=$?;

    contar_hestia "$CODIGO";

    if [ "$CODIGO" -ne 0 ]; then
      echo "  $(hestia_texto "$CODIGO")";
    fi;

  else

    echo "Alias WWW conservado: $site";

  fi;

done;



# ============================================================
# === CONFIGURAR PHP ===
# ============================================================

echo;
echo "============================================================";
echo "CONFIGURANDO PHP";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if ! cfg_si "$site" web; then
    echo "Sin PHP (solo correo) -> $site";
    continue;
  fi;


  PHP_VERSION="$(cfg "$site" php)";

  if [ -z "$PHP_VERSION" ]; then

    echo "ERROR: No existe versión PHP configurada para $site.";
    exit 1;

  fi;

  echo "PHP $PHP_VERSION -> $site";

  hestia v-change-web-domain-backend-tpl \
    "$USER_DESTINO" \
    "$site" \
    "$PHP_VERSION";

  CODIGO=$?;

  contar_hestia "$CODIGO";

  if [ "$CODIGO" -ne 0 ]; then
    echo "  $(hestia_texto "$CODIGO")";
  fi;

done;



# ============================================================
# === ELIMINAR DNS ===
# ============================================================

echo;
echo "============================================================";
echo "CONFIGURANDO DNS";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if cfg_si "$site" eliminar_dns; then

    echo "Eliminando DNS -> $site";

    hestia v-delete-dns-domain \
      "$USER_DESTINO" \
      "$site";

    CODIGO=$?;

    contar_hestia "$CODIGO";

    if [ "$CODIGO" -ne 0 ]; then
      echo "  $(hestia_texto "$CODIGO")";
    fi;

  else

    echo "DNS conservado -> $site";

  fi;

done;



# ============================================================
# === ELIMINAR MAIL ===
# ============================================================

echo;
echo "============================================================";
echo "CONFIGURANDO MAIL";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if cfg_si "$site" eliminar_mail; then

    echo "Eliminando MAIL -> $site";

    hestia v-delete-mail-domain \
      "$USER_DESTINO" \
      "$site";

    CODIGO=$?;

    contar_hestia "$CODIGO";

    if [ "$CODIGO" -ne 0 ]; then
      echo "  $(hestia_texto "$CODIGO")";
    fi;

  else

    echo "MAIL conservado -> $site";

  fi;

done;



# ============================================================
# === MIGRACIÓN DE ARCHIVOS ===
# ============================================================

echo;
echo "============================================================";
echo "MIGRANDO ARCHIVOS";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if ! migrar_archivos "$site"; then
    FASE_ERRORES=$((FASE_ERRORES + 1));
  fi;

done;



# ============================================================
# === MIGRAR CORREO ===
# ============================================================
#
# Solo si algún dominio lo pide.
#
# ============================================================

MIGRAR_CORREO="false";

for site in "${DOMINIOS[@]}"
do
  if cfg_si "$site" correo; then
    MIGRAR_CORREO="true";
  fi;
done;


if [ "$MIGRAR_CORREO" = "true" ]; then

  echo;
  echo "============================================================";
  echo "MIGRANDO CORREO";
  echo "============================================================";


  if [ ! -f "$MAIL_SCRIPT" ]; then

    echo;
    echo "ERROR: No existe:";
    echo "$MAIL_SCRIPT";
    echo;

    exit 1;

  fi;


  # shellcheck source=/dev/null
  source "$MAIL_SCRIPT";

fi;



# ============================================================
# === MIGRAR CONTENIDO DE LAS BASES DE DATOS ===
# ============================================================
#
# Trae tablas, datos, vistas, procedimientos, funciones,
# triggers y eventos desde el servidor origen, renombrando la
# base y eliminando los DEFINER.
#
# ============================================================

# ----------------------------------------------------------
# Una migración puede no tener ninguna base de datos: solo
# sitios estáticos, o solo correo. En ese caso los dos pasos
# de base de datos se saltan enteros.
# ----------------------------------------------------------

if [ "${#DBS[@]}" -eq 0 ]; then

  echo;
  echo "============================================================";
  echo "SIN BASES DE DATOS QUE MIGRAR";
  echo "============================================================";
  echo;
  echo "Ningún dominio declara bd.";

else

echo;
echo "============================================================";
echo "MIGRANDO CONTENIDO DE LAS BASES DE DATOS";
echo "============================================================";


if [ ! -f "$MIGRAR_DB_SCRIPT" ]; then

  echo;
  echo "ERROR: No existe:";
  echo "$MIGRAR_DB_SCRIPT";
  echo;

  exit 1;

fi;


# shellcheck source=/dev/null
source "$MIGRAR_DB_SCRIPT";



# ============================================================
# === CONFIGURAR database.php ===
# ============================================================
#
# BASE_CONFIGURAR_DB.sh depende de las variables definidas
# al inicio de este archivo.
#
# NO repetir aquí:
#
#   USER_DESTINO
#   DOMINIOS
#   DBS
#   BASE_DESTINO
#
# Las recibe directamente.
#
# ============================================================

echo;
echo "============================================================";
echo "CONFIGURACIÓN DE BASES DE DATOS EN database.php";
echo "============================================================";


if [ ! -f "$DB_SCRIPT" ]; then

  echo;
  echo "ERROR: No existe:";
  echo "$DB_SCRIPT";
  echo;

  exit 1;

fi;


# shellcheck source=/dev/null
source "$DB_SCRIPT";


DB_RESULT=$?;


if [ "$DB_RESULT" -ne 0 ]; then

  echo;
  echo "============================================================";
  echo "ERROR EN CONFIGURACIÓN DE database.php";
  echo "============================================================";

  exit "$DB_RESULT";

fi;

fi;



# ============================================================
# === CRONJOBS ===
# ============================================================
#
# Al final: son del usuario, no de un dominio, y conviene
# decidirlos con los sitios y las bases ya en su sitio.
#
# ============================================================

if [ "${CRONJOBS:-preguntar}" != "ninguno" ] || [ "${CRONJOBS_LISTAR:-true}" = "true" ]; then

  if [ ! -f "$CRON_SCRIPT" ]; then

    echo;
    echo "ERROR: No existe:";
    echo "$CRON_SCRIPT";
    echo;

    exit 1;

  fi;


  # shellcheck source=/dev/null
  source "$CRON_SCRIPT";

fi;



# ============================================================
# === FIN DE LA FASE 1 ===
# ============================================================

FASE_ERRORES=$((
  FASE_ERRORES
  + ${DB_MIGRACION_ERRORES:-0}
  + ${MAIL_ERRORES:-0}
  + ${CRON_ERRORES:-0}
));


echo;
echo "============================================================";

if [ "$FASE_ERRORES" -eq 0 ]; then
  echo "FASE 1 COMPLETADA";
else
  echo "FASE 1 TERMINADA CON $FASE_ERRORES ERROR(ES)";
fi;

echo "============================================================";
echo;
echo "Backups, dumps y logs de esta corrida:";
echo;
echo "  $DIR_CORRIDA";
echo;
echo "  ($DIR_MIGRACIONES/ultima apunta ahí)";

if [ -f "$DIR_CORRIDA/deshacer.sh" ]; then
  echo;
  echo "Si hay que dar marcha atrás, en esa carpeta queda";
  echo "deshacer.sh con lo que esta corrida creó.";
fi;
echo;
echo "Para probar antes de mover el DNS, apuntar el dominio a";
echo "$IP_DESTINO en el archivo hosts de la máquina local.";
echo;
echo "Siguientes pasos, con el mismo comando de siempre y";
echo "cambiando la última palabra:";
echo;
echo "  verificar     comprobar que todo conecta";
echo "  sincronizar   justo ANTES de apuntar el DNS";
echo "  2             ya con el DNS apuntando aquí";
echo;


if [ "$FASE_ERRORES" -ne 0 ]; then
  exit 1;
fi;

fi;



# ############################################################
# ###                                                      ###
# ###                      F A S E   2                     ###
# ###                                                      ###
# ############################################################

if [ "$FASE" = "2" ]; then

preparar_corrida;



# ============================================================
# === RE-SINCRONIZAR ARCHIVOS (DESACTIVADO POR DEFECTO) ===
# ============================================================
#
# La fase 2 se ejecuta cuando el DNS YA apunta aquí, así que
# el servidor nuevo puede llevar rato recibiendo escrituras:
# subidas, caché, sesiones, contenido de usuarios.
#
# Un rsync --delete desde el servidor viejo en ese momento se
# llevaría todo eso por delante.
#
# Por eso el arrastre de archivos vive en su propia fase, que
# se ejecuta ANTES del corte:
#
#   bash BASE_GENERAL.sh migracion.sh sincronizar
#
# Solo si se sabe con certeza que nadie ha escrito nada en el
# servidor nuevo tiene sentido activar esto.
#
# ============================================================

if [ "${SINCRONIZAR_EN_FASE2:-false}" = "true" ]; then

  echo;
  echo "============================================================";
  echo "RE-SINCRONIZANDO ARCHIVOS";
  echo "============================================================";
  echo;
  echo "AVISO: el DNS ya apunta aquí. Si alguien ha escrito algo";
  echo "en el servidor nuevo, esto lo borra.";

  for site in "${DOMINIOS[@]}"
  do

    migrar_archivos "$site";

  done;

fi;



# ============================================================
# === GENERAR SSL ===
# ============================================================
#
# SSL solamente se solicita si:
#
#   1. SSL está habilitado para el dominio.
#   2. El dominio resuelve hacia IP_DESTINO.
#
# ============================================================

echo;
echo "============================================================";
echo "GENERANDO SSL";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if ! cfg_si "$site" web; then

    echo "SSL omitido -> $site  (solo correo)";

    continue;

  fi;


  if ! cfg_si "$site" ssl; then

    echo "SSL omitido -> $site";

    continue;

  fi;


  if ! resuelve_a_destino "$site"; then

    echo "SSL omitido -> $site";

    if resuelve_a_cloudflare "$site"; then
      echo "  Resuelve a Cloudflare (proxy activo): el certificado no se puede emitir así.";
      echo "  1. En Cloudflare, poner sus registros en DNS only (nube gris) -> $IP_DESTINO.";
      echo "  2. Repetir la fase 2 cuando resuelva aquí.";
      echo "  3. Después, SSL/TLS de Cloudflare en Full (strict); nunca Flexible";
      echo "     (con HTTPS forzado provoca ERR_TOO_MANY_REDIRECTS).";
    else
      echo "  El dominio todavía no resuelve hacia $IP_DESTINO.";
      echo "  La fase 2 se puede repetir cuando propague.";
    fi;

    continue;

  fi;


  if [ "${RENOVAR_SSL:-false}" != "true" ] && tiene_certificado "$site"; then

    echo "SSL ya emitido -> $site";
    echo "  Se omite: HestiaCP ya renueva solo, y reemitirlo";
    echo "  consumiría cuota de Let's Encrypt.";
    echo "  Para forzarlo: RENOVAR_SSL=\"true\"";

    continue;

  fi;


  echo "Let's Encrypt -> $site";

  hestia v-add-letsencrypt-domain \
    "$USER_DESTINO" \
    "$site";

  CODIGO=$?;

  if [ "$CODIGO" -ne 0 ]; then
    echo "  $(hestia_texto "$CODIGO")";
  fi;

done;



# ============================================================
# === FORZAR HTTPS ===
# ============================================================
#
# Solamente se fuerza HTTPS cuando:
#
#   1. FORZAR_SSL está configurado como true.
#   2. SSL está configurado como true.
#   3. El dominio resuelve hacia IP_DESTINO.
#   4. Hestia reporta SSL_ENABLED como activo.
#
# ============================================================

echo;
echo "============================================================";
echo "FORZANDO HTTPS";
echo "============================================================";

for site in "${DOMINIOS[@]}"
do

  if ! cfg_si "$site" web; then

    continue;

  fi;


  if ! cfg_si "$site" forzar_ssl; then

    echo "HTTPS no forzado -> $site";

    continue;

  fi;


  if ! cfg_si "$site" ssl; then

    echo "HTTPS no forzado -> $site";
    echo "  SSL no está habilitado para este dominio.";

    continue;

  fi;


  if ! resuelve_a_destino "$site"; then

    echo "HTTPS no forzado -> $site";

    if resuelve_a_cloudflare "$site"; then
      echo "  Resuelve a Cloudflare (proxy activo): ver los pasos de SSL de arriba.";
    else
      echo "  El dominio no resuelve hacia $IP_DESTINO.";
    fi;

    continue;

  fi;


  DOMAIN_INFO="$(
    hestia_salida v-list-web-domain \
      "$USER_DESTINO" \
      "$site" \
      json
  )";


  # ----------------------------------------------------------
  # HestiaCP publica este dato como "SSL": "yes".
  #
  # La versión anterior buscaba "SSL_ENABLED" con valores
  # 1/true, que no existen en su salida, así que NUNCA daba
  # positivo y HTTPS no se forzaba jamás.
  #
  # Se aceptan las dos claves y los valores habituales.
  # ----------------------------------------------------------

  HESTIA_SSL="$(
    echo "$DOMAIN_INFO" |
    grep -Eo '"SSL(_ENABLED)?"[[:space:]]*:[[:space:]]*"?(yes|no|true|false|[01])"?' |
    head -n 1 |
    grep -Eo '(yes|no|true|false|[01])"?$' |
    tr -d '"'
  )";


  case "$HESTIA_SSL" in

    yes|true|1)
      ;;

    *)

      echo "HTTPS no forzado -> $site";
      echo "  Hestia no reporta SSL activo: $HESTIA_SSL";
      echo "  Puede que Let's Encrypt no llegara a emitirlo.";

      continue;
      ;;

  esac;


  echo "HTTPS -> $site";

  hestia v-add-web-domain-ssl-force \
    "$USER_DESTINO" \
    "$site";

  CODIGO=$?;

  if [ "$CODIGO" -ne 0 ]; then
    echo "  $(hestia_texto "$CODIGO")";
  fi;

done;



# ============================================================
# === FIN DE LA FASE 2 ===
# ============================================================

echo;
echo "============================================================";
echo "FASE 2 COMPLETADA";
echo "============================================================";
echo;
echo "Comprobar:";
echo;
echo "  1. Que el dominio resuelva a $IP_DESTINO.";
echo "  2. Que el certificado se haya emitido.";
echo "  3. Que HTTPS funcione y que HTTP redirija.";
echo "  4. Que la aplicación siga respondiendo bien por HTTPS.";
echo;

fi;
