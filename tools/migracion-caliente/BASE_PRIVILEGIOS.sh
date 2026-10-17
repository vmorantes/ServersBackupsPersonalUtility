#!/bin/bash

# ============================================================
# RESOLUCIÓN DE PRIVILEGIOS
# ============================================================
#
# ESTE ARCHIVO SE CARGA AL INICIO DE:
#
#   BASE_GENERAL.sh
#
# mediante:
#
#   source "$SCRIPT_DIR/BASE_PRIVILEGIOS.sh";
#
#
# ============================================================
#
# OBJETIVO
#
#   Que la migración NO dependa de ser root en ningún punto.
#
#   Nada en el resto de los scripts debe invocar directamente
#   v-*, mysql, ssh, rsync o chown.
#
#   Todo pasa por las funciones que define este archivo.
#
#
# ============================================================
#
# TRES PERFILES DE EJECUCIÓN
#
#   A) ROOT
#
#      El clásico. Todo directo, sin prefijos.
#
#   B) SUDOER
#
#      Usuario normal con sudo. BASE_GENERAL.sh se relanza
#      con sudo (que pide la contraseña si hace falta) y sigue
#      como root, con las llaves SSH de SUDO_USER.
#
#   C) SIN ROOT
#
#      Se ejecuta como el propio usuario del panel.
#
#        - HestiaCP  -> API REST con access key
#        - MySQL     -> usuario y contraseña propios
#        - Archivos  -> se escriben en el home propio,
#                       así que no hace falta chown
#
#      Este perfil no puede migrar cuentas de correo ni tocar
#      usuarios ajenos, pero cubre la migración de sitios.
#
#
# ============================================================
#
# QUÉ EXPONE ESTE ARCHIVO
#
#   priv_local            array con el prefijo local (o vacío)
#
#   hestia CMD ARGS...    ejecuta un comando de HestiaCP
#   hestia_texto CODIGO   traduce un código de retorno
#
#   mysql_destino ARGS    cliente MySQL local
#   sql_destino [DB]      consulta por STDIN, salida en crudo
#
#   origen_exec CMD SSH   ejecuta algo en el servidor origen
#   sql_origen [DB]       consulta al MySQL del origen
#
#   RSYNC_OPTS            opciones de rsync según el perfil
#   RSYNC_PATH_REMOTO     valor para --rsync-path
#
#   priv_cleanup          limpia credenciales temporales
#
# ============================================================



# ============================================================
# === CONFIGURACIÓN: PRIVILEGIO LOCAL ===
# ============================================================
#
# Todas las variables de este archivo usan la forma:
#
#   VARIABLE="${VARIABLE:-valor_por_defecto}";
#
# de modo que BASE_GENERAL.sh puede definirlas antes de
# hacer source y este archivo respeta esa definición.
#
# ============================================================

# ------------------------------------------------------------
#   auto : si no es root y hay sudo, BASE_GENERAL.sh se
#          relanza con sudo; si no hay sudo, sigue sin
#          privilegio
#   none : nunca elevar
# ------------------------------------------------------------

PRIV_LOCAL="${PRIV_LOCAL:-auto}";



# ============================================================
# === CONFIGURACIÓN: HESTIACP ===
# ============================================================

# ------------------------------------------------------------
#   auto : usa API si hay hash configurado, si no CLI
#   cli  : comandos v-* locales
#   api  : API REST
# ------------------------------------------------------------

HESTIA_MODO="${HESTIA_MODO:-auto}";


HESTIA_API_URL="${HESTIA_API_URL:-https://localhost:8083/api/}";


# ------------------------------------------------------------
# Formato: ACCESS_KEY:SECRET_KEY
#
# Se genera en el servidor destino con:
#
#   v-add-access-key 'admin' '*' migracion json
#
# Para restringirlo, crear un perfil en
# /usr/local/hestia/data/api/ y usar su nombre en vez de '*'.
#
# La API debe estar habilitada en:
#
#   Server settings > Security > Enable API access
# ------------------------------------------------------------

