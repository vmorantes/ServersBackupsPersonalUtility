#!/bin/bash

# ============================================================
# CONFIGURACIÓN DECLARATIVA POR DOMINIO
# ============================================================
#
# Define las funciones que permiten describir una migración
# como bloques por dominio en vez de arreglos paralelos.
#
# Lo carga BASE_GENERAL.sh antes del archivo de migración.
#
#
# ============================================================
#
# CÓMO SE USA (en el archivo de migración)
#
#   predeterminados \
#     php="PHP-8_3" \
#     ssl="true";
#
#   dominio "example.org" \
#     bd_origen="antigua_web" \
#     bd="USER_web" \
#     bd_pass="...";
#
#   dominio "tienda.example.org" \
#     php="PHP-7_4" \
#     ssl="false";
#
#
# Cada dominio hereda lo definido en predeterminados y
# solamente declara lo que es distinto.
#
# El orden de los dominios en la migración es el orden en que
# aparecen los bloques.
#
#
# ============================================================
#
# CLAVES DISPONIBLES
#
#   web             si el dominio tiene sitio web
#
#                   En HestiaCP el dominio de correo es
#                   independiente del web: puede haber
#                   buzones sin sitio.
#
#                   Con web="false" no se crea dominio web,
#                   ni PHP, ni se copian archivos, ni SSL.
#                   Solo se migra el correo.
#
#   php             plantilla PHP de HestiaCP
#                   obligatoria salvo con web="false"
#
#   ssl             emitir Let's Encrypt en la fase 2
#   forzar_ssl      redirigir HTTP a HTTPS en la fase 2
#
#   eliminar_dns    eliminar la zona DNS que crea HestiaCP
#   correo          migrar las cuentas de correo del dominio,
#                   con sus contraseñas y sus buzones
#                     auto  = si el origen tiene cuentas
#                     true  = siempre
#                     false = nunca
#
#   correo_origen   nombre del dominio de correo en el
#                   servidor viejo, si allá era distinto
#
#   eliminar_mail   eliminar el dominio de correo que crea
#
#   alias_www       eliminar el alias www
#                     auto  = solo en subdominios
#                     true  = siempre
#                     false = nunca
#
#   bd_origen       nombre REAL de la base en el origen
#
#                   OPCIONAL: si se omite, se lee del archivo
#                   de configuración del servidor viejo. Si se
#                   declara, se contrasta contra ese archivo y
#                   una discrepancia detiene la migración.
#
#   bd_user_origen  usuario que usaba la aplicación en el
#                   servidor viejo. Solo documental: se lee
#                   solo y sirve para dejar constancia del
#                   cambio.
#
#   ruta_db_origen  ruta del archivo de configuración en el
#                   servidor viejo, si allá estaba en otro
#                   sitio (por defecto: la misma que ruta_db)
#
#   bd              nombre CORTO de la base en el destino,
#                   tal como se le pasa a v-add-database
#
#                   HestiaCP le antepone el usuario, así que
#                   bd="tienda" con el usuario "cliente"
#                   produce cliente_tienda
#
#   bd_user         usuario corto (por defecto: igual a bd)
#   bd_pass         contraseña de la base
#
#   bd_sin_prefijo  true si la base ya existe con su nombre
#                   literal y HestiaCP no debe anteponer nada
#                   (bases creadas fuera del panel)
#
#   tipo            aplicación del sitio, que decide qué
#                   archivo de configuración se reescribe:
#
#                     piecesphp     (por defecto)
#                     codeigniter3
#                     wordpress
#                     joomla
#                     prestashop    (1.7 y Symfony)
#                     prestashop16
#                     laravel       (.env)
#                     drupal
#                     ninguno       no reescribir nada
#
#                   Para añadir uno, ver la guía: son tres
#                   sitios, todos con un ejemplo al lado.
#
#                   codeigniter3 lee y reescribe el grupo
#                   'default' de application/config/database.php,
#                   en forma de array o clave a clave. Se niega
#                   si $active_group no es 'default'.
#
#                   Su ruta por defecto supone que application/
#                   cuelga de public_html/. Cuando no es así, se
#                   declara con ruta_db.
#
#                   Y si el proyecto tiene
#                   application/config/<ENTORNO>/database.php,
#                   ESE manda sobre el general: hay que apuntar
#                   ruta_db a él, o se reescribiría el que la
#                   aplicación no usa.
#
#   ruta_db         ruta del archivo de configuración relativa
#                   a la raíz del dominio. Si se omite, se
#                   deriva del tipo.
#
#   origen          carpeta del dominio en el servidor origen,
#                   si allá se llamaba distinto
#
#   chmod           permisos que rsync aplica a este dominio,
#                   en formato de --chmod
#
#                     D755,F644   por defecto
#                     D775,F664   si algo escribe por grupo
#
#                   Solo hace falta cuando quien escribe no
#                   es el dueño de los archivos. Con PHP-FPM
#                   corriendo como el usuario del panel, que
#                   es lo normal en HestiaCP, el valor por
#                   defecto ya permite escribir.
#
#   grupo           grupo del que serán los archivos.
#                   Por defecto, GRUPO_WEB (www-data).
#
#
# Un dominio sin bd no participa en la migración de bases de
# datos ni en la reescritura de database.php.
#
# ============================================================



