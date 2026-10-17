#!/bin/bash

# ============================================================
# MIGRACIÓN DE CRONJOBS
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
# POR QUÉ NO VA POR DOMINIO
#
#   En HestiaCP los cronjobs son del USUARIO, no del dominio.
#
#   Un mismo trabajo puede tocar varios sitios, o ninguno, o
#   ser algo que no tiene que ver con la web. No hay forma
#   fiable de repartirlos entre los bloques dominio.
#
#
# ============================================================
#
# POR QUÉ SE PREGUNTA UNO A UNO
#
#   Un cronjob es un comando arbitrario. Al migrarlo cambia
#   la ruta, puede cambiar la versión de PHP, y puede que ya
#   no tenga sentido en el servidor nuevo.
#
#   Además, un cronjob que se activa antes de tiempo puede
#   escribir en la base de datos vieja, mandar correos, o
#   cobrarle a alguien dos veces.
#
#   Por eso se muestran uno a uno con la ruta ya reescrita, y
#   se decide viendo el comando completo.
#
#
# ============================================================
#
# CONFIGURACIÓN
#
#   CRONJOBS="preguntar"   uno a uno (por defecto)
#   CRONJOBS="todos"       migrar todos sin preguntar
#   CRONJOBS="ninguno"     no migrar ninguno, solo listarlos
#
#   CRONJOBS_USUARIOS=("admin" "otro")
#
#     Usuarios del servidor VIEJO cuyos cronjobs se revisan.
#     Si no se declara, se usa USER_ORIGEN.
#
#     No hace falta saber cuáles existen: la herramienta los
#     lee y los muestra.
#
#
# ============================================================
#
# QUÉ QUEDA EN LA CORRIDA
#
#   cronjobs.log
#       la decisión de cada uno, aceptado o rechazado
#
#   cronjobs_USUARIO.original.conf
#       copia literal de lo que había en el origen
#
#   cronjobs_pendientes.sh
#       los rechazados, como comandos listos para ejecutar
#       si más adelante hicieran falta
#
#   Ocupan nada y evitan tener que volver al servidor viejo.
#
# ============================================================



if ! declare -F origen_exec >/dev/null; then
  echo "ERROR: BASE_PRIVILEGIOS.sh no ha sido cargado.";
  return 1 2>/dev/null || exit 1;
fi;



CRON_LOG="$DIR_CORRIDA/cronjobs.log";

CRON_PENDIENTES="$DIR_CORRIDA/cronjobs_pendientes.sh";


# ------------------------------------------------------------
# Usuarios a revisar. Por defecto, el de la migración.
# ------------------------------------------------------------

if [ "${#CRONJOBS_USUARIOS[@]}" -eq 0 ]; then
  CRONJOBS_USUARIOS=("$USER_ORIGEN");
fi;



# ============================================================
# === FUNCIONES ===
# ============================================================

# ------------------------------------------------------------
# Extrae un valor del formato CLAVE='valor' de HestiaCP.
# ------------------------------------------------------------

cron_valor() {

  echo "$1" |
  grep -oE "$2='[^']*'" |
  head -n 1 |
  sed -E "s/^$2='//; s/'$//";

}


# ------------------------------------------------------------
# Reescribe las rutas del usuario de origen al de destino.
# ------------------------------------------------------------

cron_reescribir() {

  echo "$1" | sed "s|/home/$2/|/home/$USER_DESTINO/|g";

}



# ============================================================
# === RECOGER LOS CRONJOBS DE CADA USUARIO ===
# ============================================================

echo;
echo "============================================================";
echo "CRONJOBS";
echo "============================================================";
echo;
echo "Usuarios a revisar: ${CRONJOBS_USUARIOS[*]}";


CRON_TOTAL=0;

declare -A CRON_POR_USUARIO=();


for usuario in "${CRONJOBS_USUARIOS[@]}"
do

  contenido="$(
    origen_exec \
      "cat /usr/local/hestia/data/users/$(printf '%q' "$usuario")/cron.conf" \
      "" </dev/null 2>/dev/null
  )";


  if [ -z "$contenido" ]; then

    echo "  $usuario: ninguno";

    continue;

  fi;


  n="$(echo "$contenido" | grep -c 'JOB=')";

  echo "  $usuario: $n";

  CRON_POR_USUARIO[$usuario]="$contenido";

  CRON_TOTAL=$((CRON_TOTAL + n));


  # ----------------------------------------------------------
  # Copia literal de lo que había, pase lo que pase después.
  # ----------------------------------------------------------

  printf '%s\n' "$contenido" > "$DIR_CORRIDA/cronjobs_${usuario}.original.conf";

  chmod 600 "$DIR_CORRIDA/cronjobs_${usuario}.original.conf";

done;


if [ "$CRON_TOTAL" -eq 0 ]; then

  echo;
  echo "No hay cronjobs que revisar.";

  return 0 2>/dev/null || exit 0;

