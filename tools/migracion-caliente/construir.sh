#!/bin/bash

# ============================================================
# CONSTRUCTOR DE PAQUETE
# ============================================================
#
# Empaqueta todos los módulos en UN SOLO archivo ejecutable,
# para no tener que subir once al servidor.
#
#
# USO
#
#   ./construir.sh migracion-cliente.sh
#
# Genera:
#
#   migracion-cliente.paquete.sh
#
# que lleva dentro los módulos Y la configuración.
#
#
#   ./construir.sh
#
# Genera:
#
#   migrar.paquete.sh
#
# sin configuración: se le pasa el archivo de migración como
# argumento al ejecutarlo.
#
#
# CÓMO SE USA EL PAQUETE
#
#   scp migracion-cliente.paquete.sh root@destino:/tmp/;
#   ssh root@destino;
#
#   bash /tmp/migracion-cliente.paquete.sh plan;
#   bash /tmp/migracion-cliente.paquete.sh 1;
#
# La fase se pasa como argumento, así que no hay que
# reconstruir el paquete para pasar de una a otra.
#
# O sin dejar nada permanente en el servidor:
#
#   ssh root@destino 'cat > /tmp/m.sh' < migracion-cliente.paquete.sh;
#   ssh -t root@destino 'bash /tmp/m.sh; rm -f /tmp/m.sh';
#
#
# CÓMO FUNCIONA
#
# El paquete se autoextrae en un directorio temporal y ejecuta
# BASE_GENERAL.sh desde ahí, sin modificar ni una línea de los
# módulos.
#
# Así el paquete se comporta EXACTAMENTE igual que la versión
# de módulos sueltos: mismo orden, mismas variables, mismos
# mensajes. No hay dos comportamientos que mantener.
#
# El temporal se borra al terminar.
#
# ============================================================


set -u


DIR_FUENTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";


MODULOS=(
  "BASE_GENERAL.sh"
  "BASE_CONFIG.sh"
  "BASE_PRIVILEGIOS.sh"
  "BASE_LEER_CONFIG.sh"
  "BASE_PLAN.sh"
  "BASE_MIGRAR_DB.sh"
  "BASE_CONFIGURAR_DB.sh"
  "BASE_MIGRAR_MAIL.sh"
  "BASE_MIGRAR_CRON.sh"
  "BASE_COMPROBAR.sh"
  "BASE_VERIFICAR.sh"
);


MIGRACION_FUENTE="${1:-}";


# ============================================================
# === COMPROBAR QUE ESTÁN TODOS ===
# ============================================================

FALTAN=0;

for m in "${MODULOS[@]}"
do

  if [ ! -f "$DIR_FUENTE/$m" ]; then

    echo "ERROR: falta $m";

    FALTAN=$((FALTAN + 1));

  fi;

done;


if [ "$FALTAN" -ne 0 ]; then
  exit 1;
fi;


if [ -n "$MIGRACION_FUENTE" ] && [ ! -f "$MIGRACION_FUENTE" ]; then

  echo "ERROR: no existe $MIGRACION_FUENTE";

  exit 1;

fi;


# ============================================================
# === NOMBRE DE SALIDA ===
# ============================================================

# ------------------------------------------------------------
# El paquete se escribe en el directorio ACTUAL, no junto a
# los módulos.
#
# Así los BASE_* se pueden tener en un sitio fijo y trabajar
# desde la carpeta de cada cliente.
# ------------------------------------------------------------

if [ -n "$MIGRACION_FUENTE" ]; then

  BASE_NOMBRE="$(basename "$MIGRACION_FUENTE")";
  BASE_NOMBRE="${BASE_NOMBRE%.sh}";

  SALIDA="$PWD/${BASE_NOMBRE}.paquete.sh";

else

  SALIDA="$PWD/migrar.paquete.sh";

fi;


# ============================================================
# === COMPROBAR QUE NINGÚN MARCADOR CHOQUE ===
# ============================================================
#
# Si un módulo contuviera una línea igual a su marcador de
# heredoc, el paquete saldría roto sin avisar.
#
# ============================================================

ARCHIVOS=("${MODULOS[@]}");

if [ -n "$MIGRACION_FUENTE" ]; then
  ARCHIVOS+=("$MIGRACION_FUENTE");