# ============================================================
# === ALMACENAMIENTO ===
# ============================================================

declare -A CFG_VALORES=();

declare -A BD_VALORES=();

BASES_SUELTAS=();
declare -A CFG_DEFECTOS=();

DOMINIOS=();


CFG_CLAVES="web php tipo correo correo_origen chmod grupo bd_sin_prefijo bd_corto bd_user_corto bd_final bd_user_final ssl forzar_ssl eliminar_dns eliminar_mail alias_www bd_origen bd_user_origen bd bd_user bd_pass ruta_db ruta_db_origen origen";


BD_CLAVES="origen user pass sin_prefijo";

CFG_ERRORES=0;



# ============================================================
# === VALORES DE FÁBRICA ===
# ============================================================
#
# Se aplican cuando ni el dominio ni predeterminados dicen
# nada. Son los valores conservadores: no tocar nada que no
# se haya pedido explícitamente.
#
# ============================================================

CFG_DEFECTOS[ssl]="false";
CFG_DEFECTOS[forzar_ssl]="false";
CFG_DEFECTOS[eliminar_dns]="false";
CFG_DEFECTOS[eliminar_mail]="false";
CFG_DEFECTOS[correo]="auto";
CFG_DEFECTOS[web]="true";
CFG_DEFECTOS[alias_www]="auto";
CFG_DEFECTOS[tipo]="piecesphp";



# ============================================================
# === TIPOS DE APLICACIÓN ===
# ============================================================
#
# El tipo decide dos cosas:
#
#   1. Qué patrón se reescribe dentro del archivo de
#      configuración de la aplicación.
#
#   2. Dónde está ese archivo, si no se declaró ruta_db.
#
#
# Para añadir un tipo hay que tocar dos sitios:
#
#   - la ruta por defecto, aquí abajo
#   - el patrón, en el helper PHP de BASE_CONFIGURAR_DB.sh
#
# ============================================================

declare -A CFG_RUTA_POR_TIPO=();

CFG_RUTA_POR_TIPO[piecesphp]="public_html/app/config/database.php";
CFG_RUTA_POR_TIPO[codeigniter3]="public_html/application/config/database.php";
CFG_RUTA_POR_TIPO[wordpress]="public_html/wp-config.php";
CFG_RUTA_POR_TIPO[joomla]="public_html/configuration.php";
CFG_RUTA_POR_TIPO[prestashop]="public_html/app/config/parameters.php";
CFG_RUTA_POR_TIPO[prestashop16]="public_html/config/settings.inc.php";
CFG_RUTA_POR_TIPO[laravel]="public_html/.env";
CFG_RUTA_POR_TIPO[drupal]="public_html/sites/default/settings.php";
CFG_RUTA_POR_TIPO[ninguno]="";


# ------------------------------------------------------------
# La lista de tipos válidos se deriva de las claves de arriba,
# para no tener que mantener dos listas sincronizadas.
# ------------------------------------------------------------

