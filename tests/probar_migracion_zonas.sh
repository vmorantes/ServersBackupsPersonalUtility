#!/usr/bin/env bash
# =============================================================================
# tests/probar_migracion_zonas.sh — recrear las zonas DNS en el destino
# =============================================================================
# recrear-zonas.sh escribe en el panel de un servidor y lo que escribe es el
# DNS: si se equivoca, el dominio deja de resolver. Aquí no hay servidor, así
# que se prueba contra un árbol de HestiaCP falso y con órdenes del panel
# falsas, que es lo único que permite probar también los CAMINOS DE FALLO:
#
#   - v-insert-dns-records sale 0 SIN mover el archivo (el falso éxito que
#     50-hestiacp.md documenta): tiene que detectarse y dejar el original
#     intacto;
#   - v-insert-dns-records sale 3: igual.
#
# Todo el árbol es inventado: example.org, 203.0.113.10 y 203.0.113.20
# (RFC 5737), cuenta "cuenta1".
# =============================================================================
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_migracion_zonas.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_migracion_zonas =="

GUION="$BANCO_RAIZ/tools/migracion-caliente/recrear-zonas.sh"

IP_VIEJA="203.0.113.10"
IP_NUEVA="203.0.113.20"

# -----------------------------------------------------------------------------
# El árbol falso: las zonas exportadas del viejo y el panel del nuevo
# -----------------------------------------------------------------------------
# El destino tiene las zonas recién creadas desde plantilla: sus propios NS,
# su propia IP, su propio MX y su propia clave DKIM. El origen trae la zona
# de verdad, con los NS y la DKIM del servidor viejo.
sembrar() {
  local raiz="$1"

  local H="$raiz/hestia"
  local Z="$raiz/zonas/cuenta1"

  mkdir -p "$H/data/users/cuenta1/dns" "$Z" "$raiz/respaldos"

  # --- dns.conf del DESTINO: las zonas que existen aquí ---
  cat > "$H/data/users/cuenta1/dns.conf" <<'FIN'
DOMAIN='example.org' IP='203.0.113.20' TPL='default' TTL='14400' EXP='2027-01-01' SOA='ns1.nuevo.example.org' RECORDS='5' DNSSEC='no' SUSPENDED='no'
DOMAIN='otra.example.org' IP='203.0.113.20' TPL='default' TTL='14400' EXP='2027-01-01' SOA='ns1.nuevo.example.org' RECORDS='3' DNSSEC='no' SUSPENDED='no'
DOMAIN='rara.example.org' IP='203.0.113.20' TPL='default' TTL='14400' EXP='2027-01-01' SOA='ns1.nuevo.example.org' RECORDS='3' DNSSEC='no' SUSPENDED='no'
FIN

  # --- example.org en el DESTINO: plantilla, con su MX y su DKIM ---
  cat > "$H/data/users/cuenta1/dns/example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.nuevo.example.org.' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
ID='2' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns2.nuevo.example.org.' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
ID='3' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.20' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
ID='4' RECORD='@' TYPE='MX' PRIORITY='0' VALUE='mail.example.org.' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
ID='5' RECORD='mail._domainkey' TYPE='TXT' PRIORITY='' VALUE='"v=DKIM1; k=rsa; p=CLAVE-DEL-NUEVO"' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
FIN

  # --- otra.example.org en el DESTINO: plantilla SIN clave DKIM ---
  cat > "$H/data/users/cuenta1/dns/otra.example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.nuevo.example.org.' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
ID='2' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.20' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
FIN

  # --- rara.example.org en el DESTINO: normal; lo raro está en el origen ---
  cat > "$H/data/users/cuenta1/dns/rara.example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.nuevo.example.org.' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
ID='2' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.20' SUSPENDED='no' TIME='09:00:00' DATE='2026-10-17'
FIN

  # =========================================================================
  # Las zonas EXPORTADAS del servidor viejo
  # =========================================================================
  # Los ID vienen con huecos a propósito (1, 2, 3, 7, 9, 11, 12, 13, 14):
  # el resultado tiene que quedar renumerado de 1 a N.
  cat > "$Z/example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.viejo.example.org.' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='2' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns2.viejo.example.org.' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='3' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.10' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='7' RECORD='mail' TYPE='A' PRIORITY='' VALUE='203.0.113.10' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='9' RECORD='@' TYPE='MX' PRIORITY='10' VALUE='mail.example.org.' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='11' RECORD='@' TYPE='TXT' PRIORITY='' VALUE='"v=spf1 a mx ip4:203.0.113.10 -all"' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='12' RECORD='mail._domainkey' TYPE='TXT' PRIORITY='' VALUE='"v=DKIM1; k=rsa; p=CLAVE-DEL-VIEJO"' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='13' RECORD='externo' TYPE='A' PRIORITY='' VALUE='198.51.100.7' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='14' RECORD='nota' TYPE='TXT' PRIORITY='' VALUE='"servidor viejo 203.0.113.10 en texto"' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
FIN

  # Sin clave DKIM en el origen, y el destino tampoco tiene: no debe
  # aparecerse ninguna.
  cat > "$Z/otra.example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.viejo.example.org.' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='4' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.10' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
FIN

  # Una clave que no es de una zona DNS de HestiaCP: la zona entera se
  # rechaza, no se carga a medias.
  cat > "$Z/rara.example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.viejo.example.org.' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='2' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.10' INVENTADA='si' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
FIN

  # Exportada del viejo, pero en el destino NO existe: se salta.
  cat > "$Z/falta.example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.viejo.example.org.' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='2' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.10' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
FIN
}

