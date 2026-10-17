#!/bin/bash

# ============================================================
# COMPROBACIONES PREVIAS
# ============================================================
#
# Se ejecuta antes del plan, y solo lee.
#
#
# ============================================================
#
# QUÉ COMPRUEBA
#
#   1. Que las plantillas PHP pedidas existan en el destino.
#
#      Si el origen usa PHP-7_4 y el destino no lo tiene
#      instalado, sin esto te enteras a mitad de la fase 1
#      con un E_INVALID y el dominio a medias.
#
#   2. Que quepa.
#
#      Se mide lo que ocupa cada sitio en el origen y se
#      compara con el espacio libre del destino. Un rsync
#      que se queda sin disco deja los archivos truncados.
#
#   3. Qué hay en el origen que esta herramienta NO migra.
#
#      Alias distintos de www, usuarios FTP, plantillas de
#      nginx personalizadas y reglas de proxy. No se tocan,
#      pero conviene saber que están ahí antes de apagar el
#      servidor viejo.
#
#   4. Que el usuario del panel exista, o que se pueda crear.
#
# ============================================================



if ! declare -F origen_exec >/dev/null; then
  echo "ERROR: BASE_PRIVILEGIOS.sh no ha sido cargado.";
  return 1 2>/dev/null || exit 1;
fi;


COMPROBAR_ERRORES=0;

COMPROBAR_AVISOS=0;



# ============================================================
# === PLANTILLAS PHP DISPONIBLES EN EL DESTINO ===
# ============================================================
#
# HestiaCP guarda una plantilla por versión en:
#
#   /usr/local/hestia/data/templates/web/php-fpm/PHP-8_1.tpl
#
# ============================================================

comprobar_php() {

  local dir="/usr/local/hestia/data/templates/web/php-fpm";

  local site;
  local plantilla;
  local vistas="";


  if [ ! -d "$dir" ]; then

    echo "  No se pudo leer el directorio de plantillas PHP.";
    echo "  Se omite esta comprobación.";

    return 0;

  fi;


  for site in "${DOMINIOS[@]}"
  do

    cfg_si "$site" web || continue;

    plantilla="$(cfg "$site" php)";

    [ -z "$plantilla" ] && continue;


    case " $vistas " in
      *" $plantilla "*) continue;;
    esac;

    vistas="$vistas $plantilla";


    if [ -f "$dir/$plantilla.tpl" ]; then

      echo "  $plantilla: disponible";

    else

      echo "  $plantilla: NO EXISTE en este servidor";

      COMPROBAR_ERRORES=$((COMPROBAR_ERRORES + 1));

    fi;

  done;


  if [ "$COMPROBAR_ERRORES" -ne 0 ]; then

    echo;
    echo "  Plantillas instaladas aquí:";

    ls "$dir"/*.tpl 2>/dev/null |
      sed 's|.*/||; s|\.tpl$||' |
      sed 's/^/    /';

  fi;

}



# ============================================================
# === ESPACIO EN DISCO ===
# ============================================================

comprobar_espacio() {

  local site;
  local total=0;
  local tam;


  echo "  Midiendo lo que ocupa en el origen...";


  for site in "${DOMINIOS[@]}"
  do

    cfg_si "$site" web || continue;

    tam="$(
      origen_exec \
        "du -sb $(printf '%q' "$BASE_ORIGEN/$(cfg "$site" origen)/public_html") 2>/dev/null | cut -f1" \
        "" </dev/null 2>/dev/null
    )";

    case "$tam" in
      ''|*[!0-9]*) continue;;
    esac;

    total=$((total + tam));

  done;


  # ----------------------------------------------------------
  # Los buzones también ocupan.
  # ----------------------------------------------------------

  for site in "${DOMINIOS[@]}"
  do

    cfg_si "$site" correo || continue;

    local dom_correo;

    dom_correo="$(cfg "$site" correo_origen)";
    [ -z "$dom_correo" ] && dom_correo="$(cfg "$site" origen)";

    tam="$(
      origen_exec \
        "du -sb /home/$USER_ORIGEN/mail/$(printf '%q' "$dom_correo") 2>/dev/null | cut -f1" \
        "" </dev/null 2>/dev/null
    )";

    case "$tam" in
      ''|*[!0-9]*) continue;;
    esac;

    total=$((total + tam));

  done;


  if [ "$total" -eq 0 ]; then

    echo "  No se pudo medir. Se omite la comprobación.";

    return 0;

  fi;


  local libre;

  libre="$(df -B1 --output=avail "/home" 2>/dev/null | tail -n 1 | tr -d ' ')";

  case "$libre" in
    ''|*[!0-9]*) echo "  No se pudo leer el espacio libre."; return 0;;
  esac;


  local necesario;

  necesario=$((total + total / 5));


  echo "  Ocupa en el origen : $(numfmt --to=iec "$total" 2>/dev/null || echo "$total bytes")";
  echo "  Libre en el destino: $(numfmt --to=iec "$libre" 2>/dev/null || echo "$libre bytes")";


  if [ "$libre" -lt "$necesario" ]; then

    echo;
    echo "  ERROR: no hay espacio suficiente.";
    echo "  Hacen falta al menos $(numfmt --to=iec "$necesario" 2>/dev/null || echo "$necesario bytes"),";
    echo "  contando un 20% de margen para dumps y backups.";

    COMPROBAR_ERRORES=$((COMPROBAR_ERRORES + 1));

  fi;

}