CFG_TIPOS="$(echo "${!CFG_RUTA_POR_TIPO[@]}" | tr ' ' '\n' | sort | tr '\n' ' ')";



# ============================================================
# === PARSEO DE CLAVE=VALOR ===
# ============================================================

_cfg_asignar() {

  local destino="$1";
  shift;

  local par;
  local clave;
  local valor;

  for par in "$@"
  do

    clave="${par%%=*}";
    valor="${par#*=}";


    if [ "$clave" = "$par" ]; then

      echo "ERROR de configuración: '$par' no tiene la forma clave=valor.";

      CFG_ERRORES=$((CFG_ERRORES + 1));

      continue;

    fi;


    # ------------------------------------------------------
    # Validar la clave contra la lista conocida.
    #
    # Esto atrapa erratas como ssl_forzar= o bd_password=,
    # que de otro modo se ignorarían en silencio.
    # ------------------------------------------------------

    case " $CFG_CLAVES " in

      *" $clave "*)
        ;;

      *)
        echo "ERROR de configuración: clave desconocida '$clave'.";
        echo "  Claves válidas: $CFG_CLAVES";

        CFG_ERRORES=$((CFG_ERRORES + 1));

        continue;
        ;;

    esac;


    if [ "$destino" = "__defecto__" ]; then
      CFG_DEFECTOS[$clave]="$valor";
    else
      CFG_VALORES[$destino|$clave]="$valor";
    fi;

  done;

}



# ============================================================
# === predeterminados ===
# ============================================================
#
#   predeterminados \
#     php="PHP-8_3" \
#     eliminar_mail="true";
#
# Lo que se declare aquí lo heredan todos los dominios
# declarados DESPUÉS.
#
# ============================================================

predeterminados() {

  _cfg_asignar "__defecto__" "$@";

}



# ============================================================
# === dominio ===
# ============================================================
#
#   dominio "example.org" \
#     bd="USER_web" \
#     bd_pass="...";
#
# ============================================================

dominio() {

  local site="$1";

  shift;


  if [ -z "$site" ]; then

    echo "ERROR de configuración: dominio sin nombre.";

    CFG_ERRORES=$((CFG_ERRORES + 1));

    return 1;

  fi;


  # ----------------------------------------------------------
  # Detectar dominios repetidos.
  # ----------------------------------------------------------

  local existente;

  for existente in "${DOMINIOS[@]}"
  do

    if [ "$existente" = "$site" ]; then

      echo "ERROR de configuración: '$site' está declarado dos veces.";

      CFG_ERRORES=$((CFG_ERRORES + 1));

      return 1;

    fi;

  done;


  DOMINIOS+=("$site");


  # ----------------------------------------------------------
  # Congelar los predeterminados vigentes en este punto.
  #
  # Así, si el archivo de migración cambia los predeterminados
  # a mitad de la lista, cada dominio conserva los que había
  # cuando fue declarado.
  # ----------------------------------------------------------

  local clave;

  for clave in $CFG_CLAVES
  do

    if [ -n "${CFG_DEFECTOS[$clave]}" ]; then
      CFG_VALORES[$site|$clave]="${CFG_DEFECTOS[$clave]}";
    fi;

  done;


  _cfg_asignar "$site" "$@";

}



# ============================================================
# === base_de_datos ===
# ============================================================
#
# Para bases que NO cuelgan de ningún dominio: históricas,
# de un cron, de una aplicación externa.
#
#   base_de_datos "legacy" \
#     origen="admin_legacy" \
#     pass="CLAVE";
#
# Claves:
#
#   origen        nombre real en el servidor viejo
#                 OBLIGATORIO: sin dominio no hay archivo de
#                 configuración del que deducirlo
#
#   user          usuario corto (por defecto: igual al nombre)
#   pass          contraseña
#   sin_prefijo   la base ya existe con su nombre literal
#
# No se les reescribe ninguna configuración: no hay
# aplicación asociada que actualizar.
#
# ============================================================

