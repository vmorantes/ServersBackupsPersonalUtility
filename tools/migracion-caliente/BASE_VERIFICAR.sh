#!/bin/bash

# ============================================================
# VERIFICACIÓN POST-MIGRACIÓN
# ============================================================
#
# Se ejecuta con:
#
#   FASE="verificar";
#
# desde el archivo de migración.
#
#
# ============================================================
#
# QUÉ COMPRUEBA, POR CADA DOMINIO
#
#   1. Que exista el archivo de configuración.
#
#   2. Qué credenciales tiene escritas ahora mismo.
#
#   3. Que coincidan con lo declarado en la migración.
#
#   4. Que esas credenciales CONECTEN de verdad.
#
#   5. Cuántas tablas tiene la base.
#
#
# El punto 4 es el que importa. Que el archivo diga lo
# correcto no prueba que el usuario exista, que la
# contraseña sirva o que la base tenga datos.
#
#
# Se puede ejecutar tantas veces como se quiera: no modifica
# nada.
#
# ============================================================



if ! declare -F cfg >/dev/null; then
  echo "ERROR: BASE_CONFIG.sh no ha sido cargado.";
  return 1 2>/dev/null || exit 1;
fi;



if ! declare -F leer_config_local >/dev/null; then
  echo "ERROR: BASE_LEER_CONFIG.sh no ha sido cargado.";
  return 1 2>/dev/null || exit 1;
fi;


VERIF_TMP="$(mktemp -d)";



# ============================================================
# === RECORRER LOS DOMINIOS ===
# ============================================================

echo;
echo "============================================================";
echo "VERIFICACIÓN";
echo "============================================================";


VERIF_PROBLEMAS=0;


for site in "${DOMINIOS[@]}"
do

  echo;
  echo "============================================================";
  echo "$site";
  echo "============================================================";


  TIPO_APP="$(cfg "$site" tipo)";

  BD_ESPERADA="$(cfg "$site" bd_final)";
  USER_ESPERADO="$(cfg "$site" bd_user_final)";

  PASS="$(cfg "$site" bd_pass)";


  # ----------------------------------------------------------
  # Sitios sin base de datos.
  # ----------------------------------------------------------

  if ! cfg_si "$site" web; then

    echo "  Solo correo, sin sitio web.";

    continue;

  fi;


  # ----------------------------------------------------------
  # Sin el dominio en HestiaCP, el HTTP lo contesta el vhost
  # por defecto y un 200 no significaría nada.
  # ----------------------------------------------------------

  if ! plan_dominio_existe "$site"; then

    echo "  ERROR: el dominio no existe en HestiaCP";

    VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

    continue;

  fi;


  # ----------------------------------------------------------
  # ¿Responde el sitio?
  #
  # Se pide por IP con la cabecera Host, así que funciona
  # aunque el DNS siga apuntando al servidor viejo. Es la
  # única comprobación que dice si la migración sirvió de
  # algo: la base puede conectar y el sitio dar un 500.
  # ----------------------------------------------------------

  if command -v curl >/dev/null 2>&1; then

    CODIGO_HTTP="$(
      curl -s -o /dev/null -w '%{http_code}' \
        --max-time 15 \
        -H "Host: $site" \
        "http://$IP_DESTINO/" 2>/dev/null
    )";


    case "$CODIGO_HTTP" in

      2*|301|302|303|307|308)
        echo "  HTTP: $CODIGO_HTTP";
        ;;

      401|403)
        echo "  HTTP: $CODIGO_HTTP  (el servidor responde, acceso restringido)";
        ;;

      000|"")
        echo "  HTTP: sin respuesta desde $IP_DESTINO";
        VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));
        ;;

      *)
        echo "  HTTP: $CODIGO_HTTP  <-- el sitio no está sirviendo bien";
        VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));
        ;;

    esac;

  fi;


  if [ -z "$BD_ESPERADA" ]; then

    echo "  Sin base de datos.";

    RAIZ="$BASE_DESTINO/$site/public_html";

    if [ -d "$RAIZ" ]; then

      ARCHIVOS="$(find "$RAIZ" -type f 2>/dev/null | wc -l)";

      echo "  Archivos en public_html: $ARCHIVOS";

      if [ "$ARCHIVOS" -eq 0 ]; then

        echo "  AVISO: el directorio está vacío.";

        VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

      fi;

    else

      echo "  AVISO: no existe $RAIZ";

      VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

    fi;

    continue;

  fi;


  # ----------------------------------------------------------
  # El lado del origen solo se conoce si en esta ejecución se
  # leyó el servidor viejo, cosa que la verificación no hace.
  #
  # Si no se sabe, no se inventa una flecha desde la nada.
  # ----------------------------------------------------------

  if [ -n "$(cfg "$site" bd_origen)" ]; then

    echo "  Equivalencia de la migración:";
    echo "    db     : $(cfg "$site" bd_origen)  ->  $BD_ESPERADA";

    if [ -n "$(cfg "$site" bd_user_origen)" ]; then
      echo "    user   : $(cfg "$site" bd_user_origen)  ->  $USER_ESPERADO";
    else
      echo "    user   : $USER_ESPERADO";
    fi;

  else

    echo "  Esperado en el destino:";
    echo "    db     : $BD_ESPERADA";
    echo "    user   : $USER_ESPERADO";

  fi;


  # ----------------------------------------------------------
  # Leer lo que dice el archivo de la aplicación.
  # ----------------------------------------------------------

  if [ "$TIPO_APP" = "ninguno" ]; then

    echo;
    echo "  Configuración: tipo=ninguno, no se revisa el archivo.";

  else

    FILE="$BASE_DESTINO/$site/$(cfg "$site" ruta_db)";

    echo;
    echo "  Archivo: $(cfg "$site" ruta_db)";


    if [ ! -f "$FILE" ]; then

      echo "  ERROR: no existe.";

      VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

    else

      LEIDO="$(leer_config_local "$FILE" "$TIPO_APP")";


      BD_REAL="$(valor_de "$LEIDO" DB)";
      USER_REAL="$(valor_de "$LEIDO" USER)";
      HOST_REAL="$(valor_de "$LEIDO" HOST)";


      echo "    db     : $BD_REAL";
      echo "    user   : $USER_REAL";
      echo "    host   : $HOST_REAL";


      if [ "$BD_REAL" != "$BD_ESPERADA" ]; then

        echo "  ERROR: la db del archivo no coincide con la declarada.";

        VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

      fi;


      if [ "$USER_REAL" != "$USER_ESPERADO" ]; then

        echo "  ERROR: el user del archivo no coincide con el declarado.";

        VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

      fi;

    fi;

  fi;


  # ----------------------------------------------------------
  # La comprobación que de verdad importa: conectar.
  #
  # Se usa un defaults-file temporal para no exponer la
  # contraseña en la línea de comandos.
  # ----------------------------------------------------------

  echo;

  CNF="$VERIF_TMP/${site}.cnf";

  touch "$CNF";

  chmod 600 "$CNF";

  printf '[client]\nuser=%s\npassword=%s\n' \
    "$USER_ESPERADO" "$PASS" > "$CNF";


  TABLAS="$(
    mysql --defaults-file="$CNF" \
      --batch --skip-column-names \
      -e "SELECT COUNT(*) FROM information_schema.TABLES
          WHERE TABLE_SCHEMA = DATABASE();" \
      "$BD_ESPERADA" 2>/dev/null
  )";


  rm -f "$CNF";


  if [ -z "$TABLAS" ]; then

    echo "  CONEXIÓN: FALLÓ";
    echo "    El usuario no existe, la contraseña no sirve";
    echo "    o la base no está accesible para él.";

    VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

  elif [ "$TABLAS" -eq 0 ]; then

    echo "  CONEXIÓN: OK, pero la base está VACÍA.";

    VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

  else

    echo "  CONEXIÓN: OK  ($TABLAS tablas)";

  fi;