# Suma de TODO el árbol del panel: ruta, modo y contenido. Si el script
# escribe, borra o cambia un permiso de cualquier cosa, esta suma cambia.
suma_del_arbol() {
  local raiz="$1"
  {
    find "$raiz" -type f -printf '%m %P\n' 2>/dev/null | LC_ALL=C sort
    find "$raiz" -type d -printf 'D %m %P\n' 2>/dev/null | LC_ALL=C sort
    find "$raiz" -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r cat 2>/dev/null
  } | sha256sum | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# Las órdenes del panel, falsas
# -----------------------------------------------------------------------------
# v-insert-dns-records de verdad MUEVE el archivo que se le pasa al .conf de
# la zona. El falso hace ese mv real, para que lo que se comprueba después sea
# el árbol, y obedece a $FALSO_MODO:
#
#   normal       mueve y sale 0 (lo que hace el de verdad)
#   silencioso0  NO mueve y sale 0 — el falso éxito de 50-hestiacp.md
#   codigo3      NO mueve y sale 3 — la zona no existe
#
# v-rebuild-dns-domains solo apunta su invocación: aquí no hay bind.
montar_falsos() {
  local dir="$1" registro="$2"
  mkdir -p "$dir"
  : > "$registro"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "insert %%s\\n" "$*" >> %q\n' "$registro"
    printf 'cuenta="$1"; dominio="$2"; archivo="$3"\n'
    printf 'case "${FALSO_MODO:-normal}" in\n'
    printf '  silencioso0) exit 0 ;;\n'
    printf '  codigo3)     exit 3 ;;\n'
    printf 'esac\n'
    printf 'destino="$HESTIA_DIR/data/users/$cuenta/dns/$dominio.conf"\n'
    printf '[[ -f "$destino" ]] || exit 3\n'
    printf 'mv "$archivo" "$destino" || exit 4\n'
    printf 'exit 0\n'
  } > "$dir/v-insert-dns-records"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "rebuild %%s\\n" "$*" >> %q\n' "$registro"
    printf 'exit 0\n'
  } > "$dir/v-rebuild-dns-domains"

  chmod +x "$dir/v-insert-dns-records" "$dir/v-rebuild-dns-domains"
  printf '%s' "$dir:$PATH"
}

# Corre el script sobre el árbol falso. Deja stdout y stderr en archivos y
# devuelve su código de salida.
correr() {
  local raiz="$1" ruta_path="$2" modo="$3" salida_std="$4" salida_err="$5"
  shift 5
  env -i \
    HOME="${HOME:-/tmp}" \
    PATH="$ruta_path" \
    LANG=C.UTF-8 \
    HESTIA_DIR="$raiz/hestia" \
    ZONAS_RESPALDO="$raiz/respaldos" \
    FALSO_MODO="$modo" \
    bash "$GUION" "$@" > "$salida_std" 2> "$salida_err"
}