base_de_datos() {

  local nombre="$1";

  shift;


  if [ -z "$nombre" ]; then

    echo "ERROR de configuración: base_de_datos sin nombre.";

    CFG_ERRORES=$((CFG_ERRORES + 1));

    return 1;

  fi;


  local existente;

  for existente in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
  do

    if [ "$existente" = "$nombre" ]; then

      echo "ERROR de configuración: la base '$nombre' está declarada dos veces.";

      CFG_ERRORES=$((CFG_ERRORES + 1));

      return 1;

    fi;

  done;


  BASES_SUELTAS+=("$nombre");


  local par;
  local clave;
  local valor;

  for par in "$@"
  do

    clave="${par%%=*}";
    valor="${par#*=}";


    if [ "$clave" = "$par" ]; then

      echo "ERROR de configuración: '$par' no tiene la forma clave=valor.";

      CFG_ERRORES=$((CFG_ERRORES + 1));

      continue;

    fi;


    case " $BD_CLAVES " in

      *" $clave "*)
        BD_VALORES[$nombre|$clave]="$valor";
        ;;

      *)
        echo "ERROR de configuración: clave desconocida '$clave' en base_de_datos.";
        echo "  Claves válidas: $BD_CLAVES";

        CFG_ERRORES=$((CFG_ERRORES + 1));
        ;;

    esac;

  done;

}


# ------------------------------------------------------------
# Lee una clave de una base suelta.
# ------------------------------------------------------------

bdcfg() {

  echo "${BD_VALORES[$1|$2]}";

}



# ============================================================
# === cfg ===
# ============================================================
#
#   cfg "$site" php
#   cfg "$site" ssl
#
# Devuelve cadena vacía si no hay valor.
#
# ============================================================

cfg() {

  local site="$1";
  local clave="$2";

  echo "${CFG_VALORES[$site|$clave]}";

}


# ------------------------------------------------------------
# Igual que cfg, pero devuelve 0 si el valor es "true".
#
#   if cfg_si "$site" ssl; then ... fi
# ------------------------------------------------------------

cfg_si() {

  [ "$(cfg "$1" "$2")" = "true" ];

}



# ============================================================
# === VALIDACIÓN Y VALORES DERIVADOS ===
# ============================================================
#
# Se llama desde BASE_GENERAL.sh después de cargar el archivo
# de migración.
#
# ============================================================