done;



# ============================================================
# === BASES SUELTAS ===
# ============================================================
#
# No tienen aplicación, así que lo único comprobable es que
# las credenciales conecten y que la base tenga datos.
#
# ============================================================

for base in ${BASES_SUELTAS[@]+"${BASES_SUELTAS[@]}"}
do

  echo;
  echo "============================================================";
  echo "[base suelta] $base";
  echo "============================================================";

  BD_ESPERADA="$(bdcfg "$base" final)";
  USER_ESPERADO="$(bdcfg "$base" user_final)";

  echo "  Equivalencia de la migración:";
  echo "    db     : $(bdcfg "$base" origen)  ->  $BD_ESPERADA";
  echo "    user   : $USER_ESPERADO";
  echo;

  CNF="$VERIF_TMP/suelta_${base}.cnf";

  touch "$CNF";

  chmod 600 "$CNF";

  printf '[client]\nuser=%s\npassword=%s\n' \
    "$USER_ESPERADO" "$(bdcfg "$base" pass)" > "$CNF";


  TABLAS="$(
    mysql --defaults-file="$CNF" \
      --batch --skip-column-names \
      -e "SELECT COUNT(*) FROM information_schema.TABLES
          WHERE TABLE_SCHEMA = DATABASE();" \
      "$BD_ESPERADA" 2>/dev/null
  )";


  rm -f "$CNF";


  if [ -z "$TABLAS" ]; then

    echo "  CONEXIÓN: FALLÓ";

    VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

  elif [ "$TABLAS" -eq 0 ]; then

    echo "  CONEXIÓN: OK, pero la base está VACÍA.";

    VERIF_PROBLEMAS=$((VERIF_PROBLEMAS + 1));

  else

    echo "  CONEXIÓN: OK  ($TABLAS tablas)";

  fi;

done;



# ============================================================
# === LIMPIEZA Y RESUMEN ===
# ============================================================

rm -rf "$VERIF_TMP";


echo;
echo "============================================================";

if [ "$VERIF_PROBLEMAS" -eq 0 ]; then

  echo "VERIFICACIÓN: TODO EN ORDEN";
  echo "============================================================";

else

  echo "VERIFICACIÓN: $VERIF_PROBLEMAS PROBLEMA(S)";
  echo "============================================================";

fi;

echo;