# El directorio de respaldo que creó la corrida.
dir_de_respaldo() {
  find "$1/respaldos" -maxdepth 1 -type d -name 'cuenta1-*' 2>/dev/null | head -1
}

# La zona tal como quedó en el panel del destino.
zona_destino() {
  printf '%s' "$1/hestia/data/users/cuenta1/dns/$2.conf"
}

# -----------------------------------------------------------------------------
# V1: la validación rechaza antes de tocar nada
# -----------------------------------------------------------------------------
test_bad_arguments_change_nothing() {
  nueva_prueba mz_v1
  local d="$BANCO_TMP/mz_v1"
  local raiz="$d/arbol"
  sembrar "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  local antes
  antes="$(suma_del_arbol "$raiz")"

  # --- Sin --ip-origen ---
  correr "$raiz" "$ruta_path" normal "$d/o1.txt" "$d/e1.txt" \
    --cuenta cuenta1 --zonas "$raiz/zonas/cuenta1" --ip-destino "$IP_NUEVA" --aplicar
  afirmar_codigo 2 "$?" "V1: sin --ip-origen sale con código 2"
  afirmar_contiene "$d/e1.txt" "falta --ip-origen" \
    "V1: y dice qué falta"

  # --- Las dos IP iguales ---
  correr "$raiz" "$ruta_path" normal "$d/o2.txt" "$d/e2.txt" \
    --cuenta cuenta1 --zonas "$raiz/zonas/cuenta1" \
    --ip-origen "$IP_NUEVA" --ip-destino "$IP_NUEVA" --aplicar
  afirmar_codigo 2 "$?" "V1: dos IP iguales salen con código 2"
  afirmar_contiene "$d/e2.txt" "son la misma IP" \
    "V1: y dice por qué"

  # --- Una IP que no es IPv4 ---
  correr "$raiz" "$ruta_path" normal "$d/o3.txt" "$d/e3.txt" \
    --cuenta cuenta1 --zonas "$raiz/zonas/cuenta1" \
    --ip-origen "no.es.una.ip" --ip-destino "$IP_NUEVA" --aplicar
  afirmar_codigo 2 "$?" "V1: una IP mal formada sale con código 2"

  # --- Un directorio de zonas que no existe ---
  correr "$raiz" "$ruta_path" normal "$d/o4.txt" "$d/e4.txt" \
    --cuenta cuenta1 --zonas "$raiz/no-existe" \
    --ip-origen "$IP_VIEJA" --ip-destino "$IP_NUEVA" --aplicar
  afirmar_codigo 2 "$?" "V1: un directorio de zonas que no existe sale con código 2"

  # --- Una cuenta que no está en este panel ---
  correr "$raiz" "$ruta_path" normal "$d/o5.txt" "$d/e5.txt" \
    --cuenta cuenta9 --zonas "$raiz/zonas/cuenta1" \
    --ip-origen "$IP_VIEJA" --ip-destino "$IP_NUEVA" --aplicar
  afirmar_codigo 2 "$?" "V1: una cuenta sin dns.conf en el destino sale con código 2"

  afirmar_igual "$(suma_del_arbol "$raiz")" "$antes" \
    "V1: ninguna validación fallida tocó el árbol"
  afirmar_igual "$(wc -c < "$d/registro.txt" | tr -d ' ')" "0" \
    "V1: ni invocó ninguna orden del panel"
}

