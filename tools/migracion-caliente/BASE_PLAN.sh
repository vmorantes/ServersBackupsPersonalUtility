#!/bin/bash

# ============================================================
# PLAN DE EJECUCIÓN
# ============================================================
#
# Muestra, operación por operación, todo lo que va a pasar.
#
# Se usa de dos formas:
#
#   FASE="plan"    solo muestra el plan y termina
#
#   FASE="1" o "2" muestra el plan y pide confirmación
#                  antes de ejecutar nada
#
#
# Para ejecutar sin preguntar (tareas automatizadas):
#
#   CONFIRMAR="false";
#
#
# ============================================================
#
# El plan consulta el estado actual del servidor destino para
# distinguir lo que se creará de lo que ya existe. Esa consulta
# es de solo lectura.
#
# Las operaciones que destruyen datos se listan aparte al
# final, porque son las que conviene mirar dos veces.
#
# ============================================================



PLAN_DESTRUCTIVAS=();



# ------------------------------------------------------------
# ¿Existe ya el dominio en HestiaCP?
# ------------------------------------------------------------

plan_dominio_existe() {

  local site="$1";
  local salida;

  salida="$(hestia_salida v-list-web-domain "$USER_DESTINO" "$site" json 2>/dev/null)";

  # Cuando el dominio NO existe, HestiaCP contesta por la salida
  # ESTÁNDAR "Error: web domain <dominio> doesn't exist", que lleva
  # el nombre dentro: buscarlo a secas daba "existe" para todo
  # dominio nuevo. En la ficha json el nombre es una clave, y va
  # entre comillas dobles; en el mensaje de error, sin comillas.
  # grep -F porque el punto del dominio no es un comodín.

  case "$salida" in
    ""|Error:*) return 1;;
  esac;

  if printf '%s\n' "$salida" | grep -qF "\"$site\""; then
    return 0;
  fi;

  return 1;

}


# ------------------------------------------------------------
# ¿Existe ya el usuario del panel en el destino?
# ------------------------------------------------------------

usuario_destino_existe() {

  if [ "$HESTIA_MODO_RESUELTO" = "api" ]; then

    [ -n "$(hestia_salida v-list-user "$USER_DESTINO" json 2>/dev/null)" ];

    return $?;

  fi;

  test -f "/usr/local/hestia/data/users/$USER_DESTINO/user.conf";

}


# ------------------------------------------------------------
# ¿Existe ya la base de datos?
# ------------------------------------------------------------

plan_base_existe() {

  local db="$1";
  local existe;

  existe="$(
    sql_destino <<SQL
SELECT SCHEMA_NAME FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME = '${db//\'/\'\'}';
SQL
  )";

  [ -n "$existe" ];

}


# ------------------------------------------------------------
# Cuenta las tablas de una base, para avisar de lo que se va
# a borrar.
# ------------------------------------------------------------

plan_tablas_en() {

  local db="$1";

  sql_destino <<SQL
SELECT COUNT(*) FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '${db//\'/\'\'}';
SQL

}



# ============================================================
# === PLAN ===
# ============================================================