fi;


echo;
echo "Total: $CRON_TOTAL cronjob(s).";



# ============================================================
# === MODO ===
# ============================================================

CRON_DECISION="${CRONJOBS:-preguntar}";


case "$CRON_DECISION" in

  ninguno)
    echo;
    echo "CRONJOBS=\"ninguno\": no se migra ninguno.";
    ;;

  todos)
    echo;
    echo "CRONJOBS=\"todos\": se migran todos sin preguntar.";
    ;;

  *)

    if [ ! -t 0 ]; then

      echo;
      echo "AVISO: no hay terminal para preguntar uno a uno.";
      echo "No se migra ninguno. Quedan listados y recuperables.";
      echo;
      echo "Usar CRONJOBS=\"todos\" o ejecutar con ssh -t.";

      CRON_DECISION="ninguno";

    else

      echo;
      echo "Se revisarán uno a uno.";
      echo;
      echo "  s = migrar este      n = saltar este";
      echo "  t = migrar todos     q = no migrar ninguno más";

    fi;
    ;;

esac;



# ============================================================
# === LOGS ===
# ============================================================

{
  echo "============================================================";
  echo "CRONJOBS";
  echo "============================================================";
  echo;
  echo "Fecha    : $(date '+%Y-%m-%d %H:%M:%S')";
  echo "Origen   : $IP_ORIGEN";
  echo "Usuarios : ${CRONJOBS_USUARIOS[*]}";
  echo "Destino  : $USER_DESTINO";
  echo "Total    : $CRON_TOTAL";
  echo;
} > "$CRON_LOG";


{
  echo "#!/bin/bash";
  echo;
  echo "# ============================================================";
  echo "# CRONJOBS NO MIGRADOS";
  echo "# ============================================================";
  echo "#";
  echo "# Generado el $(date '+%Y-%m-%d %H:%M:%S')";
  echo "#";
  echo "# Son los que se rechazaron durante la migración, con la";
  echo "# ruta ya reescrita al usuario $USER_DESTINO.";
  echo "#";
  echo "# Si alguno hiciera falta, descomentar su línea y ejecutar";
  echo "# este archivo. No hace falta volver al servidor viejo.";
  echo "# ============================================================";
  echo;
} > "$CRON_PENDIENTES";

chmod 700 "$CRON_PENDIENTES";



# ============================================================
# === RECORRER ===
# ============================================================

CRON_MIGRADOS=0;
CRON_SALTADOS=0;
CRON_ERRORES=0;

CRON_INDICE=0;