# -----------------------------------------------------------------------------
# D1: sin --aplicar no se escribe nada
# -----------------------------------------------------------------------------
test_dry_run_writes_nothing() {
  nueva_prueba mz_d1
  local d="$BANCO_TMP/mz_d1"
  local raiz="$d/arbol"
  sembrar "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  local antes
  antes="$(suma_del_arbol "$raiz")"

  correr "$raiz" "$ruta_path" normal "$d/stdout.txt" "$d/stderr.txt" \
    --cuenta cuenta1 --zonas "$raiz/zonas/cuenta1" \
    --ip-origen "$IP_VIEJA" --ip-destino "$IP_NUEVA"
  local rc=$?

  # Hay una zona rechazada (rara.example.org), así que el código es 1: el
  # modo diff no es "siempre 0", informa de lo que no se podría cargar.
  afirmar_codigo 1 "$rc" "D1: con una zona rechazada, el modo diff sale con código 1"

  afirmar_igual "$(suma_del_arbol "$raiz")" "$antes" \
    "D1: sin --aplicar el árbol del destino queda con la misma suma sha256"
  afirmar_igual "$(wc -c < "$d/registro.txt" | tr -d ' ')" "0" \
    "D1: sin --aplicar no se invocó ninguna orden del panel"
  afirmar_igual "$(test -d "$raiz/respaldos" && find "$raiz/respaldos" -mindepth 1 | wc -l | tr -d ' ')" "0" \
    "D1: sin --aplicar no se crea ninguna copia de seguridad"

  afirmar_contiene "$d/stdout.txt" "NO SE HA APLICADO NADA" \
    "D1: y lo dice con todas las letras"
  afirmar_contiene "$d/stdout.txt" "^\+.*TYPE='MX' PRIORITY='10'" \
    "D1: el diff muestra el MX del origen entrando"
  afirmar_contiene "$d/stdout.txt" "^-.*TYPE='MX' PRIORITY='0'" \
    "D1: y el MX de la plantilla saliendo"
  afirmar_contiene "$d/stdout.txt" "Registros en la propuesta" \
    "D1: y el resumen de registros antes/después"
  afirmar_contiene "$d/stdout.txt" "example.org: se cargaría" \
    "D1: y qué zonas se cargarían"
}

# -----------------------------------------------------------------------------
# A1: la carga, con todo lo que tiene que cambiar y lo que no
# -----------------------------------------------------------------------------
CARGA_DIR=""
CARGA_RAIZ=""