fi;


for a in "${ARCHIVOS[@]}"
do

  ruta="$a";

  if [ ! -f "$ruta" ]; then
    ruta="$DIR_FUENTE/$a";
  fi;

  marcador="___FIN_$(basename "$a" | tr '[:lower:].-' '[:upper:]__')___";

  if grep -qx "$marcador" "$ruta"; then

    echo "ERROR: $a contiene una línea igual a su marcador.";

    exit 1;

  fi;

done;


# ============================================================
# === LEER LOS DATOS DEL ARCHIVO DE MIGRACIÓN ===
# ============================================================
#
# Se carga en un subshell con dominio() y predeterminados()
# neutralizadas, para quedarnos solo con las variables y no
# ejecutar nada.
#
# Sirve para imprimir al final los comandos REALES en vez de
# un ejemplo con "destino".
#
# ============================================================

DATOS_IP="";
DATOS_SSH="root";
DATOS_USER="";


if [ -n "$MIGRACION_FUENTE" ]; then

  DATOS="$(
    dominio() { :; };
    predeterminados() { :; };

    # shellcheck source=/dev/null
    source "$MIGRACION_FUENTE" >/dev/null 2>&1;

    printf '%s|%s|%s\n' \
      "${IP_DESTINO:-}" \
      "${SSH_DESTINO:-root}" \
      "${USER_DESTINO:-}";
  )";

  IFS='|' read -r DATOS_IP DATOS_SSH DATOS_USER <<< "$DATOS";

fi;



# ============================================================
# === GENERAR EL PAQUETE ===
# ============================================================

{

cat <<'CABECERA'
#!/bin/bash

# ============================================================
# PAQUETE DE MIGRACIÓN HESTIACP
# ============================================================
#
# ARCHIVO GENERADO. NO EDITAR A MANO.
#
# Este archivo es un producto, no una fuente. Cualquier cambio
# se pierde en la siguiente construcción.
#
# Para modificar algo: editar el módulo correspondiente y
# volver a ejecutar
#
#   ./construir.sh [archivo-de-migracion]
#
# Contiene todos los módulos. Se autoextrae en un directorio
# temporal, ejecuta la migración y se borra al terminar.
#
# ============================================================


PAQUETE_DIR="$(mktemp -d)";


limpiar_paquete() {

  if [ -n "$PAQUETE_DIR" ] && [ -d "$PAQUETE_DIR" ]; then
    rm -rf "$PAQUETE_DIR";
  fi;

}


trap limpiar_paquete EXIT;


chmod 700 "$PAQUETE_DIR";

CABECERA

echo;
echo "# === MÓDULOS ===";
echo;

for m in "${MODULOS[@]}"
do

  marcador="___FIN_$(echo "$m" | tr '[:lower:].-' '[:upper:]__')___";

  echo "cat > \"\$PAQUETE_DIR/$m\" <<'$marcador'";

  cat "$DIR_FUENTE/$m";

  echo "$marcador";
  echo;

done;


if [ -n "$MIGRACION_FUENTE" ]; then

  nombre="$(basename "$MIGRACION_FUENTE")";

  marcador="___FIN_$(echo "$nombre" | tr '[:lower:].-' '[:upper:]__')___";

  echo "# === CONFIGURACIÓN DE ESTA MIGRACIÓN ===";
  echo;
  echo "cat > \"\$PAQUETE_DIR/$nombre\" <<'$marcador'";

  cat "$MIGRACION_FUENTE";

  echo "$marcador";
  echo;
  echo "PAQUETE_MIGRACION=\"\$PAQUETE_DIR/$nombre\";";
  echo "PAQUETE_FASE=\"\${1:-}\";";
  echo "PAQUETE_EXTRA=(\"\${@:2}\");";

else

  cat <<'SINCONFIG'

# === CONFIGURACIÓN ===
#
# Este paquete se generó sin configuración incorporada, así
# que hay que pasarle el archivo de migración.

if [ "$#" -lt 1 ]; then

  echo;
  echo "ERROR: falta el archivo de migración.";
  echo;
  echo "Uso:";
  echo "  bash $(basename "$0") archivo-de-migracion.sh";
  echo;

  exit 1;

fi;


if [ ! -f "$1" ]; then

  echo "ERROR: no existe $1";

  exit 1;

fi;


PAQUETE_MIGRACION="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")";

