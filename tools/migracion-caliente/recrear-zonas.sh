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

# Las órdenes del panel se llaman por RUTA ABSOLUTA, nunca por
# nombre: bajo sudo, secure_path no incluye el bin de HestiaCP
# y la orden saldría con 127 sin haber hecho nada.
HESTIA_BIN="${HESTIA_BIN:-$HESTIA_DIR/bin}";
V_INSERT="$HESTIA_BIN/v-insert-dns-records";
V_REBUILD="$HESTIA_BIN/v-rebuild-dns-domains";


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

# Las órdenes del panel, comprobadas antes de prometer nada: si
# no están donde se espera, se dice ahora y no a mitad de una
# carga.
if [ "$APLICAR" = "si" ]; then
  [ -x "$V_INSERT" ]  || morir "no se encuentra o no es ejecutable: $V_INSERT. Si el panel está en otro sitio, pasa HESTIA_DIR.";
  [ -x "$V_REBUILD" ] || morir "no se encuentra o no es ejecutable: $V_REBUILD. Si el panel está en otro sitio, pasa HESTIA_DIR.";
fi;


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
#
# El patrón Y el reemplazo van ENTRE COMILLAS. Sin comillas, el
# patrón de ${x/patrón/reemplazo} se interpreta como glob —un
# '[' o un '*' en el valor cambiarían a qué casa— y en bash 5.2
# un '&' en el reemplazo se expande al texto que casó
# (patsub_replacement). Los valores de una zona llevan los dos:
# un SPF con 'a:[...]', un TXT con '&'.
cambiar_valor() {
  local linea="$1" viejo="$2" nuevo="$3";
  printf '%s' "${linea/"VALUE='$viejo'"/"VALUE='$nuevo'"}";
}


# Renumera el ID de la línea. Mismas comillas, por lo mismo.
cambiar_id() {
  local linea="$1" viejo="$2" nuevo="$3";
  printf '%s' "${linea/"ID='$viejo'"/"ID='$nuevo'"}";
}


# El token ip4: del SPF, anclado por la derecha para que una
# IP no case dentro de otra más larga (203.0.113.1 dentro de
# 203.0.113.10).
#
cambiar_ip4() {

  local valor="$1";
  local escapada="${IP_ORIGEN//./\\.}";

  printf '%s' "$valor" \
    | sed -E "s/ip4:${escapada}([^0-9.]|\$)/ip4:${IP_DESTINO}\1/g";
}


# Cierto si el valor lleva un ip4 con máscara (ip4:IP/24): ahí
# lo que se autoriza es una RED entera, no una IP, y cambiarla
# de sitio lo tiene que mirar una persona.
#
# Se comprueba desde el llamador y no dentro de cambiar_ip4: esa
# se invoca en una sustitución de comandos, y una variable que
# cambia dentro de un subshell no sobrevive al subshell
# (.agents/context/30-trampas.md).
lleva_ip4_con_prefijo() {

  local valor="$1";
  local escapada="${IP_ORIGEN//./\\.}";

  printf '%s\n' "$valor" | grep -qE "ip4:${escapada}/[0-9]";
}


