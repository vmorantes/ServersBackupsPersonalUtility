#!/bin/bash

# ============================================================
# MIGRACIÓN DE CORREO
# ============================================================
#
# ESTE ARCHIVO ES INVOCADO DESDE:
#
#   BASE_GENERAL.sh
#
# NO debe ejecutarse de forma independiente.
#
#
# ============================================================
#
# QUÉ MIGRA
#
#   - el dominio de correo
#   - todas las cuentas, con su nombre
#   - la CONTRASEÑA de cada cuenta, sin cambiarla
#   - alias de cuenta
#   - reenvíos
#   - cuota
#   - los buzones completos (Maildir)
#
#
# ============================================================
#
# CÓMO SE CONSERVAN LAS CONTRASEÑAS
#
#   No se pueden recuperar: HestiaCP solo guarda el hash.
#
#   Pero el hash se puede trasplantar. Dovecot lee un archivo
#   passwd donde cada línea lleva su propio esquema entre
#   llaves:
#
#     cuenta:{MD5-CRYPT}$1$abc$def:1001:1001::/home/...
#
#   Y acepta esquemas mezclados en el mismo archivo, así que
#   el hash del servidor viejo funciona en el nuevo aunque
#   allá usaran otro algoritmo.
#
#   El procedimiento es:
#
#     1. Crear la cuenta con una contraseña aleatoria de
#        usar y tirar.
#
#     2. Sustituir el hash de esa línea por el del servidor
#        viejo.
#
#   La contraseña aleatoria nunca llega a servir para nada:
#   se pisa inmediatamente. Por eso no importa que
#   v-add-mail-account la reciba como argumento.
#
#   Resultado: los usuarios no tienen que tocar su cliente
#   de correo.
#
#
# ============================================================
#
# REQUISITOS
#
#   Privilegio de root en AMBOS servidores.
#
#   El archivo passwd y los buzones no son legibles de otro
#   modo, así que el perfil sin root no puede migrar correo.
#
# ============================================================



if ! declare -F origen_exec >/dev/null; then
  echo "ERROR: BASE_PRIVILEGIOS.sh no ha sido cargado.";
  return 1 2>/dev/null || exit 1;
fi;



# ============================================================
# === OPCIONES ===
# ============================================================

# ------------------------------------------------------------
# Conservar las contraseñas trasplantando el hash.
#
# En "false" cada cuenta queda con una contraseña aleatoria
# que habría que comunicar a cada usuario. Casi nunca es lo
# que se quiere.
# ------------------------------------------------------------

MAIL_CONSERVAR_PASSWORD="${MAIL_CONSERVAR_PASSWORD:-true}";


# ------------------------------------------------------------
# Copiar los buzones.
#
# En "false" se crean las cuentas vacías. Útil si el correo
# se va a descargar por IMAP desde el cliente.
# ------------------------------------------------------------

MAIL_COPIAR_BUZONES="${MAIL_COPIAR_BUZONES:-true}";



# ============================================================
# === COMPROBAR PRIVILEGIO ===
# ============================================================

if [ "$PRIV_LOCAL_ES_ROOT" != "true" ]; then

  echo;
  echo "ERROR: la migración de correo necesita privilegio de root.";
  echo;
  echo "El archivo de contraseñas y los buzones no son legibles";
  echo "de otro modo.";
  echo;

  return 1 2>/dev/null || exit 1;

fi;



# ============================================================
# === RUTAS ===
# ============================================================

MAIL_CONF_ORIGEN="/home/$USER_ORIGEN/conf/mail";
MAIL_CONF_DESTINO="/home/$USER_DESTINO/conf/mail";

MAIL_DATOS_ORIGEN="/home/$USER_ORIGEN/mail";
MAIL_DATOS_DESTINO="/home/$USER_DESTINO/mail";

MAIL_META_ORIGEN="/usr/local/hestia/data/users/$USER_ORIGEN/mail";



# ============================================================
# === FUNCIONES ===
# ============================================================