test_apply_rewrites_ip_ns_and_dkim() {
  nueva_prueba mz_a1
  local d="$BANCO_TMP/mz_a1"
  CARGA_DIR="$d"
  local raiz="$d/arbol"
  CARGA_RAIZ="$raiz"
  sembrar "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  correr "$raiz" "$ruta_path" normal "$d/stdout.txt" "$d/stderr.txt" \
    --cuenta cuenta1 --zonas "$raiz/zonas/cuenta1" \
    --ip-origen "$IP_VIEJA" --ip-destino "$IP_NUEVA" --aplicar
  local rc=$?

  # rara.example.org se rechaza y falta.example.org se salta: el código tiene
  # que decirlo, aunque las otras dos se hayan cargado bien.
  afirmar_codigo 1 "$rc" "A1: con una zona rechazada el código de salida es 1"

  local zona
  zona="$(zona_destino "$raiz" example.org)"
  afirmar_existe "$zona" "A1: la zona sigue en su sitio"

  # --- La IP, en los tres sitios de la plantilla ---
  afirmar_contiene "$zona" "RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.20'" \
    "A1: la IP del @ A es la del destino"
  afirmar_contiene "$zona" "RECORD='mail' TYPE='A' PRIORITY='' VALUE='203.0.113.20'" \
    "A1: y la del mail A"
  afirmar_contiene "$zona" "v=spf1 a mx ip4:203.0.113.20 -all" \
    "A1: y la del ip4: del SPF"
  afirmar_no_contiene "$zona" "VALUE='203.0.113.10'" \
    "A1: no queda ningún VALUE con la IP del origen"

  # --- Los NS: los del destino, no los del viejo ---
  afirmar_contiene "$zona" "TYPE='NS' PRIORITY='' VALUE='ns1.nuevo.example.org.'" \
    "A1: el NS1 es el del destino"
  afirmar_contiene "$zona" "TYPE='NS' PRIORITY='' VALUE='ns2.nuevo.example.org.'" \
    "A1: y el NS2 también"
  afirmar_no_contiene "$zona" "viejo.example.org" \
    "A1: no queda ningún NS del servidor viejo"

  # --- La clave DKIM: la del destino ---
  afirmar_contiene "$zona" "p=CLAVE-DEL-NUEVO" \
    "A1: mail._domainkey es el del destino"
  afirmar_no_contiene "$zona" "CLAVE-DEL-VIEJO" \
    "A1: la clave DKIM del viejo no se copia"

  # --- Un solo MX: el del origen, no el de la plantilla ---
  afirmar_igual "$(grep -c "TYPE='MX'" "$zona")" "1" \
    "A1: queda UN solo MX, no dos"
  afirmar_contiene "$zona" "TYPE='MX' PRIORITY='10' VALUE='mail.example.org.'" \
    "A1: y es el del origen, con su prioridad"

  # --- Los ID, 1..N y únicos ---
  local ids
  ids="$(grep -oE "^ID='[0-9]+'" "$zona" | sed -E "s/ID='([0-9]+)'/\1/")"
  afirmar_igual "$(printf '%s\n' "$ids" | tr '\n' ' ' | sed 's/ $//')" "1 2 3 4 5 6 7 8 9" \
    "A1: los ID van de 1 a N, en orden y sin huecos"
  afirmar_igual "$(printf '%s\n' "$ids" | sort -u | wc -l | tr -d ' ')" "9" \
    "A1: y son únicos"

  # --- Lo que NO se toca ---
  afirmar_contiene "$zona" "RECORD='externo' TYPE='A' PRIORITY='' VALUE='198.51.100.7'" \
    "A1: un A que apunta fuera se copia tal cual"
  afirmar_contiene "$zona" "TIME='08:00:00' DATE='2025-03-04'" \
    "A1: TIME y DATE del origen se conservan literales"

  # --- Los avisos que no bloquean ---
  afirmar_contiene "$d/stdout.txt" "sigue conteniendo la IP del origen" \
    "A1: avisa del TXT que lleva la IP vieja en texto libre"
  afirmar_contiene "$d/stdout.txt" "no es ninguna de las dos IP" \
    "A1: y del A que apunta a una IP de fuera"

  # --- La zona sin DKIM en ninguno de los dos lados ---
  local otra
  otra="$(zona_destino "$raiz" otra.example.org)"
  afirmar_no_contiene "$otra" "mail._domainkey" \
    "A1: sin clave DKIM en el destino, no queda la del origen"
  afirmar_contiene "$otra" "VALUE='ns1.nuevo.example.org.'" \
    "A1: y sus NS también son los del destino"

  # --- La zona con una clave desconocida: rechazada ENTERA ---
  local rara
  rara="$(zona_destino "$raiz" rara.example.org)"
  afirmar_contiene "$rara" "VALUE='203.0.113.20'" \
    "A1: la zona rechazada se quedó como estaba en el destino"
  afirmar_no_contiene "$rara" "INVENTADA" \
    "A1: nada de la zona rechazada llegó al destino"
  afirmar_contiene "$d/stdout.txt" "rara.example.org: RECHAZADA" \
    "A1: y el resumen dice que se rechazó"
  afirmar_contiene "$d/stdout.txt" "la clave «INVENTADA»" \
    "A1: nombrando la clave que no se supo leer"

  # --- La zona que falta en el destino: SALTADA, y las demás siguen ---
  afirmar_contiene "$d/stdout.txt" "falta.example.org: SALTADA" \
    "A1: una zona que no existe en el destino se salta"
  afirmar_contiene "$d/stdout.txt" "créala con la fase 1 de la migración" \
    "A1: y dice cómo crearla"
  afirmar_contiene "$d/stdout.txt" "example.org: CARGADA" \
    "A1: y las zonas buenas se cargan igual"

  # --- El rebuild: UNA sola vez, y después de cargar ---
  afirmar_igual "$(grep -c '^rebuild ' "$d/registro.txt")" "1" \
    "A1: v-rebuild-dns-domains se llamó exactamente una vez"
  afirmar_contiene "$d/registro.txt" "^rebuild cuenta1$" \
    "A1: con la cuenta como único argumento"
  afirmar_igual "$(grep -c '^insert ' "$d/registro.txt")" "2" \
    "A1: y v-insert-dns-records una vez por zona cargable"

  # --- Lo que hay que comprobar a mano ---
  afirmar_contiene "$d/stdout.txt" "dig @<IP de este servidor> example.org SOA" \
    "A1: la salida deja el dig a correr contra el servidor nuevo"
  afirmar_contiene "$d/stdout.txt" "serial de la zona NO ha cambiado" \
    "A1: y avisa de que el serial no cambia"
}