PAQUETE_FASE="${2:-}";
PAQUETE_EXTRA=("${@:3}");
SINCONFIG

fi;


cat <<'PIE'

# === EJECUTAR ===
#
# Se ejecuta BASE_GENERAL.sh tal cual, desde el temporal.
#
# No se usa exec para que el trap alcance a borrar el
# directorio al terminar.

chmod 600 "$PAQUETE_DIR"/*.sh;

bash "$PAQUETE_DIR/BASE_GENERAL.sh" "$PAQUETE_MIGRACION" "$PAQUETE_FASE" ${PAQUETE_EXTRA[@]+"${PAQUETE_EXTRA[@]}"};

ESTADO=$?;


limpiar_paquete;

trap - EXIT;


exit "$ESTADO";
PIE

} > "$SALIDA";


chmod 755 "$SALIDA";


# ============================================================
# === COMPROBAR EL RESULTADO ===
# ============================================================

if ! bash -n "$SALIDA"; then

  echo;
  echo "ERROR: el paquete generado tiene errores de sintaxis.";

  rm -f "$SALIDA";

  exit 1;

fi;


LINEAS="$(wc -l < "$SALIDA")";

TAM="$(du -h "$SALIDA" | cut -f1)";


echo;
echo "Paquete generado:";
echo;
echo "  ./$(basename "$SALIDA")";
echo "  $LINEAS líneas, $TAM";
echo;

if [ -n "$MIGRACION_FUENTE" ]; then

  NOMBRE="$(basename "$SALIDA")";


  # ----------------------------------------------------------
  # Si el archivo de migración trae IP_DESTINO, se imprimen
  # los comandos exactos. Si no, se avisa de lo que falta.
  # ----------------------------------------------------------

  if [ -z "$DATOS_IP" ]; then

    echo "AVISO: el archivo de migración no define IP_DESTINO,";
    echo "así que no puedo darte los comandos exactos.";
    echo;

    DESTINO="usuario@servidor";

  else

    DESTINO="$DATOS_SSH@$DATOS_IP";

  fi;


  echo "Incluye la configuración de $(basename "$MIGRACION_FUENTE")";

  if [ -n "$DATOS_USER" ]; then
    echo "para el usuario $DATOS_USER.";
  else
    echo;
  fi;

  echo;
  echo "  1. Subirlo:";
  echo;
  echo "     scp $NOMBRE $DESTINO:/tmp/;";
  echo;
  echo "  2. Ver qué pasaría, sin ejecutar nada:";
  echo;
  echo "     ssh -t $DESTINO 'bash /tmp/$NOMBRE plan';";
  echo;
  echo "  3. Migrar:";
  echo;
  echo "     ssh -t $DESTINO 'bash /tmp/$NOMBRE 1';";
  echo;
  echo "  4. Comprobar que todo conecta:";
  echo;
  echo "     ssh -t $DESTINO 'bash /tmp/$NOMBRE verificar';";
  echo;
  echo "  5. JUSTO ANTES de tocar el DNS, arrastrar lo que haya";
  echo "     cambiado en el servidor viejo. Repetible:";
  echo;
  echo "     ssh -t $DESTINO 'bash /tmp/$NOMBRE sincronizar';";
  echo;
  echo "  6. Apuntar el DNS hacia $DATOS_IP.";
  echo;
  echo "  7. Certificados y HTTPS:";
  echo;
  echo "     ssh -t $DESTINO 'bash /tmp/$NOMBRE 2';";
  echo;
  echo "  8. Comprobar otra vez y limpiar:";
  echo;
  echo "     ssh -t $DESTINO 'bash /tmp/$NOMBRE verificar; rm -f /tmp/$NOMBRE';";

else

  NOMBRE="$(basename "$SALIDA")";

  echo "Sin configuración incorporada.";
  echo;
  echo "  scp $NOMBRE migracion.sh usuario@servidor:/tmp/;";
  echo "  ssh -t usuario@servidor 'bash /tmp/$NOMBRE /tmp/migracion.sh plan';";

fi;

echo;
