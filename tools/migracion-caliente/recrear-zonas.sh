#!/bin/bash

# ============================================================
# RECREAR LAS ZONAS DNS EN EL SERVIDOR NUEVO
# ============================================================
#
# Toma las zonas que el analizador exportó del servidor VIEJO
# y las deja en el servidor NUEVO como copia fiel, cambiando
# solo lo que tiene que cambiar: las IP, los NS y la clave
# DKIM. Se ejecuta en el servidor de DESTINO, como root:
#
#   bash recrear-zonas.sh \
#     --cuenta <cuenta> \
#     --zonas <ruta>/zonas/<cuenta> \
#     --ip-origen <IP del viejo> \
#     --ip-destino <IP del nuevo> \
#     [--dominio <dominio>] [--aplicar]
#
#   --dominio   solo esa zona. Repetible.
#   --aplicar   sin esto NO escribe nada: solo imprime el diff.
#
# ============================================================
#
# LO QUE NO HACE
#
#   1. NO ESCRIBE NADA EN EL SERVIDOR VIEJO (ADR 0019). Aquí
#      no hay ninguna conexión al origen: lo único que viene
#      de allí son los archivos que el analizador copió.
#
#   2. SIN --aplicar no escribe nada fuera de su propio
#      temporal, que borra al salir. CÓRRELO ASÍ PRIMERO y lee
#      el diff zona por zona: lo que no esté en el diff no va
#      a pasar, y lo que esté, va a pasar tal cual.
#
#   3. NO CREA ZONAS. La zona tiene que existir ya en el
#      destino: la crea la fase 1 de la migración (el alta del
#      dominio). Una zona que falte se salta y se dice.
#
#   4. NO CAMBIA EL SERIAL de la zona: v-rebuild-dns-domains
#      no lo toca. Un resolutor esclavo que ya tenga la zona
#      cacheada puede seguir sirviendo lo viejo hasta que
#      expire. COMPRUEBA CON dig contra el servidor nuevo
#      antes de cambiar los NS en el registrador.
#
# ============================================================
#
# De cada zona se conserva TODO lo del origen salvo:
#
#   - los VALUE que son exactamente la IP de origen, que pasan
#     a ser la IP de destino, y el token ip4: de los TXT (el
#     SPF);
#   - los NS, que se toman de la zona que el destino ya tiene
#     (los del viejo apuntan a nombres del viejo);
#   - mail._domainkey, que se toma del destino (la clave DKIM
#     del viejo no sirve: el nuevo tiene la suya).
#
# Los ID se renumeran de 1 a N. Todo lo demás de cada línea
# —TIME, DATE, TTL, PRIORITY, SUSPENDED— se copia literal.
#
# ============================================================


set -u


# ------------------------------------------------------------
# Rutas del sistema. Son variables para que las pruebas puedan
# apuntar el script a un árbol falso; en un servidor se quedan
# con su valor real.
# ------------------------------------------------------------

HESTIA_DIR="${HESTIA_DIR:-/usr/local/hestia}";
ZONAS_RESPALDO="${ZONAS_RESPALDO:-/root/zonas-respaldo}";


# Las únicas claves que una línea de zona puede llevar
# (50-hestiacp.md, «Formato y carga de una zona»). Cualquier
# otra es una línea que no sabemos reescribir sin estropearla:
# la zona entera se rechaza, no se carga a medias.
CLAVES_VALIDAS=" ID RECORD TYPE PRIORITY VALUE SUSPENDED TIME DATE TTL ";


CUENTA="";
DIR_ZONAS="";
IP_ORIGEN="";
IP_DESTINO="";
APLICAR="no";
DOMINIOS_PEDIDOS=();


morir() {
  echo "ERROR: $1" >&2;
  exit 2;
}


uso() {
  echo "Uso: bash recrear-zonas.sh --cuenta <c> --zonas <dir> \\" >&2;
  echo "       --ip-origen <IP> --ip-destino <IP> [--dominio <d>] [--aplicar]" >&2;
}


# ============================================================
# === ARGUMENTOS ===
# ============================================================