# -----------------------------------------------------------------------------
# A2: las copias de seguridad y el deshacer
# -----------------------------------------------------------------------------
# Depende de la corrida de A1: se mira lo que dejó.
test_backups_and_undo_script() {
  nueva_prueba mz_a2
  local d="$CARGA_DIR"
  local raiz="$CARGA_RAIZ"

  local resp
  resp="$(dir_de_respaldo "$raiz")"
  afirmar_igual "$(test -n "$resp" && echo si || echo no)" "si" \
    "A2: se creó el directorio de copias de seguridad"
  afirmar_existe "$resp/example.org.conf" "A2: con la copia de la zona"
  afirmar_existe "$resp/deshacer-zonas.sh" "A2: y con el deshacer"

  afirmar_igual "$(stat -c '%a' "$resp" 2>/dev/null)" "700" \
    "A2: el directorio de respaldo es 700"
  afirmar_igual "$(stat -c '%a' "$resp/example.org.conf" 2>/dev/null)" "600" \
    "A2: y la copia es 600"

  # La copia es la zona de ANTES: lleva los NS del viejo todavía no, lleva
  # los del destino de plantilla, y la IP del destino.
  afirmar_contiene "$resp/example.org.conf" "PRIORITY='0' VALUE='mail.example.org.'" \
    "A2: la copia es la zona de plantilla que había antes de cargar"

  # --- El deshacer, ejecutado de verdad contra el árbol falso ---
  local zona
  zona="$(zona_destino "$raiz" example.org)"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin2" "$d/registro2.txt")"

  env -i HOME="${HOME:-/tmp}" PATH="$ruta_path" LANG=C.UTF-8 \
    HESTIA_DIR="$raiz/hestia" FALSO_MODO=normal \
    bash "$resp/deshacer-zonas.sh" > "$d/deshacer.txt" 2>&1
  afirmar_codigo 0 "$?" "A2: el deshacer termina bien"

  afirmar_intacto "$zona" "$resp/example.org.conf" \
    "A2: tras deshacer, la zona está byte a byte como antes de cargarla"
  afirmar_contiene "$d/registro2.txt" "^rebuild cuenta1$" \
    "A2: y el deshacer también regenera las zonas"
  afirmar_existe "$resp/example.org.conf" \
    "A2: la copia sigue ahí: v-insert-dns-records movió un duplicado, no la copia"
}

# -----------------------------------------------------------------------------
# F1: camino de fallo — el falso éxito (código 0 sin mover nada)
# -----------------------------------------------------------------------------
# Es el fallo que de verdad importa: v-insert-dns-records sale 0 sin haber
# hecho nada (50-hestiacp.md). Fiarse del código de salida daría la zona por
# cargada sin que lo esté.
test_silent_zero_is_detected_and_original_survives() {
  nueva_prueba mz_f1
  local d="$BANCO_TMP/mz_f1"
  local raiz="$d/arbol"
  sembrar "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  local zona
  zona="$(zona_destino "$raiz" example.org)"
  cp "$zona" "$d/antes-example.org.conf"

  correr "$raiz" "$ruta_path" silencioso0 "$d/stdout.txt" "$d/stderr.txt" \
    --cuenta cuenta1 --zonas "$raiz/zonas/cuenta1" --dominio example.org \
    --ip-origen "$IP_VIEJA" --ip-destino "$IP_NUEVA" --aplicar
  afirmar_codigo 1 "$?" "F1: un falso éxito hace que el script salga con código 1"

  afirmar_contiene "$d/stdout.txt" "salió con código 0 pero la zona del destino NO es la propuesta" \
    "F1: y lo dice sin rodeos"
  afirmar_contiene "$d/stdout.txt" "example.org: FALLO" \
    "F1: el resumen marca la zona como FALLO"
  afirmar_no_contiene "$d/stdout.txt" "example.org: CARGADA" \
    "F1: y NO la da por cargada"

  afirmar_intacto "$zona" "$d/antes-example.org.conf" \
    "F1: la zona del destino quedó intacta"

  local resp
  resp="$(dir_de_respaldo "$raiz")"
  afirmar_intacto "$zona" "$resp/example.org.conf" \
    "F1: y coincide con su copia de seguridad"

  afirmar_igual "$(grep -c '^rebuild ' "$d/registro.txt" || true)" "0" \
    "F1: sin ninguna zona cargada, v-rebuild-dns-domains NO se llama"
}