# ------------------------------------------------------------
# Contraseña aleatoria de usar y tirar.
#
# Solo tiene que pasar la política de HestiaCP. Se sustituye
# por el hash real inmediatamente después.
# ------------------------------------------------------------

mail_password_temporal() {

  local base;

  base="$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-20)";

  echo "${base}Aa1.";

}


# ------------------------------------------------------------
# Extrae un valor del .conf de HestiaCP.
#
#   mail_valor "$linea" ALIAS
#
# El formato es CLAVE='valor' CLAVE2='valor2'
# ------------------------------------------------------------

mail_valor() {

  echo "$1" |
  grep -oE "$2='[^']*'" |
  head -n 1 |
  sed -E "s/^$2='//; s/'$//";

}


# ------------------------------------------------------------
# Sustituye el hash de una cuenta en el passwd del destino.
#
# Se cambia únicamente el segundo campo de la línea que
# corresponde a esa cuenta. El resto (uid, gid, home, cuota)
# lo dejó bien v-add-mail-account y no se toca.
# ------------------------------------------------------------

mail_trasplantar_hash() {

  local archivo="$1";
  local cuenta="$2";
  local hash="$3";

  local tmp;

  tmp="$(mktemp)";


  awk -F: -v acc="$cuenta" -v h="$hash" '
    BEGIN { OFS = ":" }
    $1 == acc { $2 = h }
    { print }
  ' "$archivo" > "$tmp";


  if [ "$?" -ne 0 ] || [ ! -s "$tmp" ]; then

    rm -f "$tmp";

    return 1;

  fi;


  # --------------------------------------------------------
  # Se conservan dueño y permisos del archivo original.
  # --------------------------------------------------------

  cat "$tmp" > "$archivo";

  rm -f "$tmp";

  return 0;

}



# ============================================================
# === PROCESAR CADA DOMINIO ===
# ============================================================

MAIL_ERRORES=0;