while [ "$#" -gt 0 ]
do

  case "$1" in

    --cuenta)
      [ "$#" -ge 2 ] || { uso; morir "--cuenta necesita un valor."; };
      CUENTA="$2";
      shift 2;
      ;;

    --zonas)
      [ "$#" -ge 2 ] || { uso; morir "--zonas necesita un valor."; };
      DIR_ZONAS="$2";
      shift 2;
      ;;

    --ip-origen)
      [ "$#" -ge 2 ] || { uso; morir "--ip-origen necesita un valor."; };
      IP_ORIGEN="$2";
      shift 2;
      ;;

    --ip-destino)
      [ "$#" -ge 2 ] || { uso; morir "--ip-destino necesita un valor."; };
      IP_DESTINO="$2";
      shift 2;
      ;;

    --dominio)
      [ "$#" -ge 2 ] || { uso; morir "--dominio necesita un valor."; };
      DOMINIOS_PEDIDOS+=("$2");
      shift 2;
      ;;

    --aplicar)
      APLICAR="si";
      shift;
      ;;

    -h|--help)
      uso;
      exit 0;
      ;;

    *)
      uso;
      morir "opción desconocida: $1";
      ;;

  esac;

done


# ============================================================
# === VALIDACIÓN (antes de tocar nada) ===
# ============================================================

es_ipv4() {

  local ip="$1";

  case "$ip" in
    *[!0-9.]*) return 1 ;;
  esac;

  local n=0 trozo;
  local IFS='.';

  for trozo in $ip
  do
    n=$((n + 1));
    [ -n "$trozo" ] || return 1;
    [ "${#trozo}" -le 3 ] || return 1;
    [ "$((10#$trozo))" -le 255 ] || return 1;
  done;

  [ "$n" -eq 4 ];
}


[ -n "$CUENTA" ]     || { uso; morir "falta --cuenta."; };
[ -n "$DIR_ZONAS" ]  || { uso; morir "falta --zonas."; };

[ -n "$IP_ORIGEN" ]  || { uso; morir "falta --ip-origen (la IP del servidor viejo)."; };
[ -n "$IP_DESTINO" ] || { uso; morir "falta --ip-destino (la IP del servidor nuevo)."; };

es_ipv4 "$IP_ORIGEN"  || morir "--ip-origen no es una IPv4: «$IP_ORIGEN».";
es_ipv4 "$IP_DESTINO" || morir "--ip-destino no es una IPv4: «$IP_DESTINO».";

if [ "$IP_ORIGEN" = "$IP_DESTINO" ]; then
  morir "--ip-origen y --ip-destino son la misma IP ($IP_ORIGEN): nada que sustituir. Si de verdad no cambia la IP, no hace falta este script.";
fi;

[ -d "$DIR_ZONAS" ] || morir "el directorio de zonas no existe: $DIR_ZONAS";

DIR_CUENTA="$HESTIA_DIR/data/users/$CUENTA";
CONF_DNS="$DIR_CUENTA/dns.conf";

[ -r "$CONF_DNS" ] || morir "no hay dns.conf legible de la cuenta «$CUENTA» en este servidor: $CONF_DNS. ¿Es esta la cuenta del destino?";


# Las zonas a tratar: las del directorio, o solo las pedidas.
ZONAS=();

if [ "${#DOMINIOS_PEDIDOS[@]}" -gt 0 ]; then

  for d in "${DOMINIOS_PEDIDOS[@]}"
  do
    [ -r "$DIR_ZONAS/$d.conf" ] || morir "no hay zona exportada de «$d» en $DIR_ZONAS.";
    ZONAS+=("$d");
  done;