# -----------------------------------------------------------------------------
# F2: camino de fallo — código de salida distinto de 0
# -----------------------------------------------------------------------------
test_nonzero_exit_leaves_the_zone_untouched() {
  nueva_prueba mz_f2
  local d="$BANCO_TMP/mz_f2"
  local raiz="$d/arbol"
  sembrar "$raiz"

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  local zona
  zona="$(zona_destino "$raiz" example.org)"
  cp "$zona" "$d/antes-example.org.conf"

  correr "$raiz" "$ruta_path" codigo3 "$d/stdout.txt" "$d/stderr.txt" \
    --cuenta cuenta1 --zonas "$raiz/zonas/cuenta1" --dominio example.org \
    --ip-origen "$IP_VIEJA" --ip-destino "$IP_NUEVA" --aplicar
  afirmar_codigo 1 "$?" "F2: con código 3 del panel, el script sale con código 1"

  afirmar_contiene "$d/stdout.txt" "v-insert-dns-records salió con código 3" \
    "F2: y dice qué código fue"
  afirmar_contiene "$d/stdout.txt" "restaurada tal como estaba" \
    "F2: y que restauró la zona"

  afirmar_intacto "$zona" "$d/antes-example.org.conf" \
    "F2: la zona del destino quedó intacta"

  afirmar_igual "$(grep -c '^rebuild ' "$d/registro.txt" || true)" "0" \
    "F2: tampoco se regenera nada"
}

# -----------------------------------------------------------------------------
# I1: una IP no se confunde con otra más larga que la contiene
# -----------------------------------------------------------------------------
# 203.0.113.1 es prefijo de 203.0.113.10. Sustituir sin anclar convertiría
# «ip4:203.0.113.10» en «ip4:203.0.113.20» por accidente, y un A que apunta a
# 203.0.113.10 en otra cosa.
test_a_shorter_ip_does_not_match_inside_a_longer_one() {
  nueva_prueba mz_i1
  local d="$BANCO_TMP/mz_i1"
  local raiz="$d/arbol"
  sembrar "$raiz"

  local Z="$raiz/zonas/cuenta1"
  rm -f -- "$Z"/*.conf

  cat > "$Z/example.org.conf" <<'FIN'
ID='1' RECORD='@' TYPE='NS' PRIORITY='' VALUE='ns1.viejo.example.org.' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='2' RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.1' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='3' RECORD='largo' TYPE='A' PRIORITY='' VALUE='203.0.113.10' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
ID='4' RECORD='@' TYPE='TXT' PRIORITY='' VALUE='"v=spf1 ip4:203.0.113.1 ip4:203.0.113.10 -all"' SUSPENDED='no' TIME='08:00:00' DATE='2025-03-04'
FIN

  local ruta_path
  ruta_path="$(montar_falsos "$d/bin" "$d/registro.txt")"

  correr "$raiz" "$ruta_path" normal "$d/stdout.txt" "$d/stderr.txt" \
    --cuenta cuenta1 --zonas "$Z" --dominio example.org \
    --ip-origen "203.0.113.1" --ip-destino "203.0.113.2" --aplicar
  afirmar_codigo 0 "$?" "I1: la carga termina bien"

  local zona
  zona="$(zona_destino "$raiz" example.org)"

  afirmar_contiene "$zona" "RECORD='@' TYPE='A' PRIORITY='' VALUE='203.0.113.2'" \
    "I1: el A que era exactamente la IP de origen se cambia"
  afirmar_contiene "$zona" "RECORD='largo' TYPE='A' PRIORITY='' VALUE='203.0.113.10'" \
    "I1: y el que la contiene como prefijo NO se toca"
  afirmar_contiene "$zona" "v=spf1 ip4:203.0.113.2 ip4:203.0.113.10 -all" \
    "I1: en el SPF se cambia el token exacto y no el más largo"
  afirmar_no_contiene "$zona" "203.0.113.20" \
    "I1: no aparece ninguna IP inventada por una sustitución a medias"
}

test_bad_arguments_change_nothing
test_dry_run_writes_nothing
test_apply_rewrites_ip_ns_and_dkim
test_backups_and_undo_script
test_silent_zero_is_detected_and_original_survives
test_nonzero_exit_leaves_the_zone_untouched
test_a_shorter_ip_does_not_match_inside_a_longer_one

fin_de_suite