cfg_validar() {

  local site;
  local faltantes=0;


  if [ "${#DOMINIOS[@]}" -eq 0 ] && [ "${#BASES_SUELTAS[@]}" -eq 0 ]; then

    echo "ERROR de configuración: no hay nada declarado.";

    return 1;

  fi;


  for site in "${DOMINIOS[@]}"
  do

    # --------------------------------------------------------
    # php es obligatorio.
    # --------------------------------------------------------

    if cfg_si "$site" web; then

      if [ -z "$(cfg "$site" php)" ]; then

        echo "ERROR de configuración: '$site' no tiene php definido.";

        faltantes=$((faltantes + 1));

      fi;

    else

      # ------------------------------------------------------
      # Sin sitio web no hay dónde poner archivos ni qué
      # configuración reescribir.
      # ------------------------------------------------------

      if [ -n "$(cfg "$site" bd)" ]; then

        echo "ERROR de configuración: '$site' tiene web=false pero declara bd.";
        echo "  Sin sitio web no hay archivo de configuración que reescribir.";

        faltantes=$((faltantes + 1));

      fi;


      if [ "$(cfg "$site" correo)" = "false" ]; then

        echo "ERROR de configuración: '$site' tiene web=false y correo=false.";
        echo "  No habría nada que migrar para este dominio.";

        faltantes=$((faltantes + 1));

      fi;


      if cfg_si "$site" ssl || cfg_si "$site" forzar_ssl; then

        echo "AVISO: '$site' tiene web=false, así que ssl no se aplica.";

      fi;

    fi;


    # --------------------------------------------------------
    # El tipo debe ser conocido.
    # --------------------------------------------------------

    local tipo;

    tipo="$(cfg "$site" tipo)";

    case " $CFG_TIPOS " in

      *" $tipo "*)
        ;;

      *)
        echo "ERROR de configuración: '$site' tiene un tipo desconocido: '$tipo'.";
        echo "  Tipos válidos: $CFG_TIPOS";

        faltantes=$((faltantes + 1));
        ;;

    esac;


    # --------------------------------------------------------
    # Si no se declaró ruta_db, se deriva del tipo.
    # --------------------------------------------------------

    if [ -z "$(cfg "$site" ruta_db)" ]; then
      CFG_VALORES[$site|ruta_db]="${CFG_RUTA_POR_TIPO[$tipo]}";
    fi;


    # --------------------------------------------------------
    # Un sitio con base de datos y tipo ninguno es válido: se
    # migran los datos pero la configuración se aplica a mano.
    # --------------------------------------------------------

    if [ "$tipo" = "ninguno" ] && [ -n "$(cfg "$site" bd)" ]; then

      echo "AVISO: '$site' migrará su base pero tiene tipo=ninguno.";
      echo "  Habrá que escribir las credenciales nuevas a mano.";

    fi;


    # --------------------------------------------------------
    # Si hay base de datos, el usuario por defecto es el mismo
    # nombre de la base, que es lo habitual en HestiaCP.
    # --------------------------------------------------------

    if [ -n "$(cfg "$site" bd)" ]; then

      if [ -z "$(cfg "$site" bd_user)" ]; then
        CFG_VALORES[$site|bd_user]="$(cfg "$site" bd)";
      fi;


      # ------------------------------------------------------
      # HestiaCP antepone el usuario del panel al nombre de la
      # base y al del usuario de base de datos.
      #
      # Por eso hay dos nombres distintos:
      #
      #   bd        el corto, que recibe v-add-database
      #   bd_final  el real, que necesitan el import y la
      #             configuración de la aplicación
      #
      # Si el nombre ya viene con el prefijo, no se duplica.
      # ------------------------------------------------------

      local declarado;
      local declarado_user;

      declarado="$(cfg "$site" bd)";
      declarado_user="$(cfg "$site" bd_user)";


      if [ "$(cfg "$site" bd_sin_prefijo)" = "true" ]; then

        # ----------------------------------------------------
        # La base no lleva prefijo: corto y final coinciden.
        # ----------------------------------------------------

        CFG_VALORES[$site|bd_corto]="$declarado";
        CFG_VALORES[$site|bd_user_corto]="$declarado_user";

        CFG_VALORES[$site|bd_final]="$declarado";
        CFG_VALORES[$site|bd_user_final]="$declarado_user";

      else

        # ----------------------------------------------------
        # HestiaCP SIEMPRE antepone el usuario del panel a lo
        # que reciba v-add-database, sin comprobar si ya lo
        # lleva.
        #
        # Por eso hay que guardar los dos nombres:
        #
        #   bd_corto  lo que recibe v-add-database
        #   bd_final  como queda de verdad en MySQL
        #
        # Si lo declarado ya trae el prefijo, se le quita para
        # obtener el corto. Pasárselo con prefijo a Hestia
        # crearía usuario_usuario_base.
        # ----------------------------------------------------

        case "$declarado" in
          "${USER_DESTINO}_"*)
            CFG_VALORES[$site|bd_corto]="${declarado#${USER_DESTINO}_}";
            CFG_VALORES[$site|bd_final]="$declarado";
            ;;
          *)
            CFG_VALORES[$site|bd_corto]="$declarado";
            CFG_VALORES[$site|bd_final]="${USER_DESTINO}_${declarado}";
            ;;
        esac;

        case "$declarado_user" in
          "${USER_DESTINO}_"*)
            CFG_VALORES[$site|bd_user_corto]="${declarado_user#${USER_DESTINO}_}";
            CFG_VALORES[$site|bd_user_final]="$declarado_user";
            ;;
          *)
            CFG_VALORES[$site|bd_user_corto]="$declarado_user";
            CFG_VALORES[$site|bd_user_final]="${USER_DESTINO}_${declarado_user}";
            ;;
        esac;

      fi;


      # ------------------------------------------------------
      # bd_origen es OPCIONAL.
      #
      # Si no se declara, se lee del archivo de configuración
      # del servidor viejo antes de empezar la migración.
      #
      # La única excepción es tipo=ninguno, donde no hay
      # archivo que leer; eso se valida en ese momento.
      # ------------------------------------------------------

      if [ -z "$(cfg "$site" bd_pass)" ]; then

        echo "ERROR de configuración: '$site' tiene bd pero no bd_pass.";

        faltantes=$((faltantes + 1));

      fi;

    fi;


    # --------------------------------------------------------
    # correo y eliminar_mail se contradicen.
    # --------------------------------------------------------

    if cfg_si "$site" correo && cfg_si "$site" eliminar_mail; then

      echo "ERROR de configuración: '$site' tiene correo y eliminar_mail.";
      echo "  Uno migra las cuentas y el otro borra el dominio de correo.";

      faltantes=$((faltantes + 1));

    fi;


    # --------------------------------------------------------
    # forzar_ssl sin ssl no tiene sentido.
    # --------------------------------------------------------

    if cfg_si "$site" forzar_ssl && ! cfg_si "$site" ssl; then

      echo "AVISO: '$site' tiene forzar_ssl pero no ssl.";
      echo "  No se forzará HTTPS.";

    fi;


    # --------------------------------------------------------
    # Permisos y grupo: si el dominio no dice nada, hereda lo
    # global de BASE_PRIVILEGIOS.sh.
    # --------------------------------------------------------

    if [ -z "$(cfg "$site" chmod)" ]; then
      CFG_VALORES[$site|chmod]="${RSYNC_CHMOD:-D755,F644}";
    fi;


    if [ -z "$(cfg "$site" grupo)" ]; then
      CFG_VALORES[$site|grupo]="${GRUPO_WEB:-www-data}";
    fi;


    # --------------------------------------------------------
    # La carpeta en el origen, si no se dijo otra cosa, es la
    # misma que el dominio.
    # --------------------------------------------------------

    if [ -z "$(cfg "$site" origen)" ]; then
      CFG_VALORES[$site|origen]="$site";
    fi;

  done;


  # ----------------------------------------------------------
  # Bases sueltas.
  # ----------------------------------------------------------

  local base;

  for base in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
  do

    if [ -z "$(bdcfg "$base" origen)" ]; then

      echo "ERROR de configuración: la base '$base' no declara origen.";
      echo "  Al no colgar de un dominio, no hay archivo del que deducirlo.";

      faltantes=$((faltantes + 1));

    fi;


    if [ -z "$(bdcfg "$base" pass)" ]; then

      echo "ERROR de configuración: la base '$base' no declara pass.";

      faltantes=$((faltantes + 1));

    fi;


    if [ -z "$(bdcfg "$base" user)" ]; then
      BD_VALORES[$base|user]="$base";
    fi;


    # --------------------------------------------------------
    # Mismo trato del prefijo que en los dominios.
    # --------------------------------------------------------

    local bcorto;
    local bcorto_user;

    bcorto="$base";
    bcorto_user="$(bdcfg "$base" user)";


    if [ "$(bdcfg "$base" sin_prefijo)" = "true" ]; then

      BD_VALORES[$base|corto]="$bcorto";
      BD_VALORES[$base|user_corto]="$bcorto_user";
      BD_VALORES[$base|final]="$bcorto";
      BD_VALORES[$base|user_final]="$bcorto_user";

    else

      case "$bcorto" in
        "${USER_DESTINO}_"*)
          BD_VALORES[$base|corto]="${bcorto#${USER_DESTINO}_}";
          BD_VALORES[$base|final]="$bcorto";
          ;;
        *)
          BD_VALORES[$base|corto]="$bcorto";
          BD_VALORES[$base|final]="${USER_DESTINO}_${bcorto}";
          ;;
      esac;

      case "$bcorto_user" in
        "${USER_DESTINO}_"*)
          BD_VALORES[$base|user_corto]="${bcorto_user#${USER_DESTINO}_}";
          BD_VALORES[$base|user_final]="$bcorto_user";
          ;;
        *)
          BD_VALORES[$base|user_corto]="$bcorto_user";
          BD_VALORES[$base|user_final]="${USER_DESTINO}_${bcorto_user}";
          ;;
      esac;

    fi;

  done;


  if [ "$CFG_ERRORES" -ne 0 ] || [ "$faltantes" -ne 0 ]; then

    echo;
    echo "La configuración tiene errores. No se ejecuta nada.";

    return 1;

  fi;


  return 0;

}