HESTIA_API_HASH="${HESTIA_API_HASH:-}";


# ------------------------------------------------------------
# Aceptar el certificado de localhost, que es autofirmado.
# ------------------------------------------------------------

HESTIA_API_INSECURE="${HESTIA_API_INSECURE:-true}";



# ============================================================
# === CONFIGURACIÓN: MYSQL DESTINO ===
# ============================================================

# ------------------------------------------------------------
#   socket : como usuario del sistema (necesita root o sudo)
#   cnf    : defaults-file existente
#   user   : usuario y contraseña de MySQL
# ------------------------------------------------------------

MYSQL_DESTINO_AUTH="${MYSQL_DESTINO_AUTH:-socket}";

MYSQL_DESTINO_CNF="${MYSQL_DESTINO_CNF:-/root/.my.cnf}";

MYSQL_DESTINO_USER="${MYSQL_DESTINO_USER:-}";
MYSQL_DESTINO_PASSWORD="${MYSQL_DESTINO_PASSWORD:-}";



# ============================================================
# === CONFIGURACIÓN: ORIGEN ===
# ============================================================

# ------------------------------------------------------------
# Usuario SSH del servidor origen.
#
# Puede ser root o un sudoer.
# ------------------------------------------------------------

SSH_ORIGEN="${SSH_ORIGEN:-root}";


# ------------------------------------------------------------
#   auto : detecta si el usuario SSH ya es root
#   true : forzar sudo
#   false: nunca usar sudo
# ------------------------------------------------------------

ORIGEN_SUDO="${ORIGEN_SUDO:-auto}";

ORIGEN_SUDO_PASSWORD="${ORIGEN_SUDO_PASSWORD:-}";


# ------------------------------------------------------------
#   socket | cnf | user
# ------------------------------------------------------------

MYSQL_ORIGEN_AUTH="${MYSQL_ORIGEN_AUTH:-socket}";

MYSQL_ORIGEN_CNF="${MYSQL_ORIGEN_CNF:-/root/.my.cnf}";

MYSQL_ORIGEN_USER="${MYSQL_ORIGEN_USER:-}";
MYSQL_ORIGEN_PASSWORD="${MYSQL_ORIGEN_PASSWORD:-}";



# ============================================================
# === CONFIGURACIÓN: ARCHIVOS ===
# ============================================================

# ------------------------------------------------------------
# Permisos que rsync aplicará en el destino.
#
# Se aplican durante la transferencia, lo que evita tener que
# hacer chmod después y evita 0777.
# ------------------------------------------------------------

RSYNC_CHMOD="${RSYNC_CHMOD:-D755,F644}";


# ------------------------------------------------------------
# Grupo del servidor web.
#
# Solo se usa si hay privilegio para hacer chown.
# Sin privilegio, los archivos quedan con el grupo propio del
# usuario, que es lo que Hestia usa por defecto.
# ------------------------------------------------------------

GRUPO_WEB="${GRUPO_WEB:-www-data}";



# ============================================================
# === RESOLVER PRIVILEGIO LOCAL ===
# ============================================================

priv_local=();

PRIV_LOCAL_ES_ROOT="false";


USUARIO_LOCAL="$(id -un)";


echo;
echo "============================================================";
echo "RESOLVIENDO PRIVILEGIOS";
echo "============================================================";
echo;
echo "Usuario local : $USUARIO_LOCAL";


if [ "$(id -u)" -eq 0 ]; then

  PRIV_LOCAL_ES_ROOT="true";

  echo "Privilegio    : root directo";

elif [ "$PRIV_LOCAL" = "none" ]; then

  echo "Privilegio    : ninguno (por configuración)";