for site in "${DOMINIOS[@]}"
do

  if ! cfg_si "$site" correo; then
    continue;
  fi;


  DOM_ORIGEN="$(cfg "$site" correo_origen)";

  if [ -z "$DOM_ORIGEN" ]; then
    DOM_ORIGEN="$(cfg "$site" origen)";
  fi;


  echo;
  echo "============================================================";
  echo "CORREO: $site";
  echo "============================================================";

  if [ "$DOM_ORIGEN" != "$site" ]; then
    echo "  Dominio en el origen: $DOM_ORIGEN";
  fi;


  PASSWD_ORIGEN="$MAIL_CONF_ORIGEN/$DOM_ORIGEN/passwd";

  CONF_ORIGEN="$MAIL_META_ORIGEN/$DOM_ORIGEN.conf";


  # ==========================================================
  # === LEER LAS CUENTAS DEL ORIGEN ===
  # ==========================================================

  PASSWD_CONTENIDO="$(
    origen_exec "cat $(printf '%q' "$PASSWD_ORIGEN")" "" </dev/null 2>/dev/null
  )";


  if [ -z "$PASSWD_CONTENIDO" ]; then

    echo "  No hay cuentas de correo, o no se pudo leer:";
    echo "    $PASSWD_ORIGEN";

    continue;

  fi;


  CONF_CONTENIDO="$(
    origen_exec "cat $(printf '%q' "$CONF_ORIGEN")" "" </dev/null 2>/dev/null
  )";


  NUM_CUENTAS="$(echo "$PASSWD_CONTENIDO" | grep -c ':')";

  echo "  Cuentas encontradas: $NUM_CUENTAS";


  # ==========================================================
  # === CREAR EL DOMINIO DE CORREO ===
  # ==========================================================

  hestia v-add-mail-domain "$USER_DESTINO" "$site";

  CODIGO=$?;

  if [ "$CODIGO" -ne 0 ] && [ "$CODIGO" -ne 4 ]; then

    echo "  ERROR al crear el dominio de correo: $(hestia_texto "$CODIGO")";

    MAIL_ERRORES=$((MAIL_ERRORES + 1));

    continue;

  fi;


  PASSWD_DESTINO="$MAIL_CONF_DESTINO/$site/passwd";


  # ==========================================================
  # === CREAR CADA CUENTA ===
  # ==========================================================

  while IFS= read -r linea
  do

    case "$linea" in
      ''|\#*) continue;;
    esac;


    CUENTA="${linea%%:*}";

    RESTO="${linea#*:}";

    HASH="${RESTO%%:*}";


    if [ -z "$CUENTA" ] || [ -z "$HASH" ]; then
      continue;
    fi;


    echo;
    echo "  $CUENTA@$site";


    # --------------------------------------------------------
    # Metadatos de esta cuenta en el .conf del origen.
    # --------------------------------------------------------

    LINEA_CONF="$(
      echo "$CONF_CONTENIDO" | grep -F "ACCOUNT='$CUENTA'" | head -n 1
    )";

    QUOTA="$(mail_valor "$LINEA_CONF" QUOTA)";
    ALIASES="$(mail_valor "$LINEA_CONF" ALIAS)";
    FWD="$(mail_valor "$LINEA_CONF" FWD)";


    if [ -z "$QUOTA" ]; then
      QUOTA="unlimited";
    fi;


    # --------------------------------------------------------
    # Crear la cuenta con una contraseña de usar y tirar.
    # --------------------------------------------------------

    TEMPORAL="$(mail_password_temporal)";

    hestia v-add-mail-account \
      "$USER_DESTINO" \
      "$site" \
      "$CUENTA" \
      "$TEMPORAL" \
      "$QUOTA";

    CODIGO=$?;

    TEMPORAL="";


    if [ "$CODIGO" -ne 0 ] && [ "$CODIGO" -ne 4 ]; then

      echo "    ERROR: $(hestia_texto "$CODIGO")";

      MAIL_ERRORES=$((MAIL_ERRORES + 1));

      continue;

    fi;


    if [ "$CODIGO" -eq 4 ]; then
      echo "    la cuenta ya existía";
    else
      echo "    creada, cuota $QUOTA";
    fi;


    # --------------------------------------------------------
    # Trasplantar el hash.
    # --------------------------------------------------------

    if [ "$MAIL_CONSERVAR_PASSWORD" = "true" ]; then

      if [ ! -f "$PASSWD_DESTINO" ]; then

        echo "    ERROR: no existe $PASSWD_DESTINO";

        MAIL_ERRORES=$((MAIL_ERRORES + 1));

      elif mail_trasplantar_hash "$PASSWD_DESTINO" "$CUENTA" "$HASH"; then

        echo "    contraseña conservada";

      else

        echo "    ERROR: no se pudo conservar la contraseña.";
        echo "    La cuenta queda con una contraseña aleatoria.";

        MAIL_ERRORES=$((MAIL_ERRORES + 1));

      fi;

    fi;


    # --------------------------------------------------------
    # Alias de la cuenta.
    # --------------------------------------------------------

    if [ -n "$ALIASES" ]; then

      IFS=',' read -r -a LISTA_ALIAS <<< "$ALIASES";

      for al in "${LISTA_ALIAS[@]}"
      do

        [ -z "$al" ] && continue;

        hestia v-add-mail-account-alias \
          "$USER_DESTINO" "$site" "$CUENTA" "$al" >/dev/null 2>&1;

        echo "    alias: $al";

      done;

    fi;


    # --------------------------------------------------------
    # Reenvíos.
    # --------------------------------------------------------

    if [ -n "$FWD" ]; then

      IFS=',' read -r -a LISTA_FWD <<< "$FWD";

      for fw in "${LISTA_FWD[@]}"
      do

        [ -z "$fw" ] && continue;

        hestia v-add-mail-account-forward \
          "$USER_DESTINO" "$site" "$CUENTA" "$fw" >/dev/null 2>&1;

        echo "    reenvío: $fw";

      done;

    fi;

  done <<< "$PASSWD_CONTENIDO";


  # ==========================================================
  # === COPIAR LOS BUZONES ===
  # ==========================================================
  #
  # Sin --chmod ni --no-o: los permisos y la estructura del
  # Maildir vienen bien del origen, que también es HestiaCP.
  #
  # ==========================================================

  if [ "$MAIL_COPIAR_BUZONES" = "true" ]; then

    echo;
    echo "  Copiando buzones...";

    mkdir -p "$MAIL_DATOS_DESTINO/$site";


    LOG_BUZONES="$DIR_CORRIDA/${site}_buzones.log";


    rsync -aHAX --numeric-ids \
      -e "$RSYNC_SSH" \
      --info=progress2 \
      --log-file="$LOG_BUZONES" \
      --rsync-path="$RSYNC_PATH_REMOTO" \
      "$SSH_TARGET:$MAIL_DATOS_ORIGEN/$DOM_ORIGEN/" \
      "$MAIL_DATOS_DESTINO/$site/";


    if [ "$?" -ne 0 ]; then

      echo "  ERROR: falló la copia de los buzones.";

      MAIL_ERRORES=$((MAIL_ERRORES + 1));

    else

      # ------------------------------------------------------
      # Los uid/gid del origen no valen aquí.
      # ------------------------------------------------------

      "${priv_local[@]}" chown -R \
        "$USER_DESTINO":mail \
        "$MAIL_DATOS_DESTINO/$site" 2>/dev/null;

      ENVIADOS="$(grep -c ' >f' "$LOG_BUZONES" 2>/dev/null)";

      echo "  Buzones copiados ($ENVIADOS archivos).";

      {
        echo;
        echo "RESUMEN";
        echo "  archivos transferidos : $ENVIADOS";
        echo "  origen  : $SSH_TARGET:$MAIL_DATOS_ORIGEN/$DOM_ORIGEN/";
        echo "  destino : $MAIL_DATOS_DESTINO/$site/";
      } >> "$LOG_BUZONES";

    fi;

  fi;