else

  for archivo in "$DIR_ZONAS"/*.conf
  do
    [ -r "$archivo" ] || continue;
    base="$(basename "$archivo")";
    ZONAS+=("${base%.conf}");
  done;

fi;

if [ "${#ZONAS[@]}" -eq 0 ]; then
  morir "no hay ninguna zona (*.conf) en $DIR_ZONAS.";
fi;


# ============================================================
# === TEMPORAL PROPIO ===
# ============================================================

TMP="$(mktemp -d)";

if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  morir "no se pudo crear el directorio temporal.";
fi;

chmod 700 "$TMP";

limpiar() {
  rm -rf "$TMP";
}

trap limpiar EXIT


# ============================================================
# === LECTURA DE LÍNEAS DE ZONA ===
# ============================================================
#
# Nunca con «source»: hacer source de un archivo de datos es
# ejecutarlo, y esto corre como root.
# ============================================================

declare -A CAMPO=();
CLAVES_ORDEN=();

# Parte una línea CLAVE='valor' CLAVE='valor'… en CAMPO[] y
# CLAVES_ORDEN[]. Devuelve 1 si queda texto sin consumir: eso
# es una línea que no sabemos leer.
parsear_linea() {

  local resto="$1";
  local k v;

  CAMPO=();
  CLAVES_ORDEN=();

  while [[ "$resto" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=\'([^\']*)\'(.*)$ ]]
  do
    k="${BASH_REMATCH[1]}";
    v="${BASH_REMATCH[2]}";
    resto="${BASH_REMATCH[3]}";
    CAMPO["$k"]="$v";
    CLAVES_ORDEN+=("$k");
  done;

  [[ "$resto" =~ ^[[:space:]]*$ ]];
}


# Cierto si la línea leída es un NS del vértice de la zona.
es_ns_del_vertice() {
  [ "${CAMPO[RECORD]:-}" = "@" ] && [ "${CAMPO[TYPE]:-}" = "NS" ];
}


# Cierto si la línea leída es la clave DKIM.
es_domainkey() {
  case "${CAMPO[RECORD]:-}" in
    mail._domainkey|mail._domainkey.*) return 0 ;;
  esac;
  return 1;
}


# Sustituye el primer VALUE='viejo' por VALUE='nuevo' en la
# línea, sin reescribir el resto: TIME, DATE, TTL y los
# espacios se conservan literales.
cambiar_valor() {
  local linea="$1" viejo="$2" nuevo="$3";
  printf '%s' "${linea/VALUE=\'$viejo\'/VALUE=\'$nuevo\'}";
}


# Renumera el ID de la línea.
cambiar_id() {
  local linea="$1" viejo="$2" nuevo="$3";
  printf '%s' "${linea/ID=\'$viejo\'/ID=\'$nuevo\'}";
}


# El token ip4: del SPF, anclado por la derecha para que una
# IP no case dentro de otra más larga (203.0.113.1 dentro de
# 203.0.113.10).
cambiar_ip4() {

  local valor="$1";
  local escapada="${IP_ORIGEN//./\\.}";

  printf '%s' "$valor" \
    | sed -E "s/ip4:${escapada}([^0-9.]|\$)/ip4:${IP_DESTINO}\1/g";
}


# ============================================================
# === CONSTRUIR LA PROPUESTA DE UNA ZONA ===
# ============================================================
#
# Escribe la zona propuesta en $3. Devuelve 0 si se pudo
# construir; 1 si la zona se rechaza (y entonces MOTIVO dice
# por qué). Los avisos que no bloquean se van acumulando en
# AVISOS_ZONA.
# ============================================================

MOTIVO="";
AVISOS_ZONA=();

construir_propuesta() {

  local origen="$1" actual="$2" destino="$3";

  MOTIVO="";
  AVISOS_ZONA=();

  # --- Lo que se toma de la zona que YA tiene el destino ---
  local ns_destino="$TMP/.ns";
  local dkim_destino="$TMP/.dkim";

  : > "$ns_destino";
  : > "$dkim_destino";

  local linea;

  while IFS= read -r linea || [ -n "$linea" ]
  do

    [ -n "${linea//[[:space:]]/}" ] || continue;

    if ! parsear_linea "$linea"; then
      MOTIVO="la zona que el destino tiene ahora lleva una línea que no se puede leer: «$linea». No se toca.";
      return 1;
    fi;

    if es_ns_del_vertice; then
      printf '%s\n' "$linea" >> "$ns_destino";
    elif es_domainkey; then
      printf '%s\n' "$linea" >> "$dkim_destino";
    fi;

  done < "$actual"

  if [ ! -s "$ns_destino" ]; then
    MOTIVO="la zona que el destino tiene ahora no lleva ningún NS en @: sin NS del destino no se puede sustituir los del origen.";
    return 1;
  fi;

  # --- El cuerpo, a partir del origen ---
  local cuerpo="$TMP/.cuerpo";
  : > "$cuerpo";

  local ns_puestos="no";
  local dkim_puesto="no";
  local clave valor tipo nueva valor_nuevo;

  while IFS= read -r linea || [ -n "$linea" ]
  do

    [ -n "${linea//[[:space:]]/}" ] || continue;

    if ! parsear_linea "$linea"; then
      MOTIVO="línea del origen que no se puede leer: «$linea»";
      return 1;
    fi;

    for clave in "${CLAVES_ORDEN[@]}"
    do
      case "$CLAVES_VALIDAS" in
        *" $clave "*) ;;
        *)
          MOTIVO="la línea «$linea» lleva la clave «$clave», que no es de una zona DNS de HestiaCP. La zona no se carga.";
          return 1;
          ;;
      esac;
    done;

    if [ -z "${CAMPO[ID]:-}" ] || [ -z "${CAMPO[RECORD]:-}" ] || [ -z "${CAMPO[TYPE]:-}" ]; then
      MOTIVO="la línea «$linea» no tiene ID, RECORD o TYPE. La zona no se carga.";
      return 1;
    fi;

    # Los NS del origen se cambian en bloque por los del destino.
    if es_ns_del_vertice; then
      if [ "$ns_puestos" = "no" ]; then
        cat "$ns_destino" >> "$cuerpo";
        ns_puestos="si";
      fi;
      continue;
    fi;

    # La clave DKIM del origen no sirve en el destino.
    if es_domainkey; then
      if [ "$dkim_puesto" = "no" ]; then
        cat "$dkim_destino" >> "$cuerpo";
        dkim_puesto="si";
      fi;
      continue;
    fi;

    valor="${CAMPO[VALUE]:-}";
    tipo="${CAMPO[TYPE]}";
    nueva="$linea";

    if [ "$valor" = "$IP_ORIGEN" ]; then

      nueva="$(cambiar_valor "$linea" "$valor" "$IP_DESTINO")";
      valor="$IP_DESTINO";

    elif [ "$tipo" = "TXT" ]; then

      valor_nuevo="$(cambiar_ip4 "$valor")";

      if [ "$valor_nuevo" != "$valor" ]; then
        nueva="$(cambiar_valor "$linea" "$valor" "$valor_nuevo")";
        valor="$valor_nuevo";
      fi;

    fi;

    # --- Avisos que NO bloquean ---
    case "$valor" in
      *"$IP_ORIGEN"*)
        AVISOS_ZONA+=("el registro «${CAMPO[RECORD]}» ($tipo) sigue conteniendo la IP del origen después de la sustitución: «$valor». Revísalo a mano.");
        ;;
    esac;

    if [ "$tipo" = "A" ] || [ "$tipo" = "AAAA" ]; then
      if [ "$valor" != "$IP_DESTINO" ] && [ "$valor" != "$IP_ORIGEN" ]; then
        AVISOS_ZONA+=("el registro «${CAMPO[RECORD]}» ($tipo) apunta a «$valor», que no es ninguna de las dos IP. Puede ser correcto —un servicio de fuera— y por eso NO se cambia: compruébalo.");
      fi;
    fi;

    printf '%s\n' "$nueva" >> "$cuerpo";

  done < "$origen"

  # Si el origen no traía NS o DKIM, los del destino no se
  # pierden por eso: se añaden al final.
  if [ "$ns_puestos" = "no" ]; then
    cat "$ns_destino" >> "$cuerpo";
  fi;

  if [ "$dkim_puesto" = "no" ]; then
    cat "$dkim_destino" >> "$cuerpo";
  fi;

  # --- Renumerar los ID, 1..N, en el orden resultante ---
  : > "$destino";
  chmod 600 "$destino";

  local n=0;

  while IFS= read -r linea || [ -n "$linea" ]
  do

    [ -n "${linea//[[:space:]]/}" ] || continue;

    if ! parsear_linea "$linea"; then
      MOTIVO="línea que no se puede renumerar: «$linea»";
      return 1;
    fi;

    n=$((n + 1));
    cambiar_id "$linea" "${CAMPO[ID]}" "$n" >> "$destino";
    printf '\n' >> "$destino";

  done < "$cuerpo"

  if [ "$n" -eq 0 ]; then
    MOTIVO="la propuesta se quedó sin ningún registro.";
    return 1;
  fi;

  return 0;
}


# Cuántos registros y cuántos MX tiene un archivo de zona.
contar_registros() {
  grep -c "RECORD='" "$1" 2>/dev/null || true;
}

contar_mx() {
  grep -c "TYPE='MX'" "$1" 2>/dev/null || true;
}


# ============================================================
# === RECORRIDO ===
# ============================================================

echo;
echo "============================================================";
echo "RECREAR LAS ZONAS DNS DE «$CUENTA» EN ESTE SERVIDOR";
echo "============================================================";
echo;
echo "  Zonas exportadas : $DIR_ZONAS";
echo "  IP de origen     : $IP_ORIGEN";
echo "  IP de destino    : $IP_DESTINO";
echo "  Panel            : $HESTIA_DIR";
echo "  Modo             : $([ "$APLICAR" = "si" ] && echo "--aplicar (SE VA A ESCRIBIR)" || echo "solo el diff, no se escribe nada")";
echo;


# Primera pasada: construir la propuesta de cada zona y
# decidir cuáles se pueden tratar. Nada se escribe todavía en
# el panel.

TRATABLES=();
RESULTADOS=();
SALTADAS=0;
RECHAZADAS=0;

for dom in "${ZONAS[@]}"
do

  origen="$DIR_ZONAS/$dom.conf";
  actual="$DIR_CUENTA/dns/$dom.conf";

  echo "------------------------------------------------------------";
  echo "ZONA: $dom";
  echo "------------------------------------------------------------";

  # Los puntos del dominio, escapados: en una expresión regular
  # un punto casa con cualquier carácter, y «a.example.org»
  # casaría con «aXexample.org».
  dom_re="${dom//./\\.}";

  if ! grep -qE "(^|[[:space:]])DOMAIN='$dom_re'([[:space:]]|\$)" "$CONF_DNS"; then
    echo "  SALTADA: falta en el destino: créala con la fase 1 de la migración.";
    echo;
    RESULTADOS+=("$dom: SALTADA (falta en el destino: créala con la fase 1 de la migración)");
    SALTADAS=$((SALTADAS + 1));
    continue;
  fi;

  if [ ! -r "$actual" ]; then
    echo "  SALTADA: la zona está en dns.conf pero $actual no se puede leer.";
    echo;
    RESULTADOS+=("$dom: SALTADA (la zona está en dns.conf pero su .conf no se puede leer)");
    SALTADAS=$((SALTADAS + 1));
    continue;
  fi;

  propuesta="$TMP/$dom.propuesta";

  if ! construir_propuesta "$origen" "$actual" "$propuesta"; then
    echo "  RECHAZADA: $MOTIVO";
    echo;
    RESULTADOS+=("$dom: RECHAZADA ($MOTIVO)");
    RECHAZADAS=$((RECHAZADAS + 1));
    continue;
  fi;

  echo;
  echo "  Registros ahora en el destino: $(contar_registros "$actual")  (MX: $(contar_mx "$actual"))";
  echo "  Registros en la propuesta    : $(contar_registros "$propuesta")  (MX: $(contar_mx "$propuesta"))";
  echo;

  if [ "${#AVISOS_ZONA[@]}" -gt 0 ]; then
    echo "  AVISOS de esta zona:";
    for a in "${AVISOS_ZONA[@]}"
    do
      echo "    - $a";
    done;
    echo;
  fi;

  echo "  --- diff: lo que el destino tiene ahora  ->  la propuesta ---";
  diff -u "$actual" "$propuesta";
  echo "  --- fin del diff ---";
  echo;

  TRATABLES+=("$dom");

done


if [ "$APLICAR" != "si" ]; then

  echo "============================================================";
  echo "RESUMEN (nada se ha escrito)";
  echo "============================================================";
  echo;

  for r in "${RESULTADOS[@]}"
  do
    echo "  $r";
  done;

  for dom in "${TRATABLES[@]}"
  do
    echo "  $dom: se cargaría";
  done;

  echo;
  echo "NO SE HA APLICADO NADA. Este servidor sigue exactamente como estaba.";
  echo "Cuando el diff de arriba convenza, repite la misma orden añadiendo";
  echo "--aplicar al final.";
  echo;

  if [ "$RECHAZADAS" -gt 0 ]; then
    exit 1;
  fi;

  exit 0;

fi;


# ============================================================
# === APLICAR ===
# ============================================================

if [ "${#TRATABLES[@]}" -eq 0 ]; then

  echo "============================================================";
  echo "No hay ninguna zona que se pueda cargar: no se escribe nada.";
  echo "============================================================";
  echo;

  for r in "${RESULTADOS[@]}"
  do
    echo "  $r";
  done;

  echo;
  exit 1;

fi;


SELLO="$(date '+%Y%m%d-%H%M%S')";
DIR_RESPALDO="$ZONAS_RESPALDO/$CUENTA-$SELLO";

if ! mkdir -p "$DIR_RESPALDO"; then
  morir "no se pudo crear el directorio de copias de seguridad: $DIR_RESPALDO. No se ha escrito nada.";
fi;

chmod 700 "$DIR_RESPALDO";

echo "============================================================";
echo "COPIAS DE SEGURIDAD";
echo "============================================================";
echo;
echo "  $DIR_RESPALDO";
echo;

# --- Copia de seguridad de cada zona, ANTES de cargar nada ---
RESPALDADAS=();

for dom in "${TRATABLES[@]}"
do

  actual="$DIR_CUENTA/dns/$dom.conf";

  if cp "$actual" "$DIR_RESPALDO/$dom.conf" \
     && cmp -s "$actual" "$DIR_RESPALDO/$dom.conf"; then

    chmod 600 "$DIR_RESPALDO/$dom.conf";
    echo "  $dom: copiada";
    RESPALDADAS+=("$dom");

  else

    echo "  $dom: FALLO al copiar: esta zona NO se toca.";
    RESULTADOS+=("$dom: FALLO (no se pudo hacer la copia de seguridad; la zona no se tocó)");

  fi;

done

echo;

if [ "${#RESPALDADAS[@]}" -eq 0 ]; then
  echo "Ninguna zona se pudo respaldar: no se carga nada.";
  echo;
  exit 1;
fi;


# --- El deshacer, ANTES de cargar la primera zona ---
DESHACER="$DIR_RESPALDO/deshacer-zonas.sh";

{
  echo "#!/bin/bash";
  echo;
  echo "# Deshace la carga de zonas hecha el $SELLO sobre la cuenta $CUENTA.";
  echo "# Reinserta cada zona tal como estaba justo antes. Se ejecuta en ESTE";
  echo "# servidor, como root. v-insert-dns-records MUEVE el archivo que se le";
  echo "# pasa, así que de cada copia se le da un duplicado y la copia se queda.";
  echo;
  echo "set -u";
  echo;
  echo "HESTIA_DIR=\"\${HESTIA_DIR:-$HESTIA_DIR}\";";
  echo "AQUI=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\";";
  echo;
  echo "ENTREGA=\"\$(mktemp -d)\";";
  echo "trap 'rm -rf -- \"\$ENTREGA\"' EXIT";
  echo;
  echo "fallos=0;";
  echo;

  for dom in "${RESPALDADAS[@]}"
  do
    echo "cp \"\$AQUI/$dom.conf\" \"\$ENTREGA/$dom.conf\" \\";
    echo "  && v-insert-dns-records $CUENTA $dom \"\$ENTREGA/$dom.conf\";";
    echo "if cmp -s \"\$HESTIA_DIR/data/users/$CUENTA/dns/$dom.conf\" \"\$AQUI/$dom.conf\"; then";
    echo "  echo \"$dom: restaurada\";";
    echo "else";
    echo "  echo \"$dom: FALLO al restaurar\" >&2;";
    echo "  fallos=\$((fallos + 1));";
    echo "fi;";
    echo;
  done

  echo "v-rebuild-dns-domains $CUENTA;";
  echo;
  echo "echo \"Comprueba con dig contra este servidor antes de dar nada por bueno.\";";
  echo;
  echo "[ \"\$fallos\" -eq 0 ];";

} > "$DESHACER"

chmod 700 "$DESHACER";

echo "  Para deshacer todo esto:";
echo "    bash $DESHACER";
echo;


# --- Cargar ---
echo "============================================================";
echo "CARGANDO";
echo "============================================================";
echo;

CARGADAS=0;
FALLIDAS=0;

for dom in "${RESPALDADAS[@]}"
do

  actual="$DIR_CUENTA/dns/$dom.conf";
  propuesta="$TMP/$dom.propuesta";
  respaldo="$DIR_RESPALDO/$dom.conf";

  # v-insert-dns-records MUEVE el archivo: se le da una copia,
  # para quedarnos con la propuesta y poder compararla después.
  entrega="$TMP/$dom.entrega";

  if ! cp "$propuesta" "$entrega"; then
    echo "  $dom: FALLO: no se pudo preparar el archivo a cargar. La zona no se tocó.";
    RESULTADOS+=("$dom: FALLO (no se pudo preparar el archivo a cargar; la zona no se tocó)");
    FALLIDAS=$((FALLIDAS + 1));
    continue;
  fi;

  v-insert-dns-records "$CUENTA" "$dom" "$entrega";
  codigo="$?";

  # El código de salida NO basta: con un archivo que no existe,
  # v-insert-dns-records sale 0 sin hacer nada (50-hestiacp.md).
  # Lo que decide es el contenido del .conf del destino.
  if [ "$codigo" -eq 0 ] && cmp -s "$actual" "$propuesta"; then

    echo "  $dom: CARGADA";
    RESULTADOS+=("$dom: CARGADA");
    CARGADAS=$((CARGADAS + 1));

  else

    if [ "$codigo" -ne 0 ]; then
      echo "  $dom: FALLO: v-insert-dns-records salió con código $codigo.";
    else
      echo "  $dom: FALLO: v-insert-dns-records salió con código 0 pero la zona del destino NO es la propuesta.";
    fi;

    if cp "$respaldo" "$actual" && cmp -s "$actual" "$respaldo"; then
      echo "    restaurada tal como estaba.";
      RESULTADOS+=("$dom: FALLO (restaurada tal como estaba)");
    else
      echo "    ATENCIÓN: NO se pudo restaurar. La copia está en $respaldo." >&2;
      RESULTADOS+=("$dom: FALLO (NO se pudo restaurar: la copia está en $respaldo)");
    fi;

    FALLIDAS=$((FALLIDAS + 1));

  fi;

done

echo;


# --- Regenerar, una sola vez ---
CODIGO_REBUILD=0;

if [ "$CARGADAS" -gt 0 ]; then

  echo "============================================================";
  echo "REGENERANDO LAS ZONAS DE «$CUENTA»";
  echo "============================================================";
  echo;

  v-rebuild-dns-domains "$CUENTA";
  CODIGO_REBUILD="$?";

  if [ "$CODIGO_REBUILD" -ne 0 ]; then
    echo;
    echo "  AVISO: v-rebuild-dns-domains salió con código $CODIGO_REBUILD. Las copias de";
    echo "  seguridad siguen en $DIR_RESPALDO y deshacer-zonas.sh está ahí.";
  fi;

  echo;
  echo "  El código de salida de v-rebuild-dns-domains IGNORA el del reinicio del";
  echo "  DNS: que haya salido bien no demuestra que bind esté sirviendo las zonas";
  echo "  nuevas. COMPRUEBA CON dig CONTRA EL SERVIDOR NUEVO antes de cambiar los NS:";
  echo;

  for dom in "${TRATABLES[@]}"
  do
    echo "    dig @<IP de este servidor> $dom SOA +norecurse";
    echo "    dig @<IP de este servidor> $dom MX  +norecurse";
  done;

  echo;
  echo "  El serial de la zona NO ha cambiado: un esclavo que ya la tenga puede";
  echo "  seguir sirviendo la versión vieja hasta que expire.";
  echo;

fi;


# ============================================================
# === RESUMEN ===
# ============================================================

echo "============================================================";
echo "RESUMEN";
echo "============================================================";
echo;

for r in "${RESULTADOS[@]}"
do
  echo "  $r";
done;

echo;
echo "  Cargadas: $CARGADAS   Falladas: $FALLIDAS   Saltadas: $SALTADAS   Rechazadas: $RECHAZADAS";
echo;
echo "  Copias de seguridad: $DIR_RESPALDO";
echo "  Deshacer           : bash $DESHACER";
echo;

if [ "$FALLIDAS" -gt 0 ] || [ "$RECHAZADAS" -gt 0 ] || [ "$CODIGO_REBUILD" -ne 0 ]; then
  exit 1;
fi;

exit 0;