else

  # ----------------------------------------------------------
  # Si hubiera sudo, BASE_GENERAL.sh ya se habría relanzado
  # con él. Aquí solo se llega sin sudo.
  # ----------------------------------------------------------

  echo "Privilegio    : ninguno (sudo no disponible)";

fi;


# ------------------------------------------------------------
# Sin root, solo se puede escribir en el home propio. Si no
# somos USER_DESTINO, las fases que escriben fallarían a
# mitad con "Permission denied": mejor decirlo ahora.
# ------------------------------------------------------------

if [ "$PRIV_LOCAL_ES_ROOT" != "true" ] &&
   [ "$USUARIO_LOCAL" != "$USER_DESTINO" ]; then

  case "$FASE" in

    1|2|sincronizar)

      echo;
      echo "ERROR: sin privilegio de root solo se puede ejecutar como $USER_DESTINO.";
      echo "Ejecutar como root o con un usuario con sudo.";
      echo "O usar el perfil sin root (PRIV_LOCAL=\"none\", HESTIA_MODO=\"api\") como $USER_DESTINO.";
      echo;

      return 1 2>/dev/null || exit 1;
      ;;

    *)

      echo;
      echo "AVISO: sin privilegio de root solo se puede ejecutar como $USER_DESTINO.";
      ;;

  esac;

fi;



# ============================================================
# === HESTIACP ===
# ============================================================

HESTIA_BIN="${HESTIA_BIN:-/usr/local/hestia/bin}";


HESTIA_MODO_RESUELTO="";


case "$HESTIA_MODO" in

  api)
    HESTIA_MODO_RESUELTO="api";
    ;;

  cli)
    HESTIA_MODO_RESUELTO="cli";
    ;;

  *)
    if [ -n "$HESTIA_API_HASH" ]; then
      HESTIA_MODO_RESUELTO="api";
    else
      HESTIA_MODO_RESUELTO="cli";
    fi;
    ;;

esac;


# ------------------------------------------------------------
# Traduce los códigos de retorno de HestiaCP.
# ------------------------------------------------------------

hestia_texto() {

  case "$1" in
    0)  echo "OK";;
    1)  echo "E_ARGS: faltan argumentos";;
    2)  echo "E_INVALID: objeto o argumento no válido";;
    3)  echo "E_NOTEXIST: el objeto no existe";;
    4)  echo "E_EXISTS: el objeto ya existe";;
    5)  echo "E_SUSPENDED: el objeto está suspendido";;
    6)  echo "E_UNSUSPENDED: el objeto no está suspendido";;
    7)  echo "E_INUSE: el objeto está en uso";;
    8)  echo "E_LIMIT: límite del paquete de hosting";;
    9)  echo "E_PASSWORD: contraseña incorrecta";;
    10) echo "E_FORBIDEN: sin acceso a este objeto";;
    11) echo "E_DISABLED: subsistema deshabilitado";;
    12) echo "E_PARSING: configuración rota";;
    13) echo "E_DISK: sin espacio en disco";;
    14) echo "E_LA: servidor sobrecargado";;
    15) echo "E_CONNECT: host inalcanzable";;
    17) echo "E_DB: el servidor de base de datos no responde";;
    *)  echo "código $1";;
  esac;

}


# ------------------------------------------------------------
# Ejecuta un comando de HestiaCP.
#
#   hestia v-add-domain "$USER" "$DOMINIO";
#
# Devuelve el código de retorno de HestiaCP.
# ------------------------------------------------------------