# ============================================================
# === LO QUE NO SE MIGRA ===
# ============================================================
#
# Se lee web.conf del origen, que es donde HestiaCP guarda
# los alias, el usuario FTP y las plantillas de cada dominio.
#
# ============================================================

comprobar_pendientes() {

  local conf;
  local site;
  local linea;
  local alias;
  local ftp;
  local tpl;
  local proxy;
  local hay=0;


  conf="$(
    origen_exec \
      "cat /usr/local/hestia/data/users/$USER_ORIGEN/web.conf" \
      "" </dev/null 2>/dev/null
  )";


  if [ -z "$conf" ]; then

    echo "  No se pudo leer web.conf del origen.";

    return 0;

  fi;


  for site in "${DOMINIOS[@]}"
  do

    cfg_si "$site" web || continue;


    linea="$(
      echo "$conf" | grep -F "DOMAIN='$(cfg "$site" origen)'" | head -n 1
    )";

    [ -z "$linea" ] && continue;


    alias="$(echo "$linea" | grep -oE "ALIAS='[^']*'" | sed "s/ALIAS='//; s/'$//")";
    ftp="$(echo "$linea" | grep -oE "FTP_USER='[^']*'" | sed "s/FTP_USER='//; s/'$//")";
    tpl="$(echo "$linea" | grep -oE "^TPL='[^']*'|[[:space:]]TPL='[^']*'" | sed "s/.*TPL='//; s/'$//")";
    proxy="$(echo "$linea" | grep -oE "PROXY_TPL='[^']*'" | sed "s/PROXY_TPL='//; s/'$//")";


    # --------------------------------------------------------
    # El alias www lo gestiona la clave alias_www, así que no
    # cuenta como pendiente.
    # --------------------------------------------------------

    local otros="";
    local a;

    IFS=',' read -r -a lista <<< "$alias";

    for a in ${lista[@]+"${lista[@]}"}
    do
      [ -z "$a" ] && continue;
      [ "$a" = "www.$(cfg "$site" origen)" ] && continue;
      otros="$otros $a";
    done;


    if [ -n "$otros" ] || [ -n "$ftp" ] ||
       { [ -n "$tpl" ] && [ "$tpl" != "default" ]; } ||
       { [ -n "$proxy" ] && [ "$proxy" != "default" ]; }; then

      hay=1;

      echo;
      echo "  $site";

      [ -n "$otros" ] && echo "    alias:$otros";
      [ -n "$ftp" ] && echo "    usuario FTP: $ftp";

      if [ -n "$tpl" ] && [ "$tpl" != "default" ]; then
        echo "    plantilla web: $tpl";
      fi;

      if [ -n "$proxy" ] && [ "$proxy" != "default" ]; then
        echo "    plantilla proxy: $proxy";
      fi;

      COMPROBAR_AVISOS=$((COMPROBAR_AVISOS + 1));

    fi;

  done;


  if [ "$hay" -eq 0 ]; then

    echo "  Nada. Todo lo que hay en el origen se migra.";

  else

    echo;
    echo "  Esto NO se migra. Si hace falta, hay que crearlo a mano";
    echo "  en el destino antes de apagar el servidor viejo.";

  fi;

}



# ============================================================
# === USUARIO DEL PANEL ===
# ============================================================
#
# Si no existe, la fase 1 lo crea. Para eso hace falta root
# y la CLI de HestiaCP, y que CREAR_USUARIO no sea "false".
#
# ============================================================

comprobar_usuario() {

  local motivo="";


  if usuario_destino_existe; then

    echo "  $USER_DESTINO: existe";

    return 0;

  fi;


  if [ "${CREAR_USUARIO:-true}" = "false" ]; then
    motivo="CREAR_USUARIO=\"false\"";
  elif [ "$PRIV_LOCAL_ES_ROOT" != "true" ]; then
    motivo="sin privilegio de root";
  elif [ "$HESTIA_MODO_RESUELTO" = "api" ]; then
    motivo="en modo API";
  fi;


  if [ -z "$motivo" ]; then

    echo "  $USER_DESTINO: NO EXISTE: se creará en la fase 1";

  else

    echo "  $USER_DESTINO: NO EXISTE y no se puede crear ($motivo)";

    COMPROBAR_ERRORES=$((COMPROBAR_ERRORES + 1));

  fi;

}



# ============================================================
# === EJECUTAR ===
# ============================================================

echo;
echo "============================================================";
echo "COMPROBACIONES PREVIAS";
echo "============================================================";

echo;
echo "Plantillas PHP";
comprobar_php;

echo;
echo "Espacio en disco";
comprobar_espacio;

echo;
echo "Lo que esta herramienta no migra";
comprobar_pendientes;

echo;
echo "Usuario del panel";
comprobar_usuario;


if [ "$COMPROBAR_ERRORES" -ne 0 ]; then

  echo;
  echo "============================================================";
  echo "COMPROBACIONES PREVIAS: $COMPROBAR_ERRORES PROBLEMA(S)";
  echo "============================================================";
  echo;
  echo "No se ha modificado nada.";
  echo;

fi;
