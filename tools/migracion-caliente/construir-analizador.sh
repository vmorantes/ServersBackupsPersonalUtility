#!/bin/bash

# ============================================================
# CONSTRUIR EL ANALIZADOR
# ============================================================
#
#   bash construir-analizador.sh
#
# Produce analizar.paquete.sh: un único archivo que se sube al
# servidor de ORIGEN y se ejecuta allí.
#
# Lo único que hace es concatenar archivos de este
# repositorio. No conecta a nada, no instala nada y no escribe
# fuera de este directorio.
#
#
# POR QUÉ UN PAQUETE
#
# El analizador necesita leer qué base de datos tiene escrita
# cada aplicación, y eso ya lo sabe hacer el programa PHP que
# vive dentro de BASE_LEER_CONFIG.sh. Copiar sus patrones aquí
# los duplicaría por tercera vez, y una copia que se queda
# atrás da el peor fallo posible: leería bien en un sitio y mal
# en otro.
#
# Así que no se copian: se extrae el programa de su heredoc, por
# sus marcadores, y se empotra en el paquete. Si ese archivo
# cambia, el paquete siguiente lleva el cambio.
#
# ============================================================

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";

ANALIZADOR="$DIR/analizar.sh";
LECTOR="$DIR/BASE_LEER_CONFIG.sh";
PAQUETE="$DIR/analizar.paquete.sh";

APERTURA='cat > "$LEER_PHP" <<'"'"'PHP'"'"''
MARCADOR='___FIN_HELPER_LECTURA___';


for archivo in "$ANALIZADOR" "$LECTOR"
do
  if [ ! -r "$archivo" ]; then
    echo "ERROR: no se puede leer $archivo" >&2;
    exit 1;
  fi;
done


# ------------------------------------------------------------
# Extraer el programa PHP de lectura de su heredoc.
# ------------------------------------------------------------

HELPER="$(
  awk -v ap="$APERTURA" '
    $0 == ap { dentro = 1; next }
    dentro && $0 == "PHP" { exit }
    dentro { print }
  ' "$LECTOR"
)";

if [ -z "$HELPER" ]; then
  echo "ERROR: no se encontró el programa de lectura en $LECTOR." >&2;
  echo "       Se buscaba la línea de apertura de su heredoc." >&2;
  exit 1;
fi;

if ! printf '%s\n' "$HELPER" | grep -q "leer_config.php ARCHIVO FORMATO"; then
  echo "ERROR: lo extraído de $LECTOR no parece el lector de configuraciones." >&2;
  exit 1;
fi;


# Una línea igual al marcador cerraría el heredoc del paquete
# por la mitad y lo dejaría roto. Es la misma comprobación que
# hace construir.sh con sus módulos.
if printf '%s\n' "$HELPER" | grep -qx "$MARCADOR"; then
  echo "ERROR: el lector contiene una línea igual al marcador $MARCADOR." >&2;
  exit 1;
fi;


# ------------------------------------------------------------
# Escribir el paquete.
# ------------------------------------------------------------

{
  echo '#!/bin/bash';
  echo;
  echo '# ============================================================';
  echo '# ANALIZADOR DE UN HESTIACP — PAQUETE';
  echo '# ============================================================';
  echo '#';
  echo '# Generado por construir-analizador.sh. No se edita a mano:';
  echo '# se cambia analizar.sh y se vuelve a construir.';
  echo '#';
  echo '#   bash analizar.paquete.sh [--rapido] [--usuario <cuenta>]';
  echo '#';
  echo '# ============================================================';
  echo;
  echo '# El lector de configuraciones de aplicaciones, tal como vive';
  echo '# en BASE_LEER_CONFIG.sh. No es una copia editada: se extrae en';
  echo '# cada construcción.';
  echo;
  echo "ANALIZADOR_HELPER_EMBEBIDO=\"\$(cat <<'$MARCADOR'";
  printf '%s\n' "$HELPER";
  echo "$MARCADOR";
  echo ')"';
  echo;
  echo;

  # El analizador, sin su línea de shebang: el paquete ya tiene
  # la suya arriba.
  tail -n +2 "$ANALIZADOR";

} > "$PAQUETE"


chmod 700 "$PAQUETE";


if ! bash -n "$PAQUETE"; then
  echo "ERROR: el paquete generado no pasa bash -n. No se usa." >&2;
  exit 1;
fi;


echo "Paquete escrito: $PAQUETE";
echo;
echo "Para analizar un servidor, desde tu equipo:";
echo "  scp $(basename "$PAQUETE") root@<servidor-de-origen>:/root/";
echo "  ssh root@<servidor-de-origen> 'bash /root/$(basename "$PAQUETE")'";
echo;
echo "El analizador solo lee: no escribe nada en el servidor fuera del";
echo "directorio de salida que él mismo crea, y te dice cuál es.";