mostrar_plan() {

  local site;
  local marca;


  echo;
  echo "============================================================";
  echo "PLAN DE EJECUCIÓN - FASE $FASE";
  echo "============================================================";
  echo;
  echo "  Origen  : $USER_ORIGEN@$IP_ORIGEN  (SSH como $SSH_ORIGEN)";
  echo "  Destino : $USER_DESTINO  en  $IP_DESTINO";
  echo "  HestiaCP: $HESTIA_MODO_RESUELTO";

  if [ "$PRIV_LOCAL_ES_ROOT" = "true" ]; then
    echo "  Permisos: con privilegio de root";
  else
    echo "  Permisos: SIN privilegio de root";
  fi;


  # ==========================================================
  # === FASE 1 ===
  # ==========================================================

  if [ "$FASE" = "1" ] || [ "$FASE" = "plan" ]; then

    if ! usuario_destino_existe; then
      echo;
      echo "  crear usuario del panel          [nuevo]";
    fi;

    for site in "${DOMINIOS[@]}"
    do

      echo;
      echo "------------------------------------------------------------";
      echo "$site";
      echo "------------------------------------------------------------";


      if ! cfg_si "$site" web; then

        echo "  sitio web                        NO (solo correo)";
        echo "  migrar correo";
        echo "      cuentas, contraseñas, alias, reenvíos y buzones";
        echo "      la clave DKIM será NUEVA en este servidor";

        continue;

      fi;


      if plan_dominio_existe "$site"; then
        marca="ya existe, se omitirá";
      else
        marca="nuevo";
      fi;

      echo "  crear dominio                    [$marca]";


      echo "  borrar index.html y robots.txt";


      local aw;

      aw="$(cfg "$site" alias_www)";

      if [ "$aw" = "auto" ]; then
        case "$site" in
          *.*.*) aw="true";;
          *)     aw="false";;
        esac;
      fi;

      if [ "$aw" = "true" ]; then
        echo "  eliminar alias                   www.$site";
      fi;


      echo "  plantilla PHP                    $(cfg "$site" php)";


      if cfg_si "$site" eliminar_dns; then
        echo "  eliminar zona DNS                [DESTRUCTIVO]";
        PLAN_DESTRUCTIVAS+=("$site: se elimina la zona DNS de HestiaCP");
      fi;


      if cfg_si "$site" eliminar_mail; then
        echo "  eliminar dominio de correo       [DESTRUCTIVO]";
        PLAN_DESTRUCTIVAS+=("$site: se elimina el dominio de correo y sus buzones");
      fi;


      if cfg_si "$site" correo; then
        echo "  migrar correo";
        echo "      cuentas, contraseñas, alias, reenvíos y buzones";
        echo "      la clave DKIM será NUEVA en este servidor";
      fi;


      # ------------------------------------------------------
      # Archivos
      # ------------------------------------------------------

      echo "  copiar archivos";
      echo "      desde  $SSH_TARGET:$BASE_ORIGEN/$(cfg "$site" origen)/public_html/";
      echo "      hasta  $BASE_DESTINO/$site/public_html/";
      echo "      rsync --delete: lo que no esté en el origen se borra";
      echo "      permisos $(cfg "$site" chmod), grupo $(cfg "$site" grupo)";

      PLAN_DESTRUCTIVAS+=("$site: rsync --delete borra en el destino lo que no exista en el origen");


      # ------------------------------------------------------
      # Base de datos
      # ------------------------------------------------------

      local bd;

      bd="$(cfg "$site" bd)";

      if [ -z "$bd" ]; then

        echo "  base de datos                    ninguna";

        continue;

      fi;


      local bd_final;
      local bd_user_final;
      local bd_origen;

      bd_final="$(cfg "$site" bd_final)";
      bd_user_final="$(cfg "$site" bd_user_final)";
      bd_origen="$(cfg "$site" bd_origen)";


      if plan_base_existe "$bd_final"; then
        marca="ya existe";
      else
        marca="nueva";
      fi;

      echo "  crear base de datos              [$marca]";
      echo "      $(cfg "$site" bd_corto)  ->  $bd_final";
      echo "      $(cfg "$site" bd_user_corto)  ->  $bd_user_final";


      if [ -n "$bd_origen" ]; then
        echo "  importar datos";
        echo "      desde  $bd_origen  (servidor viejo)";
        echo "      hasta  $bd_final";
      else
        echo "  importar datos";
        echo "      el nombre de origen se leerá del servidor viejo";
      fi;


      if [ "$marca" = "ya existe" ]; then

        local tablas;

        tablas="$(plan_tablas_en "$bd_final")";

        if [ -n "$tablas" ] && [ "$tablas" -gt 0 ]; then

          echo "      [DESTRUCTIVO] la base destino tiene $tablas tablas";
          echo "                    y se vaciará antes de importar";

          PLAN_DESTRUCTIVAS+=("$site: se vacían las $tablas tablas de $bd_final antes de importar");

        fi;

      fi;


      local tipo;

      tipo="$(cfg "$site" tipo)";

      if [ "$tipo" = "ninguno" ]; then
        echo "  configuración de la app          no se toca (tipo=ninguno)";
        echo "      las credenciales se aplican a mano";
      else
        echo "  reescribir configuración         $(cfg "$site" ruta_db)";
        echo "      formato $tipo, solo db, user y password";
        echo "      se guarda copia previa en migraciones/";
      fi;

    done;

  fi;


  # ==========================================================
  # === FASE 2 ===
  # ==========================================================

  if [ "$FASE" = "2" ] || [ "$FASE" = "plan" ]; then

    echo;
    echo "############################################################";
    echo "FASE 2";
    echo "############################################################";

    for site in "${DOMINIOS[@]}"
    do

      echo;
      echo "------------------------------------------------------------";
      echo "$site";
      echo "------------------------------------------------------------";


      if ! cfg_si "$site" web; then

        echo "  nada que hacer en la fase 2 (solo correo)";

        continue;

      fi;


      if [ "${SINCRONIZAR_EN_FASE2:-false}" = "true" ]; then

        echo "  re-sincronizar archivos          rsync --delete  [ACTIVADO]";

        if [ "$FASE" = "2" ]; then
          PLAN_DESTRUCTIVAS+=("$site: rsync --delete con el DNS ya apuntando aquí; borra lo que hayan escrito los visitantes");
        fi;

      else

        echo "  re-sincronizar archivos          no (se hace en la fase sincronizar)";

      fi;


      if cfg_si "$site" ssl; then

        if resuelve_a_destino "$site" >/dev/null 2>&1; then

          if [ "${RENOVAR_SSL:-false}" != "true" ] && tiene_certificado "$site"; then
            echo "  emitir certificado SSL           [YA LO TIENE: se omitirá]";
          else
            echo "  emitir certificado SSL           [el dominio ya resuelve aquí]";
          fi;

        elif resuelve_a_cloudflare "$site"; then
          echo "  emitir certificado SSL           [SE OMITIRÁ: resuelve a Cloudflare (proxy)]";
        else
          echo "  emitir certificado SSL           [SE OMITIRÁ: aún no resuelve aquí]";
        fi;

      else

        echo "  emitir certificado SSL           no";

      fi;


      if cfg_si "$site" forzar_ssl; then
        echo "  forzar HTTPS                     sí";
      else
        echo "  forzar HTTPS                     no";
      fi;

    done;

  fi;


  # ==========================================================
  # === BASES SUELTAS ===
  # ==========================================================

  if [ "$FASE" = "1" ] || [ "$FASE" = "plan" ]; then

    local base;

    for base in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
    do

      echo;
      echo "------------------------------------------------------------";
      echo "[base suelta] $base";
      echo "------------------------------------------------------------";

      local bfinal;

      bfinal="$(bdcfg "$base" final)";


      if plan_base_existe "$bfinal"; then
        marca="ya existe";
      else
        marca="nueva";
      fi;

      echo "  crear base de datos              [$marca]";
      echo "      $(bdcfg "$base" corto)  ->  $bfinal";
      echo "      $(bdcfg "$base" user_corto)  ->  $(bdcfg "$base" user_final)";

      echo "  importar datos";
      echo "      desde  $(bdcfg "$base" origen)  (servidor viejo)";
      echo "      hasta  $bfinal";

      echo "  configuración de la app          ninguna que reescribir";


      if [ "$marca" = "ya existe" ]; then

        local btablas;

        btablas="$(plan_tablas_en "$bfinal")";

        if [ -n "$btablas" ] && [ "$btablas" -gt 0 ]; then

          echo "      [DESTRUCTIVO] la base destino tiene $btablas tablas";
          echo "                    y se vaciará antes de importar";

          PLAN_DESTRUCTIVAS+=("base suelta $base: se vacían las $btablas tablas de $bfinal");

        fi;

      fi;

    done;

  fi;


  # ==========================================================
  # === CRONJOBS ===
  # ==========================================================

  if [ "$FASE" = "1" ] || [ "$FASE" = "plan" ]; then

    local cron_conf;
    local cron_total;
    local cron_usuarios;
    local u;

    if [ "${#CRONJOBS_USUARIOS[@]}" -eq 0 ]; then
      cron_usuarios="$USER_ORIGEN";
    else
      cron_usuarios="${CRONJOBS_USUARIOS[*]}";
    fi;


    echo;
    echo "------------------------------------------------------------";
    echo "cronjobs de: $cron_usuarios";
    echo "------------------------------------------------------------";


    cron_total=0;

    for u in $cron_usuarios
    do

      cron_conf="$(
        origen_exec "cat /usr/local/hestia/data/users/$u/cron.conf" \
          "" </dev/null 2>/dev/null
      )";

      local n;

      n="$(echo "$cron_conf" | grep -c 'JOB=')";

      if [ -z "$cron_conf" ]; then
        n=0;
      fi;

      echo "  $u: $n";

      cron_total=$((cron_total + n));

    done;


    if [ "$cron_total" -eq 0 ]; then

      echo "  ninguno en el servidor viejo";

    else

      case "${CRONJOBS:-preguntar}" in

        todos)
          echo "  total $cron_total, se migrarán TODOS sin preguntar";
          ;;

        ninguno)
          echo "  total $cron_total, no se migrará ninguno";
          echo "  quedarán listados y recuperables en la corrida";
          ;;

        *)
          echo "  total $cron_total, se pedirá aceptación uno a uno";
          echo "  con la ruta ya reescrita al usuario $USER_DESTINO";
          ;;

      esac;

    fi;

  fi;


  # ==========================================================
  # === LO QUE DESTRUYE ===
  # ==========================================================

  echo;
  echo "============================================================";

  if [ "${#PLAN_DESTRUCTIVAS[@]}" -eq 0 ]; then

    echo "NADA DE LO ANTERIOR DESTRUYE DATOS";

  else

    echo "OPERACIONES QUE DESTRUYEN DATOS (${#PLAN_DESTRUCTIVAS[@]})";
    echo "============================================================";
    echo;

    printf '  - %s\n' "${PLAN_DESTRUCTIVAS[@]}";

  fi;

  echo "============================================================";

}