hestia() {

  local cmd="$1";

  shift;


  if [ "$HESTIA_MODO_RESUELTO" = "api" ]; then

    local curl_args=();
    local i=1;
    local a;

    for a in "$@"
    do
      curl_args+=( --data-urlencode "arg$i=$a" );
      i=$((i + 1));
    done;


    local insecure=();

    if [ "$HESTIA_API_INSECURE" = "true" ]; then
      insecure=(-k);
    fi;


    local salida;

    salida="$(
      curl -s "${insecure[@]}" \
        --data-urlencode "hash=$HESTIA_API_HASH" \
        --data-urlencode "returncode=yes" \
        --data-urlencode "cmd=$cmd" \
        "${curl_args[@]}" \
        "$HESTIA_API_URL" 2>/dev/null
    )";


    salida="$(echo "$salida" | tr -d '[:space:]')";


    if [ -z "$salida" ]; then
      echo "ERROR: la API de HestiaCP no respondió." >&2;
      return 15;
    fi;


    case "$salida" in
      ''|*[!0-9]*)
        echo "ERROR: respuesta inesperada de la API: $salida" >&2;
        return 2;
        ;;
    esac;


    return "$salida";

  else

    "${priv_local[@]}" "$HESTIA_BIN/$cmd" "$@";

  fi;

}



# ------------------------------------------------------------
# Igual que hestia(), pero devuelve la SALIDA del comando en
# lugar del código de retorno.
#
# Necesaria para comandos de consulta como:
#
#   hestia_salida v-list-web-domain "$USER" "$DOMINIO" json;
#
# En modo API se omite returncode=yes, que es lo que hace que
# la API responda con datos en vez de con un número.
# ------------------------------------------------------------

hestia_salida() {

  local cmd="$1";

  shift;


  if [ "$HESTIA_MODO_RESUELTO" = "api" ]; then

    local curl_args=();
    local i=1;
    local a;

    for a in "$@"
    do
      curl_args+=( --data-urlencode "arg$i=$a" );
      i=$((i + 1));
    done;


    local insecure=();

    if [ "$HESTIA_API_INSECURE" = "true" ]; then
      insecure=(-k);
    fi;


    curl -s "${insecure[@]}" \
      --data-urlencode "hash=$HESTIA_API_HASH" \
      --data-urlencode "cmd=$cmd" \
      "${curl_args[@]}" \
      "$HESTIA_API_URL" 2>/dev/null;

  else

    "${priv_local[@]}" "$HESTIA_BIN/$cmd" "$@" 2>/dev/null;

  fi;

}



# ============================================================
# === MYSQL DESTINO ===
# ============================================================

MYSQL_DESTINO_OPTS="";

MYSQL_DESTINO_PRIV="false";

MYSQL_DESTINO_TMP_CNF="";


case "$MYSQL_DESTINO_AUTH" in

  socket)
    MYSQL_DESTINO_PRIV="true";
    ;;

  cnf)
    MYSQL_DESTINO_OPTS="--defaults-file=$MYSQL_DESTINO_CNF";
    MYSQL_DESTINO_PRIV="true";
    ;;

  user)

    if [ -z "$MYSQL_DESTINO_USER" ]; then
      echo "ERROR: MYSQL_DESTINO_USER está vacío.";
      return 1 2>/dev/null || exit 1;
    fi;


    if [ -z "$MYSQL_DESTINO_PASSWORD" ]; then
      read -r -s -p "Contraseña MySQL de $MYSQL_DESTINO_USER: " \
        MYSQL_DESTINO_PASSWORD;
      echo;
    fi;


    MYSQL_DESTINO_TMP_CNF="$(mktemp)";

    chmod 600 "$MYSQL_DESTINO_TMP_CNF";

    printf '[client]\nuser=%s\npassword=%s\n' \
      "$MYSQL_DESTINO_USER" \
      "$MYSQL_DESTINO_PASSWORD" > "$MYSQL_DESTINO_TMP_CNF";

    MYSQL_DESTINO_PASSWORD="";

    MYSQL_DESTINO_OPTS="--defaults-file=$MYSQL_DESTINO_TMP_CNF";
    ;;

  *)
    echo "ERROR: MYSQL_DESTINO_AUTH no válido: $MYSQL_DESTINO_AUTH";
    return 1 2>/dev/null || exit 1;
    ;;

esac;