# ------------------------------------------------------------
# Deja solo los dominios y bases pedidos por argumento.
#
# Sirve para repetir lo que falló sin volver a pasar por todo
# lo demás.
#
# Un nombre que no exista es un error: es más probable que
# sea una errata que una intención.
# ------------------------------------------------------------

cfg_filtrar() {

  local -n pedidos_dom="$1";
  local -n pedidos_bd="$2";

  local d;
  local b;
  local p;
  local encontrado;
  local errores=0;

  local nuevos_dom=();
  local nuevas_bd=();


  for p in ${pedidos_dom[@]+"${pedidos_dom[@]}"}
  do

    encontrado="no";

    for d in ${DOMINIOS[@]+"${DOMINIOS[@]}"}
    do
      if [ "$d" = "$p" ]; then
        nuevos_dom+=("$d");
        encontrado="si";
      fi;
    done;

    if [ "$encontrado" = "no" ]; then
      echo "ERROR: --dominio $p no está en la migración.";
      errores=$((errores + 1));
    fi;

  done;


  for p in ${pedidos_bd[@]+"${pedidos_bd[@]}"}
  do

    encontrado="no";

    for b in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
    do
      if [ "$b" = "$p" ]; then
        nuevas_bd+=("$b");
        encontrado="si";
      fi;
    done;

    if [ "$encontrado" = "no" ]; then
      echo "ERROR: --base $p no está en la migración.";
      errores=$((errores + 1));
    fi;

  done;


  if [ "$errores" -ne 0 ]; then

    echo;
    echo "Declarados en la migración:";

    for d in ${DOMINIOS[@]+"${DOMINIOS[@]}"}; do
      echo "  --dominio $d";
    done;

    for b in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}; do
      echo "  --base $b";
    done;

    return 1;

  fi;


  DOMINIOS=(${nuevos_dom[@]+"${nuevos_dom[@]}"});
  BASES_SUELTAS=(${nuevas_bd[@]+"${nuevas_bd[@]}"});


  echo;
  echo "FILTRO ACTIVO: solo se procesará lo pedido por argumento.";

  for d in ${DOMINIOS[@]+"${DOMINIOS[@]}"}; do
    echo "  dominio $d";
  done;

  for b in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}; do
    echo "  base $b";
  done;

  return 0;

}