done;



# ============================================================
# === RESUMEN ===
# ============================================================

echo;
echo "============================================================";

if [ "$MAIL_ERRORES" -eq 0 ]; then

  echo "CORREO MIGRADO";
  echo "============================================================";
  echo;
  echo "Las contraseñas son las mismas de antes: los usuarios no";
  echo "tienen que tocar su cliente de correo.";
  echo;
  echo "############################################################";
  echo "###  FALTA UN PASO MANUAL: EL DNS DEL CORREO             ###";
  echo "############################################################";
  echo;
  echo "La clave DKIM de este servidor es NUEVA. Mientras no se";
  echo "publique, el correo saliente irá fallando autenticación y";
  echo "acabará en spam.";
  echo;
  echo "Hay que actualizar, donde tengas el DNS:";
  echo;
  echo "  MX     -> $IP_DESTINO";
  echo "  SPF    -> incluir $IP_DESTINO";
  echo "  DKIM   -> la clave de abajo";
  echo "  DMARC  -> revisar que siga valiendo";
  echo;


  for site in "${DOMINIOS[@]}"
  do

    cfg_si "$site" correo || continue;


    PUB="$MAIL_CONF_DESTINO/$site/dkim.pub";

    echo "------------------------------------------------------------";
    echo "$site";
    echo "------------------------------------------------------------";


    if [ -f "$PUB" ]; then

      echo;
      echo "  registro: mail._domainkey.$site   TXT";
      echo;
      echo "  v=DKIM1; k=rsa; p=$(grep -v '^-' "$PUB" | tr -d '\n')";
      echo;

    else

      echo;
      echo "  No se encontró la clave en:";
      echo "  $PUB";
      echo;
      echo "  Se puede consultar con:";
      echo "    v-list-mail-domain-dkim $USER_DESTINO $site";
      echo;

    fi;

  done;

  echo "############################################################";
  echo;

else

  echo "CORREO: $MAIL_ERRORES PROBLEMA(S)";
  echo "============================================================";
  echo;

fi;