# Cierto si el valor contiene la IP de origen COMO TAL, no como
# trozo de otra más larga: con origen 203.0.113.1, el valor
# 203.0.113.10 no la contiene.
contiene_ip_origen() {

  local valor="$1";
  local escapada="${IP_ORIGEN//./\\.}";

  printf '%s\n' "$valor" \
    | grep -qE "(^|[^0-9.])${escapada}([^0-9.]|\$)";
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

# Comprueba que la línea ya leída solo lleva claves de una zona
# DNS de HestiaCP. Deja el motivo en MOTIVO y devuelve 1 si no.
# Vale para las líneas del origen Y para las del destino: una
# línea del destino con una clave rara se copiaría igual de mal
# a la propuesta.
claves_conocidas() {

  local linea="$1" donde="$2";
  local clave;

  for clave in "${CLAVES_ORDEN[@]}"
  do
    case "$CLAVES_VALIDAS" in
      *" $clave "*) ;;
      *)
        MOTIVO="la línea «$linea» ($donde) lleva la clave «$clave», que no es de una zona DNS de HestiaCP. La zona no se carga.";
        return 1;
        ;;
    esac;
  done;

  if [ -z "${CAMPO[ID]:-}" ] || [ -z "${CAMPO[RECORD]:-}" ] || [ -z "${CAMPO[TYPE]:-}" ]; then
    MOTIVO="la línea «$linea» ($donde) no tiene ID, RECORD o TYPE. La zona no se carga.";
    return 1;
  fi;

  return 0;
}

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

    claves_conocidas "$linea" "la zona que el destino tiene ahora" || return 1;

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
  local valor tipo nueva valor_nuevo prefijo;

  while IFS= read -r linea || [ -n "$linea" ]
  do

    [ -n "${linea//[[:space:]]/}" ] || continue;

    if ! parsear_linea "$linea"; then
      MOTIVO="línea del origen que no se puede leer: «$linea»";
      return 1;
    fi;

    claves_conocidas "$linea" "la zona exportada del origen" || return 1;

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

      # Si la línea no cambió, la sustitución NO se hizo y la
      # zona se cargaría con la IP vieja. No se calla.
      if [ "$nueva" = "$linea" ]; then
        AVISOS_ZONA+=("el registro «${CAMPO[RECORD]}» ($tipo) valía exactamente la IP del origen pero la línea no se pudo reescribir: «$linea». REVÍSALO: se cargaría con la IP vieja.");
      else
        valor="$IP_DESTINO";
      fi;

    elif [ "$tipo" = "TXT" ]; then

      prefijo="no";

      if lleva_ip4_con_prefijo "$valor"; then
        prefijo="si";
      fi;

      valor_nuevo="$(cambiar_ip4 "$valor")";

      if [ "$valor_nuevo" != "$valor" ]; then

        nueva="$(cambiar_valor "$linea" "$valor" "$valor_nuevo")";

        if [ "$nueva" = "$linea" ]; then
          AVISOS_ZONA+=("el registro «${CAMPO[RECORD]}» (TXT) lleva un ip4: con la IP del origen pero la línea no se pudo reescribir: «$linea». REVÍSALO: se cargaría con la IP vieja.");
        else
          valor="$valor_nuevo";
        fi;

        if [ "$prefijo" = "si" ]; then
          AVISOS_ZONA+=("el registro «${CAMPO[RECORD]}» (TXT) llevaba un ip4 con prefijo /N y se ha reescrito: eso autoriza una RED entera, no una IP. Revísalo: la red del servidor nuevo puede no ser la misma.");
        fi;

      fi;

    fi;

    # --- Avisos que NO bloquean ---
    # La comprobación va anclada igual que la sustitución: con
    # origen 203.0.113.1, un valor 203.0.113.10 no la contiene y
    # no debe disparar este aviso.
    if contiene_ip_origen "$valor"; then
      AVISOS_ZONA+=("el registro «${CAMPO[RECORD]}» ($tipo) sigue conteniendo la IP del origen después de la sustitución: «$valor». Revísalo a mano.");
    fi;

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
CARGADAS=0;
FALLIDAS=0;

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
    FALLIDAS=$((FALLIDAS + 1));

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

# Cada dato que entra en el script generado va con printf %q:
# un nombre de cuenta o de dominio con un carácter raro no debe
# poder convertirse en una orden dentro del deshacer. Las
# órdenes del panel van con su ruta absoluta ya expandida: el
# deshacer puede correrse bajo sudo, donde el PATH no las
# alcanza.
{
  printf '#!/bin/bash\n';
  printf '\n';
  printf '# Deshace la carga de zonas hecha el %s sobre la cuenta %s.\n' "$SELLO" "$CUENTA";
  printf '# Reinserta cada zona tal como estaba justo antes. Se ejecuta en ESTE\n';
  printf '# servidor, como root. v-insert-dns-records MUEVE el archivo que se le\n';
  printf '# pasa, así que de cada copia se le da un duplicado y la copia se queda.\n';
  printf '\n';
  printf 'set -u\n';
  printf '\n';
  printf 'V_INSERT=%q;\n'  "$V_INSERT";
  printf 'V_REBUILD=%q;\n' "$V_REBUILD";
  printf 'CUENTA=%q;\n'    "$CUENTA";
  printf 'DIR_ZONAS=%q;\n' "$DIR_CUENTA/dns";
  printf 'AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";\n';
  printf '\n';
  printf 'ENTREGA="$(mktemp -d)";\n';
  printf 'trap '"'"'rm -rf -- "$ENTREGA"'"'"' EXIT\n';
  printf '\n';
  printf 'fallos=0;\n';
  printf '\n';

  for dom in "${RESPALDADAS[@]}"
  do
    printf 'dom=%q;\n' "$dom";
    printf 'cp "$AQUI/$dom.conf" "$ENTREGA/$dom.conf" \\\n';
    printf '  && "$V_INSERT" "$CUENTA" "$dom" "$ENTREGA/$dom.conf";\n';
    printf 'if cmp -s "$DIR_ZONAS/$dom.conf" "$AQUI/$dom.conf"; then\n';
    printf '  echo "$dom: restaurada";\n';
    printf 'else\n';
    printf '  echo "$dom: FALLO al restaurar" >&2;\n';
    printf '  fallos=$((fallos + 1));\n';
    printf 'fi;\n';
    printf '\n';
  done

  printf '"$V_REBUILD" "$CUENTA";\n';
  printf '\n';
  printf 'echo "Comprueba con dig contra este servidor antes de dar nada por bueno.";\n';
  printf '\n';
  printf '[ "$fallos" -eq 0 ];\n';

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

  "$V_INSERT" "$CUENTA" "$dom" "$entrega";
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

  "$V_REBUILD" "$CUENTA";
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