# ------------------------------------------------------------
# Construye el arreglo DBS que consumen BASE_MIGRAR_DB.sh y
# BASE_CONFIGURAR_DB.sh.
#
# Formato:
#
#   DOMINIO|BD_ORIGEN|BD_DESTINO|USUARIO|PASSWORD
#
# Los dominios sin bd quedan fuera.
# ------------------------------------------------------------

cfg_construir_dbs() {

  local site;

  DBS=();

  for site in "${DOMINIOS[@]}"
  do

    if [ -z "$(cfg "$site" bd)" ]; then
      continue;
    fi;

    DBS+=(
      "$site|$(cfg "$site" bd_origen)|$(cfg "$site" bd_final)|$(cfg "$site" bd_user_final)|$(cfg "$site" bd_pass)"
    );

  done;


  # ----------------------------------------------------------
  # Las bases sueltas van con el sitio marcado con @.
  #
  # Ese marcador es lo que permite al resto de los módulos
  # distinguirlas: no tienen public_html, ni configuración
  # que reescribir, y sus logs van a otra carpeta.
  # ----------------------------------------------------------

  local base;

  for base in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
  do

    DBS+=(
      "@$base|$(bdcfg "$base" origen)|$(bdcfg "$base" final)|$(bdcfg "$base" user_final)|$(bdcfg "$base" pass)"
    );

  done;

}


# ------------------------------------------------------------
# Resuelve correo="auto" en true o false.
#
# Se migra el correo si el origen tiene cuentas en el
# dominio. Sin root no se puede migrar correo, y con
# eliminar_mail se va a borrar el dominio de correo.
#
# Lo llama BASE_GENERAL.sh solo en plan y en la fase 1. En
# las demás fases "auto" no es "true", así que no se migra.
# ------------------------------------------------------------