# ------------------------------------------------------------
# Cliente MySQL del destino.
#
# Los argumentos se pasan tal cual; STDIN también.
# ------------------------------------------------------------

mysql_destino() {

  if [ "$MYSQL_DESTINO_PRIV" = "true" ]; then
    "${priv_local[@]}" mysql $MYSQL_DESTINO_OPTS "$@";
  else
    mysql $MYSQL_DESTINO_OPTS "$@";
  fi;

}


# ------------------------------------------------------------
# Consulta por STDIN, salida sin cabeceras.
# ------------------------------------------------------------

sql_destino() {

  local db="$1";

  if [ -n "$db" ]; then
    mysql_destino --batch --skip-column-names "$db" 2>/dev/null;
  else
    mysql_destino --batch --skip-column-names 2>/dev/null;
  fi;

}



# ============================================================
# === ORIGEN: SSH Y SUDO ===
# ============================================================

SSH_TARGET="$SSH_ORIGEN@$IP_ORIGEN";


# ------------------------------------------------------------
# Opciones de TODAS las llamadas ssh, también las de rsync.
#
# Relanzado con sudo, ssh buscaría las llaves y known_hosts
# de root. Se añaden las de quien lanzó la migración
# (SUDO_USER), además de las de root.
# ------------------------------------------------------------

SSH_OPTS=(-o BatchMode=yes);

if [ "$(id -u)" -eq 0 ] &&
   [ -n "${SUDO_USER:-}" ] &&
   [ "$SUDO_USER" != "root" ]; then

  HOME_SUDO="$(getent passwd "$SUDO_USER" | cut -d: -f6)";

  for llave in id_ed25519 id_ecdsa id_rsa
  do

    for dir_ssh in "$HOME_SUDO/.ssh" /root/.ssh
    do

      if [ -f "$dir_ssh/$llave" ]; then
        SSH_OPTS+=(-i "$dir_ssh/$llave");
      fi;

    done;

  done;

  SSH_OPTS+=(-o "UserKnownHostsFile=$HOME_SUDO/.ssh/known_hosts /root/.ssh/known_hosts");

fi;


# ------------------------------------------------------------
# Lo mismo para rsync -e, que recibe una sola cadena.
# ------------------------------------------------------------

RSYNC_SSH="ssh$(printf ' %q' "${SSH_OPTS[@]}")";

ORIGEN_SUDO_PREFIX="";
ORIGEN_SUDO_STDIN="false";
ORIGEN_TMP_CNF="";


# ------------------------------------------------------------
# Ejecuta un comando en el origen con el privilegio adecuado.
#
#   $1  comando remoto
#   $2  opciones extra de ssh (por ejemplo -C)
#
# STDIN se entrega al comando remoto.
#
# Cuando sudo necesita contraseña, se antepone una línea que
# sudo -S consume; el resto llega intacto al comando.
#
# Quien llame debe redirigir STDIN siempre, aunque sea desde
# /dev/null.
# ------------------------------------------------------------

origen_exec() {

  local cmd="$1";
  local ssh_extra="$2";

  if [ "$ORIGEN_SUDO_STDIN" = "true" ]; then

    {
      printf '%s\n' "$ORIGEN_SUDO_PASSWORD";
      cat;
    } |
    ssh $ssh_extra "${SSH_OPTS[@]}" "$SSH_TARGET" \
      "$ORIGEN_SUDO_PREFIX$cmd";

  else

    ssh $ssh_extra "${SSH_OPTS[@]}" "$SSH_TARGET" \
      "$ORIGEN_SUDO_PREFIX$cmd";

  fi;

}