# ============================================================
# === CONFIRMACIÓN ===
# ============================================================

confirmar_plan() {

  if [ "${CONFIRMAR:-true}" = "false" ]; then

    echo;
    echo "CONFIRMAR=false: se ejecuta sin preguntar.";

    return 0;

  fi;


  # ----------------------------------------------------------
  # Sin terminal interactiva no se puede preguntar.
  #
  # Antes que ejecutar en silencio algo que borra datos, se
  # detiene y se explica cómo autorizarlo.
  # ----------------------------------------------------------

  if [ ! -t 0 ]; then

    echo;
    echo "ERROR: no hay terminal interactiva para confirmar.";
    echo;
    echo "Ejecutar con:";
    echo;
    echo "  ssh -t usuario@servidor '...'";
    echo;
    echo "o declarar CONFIRMAR=\"false\" en el archivo de migración.";
    echo;

    return 1;

  fi;


  echo;

  local respuesta;

  read -r -p "¿Ejecutar la fase $FASE? Escribir 'si' para continuar: " respuesta;


  case "$respuesta" in

    si|SI|Si|sí|SÍ|Sí)
      echo;
      return 0;
      ;;

    *)
      echo;
      echo "Cancelado. No se ha modificado nada.";
      echo;
      return 1;
      ;;

  esac;

}