cfg_resolver_correo() {

  local site;
  local dom;
  local cuentas;


  for site in "${DOMINIOS[@]}"
  do

    [ "$(cfg "$site" correo)" = "auto" ] || continue;


    if cfg_si "$site" eliminar_mail; then

      CFG_VALORES["$site|correo"]="false";

      continue;

    fi;


    if [ "$PRIV_LOCAL_ES_ROOT" != "true" ]; then

      CFG_VALORES["$site|correo"]="false";

      echo "AVISO: '$site' tiene correo=auto pero sin root no se puede migrar correo.";

      continue;

    fi;


    dom="$(cfg "$site" correo_origen)";

    if [ -z "$dom" ]; then
      dom="$(cfg "$site" origen)";
    fi;


    cuentas="$(
      origen_exec \
        "cat $(printf '%q' "/home/$USER_ORIGEN/conf/mail/$dom/passwd")" \
        "" </dev/null 2>/dev/null |
      grep -v '^[[:space:]]*#' |
      grep -c '[^[:space:]]'
    )";


    if [ "${cuentas:-0}" -gt 0 ]; then

      CFG_VALORES["$site|correo"]="true";

      echo "  $site: correo auto -> sí ($cuentas cuentas)";

    else

      CFG_VALORES["$site|correo"]="false";

      echo "  $site: correo auto -> no (sin cuentas)";

    fi;

  done;

}


# ------------------------------------------------------------
# Muestra la configuración resuelta de cada dominio.
#
# Sirve para revisar qué se va a hacer antes de ejecutar.
# ------------------------------------------------------------

cfg_resumen() {

  local site;

  for site in "${DOMINIOS[@]}"
  do

    echo;
    echo "  $site";


    # --------------------------------------------------------
    # Un dominio solo de correo no tiene PHP, ni SSL, ni
    # archivos: mostrar todo eso solo confunde.
    # --------------------------------------------------------

    if ! cfg_si "$site" web; then

      echo "    web           : NO (solo correo)";
      echo "    correo        : $(cfg "$site" correo)";
      echo "    origen        : $(cfg "$site" origen)";

      if [ -n "$(cfg "$site" correo_origen)" ]; then
        echo "    correo_origen : $(cfg "$site" correo_origen)";
      fi;

      continue;

    fi;


    echo "    php           : $(cfg "$site" php)";
    echo "    tipo          : $(cfg "$site" tipo)";
    echo "    ssl           : $(cfg "$site" ssl)";
    echo "    forzar_ssl    : $(cfg "$site" forzar_ssl)";
    echo "    eliminar_dns  : $(cfg "$site" eliminar_dns)";
    echo "    eliminar_mail : $(cfg "$site" eliminar_mail)";
    echo "    correo        : $(cfg "$site" correo)";
    echo "    alias_www     : $(cfg "$site" alias_www)";
    echo "    origen        : $(cfg "$site" origen)";
    echo "    chmod         : $(cfg "$site" chmod)  grupo $(cfg "$site" grupo)";

    if [ -n "$(cfg "$site" bd)" ]; then
      if [ -n "$(cfg "$site" bd_origen)" ]; then
        echo "    bd            : $(cfg "$site" bd_origen) -> $(cfg "$site" bd_final)";
      else
        echo "    bd            : (se leerá del origen) -> $(cfg "$site" bd_final)";
      fi;

      echo "    bd_user       : $(cfg "$site" bd_user_final)";
      echo "    bd_pass       : [NO SE MUESTRA]";
      echo "    ruta_db       : $(cfg "$site" ruta_db)";
    else
      echo "    bd            : sin base de datos";
    fi;

  done;


  # ----------------------------------------------------------
  # Bases que no cuelgan de ningún dominio.
  # ----------------------------------------------------------

  local base;

  for base in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
  do

    echo;
    echo "  [base suelta] $base";
    echo "    bd            : $(bdcfg "$base" origen) -> $(bdcfg "$base" final)";
    echo "    bd_user       : $(bdcfg "$base" user_final)";
    echo "    pass          : [NO SE MUESTRA]";

  done;

}