if [ -n "$IP_ORIGEN" ]; then

  ORIGEN_WHOAMI="$(
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'id -un' </dev/null 2>/dev/null
  )";


  if [ -z "$ORIGEN_WHOAMI" ]; then

    echo;
    echo "ERROR: No se pudo conectar por SSH a $SSH_TARGET.";
    echo "Instalar la llave con:";
    echo;
    echo "  ssh-copy-id $SSH_TARGET";
    echo;

    return 1 2>/dev/null || exit 1;

  fi;


  echo "Usuario origen: $ORIGEN_WHOAMI";


  NECESITA_SUDO="false";

  case "$ORIGEN_SUDO" in
    true)  NECESITA_SUDO="true";;
    false) NECESITA_SUDO="false";;
    *)     [ "$ORIGEN_WHOAMI" != "root" ] && NECESITA_SUDO="true";;
  esac;


  if [ "$NECESITA_SUDO" = "true" ]; then

    if ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
         'sudo -n true' </dev/null >/dev/null 2>&1; then

      ORIGEN_SUDO_PREFIX="sudo -n ";

      echo "Origen        : sudo sin contraseña";

    else

      if [ -z "$ORIGEN_SUDO_PASSWORD" ]; then

        echo;
        read -r -s -p "Contraseña sudo para $SSH_TARGET: " \
          ORIGEN_SUDO_PASSWORD;

        echo;

      fi;


      if [ -z "$ORIGEN_SUDO_PASSWORD" ]; then

        echo;
        echo "ERROR: sudo en el origen requiere contraseña.";
        echo;
        echo "Alternativas:";
        echo "  - NOPASSWD para este usuario.";
        echo "  - MYSQL_ORIGEN_AUTH=\"user\" para evitar sudo en MySQL.";
        echo;

        return 1 2>/dev/null || exit 1;

      fi;


      ORIGEN_SUDO_PREFIX="sudo -S -p '' ";
      ORIGEN_SUDO_STDIN="true";


      if [ "$(origen_exec "id -un" "" </dev/null 2>/dev/null)" != "root" ]; then

        echo;
        echo "ERROR: sudo falló en el origen.";

        ORIGEN_SUDO_PASSWORD="";

        return 1 2>/dev/null || exit 1;

      fi;


      echo "Origen        : sudo con contraseña";

    fi;

  else

    echo "Origen        : directo";

  fi;

fi;



# ============================================================
# === ORIGEN: AUTENTICACIÓN MYSQL ===
# ============================================================

MYSQL_ORIGEN_OPTS="";


case "$MYSQL_ORIGEN_AUTH" in

  socket)
    ;;

  cnf)
    MYSQL_ORIGEN_OPTS="--defaults-file=$(printf '%q' "$MYSQL_ORIGEN_CNF")";
    ;;

  user)

    if [ -z "$MYSQL_ORIGEN_USER" ]; then
      echo "ERROR: MYSQL_ORIGEN_USER está vacío.";
      return 1 2>/dev/null || exit 1;
    fi;


    if [ -z "$MYSQL_ORIGEN_PASSWORD" ]; then
      read -r -s -p "Contraseña MySQL de $MYSQL_ORIGEN_USER en el origen: " \
        MYSQL_ORIGEN_PASSWORD;
      echo;
    fi;


    ORIGEN_TMP_CNF="$(origen_exec "mktemp" "" </dev/null 2>/dev/null)";


    if [ -z "$ORIGEN_TMP_CNF" ]; then
      echo "ERROR: No se pudo crear el temporal en el origen.";
      return 1 2>/dev/null || exit 1;
    fi;


    origen_exec "chmod 600 $(printf '%q' "$ORIGEN_TMP_CNF")" "" </dev/null;


    printf '[client]\nuser=%s\npassword=%s\n' \
      "$MYSQL_ORIGEN_USER" \
      "$MYSQL_ORIGEN_PASSWORD" |
    origen_exec "cat > $(printf '%q' "$ORIGEN_TMP_CNF")" "";


    MYSQL_ORIGEN_PASSWORD="";

    MYSQL_ORIGEN_OPTS="--defaults-file=$(printf '%q' "$ORIGEN_TMP_CNF")";
    ;;

  *)
    echo "ERROR: MYSQL_ORIGEN_AUTH no válido: $MYSQL_ORIGEN_AUTH";
    return 1 2>/dev/null || exit 1;
    ;;