for usuario in "${CRONJOBS_USUARIOS[@]}"
do

  contenido="${CRON_POR_USUARIO[$usuario]}";

  [ -z "$contenido" ] && continue;


  echo "" >> "$CRON_LOG";
  echo "--- usuario $usuario ---" >> "$CRON_LOG";
  echo "" >> "$CRON_LOG";


  while IFS= read -r linea
  do

    case "$linea" in
      *JOB=*) ;;
      *) continue;;
    esac;


    CRON_INDICE=$((CRON_INDICE + 1));


    MIN="$(cron_valor "$linea" MIN)";
    HOUR="$(cron_valor "$linea" HOUR)";
    DAY="$(cron_valor "$linea" DAY)";
    MONTH="$(cron_valor "$linea" MONTH)";
    WDAY="$(cron_valor "$linea" WDAY)";
    CMD="$(cron_valor "$linea" CMD)";
    SUSPENDIDO="$(cron_valor "$linea" SUSPENDED)";


    [ -z "$CMD" ] && continue;


    CMD_NUEVO="$(cron_reescribir "$CMD" "$usuario")";


    echo;
    echo "------------------------------------------------------------";
    echo "[$CRON_INDICE/$CRON_TOTAL]  usuario $usuario";
    echo "                 $MIN $HOUR $DAY $MONTH $WDAY";
    echo "------------------------------------------------------------";
    echo;
    echo "  $CMD_NUEVO";


    if [ "$CMD_NUEVO" != "$CMD" ]; then
      echo;
      echo "  ruta reescrita desde:";
      echo "  $CMD";
    fi;


    if [ "$SUSPENDIDO" = "yes" ]; then
      echo;
      echo "  AVISO: está SUSPENDIDO en el servidor viejo.";
    fi;


    # --------------------------------------------------------
    # Decidir.
    # --------------------------------------------------------

    RESPUESTA="";

    case "$CRON_DECISION" in

      todos)   RESPUESTA="s";;
      ninguno) RESPUESTA="n";;

      *)

        echo;

        # ----------------------------------------------------
        # Se lee de /dev/tty, no de la entrada estándar.
        #
        # Este read está dentro de un while que consume la
        # lista de cronjobs por STDIN. Sin redirigir, cada
        # respuesta se comería la línea del siguiente cronjob
        # y algunos no llegarían a mostrarse.
        # ----------------------------------------------------

        read -r -p "  ¿Migrar este cronjob? [s/n/t/q]: " RESPUESTA < /dev/tty;

        case "$RESPUESTA" in

          t|T)
            CRON_DECISION="todos";
            RESPUESTA="s";
            echo "  Se migrarán todos los restantes.";
            ;;

          q|Q)
            CRON_DECISION="ninguno";
            RESPUESTA="n";
            echo "  No se migrará ninguno más.";
            ;;

        esac;
        ;;

    esac;


    case "$RESPUESTA" in

      s|S|si|SI|Si)

        hestia v-add-cron-job \
          "$USER_DESTINO" \
          "$MIN" "$HOUR" "$DAY" "$MONTH" "$WDAY" \
          "$CMD_NUEVO";

        CODIGO=$?;


        if [ "$CODIGO" -eq 0 ]; then

          echo "  MIGRADO";

          CRON_MIGRADOS=$((CRON_MIGRADOS + 1));

          {
            echo "[$CRON_INDICE] ACEPTADO";
            echo "    $MIN $HOUR $DAY $MONTH $WDAY";
            echo "    $CMD_NUEVO";
            [ "$SUSPENDIDO" = "yes" ] && echo "    (estaba suspendido en el origen)";
            echo;
          } >> "$CRON_LOG";

        else

          echo "  ERROR: $(hestia_texto "$CODIGO")";

          CRON_ERRORES=$((CRON_ERRORES + 1));

          {
            echo "[$CRON_INDICE] ERROR: $(hestia_texto "$CODIGO")";
            echo "    $CMD_NUEVO";
            echo;
          } >> "$CRON_LOG";

          {
            echo "# [$CRON_INDICE] falló al crearse";
            echo "# $HESTIA_BIN/v-add-cron-job$(printf ' %q' "$USER_DESTINO" "$MIN" "$HOUR" "$DAY" "$MONTH" "$WDAY" "$CMD_NUEVO")";
            echo;
          } >> "$CRON_PENDIENTES";

        fi;
        ;;

      *)

        echo "  rechazado";

        CRON_SALTADOS=$((CRON_SALTADOS + 1));

        {
          echo "[$CRON_INDICE] RECHAZADO";
          echo "    $MIN $HOUR $DAY $MONTH $WDAY";
          echo "    $CMD_NUEVO";
          [ "$SUSPENDIDO" = "yes" ] && echo "    (estaba suspendido en el origen)";
          echo;
        } >> "$CRON_LOG";

        {
          echo "# [$CRON_INDICE] usuario $usuario, $MIN $HOUR $DAY $MONTH $WDAY";
          [ "$SUSPENDIDO" = "yes" ] && echo "# estaba SUSPENDIDO en el origen";
          echo "# $HESTIA_BIN/v-add-cron-job$(printf ' %q' "$USER_DESTINO" "$MIN" "$HOUR" "$DAY" "$MONTH" "$WDAY" "$CMD_NUEVO")";
          echo;
        } >> "$CRON_PENDIENTES";
        ;;

    esac;

  done <<< "$contenido";

done;



# ============================================================
# === RESUMEN ===
# ============================================================

{
  echo "------------------------------------------------------------";
  echo "RESUMEN";
  echo "  aceptados : $CRON_MIGRADOS";
  echo "  rechazados: $CRON_SALTADOS";
  echo "  errores   : $CRON_ERRORES";
} >> "$CRON_LOG";


"${priv_local[@]}" chown -R "$USER_DESTINO":"$USER_DESTINO" \
  "$DIR_CORRIDA" 2>/dev/null;


echo;
echo "============================================================";
echo "CRONJOBS: $CRON_MIGRADOS aceptados, $CRON_SALTADOS rechazados";
echo "============================================================";
echo;
echo "  decisiones : $CRON_LOG";
echo "  originales : $DIR_CORRIDA/cronjobs_USUARIO.original.conf";

if [ "$CRON_SALTADOS" -gt 0 ] || [ "$CRON_ERRORES" -gt 0 ]; then
  echo "  rechazados : $CRON_PENDIENTES";
  echo;
  echo "Los rechazados quedan como comandos comentados en ese";
  echo "archivo. Si alguno hiciera falta, se descomenta y se";
  echo "ejecuta, sin volver al servidor viejo.";
fi;


if [ "$CRON_MIGRADOS" -gt 0 ]; then

  echo;
  echo "AVISO: los cronjobs migrados quedan ACTIVOS desde ya.";
  echo;
  echo "Si el DNS todavía apunta al servidor viejo, van a";
  echo "ejecutarse en los dos sitios a la vez. Conviene";
  echo "desactivarlos en el servidor viejo al cortar.";

fi;


if [ "$CRON_ERRORES" -ne 0 ]; then
  echo;
  echo "Cronjobs con error: $CRON_ERRORES";
fi;