esac;


# ------------------------------------------------------------
# Consulta al MySQL del origen.
# ------------------------------------------------------------

sql_origen() {

  local db="$1";
  local target="";

  if [ -n "$db" ]; then
    target=" $(printf '%q' "$db")";
  fi;

  origen_exec \
    "mysql $MYSQL_ORIGEN_OPTS --batch --skip-column-names$target" \
    "" 2>/dev/null;

}



# ============================================================
# === RSYNC ===
# ============================================================
#
# Sin privilegio no se pueden conservar propietario, ACL ni
# xattrs. Tampoco hace falta: los archivos se escriben en el
# home propio y Hestia solo necesita que el usuario sea dueño.
#
# --chmod evita el chmod posterior y evita 0777.
#
# ============================================================

RSYNC_PATH_REMOTO="rsync";


if [ -n "$ORIGEN_SUDO_PREFIX" ]; then

  # ----------------------------------------------------------
  # sudo -S no sirve aquí: rsync usa STDIN para su protocolo.
  #
  # Con contraseña, el usuario SSH debe poder leer los
  # archivos por sí mismo o tener NOPASSWD para rsync.
  # ----------------------------------------------------------

  if [ "$ORIGEN_SUDO_STDIN" != "true" ]; then
    RSYNC_PATH_REMOTO="sudo -n rsync";
  fi;

fi;


if [ "$PRIV_LOCAL_ES_ROOT" = "true" ]; then

  RSYNC_OPTS="-aHAX --numeric-ids";

else

  RSYNC_OPTS="-rlptD --no-o --no-g";

fi;


# ------------------------------------------------------------
# El --chmod NO va aquí: lo pone migrar_archivos, que usa el
# de cada dominio.
#
# RSYNC_CHMOD sigue siendo el valor global del que heredan
# los dominios que no declaren el suyo.
# ------------------------------------------------------------



# ============================================================
# === LIMPIEZA ===
# ============================================================

priv_cleanup() {

  if [ -n "$ORIGEN_TMP_CNF" ]; then
    origen_exec "rm -f $(printf '%q' "$ORIGEN_TMP_CNF")" "" </dev/null;
    ORIGEN_TMP_CNF="";
  fi;


  if [ -n "$MYSQL_DESTINO_TMP_CNF" ]; then
    rm -f "$MYSQL_DESTINO_TMP_CNF";
    MYSQL_DESTINO_TMP_CNF="";
  fi;


  ORIGEN_SUDO_PASSWORD="";


  # ----------------------------------------------------------
  # BASE_LEER_CONFIG.sh crea su propio temporal. Como el trap
  # de este archivo es el único registrado, se encadena aquí
  # para que no quede nada suelto en /tmp al terminar.
  # ----------------------------------------------------------

  if declare -F leer_config_cleanup >/dev/null; then
    leer_config_cleanup;
  fi;

}


trap priv_cleanup EXIT;



# ============================================================
# === RESUMEN ===
# ============================================================

echo;
echo "HestiaCP      : $HESTIA_MODO_RESUELTO";
echo "MySQL destino : $MYSQL_DESTINO_AUTH";
echo "MySQL origen  : $MYSQL_ORIGEN_AUTH";
echo "rsync         : $RSYNC_OPTS";


if [ "$PRIV_LOCAL_ES_ROOT" != "true" ]; then

  echo;
  echo "AVISO: ejecutando sin privilegio de root.";
  echo;
  echo "No estarán disponibles:";
  echo "  - chown a otro usuario";
  echo "  - conservación de propietario, ACL y xattrs";
  echo "  - migración de cuentas de correo";
  echo;
  echo "Los archivos deben escribirse en el home del propio";
  echo "usuario que ejecuta este script.";

fi;
