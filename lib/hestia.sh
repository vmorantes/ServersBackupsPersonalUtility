#!/usr/bin/env bash
# =============================================================================
# lib/hestia.sh — configurar y blindar los respaldos de HestiaCP
# =============================================================================
# Deja montado el respaldo incremental con Restic sin tocar nada a mano: el
# remoto de rclone (S3/Mega S4, disco o NAS), el host de respaldo en HestiaCP,
# el cron, y el rescate de las claves sin las cuales el repositorio es
# ilegible.
#
# DÓNDE SE EJECUTA
#   Todas estas operaciones ocurren EN EL SERVIDOR. Si el perfil tiene
#   DEPLOY_HOST, se hacen por SSH; si backupctl ya vive en el servidor, se hacen
#   ahí mismo. Una sola implementación para los dos casos.
#
# LAS CREDENCIALES NUNCA VAN EN LA LÍNEA DE ÓRDENES
#   Las claves de S3 viajan por la entrada estándar hasta el archivo de destino.
#   Pasarlas como argumento las haría visibles en `ps` para cualquier otro
#   usuario del servidor.
# =============================================================================

[[ -n "${BC_HESTIA_LOADED:-}" ]] && return 0
BC_HESTIA_LOADED=1

BC_HESTIA_REMOTO=0          # ¿hay que ir por SSH?
BC_HESTIA_RCLONE_CONF="${BC_RCLONE_CONF:-/root/.config/rclone/rclone.conf}"

# Configuración GLOBAL del host de respaldo: repositorio y retención. Está en
# conf/, no bajo data/users/. Cada usuario tiene además su propio restic.conf
# en data/users/<usuario>/ con SU clave de cifrado.
HESTIA_CONF_RESTIC="${HESTIA_DIR:-/usr/local/hestia}/conf/restic.conf"

# Crontab de tareas propias de HestiaCP. Ahí pone el instalador v-backup-users,
# v-update-sys-queue, etc. No es un usuario del panel: v-rebuild-cron-jobs no
# lo toca, así que lo que se escriba aquí sobrevive.
BC_HESTIA_CRONTAB_SIS="/var/spool/cron/crontabs/hestiaweb"

# -----------------------------------------------------------------------------
# Decidir dónde actuar y abrir la conexión si hace falta
# -----------------------------------------------------------------------------
bc_hestia_conectar() {
  # Se recalcula aquí: al cargar el módulo, HESTIA_DIR todavía no está definido.
  HESTIA_CONF_RESTIC="$HESTIA_DIR/conf/restic.conf"
  if [[ -d "$HESTIA_DIR" ]]; then
    BC_HESTIA_REMOTO=0
    bc_debug "HestiaCP local en $HESTIA_DIR"
    return 0
  fi
  if [[ -n "$DEPLOY_HOST" ]]; then
    BC_HESTIA_REMOTO=1
    local target="$DEPLOY_USER@$DEPLOY_HOST"
    bc_log "HestiaCP no está aquí; se trabajará sobre $target."
    bc_ssh_init "$target" || bc_die "no se pudo conectar a $target."
    bc_ssh "test -d '$HESTIA_DIR'" 2>/dev/null \
      || bc_die "en $target tampoco existe $HESTIA_DIR. ¿Es un servidor HestiaCP?"
    return 0
  fi
  bc_die "no hay HestiaCP aquí ni DEPLOY_HOST configurado en $BC_ENV_FILE."
}

bc_hestia_cerrar() { (( BC_HESTIA_REMOTO )) && bc_ssh_close; return 0; }

# LECTURA: se intenta primero sin elevar. Muchos de estos archivos son
# legibles por el usuario, y pedir sudo para leerlos sería tan molesto como
# innecesario. Solo si falla se escala.
# La entrada estándar se cierra a propósito. Sin esto, un `ssh` invocado dentro
# de un bucle `while read` se COME las líneas que quedaban por leer: el bucle
# procesa el primer elemento y termina. Es la causa de que la lista de usuarios
# mostrara solo el primero de los tres.
bc_hestia_read() {
  local salida rc

  # La salida se CAPTURA, no se deja salir directamente. La versión anterior
  # hacía `orden && return 0` y, si la orden terminaba en código distinto de
  # cero, la volvía a ejecutar con sudo: la primera salida ya se había impreso,
  # así que se veía TODO DUPLICADO. Y un `grep` que no encuentra nada en el
  # último archivo de un bucle ya devuelve 1, aunque haya encontrado antes.
  if (( BC_HESTIA_REMOTO )); then
    salida="$(bc_ssh "$*" 2>/dev/null < /dev/null)" && rc=0 || rc=$?
  else
    salida="$(bash -c "$*" 2>/dev/null < /dev/null)" && rc=0 || rc=$?
  fi

  # Si dio salida, sirvió: da igual el código. Solo se reintenta con privilegios
  # cuando no se obtuvo nada, que es el síntoma de un permiso denegado.
  if (( rc == 0 )) || [[ -n "$salida" ]]; then
    [[ -n "$salida" ]] && printf '%s\n' "$salida"
    return 0
  fi

  if (( BC_HESTIA_REMOTO )); then
    salida="$(bc_ssh_sudo "$*" 2>/dev/null < /dev/null)" || true
  elif [[ "$(id -u)" -eq 0 ]]; then
    return 1
  else
    salida="$(sudo -n bash -c "$*" 2>/dev/null < /dev/null)" || true
  fi
  [[ -n "$salida" ]] || return 1
  printf '%s\n' "$salida"
}

# ESCRITURA: siempre elevado. Nunca se intenta sin sudo, porque un intento a
# medias podría dejar un archivo escrito a medias.
# Igual que en bc_hestia_read: sin cerrar stdin, un ssh dentro de un bucle se
# lleva por delante las líneas pendientes. Para enviar datos está la variante
# bc_hestia_root_stdin.
bc_hestia_root() {
  if (( BC_HESTIA_REMOTO )); then
    bc_ssh_sudo "$*" < /dev/null
  elif [[ "$(id -u)" -eq 0 ]]; then
    bash -c "$*" < /dev/null
  elif sudo -n true 2>/dev/null; then
    sudo -n bash -c "$*" < /dev/null
  elif bc_can_prompt; then
    sudo bash -c "$*"
  else
    return 1
  fi
}

# PREGUNTA DE SÍ O NO, con tres respuestas posibles: 1, 0 o '?'.
# La orden que se le pasa se ejecuta en el servidor y su respuesta viaja como
# un centinela en la SALIDA, no como código de salida. Así «el archivo no
# está» (0) se distingue de «la orden ni siquiera llegó a correr» ('?'):
# conexión caída, sudo denegado, HestiaCP en otro sitio. Rellenar ese hueco
# con un 0 es lo que convierte un diagnóstico en una mentira con forma de dato
# leído (ADR 0017).
# Compone el texto que se ejecutará en el servidor. Va aparte, y es pura, para
# que el banco pueda comprobar SIN SERVIDOR que ese texto sobrevive a que le
# antepongan cosas.
#
# La orden va dentro de su PROPIO `bash -c`, escapada con printf '%q'. No es
# adorno: bc_hestia_root puede anteponer texto a lo que recibe (bc_ssh_sudo
# hace `ssh "sudo -n $*"`, lib/ssh.sh:132), y entonces un grupo `{ orden; }`
# quedaría detrás de `sudo`, donde `{` ya no es palabra reservada y `}` es un
# error de sintaxis. Con el `bash -c` propio, la orden se parsea igual venga
# por donde venga.
#
# Solo el código 1 es un «no». Cualquier otro es la orden quejándose —`grep`
# sale con 2 si el archivo no existe o no se puede leer, no con 1—, y eso es
# «no lo pude preguntar».
bc_hestia_sondear_orden() {
  local guion="rc=0; $* || rc=\$?; case \$rc in 0) echo BC_SI;; 1) echo BC_NO;; *) echo BC_ERR;; esac"
  printf 'bash -c %s' "$(printf '%q' "$guion")"
}

# Sondea el repositorio de una cuenta y devuelve 0, 1 o '?'. Pregunta dos
# veces cuando hace falta; el juicio está separado, en bc_hestia_juzgar_repo,
# para que el banco lo pruebe sin servidor.
#
# Hay TRES caminos porque el REPO registrado tiene tres formas distintas, las
# mismas que distingue bc_hestia_validar_repo (verificado en la fuente de
# HestiaCP 1.10.4 el 2026-09-23):
#   rclone:<remoto>:<ruta>  se sondea listando, que no necesita la contraseña
#                           del repositorio.
#   /ruta/absoluta          es el sistema de archivos del propio servidor.
#   otro esquema (sftp:, s3:, b2:, rest:…)  se hablaría el protocolo, pero
#                           abrir el repositorio para mirar dentro exige su
#                           contraseña, y aquí no se usan contraseñas. No se
#                           puede sondear: '?'.
# Un repositorio siempre tiene un archivo "config" en su raíz: se pregunta por
# él.
bc_hestia_sondear_repo() {
  local repo="${1:-}" u="${2:-}" cuenta padre='?' base
  if [[ "$repo" == rclone:* ]]; then
    base="${repo#rclone:}"; base="${base%/}"
    cuenta="$(bc_hestia_sondear "rclone lsf $(printf '%q' "$base/$u/config") 2>/dev/null | grep -q .")"
    # La sonda del padre mira si el listado TERMINA BIEN, no si devuelve
    # líneas. Un repositorio global recién registrado está vacío, y un padre
    # vacío que se lista sin error demuestra lo que hace falta demostrar: que
    # el almacenamiento responde. Con la otra forma, ese servidor recién
    # montado decía «no se pudo comprobar» en todas sus cuentas.
    [[ "$cuenta" == 1 ]] \
      || padre="$(bc_hestia_sondear "rclone lsf $(printf '%q' "$base/") >/dev/null 2>&1")"
  elif [[ "$repo" == /* ]]; then
    base="${repo%/}"
    cuenta="$(bc_hestia_sondear "test -f $(printf '%q' "$base/$u/config")")"
    # `test -d` ya es «terminó bien o no»: un directorio vacío existe igual.
    [[ "$cuenta" == 1 ]] \
      || padre="$(bc_hestia_sondear "test -d $(printf '%q' "$base")")"
  else
    echo '?'
    return 0
  fi
  bc_hestia_juzgar_repo "$cuenta" "$padre"
}

bc_hestia_sondear() {
  local salida
  salida="$( { bc_hestia_root "$(bc_hestia_sondear_orden "$@")" 2>/dev/null || true; } | tr -d '\r' )"
  case "$salida" in
    *BC_SI*)  echo 1 ;;
    *BC_NO*)  echo 0 ;;
    *)        echo '?' ;;
  esac
}

# Igual, pero enviando algo por la entrada estándar. Es la vía por la que
# viajan las credenciales.
bc_hestia_root_stdin() {
  if (( BC_HESTIA_REMOTO )); then
    bc_ssh_sudo "$*"
  elif [[ "$(id -u)" -eq 0 ]]; then
    bash -c "$*"
  else
    sudo -n bash -c "$*" 2>/dev/null || sudo bash -c "$*"
  fi
}

bc_hestia_v() { bc_hestia_root "$HESTIA_DIR/bin/$*"; }

# =============================================================================
# El juicio: funciones PURAS
# =============================================================================
# No conectan a nada, no leen archivos, no escriben: reciben texto e imprimen
# UNA línea «NIVEL<TAB>mensaje», con NIVEL en OK / AVISO / FALLO, y devuelven 0
# siempre. Quien las llama decide cómo pintarlas.
#
# Viven aparte a propósito (ADR 0017): el juicio sobre si los respaldos
# funcionan es justo lo que hay que poder probar sin un servidor delante. Lo
# que necesita el servidor es la LECTURA; la conclusión, no.
#
# La regla que las gobierna a todas: HestiaCP puede registrar éxito con el
# respaldo fallado (v-backup-user-restic usa una constante E_BACKUP que no
# existe, 1.10.4), así que la única prueba de que un respaldo se hizo es una
# instantánea con fecha.

bc_hestia_veredicto() { printf '%s\t%s\n' "$1" "$2"; }

# Interpreta la línea de cron que encontró bc_hestia_cron_donde.
# $1 la línea (vacía si no hay ninguna)   $2 el archivo donde vive
#
# Los campos de minuto y hora solo se comprueban cuando son un número pelado:
# con "*", "*/2" o "1,15" no se puede decidir el rango sin implementar la
# sintaxis entera de cron, y una comprobación a medias daría falsos fallos.
bc_hestia_diag_cron() {
  local linea="${1:-}" archivo="${2:-}"

  if [[ -z "$linea" ]]; then
    bc_hestia_veredicto FALLO "no hay ningún respaldo programado: está configurado, pero no se ejecuta nunca. Actívalo con: backupctl hestia cron"
    return 0
  fi

  # La línea puede venir como "archivo:contenido" (grep -H) o suelta.
  local cuerpo="$linea"
  [[ -z "$archivo" && "$linea" == /*:* ]] && { archivo="${linea%%:*}"; cuerpo="${linea#*:}"; }

  local minuto hora resto
  read -r minuto hora resto <<<"$cuerpo"

  local malos=""
  [[ "$minuto" =~ ^[0-9]+$ ]] && (( 10#$minuto > 59 )) && malos+="minuto $minuto"
  [[ "$hora"   =~ ^[0-9]+$ ]] && (( 10#$hora   > 23 )) && malos+="${malos:+ y }hora $hora"
  if [[ -n "$malos" ]]; then
    bc_hestia_veredicto FALLO "la programación tiene un valor imposible ($malos). El cron de Debian/Ubuntu puede rechazar el archivo ENTERO, no solo esa línea: puede que no se ejecute NADA de lo que hay en $archivo"
    return 0
  fi

  # La ruta sale de HESTIA_DIR, no escrita a pelo: en un servidor con HestiaCP
  # instalado fuera de /usr/local/hestia, una ruta fija haría que este juez
  # rechazara una línea perfectamente buena — un falso fallo en la cara del
  # usuario, y justo en la orden que existe para que se fíe. El valor por
  # defecto es el de siempre, para quien llame a esta función suelta (T18).
  local bin_hestia="${HESTIA_DIR:-/usr/local/hestia}/bin/"
  if [[ "$cuerpo" != *"$bin_hestia"* ]]; then
    bc_hestia_veredicto FALLO "la orden del cron no lleva ruta absoluta (${bin_hestia}...). El PATH de cron no incluye ese directorio: probablemente no se ejecuta nunca"
    return 0
  fi

  if [[ "$archivo" != */crontabs/hestiaweb ]]; then
    bc_hestia_veredicto AVISO "el respaldo está programado en $archivo, no en el crontab de hestiaweb: ahí puede quedarse sin sudo ni PATH, y un v-rebuild-cron-jobs puede borrarlo"
    return 0
  fi

  if [[ "$hora" =~ ^[0-9]+$ && "$minuto" =~ ^[0-9]+$ ]]; then
    # El 10# va DENTRO de la aritmética, no en printf: un "08" sin él se leería
    # como octal, y printf no entiende ese prefijo.
    bc_hestia_veredicto OK "$(printf 'respaldo programado a las %02d:%02d' "$(( 10#$hora ))" "$(( 10#$minuto ))")"
  else
    bc_hestia_veredicto OK "respaldo programado (minuto '$minuto', hora '$hora')"
  fi
}

# ¿La última instantánea es lo bastante reciente para la periodicidad del cron?
# $1 fecha ISO de la última (vacía si no hay)  $2 ahora en epoch  $3 cada cuántas horas
#
# Este es el diagnóstico que ningún log del servidor da: con el cron cada
# noche y una instantánea de hace tres días, las últimas ejecuciones no
# hicieron nada — y HestiaCP las registró como correctas.
bc_hestia_diag_instantanea() {
  local fecha="${1:-}" ahora="${2:-0}" cada_h="${3:-24}"

  if [[ -z "$fecha" ]]; then
    bc_hestia_veredicto FALLO "esta cuenta no tiene ninguna copia"
    return 0
  fi

  # Dos preguntas distintas, y en este orden: ¿esto se entiende como fecha?, y
  # solo entonces ¿dice a qué hora fue? Juntarlas daría el mensaje equivocado
  # a la mitad de los casos.
  if ! date -d "$fecha" +%s >/dev/null 2>&1; then
    # Ceguera, no aviso: lo que hay que responder no es «¿falló la lectura?»
    # sino «¿puedo afirmar que esta cuenta se respalda?». Sin saber cuándo fue
    # la última copia, no puedo — da igual que la lectura llegara a ocurrir.
    bc_hestia_veredicto CIEGO "no se pudo leer la fecha de la última copia ('$fecha'): no es lo mismo que no tenerla"
    return 0
  fi

  # Una fecha SIN huso no se interpreta: se declara. `date -d` la aceptaría y
  # la leería en la zona local de quien ejecuta esto, que trabajando por SSH
  # normalmente no es la del servidor — y ese desfase entraría entero en la
  # antigüedad, pudiendo convertir una copia vieja en una «reciente».
  local epoch
  if ! epoch="$(bc_hestia_fecha_epoch "$fecha")" || [[ -z "$epoch" ]]; then
    bc_hestia_veredicto CIEGO "la fecha de la última copia ('$fecha') llega SIN huso horario: no se sabe a qué instante corresponde, así que no se puede calcular su antigüedad. No es que falten copias — es que no se entiende la hora. Mira con qué versión de la herramienta de respaldo se escribieron: las que dicen el huso se leen bien"
    return 0
  fi

  local edad=$(( ahora - epoch ))
  (( edad < 0 )) && edad=0
  local limite=$(( cada_h * 3600 ))

  if (( edad > limite * 2 )); then
    bc_hestia_veredicto FALLO "la última copia es de hace $(bc_hestia_edad_llana "$edad") y el respaldo corre cada ${cada_h}h: las últimas ejecuciones no hicieron nada. HestiaCP puede haberlas registrado como correctas igualmente"
  elif (( edad > limite )); then
    bc_hestia_veredicto AVISO "la última copia es de hace $(bc_hestia_edad_llana "$edad"), más de lo que tarda el cron (${cada_h}h)"
  else
    bc_hestia_veredicto OK "última copia de hace $(bc_hestia_edad_llana "$edad")"
  fi
}

# -----------------------------------------------------------------------------
# Fechas: en qué referencia está cada una
# -----------------------------------------------------------------------------
# Todas PURAS. Existen porque en un servidor real se vio LA MISMA copia
# impresa con cinco horas de diferencia entre dos consultas: no cambió el
# respaldo, cambió la zona del entorno desde el que se pidió el listado, que es
# quien decide cómo se imprime. Si una punta de la comparación está en una
# referencia y la otra en otra, el desfase entra directo en el cálculo de
# antigüedad y una copia que sí se saltó una noche puede parecer reciente.
#
# El formato de esa lista NO lo decide HestiaCP: lo decide la versión de la
# herramienta de respaldo instalada en cada servidor. Así que aquí no se exige
# un formato concreto — se exige lo único que hace falta para que la cuenta
# salga bien: que la fecha diga a qué hora fue.

# ¿Esta fecha lleva indicador de huso?
# Se aceptan las formas que una fecha ISO puede traer —Z, ±HH:MM, ±HHMM, ±HH—
# y un nombre de zona al final (UTC, CEST…). Lo que NO se acepta es una hora de
# pared a secas: esa no dice a qué instante corresponde.
bc_hestia_fecha_con_huso() {
  local f="${1:-}"
  [[ "$f" =~ [Zz]$ ]]                      && return 0
  [[ "$f" =~ [+-][0-9]{2}:[0-9]{2}$ ]]     && return 0
  [[ "$f" =~ [+-][0-9]{4}$ ]]              && return 0
  [[ "$f" =~ [+-][0-9]{2}$ ]]              && return 0
  [[ "$f" =~ [[:space:]][A-Za-z]{2,5}$ ]]  && return 0
  return 1
}

# El instante absoluto de una fecha, en segundos. Devuelve 1 —sin imprimir
# nada— si la fecha no lleva huso o si no se puede interpretar.
#
# La comprobación del huso va ANTES de llamar a `date`: `date -d` acepta
# encantado una hora sin huso y la interpreta en la zona local de QUIEN EJECUTA
# esto, que trabajando por SSH normalmente no es el servidor. Eso no es leer
# una fecha, es inventarle una zona.
bc_hestia_fecha_epoch() {
  local f="${1:-}" e
  [[ -n "$f" ]] || return 1
  bc_hestia_fecha_con_huso "$f" || return 1
  e="$(date -d "$f" +%s 2>/dev/null)" || return 1
  [[ -n "$e" ]] || return 1
  printf '%s' "$e"
}

# La fecha, en la hora local de quien mira y CON su huso a la vista.
# Dos ejecuciones de la misma orden no pueden enseñar dos horas distintas para
# la misma copia, y quien la lee tiene que saber en qué referencia está.
bc_hestia_fecha_legible() {
  local f="${1:-}"
  bc_hestia_fecha_con_huso "$f" || { printf 'sin huso'; return 0; }
  date -d "$f" '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || printf 'sin huso'
}

# La más reciente de una lista de fechas (una por línea).
#
# Por INSTANTE, no por texto. Ordenar cadenas con husos distintos elige mal:
# "2026-09-24T02:00:00+07:00" es mayor como texto que "2026-09-23T21:25:50+02:00"
# y sin embargo ocurrió ANTES. Eso envejece una cuenta bien respaldada y manda
# a alguien a buscar un problema que no existe.
#
# Si alguna fecha NO lleva huso, se devuelve ESA: con la lista en dos
# referencias distintas no se puede ordenar ni restar, y quien juzgue tiene que
# poder decir cuál es la que no se entiende.
bc_hestia_fecha_mas_reciente() {
  local lista="${1:-}" f e mejor="" mejor_e=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if ! bc_hestia_fecha_con_huso "$f"; then
      printf '%s' "$f"
      return 0
    fi
    e="$(bc_hestia_fecha_epoch "$f")" || continue
    if [[ -z "$mejor_e" ]] || (( e > mejor_e )); then mejor="$f"; mejor_e="$e"; fi
  done <<<"$lista"
  printf '%s' "$mejor"
}

# -----------------------------------------------------------------------------
# La diferencia entre dos listas de instantáneas
# -----------------------------------------------------------------------------
# Puras. Son el corazón del paso que comprueba una copia: la ÚNICA prueba de
# que un respaldo se hizo es una instantánea nueva con fecha (ADR 0017). Ni el
# código de salida de la orden ni lo que registre el panel valen, porque un
# respaldo que falla puede terminar registrando éxito.

# Una línea por instantánea: "fecha<TAB>identificador".
#
# El troceado se ancla en la clave de la fecha, no en las llaves del json: el
# formato lo decide la versión de la herramienta de respaldo instalada en cada
# servidor, y un objeto anidado dentro de cada instantánea rompería cualquier
# corte por llaves. Lo único que se asume es que cada instantánea trae su fecha
# y que su identificador viene después.
bc_hestia_instantaneas_de() {
  awk '
    {
      n = split($0, trozos, /"time"[[:space:]]*:[[:space:]]*"/)
      for (i = 2; i <= n; i++) {
        t = trozos[i]; sub(/".*/, "", t)
        id = ""
        if (match(trozos[i], /"short_id"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
          id = substr(trozos[i], RSTART, RLENGTH)
          sub(/.*"short_id"[[:space:]]*:[[:space:]]*"/, "", id)
          sub(/".*/, "", id)
        }
        print t "\t" id
      }
    }' <<<"${1:-}"
}

# Solo las fechas de esa lista.
bc_hestia_fechas_de() { cut -f1 <<<"${1:-}" | sed '/^$/d'; }

# ¿Hay alguna instantánea en el DESPUÉS más reciente que todas las del ANTES?
# Imprime "fecha<TAB>identificador" de la más nueva, o nada si no hay ninguna.
#
# Se compara por INSTANTE. Una fecha sin huso no dice a qué instante
# corresponde, así que no puede demostrar nada: se ignora para esto, y quien
# llame se encontrará con que no hay prueba — que es la verdad.
bc_hestia_instantanea_nueva() {
  local antes="${1:-}" despues="${2:-}"
  local corte=0 linea f e mejor="" mejor_e=0

  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    e="$(bc_hestia_fecha_epoch "$f")" || continue
    (( e > corte )) && corte="$e"
  done <<<"$(bc_hestia_fechas_de "$antes")"

  while IFS= read -r linea; do
    f="${linea%%$'\t'*}"
    [[ -n "$f" ]] || continue
    e="$(bc_hestia_fecha_epoch "$f")" || continue
    if (( e > corte )) && (( e > mejor_e )); then mejor="$linea"; mejor_e="$e"; fi
  done <<<"$despues"

  printf '%s' "$mejor"
}

# Cuántas instantáneas hay en una lista ya troceada.
bc_hestia_cuantas_de() { grep -c . <<<"${1:-}" || true; }

# Lo que la lista diga que ocupó lo añadido, si lo dice. Vacío si no.
# No todas las versiones lo traen, y un dato inventado es peor que ninguno.
bc_hestia_tamano_anadido() {
  local json="${1:-}" bytes
  # El recorte va por los DOS PUNTOS, no por espacios: en un json compacto no
  # hay ni un espacio entre la clave y el valor, y recortando por espacios se
  # quedaba la clave pegada al número.
  bytes="$(grep -oE '"data_added"[[:space:]]*:[[:space:]]*[0-9]+' <<<"$json" \
           | sed 's/.*:[[:space:]]*//' | sort -n | tail -1)"
  [[ -n "$bytes" ]] || return 0
  awk -v b="$bytes" 'BEGIN{
    if (b < 1024) { printf "%d B", b }
    else if (b < 1048576) { printf "%.1f KiB", b/1024 }
    else if (b < 1073741824) { printf "%.1f MiB", b/1048576 }
    else { printf "%.2f GiB", b/1073741824 }
  }'
}

# Segundos -> "1 m 12 s". Para decir cuánto tardó.
bc_hestia_duracion_llana() {
  local s="${1:-0}"
  if (( s < 60 )); then printf '%d s' "$s"
  elif (( s < 3600 )); then printf '%d m %d s' $(( s / 60 )) $(( s % 60 ))
  else printf '%d h %d m' $(( s / 3600 )) $(( (s % 3600) / 60 ))
  fi
}

# -----------------------------------------------------------------------------
# Comparar claves sin mirarlas
# -----------------------------------------------------------------------------
# Puras. Existen por algo que pasó en producción: cuando el panel no encuentra
# la contraseña de una cuenta, GENERA UNA NUEVA. Si esa cuenta ya tenía copias
# hechas con la anterior, la nueva NO las abre. Quedan ahí, ocupando espacio,
# ilegibles para siempre.
#
# Por eso cada rescate se compara con el anterior. Y se compara por HUELLA:
# ninguna clave se imprime, ni entera ni en parte, ni en pantalla ni en el
# informe. Lo único que sale de aquí es «igual», «CAMBIÓ» o «no hay con qué
# comparar».

# La huella de un texto. Vacío si no se puede calcular.
#
# Se quitan los espacios y saltos de línea DEL FINAL antes de calcularla, y
# nada más. Un salto de línea de más es el cambio cosmético más probable, y un
# falso «LA CONTRASEÑA HA CAMBIADO» es caro justo porque asusta con lo que más
# asusta. Lo que NO se hace es normalizar de más: cualquier diferencia que no
# sea espacio en blanco al final ES un cambio, y como tal se informa.
bc_hestia_huella() {
  local t="${1:-}"
  t="${t%"${t##*[![:space:]]}"}"
  [[ -n "$t" ]] || return 0
  printf '%s' "$t" | sha256sum 2>/dev/null | cut -c1-16
}

# El bloque de una cuenta dentro de un archivo de rescate. Los rescates se
# escriben con una cabecera «# <cuenta>:» y un separador detrás, así que se
# recorta entre los dos.
# $1 contenido del archivo de rescate   $2 cuenta
bc_hestia_bloque_rescatado() {
  awk -v cuenta="${2:-}" '
    $0 == "# " cuenta ":" { dentro = 1; next }
    dentro && /^=====/    { dentro = 0 }
    dentro                { print }
  ' <<<"${1:-}" | sed '/^[[:space:]]*$/d'
}

# El veredicto de comparar dos huellas. Nunca recibe ni devuelve una clave.
#   sin-anterior  no había rescate previo de esa cuenta
#   igual         la guardada sigue sirviendo
#   CAMBIO        la contraseña ha cambiado desde el último rescate
bc_hestia_comparar_huellas() {
  local ahora="${1:-}" antes="${2:-}"
  [[ -n "$antes" ]] || { printf 'sin-anterior'; return 0; }
  [[ "$ahora" == "$antes" ]] && { printf 'igual'; return 0; }
  printf 'CAMBIO'
}

# El rescate anterior más reciente que haya en un directorio, o vacío.
# $1 directorio   $2 archivo que NO cuenta (el que se está escribiendo ahora)
bc_hestia_rescate_anterior() {
  local dir="${1:-}" excluir="${2:-}"
  [[ -d "$dir" ]] || return 0
  { find "$dir" -maxdepth 1 -name 'Restic_Configs_*.txt' -printf '%T@ %p\n' 2>/dev/null || true; } \
    | sort -rn | cut -d' ' -f2- | grep -vxF "${excluir:-/dev/null}" | sed -n '1p'
}

# -----------------------------------------------------------------------------
# Qué remotos hay, sin mirar sus credenciales
# -----------------------------------------------------------------------------
# Puras. El archivo de acceso al almacenamiento lleva claves EN CLARO, así que
# de él no se lee el contenido: se lee solo la lista de secciones y su tipo.
# Con eso basta para todo lo que hay que decidir —si el remoto pedido está, si
# es del tipo pedido, si los que había siguen— y así las credenciales no salen
# del servidor ni por error.
#
# Lo que se le pide al servidor es la lista de líneas de sección y de tipo; lo
# que llega aquí tiene esta forma:
#     [almacen]
#     type = s3
#     [disco]
#     type = local

# Una línea por remoto: "nombre<TAB>tipo". El tipo queda vacío si no lo dice.
bc_hestia_remotos_de() {
  awk '
    /^\[/ {
      if (n != "") print n "\t" t
      n = $0; gsub(/^\[|\]$/, "", n); t = ""; next
    }
    /^[[:space:]]*type[[:space:]]*=/ {
      t = $0; sub(/^[^=]*=[[:space:]]*/, "", t); gsub(/[[:space:]]+$/, "", t)
    }
    END { if (n != "") print n "\t" t }
  ' <<<"${1:-}"
}

# Solo los nombres.
bc_hestia_nombres_de() { cut -f1 <<<"$(bc_hestia_remotos_de "${1:-}")" | sed '/^$/d'; }

# El tipo de un remoto concreto, o vacío si no está.
bc_hestia_tipo_de() {
  local linea
  linea="$(bc_hestia_remotos_de "${1:-}" | grep -m1 -P "^${2:-}\t" || true)"
  printf '%s' "${linea#*$'\t'}"
}

# Lo que se pide al escribir un remoto. Los jueces solo reciben el texto
# leído, así que lo pedido viaja por aquí.
BC_HESTIA_RC_NOMBRE=""
BC_HESTIA_RC_TIPO=""

# ¿Este archivo ya tiene el remoto pedido, del tipo pedido?
bc_hestia_remoto_cumple() {
  local texto="${1:-}"
  [[ -n "$(bc_hestia_nombres_de "$texto")" ]] || return 1
  [[ "$(bc_hestia_tipo_de "$texto" "$BC_HESTIA_RC_NOMBRE")" == "$BC_HESTIA_RC_TIPO" ]]
}

bc_hestia_remoto_ya_estaba() { bc_hestia_remoto_cumple "${1:-}"; }
bc_hestia_remoto_se_hizo()   { bc_hestia_remoto_cumple "${2:-}"; }

# Los nombres que estaban antes y ya NO están. Uno por línea.
# Un remoto perdido es un almacenamiento al que ya no se llega, y eso no se
# descubre hasta el día que hace falta.
bc_hestia_remotos_perdidos() {
  local antes="${1:-}" despues="${2:-}" n
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    grep -qxF "$n" <<<"$(bc_hestia_nombres_de "$despues")" || printf '%s\n' "$n"
  done <<<"$(bc_hestia_nombres_de "$antes")"
}

# Segundos -> lenguaje llano. Pura, auxiliar de la de arriba.
bc_hestia_edad_llana() {
  local s="${1:-0}"
  if   (( s < 3600   )); then echo "menos de una hora"
  elif (( s < 172800 )); then echo "$(( s / 3600 )) horas"
  else                        echo "$(( s / 86400 )) días"
  fi
}

# Cruza los tres datos de una cuenta: ¿tiene contraseña de repositorio?, ¿existe
# el repositorio?, ¿está marcada con BACKUPS_INCREMENTAL?
# $1 clave 0|1|?   $2 repo 0|1|?|-   $3 marcada 0|1|?
#
# Tres estados, no dos. El '?' significa «no se pudo leer», y NO es lo mismo
# que «no»: si una conexión se cae o un permiso falta, tratar eso como un 0
# fabrica un diagnóstico que suena a dato leído. Por eso las comparaciones son
# de CADENA (==) y no aritméticas: en aritmética un '?' no vale, y el 0 por
# defecto volvería a colarse. Un '?' nunca produce OK.
#
# El repositorio admite además '-': no hay NINGUNO registrado en el servidor.
# No es «no se pudo leer», es una pregunta que no tiene sentido hacer, y la
# línea «Ruta del repositorio» ya la contestó una vez. Repetirla por cada
# cuenta llena el informe de ruido que el usuario aprende a saltarse.
bc_hestia_diag_cuenta() {
  local clave="${1:-?}" repo="${2:-?}" marcada="${3:-?}"

  # Lo desconocido se declara antes que nada: con un dato que falta no se puede
  # afirmar ni que está bien ni que está mal.
  if [[ "$clave" == "?" || "$repo" == "?" || "$marcada" == "?" ]]; then
    local faltan=""
    [[ "$marcada" == "?" ]] && faltan+=", si está marcada para respaldo incremental"
    [[ "$clave"   == "?" ]] && faltan+=", si tiene contraseña de repositorio"
    [[ "$repo"    == "?" ]] && faltan+=", si su repositorio existe"
    bc_hestia_veredicto CIEGO "no se pudo comprobar${faltan#,}. Sin ese dato no se puede decir si esta cuenta se respalda: compruébalo en el servidor"
    return 0
  fi

  # Contraseña huérfana. Va antes que las reglas generales porque es más
  # específica que todas ellas, y porque es la PRECONDICIÓN del incidente del
  # 2026-09-23: HestiaCP solo crea el repositorio de una cuenta cuando NO
  # existe su contraseña. Con la contraseña ya guardada, marcar la cuenta no
  # crea nada, y el primer respaldo «correcto» no respalda nada.
  if [[ "$marcada" == 0 && "$clave" == 1 && "$repo" != 1 ]]; then
    bc_hestia_veredicto AVISO "no entra en los respaldos incrementales, pero tiene una contraseña de repositorio guardada. Si la marcas sin más, HestiaCP dará por hecho que su repositorio ya existe y NO lo creará: aparta esa contraseña antes de marcarla"
    return 0
  fi

  # Sin repositorio registrado en el servidor, de esta cuenta solo se sabe si
  # está marcada y si tiene contraseña. Se dice eso y nada más.
  if [[ "$repo" == "-" ]]; then
    if [[ "$marcada" == 1 && "$clave" == 1 ]]; then
      bc_hestia_veredicto AVISO "marcada para respaldo incremental y con contraseña de repositorio guardada"
    elif [[ "$marcada" == 1 ]]; then
      bc_hestia_veredicto AVISO "marcada para respaldo incremental; todavía no tiene contraseña de repositorio"
    else
      bc_hestia_veredicto AVISO "esta cuenta no entra en los respaldos incrementales"
    fi
    return 0
  fi

  if [[ "$marcada" == 1 && "$clave" == 1 && "$repo" == 0 ]]; then
    # El estado exacto del incidente del 2026-09-23: HestiaCP solo crea el
    # repositorio si NO existe la contraseña, así que con la contraseña puesta
    # y el repositorio ausente no lo creará nunca más por su cuenta.
    bc_hestia_veredicto FALLO "tiene contraseña de repositorio pero el repositorio NO existe: HestiaCP ya no lo creará solo. Salida: apartar esa contraseña para que la vuelva a crear, o crear el repositorio con ella"
  elif [[ "$marcada" == 1 && "$repo" == 1 && "$clave" == 0 ]]; then
    # El repositorio está ahí, con copias dentro, pero HestiaCP no tiene su
    # contraseña. Al siguiente respaldo generará una NUEVA, y una contraseña
    # nueva NO abre las copias que ya hay: quedarían ilegibles para siempre.
    bc_hestia_veredicto FALLO "el repositorio existe pero HestiaCP NO tiene su contraseña: una contraseña nueva no abriría las copias que ya hay. Salida: recuperar la contraseña original ('backupctl hestia keys') y devolverla a \$HESTIA/data/users/<cuenta>/restic.conf ANTES del siguiente respaldo"
  elif [[ "$marcada" == 1 && "$clave" == 0 && "$repo" == 0 ]]; then
    bc_hestia_veredicto OK "marcada para respaldo incremental; todavía no ha respaldado nunca, el primer respaldo creará su repositorio"
  elif [[ "$marcada" == 0 && "$repo" == 1 ]]; then
    bc_hestia_veredicto AVISO "tiene copias pero YA NO se respalda: no está marcada para respaldo incremental"
  elif [[ "$marcada" == 0 && "$repo" == 0 ]]; then
    bc_hestia_veredicto AVISO "esta cuenta no entra en los respaldos incrementales"
  else
    bc_hestia_veredicto OK "marcada y con repositorio"
  fi
}

# Decide si el repositorio de una cuenta existe, a partir de DOS sondas.
# $1 respuesta de la sonda de la cuenta (0|1|?)   $2 la del padre (0|1|?)
#
# POR QUÉ SE PREGUNTA DOS VECES
# Una sola sonda no distingue «ese repositorio no está» de «no pude mirar».
# Y esa confusión tiene un desastre concreto detrás: con la cuenta marcada y
# su contraseña guardada, un «no está» hace que el diagnóstico recomiende
# APARTAR la contraseña para que HestiaCP vuelva a crear el repositorio. Si lo
# que falló fue el almacenamiento —el remoto no responde, las credenciales
# caducaron, la red se cayó— el repositorio sí estaba, con copias dentro, y
# apartar la contraseña las deja ilegibles para siempre.
# La segunda sonda pregunta por el PADRE, el repositorio global. Si el padre
# responde, el camino hasta el almacenamiento funciona: que no esté el de la
# cuenta significa de verdad que no existe. Si el padre tampoco responde, no
# estamos en condiciones de afirmar nada.
# No se miran códigos de salida concretos del almacenamiento: no se pueden
# verificar contra la versión que corre en cada servidor. Se mira si el padre
# contesta.
bc_hestia_juzgar_repo() {
  local cuenta="${1:-?}" padre="${2:-?}"
  if [[ "$cuenta" == 1 ]]; then echo 1
  elif [[ "$padre" == 1 ]]; then echo 0
  else echo '?'
  fi
}

# Traduce lo que devolvió la consulta del tipo del remoto al valor que entiende
# bc_hestia_validar_repo. Pura: los dos sitios que consultan el tipo pasan por
# aquí, y así la regla se prueba en el banco en vez de vivir por duplicado.
# $1 lo que salió de la consulta (vacío si no salió nada)
# $2 1 si es un ensayo —no se consultó nada—, 0 si se consultó de verdad
#
# Vacío y '?' NO son lo mismo. '?' quiere decir «lo intenté y no pude», y con
# una ruta absoluta hace que se avise en vez de aprobar. En un ensayo no se
# intentó nada: avisar ahí sería avisar de algo que nadie miró, ruido en una
# simulación que a propósito no toca el servidor.
bc_hestia_tipo_leido() {
  local salida="${1:-}" ensayo="${2:-0}"
  if [[ -n "$salida" ]]; then printf '%s\n' "$salida"
  elif [[ "$ensayo" == "1" ]]; then printf '\n'
  else printf '%s\n' '?'
  fi
}

# ¿La ruta que hay registrada HOY en el servidor es una ruta sensata?
# $1 repositorio registrado   $2 tipo del remoto: el tipo, '?' si no se pudo
#    leer, o vacío si no hay tipo que mirar
#
# No duplica la lógica: llama a bc_hestia_validar_repo y traduce. La llamada va
# dentro de $( ), que es una subshell: así ni sus mensajes ni los contadores
# BC_ERR_COUNT/BC_WARN_COUNT que toca salen de aquí, y esta función sigue
# imprimiendo una sola línea. Sin tocar su contrato.
bc_hestia_diag_ruta_repo() {
  local repo="${1:-}" tipo="${2:-}" salida rc=0

  if [[ -z "$repo" ]]; then
    bc_hestia_veredicto FALLO "no hay ningún repositorio registrado en el servidor"
    return 0
  fi

  salida="$(bc_hestia_validar_repo "$repo" "$tipo" 2>&1)" || rc=$?

  if (( rc != 0 )); then
    # Se queda con la primera línea: es la que dice QUÉ está mal.
    bc_hestia_veredicto FALLO "la ruta registrada no es segura: $(sed -n '1p' <<<"$salida" | sed 's/.*\[ERROR\] *//')"
  elif [[ -n "$salida" ]]; then
    # Con el tipo sin leer, lo que sale no es un aviso sobre algo que se miró:
    # es la constancia de que no se pudo mirar. Cuenta como ceguera.
    local nivel=AVISO
    [[ "$tipo" == "?" ]] && nivel=CIEGO
    bc_hestia_veredicto "$nivel" "$(sed -n '1p' <<<"$salida" | sed 's/.*\[AVISO\] *//')"
  else
    bc_hestia_veredicto OK "la ruta registrada ('$repo') no cae dentro de ninguna web ni depende del directorio de trabajo"
  fi
}

# =============================================================================
# Desactivar el respaldo incremental
# =============================================================================
# ESTA ORDEN NO BORRA NI UN BYTE DE LAS COPIAS. Deja de hacer copias nuevas;
# las que hay siguen donde están, ocupando lo mismo, y se puede volver atrás.
#
# Desactivar son TRES cosas, y hacer solo una deja el servidor a medias sin que
# nadie lo note (fuente 1.10.4):
#   1. Quitar la línea del cron.
#   2. Borrar el host de respaldo. Esto pone el interruptor DE SISTEMA en 'no'
#      y borra la configuración global... pero NO TOCA NINGUNA CUENTA.
#   3. Poner la marca de cada cuenta en 'no', una por una. Esto es lo único que
#      de verdad impide que una cuenta respalde: si mañana se registra otro
#      repositorio, las cuentas que sigan marcadas EMPIEZAN A RESPALDAR SOLAS.
#
# Y antes de nada, una comprobación que no está en el plan original: si hay
# cuentas con copias cuya clave no está rescatada, desactivar las deja con
# copias que nadie podrá abrir si se pierde la máquina. Con -y, que es como
# llama la web, la orden se NIEGA: un aviso que nadie lee no protege nada, y
# esta es la única orden del ciclo cuyo daño no se ve hasta que es tarde.
bc_hestia_desactivar() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Desactivar el respaldo incremental"
  bc_log "Esto NO borra ninguna copia: deja de hacer copias nuevas. Las que hay"
  bc_log "siguen donde están y se puede volver a activar."

  # --- Lo que hay ahora, todo de lectura ------------------------------------
  local conf repo snaps d w m y
  conf="$(bc_hestia_read "cat $(printf '%q' "$HESTIA_CONF_RESTIC")" || true)"
  repo="$(bc_hestia_conf_valor "$conf" REPO)"
  snaps="$(bc_hestia_conf_valor "$conf" SNAPSHOTS)"
  d="$(bc_hestia_conf_valor "$conf" KEEP_DAILY)"
  w="$(bc_hestia_conf_valor "$conf" KEEP_WEEKLY)"
  m="$(bc_hestia_conf_valor "$conf" KEEP_MONTHLY)"
  y="$(bc_hestia_conf_valor "$conf" KEEP_YEARLY)"

  local lista
  lista="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-users plain" || true)"
  if [[ -z "$lista" ]]; then
    bc_err "no se pudo leer la lista de cuentas: no se desactiva nada a ciegas."
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  local marcadas=() con_copias_sin_clave=() u
  local rescate rescate_txt=""
  rescate="$(bc_hestia_rescate_anterior "$(bc_hestia_salida)" "")"
  [[ -n "$rescate" ]] && rescate_txt="$(cat "$rescate" 2>/dev/null || true)"

  while IFS= read -r u; do
    u="$(awk '{print $1}' <<<"$u")"
    [[ -z "$u" || "$u" == "USER" ]] && continue
    [[ "$(bc_hestia_sondear "grep -q \"^BACKUPS_INCREMENTAL='yes'\" $(printf '%q' "$HESTIA_DIR/data/users/$u/user.conf")")" == "1" ]] \
      && marcadas+=("$u")
    # ¿Tiene copias y su clave NO está rescatada aquí? Solo se mira si el
    # bloque existe: el valor no se lee ni se enseña.
    if [[ -n "$repo" && "$(bc_hestia_sondear_repo "$repo" "$u")" == "1" ]]; then
      [[ -n "$(bc_hestia_bloque_rescatado "$rescate_txt" "$u")" ]] || con_copias_sin_clave+=("$u")
    fi
  done <<<"$lista"

  bc_log "Cuentas marcadas para respaldo incremental: ${#marcadas[@]}"
  [[ -n "$repo" ]] && bc_log "Repositorio registrado: $repo"

  # --- La comprobación que protege de lo irreversible ------------------------
  if (( ${#con_copias_sin_clave[@]} > 0 )); then
    echo
    bc_err "TIENEN COPIAS Y SU CLAVE NO ESTÁ RESCATADA (${#con_copias_sin_clave[@]}): ${con_copias_sin_clave[*]}"
    bc_log  "Si desactivas ahora, dejas de hacer copias de un servidor cuyas copias"
    bc_log  "existentes NO se podrían abrir si se pierde la máquina: la contraseña"
    bc_log  "que las descifra vive solo dentro de él."
    bc_log  "Rescátalas primero:  backupctl -p $BC_PROFILE hestia keys"
    if [[ "${BC_ASSUME_YES:-0}" == "1" ]]; then
      echo
      bc_err "NO se desactiva nada. Con --yes esta orden no pasa de aquí."
      bc_log  "Un aviso que nadie lee no protege nada, y este daño no se ve hasta"
      bc_log  "que ya es tarde. Rescata las claves y vuelve a intentarlo."
      BC_DELIBERATE_EXIT=1
      return 1
    fi
    bc_confirm "¿Desactivar DE TODOS MODOS, sin esas claves rescatadas?" n \
      || { bc_log "Cancelado. Rescata las claves primero."; return 0; }
  fi

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    echo
    bc_step "Simulación (--dry-run): esto es lo que PASARÍA, no lo que ha pasado."
    bc_log "Se quitaría la línea del cron de $BC_HESTIA_CRONTAB_SIS."
    bc_log "Se borraría el host de respaldo (la configuración global)."
    if (( ${#marcadas[@]} > 0 )); then
      bc_log "Se desmarcarían ${#marcadas[@]} cuenta(s): ${marcadas[*]}"
    else
      bc_log "No hay ninguna cuenta marcada que desmarcar."
    fi
    bc_log "NO se borraría ninguna copia del almacenamiento."
    bc_ok "No se ha tocado nada, y no se ha guardado ningún informe."
    return 0
  fi

  echo
  bc_confirm "¿Desactivar el respaldo incremental?" n \
    || { bc_log "Cancelado."; return 0; }

  bc_informe_abrir "Desactivar el respaldo incremental" "${DEPLOY_HOST:-este servidor}"
  # Lo primero del informe, porque es lo primero que alguien se preguntará.
  bc_informe_dato "Las copias del almacenamiento" "" \
    "NO se borran: esta orden solo deja de hacer copias nuevas"
  bc_informe_dato "Espacio liberado" "" "ninguno: no se borra nada"
  bc_informe_dato "Repositorio que estaba registrado" "$repo" "(ninguno)"
  bc_informe_dato "Retención que tenía" "$(bc_hestia_retencion_pedida "$snaps" "$d" "$w" "$m" "$y")" "(ninguna)"
  bc_informe_deshacer "Para volver a activarlo con los MISMOS valores: backupctl -p $BC_PROFILE hestia restic --repo '$repo' (la retención se pide por teclado: $snaps, $d, $w, $m, $y) y después: backupctl -p $BC_PROFILE hestia cron"

  local rc=0

  # --- 1. El cron -----------------------------------------------------------
  bc_hestia_desactivar_cron || rc=1

  # --- 2. El host de respaldo ----------------------------------------------
  bc_hestia_desactivar_host || rc=1

  # --- 3. Las cuentas, una por una -----------------------------------------
  local fallidas=0
  if (( ${#marcadas[@]} == 0 )); then
    bc_ok "No hay ninguna cuenta marcada: nada que desmarcar."
    bc_informe_paso "Desmarcar cuentas" SIN_CAMBIO "no había ninguna marcada"
  else
    for u in "${marcadas[@]}"; do
      echo
      bc_log "Cuenta '$u':"
      bc_hestia_desmarcar_cuenta "$u" || { fallidas=$(( fallidas + 1 )); rc=1; }
    done
  fi

  echo
  if (( fallidas > 0 )); then
    bc_err "$fallidas cuenta(s) SIGUEN MARCADAS para respaldo incremental."
    bc_log  "Eso significa que si mañana registras otro repositorio, esas cuentas"
    bc_log  "EMPEZARÁN A RESPALDAR SOLAS, sin que nadie lo pida. Quítales la marca"
    bc_log  "a mano o vuelve a ejecutar esta orden."
  fi
  bc_log "Las copias que había siguen en el almacenamiento: no se ha borrado nada."

  local estado; estado="$([[ $rc -eq 0 ]] && echo HECHO || echo FALLO)"
  bc_informe_paso "Desactivar" "$estado" \
    "$([[ $fallidas -gt 0 ]] && echo "$fallidas cuenta(s) siguen marcadas" || echo "cron, host y cuentas")"
  local ruta; ruta="$(bc_informe_cerrar "$estado")"
  [[ -n "$ruta" ]] && bc_log "Informe de lo hecho: $ruta"
  (( rc != 0 )) && BC_DELIBERATE_EXIT=1
  return "$rc"
}

# 1. Quitar la línea del cron, con su copia fechada.
bc_hestia_desactivar_cron() {
  local ct; ct="$(printf '%q' "$BC_HESTIA_CRONTAB_SIS")"
  local copia=""
  if ! copia="$(bc_hestia_copia_fechada "$BC_HESTIA_CRONTAB_SIS")"; then
    bc_err "no se pudo copiar el crontab: NO se toca la programación."
    bc_informe_paso "Quitar del cron" FALLO "no se pudo copiar el crontab"
    return 1
  fi
  [[ -n "$copia" ]] && { bc_informe_copia "$BC_HESTIA_CRONTAB_SIS" "$copia"; \
    bc_log "  Copia del crontab: $copia"; }

  local orden="sed -i '/v-backup-users\\?-restic/d' $ct && chmod 600 $ct && chown hestiaweb:hestiaweb $ct"
  bc_informe_orden "$orden"
  local datos
  datos="$(bc_hestia_escribir_y_confirmar "Quitar del cron" "$orden" "cat $ct" \
      bc_hestia_sin_cron_ya_estaba bc_hestia_sin_cron_se_hizo)"

  case "$(bc_hestia_dato_de "$datos" estado)" in
    HECHO)      bc_ok "Programación quitada del cron, y comprobado."
                bc_informe_paso "Quitar del cron" HECHO "la línea ya no está"; return 0 ;;
    SIN_CAMBIO) bc_ok "No había ninguna programación en ese crontab."
                bc_informe_paso "Quitar del cron" SIN_CAMBIO "no había nada que quitar"; return 0 ;;
    SIN_CONFIRMAR)
                bc_err "Se pidió quitar la línea del cron y AL RELEER SIGUE AHÍ."
                bc_log  "El respaldo seguirá ejecutándose cada noche. Mira $BC_HESTIA_CRONTAB_SIS."
                bc_informe_paso "Quitar del cron" SIN_CONFIRMAR "la línea sigue en el crontab"; return 1 ;;
    *)          bc_err "No se pudo quitar la línea del cron."
                bc_informe_paso "Quitar del cron" FALLO "no se pudo quitar"; return 1 ;;
  esac
}

# Los jueces del cron al revés: cumple cuando NO hay ninguna línea.
bc_hestia_sin_cron_ya_estaba() { [[ -z "$(bc_hestia_cron_linea_de "${1:-}")" ]]; }
bc_hestia_sin_cron_se_hizo()   { [[ -z "$(bc_hestia_cron_linea_de "${2:-}")" ]]; }

# 2. Borrar el host de respaldo. OJO: esto NO toca ninguna cuenta.
bc_hestia_desactivar_host() {
  local conf; conf="$(printf '%q' "$HESTIA_CONF_RESTIC")"
  local copia=""
  copia="$(bc_hestia_copia_fechada "$HESTIA_CONF_RESTIC")" || copia=""
  [[ -n "$copia" ]] && { bc_informe_copia "$HESTIA_CONF_RESTIC" "$copia"; \
    bc_log "  Copia de la configuración: $copia"; }

  local orden="$HESTIA_DIR/bin/v-delete-backup-host-restic"
  bc_informe_orden "$orden"
  local datos
  datos="$(bc_hestia_escribir_y_confirmar "Borrar el host de respaldo" "$orden" \
      "cat $conf 2>/dev/null || true" bc_hestia_sin_host_ya_estaba bc_hestia_sin_host_se_hizo)"

  case "$(bc_hestia_dato_de "$datos" estado)" in
    HECHO)      bc_ok "Host de respaldo borrado, y comprobado."
                bc_informe_paso "Borrar el host" HECHO "ya no hay repositorio registrado"; return 0 ;;
    SIN_CAMBIO) bc_ok "No había ningún host de respaldo registrado."
                bc_informe_paso "Borrar el host" SIN_CAMBIO "no había nada registrado"; return 0 ;;
    SIN_CONFIRMAR)
                bc_err "Se pidió borrar el host y la configuración SIGUE AHÍ."
                bc_informe_paso "Borrar el host" SIN_CONFIRMAR "la configuración sigue registrada"; return 1 ;;
    *)          bc_err "No se pudo borrar el host de respaldo."
                bc_informe_paso "Borrar el host" FALLO "no se pudo borrar"; return 1 ;;
  esac
}

# Cumple cuando ya no queda ningún repositorio registrado.
bc_hestia_sin_host_ya_estaba() { [[ -z "$(bc_hestia_conf_valor "${1:-}" REPO)" ]]; }
bc_hestia_sin_host_se_hizo()   { [[ -z "$(bc_hestia_conf_valor "${2:-}" REPO)" ]]; }

# 3. Desmarcar UNA cuenta. Es lo único que de verdad impide que respalde.
bc_hestia_desmarcar_cuenta() {
  local u="${1:-}"
  local archivo="$HESTIA_DIR/data/users/$u/user.conf"
  local esc; esc="$(printf '%q' "$archivo")"

  local copia=""
  if ! copia="$(bc_hestia_copia_fechada "$archivo")" || [[ -z "$copia" ]]; then
    bc_err "  no se pudo copiar su user.conf: NO se toca esta cuenta."
    bc_informe_paso "Desmarcar $u" FALLO "no se pudo copiar su user.conf"
    return 1
  fi
  bc_informe_copia "$archivo" "$copia"
  bc_informe_deshacer "cp -p $copia $archivo   # cuenta $u"

  local orden="$HESTIA_DIR/bin/v-change-user-config-value $(printf '%q' "$u") BACKUPS_INCREMENTAL no"
  bc_informe_orden "$orden"
  local datos
  datos="$(bc_hestia_escribir_y_confirmar "Desmarcar $u" "$orden" "cat $esc" \
      bc_hestia_desmarcada_ya_estaba bc_hestia_desmarcada_se_hizo)"

  local antes despues
  antes="$(bc_hestia_restaurar_saltos "$(bc_hestia_dato_de "$datos" antes)")"
  despues="$(bc_hestia_restaurar_saltos "$(bc_hestia_dato_de "$datos" despues)")"
  bc_informe_dato "Cuenta $u — respaldo incremental" \
    "$(bc_hestia_marca_de "$antes")" "$(bc_hestia_marca_de "$despues")"

  case "$(bc_hestia_dato_de "$datos" estado)" in
    HECHO)      bc_ok "  desmarcada, y comprobado leyendo su user.conf de vuelta."
                bc_informe_paso "Desmarcar $u" HECHO "desmarcada y confirmada"; return 0 ;;
    SIN_CAMBIO) bc_ok "  ya estaba desmarcada."
                bc_informe_paso "Desmarcar $u" SIN_CAMBIO "ya estaba desmarcada"; return 0 ;;
    SIN_CONFIRMAR)
                bc_err "  la orden dijo que fue bien y su user.conf SIGUE MARCADO."
                bc_informe_paso "Desmarcar $u" SIN_CONFIRMAR "sigue marcada"; return 1 ;;
    ESCRITO_SIN_COMPROBAR)
                bc_err "  se escribió y no se pudo volver a leer su user.conf."
                bc_informe_paso "Desmarcar $u" ESCRITO_SIN_COMPROBAR "sin comprobar"; return 1 ;;
    *)          bc_err "  no se pudo desmarcar."
                bc_informe_paso "Desmarcar $u" FALLO "no se pudo desmarcar"; return 1 ;;
  esac
}

# Cumple cuando la cuenta NO está marcada. Una cuenta sin la clave tampoco
# está marcada: no respalda, que es lo que aquí se busca.
bc_hestia_desmarcada_ya_estaba() { [[ "$(bc_hestia_marca_de "${1:-}")" != "yes" ]]; }
bc_hestia_desmarcada_se_hizo()   { [[ "$(bc_hestia_marca_de "${2:-}")" != "yes" ]]; }

# =============================================================================
# La primera copia, COMPROBADA
# =============================================================================
# El paso que cierra el ciclo, y el único que demuestra que todo lo anterior
# sirvió de algo. Es el ADR 0017 en su forma más pura:
#
#   - v-backup-user-restic usa una constante de error que NO existe, así que un
#     respaldo que falla termina registrando ÉXITO. Su código de salida no vale
#     como prueba de nada.
#   - El respaldo incremental no escribe en ningún log de archivo.
#   - La ÚNICA prueba de que un respaldo se hizo es una instantánea nueva con
#     fecha.
#
# De ahí la forma del paso: se lee la lista ANTES, se lanza, se vuelve a leer,
# y el veredicto sale de la DIFERENCIA. Si no se puede leer el antes no se
# lanza nada: sin el antes no se puede demostrar nada, y lanzarlo sería gastar
# el tiempo del servidor para no saber el resultado.
#
# Aquí NO hay copia fechada que hacer: no se sobrescribe ninguna configuración,
# se añade una copia. Lo que este paso hace no se deshace, y no hace falta.
bc_hestia_copia() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Primera copia, comprobada"

  # Por defecto NO todas: un respaldo completo de todas las cuentas de un panel
  # puede tardar mucho y cargar el servidor. Eso no se lanza por descuido.
  local pedidas="${BC_OPT_USERS:-}"
  if [[ -z "$pedidas" ]]; then
    bc_err "hace falta decir de qué cuenta se quiere la copia."
    bc_log  "Esto lanza un respaldo DE VERDAD, que puede tardar y cargar el servidor,"
    bc_log  "así que no se hace de todas por descuido. Elige una o varias:"
    bc_log  "    backupctl -p $BC_PROFILE hestia copia --usuarios cliente07"
    bc_log  "Para ver qué cuentas hay:  backupctl -p $BC_PROFILE hestia users"
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  local cuentas=() u
  while IFS= read -r u; do
    [[ -n "$u" ]] && cuentas+=("$u")
  done <<<"$(tr ',' '\n' <<<"$pedidas")"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_step "Simulación (--dry-run): esto es lo que PASARÍA, no lo que ha pasado."
    for u in "${cuentas[@]}"; do
      local antes_json
      if ! antes_json="$(bc_hestia_lista_instantaneas "$u")"; then
        bc_warn "  $u: no se puede leer su lista de copias, así que NO se lanzaría nada."
        continue
      fi
      local n; n="$(bc_hestia_cuantas_de "$(bc_hestia_instantaneas_de "$antes_json")")"
      bc_log "  $u: tiene $n copia(s) ahora. Se lanzaría un respaldo y se comprobaría"
      bc_log "      que aparece una NUEVA, más reciente que todas las de ahora."
    done
    bc_ok "No se ha tocado nada, y no se ha guardado ningún informe."
    return 0
  fi

  bc_warn "Esto lanza un respaldo DE VERDAD. Puede tardar y cargar el servidor."
  bc_confirm "¿Lanzar la copia de ${#cuentas[@]} cuenta(s)?" y \
    || { bc_log "Cancelado."; return 0; }

  bc_informe_abrir "Primera copia comprobada" "${DEPLOY_HOST:-este servidor}"
  bc_informe_deshacer "Nada que deshacer: este paso AÑADE una copia, no sobrescribe nada."

  local rc=0 hechas=0 fallidas=0
  for u in "${cuentas[@]}"; do
    echo
    bc_log "Cuenta '$u':"
    if bc_hestia_copia_de_cuenta "$u"; then
      hechas=$(( hechas + 1 ))
    else
      fallidas=$(( fallidas + 1 )); rc=1
    fi
  done

  echo
  bc_log "Resumen: $hechas copia(s) comprobada(s), $fallidas sin comprobar."
  bc_informe_paso "Primera copia" "$([[ $fallidas -eq 0 ]] && echo HECHO || echo FALLO)" \
    "$hechas comprobada(s), $fallidas sin comprobar"
  local ruta; ruta="$(bc_informe_cerrar "$([[ $fallidas -eq 0 ]] && echo HECHO || echo FALLO)")"
  [[ -n "$ruta" ]] && bc_log "Informe de lo hecho: $ruta"
  (( rc != 0 )) && BC_DELIBERATE_EXIT=1
  return "$rc"
}

# La lista de instantáneas de una cuenta, en crudo. Devuelve 1 si no se pudo
# leer — que no es lo mismo que «no tiene copias», y por eso no se confunden.
bc_hestia_lista_instantaneas() {
  local u="${1:-}" salida
  salida="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-user-backups-restic $(printf '%q' "$u") json" 2>/dev/null || true)"
  [[ -n "$salida" ]] || return 1
  [[ "$salida" == *"{"* || "$salida" == *"["* ]] || return 1
  printf '%s' "$salida"
}

# Una cuenta. Devuelve 0 solo si apareció una instantánea nueva.
bc_hestia_copia_de_cuenta() {
  local u="${1:-}"

  # 1. El ANTES. Sin él no se puede demostrar nada, así que no se lanza nada.
  local antes_json antes
  if ! antes_json="$(bc_hestia_lista_instantaneas "$u")"; then
    bc_err "  no se pudo leer su lista de copias: NO se ha lanzado ningún respaldo."
    bc_log  "  Sin saber qué había antes, un respaldo no demostraría nada."
    bc_informe_paso "Copia de $u" CIEGO "no se pudo leer la lista previa; no se lanzó nada"
    return 1
  fi
  antes="$(bc_hestia_instantaneas_de "$antes_json")"
  local n_antes; n_antes="$(bc_hestia_cuantas_de "$antes")"
  bc_log "  Antes: $n_antes copia(s)."

  # 2. Lanzar. Se cronometra: es el dato que se querrá saber.
  bc_log "  Lanzando el respaldo... (puede tardar)"
  local t0 t1 segundos salida rc=0
  t0="$(date +%s)"
  salida="$(bc_hestia_root "$HESTIA_DIR/bin/v-backup-user-restic $(printf '%q' "$u")" 2>&1)" || rc=$?
  t1="$(date +%s)"
  segundos=$(( t1 - t0 ))

  # 3. El DESPUÉS.
  local despues_json despues
  if ! despues_json="$(bc_hestia_lista_instantaneas "$u")"; then
    bc_err "  SE LANZÓ el respaldo y no se pudo volver a leer la lista de copias."
    bc_log  "  No sabemos si se hizo. Compruébalo en el panel."
    bc_informe_dato "Cuenta $u — duración" "" "$(bc_hestia_duracion_llana "$segundos")"
    bc_informe_paso "Copia de $u" ESCRITO_SIN_COMPROBAR "se lanzó y no se pudo leer el resultado"
    return 1
  fi
  despues="$(bc_hestia_instantaneas_de "$despues_json")"

  # 4. El veredicto sale de la DIFERENCIA, y solo de ahí.
  local nueva fecha id
  nueva="$(bc_hestia_instantanea_nueva "$antes" "$despues")"
  fecha="${nueva%%$'\t'*}"; id="${nueva#*$'\t'}"

  local tam; tam="$(bc_hestia_tamano_anadido "$despues_json")"
  bc_informe_dato "Cuenta $u — copias" "$n_antes" "$(bc_hestia_cuantas_de "$despues")"
  bc_informe_dato "Cuenta $u — duración" "" "$(bc_hestia_duracion_llana "$segundos")"
  [[ -n "$tam" ]] && bc_informe_dato "Cuenta $u — datos añadidos" "" "$tam"
  # El código de la orden es un DATO, nunca una prueba.
  bc_informe_dato "Cuenta $u — código de la orden (dato, no prueba)" "" "$rc"

  if [[ -n "$nueva" ]]; then
    bc_ok "  Copia HECHA y comprobada: hay una instantánea nueva."
    bc_log "    Identificador: ${id:-<no lo dice la lista>}"
    bc_log "    Fecha:         $(bc_hestia_fecha_legible "$fecha")"
    bc_log "    Tardó:         $(bc_hestia_duracion_llana "$segundos")${tam:+ · añadió $tam}"
    (( rc != 0 )) && bc_warn "  (la orden salió con código $rc, pero la copia está: manda el servidor)"
    bc_informe_dato "Cuenta $u — instantánea nueva" "" \
      "${id:-sin identificador} · $(bc_hestia_fecha_legible "$fecha")"
    bc_informe_paso "Copia de $u" HECHO "instantánea nueva ${id:-sin identificador}"
    return 0
  fi

  if (( rc == 0 )); then
    bc_err "  La orden dijo que el respaldo fue BIEN, y NO hay ninguna copia nueva."
    bc_log  "  Esto es exactamente lo que este paso existe para detectar: HestiaCP"
    bc_log  "  PUEDE DECIR QUE UN RESPALDO SALIÓ BIEN CUANDO HA FALLADO, y acaba de"
    bc_log  "  pasar. No lo arregles repitiendo la orden: mira el destino del"
    bc_log  "  repositorio, que responda, y que la cuenta tenga su contraseña."
    bc_log  "  Sigue habiendo $n_antes copia(s), las mismas que antes."
    [[ -n "$salida" ]] && { bc_log "  Lo que respondió:"; sed 's/^/        /' <<<"$salida"; }
    bc_informe_paso "Copia de $u" SIN_CONFIRMAR \
      "la orden salió con 0 y no apareció ninguna instantánea nueva"
    return 1
  fi

  bc_err "  El respaldo falló (código $rc) y no hay ninguna copia nueva."
  [[ -n "$salida" ]] && { bc_log "  Lo que respondió:"; sed 's/^/        /' <<<"$salida"; }
  bc_informe_paso "Copia de $u" FALLO "la orden falló con $rc y no apareció ninguna instantánea"
  return 1
}

# =============================================================================
# Marcar las cuentas para respaldo incremental
# =============================================================================
# EL PASO MÁS PELIGROSO DE LOS OCHO, y el motivo está en la fuente de HestiaCP
# 1.10.4:
#
#   - Lo que de verdad hace que una cuenta se respalde es BACKUPS_INCREMENTAL
#     (con S) en SU user.conf. El interruptor global no sirve para eso.
#   - v-change-user-config-value con una clave que NO existe dispara un
#     v-rebuild-user COMPLETO —useradd si falta el usuario del sistema,
#     reescritura de permisos, usermod, jaula sftp, colas de disco y tráfico—
#     y después llama a update_user_value, que solo escribe si la línea ya
#     estaba. Es decir: una operación enorme que encima puede no escribir nada.
#   - rebuild_user_conf solo repara una lista cerrada de claves, y
#     BACKUPS_INCREMENTAL no está en ella.
#
# De ahí la regla que manda aquí: ANTES de llamar a nada se comprueba que la
# clave existe en ese user.conf. Si no existe, no se llama. Se explica por qué
# y se ofrece la vía del paquete, que NO se ejecuta desde aquí: reaplicar un
# paquete toca TODAS las cuentas que lo usan y cambia shells, cuotas y
# límites. Eso no puede pasar como efecto colateral de «quiero respaldos».
#
# Y se trabaja cuenta por cuenta, con su copia, su relectura y su estado: una
# que falle no impide intentar las demás, pero el resultado global lo refleja.
bc_hestia_cuentas() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Cuentas en el respaldo incremental"

  local lista
  lista="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-users plain" || true)"
  if [[ -z "$lista" ]]; then
    bc_err "no se pudo leer la lista de cuentas del panel."
    bc_log  "Sin saber qué cuentas hay no se toca ninguna."
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  # Solo las que pida --usuarios, si se pidió alguna.
  local pedidas="${BC_OPT_USERS:-}"
  local cuentas=() u
  while IFS= read -r u; do
    u="$(awk '{print $1}' <<<"$u")"
    [[ -z "$u" || "$u" == "USER" ]] && continue
    if [[ -n "$pedidas" ]]; then
      [[ ",$pedidas," == *",$u,"* ]] || continue
    fi
    cuentas+=("$u")
  done <<<"$lista"

  if (( ${#cuentas[@]} == 0 )); then
    bc_err "ninguna cuenta que tocar${pedidas:+ (se pidieron: $pedidas)}."
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  # --- Qué hay hoy en cada una ----------------------------------------------
  # Se lee TODO antes de escribir NADA: así el ensayo y el informe dicen lo
  # mismo, y el usuario ve la foto completa antes de decidir.
  local -a estado_de=() ; local conf marca
  for u in "${cuentas[@]}"; do
    conf="$(bc_hestia_leer_texto "cat $(printf '%q' "$HESTIA_DIR/data/users/$u/user.conf")")" \
      && marca="$(bc_hestia_marca_de "$conf")" || marca="ilegible"
    estado_de+=("$u:$marca")
  done

  bc_hestia_pintar_cuentas "${estado_de[@]}"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_step "Simulación (--dry-run): esto es lo que PASARÍA, no lo que ha pasado."
    bc_hestia_plan_cuentas "${estado_de[@]}"
    bc_ok "No se ha tocado nada, y no se ha guardado ningún informe."
    return 0
  fi

  # Las que no tienen la clave se nombran y se explican ANTES de preguntar: es
  # parte de a qué está diciendo que sí, y de lo que va a quedar sin hacer.
  local a_tocar=() sin_clave=()
  for marca in "${estado_de[@]}"; do
    case "${marca#*:}" in
      no)        a_tocar+=("${marca%%:*}") ;;
      sin-clave) sin_clave+=("${marca%%:*}") ;;
    esac
  done
  if (( ${#sin_clave[@]} > 0 )); then
    echo
    bc_warn "NO SE PUEDEN MARCAR desde aquí (${#sin_clave[@]}): ${sin_clave[*]}"
    bc_hestia_explicar_sin_clave
  fi

  if (( ${#a_tocar[@]} == 0 )); then
    bc_ok "No hay ninguna cuenta que marcar."
    (( ${#sin_clave[@]} > 0 )) && { BC_DELIBERATE_EXIT=1; return 1; }
    return 0
  fi
  echo

  bc_confirm "¿Marcar ${#a_tocar[@]} cuenta(s) para respaldo incremental?" y \
    || { bc_log "Cancelado."; return 0; }

  bc_informe_abrir "Marcar cuentas para respaldo incremental" "${DEPLOY_HOST:-este servidor}"

  local rc=0 hechas=0 fallidas=0
  for u in "${a_tocar[@]}"; do
    echo
    bc_log "Cuenta '$u':"
    # Una que falle no impide intentar las demás: son independientes, y dejar
    # nueve sin respaldo porque la décima falló no ayuda a nadie.
    if bc_hestia_marcar_cuenta "$u"; then
      hechas=$(( hechas + 1 ))
    else
      fallidas=$(( fallidas + 1 )); rc=1
    fi
  done

  echo
  bc_log "Resumen: $hechas cuenta(s) marcada(s), $fallidas con problemas."
  bc_informe_paso "Marcar cuentas" "$([[ $fallidas -eq 0 ]] && echo HECHO || echo FALLO)" \
    "$hechas marcada(s), $fallidas con problemas"
  local ruta_informe; ruta_informe="$(bc_informe_cerrar "$([[ $fallidas -eq 0 ]] && echo HECHO || echo FALLO)")"
  [[ -n "$ruta_informe" ]] && bc_log "Informe de lo hecho: $ruta_informe"
  (( rc != 0 )) && BC_DELIBERATE_EXIT=1
  return "$rc"
}

# Qué dice el user.conf sobre el respaldo incremental de esa cuenta. Pura.
#   yes       la clave está y vale 'yes'
#   no        la clave está y vale otra cosa
#   sin-clave la clave NO ESTÁ. No es lo mismo que 'no': es una cuenta anterior
#             al paquete que la trae, y ahí NO se puede llamar a la orden.
bc_hestia_marca_de() {
  local conf="${1:-}"
  grep -q "^BACKUPS_INCREMENTAL=" <<<"$conf" || { echo "sin-clave"; return 0; }
  if grep -q "^BACKUPS_INCREMENTAL='yes'" <<<"$conf"; then echo "yes"; else echo "no"; fi
}

# La foto de partida, para que el usuario vea a qué está diciendo que sí.
bc_hestia_pintar_cuentas() {
  local par u marca
  for par in "$@"; do
    u="${par%%:*}"; marca="${par#*:}"
    case "$marca" in
      yes)       bc_ok   "  $u: ya está marcada" ;;
      no)        bc_log  "  $u: NO está marcada (se marcaría)" ;;
      sin-clave) bc_warn "  $u: no tiene la clave BACKUPS_INCREMENTAL" ;;
      *)         bc_warn "  $u: no se pudo leer su user.conf" ;;
    esac
  done
}

# El plan del ensayo: qué cuentas se tocarían, cuáles no, y por qué. En un
# servidor con diez cuentas esto es lo más valioso del paso.
bc_hestia_plan_cuentas() {
  local par u marca
  local -a se_tocan=() ya=() sin_clave=() ilegibles=()
  for par in "$@"; do
    u="${par%%:*}"; marca="${par#*:}"
    case "$marca" in
      no)        se_tocan+=("$u") ;;
      yes)       ya+=("$u") ;;
      sin-clave) sin_clave+=("$u") ;;
      *)         ilegibles+=("$u") ;;
    esac
  done

  if (( ${#se_tocan[@]} > 0 )); then
    bc_log "SE TOCARÍAN (${#se_tocan[@]}): ${se_tocan[*]}"
    bc_log "  De cada una se dejaría antes una copia fechada de su user.conf."
  else
    bc_log "No se tocaría ninguna cuenta."
  fi
  (( ${#ya[@]} > 0 )) && bc_log "Ya marcadas, no se tocan (${#ya[@]}): ${ya[*]}"
  if (( ${#sin_clave[@]} > 0 )); then
    bc_warn "NO SE PUEDEN MARCAR desde aquí (${#sin_clave[@]}): ${sin_clave[*]}"
    bc_hestia_explicar_sin_clave
  fi
  (( ${#ilegibles[@]} > 0 )) && bc_warn "No se pudo leer su configuración (${#ilegibles[@]}): ${ilegibles[*]}"
  return 0
}

# Por qué una cuenta sin la clave no se toca, y qué puede hacer el usuario.
bc_hestia_explicar_sin_clave() {
  bc_log "Esas cuentas son anteriores al paquete que trae BACKUPS_INCREMENTAL."
  bc_log "Pedirle a HestiaCP que cambie una clave que NO existe en el user.conf"
  bc_log "dispara una RECONSTRUCCIÓN COMPLETA de la cuenta —crear el usuario del"
  bc_log "sistema si falta, reescribir permisos, usermod, la jaula de sftp y las"
  bc_log "colas de disco y tráfico— y aun así probablemente no escribiría nada,"
  bc_log "porque solo actualiza la línea si ya estaba."
  bc_log "Por eso esta orden NO lo intenta."
  bc_log "La vía es reaplicar el paquete de esas cuentas, y esa la ejecutas tú:"
  bc_log "    v-update-user-package <paquete>"
  bc_warn "OJO: eso reaplica el paquete a TODAS sus cuentas y puede cambiar shell,"
  bc_warn "cuotas y límites. Míralo antes de ejecutarlo."
  return 0
}

# Marca UNA cuenta. Devuelve 0 solo si quedó marcada y comprobado.
bc_hestia_marcar_cuenta() {
  local u="${1:-}"
  local archivo="$HESTIA_DIR/data/users/$u/user.conf"
  local esc; esc="$(printf '%q' "$archivo")"

  local copia=""
  if ! copia="$(bc_hestia_copia_fechada "$archivo")"; then
    bc_err "  no se pudo copiar su user.conf: NO se toca esta cuenta."
    bc_informe_paso "Cuenta $u" FALLO "no se pudo copiar su user.conf; no se tocó"
    return 1
  fi
  if [[ -z "$copia" ]]; then
    bc_err "  no existe $archivo: NO se toca esta cuenta."
    bc_informe_paso "Cuenta $u" FALLO "no existe su user.conf"
    return 1
  fi
  bc_informe_copia "$archivo" "$copia"
  bc_informe_deshacer "cp -p $copia $archivo   # cuenta $u"

  local orden_escritura="$HESTIA_DIR/bin/v-change-user-config-value $(printf '%q' "$u") BACKUPS_INCREMENTAL yes"
  bc_informe_orden "$orden_escritura"

  BC_HESTIA_CUENTA_ACTUAL="$u"
  local datos
  datos="$(bc_hestia_escribir_y_confirmar "Cuenta $u" "$orden_escritura" "cat $esc" \
      bc_hestia_cuenta_ya_estaba bc_hestia_cuenta_se_hizo)"

  local estado antes despues codigo
  estado="$(bc_hestia_dato_de "$datos" estado)"; estado="${estado:-CIEGO}"
  antes="$(bc_hestia_restaurar_saltos "$(bc_hestia_dato_de "$datos" antes)")"
  despues="$(bc_hestia_restaurar_saltos "$(bc_hestia_dato_de "$datos" despues)")"
  codigo="$(bc_hestia_dato_de "$datos" codigo)"

  bc_informe_dato "Cuenta $u — respaldo incremental" \
    "$(bc_hestia_marca_de "$antes")" "$(bc_hestia_marca_de "$despues")"

  case "$estado" in
    HECHO)
      bc_ok "  marcada, y comprobado leyendo su user.conf de vuelta."
      bc_informe_paso "Cuenta $u" HECHO "marcada y confirmada"; return 0 ;;
    SIN_CAMBIO)
      bc_ok "  ya estaba marcada."
      bc_informe_paso "Cuenta $u" SIN_CAMBIO "ya estaba marcada"; return 0 ;;
    SIN_CONFIRMAR)
      bc_err "  la orden dijo que fue bien (código $codigo) y su user.conf NO lo confirma."
      bc_log  "  Sigue en: $(bc_hestia_marca_de "$despues"). La copia está en $copia"
      bc_informe_paso "Cuenta $u" SIN_CONFIRMAR "la relectura no confirma el cambio"; return 1 ;;
    ESCRITO_SIN_COMPROBAR)
      bc_err "  SE ESCRIBIÓ y no se pudo volver a leer su user.conf. Míralo: $archivo"
      bc_informe_paso "Cuenta $u" ESCRITO_SIN_COMPROBAR "se escribió y no se pudo comprobar"; return 1 ;;
    FALLO)
      bc_err "  la orden falló (código $codigo) y la cuenta no cambió."
      bc_informe_paso "Cuenta $u" FALLO "la orden falló"; return 1 ;;
    *)
      bc_err "  no se pudo leer su user.conf: NO se ha tocado nada."
      bc_informe_paso "Cuenta $u" CIEGO "no se pudo leer su user.conf"; return 1 ;;
  esac
}

# La cuenta que se está marcando, para los jueces.
BC_HESTIA_CUENTA_ACTUAL=""

# Los dos jueces. Una cuenta SIN la clave nunca cumple: no es que esté en
# 'no', es que ahí no se puede escribir con esta orden.
bc_hestia_cuenta_ya_estaba() { [[ "$(bc_hestia_marca_de "${1:-}")" == "yes" ]]; }
bc_hestia_cuenta_se_hizo()   { [[ "$(bc_hestia_marca_de "${2:-}")" == "yes" ]]; }

# =============================================================================
# Escribir en el servidor y COMPROBARLO
# =============================================================================
# La regla del ADR 0017: HestiaCP puede decir que hizo algo y no haberlo hecho
# —la orden del respaldo incremental registra éxito aunque el respaldo falle—.
# Por eso nada que escriba en un servidor puede fiarse del código de salida de
# la orden: hay que leer el estado antes, escribir, volver a leerlo y juzgar
# por la diferencia. Esto es esa secuencia, escrita una vez.
#
#   bc_hestia_escribir_y_confirmar <etiqueta> <orden_escritura> <orden_lectura> \
#                                  <ya_estaba> <se_hizo> [<por_stdin>]
#
# El sexto argumento es opcional: lo que haya que mandarle a la orden por la
# ENTRADA ESTÁNDAR. Existe porque un secreto NO puede viajar en la línea de
# órdenes —ahí lo ve cualquier otro usuario del servidor con `ps`— y sin esto
# el único paso que manda credenciales tenía que repetir toda la secuencia por
# su cuenta, con lo que eso acaba costando cuando hay dos.
#
# DOS JUECES, NO UNO. Los dos son funciones puras que trae cada paso:
#   ya_estaba <antes>            0 si el estado leído ya cumple el criterio.
#   se_hizo   <antes> <después>  0 si el cambio se ve en el estado leído.
# Antes era uno solo al que se llamaba dos veces, con el «después» vacío para
# preguntar «¿ya estaba?». Funcionaba, pero un juez que se olvidara de mirar el
# segundo argumento habría dicho SIN_CAMBIO siempre y no habría escrito nunca:
# un fallo que no rompe nada, no da error y deja la herramienta sin hacer su
# trabajo. Dos funciones son más verbosas e imposibles de confundir. Un paso
# escribe las dos aunque solo necesite una.
#
# Devuelve DATOS, no texto para nadie: una línea por campo, con el mismo
# separador y el mismo cuidado que el diagnóstico. No pinta, no sabe qué nivel
# es cada estado ni qué color lleva.
#
#   estado    SIN_CAMBIO|HECHO|SIN_CONFIRMAR|FALLO|CIEGO|ESCRITO_SIN_COMPROBAR
#   antes     lo que se leyó antes de tocar nada
#   despues   lo que se leyó después (vacío si no se pudo leer)
#   codigo    el código con el que salió la orden de escritura (vacío si no se
#             llegó a ejecutar)
#   salida    lo que imprimió la orden de escritura
#
# LOS SEIS ESTADOS
#   SIN_CAMBIO     el antes ya cumplía. NO se escribió nada. No es un éxito
#                  disfrazado: se dice «no había nada que cambiar».
#   HECHO          se escribió y la relectura lo confirma. También cuando la
#                  orden salió con error pero el cambio SÍ se ve: manda el
#                  estado del servidor, no lo que diga la orden.
#   SIN_CONFIRMAR  se escribió, la orden dijo que bien, y la relectura NO lo
#                  confirma. Este estado existe por el ADR 0017 y no puede
#                  caer en FALLO: la acción que toca es distinta —ir a mirar
#                  por qué el servidor dice una cosa y enseña otra—, no
#                  reintentar.
#   FALLO          la orden falló y la relectura tampoco confirma el cambio.
#   CIEGO          no se pudo leer el ANTES, así que NO se escribió nada. Sin
#                  saber qué había no se puede informar ni deshacer. Es
#                  inocuo: el servidor quedó como estaba.
#   ESCRITO_SIN_COMPROBAR
#                  se escribió y no se pudo leer el DESPUÉS. Exige ir al
#                  servidor. Va aparte de CIEGO porque para quien lo lee son
#                  dos cosas muy distintas, y distinguirlas mirando si un
#                  campo viene vacío es justo lo que no se hace aquí.
bc_hestia_escribir_y_confirmar() {
  local etiqueta="${1:-}" orden_escritura="${2:-}" orden_lectura="${3:-}"
  local ya_estaba="${4:-}" se_hizo="${5:-}" por_stdin="${6:-}"
  local antes despues rc=0 salida=""

  # La etiqueta viaja con los datos para que quien informe sepa de qué paso
  # son sin tener que acordarse del orden en que los pidió.
  bc_hestia_registro etiqueta "$etiqueta"

  # 1. El ANTES. Se lee con centinela: una salida vacía puede ser un valor
  #    vacío legítimo, y no es lo mismo que no haber podido preguntar.
  if ! antes="$(bc_hestia_leer_texto "$orden_lectura")"; then
    bc_hestia_escribir_datos CIEGO "" "" "" ""
    return 0
  fi

  # 2. ¿Ya estaba? Se pregunta ANTES de escribir. Escribir sobre algo que ya
  #    cumple es tocar un servidor sin motivo, y en esta herramienta tocar de
  #    más es justo lo que hay que evitar.
  if "$ya_estaba" "$antes"; then
    bc_hestia_escribir_datos SIN_CAMBIO "$antes" "$antes" "" ""
    return 0
  fi

  # 3. Escribir. El código se guarda como DATO, nunca como prueba.
  #
  # Si el paso trae algo por la ENTRADA ESTÁNDAR, va por ahí y no en la línea
  # de órdenes: un secreto en la línea de órdenes es visible en `ps` para
  # cualquier otro usuario del servidor. El nombre del sexto argumento es lo
  # único que distingue los dos caminos, y por eso se llama así.
  if [[ -n "$por_stdin" ]]; then
    salida="$(printf '%s' "$por_stdin" | bc_hestia_root_stdin "$orden_escritura" 2>&1)" || rc=$?
  else
    salida="$(bc_hestia_root "$orden_escritura" 2>&1)" || rc=$?
  fi

  # 4. El DESPUÉS. Si no se puede leer, NO es lo mismo que no haber podido
  #    leer el antes: allí no se tocó nada y aquí sí. Se dice con su propio
  #    estado, porque lo que el usuario tiene que hacer es distinto.
  if ! despues="$(bc_hestia_leer_texto "$orden_lectura")"; then
    bc_hestia_escribir_datos ESCRITO_SIN_COMPROBAR "$antes" "" "$rc" "$salida"
    return 0
  fi

  # 5. Juzgar por la diferencia, no por el código.
  local estado
  if "$se_hizo" "$antes" "$despues"; then
    estado=HECHO
  elif (( rc == 0 )); then
    estado=SIN_CONFIRMAR
  else
    estado=FALLO
  fi
  bc_hestia_escribir_datos "$estado" "$antes" "$despues" "$rc" "$salida"
  return 0
}

# Los cinco campos de salida, siempre los cinco y siempre en el mismo orden.
bc_hestia_escribir_datos() {
  bc_hestia_registro estado  "${1:-}"
  bc_hestia_registro antes   "${2:-}"
  bc_hestia_registro despues "${3:-}"
  bc_hestia_registro codigo  "${4:-}"
  bc_hestia_registro salida  "${5:-}"
}

# Lee un texto del servidor distinguiendo «vacío» de «no se pudo leer».
# Imprime el texto y devuelve 0; devuelve 1 si la lectura no llegó a ocurrir.
#
# El centinela es el mismo truco que bc_hestia_sondear: el código de salida de
# la orden no distingue «el archivo está vacío» de «la conexión se cayó», y
# confundirlos hace que un paso escriba creyendo que no había nada. La orden va
# dentro de su propio `bash -c` por lo mismo que allí: el camino con sudo
# antepone texto y un grupo de llaves detrás de sudo es un error de sintaxis.
bc_hestia_leer_texto() {
  local orden="${1:-}" guion salida
  guion="{ $orden; } 2>/dev/null; printf 'BC_FIN\n'"
  salida="$( { bc_hestia_root "bash -c $(printf '%q' "$guion")" 2>/dev/null || true; } | tr -d '\r' )"
  [[ "$salida" == *BC_FIN* ]] || return 1
  # La última línea es el centinela; lo que quede por encima es el valor.
  printf '%s' "$(sed '$d' <<<"$salida")"
  return 0
}

# =============================================================================
# Estado
# =============================================================================
bc_hestia_status() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Respaldos de HestiaCP — perfil '$BC_PROFILE'"

  # --- Host de respaldo Restic ----------------------------------------------
  local conf
  conf="$(bc_hestia_read "cat '$HESTIA_CONF_RESTIC'" || true)"
  if [[ -z "$conf" ]]; then
    bc_warn "Restic NO está configurado en este servidor."
    bc_log  "Móntalo con:  backupctl hestia setup"
  else
    local repo snaps d w m y
    repo="$(sed -n "s/^REPO='\(.*\)'$/\1/p"          <<<"$conf")"
    snaps="$(sed -n "s/^SNAPSHOTS='\(.*\)'$/\1/p"    <<<"$conf")"
    d="$(sed -n "s/^KEEP_DAILY='\(.*\)'$/\1/p"       <<<"$conf")"
    w="$(sed -n "s/^KEEP_WEEKLY='\(.*\)'$/\1/p"      <<<"$conf")"
    m="$(sed -n "s/^KEEP_MONTHLY='\(.*\)'$/\1/p"     <<<"$conf")"
    y="$(sed -n "s/^KEEP_YEARLY='\(.*\)'$/\1/p"      <<<"$conf")"
    bc_ok "Restic configurado."
    {
      printf 'Repositorio\t%s\n' "$repo"
      printf 'Instantáneas totales\t%s\n' "$snaps"
      printf 'Diarias\t%s\n'   "$d"
      printf 'Semanales\t%s\n' "$w"
      printf 'Mensuales\t%s\n' "$m"
      printf 'Anuales\t%s\n'   "$(bc_hestia_texto_anuales_registro "$y" " (-1)")"
    } | bc_table | sed 's/^/        /'
  fi

  # --- Remoto de rclone ------------------------------------------------------
  local remotos
  remotos="$(bc_hestia_read "grep -oP '^\[\K[^]]+' '$BC_HESTIA_RCLONE_CONF'" || true)"
  if [[ -n "$remotos" ]]; then
    bc_ok "Remotos de rclone: $(tr '\n' ' ' <<<"$remotos")"
  else
    bc_warn "no hay remotos de rclone configurados (o no se pudo leer $BC_HESTIA_RCLONE_CONF)."
  fi

  # --- Cron ------------------------------------------------------------------
  local donde
  donde="$(bc_hestia_cron_donde)"
  if [[ -n "$donde" ]]; then
    bc_ok "Cron de Restic activo:"
    sed 's/^/        /' <<<"$donde"
  else
    bc_warn "el cron de Restic NO está activo: nunca se respaldará solo."
    bc_log  "Actívalo con:  backupctl hestia cron"
  fi

  # --- Usuarios y último respaldo -------------------------------------------
  local usuarios
  usuarios="$( { bc_hestia_v "v-list-users plain" 2>/dev/null || true; } | awk '{print $1}')"
  if [[ -n "$usuarios" ]]; then
    bc_log "Usuarios de HestiaCP: $(tr '\n' ' ' <<<"$usuarios")"
  fi

  # --- Diagnóstico: ¿esto respalda de verdad? --------------------------------
  # Lo que sigue no describe la configuración: dice si funciona. El juicio vive
  # en las funciones puras de arriba; aquí solo se LEE del servidor y se pinta.
  # El `|| diag_rc=$?` no sobra: con `set -e` activo, una llamada suelta que
  # devuelve distinto de cero ABORTA la orden entera, y justo entonces —cuando
  # hay algo que contar— se perdería el resto del informe y el cierre
  # deliberado de abajo.
  local diag_rc=0
  bc_hestia_diagnosticar "$conf" "$donde" "$usuarios" || diag_rc=$?

  # --- Claves rescatadas -----------------------------------------------------
  local restic_local rclone_local
  local dir_claves; dir_claves="$(bc_hestia_salida)"
  restic_local="$( { find "$dir_claves" -maxdepth 1 -name 'Restic_Configs_*.txt' 2>/dev/null || true; } | wc -l)"
  rclone_local="$( { find "$dir_claves" -maxdepth 1 -name 'rclone_*.conf' 2>/dev/null || true; } | wc -l)"
  if (( restic_local > 0 )); then bc_ok "Claves Restic rescatadas: $restic_local archivo(s)."
  else bc_err "las claves Restic NO están rescatadas. Sin ellas el repositorio es ILEGIBLE."; fi
  if (( rclone_local > 0 )); then bc_ok "rclone.conf rescatado: $rclone_local archivo(s)."
  else bc_err "el rclone.conf NO está rescatado. Sin él no se puede LLEGAR al repositorio."; fi
  (( restic_local == 0 || rclone_local == 0 )) && bc_log "Rescátalas con:  sudo backupctl hestia keys"

  # Código de salida 1 si el diagnóstico encontró un FALLO O si algo no se pudo
  # leer: las dos cosas «requieren atención», que es lo que el 1 significa en
  # este proyecto. El 2 sigue siendo «no se pudo ni empezar», que es lo que da
  # bc_die cuando no hay HestiaCP o no se puede conectar, y no se toca.
  (( diag_rc != 0 )) && { BC_DELIBERATE_EXIT=1; return 1; }
  return 0
}

# -----------------------------------------------------------------------------
# El diagnóstico: solo LEE del servidor y delega el juicio
# -----------------------------------------------------------------------------
# $1 el contenido de conf/restic.conf   $2 la salida de bc_hestia_cron_donde
# $3 la lista de cuentas del panel
# Devuelve 1 si encontró algún FALLO o si algo no se pudo leer; 0 si no.
#
# Los datos que no se pudieron leer se cuentan APARTE de los avisos. No son lo
# mismo: un aviso es algo que se miró y no gusta; un dato ciego es algo que no
# se miró, y mezclarlos deja al usuario creyendo que el diagnóstico fue
# completo cuando no lo fue (40-salvaguardas.md §5). De la contraseña de una
# cuenta solo se dice si está o no: nunca su contenido.
bc_hestia_diagnosticar() {
  local datos
  datos="$(bc_hestia_leer_diagnostico "${1:-}" "${2:-}" "${3:-}")"
  bc_hestia_pintar_diagnostico "$datos"
}

# -----------------------------------------------------------------------------
# La parte que LEE
# -----------------------------------------------------------------------------
# Habla con el servidor y no imprime NADA para el usuario: devuelve los datos
# en crudo, una línea por cosa, con los campos separados por tabuladores.
#
#   repo      <repositorio registrado>  <tipo del remoto: el tipo, '?' o vacío>
#   cron      <línea del cron>          <archivo donde vive>
#   cada_h    <cada cuántas horas>      <leido|asumido>
#   ahora     <epoch>
#   cuentas   <si|no>                   ('no' = no se pudo leer la lista)
#   cuenta    <nombre> <clave> <repo> <marcada> <fecha de la última copia>
#
# El separador es el carácter de unidad (0x1F), no un tabulador. El tabulador
# es un espacio en blanco para IFS y bash COLAPSA las series de separadores en
# blanco al leer: un campo vacío en medio desaparecería y todos los de detrás
# se correrían un sitio. Con una cuenta sin fecha de última copia, eso movería
# los datos de una columna a otra. Lo que venga dentro de un valor se limpia
# antes de emitirlo.
bc_hestia_leer_diagnostico() {
  local conf="${1:-}" donde="${2:-}" usuarios="${3:-}"

  # --- La ruta registrada ----------------------------------------------------
  local repo tipo_remoto="" rem
  repo="$(sed -n "s/^REPO='\(.*\)'$/\1/p" <<<"$conf")"
  if [[ "$repo" == rclone:* ]]; then
    rem="${repo#rclone:}"; rem="${rem%%:*}"
    tipo_remoto="$( { bc_hestia_root "rclone config show $(printf '%q' "$rem") 2>/dev/null \
        | awk '/^type[[:space:]]*=/{sub(/^type[[:space:]]*=[[:space:]]*/,\"\"); print; exit}'" \
        || true; } | tr -d '\r' )"
    # Es un remoto de rclone: aquí SÍ hay un tipo que mirar, y se consultó de
    # verdad (el 0). Si no salió nada, no es «no aplica», es «no lo pude leer».
    tipo_remoto="$(bc_hestia_tipo_leido "$tipo_remoto" 0)"
  fi
  bc_hestia_registro repo "$repo" "$tipo_remoto"

  # --- El cron ---------------------------------------------------------------
  # bc_hestia_cron_donde devuelve "archivo:contenido" (grep -H). Se coge la
  # primera línea: si hubiera varias, la de más arriba es la que manda para el
  # diagnóstico y las demás ya se listaron más arriba.
  local linea_cron="" archivo_cron=""
  if [[ -n "$donde" ]]; then
    linea_cron="$(sed -n '1p' <<<"$donde")"
    if [[ "$linea_cron" == /*:* ]]; then
      archivo_cron="${linea_cron%%:*}"
      linea_cron="${linea_cron#*:}"
    fi
  fi
  bc_hestia_registro cron "$linea_cron" "$archivo_cron"

  # Cada cuántas horas corre, para poder juzgar si una instantánea es vieja.
  # Sin una línea legible se asume a diario, que es lo que instala esta misma
  # herramienta; se marca como 'asumido' para que quien pinte lo diga y nadie
  # lo tome por un dato leído.
  local cada_h=24 origen_cada_h=asumido
  if [[ -n "$linea_cron" ]]; then
    origen_cada_h=leido
    local c_min c_hora c_resto
    read -r c_min c_hora c_resto <<<"$linea_cron"
    if [[ "$c_hora" == "*" ]]; then cada_h=1
    elif [[ "$c_hora" =~ ^\*/([0-9]+)$ ]]; then cada_h="${BASH_REMATCH[1]}"
    elif [[ "$c_hora" == *,* ]]; then cada_h=$(( 24 / $(tr ',' '\n' <<<"$c_hora" | grep -c .) ))
    fi
  fi
  (( cada_h < 1 )) && cada_h=1
  bc_hestia_registro cada_h "$cada_h" "$origen_cada_h"
  bc_hestia_registro ahora "$(date +%s)"

  # --- Cuenta por cuenta -----------------------------------------------------
  if [[ -z "$usuarios" ]]; then
    bc_hestia_registro cuentas no
    return 0
  fi
  bc_hestia_registro cuentas si

  local u clave repo_existe marcada fecha
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue

    # Las tres lecturas devuelven un CENTINELA (SI/NO), no un código de salida.
    # Motivo: `test -f` y `grep -q` salen con 1 tanto si la respuesta es «no»
    # como si la orden no llegó a ejecutarse (conexión caída, sudo denegado).
    # Con el centinela, «no me respondió» se convierte en '?' y no en un 0 que
    # el diagnóstico presentaría como un hecho leído.

    # ¿Tiene contraseña de repositorio? Solo SI o NO; el contenido no se lee.
    clave="$(bc_hestia_sondear "test -f $(printf '%q' "$HESTIA_DIR/data/users/$u/restic.conf")")"

    # ¿Está marcada? BACKUPS_INCREMENTAL, con S, en el user.conf de la cuenta.
    # Con `grep -q` y su código de salida, no contando coincidencias: contar
    # aquí no aporta nada, y contar con un cero por defecto detrás acaba
    # imprimiendo ese cero dos veces (el propio contador ya escribe "0" antes
    # de salir con 1). Es el patrón que vigila tests/probar_patrones.sh.
    marcada="$(bc_hestia_sondear "grep -q \"^BACKUPS_INCREMENTAL='yes'\" $(printf '%q' "$HESTIA_DIR/data/users/$u/user.conf")")"

    # ¿Existe el repositorio de esta cuenta? Doble sonda; el porqué está en
    # bc_hestia_juzgar_repo. Si no hay ninguno registrado en el servidor, no
    # se pregunta: la línea «Ruta del repositorio» ya lo dijo una vez.
    if [[ -z "$repo" ]]; then
      repo_existe='-'
    else
      repo_existe="$(bc_hestia_sondear_repo "$repo" "$u")"
    fi

    # La última instantánea, SIEMPRE con json explícito: con un formato que no
    # reconoce, la orden de HestiaCP devuelve vacío y código 0, que se leería
    # como «no tiene copias» (ADR 0017).
    fecha="$(bc_hestia_ultima_instantanea "$u")"

    bc_hestia_registro cuenta "$u" "$clave" "$repo_existe" "$marcada" "$fecha"
  done <<<"$usuarios"
  return 0
}

# Emite un registro del conjunto de datos. Los tabuladores de dentro de un
# valor se vuelven espacios: son el separador, y uno perdido ahí dentro
# desplazaría todos los campos siguientes.
BC_HESTIA_SEP=$'\x1f'

# Un salto de línea dentro de un valor partiría el registro en dos, y quien lee
# no podría distinguir esa mitad de un registro nuevo. Pero APLANARLO a un
# espacio pierde información justo cuando más se necesita: la salida de una
# orden que fue mal se lee en varias líneas o no se lee. Así que se CODIFICA
# con el separador de registro (0x1E) y se restaura al presentarla.
BC_HESTIA_NL=$'\x1e'

bc_hestia_registro() {
  local campo valor salida=""
  for campo in "$@"; do
    valor="${campo//$BC_HESTIA_SEP/ }"
    valor="${valor//$BC_HESTIA_NL/ }"
    salida+="${valor//$'\n'/$BC_HESTIA_NL}$BC_HESTIA_SEP"
  done
  printf '%s\n' "${salida%$BC_HESTIA_SEP}"
}

# Devuelve un valor con sus saltos de línea de vuelta. Lo usa quien PRESENTA
# los datos (el informe, la pantalla), nunca quien los transporta.
bc_hestia_restaurar_saltos() { printf '%s' "${1//$BC_HESTIA_NL/$'\n'}"; }

# -----------------------------------------------------------------------------
# La parte que PINTA y CUENTA
# -----------------------------------------------------------------------------
# Recibe lo que devolvió bc_hestia_leer_diagnostico y no toca NADA remoto: por
# eso el banco puede probarla entera, con datos sintéticos, sin ssh. Devuelve
# el código de salida del diagnóstico.
bc_hestia_pintar_diagnostico() {
  local datos="${1:-}"
  local fallos=0 avisos=0 ciegos=0 sin_contar=0

  echo
  bc_step "¿Los respaldos funcionan de verdad?"

  # Los datos se recorren dos veces: primero lo global, después las cuentas. Es
  # más barato que arrastrar variables por un solo bucle, y deja el orden del
  # informe fijo aunque el de los datos cambie.
  local repo="" tipo_remoto="" linea_cron="" archivo_cron=""
  local cada_h=24 origen_cada_h=asumido ahora=0 hay_cuentas=si
  local -a c
  while IFS="$BC_HESTIA_SEP" read -r -a c; do
    case "${c[0]:-}" in
      repo)    repo="${c[1]:-}";       tipo_remoto="${c[2]:-}" ;;
      cron)    linea_cron="${c[1]:-}"; archivo_cron="${c[2]:-}" ;;
      cada_h)  cada_h="${c[1]:-24}";   origen_cada_h="${c[2]:-asumido}" ;;
      ahora)   ahora="${c[1]:-0}" ;;
      cuentas) hay_cuentas="${c[1]:-si}" ;;
    esac
  done <<<"$datos"

  bc_hestia_pintar_veredicto "Ruta del repositorio" \
    "$(bc_hestia_diag_ruta_repo "$repo" "$tipo_remoto")" fallos avisos ciegos
  bc_hestia_pintar_veredicto "Programación" \
    "$(bc_hestia_diag_cron "$linea_cron" "$archivo_cron")" fallos avisos ciegos

  [[ "$origen_cada_h" == "asumido" ]] \
    && bc_log "No hay línea de cron legible: para juzgar la antigüedad se asume una vez al día."

  if [[ "$hay_cuentas" != "si" ]]; then
    bc_warn "No se pudo leer la lista de cuentas del panel: el diagnóstico por cuenta se omite."
    ciegos=$(( ciegos + 1 ))
    bc_hestia_resumen_diag "$fallos" "$avisos" "$ciegos"
    bc_hestia_codigo_diag "$fallos" "$ciegos"
    return
  fi

  local u clave repo_existe marcada fecha dato
  while IFS="$BC_HESTIA_SEP" read -r -a c; do
    [[ "${c[0]:-}" == "cuenta" ]] || continue
    u="${c[1]:-}"; clave="${c[2]:-?}"; repo_existe="${c[3]:-?}"
    marcada="${c[4]:-?}"; fecha="${c[5]:-}"
    [[ -n "$u" ]] || continue

    echo
    bc_log "Cuenta '$u':"

    # El veredicto de la cuenta se pinta con `sin_contar`: si sale CIEGO, lo
    # que cuenta es cuántos DATOS quedaron sin leer (hasta tres), no cuántas
    # cuentas. Eso lo hace el bucle de abajo.
    bc_hestia_pintar_veredicto "  estado" \
      "$(bc_hestia_diag_cuenta "$clave" "$repo_existe" "$marcada")" fallos avisos sin_contar

    # El '-' no cuenta: no es ceguera, es que no hay ningún repositorio
    # registrado, y eso ya lo dijo la línea de arriba una sola vez.
    for dato in "$clave" "$repo_existe" "$marcada"; do
      [[ "$dato" == "?" ]] && ciegos=$(( ciegos + 1 ))
    done

    if [[ "$fecha" == "__ILEGIBLE__" ]]; then
      bc_warn "  última copia: no se pudo leer la lista de instantáneas."
      ciegos=$(( ciegos + 1 ))
    else
      bc_hestia_pintar_veredicto "  última copia" \
        "$(bc_hestia_diag_instantanea "$fecha" "$ahora" "$cada_h")" fallos avisos ciegos
    fi
  done <<<"$datos"

  bc_hestia_resumen_diag "$fallos" "$avisos" "$ciegos"
  bc_hestia_codigo_diag "$fallos" "$ciegos"
}

# Código de salida del diagnóstico. Pura, y aparte, para que el banco la pruebe
# sin montar un servidor.
# $1 fallos   $2 datos que no se pudieron leer
#
# Los avisos NO son parámetro: no cambian el código, y una firma que los pida
# para no usarlos es un contrato falso que alguien leerá como verdadero. Si
# algún día cuentan, se añaden entonces; las llamadas son dos.
#
# Lo cambian un FALLO y una CEGUERA, porque las dos «requieren atención», que
# es lo que el 1 significa en este proyecto (docs/referencia/codigos.md). Un
# diagnóstico ciego saliendo con 0 sería un éxito sin comprobación
# (40-salvaguardas.md §5).
bc_hestia_codigo_diag() {
  local fallos="${1:-0}" ciegos="${2:-0}"
  (( fallos > 0 || ciegos > 0 )) && return 1
  return 0
}

# Cierre del diagnóstico. Separada y pura salvo por lo que imprime, para que el
# banco pueda comprobar el texto sin montar un servidor entero.
# $1 fallos   $2 avisos   $3 datos que no se pudieron leer
bc_hestia_resumen_diag() {
  local fallos="${1:-0}" avisos="${2:-0}" ciegos="${3:-0}"
  echo
  bc_log "Resumen del diagnóstico: $fallos fallo(s) · $avisos aviso(s) · $ciegos dato(s) que no se pudieron leer."
  if (( ciegos > 0 )); then
    bc_warn "El diagnóstico está INCOMPLETO: con $ciegos dato(s) sin leer no se"
    bc_warn "puede afirmar que los respaldos funcionen. Arregla primero el acceso."
  fi
  return 0
}

# Fecha ISO de la última instantánea de una cuenta, o vacío si no tiene
# ninguna, o __ILEGIBLE__ si no se pudo saber.
#
# Se llama con `json` EXPLÍCITO: el formato no se valida en HestiaCP y uno
# desconocido devuelve vacío con código 0. Y una salida vacía NO se toma por
# «no hay copias» sin más: solo se afirma eso si la orden respondió algo que
# parece JSON. En cualquier otro caso, __ILEGIBLE__.
bc_hestia_ultima_instantanea() {
  local u="$1" salida
  salida="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-user-backups-restic $(printf '%q' "$u") json" 2>/dev/null || true)"
  [[ -n "$salida" ]] || { echo "__ILEGIBLE__"; return 0; }
  [[ "$salida" == *"{"* || "$salida" == *"["* ]] || { echo "__ILEGIBLE__"; return 0; }

  # La fecha de cada instantánea viene como "time": "2026-09-24T03:00:00...".
  # La más reciente se elige por INSTANTE, no ordenando texto: con husos
  # distintos el orden alfabético elige mal (ver bc_hestia_fecha_mas_reciente).
  local fechas
  fechas="$(grep -oE '"time"[[:space:]]*:[[:space:]]*"[^"]+"' <<<"$salida" \
            | sed 's/.*"\([^"]*\)"$/\1/')"
  printf '%s\n' "$(bc_hestia_fecha_mas_reciente "$fechas")"
}

# Pinta un veredicto "NIVEL<TAB>mensaje" y suma al contador que corresponda.
# $3 y $4 son NOMBRES de variable (se actualizan por referencia).
bc_hestia_pintar_veredicto() {
  # Cinco argumentos, los cinco OBLIGATORIOS. El de los ciegos lo era «si te
  # apetece» y eso perdía información en silencio: un veredicto CIEGO pintado
  # por un llamador que se dejó el quinto argumento no lo contaba NADIE, y el
  # resumen decía «0 datos sin leer» de un diagnóstico ciego. Quien no quiera
  # contarlos aquí —porque los cuenta él, con más detalle— lo dice pasando una
  # variable llamada `sin_contar`, que se ve al leer la llamada.
  if (( $# < 5 )); then
    bc_die "bc_hestia_pintar_veredicto necesita 5 argumentos (etiqueta, veredicto, y los contadores de fallos, avisos y ciegos); recibió $#."
  fi
  local etiqueta="$1" veredicto="$2" n_fallos="$3" n_avisos="$4" n_ciegos="$5"
  local nivel mensaje
  nivel="${veredicto%%$'\t'*}"
  mensaje="${veredicto#*$'\t'}"
  case "$nivel" in
    FALLO) bc_err  "$etiqueta: $mensaje"; printf -v "$n_fallos" '%s' "$(( ${!n_fallos} + 1 ))" ;;
    AVISO) bc_warn "$etiqueta: $mensaje"; printf -v "$n_avisos" '%s' "$(( ${!n_avisos} + 1 ))" ;;
    # CIEGO se pinta como un aviso —al usuario el nombre interno le da igual—
    # pero NO se cuenta como tal: un aviso es algo que se miró y no gusta; una
    # ceguera es algo que no se pudo saber, y sumarlas deja al usuario creyendo
    # que el diagnóstico fue completo.
    #
    # El contador `sin_contar` existe y se incrementa; simplemente no lo mira
    # nadie. Quien lo pasa es porque cuenta él con más detalle: el veredicto de
    # una cuenta puede tapar hasta tres datos ilegibles, y el resumen cuenta por
    # dato, no por veredicto. Sumarlo aquí además sería contarlo dos veces.
    CIEGO) bc_warn "$etiqueta: $mensaje"; printf -v "$n_ciegos" '%s' "$(( ${!n_ciegos} + 1 ))" ;;
    *)     bc_ok   "$etiqueta: $mensaje" ;;
  esac
}

# =============================================================================
# Configurar el remoto de rclone
# =============================================================================
# Se escribe la sección directamente en rclone.conf en lugar de lanzar
# `rclone config`, que es interactivo y no se puede guionizar. El resultado es
# idéntico y además es reproducible.
# -----------------------------------------------------------------------------
# rclone tiene que estar en el servidor ANTES de nada
# -----------------------------------------------------------------------------
# Comprobado leyendo v-add-backup-host-restic de HestiaCP 1.10.4:
#
#   - restic NO es problema: si falta, la propia orden hace `apt install restic`
#     y luego `restic self-update`.
#   - rclone SÍ: HestiaCP no lo instala. Y con un repositorio «rclone:...» la
#     orden ejecuta `rclone lsd` y aborta con «Rclone repository does not exist»
#     si no puede listarlo. Sin rclone, todo el montaje se para ahí.
#
# En un servidor recién instalado rclone no viene. Esto lo detecta y lo instala,
# en vez de dejar que falle tres pasos más adelante con un error que no señala
# la causa.
bc_hestia_requiere_rclone() {
  local version
  version="$(bc_hestia_read "rclone version 2>/dev/null | head -1" || true)"
  if [[ -n "$version" ]]; then
    bc_ok "rclone presente en el servidor: $version"
    return 0
  fi

  bc_warn "rclone NO está instalado en el servidor."
  bc_log  "HestiaCP instala restic por su cuenta, pero rclone no. Sin él no se"
  bc_log  "puede llegar al almacenamiento S3, y el registro del host fallaría"
  bc_log  "con «Rclone repository does not exist», que no dice la causa real."

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_log "Simulación (--dry-run): no se instala nada."
    return 1
  fi
  bc_confirm "¿Instalarlo ahora con apt?" y || {
    bc_err "sin rclone no se puede continuar."
    BC_DELIBERATE_EXIT=1
    return 1
  }

  bc_log "Instalando rclone (apt-get install rclone)..."
  bc_hestia_root "DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
                  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rclone" \
    || { bc_err "no se pudo instalar rclone."; BC_DELIBERATE_EXIT=1; return 1; }

  version="$(bc_hestia_read "rclone version 2>/dev/null | head -1" || true)"
  [[ -n "$version" ]] || { bc_err "rclone sigue sin responder tras instalarlo."; BC_DELIBERATE_EXIT=1; return 1; }
  bc_ok "rclone instalado: $version"
}

bc_hestia_rclone() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local nombre="${BC_OPT_RC_NAME:-}" tipo="${BC_OPT_RC_TYPE:-}"
  local key="${BC_OPT_RC_KEY:-}" secret="${BC_OPT_RC_SECRET:-}"
  local endpoint="${BC_OPT_RC_ENDPOINT:-}" region="${BC_OPT_RC_REGION:-}"

  # Con BC_OPT_RC_NAME ya puesto (lo hace la interfaz web) no se pregunta nada
  if [[ -z "$nombre" ]] && bc_can_prompt; then
    bc_section "Nuevo remoto de rclone"
    nombre="$(bc_ask "Nombre del remoto" "almacenamiento")"
    tipo="$(bc_ask "Tipo: s3 (Mega S4, compatible S3) o local" "s3")"
    if [[ "$tipo" == "s3" ]]; then
      key="$(bc_ask "Access key ID")"
      secret="$(bc_ask_secret "Secret access key")"
      endpoint="$(bc_ask "Endpoint S3 (obligatorio: sin él rclone hablaría con Amazon)")"
      region="$(bc_ask "Región (vacío si no aplica)" "")"
    fi
  fi

  bc_hestia_requiere_rclone || return 1

  [[ -n "$nombre" ]] || bc_die "hace falta el nombre del remoto."
  [[ "$nombre" =~ ^[A-Za-z0-9._-]+$ ]] || bc_die "nombre de remoto no válido."
  tipo="${tipo:-s3}"

  local seccion
  if [[ "$tipo" == "local" ]]; then
    seccion="[$nombre]
type = local
"
  else
    [[ -n "$key" && -n "$secret" ]] || bc_die "hacen falta access key y secret."
    [[ -n "$endpoint" ]] || bc_die "hace falta el endpoint: Mega S4 no es Amazon, y sin él rclone iría a AWS."
    seccion="[$nombre]
type = s3
provider = Other
env_auth = false
access_key_id = $key
secret_access_key = $secret
endpoint = $endpoint
$( [[ -n "$region" ]] && echo "region = $region" )acl = private
"
  fi

  bc_log "Se configurará el remoto '$nombre' (tipo $tipo) en $BC_HESTIA_RCLONE_CONF"
  [[ "$tipo" == "s3" ]] && bc_log "Endpoint: $endpoint"

  # --- Lo que hay ahora ------------------------------------------------------
  # Del archivo NO se lee el contenido: lleva claves en claro. Se le pide al
  # servidor solo la lista de secciones y sus tipos, que es todo lo que hace
  # falta para decidir. Así las credenciales no salen de ahí ni por error.
  local lectura; lectura="grep -E '^\[|^[[:space:]]*type[[:space:]]*=' $(printf '%q' "$BC_HESTIA_RCLONE_CONF")"
  local antes
  if ! antes="$(bc_hestia_leer_texto "$lectura")"; then
    bc_err "no se pudo leer $BC_HESTIA_RCLONE_CONF: NO se ha escrito nada."
    bc_log  "Sin saber qué remotos hay, escribir podría dejar fuera alguno."
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  local nombres_antes; nombres_antes="$(bc_hestia_nombres_de "$antes")"
  if [[ -n "$nombres_antes" ]]; then
    bc_log "Remotos que ya hay:"
    bc_hestia_remotos_de "$antes" | sed 's/^/        /'
  else
    bc_log "No hay ningún remoto configurado todavía."
  fi

  # --- ¿Se va a pisar uno que ya existe? ------------------------------------
  # Sustituir un remoto borra sus credenciales actuales, que pueden ser la
  # única forma de llegar a copias que ya existen. A partir de aquí solo
  # estarán en la copia fechada.
  local tipo_actual; tipo_actual="$(bc_hestia_tipo_de "$antes" "$nombre")"
  if grep -qxF "$nombre" <<<"$nombres_antes"; then
    echo
    bc_err "El remoto '$nombre' YA EXISTE (tipo ${tipo_actual:-desconocido}) y se va a SUSTITUIR."
    bc_log  "Sus credenciales actuales dejarán de estar en el servidor: a partir de"
    bc_log  "ahora solo estarán en la copia fechada que se deja aquí al lado. Si hay"
    bc_log  "copias hechas a través de ese remoto, compruébalo antes de seguir."
    if [[ "${BC_ASSUME_YES:-0}" == "1" ]]; then
      bc_err "NO se escribe nada. Con --yes esta orden no pisa un remoto que ya existe."
      bc_log  "Bórralo a propósito o usa otro nombre."
      BC_DELIBERATE_EXIT=1
      return 1
    fi
    bc_confirm "¿Sustituir el remoto '$nombre'?" n \
      || { bc_log "Cancelado."; return 0; }
  fi

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    echo
    bc_step "Simulación (--dry-run): esto es lo que PASARÍA, no lo que ha pasado."
    if [[ -n "$tipo_actual" ]]; then
      bc_log "El remoto '$nombre' pasaría de tipo '$tipo_actual' a '$tipo'."
    else
      bc_log "Se añadiría el remoto '$nombre' (tipo $tipo)."
    fi
    bc_log "Los demás remotos se conservarían, y se dejaría antes una copia fechada."
    bc_ok "No se ha escrito nada, y no se ha guardado ningún informe."
    return 0
  fi
  bc_confirm "¿Escribirlo en el servidor?" y || { bc_log "Cancelado."; return 0; }

  bc_informe_abrir "Configurar el acceso al almacenamiento" "${DEPLOY_HOST:-este servidor}"
  # Del archivo solo entran NOMBRES y TIPOS. Ninguna credencial, en ningún caso.
  bc_informe_dato "Remotos antes" "$(bc_hestia_remotos_de "$antes" | tr '\t' ' ' | tr '\n' ' ')" ""
  bc_informe_dato "Remoto pedido" "" "$nombre (tipo $tipo)"

  # --- La copia a la que volver ---------------------------------------------
  local copia=""
  if ! copia="$(bc_hestia_copia_fechada "$BC_HESTIA_RCLONE_CONF")"; then
    bc_err "no se pudo copiar $BC_HESTIA_RCLONE_CONF. NO se ha escrito nada."
    bc_log  "Nadie más gestiona ese archivo: si se estropea, no hay quien lo"
    bc_log  "reconstruya salvo un rescate. Sin copia no se toca."
    bc_informe_paso "Copia de seguridad" FALLO "no se pudo copiar el archivo"
    bc_informe_cerrar "FALLO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  if [[ -n "$copia" ]]; then
    bc_ok "Copia de la configuración anterior: $copia"
    bc_informe_copia "$BC_HESTIA_RCLONE_CONF" "$copia"
    bc_informe_deshacer "cp -p $copia $BC_HESTIA_RCLONE_CONF && chmod 600 $BC_HESTIA_RCLONE_CONF"
  else
    bc_log "No había configuración previa que copiar."
    bc_informe_deshacer "rm -f $BC_HESTIA_RCLONE_CONF   # no había configuración previa"
  fi

  # --- Escribir -------------------------------------------------------------
  # Las credenciales van por la ENTRADA ESTÁNDAR, nunca en la línea de órdenes:
  # ahí las vería cualquier otro usuario del servidor con `ps`. La primitiva
  # las lleva por su sexto argumento.
  local conf_esc; conf_esc="$(printf '%q' "$BC_HESTIA_RCLONE_CONF")"
  local orden_escritura="
    umask 077
    mkdir -p \"\$(dirname $conf_esc)\"
    touch $conf_esc
    nueva=\$(cat)
    awk -v n='[$nombre]' '
      \$0 == n { saltar=1; next }
      /^\[/    { saltar=0 }
      !saltar  { print }
    ' $conf_esc > $conf_esc.tmp 2>/dev/null || true
    printf '%s\n' \"\$nueva\" >> $conf_esc.tmp
    mv $conf_esc.tmp $conf_esc
    chmod 600 $conf_esc
  "
  BC_HESTIA_RC_NOMBRE="$nombre"; BC_HESTIA_RC_TIPO="$tipo"
  local datos
  datos="$(bc_hestia_escribir_y_confirmar "Escribir el remoto" "$orden_escritura" \
      "$lectura" bc_hestia_remoto_ya_estaba bc_hestia_remoto_se_hizo "$seccion")"
  local rc; rc="$(bc_hestia_dato_de "$datos" codigo)"
  bc_informe_dato "Código de la orden (dato, no prueba)" "" "${rc:-0}"

  # --- Releer y juzgar ------------------------------------------------------
  # La primitiva ya releyó, pero lo que devuelve es un estado general. Lo que
  # hay que decir aquí es MÁS preciso —quedó vacío, falta un remoto, el tipo no
  # es el pedido— y cada caso lleva su propia salida, así que se vuelve a mirar
  # el después que ella trajo.
  local despues
  despues="$(bc_hestia_restaurar_saltos "$(bc_hestia_dato_de "$datos" despues)")"
  if [[ "$(bc_hestia_dato_de "$datos" estado)" == "CIEGO" ]]; then
    bc_err "no se pudo leer $BC_HESTIA_RCLONE_CONF: NO se ha escrito nada."
    bc_informe_paso "Escribir el remoto" CIEGO "no se pudo leer el estado de partida"
    bc_informe_cerrar "CIEGO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  if [[ "$(bc_hestia_dato_de "$datos" estado)" == "ESCRITO_SIN_COMPROBAR" ]]; then
    bc_err "SE ESCRIBIÓ y no se pudo volver a leer $BC_HESTIA_RCLONE_CONF."
    bc_log  "No se sabe cómo quedó. La copia anterior está en: ${copia:-<no había>}"
    bc_informe_paso "Escribir el remoto" ESCRITO_SIN_COMPROBAR "se escribió y no se pudo leer"
    bc_informe_cerrar "ESCRITO_SIN_COMPROBAR" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  bc_informe_dato "Remotos después" "" "$(bc_hestia_remotos_de "$despues" | tr '\t' ' ' | tr '\n' ' ')"

  # T23: el archivo podía quedar VACÍO mientras la orden decía «escrito». Eso
  # no es «no se pudo leer»: es que se acaba de dejar al servidor sin forma de
  # llegar a su almacenamiento, y tiene que sonar como lo que es.
  if [[ -z "$(bc_hestia_nombres_de "$despues")" ]]; then
    bc_err "EL ARCHIVO HA QUEDADO VACÍO. Este servidor ya no sabe llegar a ningún"
    bc_err "almacenamiento, y los respaldos de esta noche NO se harán."
    bc_log  "Recupéralo AHORA desde la copia:"
    bc_log  "    cp -p ${copia:-<no había copia>} $BC_HESTIA_RCLONE_CONF"
    bc_informe_paso "Escribir el remoto" FALLO "el archivo quedó vacío"
    bc_informe_cerrar "FALLO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  local perdidos; perdidos="$(bc_hestia_remotos_perdidos "$antes" "$despues")"
  if [[ -n "$perdidos" ]]; then
    bc_err "HAN DESAPARECIDO REMOTOS QUE ESTABAN: $(tr '\n' ' ' <<<"$perdidos")"
    bc_log  "Un remoto perdido es un almacenamiento al que ya no se llega, y eso no"
    bc_log  "se descubre hasta el día que hace falta. Recupéralo desde: ${copia:-<no había copia>}"
    bc_informe_paso "Escribir el remoto" FALLO "desaparecieron remotos: $(tr '\n' ' ' <<<"$perdidos")"
    bc_informe_cerrar "FALLO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  local tipo_final; tipo_final="$(bc_hestia_tipo_de "$despues" "$nombre")"
  if [[ "$tipo_final" != "$tipo" ]]; then
    bc_err "El remoto '$nombre' no quedó como se pidió: se pidió tipo '$tipo' y hay"
    bc_err "'${tipo_final:-ninguno}'."
    bc_log  "La copia anterior está en: ${copia:-<no había>}"
    bc_informe_paso "Escribir el remoto" SIN_CONFIRMAR "se pidió '$tipo' y quedó '${tipo_final:-ninguno}'"
    bc_informe_cerrar "SIN_CONFIRMAR" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  bc_ok "Remoto '$nombre' escrito, y comprobado leyendo la configuración de vuelta."
  bc_informe_paso "Escribir el remoto" HECHO "'$nombre' (tipo $tipo), y los demás siguen"

  # --- ¿Responde? -----------------------------------------------------------
  # Un remoto escrito que no responde es una configuración inútil, y es mejor
  # saberlo ahora que la noche del primer respaldo.
  bc_log "Comprobando que el remoto responde..."
  local vivo; vivo="$(bc_hestia_sondear "rclone lsd $(printf '%q' "$nombre:") >/dev/null 2>&1")"
  case "$vivo" in
    1) bc_ok "El remoto responde."
       bc_informe_paso "El remoto responde" HECHO "responde"
       bc_informe_cerrar "HECHO" >/dev/null
       return 0 ;;
    0) bc_err "El remoto quedó escrito, pero NO responde."
       bc_log  "La configuración está bien puesta y aun así no se llega al"
       bc_log  "almacenamiento: revisa las credenciales, el endpoint y que el"
       bc_log  "bucket exista en tu proveedor. Sin esto, los respaldos fallarán."
       bc_informe_paso "El remoto responde" FALLO "quedó escrito pero no responde"
       bc_informe_cerrar "FALLO" >/dev/null
       BC_DELIBERATE_EXIT=1
       return 1 ;;
    *) bc_err "El remoto quedó escrito, pero NO se pudo comprobar si responde."
       bc_informe_paso "El remoto responde" CIEGO "no se pudo comprobar"
       bc_informe_cerrar "CIEGO" >/dev/null
       BC_DELIBERATE_EXIT=1
       return 1 ;;
  esac
}

# Texto de la fila "Anuales" (T26): v-backup-user-restic solo añade
# --keep-yearly si KEEP_YEARLY >= 0 (HestiaCP 1.10.4); con -1 no hay tramo
# anual, así que nunca se dice "ilimitadas". Usada por la tabla de registro
# (bc_hestia_restic) y por la de estado (más arriba, con $2 para que siga
# mostrando el "(-1)" que ya llevaba: la regla vive en un solo sitio, el
# formato puede seguir siendo distinto en cada tabla). Función pura (sin
# ssh, sin efectos) para poder probarla sin conectar a nada.
bc_hestia_texto_anuales_registro() {
  local y="${1:-}" sufijo="${2:-}"
  [[ "$y" == "-1" ]] && echo "sin regla anual${sufijo}" || echo "$y"
}

# -----------------------------------------------------------------------------
# Leer lo que hay en conf/restic.conf, y juzgarlo
# -----------------------------------------------------------------------------
# Todas PURAS: reciben el texto del archivo y no tocan nada. Lo que las llama es
# bc_hestia_escribir_y_confirmar, que les da el «antes» y el «después».
#
# La configuración de Restic del panel es UNA sola para todo el HestiaCP, con
# seis claves: REPO, SNAPSHOTS, KEEP_DAILY, KEEP_WEEKLY, KEEP_MONTHLY y
# KEEP_YEARLY. Las escribe enteras v-add-backup-host-restic.

# Saca el valor de una clave del texto de restic.conf. Vacío si no está.
bc_hestia_conf_valor() {
  local conf="${1:-}" clave="${2:-}"
  sed -n "s/^${clave}='\(.*\)'$/\1/p" <<<"$conf" | sed -n '1p'
}

# La retención, en una sola línea comparable. No es para enseñar: es para
# comparar lo pedido con lo leído sin depender del ORDEN de las líneas.
bc_hestia_conf_retencion() {
  local conf="${1:-}" clave valor salida="" alguno=0
  for clave in SNAPSHOTS KEEP_DAILY KEEP_WEEKLY KEEP_MONTHLY KEEP_YEARLY; do
    valor="$(bc_hestia_conf_valor "$conf" "$clave")"
    [[ -n "$valor" ]] && alguno=1
    salida+="${salida:+ }$clave=$valor"
  done
  # Sin ni un solo valor, lo que hay no es «una retención con los campos
  # vacíos»: es que no hay retención. Devolver la plantilla vacía llenaría el
  # informe de un «SNAPSHOTS= KEEP_DAILY= …» que parece un dato leído.
  (( alguno )) || return 0
  printf '%s' "$salida"
}

# La misma línea, a partir de los valores que se van a pedir.
bc_hestia_retencion_pedida() {
  printf 'SNAPSHOTS=%s KEEP_DAILY=%s KEEP_WEEKLY=%s KEEP_MONTHLY=%s KEEP_YEARLY=%s' \
    "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
}

# Lo que se pide. Los jueces reciben solo el texto leído
# (bc_hestia_escribir_y_confirmar no les pasa nada más), así que lo pedido
# viaja por aquí: explícito y greppable, en vez de fiarse del alcance dinámico
# de bash para leer las variables de quien llama.
BC_HESTIA_PEDIDO_REPO=""
BC_HESTIA_PEDIDO_RETENCION=""

# ¿Este texto de restic.conf tiene EXACTAMENTE lo que se pide?
#
# Un archivo que NO existe se lee como vacío, y eso no es «ya estaba»: es un
# servidor sin configurar, que es el caso normal la primera vez. Tampoco es un
# error — el error sería no haber podido leerlo, y de eso se encarga el
# centinela de bc_hestia_leer_texto, no esta función.
#
# La retención se compara LITERAL, valor a valor. Si HestiaCP normalizara
# alguno al escribirlo (por ejemplo el -1 de «sin regla anual»), esto daría
# SIN_CONFIRMAR de más — molesto, pero nunca un HECHO de menos. La dirección
# está elegida a propósito: un falso «no lo puedo confirmar» manda a mirar; un
# falso «hecho» deja a alguien creyendo que su servidor está configurado.
bc_hestia_restic_cumple() {
  local conf="${1:-}"
  [[ -n "$conf" ]] || return 1
  [[ "$(bc_hestia_conf_valor "$conf" REPO)" == "$BC_HESTIA_PEDIDO_REPO" ]] || return 1
  [[ "$(bc_hestia_conf_retencion "$conf")" == "$BC_HESTIA_PEDIDO_RETENCION" ]] || return 1
  return 0
}

# Los dos jueces. Cada uno mira lo suyo: el primero el estado de partida, el
# segundo en qué estado quedó el servidor.
bc_hestia_restic_ya_estaba() { bc_hestia_restic_cumple "${1:-}"; }
bc_hestia_restic_se_hizo()   { bc_hestia_restic_cumple "${2:-}"; }

# -----------------------------------------------------------------------------
# La copia a la que volver
# -----------------------------------------------------------------------------
# Deja una copia fechada de un archivo del servidor, junto al original y con sus
# permisos. Imprime la ruta de la copia y devuelve 0; devuelve 1 si no se pudo
# hacer, o si el original no existe y no hay nada que copiar (eso último se
# distingue por la salida vacía).
#
# Un «cómo deshacerlo» que no tiene a qué volver no es una reversión, es una
# frase. Por eso quien llame a esto tiene que tratar el fallo como motivo para
# NO escribir: sin poder volver atrás no se toca un servidor de producción.
#
# `cp -p` conserva permisos y fechas. Se copia, NO se mueve: mover dejaría al
# servidor sin el archivo durante el hueco entre las dos operaciones, y hay un
# respaldo nocturno que lo lee.
bc_hestia_copia_fechada() {
  local ruta="${1:-}" marca copia
  marca="$(date '+%Y%m%d-%H%M%S')"
  copia="${ruta}.${marca}.bak"
  local guion
  guion="if [ ! -e $(printf '%q' "$ruta") ]; then printf 'BC_SIN_ORIGINAL\n'; exit 0; fi; \
cp -p $(printf '%q' "$ruta") $(printf '%q' "$copia") && [ -e $(printf '%q' "$copia") ] \
&& printf 'BC_COPIA_OK\n'"
  local salida
  salida="$( { bc_hestia_root "bash -c $(printf '%q' "$guion")" 2>/dev/null || true; } | tr -d '\r' )"
  case "$salida" in
    *BC_SIN_ORIGINAL*) return 0 ;;          # no había nada que copiar
    *BC_COPIA_OK*)     printf '%s' "$copia"; return 0 ;;
    *)                 return 1 ;;          # se intentó y no se pudo
  esac
}

# Comprueba un repositorio ANTES de registrarlo en HestiaCP (T24, endurecida
# tras la revisión de #038: H1 — $repo llegaba sin validar hasta una orden
# ejecutada como root; H2 — antes solo se miraba si empezaba por "rclone:",
# así que una ruta local reproducía el incidente sin que nada lo dijera).
# $1 repositorio tal como se registrará: rclone:remoto:ruta, una ruta local
#    absoluta (/ruta), u otro esquema de restic (sftp:, s3:, b2:…)
# $2 tipo del remoto de rclone (local, alias, s3, …), '?' si es de rclone y no
#    se pudo leer su tipo, o vacío si no hay tipo que mirar
# Devuelve 0 si es aceptable, 1 tras explicar por qué no. Función pura: no
# conecta a nada, no lee ni escribe, solo mira el texto que se le pasa.
bc_hestia_validar_repo() {
  local repo="${1:-}" tipo="${2:-}"
  tipo="${tipo,,}"  # comparación en minúsculas: H4, "Local" pasaba

  # --- Forma y juego de caracteres, antes de mirar nada más (H1, H9) -------
  # El mismo criterio que ya aplica la web (web/server.py): sin esto, una
  # comilla simple en $repo llega intacta hasta una orden que se ejecuta
  # como root (bc_hestia_v "v-add-backup-host-restic '$repo' ...").
  # Qué forma tiene $repo: de eso depende qué comprobaciones tienen sentido
  # más abajo. El tipo del remoto SOLO se puede consultar para "rclone"
  # (rclone config show); en "otro" (sftp:, s3:, b2:…) lo que sigue al
  # esquema no es necesariamente una ruta del sistema de archivos —puede ser
  # host:puerto/bucket o una URL entera—, así que las reglas pensadas para
  # rutas de archivo (tipo de remoto, "//") no se le aplican (revisión de
  # #041: rechazaban repositorios válidos de restic con un mensaje que
  # hablaba de otra cosa).
  local esquema ruta rem=""
  if [[ "$repo" == rclone:* ]]; then
    esquema=rclone
    if [[ ! "$repo" =~ ^rclone:[A-Za-z0-9._-]+:[A-Za-z0-9._/-]*$ ]]; then
      bc_err "repositorio no válido: '$repo'."
      bc_log  "Con rclone:, el nombre del remoto y la ruta solo admiten letras,"
      bc_log  "números, '.', '_', '-' y '/'. Nada de comillas, espacios ni ';'."
      return 1
    fi
    local resto="${repo#rclone:}"
    rem="${resto%%:*}"
    ruta="${resto#*:}"
  elif [[ "$repo" == /* ]]; then
    esquema=local
    if [[ ! "$repo" =~ ^[A-Za-z0-9._/-]+$ ]]; then
      bc_err "repositorio no válido: '$repo'."
      bc_log  "Una ruta local solo admite letras, números, '.', '_', '-' y '/'."
      return 1
    fi
    ruta="$repo"
  else
    esquema=otro
    if [[ ! "$repo" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
      bc_err "repositorio no válido: '$repo'."
      bc_log  "Solo se admiten letras, números, '.', '_', '-', ':' y '/'."
      return 1
    fi
    ruta="${repo##*:}"
  fi

  if [[ -z "$ruta" ]]; then
    bc_err "falta la ruta${rem:+ dentro del remoto '$rem'}."
    return 1
  fi

  # --- No se intenta normalizar: una ruta con ".." se rechaza tal cual (H8)
  # — no se puede resolver sin tocar el servidor, y una normalización a
  # medias es peor que un rechazo. Esto vale para los tres esquemas.
  if [[ "$ruta" == *..* ]]; then
    bc_err "la ruta '$ruta' no puede llevar '..'. Escríbela limpia."
    return 1
  fi

  # "//" solo se rechaza en rclone y en una ruta local: ahí es siempre parte
  # del propio sistema de archivos. En "otro" esquema puede ser el "//" de
  # una URL (s3:https://s3.example.org/bucket) y no dice nada malo (#041).
  if [[ "$esquema" != "otro" && "$ruta" == *//* ]]; then
    bc_err "la ruta '$ruta' no puede llevar '//'. Escríbela limpia."
    return 1
  fi

  # --- Dentro de una web: la ruta exacta o con algo detrás (H8) ------------
  if [[ "$ruta" == /home/*/web || "$ruta" == /home/*/web/* ]]; then
    bc_err "la ruta '$ruta' está DENTRO del directorio de un sitio web."
    bc_log  "Quedaría accesible desde internet. Usa una ruta fuera de /home/*/web/."
    return 1
  fi

  # --- Según el tipo de remoto (H4: local vs envolvente vs desconocido) ---
  # Solo para "rclone": el tipo únicamente se puede consultar (rclone config
  # show) para un remoto de rclone. En "otro" esquema no hay tipo que
  # consultar y estas reglas no aplican — lo que sigue al esquema no es
  # necesariamente una ruta del sistema de archivos (#041).
  if [[ "$esquema" != "rclone" ]]; then
    return 0
  fi

  local envolvente=0
  case "$tipo" in
    alias|crypt|union|combine|chunker|compress) envolvente=1 ;;
  esac

  if [[ "$tipo" == "local" ]] && [[ "$ruta" != /* ]]; then
    bc_err "la ruta '$ruta'${rem:+ del remoto '$rem'} (tipo local) es RELATIVA."
    bc_log  "rclone la resuelve desde el directorio de trabajo de quien ejecuta el"
    bc_log  "respaldo — así es como un repositorio acabó dentro de un sitio web"
    bc_log  "servido por internet (T24). Escribe una ruta ABSOLUTA, por ejemplo:"
    bc_log  "/IncrementalBackups"
    return 1
  fi

  if (( envolvente )); then
    if [[ "$ruta" != /* ]]; then
      bc_err "la ruta '$ruta'${rem:+ del remoto '$rem'} (tipo $tipo) es RELATIVA."
      bc_log  "Un remoto de este tipo envuelve a OTRO remoto: rclone también puede"
      bc_log  "resolverla desde el directorio de trabajo. Escribe una ruta ABSOLUTA."
      return 1
    fi
    bc_warn "el remoto${rem:+ '$rem'} es de tipo $tipo: envuelve a OTRO remoto."
    bc_warn "Una ruta absoluta NO garantiza nada aquí — la raíz del remoto real es"
    bc_warn "la que manda, y desde aquí no se puede saber a dónde apunta."
    bc_warn "Comprueba tú mismo que su destino no está dentro de una web."
    return 0
  fi

  # El tipo VACÍO y el tipo '?' NO son lo mismo, y confundirlos convierte un
  # fallo de lectura en un aprobado:
  #   ""   no hay tipo que mirar (el repositorio no es de rclone, no aplica).
  #   '?'  es de rclone y NO se pudo leer su tipo.
  # Antes los dos caían aquí, y con una ruta absoluta la función devolvía 0 sin
  # más: el diagnóstico acababa diciendo «la ruta registrada no cae dentro de
  # ninguna web». Eso es afirmar lo que no se miró. Si ese remoto fuera
  # envolvente (alias, crypt, union…), la ruta absoluta NO garantiza nada —la
  # raíz del remoto real es la que manda—, y por ahí fue exactamente como un
  # repositorio acabó dentro de un sitio web servido por internet (T24).
  if [[ "$tipo" == "?" ]]; then
    if [[ "$ruta" != /* ]]; then
      bc_err "no se pudo determinar el tipo del remoto${rem:+ '$rem'}."
      bc_log  "No se registra a ciegas una ruta relativa: escríbela absoluta, o"
      bc_log  "comprueba que el remoto existe en el servidor."
      return 1
    fi
    bc_warn "no se pudo leer el tipo del remoto${rem:+ '$rem'}: desde aquí no se"
    bc_warn "puede saber a dónde apunta. Si fuera de tipo envolvente (alias, crypt,"
    bc_warn "union…), una ruta absoluta NO bastaría."
    bc_warn "Comprueba tú mismo que su destino no está dentro de una web."
    return 0
  fi

  if [[ -z "$tipo" ]] && [[ "$ruta" != /* ]]; then
    bc_err "no se pudo determinar el tipo del remoto${rem:+ '$rem'}."
    bc_log  "No se registra a ciegas una ruta relativa: escríbela absoluta, o"
    bc_log  "comprueba que el remoto existe en el servidor."
    return 1
  fi

  return 0
}

# =============================================================================
# Registrar el host de respaldo en HestiaCP
# =============================================================================
bc_hestia_restic() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local repo="${BC_OPT_REPO:-}"
  local snaps="${BC_OPT_SNAPSHOTS:-30}" d="${BC_OPT_DAILY:-8}"
  local w="${BC_OPT_WEEKLY:-5}" m="${BC_OPT_MONTHLY:-3}" y="${BC_OPT_YEARLY:--1}"

  if [[ -z "$repo" ]] && bc_can_prompt; then
    bc_section "Host de respaldo Restic"
    local rem ruta
    rem="$(bc_ask "Remoto de rclone" "almacenamiento")"
    ruta="$(bc_ask "Ruta dentro del remoto (absoluta si el remoto es local)" "/hestiacp")"
    repo="rclone:$rem:$ruta"
    bc_log "Política de retención (por defecto: 30 instantáneas, 8 diarias, 5 semanales, 3 mensuales, sin tramo anual)"
    snaps="$(bc_ask "Instantáneas totales" "30")"
    d="$(bc_ask "Diarias a conservar" "8")"
    w="$(bc_ask "Semanales" "5")"
    m="$(bc_ask "Mensuales" "3")"
    y="$(bc_ask "Anuales (-1 = sin tramo anual)" "-1")"
  fi
  [[ -n "$repo" ]] || bc_die "hace falta el repositorio."

  # T24/H1-H5 (revisión de #038): la validación TEXTUAL corre SIEMPRE, antes
  # de pintar nada y de pedir confirmación — es pura, no toca el servidor.
  # La consulta del TIPO del remoto sí toca el servidor (rclone config show),
  # así que se salta en --dry-run (H3: antes se ejecutaba —e incluso podía
  # instalar rclone por apt— antes de enseñar nada).
  local rem_nombre="" tipo_remoto=""
  if [[ "$repo" == rclone:* ]]; then
    rem_nombre="${repo#rclone:}"; rem_nombre="${rem_nombre%%:*}"
    if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
      # En ensayo el tipo se queda VACÍO, no en '?'. No es lo mismo: '?' quiere
      # decir «lo intenté y no pude», y avisaría de algo que aquí ni se
      # intentó. Eso sería ruido en una simulación que a propósito no toca el
      # servidor.
      bc_log "Simulación (--dry-run): no se comprueba el tipo del remoto en el servidor."
    else
      # El filtrado corre EN EL SERVIDOR (awk), no en local: "rclone config
      # show" imprime credenciales en claro, y así no cruzan el canal más de
      # lo necesario (H11). Sin "head" en la tubería LOCAL: con pipefail,
      # cortar antes de que el productor termine mata todo con SIGPIPE (H10,
      # mismo motivo que bc_gen_password en core.sh). Esta consulta ocurre
      # ANTES de que bc_hestia_validar_repo compruebe el juego de caracteres
      # de $repo (unas líneas más abajo): $rem_nombre se cita con printf %q
      # como defensa en profundidad (lib/ssh.sh:112), no porque se confíe en
      # que ya esté validado.
      tipo_remoto="$( { bc_hestia_root "rclone config show $(printf '%q' "$rem_nombre") 2>/dev/null \
          | awk '/^type[[:space:]]*=/{sub(/^type[[:space:]]*=[[:space:]]*/,\"\"); print; exit}'" \
          || true; } | tr -d '\r' )"
    fi
    # Con una ruta absoluta y el tipo sin leer, el registro sigue adelante,
    # pero avisando de que nadie ha comprobado a dónde apunta ese remoto. En
    # ensayo no avisa: ahí no se intentó leerlo.
    tipo_remoto="$(bc_hestia_tipo_leido "$tipo_remoto" "${BC_OPT_DRY:-0}")"
  fi
  bc_hestia_validar_repo "$repo" "$tipo_remoto" || { BC_DELIBERATE_EXIT=1; return 1; }

  bc_section "Registrar el host de respaldo"
  bc_log "Repositorio: $repo"
  {
    printf 'Instantáneas totales\t%s\n' "$snaps"
    printf 'Diarias\t%s\n' "$d"; printf 'Semanales\t%s\n' "$w"
    printf 'Mensuales\t%s\n' "$m"
    printf 'Anuales\t%s\n' "$(bc_hestia_texto_anuales_registro "$y")"
  } | bc_table | sed 's/^/        /'
  bc_warn "El PRIMER número es el total de instantáneas, no los días. Es el error"
  bc_warn "más común al configurar esto a mano."

  # Lo que se va a pedir, para los jueces y para el informe. Se compone aquí,
  # una sola vez, porque lo usan el ensayo y el registro de verdad.
  BC_HESTIA_PEDIDO_REPO="$repo"
  BC_HESTIA_PEDIDO_RETENCION="$(bc_hestia_retencion_pedida "$snaps" "$d" "$w" "$m" "$y")"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    # El ensayo produce un PLAN, no un informe: no se archiva nada en
    # <Perfil>/informes/. Un histórico lleno de cosas que no pasaron no sirve
    # para saber qué pasó.
    #
    # El estado de partida solo se lee AQUÍ. En el camino real lo lee
    # bc_hestia_escribir_y_confirmar, que necesita el «antes» y el «después»
    # de la MISMA lectura: leerlo también aquí sería una consulta de más al
    # servidor y, peor, dos «antes» distintos si algo cambiara entre medias.
    bc_step "Simulación (--dry-run): esto es lo que PASARÍA, no lo que ha pasado."
    local conf_antes=""
    if ! conf_antes="$(bc_hestia_leer_texto "cat $(printf '%q' "$HESTIA_CONF_RESTIC")")"; then
      bc_warn "No se pudo leer $HESTIA_CONF_RESTIC: no se puede decir qué cambiaría."
      BC_DELIBERATE_EXIT=1
      return 1
    fi
    bc_hestia_plan_restic "$conf_antes" "$repo" "$BC_HESTIA_PEDIDO_RETENCION"
    bc_ok "No se ha tocado nada, y no se ha guardado ningún informe."
    return 0
  fi

  bc_confirm "¿Registrarlo en HestiaCP?" y || { bc_log "Cancelado."; return 0; }

  # El informe se abre ANTES de comprobar el destino: un rechazo por ruta
  # inaccesible o por ruta compartida es INFORMACIÓN, no un no-suceso.
  # Responde a «¿por qué mi servidor no cambió el martes?», que es la mitad
  # del motivo por el que existe este archivo. No es como el ensayo: allí no
  # llegó a haber ni intento; aquí hubo intento y hubo una decisión.
  bc_informe_abrir "Registrar el host de respaldo" "${DEPLOY_HOST:-este servidor}"
  bc_informe_dato "Repositorio pedido" "" "$repo"
  bc_informe_dato "Retención pedida" "" "$BC_HESTIA_PEDIDO_RETENCION"

  if ! bc_hestia_restic_destino_usable "$repo"; then
    bc_informe_paso "Comprobar el destino" FALLO \
      "el destino no se puede usar; no se ha registrado nada"
    bc_informe_cerrar "FALLO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  # ---------------------------------------------------------------------------
  # Escribir, y COMPROBAR lo escrito
  # ---------------------------------------------------------------------------
  # Antes esto era `bc_hestia_v … || bc_die`: mataba la orden usando el código
  # de la propia orden como única prueba. Es exactamente lo que el ADR 0017
  # dice que no se puede hacer —HestiaCP registra éxitos que no ocurrieron— y
  # además impedía escribir el informe justo en el caso en que más falta hace.

  # La copia a la que volver, ANTES de tocar nada. Si no se puede hacer, no se
  # escribe: sin poder volver atrás no se toca un servidor de producción.
  local copia=""
  if ! copia="$(bc_hestia_copia_fechada "$HESTIA_CONF_RESTIC")"; then
    bc_err "no se pudo dejar una copia de $HESTIA_CONF_RESTIC. NO se ha registrado nada."
    bc_log  "Sin una copia a la que volver no se toca la configuración del panel."
    bc_log  "Comprueba el espacio libre y los permisos de $(dirname "$HESTIA_CONF_RESTIC")."
    bc_informe_paso "Copia de seguridad" FALLO "no se pudo copiar $HESTIA_CONF_RESTIC"
    bc_informe_cerrar "FALLO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  if [[ -n "$copia" ]]; then
    bc_ok "Copia de la configuración anterior: $copia"
    bc_informe_copia "$HESTIA_CONF_RESTIC" "$copia"
    bc_informe_deshacer "cp -p $copia $HESTIA_CONF_RESTIC"
  else
    bc_log "No había configuración previa que copiar: este servidor no tenía Restic registrado."
    bc_informe_deshacer "rm -f $HESTIA_CONF_RESTIC   # no había configuración previa"
  fi

  local orden_escritura="$HESTIA_DIR/bin/v-add-backup-host-restic $(printf '%q' "$repo") \
$(printf '%q' "$snaps") $(printf '%q' "$d") $(printf '%q' "$w") $(printf '%q' "$m") $(printf '%q' "$y")"
  bc_informe_orden "$orden_escritura"

  local datos
  datos="$(bc_hestia_escribir_y_confirmar "Registrar el host de respaldo" \
      "$orden_escritura" "cat $(printf '%q' "$HESTIA_CONF_RESTIC")" \
      bc_hestia_restic_ya_estaba bc_hestia_restic_se_hizo)"

  # Que el archivo haya quedado bien NO prueba que el servidor pueda respaldar.
  # v-add-backup-host-restic no comprueba el resultado de instalar ni de
  # actualizar restic: si eso falla, sigue de largo y escribe la configuración
  # igualmente (fuente 1.10.4). Es la misma familia de fallo que el del
  # respaldo incremental: dar por bueno lo que no se comprobó. Así que se
  # pregunta aparte, y es de solo lectura.
  #
  # Solo se pregunta si el registro salió bien: si no, es una consulta de más
  # a un servidor que justo ahora está teniendo problemas, y su respuesta no
  # cambiaría nada de lo que hay que decir.
  local restic_vivo="?"
  case "$(bc_hestia_dato_de "$datos" estado)" in
    HECHO|SIN_CAMBIO) restic_vivo="$(bc_hestia_comprobar_restic)" ;;
  esac

  local rc=0
  bc_hestia_informar_restic "$datos" "$repo" "$copia" "$restic_vivo" || rc=$?
  if (( rc != 0 )); then
    BC_DELIBERATE_EXIT=1
    return "$rc"
  fi

  # NO se inicializa nada aquí. La ruta registrada NO es un repositorio: HestiaCP
  # guarda un repositorio POR USUARIO en "${REPO%/}/<usuario>", cada uno con la
  # clave de ese usuario, y la orden de respaldo incremental ejecuta `restic
  # init` sobre él la primera vez que lo respalda (comprobado en HestiaCP
  # 1.10.4).
  #
  # La versión anterior hacía `restic init` sobre la ruta global: sin contraseña
  # fallaba, y el mensaje mandaba a hacer a mano algo que no hay que hacer. Con
  # contraseña, habría dejado un repositorio huérfano encima de los de los
  # usuarios.
  bc_log "Cada cuenta tendrá su propio repositorio en ${repo%/}/<usuario>."
  bc_log "HestiaCP los crea solo la primera vez que las respalde: tras activar el"
  bc_log "cron, al día siguiente deberían aparecer en «Configuración de Restic»."
  return 0
}

# -----------------------------------------------------------------------------
# ¿Se puede usar ese destino?
# -----------------------------------------------------------------------------
# Todo lo que hay que mirar ANTES de tocar nada. Va aparte porque el paso
# siguiente necesita engancharse en el mismo sitio, y porque una función que
# pregunta, valida, comprueba el destino, escribe e informa no la revisa nadie
# de verdad. Esta SOLO LEE. Devuelve 0 si se puede seguir.
# $1 repositorio pedido
bc_hestia_restic_destino_usable() {
  local repo="${1:-}"
  [[ "$repo" == rclone:* ]] || return 0   # una ruta local no se sondea aquí

  bc_hestia_requiere_rclone || return 1
  local ruta_rclone="${repo#rclone:}"

  # v-add-backup-host-restic ejecuta un listado sobre el repositorio y aborta
  # con «Rclone repository does not exist» si no puede verlo. Ese mensaje no
  # distingue entre las tres causas posibles, así que se comprueban aquí
  # antes, una por una, y se dice cuál es.
  bc_log "Comprobando que el destino existe y responde..."
  if ! bc_hestia_root "rclone lsd $(printf '%q' "$ruta_rclone")" >/dev/null 2>&1; then
    bc_err "no se puede listar '$ruta_rclone'. HestiaCP rechazará el registro."
    bc_log  "Las causas posibles, en orden:"
    bc_log  "  1. El remoto '${ruta_rclone%%:*}' no está configurado en el servidor."
    bc_log  "     Hazlo en el paso 1, «Configurar el remoto»."
    bc_log  "  2. El bucket no existe todavía en tu proveedor. Créalo en su panel:"
    bc_log  "     esto no lo puede hacer nadie desde aquí."
    bc_log  "  3. Las claves o el endpoint son incorrectos."
    bc_log  "Lo que respondió el servidor:"
    bc_hestia_root "rclone lsd $(printf '%q' "$ruta_rclone") 2>&1 | head -5" \
      | sed 's/^/        /' || true
    return 1
  fi
  bc_ok "El destino responde."

  # ---------------------------------------------------------------------------
  # ¿Esa ruta ya la usa otro servidor?
  # ---------------------------------------------------------------------------
  # Dentro de la ruta, HestiaCP guarda un repositorio por cuenta. Si ya hay
  # carpetas y NO es la ruta que este mismo servidor tiene registrada, lo
  # normal es que sean de otro servidor. Compartirla es destructivo: tras cada
  # respaldo cada uno aplica SU política de retención sobre el mismo sitio, y
  # las cuentas con el mismo nombre acabarían en el mismo repositorio. Con la
  # interfaz todo se confirma solo, así que aquí no se pregunta: se rechaza, y
  # solo se permite a propósito con --ruta-compartida.
  local ocupantes actual
  ocupantes="$( { bc_hestia_root "rclone lsd $(printf '%q' "$ruta_rclone") 2>/dev/null" || true; } \
                | awk '{print $NF}' | sed '/^$/d')"
  actual="$(bc_hestia_read "sed -n \"s/^REPO='\\(.*\\)'$/\\1/p\" '$HESTIA_CONF_RESTIC'" || true)"
  if [[ -n "$ocupantes" && "${actual%/}" != "${repo%/}" && "${BC_OPT_RUTA_COMPARTIDA:-0}" != "1" ]]; then
    bc_err "Esa ruta YA CONTIENE repositorios que este servidor no tiene registrados:"
    sed 's/^/          - /' <<<"$ocupantes" >&2
    bc_log "Si son de otro servidor, compartirla haría que la retención de uno"
    bc_log "borrara las copias del otro. Usa otro bucket u otra ruta."
    bc_log "Si de verdad es a propósito (este servidor continúa esos respaldos):"
    bc_log "    backupctl -p $BC_PROFILE hestia restic --repo '$repo' --ruta-compartida"
    return 1
  fi
  return 0
}

# -----------------------------------------------------------------------------
# El plan del ensayo: lo que PASARÍA
# -----------------------------------------------------------------------------
# Mismo contenido que el informe, pero en futuro y sin archivar nada. Pura.
# $1 restic.conf leído   $2 repositorio pedido   $3 retención pedida
bc_hestia_plan_restic() {
  local antes="${1:-}" repo="${2:-}" retencion="${3:-}"
  local repo_antes ret_antes
  repo_antes="$(bc_hestia_conf_valor "$antes" REPO)"
  ret_antes="$(bc_hestia_conf_retencion "$antes")"

  if [[ -z "$antes" ]]; then
    bc_log "Ahora mismo este servidor NO tiene ningún host de respaldo registrado."
    bc_log "Pasaría a:"
    bc_log "  Repositorio: $repo"
    bc_log "  Retención:   $retencion"
    return 0
  fi

  if [[ "$repo_antes" == "$repo" ]]; then
    bc_log "Repositorio: ya es '$repo'. No cambiaría."
  else
    bc_log "Repositorio: pasaría de '${repo_antes:-<ninguno>}' a '$repo'."
  fi
  if [[ "$ret_antes" == "$retencion" ]]; then
    bc_log "Retención:   ya es la pedida. No cambiaría."
  else
    bc_log "Retención:   pasaría de '$ret_antes' a '$retencion'."
  fi
  if [[ "$repo_antes" == "$repo" && "$ret_antes" == "$retencion" ]]; then
    bc_log "Es decir: no habría nada que cambiar."
  else
    bc_log "Se dejaría antes una copia fechada de $HESTIA_CONF_RESTIC."
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Traducir los datos de la escritura a algo que una persona pueda usar
# -----------------------------------------------------------------------------
# $1 los datos de bc_hestia_escribir_y_confirmar   $2 repositorio pedido
# $3 la copia fechada (vacío si no había nada que copiar)
#
# Devuelve 0 solo si el servidor quedó como se pidió. Lo que decide NO es el
# código de HestiaCP: es el estado que se leyó después.
# Saca un campo de los datos que devuelve bc_hestia_escribir_y_confirmar.
# $1 los datos   $2 el nombre del campo
bc_hestia_dato_de() {
  local datos="${1:-}" nombre="${2:-}" clave valor
  while IFS="$BC_HESTIA_SEP" read -r clave valor; do
    [[ "$clave" == "$nombre" ]] && { printf '%s' "$valor"; return 0; }
  done <<<"$datos"
  return 0
}

# ¿Responde restic en el servidor? 1 sí, 0 no, '?' no se pudo preguntar.
# Solo lectura: preguntar la versión no toca ningún repositorio ni necesita
# ninguna contraseña.
bc_hestia_comprobar_restic() {
  bc_hestia_sondear "command -v restic >/dev/null 2>&1 && restic version >/dev/null 2>&1"
}

bc_hestia_informar_restic() {
  local datos="${1:-}" repo="${2:-}" copia="${3:-}" restic_vivo="${4:-?}"
  local estado antes despues codigo salida
  estado="$(bc_hestia_dato_de "$datos" estado)"
  antes="$(bc_hestia_dato_de "$datos" antes)"
  despues="$(bc_hestia_dato_de "$datos" despues)"
  codigo="$(bc_hestia_dato_de "$datos" codigo)"
  salida="$(bc_hestia_dato_de "$datos" salida)"
  estado="${estado:-CIEGO}"

  # Los dos datos por separado, aunque la orden sea una sola: un «no lo puedo
  # confirmar» que no dice CUÁL de los dos no cuadró obliga a mirar a ciegas.
  local antes_txt despues_txt
  antes_txt="$(bc_hestia_restaurar_saltos "$antes")"
  despues_txt="$(bc_hestia_restaurar_saltos "$despues")"
  bc_informe_dato "Repositorio" \
    "$(bc_hestia_conf_valor "$antes_txt" REPO)" "$(bc_hestia_conf_valor "$despues_txt" REPO)"
  bc_informe_dato "Retención" \
    "$(bc_hestia_conf_retencion "$antes_txt")" "$(bc_hestia_conf_retencion "$despues_txt")"
  [[ -n "$salida" ]] && bc_informe_dato "Lo que respondió la orden" "" \
    "$(bc_hestia_restaurar_saltos "$salida")"
  [[ -n "$codigo" ]] && bc_informe_dato "Código de la orden (dato, no prueba)" "" "$codigo"

  local rc=0 mensaje=""
  case "$estado" in
    SIN_CAMBIO)
      bc_ok "No había nada que cambiar: ya estaba registrado exactamente así."
      mensaje="el servidor ya tenía este repositorio y esta retención" ;;
    HECHO)
      bc_ok "Host de respaldo registrado, y comprobado leyéndolo de vuelta."
      mensaje="registrado y confirmado releyendo la configuración" ;;
    SIN_CONFIRMAR)
      rc=1
      bc_err "La orden dijo que fue bien, pero la configuración NO lo confirma."
      bc_log  "  Se pidió:  $repo"
      bc_log  "             $BC_HESTIA_PEDIDO_RETENCION"
      bc_log  "  Se leyó:   $(bc_hestia_conf_valor "$despues_txt" REPO)"
      bc_log  "             $(bc_hestia_conf_retencion "$despues_txt")"
      # Si el archivo quedó EXACTAMENTE igual que antes, HestiaCP abortó sin
      # llegar a escribir: validación de argumentos, directorio inexistente o
      # un destino que no responde. Decirlo ahorra media hora de búsqueda.
      if [[ "$antes_txt" == "$despues_txt" ]]; then
        bc_log "La configuración quedó EXACTAMENTE como estaba, así que la orden"
        bc_log "ni llegó a escribir. Mira el destino del repositorio y que responda."
      fi
      bc_log  "Esto NO es un error que se arregle reintentando: el servidor dice una"
      bc_log  "cosa y enseña otra. Mira $HESTIA_CONF_RESTIC en el panel."
      [[ -n "$copia" ]] && bc_log "La configuración anterior está en: $copia"
      mensaje="la orden salió con $codigo y la relectura no confirma el cambio" ;;
    ESCRITO_SIN_COMPROBAR)
      rc=1
      bc_err "SE ESCRIBIÓ, pero no se pudo volver a leer la configuración."
      bc_log  "No se sabe cómo quedó el servidor. Hay que mirarlo:"
      bc_log  "  $HESTIA_CONF_RESTIC"
      [[ -n "$copia" ]] && bc_log "La configuración anterior está en: $copia"
      mensaje="se escribió y no se pudo leer el resultado" ;;
    FALLO)
      rc=1
      bc_err "La orden falló (código $codigo) y la configuración no cambió."
      [[ -n "$salida" ]] && { bc_log "Lo que respondió:"; \
        bc_hestia_restaurar_saltos "$salida" | sed 's/^/        /'; }
      mensaje="la orden falló y el cambio no está" ;;
    CIEGO|*)
      rc=1
      bc_err "No se pudo leer $HESTIA_CONF_RESTIC: NO se ha tocado nada."
      bc_log  "El servidor está como estaba. Comprueba el acceso y vuelve a intentarlo."
      mensaje="no se pudo leer la configuración; no se escribió nada" ;;
  esac

  bc_informe_paso "Registrar el host de respaldo" "$estado" "$mensaje"

  # Segundo paso, con su propio estado: el objetivo no es dejar un archivo
  # escrito, es dejar el servidor capaz de respaldar. Solo se informa cuando
  # el primero salió bien; si el registro falló, esto es ruido.
  if [[ "$estado" == "HECHO" || "$estado" == "SIN_CAMBIO" ]]; then
    case "$restic_vivo" in
      1) bc_ok "restic responde en el servidor."
         bc_informe_paso "restic en el servidor" HECHO "responde" ;;
      0) rc=1
         bc_err "El destino quedó registrado, pero restic NO responde en el servidor."
         bc_log  "Sin restic no se hará ninguna copia, por muy bien que esté la"
         bc_log  "configuración. Esto NO se arregla repitiendo esta orden: hay que"
         bc_log  "instalarlo en el servidor."
         bc_informe_paso "restic en el servidor" FALLO \
           "el destino quedó registrado pero restic no responde: sin él no se hará ninguna copia" ;;
      *) rc=1
         bc_err "El destino quedó registrado, pero NO se pudo comprobar si restic responde."
         bc_log  "Compruébalo en el servidor antes de fiarte de este registro."
         bc_informe_paso "restic en el servidor" CIEGO \
           "no se pudo comprobar si restic responde" ;;
    esac
  fi

  local ruta_informe
  ruta_informe="$(bc_informe_cerrar "$estado")"
  [[ -n "$ruta_informe" ]] && bc_log "Informe de lo hecho: $ruta_informe"
  return "$rc"
}

# -----------------------------------------------------------------------------
# ¿Dónde está el cron de Restic?
# -----------------------------------------------------------------------------
# No basta con mirar `crontab -l`. Comprobado en un servidor real: la entrada
# puede vivir en sitios muy distintos y ninguno es «el evidente».
#
#   /var/spool/cron/crontabs/hestiaweb   crontab interno de HestiaCP, donde
#                                        están sus propios v-update-sys-queue.
#                                        Es donde suele acabar si se añadió a
#                                        mano siguiendo el estilo del panel.
#   crontab de root                      si se añadió con `crontab -e` como root
#   cron.conf de un usuario del panel    si se añadió desde la sección Cron
#   /etc/cron.d/*                        si se puso como cron del sistema
#
# Mirar solo uno da un «NO está activo» falso en un servidor que lleva meses
# respaldando cada noche. Se buscan todos.
bc_hestia_cron_donde() {
  local encontrado=""
  local salida

  # Crontabs de usuario, incluido el interno de HestiaCP
  salida="$(bc_hestia_read "
    for f in /var/spool/cron/crontabs/*; do
      [ -f \"\$f\" ] || continue
      grep -H 'v-backup-users\?-restic' \"\$f\" 2>/dev/null | grep -v '^#'
    done" || true)"
  [[ -n "$salida" ]] && encontrado+="$salida"$'\n'

  # Crones del sistema
  salida="$(bc_hestia_read "grep -rh 'v-backup-users\?-restic' /etc/cron.d/ /etc/crontab 2>/dev/null | grep -v '^#'" || true)"
  [[ -n "$salida" ]] && encontrado+="$salida"$'\n'

  # Los de la sección Cron del panel
  salida="$(bc_hestia_read "grep -l 'restic' $HESTIA_DIR/data/users/*/cron.conf 2>/dev/null" || true)"
  [[ -n "$salida" ]] && encontrado+="panel HestiaCP: $salida"$'\n'

  sed '/^$/d' <<<"$encontrado"
}

# =============================================================================
# Cron de Restic
# =============================================================================
bc_hestia_cron() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local hora="${BC_OPT_HOUR:-5}" minuto="${BC_OPT_MINUTE:-45}"

  bc_section "Cron de respaldos Restic"

  # ---------------------------------------------------------------------------
  # POR QUÉ ESTE CRON NO EXISTE SOLO  (comprobado en HestiaCP 1.10.4)
  # ---------------------------------------------------------------------------
  # v-add-backup-host-restic solo escribe conf/restic.conf y pone
  # BACKUP_INCREMENTAL=yes. No programa nada: no hay ni una mención a
  # v-backup-users-restic en bin/, func/ ni install/. Configurar el
  # incremental deja el repositorio listo, pero NADIE lo llena.
  #
  # DÓNDE VA
  # v-backup-users-restic recorre TODAS las cuentas: es una tarea del sistema,
  # no de un usuario del panel. Por eso no se registra con v-add-cron-job (que
  # la ataría a una cuenta) sino en el crontab de `hestiaweb`, que es donde el
  # instalador pone v-backup-users, v-update-sys-queue y las demás tareas
  # propias. Se sigue el mismo idioma que v-add-cron-restart-job:
  #   comprobar con grep, añadir al final, chmod 600, chown hestiaweb.
  #
  # v-rebuild-cron-jobs actúa sobre un USUARIO del panel y regenera su crontab
  # desde su cron.conf. hestiaweb no es un usuario del panel, así que esta
  # línea NO la borra ningún rebuild.
  # ---------------------------------------------------------------------------
  bc_warn "HestiaCP NO programa este cron al configurar el respaldo incremental."
  bc_warn "Sin él, Restic queda montado pero el repositorio no se llena nunca."

  local linea="$minuto $hora * * * sudo $HESTIA_DIR/bin/v-backup-users-restic"
  BC_HESTIA_CRON_LINEA="$linea"

  # Se busca en TODAS partes antes de añadir nada. Un segundo cron significaría
  # dos respaldos simultáneos compitiendo por el mismo repositorio, que es peor
  # que uno mal puesto.
  local existente
  existente="$(bc_hestia_cron_donde)"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_step "Simulación (--dry-run): esto es lo que PASARÍA, no lo que ha pasado."
    bc_hestia_plan_cron "$existente" "$linea"
    bc_ok "No se ha tocado nada, y no se ha guardado ningún informe."
    return 0
  fi

  bc_informe_abrir "Programar el respaldo incremental" "${DEPLOY_HOST:-este servidor}"
  bc_informe_dato "Línea pedida" "" "$linea"

  # --- Ya hay una programación en alguna parte -------------------------------
  # No se añade otra, pero tampoco se da por buena sin mirarla: la del PO
  # estaba en el crontab de una cuenta, sin ruta absoluta y con la hora 25.
  if [[ -n "$existente" ]]; then
    local rc_ex=0
    bc_hestia_informar_cron_existente "$existente" || rc_ex=$?
    local ruta_ex; ruta_ex="$(bc_informe_cerrar "$([[ $rc_ex -eq 0 ]] && echo SIN_CAMBIO || echo FALLO)")"
    [[ -n "$ruta_ex" ]] && bc_log "Informe de lo hecho: $ruta_ex"
    (( rc_ex != 0 )) && BC_DELIBERATE_EXIT=1
    return "$rc_ex"
  fi

  bc_log "Se añadirá a $BC_HESTIA_CRONTAB_SIS :"
  bc_log "    $linea"
  bc_log "Los respaldos .tar de HestiaCP corren a las 05:10; esta hora no se solapa."

  if ! bc_confirm "¿Programar el respaldo Restic diario?" y; then
    bc_log "Cancelado."
    bc_informe_paso "Programar el respaldo" SIN_CAMBIO "cancelado por el usuario"
    bc_informe_cerrar "CANCELADO" >/dev/null
    return 0
  fi

  # --- La copia a la que volver ----------------------------------------------
  local copia=""
  if ! copia="$(bc_hestia_copia_fechada "$BC_HESTIA_CRONTAB_SIS")"; then
    bc_err "no se pudo dejar una copia de $BC_HESTIA_CRONTAB_SIS. NO se ha programado nada."
    bc_log  "Sin una copia a la que volver no se toca el crontab de un servidor."
    bc_informe_paso "Copia de seguridad" FALLO "no se pudo copiar $BC_HESTIA_CRONTAB_SIS"
    bc_informe_cerrar "FALLO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  if [[ -n "$copia" ]]; then
    bc_ok "Copia del crontab anterior: $copia"
    bc_informe_copia "$BC_HESTIA_CRONTAB_SIS" "$copia"
    bc_informe_deshacer "cp -p $copia $BC_HESTIA_CRONTAB_SIS && chown hestiaweb:hestiaweb $BC_HESTIA_CRONTAB_SIS && chmod 600 $BC_HESTIA_CRONTAB_SIS"
  else
    bc_err "no existe $BC_HESTIA_CRONTAB_SIS. ¿Es este un servidor con HestiaCP?"
    bc_log  "Ese archivo lo crea el instalador de HestiaCP; no se crea desde aquí."
    bc_informe_paso "Programar el respaldo" FALLO "no existe $BC_HESTIA_CRONTAB_SIS"
    bc_informe_cerrar "FALLO" >/dev/null
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  # --- Escribir y comprobar --------------------------------------------------
  # El `printf '\n'` de delante no sobra: si el archivo no termina en salto de
  # línea, un >> pegaría la orden a la última existente y rompería las dos.
  # Y el chmod/chown van DENTRO de la misma orden porque un crontab con otros
  # permisos o con otro dueño lo ignora cron ENTERO, y eso es indistinguible
  # de «no hay respaldo» hasta que pasan semanas.
  local ct; ct="$(printf '%q' "$BC_HESTIA_CRONTAB_SIS")"
  local orden_escritura="[ -s $ct ] && [ -n \"\$(tail -c1 $ct)\" ] && printf '\n' >> $ct; \
printf '%s\n' $(printf '%q' "$linea") >> $ct && chmod 600 $ct && chown hestiaweb:hestiaweb $ct"
  bc_informe_orden "$orden_escritura"

  local datos
  datos="$(bc_hestia_escribir_y_confirmar "Programar el respaldo incremental" \
      "$orden_escritura" "cat $ct" bc_hestia_cron_ya_estaba bc_hestia_cron_se_hizo)"

  # Los permisos y el dueño, solo si la línea quedó puesta.
  local permisos="?"
  case "$(bc_hestia_dato_de "$datos" estado)" in
    HECHO|SIN_CAMBIO) permisos="$(bc_hestia_leer_texto "stat -c '%a %U:%G' $ct" || true)" ;;
  esac

  local rc=0
  bc_hestia_informar_cron "$datos" "$copia" "$permisos" || rc=$?
  (( rc != 0 )) && BC_DELIBERATE_EXIT=1
  return "$rc"
}

# La línea que se va a programar. Los jueces solo reciben el texto leído, así
# que lo pedido viaja por aquí, igual que en el registro del host.
BC_HESTIA_CRON_LINEA=""

# La primera línea de respaldo incremental que haya en un crontab, sin las
# comentadas. Pura.
bc_hestia_cron_linea_de() {
  grep -v '^[[:space:]]*#' <<<"${1:-}" | grep 'v-backup-users\?-restic' | sed -n '1p'
}

# ¿Este crontab tiene una programación que el diagnóstico dé por buena?
#
# No basta con que la línea ESTÉ: tiene que estar bien. Se reutiliza el mismo
# juez que usa `hestia status` (bc_hestia_diag_cron), que ya sabe de horas
# imposibles, rutas sin absolutizar y crontabs equivocados. Si la línea
# escrita no pasara ese examen, esto no es HECHO.
bc_hestia_cron_cumple() {
  local texto="${1:-}" cron_linea
  cron_linea="$(bc_hestia_cron_linea_de "$texto")"
  [[ -n "$cron_linea" ]] || return 1
  local veredicto; veredicto="$(bc_hestia_diag_cron "$cron_linea" "$BC_HESTIA_CRONTAB_SIS")"
  [[ "${veredicto%%$'\t'*}" == "OK" ]]
}

bc_hestia_cron_ya_estaba() { bc_hestia_cron_cumple "${1:-}"; }
bc_hestia_cron_se_hizo()   { bc_hestia_cron_cumple "${2:-}"; }

# El plan del ensayo. Pura.
# $1 lo que ya hay (vacío si nada)   $2 la línea que se pondría
bc_hestia_plan_cron() {
  local existente="${1:-}" linea="${2:-}"
  if [[ -n "$existente" ]]; then
    bc_log "Ya hay una programación de respaldo incremental:"
    sed 's/^/        /' <<<"$existente"
    bc_log "No se añadiría otra: dos respaldos a la vez sobre el mismo"
    bc_log "repositorio es peor que uno mal puesto."
    return 0
  fi
  bc_log "Ahora mismo NO hay ninguna programación de respaldo incremental."
  bc_log "Se añadiría a $BC_HESTIA_CRONTAB_SIS :"
  bc_log "    $linea"
  bc_log "Se dejaría antes una copia fechada de $BC_HESTIA_CRONTAB_SIS."
  return 0
}

# Ya había una programación: se dice dónde está y qué le pasa, y NO se añade
# otra. Devuelve 0 solo si la que hay está bien puesta.
bc_hestia_informar_cron_existente() {
  local existente="${1:-}"
  bc_log "Ya hay una programación de respaldo incremental. No se añade otra:"
  sed 's/^/        /' <<<"$existente"
  bc_informe_dato "Programación encontrada" "$existente" "$existente"

  # La línea viene como "archivo:contenido" (grep -H). El diagnóstico necesita
  # las dos partes por separado: el archivo es la mitad del veredicto.
  local primera archivo="" cuerpo
  primera="$(sed -n '1p' <<<"$existente")"
  cuerpo="$primera"
  if [[ "$primera" == /*:* ]]; then
    archivo="${primera%%:*}"; cuerpo="${primera#*:}"
  fi

  local veredicto nivel mensaje
  veredicto="$(bc_hestia_diag_cron "$cuerpo" "$archivo")"
  nivel="${veredicto%%$'\t'*}"; mensaje="${veredicto#*$'\t'}"

  if [[ "$nivel" == "OK" ]]; then
    bc_ok "Y está bien puesta: $mensaje"
    bc_log "Para cambiar la hora, edítala donde está."
    bc_informe_paso "Programar el respaldo" SIN_CAMBIO "ya había una, y está bien puesta"
    return 0
  fi

  bc_err "La programación que hay tiene un problema: $mensaje"
  bc_log  "NO se ha añadido otra: dos respaldos a la vez sobre el mismo repositorio"
  bc_log  "es peor que uno mal puesto. Decide tú: arregla la que hay donde está, o"
  bc_log  "quítala y vuelve a ejecutar esta orden."
  bc_informe_paso "Programar el respaldo" FALLO \
    "ya había una programación y tiene un problema: $mensaje"
  return 1
}

# Traduce los datos de la escritura del cron. Devuelve 0 solo si quedó bien.
# $1 datos   $2 copia fechada   $3 permisos leídos ('?' si no se miraron)
bc_hestia_informar_cron() {
  local datos="${1:-}" copia="${2:-}" permisos="${3:-?}"
  local estado antes despues codigo salida
  estado="$(bc_hestia_dato_de "$datos" estado)"
  antes="$(bc_hestia_dato_de "$datos" antes)"
  despues="$(bc_hestia_dato_de "$datos" despues)"
  codigo="$(bc_hestia_dato_de "$datos" codigo)"
  salida="$(bc_hestia_dato_de "$datos" salida)"
  estado="${estado:-CIEGO}"

  local antes_txt despues_txt
  antes_txt="$(bc_hestia_restaurar_saltos "$antes")"
  despues_txt="$(bc_hestia_restaurar_saltos "$despues")"
  bc_informe_dato "Línea programada" \
    "$(bc_hestia_cron_linea_de "$antes_txt")" "$(bc_hestia_cron_linea_de "$despues_txt")"
  [[ -n "$salida" ]] && bc_informe_dato "Lo que respondió la orden" "" \
    "$(bc_hestia_restaurar_saltos "$salida")"

  local rc=0 mensaje=""
  case "$estado" in
    SIN_CAMBIO)
      bc_ok "No había nada que cambiar: ya estaba programado y bien puesto."
      mensaje="ya estaba programado correctamente" ;;
    HECHO)
      bc_ok "Respaldo incremental programado, y comprobado leyéndolo de vuelta:"
      bc_log "    $(bc_hestia_cron_linea_de "$despues_txt")"
      mensaje="programado y confirmado releyendo el crontab" ;;
    SIN_CONFIRMAR)
      rc=1
      bc_err "Se escribió la línea, pero al releer el crontab NO queda bien."
      local puesta; puesta="$(bc_hestia_cron_linea_de "$despues_txt")"
      if [[ -z "$puesta" ]]; then
        bc_log "No se encuentra ninguna línea de respaldo incremental en el crontab."
      else
        bc_log "La línea que hay es:"
        bc_log "    $puesta"
        bc_log "Y el diagnóstico la rechaza: $(bc_hestia_diag_cron "$puesta" "$BC_HESTIA_CRONTAB_SIS" | cut -f2-)"
      fi
      [[ -n "$copia" ]] && bc_log "El crontab anterior está en: $copia"
      mensaje="se escribió y la relectura no la da por buena" ;;
    ESCRITO_SIN_COMPROBAR)
      rc=1
      bc_err "SE ESCRIBIÓ en el crontab, pero no se pudo volver a leer."
      bc_log  "No se sabe cómo quedó. Míralo: $BC_HESTIA_CRONTAB_SIS"
      [[ -n "$copia" ]] && bc_log "El crontab anterior está en: $copia"
      mensaje="se escribió y no se pudo leer el resultado" ;;
    FALLO)
      rc=1
      bc_err "No se pudo escribir en el crontab (código $codigo)."
      [[ -n "$salida" ]] && { bc_log "Lo que respondió:"; \
        bc_hestia_restaurar_saltos "$salida" | sed 's/^/        /'; }
      mensaje="la orden falló y la línea no está" ;;
    CIEGO|*)
      rc=1
      bc_err "No se pudo leer $BC_HESTIA_CRONTAB_SIS: NO se ha tocado nada."
      mensaje="no se pudo leer el crontab; no se escribió nada" ;;
  esac
  bc_informe_paso "Programar el respaldo" "$estado" "$mensaje"

  # Los permisos y el dueño, con su propio veredicto: un crontab con otros
  # permisos lo ignora cron ENTERO, y eso no se distingue de «no hay respaldo»
  # hasta que pasan semanas sin una sola copia.
  if [[ "$estado" == "HECHO" || "$estado" == "SIN_CAMBIO" ]]; then
    bc_informe_dato "Permisos y dueño del crontab" "" "$permisos"
    case "$permisos" in
      "600 hestiaweb:hestiaweb")
        bc_ok "El crontab tiene los permisos y el dueño correctos (600 hestiaweb:hestiaweb)."
        bc_informe_paso "Permisos del crontab" HECHO "600 hestiaweb:hestiaweb" ;;
      "?"|"")
        rc=1
        bc_err "No se pudieron comprobar los permisos ni el dueño del crontab."
        bc_log  "Compruébalo a mano: debe ser 600 y de hestiaweb:hestiaweb."
        bc_informe_paso "Permisos del crontab" CIEGO "no se pudieron leer" ;;
      *)
        rc=1
        bc_err "El crontab tiene permisos o dueño equivocados: '$permisos'."
        bc_log  "Debe ser 600 y de hestiaweb:hestiaweb. Con otros valores, cron"
        bc_log  "puede ignorar el archivo ENTERO, y no se notaría hasta que"
        bc_log  "pasaran semanas sin una sola copia."
        bc_informe_paso "Permisos del crontab" FALLO \
          "'$permisos' en vez de '600 hestiaweb:hestiaweb'" ;;
    esac
  fi

  local ruta_informe
  ruta_informe="$(bc_informe_cerrar "$estado")"
  [[ -n "$ruta_informe" ]] && bc_log "Informe de lo hecho: $ruta_informe"
  return "$rc"
}

# =============================================================================
# Verificación del repositorio
# =============================================================================
bc_hestia_verify() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local repo
  repo="$(bc_hestia_read "sed -n \"s/^REPO='\(.*\)'\$/\1/p\" '$HESTIA_CONF_RESTIC'" || true)"
  [[ -n "$repo" ]] || bc_die "Restic no está configurado. Móntalo con: backupctl hestia setup"

  bc_section "Verificación del repositorio Restic"
  bc_log "Repositorio: $repo"

  bc_step "Instantáneas"
  bc_hestia_root "restic -r '$repo' snapshots 2>&1 | tail -20" | sed 's/^/        /' \
    || bc_warn "no se pudieron listar."

  bc_step "Estado del repositorio"
  if bc_hestia_root "restic -r '$repo' check 2>&1 | tail -10" | sed 's/^/        /'; then
    bc_ok "repositorio íntegro."
  else
    bc_err "el repositorio NO pasa la comprobación."
  fi

  bc_step "Espacio (tras deduplicar)"
  bc_hestia_root "restic -r '$repo' stats 2>&1 | tail -8" | sed 's/^/        /' || true
}

# =============================================================================
# Rescate de claves — lo que hace que el respaldo sea recuperable
# =============================================================================
# -----------------------------------------------------------------------------
# ¿Dónde se dejan las claves rescatadas?
# -----------------------------------------------------------------------------
# Cuando el perfil apunta a otro servidor, HESTIA_OUTPUT_DIR es una ruta DEL
# SERVIDOR (/home/admin/scripts/output/HestiaCP). Aquí no existe, y `mkdir -p`
# se estrellaba contra «Permiso denegado» al intentar crear /home/admin.
#
# Rescatando desde fuera, el destino correcto es el repositorio: es exactamente
# el sitio donde tienen que estar, fuera del servidor que se quiere poder
# perder. Ahí están ya los rescates anteriores.
bc_hestia_salida() {
  # No se mira BC_HESTIA_REMOTO: hay funciones que consultan esto sin haber
  # abierto conexión, y entonces la variable no está puesta. El criterio es
  # el hecho objetivo —si HestiaCP está en esta máquina o no— y es el mismo
  # que aplica dir_claves_local() en web/server.py, para que la interfaz y
  # la línea de órdenes no puedan discrepar.
  if [[ -d "$HESTIA_DIR" ]]; then
    echo "$HESTIA_OUTPUT_DIR"
  else
    echo "$BC_PROFILE_DIR/output/HestiaCP"
  fi
}

bc_hestia_keys() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Rescate de claves"
  bc_warn "Sin estos dos archivos, tus respaldos son irrecuperables aunque estén"
  bc_warn "intactos: uno descifra el repositorio y el otro permite llegar a él."

  local destino; destino="$(bc_hestia_salida)"
  mkdir -p "$destino" 2>/dev/null \
    || bc_die "no se puede escribir en $destino. Comprueba los permisos."
  bc_log "Las claves se guardarán en: $destino"
  # Con la HORA, no solo la fecha: dos rescates el mismo día se pisaban, y un
  # rescate anterior es justo lo que NO se puede perder — es el único sitio
  # donde queda una contraseña que el panel haya cambiado.
  local fecha; fecha="$(date +%Y%m%d-%H%M%S)"
  local n_restic=0

  local salida="$destino/Restic_Configs_${fecha}.txt"
  local anterior; anterior="$(bc_hestia_rescate_anterior "$destino" "$salida")"
  local anterior_txt=""
  if [[ -n "$anterior" ]]; then
    bc_log "Se comparará con el rescate anterior: $(basename "$anterior")"
    anterior_txt="$(cat "$anterior" 2>/dev/null || true)"
  else
    bc_log "No hay ningún rescate anterior con el que comparar: este es el primero."
  fi

  # --- La clave de cada cuenta ----------------------------------------------
  local confs
  confs="$(bc_hestia_read "find '$HESTIA_DIR' -type f -name restic.conf" || true)"
  local cuentas_con_clave="" cambiadas=0 iguales=0 nuevas=0
  if [[ -n "$confs" ]]; then
    n_restic="$(grep -c . <<<"$confs" || true)"

    if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
      bc_step "Simulación (--dry-run): esto es lo que PASARÍA, no lo que ha pasado."
      bc_log "Se rescatarían las claves de $n_restic cuenta(s), a:"
      bc_log "    $salida"
      bc_log "y se compararían con el rescate anterior para avisar si alguna cambió."
      bc_ok "No se ha escrito nada, y no se ha guardado ningún informe."
      return 0
    fi

    bc_informe_abrir "Rescate de claves" "${DEPLOY_HOST:-este servidor}"

    # El archivo se compone en un temporal y se mueve al final: si algo falla a
    # mitad, no queda un rescate a medias que parezca completo.
    local tmp; tmp="$(mktemp)"
    bc_cleanup_register "keys:$tmp" "rm -f $(printf '%q' "$tmp")"
    {
      printf '# Claves de repositorio de las cuentas de HestiaCP\n'
      printf '# Servidor: %s\n' "$( (( BC_HESTIA_REMOTO )) && echo "$DEPLOY_HOST" || hostname -f 2>/dev/null || hostname )"
      printf '# Generado: %s por backupctl %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$BC_VERSION"
    } > "$tmp"

    local c u contenido huella huella_antes veredicto
    while IFS= read -r c; do
      [[ -z "$c" ]] && continue
      u="$(basename "$(dirname "$c")")"
      contenido="$(bc_hestia_read "cat $(printf '%q' "$c")" || true)"
      if [[ -z "$contenido" ]]; then
        bc_err "  $u: NO se pudo leer su clave."
        bc_informe_paso "Clave de $u" CIEGO "no se pudo leer"
        continue
      fi
      cuentas_con_clave+="$u"$'\n'

      # Se escribe la clave en el archivo de rescate —que para eso está— pero
      # NO sale por ninguna otra parte: lo que se compara y se informa es la
      # huella, nunca el valor.
      { printf '# %s:\n' "$u"; printf '%s\n' "$contenido"; printf '\n=====================\n\n'; } >> "$tmp"

      huella="$(bc_hestia_huella "$contenido")"
      huella_antes="$(bc_hestia_huella "$(bc_hestia_bloque_rescatado "$anterior_txt" "$u")")"
      veredicto="$(bc_hestia_comparar_huellas "$huella" "$huella_antes")"

      case "$veredicto" in
        igual)
          iguales=$(( iguales + 1 ))
          bc_ok "  $u: la misma clave que en el rescate anterior. Lo guardado sigue sirviendo."
          bc_informe_paso "Clave de $u" SIN_CAMBIO "igual que en el rescate anterior" ;;
        sin-anterior)
          nuevas=$(( nuevas + 1 ))
          bc_ok "  $u: rescatada. No había rescate anterior de esta cuenta con el que comparar."
          bc_informe_paso "Clave de $u" HECHO "rescatada; sin rescate anterior con el que comparar" ;;
        *)
          cambiadas=$(( cambiadas + 1 ))
          bc_err "  $u: LA CONTRASEÑA HA CAMBIADO desde el último rescate."
          bc_log  "     Las copias de esta cuenta hechas ANTES del cambio NO se abren con"
          bc_log  "     la nueva. La anterior sigue en $(basename "${anterior:-<sin anterior>}"),"
          bc_log  "     que NO se borra ni se sobrescribe. Conserva las DOS mientras existan"
          bc_log  "     copias de las dos épocas."
          bc_informe_paso "Clave de $u" FALLO \
            "la contraseña CAMBIÓ desde el rescate anterior; las copias previas al cambio no se abren con la nueva" ;;
      esac
      bc_informe_dato "Clave de $u" "$([[ -n "$huella_antes" ]] && echo "rescatada antes" || echo "sin rescate anterior")" \
        "$veredicto"
    done <<<"$confs"

    mv -f "$tmp" "$salida" && bc_cleanup_forget "keys:$tmp"
    bc_ok "Claves de las cuentas: $salida"
  else
    bc_err "no se encontró ninguna clave de cuenta."
    [[ "${BC_OPT_DRY:-0}" == "1" ]] && return 1
    bc_informe_abrir "Rescate de claves" "${DEPLOY_HOST:-este servidor}"
    bc_informe_paso "Rescate de claves" FALLO "no se encontró ninguna clave de cuenta"
  fi

  # --- Cuentas con copias y SIN clave rescatable ----------------------------
  # Una cuenta con repositorio cuya clave no se pueda rescatar tiene copias que
  # nadie podrá abrir si se pierde el servidor. Eso es un fallo con nombre.
  bc_hestia_avisar_sin_clave "$cuentas_con_clave"

  # --- rclone.conf ----------------------------------------------------------
  # Este es el que casi nadie guarda: Restic respalda las cuentas de usuario,
  # no la configuración de root. Sin él no se puede LLEGAR al repositorio,
  # aunque se tengan las claves para descifrarlo.
  local rc_salida="$destino/rclone_${fecha}.conf"
  if bc_hestia_read "cat '$BC_HESTIA_RCLONE_CONF'" > "$rc_salida" && [[ -s "$rc_salida" ]]; then
    bc_ok "Configuración de rclone: $rc_salida"
  else
    rm -f "$rc_salida"
    bc_warn "no se pudo leer $BC_HESTIA_RCLONE_CONF (¿hacen falta permisos de root?)."
  fi

  echo
  bc_err "GUARDA ESTOS ARCHIVOS FUERA DEL SERVIDOR."
  bc_log "En un gestor de contraseñas o en otra máquina. Mientras vivan solo dentro"
  bc_log "del servidor que protegen, NO PROTEGEN NADA: se pierden con él, y con"
  bc_log "ellos la posibilidad de recuperar una sola copia."
  bc_informe_dato "Dónde han quedado" "" "$destino"
  bc_informe_deshacer "Nada que deshacer: este paso solo LEE del servidor y escribe en el perfil. Ningún rescate anterior se borra ni se sobrescribe."

  echo
  if (( cambiadas > 0 )); then
    bc_err "Resumen: $cambiadas clave(s) CAMBIADAS, $iguales igual(es), $nuevas nueva(s)."
    bc_err "Una clave cambiada significa copias viejas que la nueva no abre. No borres"
    bc_err "ningún rescate anterior."
  else
    bc_ok "Resumen: $iguales clave(s) igual(es) que antes, $nuevas nueva(s), ninguna cambiada."
  fi

  bc_prune "$destino" 'Restic_Configs_*.txt' "$RESTIC_RETENTION_DAYS" 2 "claves Restic" 0
  bc_prune "$destino" 'rclone_*.conf'        "$RESTIC_RETENTION_DAYS" 2 "config rclone"  0

  local estado_final=HECHO
  (( cambiadas > 0 || BC_HESTIA_SIN_CLAVE > 0 )) && estado_final=FALLO
  bc_informe_paso "Rescate de claves" "$estado_final" \
    "$iguales igual(es), $nuevas nueva(s), $cambiadas cambiada(s), $BC_HESTIA_SIN_CLAVE con copias y sin clave"
  local ruta; ruta="$(bc_informe_cerrar "$estado_final")"
  [[ -n "$ruta" ]] && bc_log "Informe de lo hecho: $ruta"

  if [[ "$estado_final" == "FALLO" ]]; then BC_DELIBERATE_EXIT=1; return 1; fi
  return 0
}

# Cuántas cuentas tienen copias y ninguna clave rescatable.
BC_HESTIA_SIN_CLAVE=0

# Avisa, con nombre, de las cuentas que tienen repositorio y de las que no se
# ha podido rescatar ninguna clave: sus copias no las abrirá nadie si se pierde
# el servidor.
# $1 las cuentas cuya clave SÍ se rescató, una por línea
bc_hestia_avisar_sin_clave() {
  local rescatadas="${1:-}"
  BC_HESTIA_SIN_CLAVE=0

  local lista
  lista="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-users plain" || true)"
  if [[ -z "$lista" ]]; then
    bc_warn "No se pudo leer la lista de cuentas: no se puede comprobar si alguna"
    bc_warn "tiene copias sin clave rescatada. Compruébalo en el panel."
    bc_informe_paso "Cuentas con copias y sin clave" CIEGO "no se pudo leer la lista de cuentas"
    return 0
  fi

  local conf repo
  conf="$(bc_hestia_read "cat $(printf '%q' "$HESTIA_CONF_RESTIC")" || true)"
  repo="$(bc_hestia_conf_valor "$conf" REPO)"
  if [[ -z "$repo" ]]; then
    bc_log "No hay ningún repositorio registrado: no hay copias que puedan quedarse sin clave."
    return 0
  fi

  local u sin_clave=()
  while IFS= read -r u; do
    u="$(awk '{print $1}' <<<"$u")"
    [[ -z "$u" || "$u" == "USER" ]] && continue
    grep -qxF "$u" <<<"$rescatadas" && continue
    [[ "$(bc_hestia_sondear_repo "$repo" "$u")" == "1" ]] && sin_clave+=("$u")
  done <<<"$lista"

  (( ${#sin_clave[@]} == 0 )) && return 0
  BC_HESTIA_SIN_CLAVE="${#sin_clave[@]}"
  echo
  bc_err "TIENEN COPIAS Y NO SE HA RESCATADO SU CLAVE (${#sin_clave[@]}): ${sin_clave[*]}"
  bc_log  "Si se pierde el servidor, esas copias no las abrirá nadie. Mira por qué no"
  bc_log  "tienen clave en \$HESTIA/data/users/<cuenta>/restic.conf antes de fiarte de"
  bc_log  "esos respaldos."
  bc_informe_paso "Cuentas con copias y sin clave" FALLO "${sin_clave[*]}"
  return 0
}

# -----------------------------------------------------------------------------
# Última instantánea Restic de un usuario
# -----------------------------------------------------------------------------
# Se usa la orden PROPIA de HestiaCP en lugar de invocar restic a mano.
#
# Razones, todas comprobadas en el código de HestiaCP 1.10.4:
#   - La ruta del repositorio es "${REPO%/}/$user": cada usuario tiene el SUYO.
#     Componerla por nuestra cuenta obliga a replicar ese detalle, y ya hubo un
#     fallo histórico ahí (issue 5100 de HestiaCP, con y sin barra final).
#   - La contraseña se pasa con --password-file, no por variable de entorno.
#   - Si HestiaCP cambia el esquema, su orden sigue funcionando y la nuestra no.
#
# OJO con no confundir dos cosas distintas:
#   v-list-user-backups          los .tar tradicionales
#   v-list-user-backups-restic   las instantáneas de Restic   <- esto es lo real
# SIEMPRE con `json` explícito (ADR 0017). Y el parseo se apoya en la clave
# "time", no en columnas ni en "short_id":
#   - v-list-user-backups-restic no formatea nada; ejecuta `restic snapshots`
#     (con --json o sin él) y deja pasar su salida tal cual (fuente 1.10.4,
#     verificado el 2026-09-23). Es decir, el formato lo decide el `restic`
#     instalado en cada servidor, no HestiaCP.
#   - De ese formato, "time" es el único campo que se puede dar por estable en
#     todas las versiones de restic que este proyecto admite (>= 0.14). Las
#     columnas del formato de tabla y la clave "short_id" NO están verificadas
#     para 0.14, y contar por ellas daría cero instantáneas en silencio.
bc_hestia_restic_ultima() {
  local u="$1"
  local salida
  salida="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-user-backups-restic $(printf '%q' "$u") json" || true)"
  [[ -n "$salida" ]] || { echo "no disponible"; return 0; }
  [[ "$salida" == *"{"* || "$salida" == *"["* ]] || { echo "no disponible"; return 0; }

  # La más reciente por INSTANTE, y se muestra en la hora local de quien mira
  # CON su huso a la vista. Antes se recortaba a 19 caracteres para que la
  # columna cupiera, y eso borraba justo el dato que dice qué significa esa
  # hora: la misma copia salía con horas distintas según el huso con que la
  # hubiera escrito el servidor. Si hay que acortar la columna, se acorta por
  # otro sitio, no por el dato que dice qué significa la hora.
  local fechas ultima
  fechas="$(grep -oE '"time"[[:space:]]*:[[:space:]]*"[^"]+"' <<<"$salida" \
            | sed 's/.*"\([^"]*\)"$/\1/')"
  ultima="$(bc_hestia_fecha_mas_reciente "$fechas")"
  [[ -n "$ultima" ]] || { echo "ninguna"; return 0; }
  bc_hestia_fecha_legible "$ultima"
  echo
}

# Cuántas instantáneas tiene un usuario, para contrastarlo con SNAPSHOTS.
# Una clave "time" por instantánea: `restic --json snapshots` serializa el
# array entero, así que contar LÍNEAS no vale (puede venir todo en una).
bc_hestia_restic_cuantas() {
  local u="$1" salida
  salida="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-user-backups-restic $(printf '%q' "$u") json" || true)"
  grep -oE '"time"[[:space:]]*:' <<<"$salida" | grep -c . || true
}

# =============================================================================
# Usuarios de HestiaCP
# =============================================================================
# Sin saber qué usuarios hay no se puede razonar sobre los respaldos: Restic
# respalda CUENTAS, y cada una tiene sus dominios, su correo y sus bases.
bc_hestia_users() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Usuarios de HestiaCP"

  local lista
  lista="$(bc_hestia_read "$HESTIA_DIR/bin/v-list-users plain" || true)"
  if [[ -z "$lista" ]]; then
    bc_warn "no se pudieron listar (hace falta root: conéctate como root)."
    return 1
  fi

  # El repositorio y la retención son GLOBALES, pero la CLAVE de cifrado es de
  # cada usuario: cada uno tiene su propio restic.conf. Con la clave de uno no
  # se abren los respaldos de los demás, así que la cobertura se mira usuario a
  # usuario y no como una sola cosa.
  local filas; filas="$(mktemp)"
  # El repositorio global es solo el prefijo: a cada usuario le corresponde
  # <REPO><usuario>, que es un repositorio Restic independiente.
  printf 'USUARIO\tDOMINIOS\tBASES\tCORREO\tCLAVE\tINSTANTÁNEAS\tÚLTIMA\tÚLTIMO .tar\n' > "$filas"
  local u
  while IFS= read -r u; do
    u="$(awk '{print $1}' <<<"$u")"
    [[ -z "$u" || "$u" == "USER" ]] && continue
    local dom bd mail rst ult
    dom="$( { bc_hestia_read "$HESTIA_DIR/bin/v-list-web-domains $u plain" || true; } | grep -c . || true )"
    bd="$(  { bc_hestia_read "$HESTIA_DIR/bin/v-list-databases $u plain"   || true; } | grep -c . || true )"
    mail="$({ bc_hestia_read "$HESTIA_DIR/bin/v-list-mail-domains $u plain" || true; } | grep -c . || true )"
    # La presencia de su restic.conf indica que ese usuario ya tiene clave propia
    if bc_hestia_read "test -f '$HESTIA_DIR/data/users/$u/restic.conf'"; then rst="sí"; else rst="NO"; fi
    # Último respaldo según el propio HestiaCP
    # v-list-user-backups devuelve el nombre del .tar en la primera columna y la
    # fecha en la última. Interesa la fecha, no el nombre del archivo.
    ult="$( { bc_hestia_read "$HESTIA_DIR/bin/v-list-user-backups $u plain" || true; } \
            | awk -F'\t' 'NF>1{print $NF}' | grep -E '^[0-9]{4}-' | sort -r | head -1 )"
    local snap
    snap="$(bc_hestia_restic_ultima "$u")"
    local n_snap; n_snap="$(bc_hestia_restic_cuantas "$u")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$u" "$dom" "$bd" "$mail" "$rst" "${n_snap:-0}" "$snap" "${ult:-ninguno}" >> "$filas"
  done <<<"$lista"

  bc_table < "$filas"; rm -f "$filas"
  echo
  bc_step "Cómo se reparte esto"
  bc_log "  El repositorio y la retención son GLOBALES: una sola configuración en"
  bc_log "  data/users/conf/restic.conf, la que pone v-add-backup-host-restic."
  bc_log "  La CLAVE de cifrado es DE CADA USUARIO: su propio restic.conf, que se"
  bc_log "  le crea solo la primera vez que se le respalda."
  bc_log "  v-backup-users-restic respalda a todos; v-backup-user-restic <u>, a uno."
  echo
  bc_log "  «CLAVE = NO» solo significa que ese usuario aún no se ha respaldado"
  bc_log "  nunca. No es un error si acabas de montarlo."
  echo
  bc_warn "ÚLTIMA INSTANTÁNEA es lo que cuenta: son los respaldos de Restic."
  bc_warn "ÚLTIMO .tar son los respaldos tradicionales de HestiaCP, que pueden"
  bc_warn "llevar años sin actualizarse aunque Restic funcione a diario. No"
  bc_warn "confundas una cosa con la otra."
  bc_warn "Hay que rescatar la clave de CADA usuario: con la de uno no se abren los"
  bc_warn "respaldos de los demás. «Traer las claves del servidor» las coge todas."
}

# -----------------------------------------------------------------------------
# Consultar MySQL y los respaldos EN EL SERVIDOR
# -----------------------------------------------------------------------------
# Las credenciales viajan a un archivo temporal 0600 en el destino y se borran
# al terminar: pasarlas como -p las haría visibles en `ps` para toda la máquina.
bc_hestia_mysql_remoto() {
  local cnf
  cnf="$(bc_ssh 'mktemp' < /dev/null)" || return 1
  # El `true` final NO es decorativo. Sin él, el último `[[ -n ... ]] && echo`
  # decide el código de salida del grupo: con MYSQL_SOCKET vacío —lo normal—
  # el grupo devuelve 1, y con pipefail la tubería entera se da por fallida.
  # La función abortaba antes de consultar nada y devolvía cero bases de datos
  # sin ningún error visible.
  {
    echo "[client]"
    echo "user=$MYSQL_USER"
    [[ -n "$MYSQL_PASS"   ]] && echo "password=$MYSQL_PASS"
    [[ -n "$MYSQL_HOST"   ]] && echo "host=$MYSQL_HOST"
    [[ -n "$MYSQL_PORT"   ]] && echo "port=$MYSQL_PORT"
    [[ -n "$MYSQL_SOCKET" ]] && echo "socket=$MYSQL_SOCKET"
    true
  } | bc_ssh "cat > '$cnf' && chmod 600 '$cnf'" || { bc_ssh "rm -f '$cnf'" < /dev/null; return 1; }

  # El script se envía por la entrada estándar a `bash -s` en lugar de meterlo
  # entrecomillado en la orden de ssh: anidar comillas dentro de comillas
  # dentro de SQL es una fuente inagotable de errores de escapado.
  bc_ssh 'bash -s' <<REMOTO || true
mysql --defaults-file='$cnf' -s --skip-column-names -e "
  SELECT schema_name FROM information_schema.schemata
  WHERE schema_name NOT IN $EXCLUDE_DBS ORDER BY schema_name"
REMOTO
  bc_ssh "rm -f '$cnf'" < /dev/null || true
}

# Bases de datos contenidas en el respaldo más reciente DEL SERVIDOR
bc_hestia_respaldo_remoto() {
  # \$z queda literal para que lo resuelva el shell del servidor;
  # $BACKUP_OUTPUT_DIR sí se expande aquí, que es lo que queremos enviar.
  bc_ssh 'bash -s' <<REMOTO || true
z=\$(ls -t '$BC_SRV_BACKUP_OUTPUT_DIR'/all_databases_*.zip 2>/dev/null | head -1)
[ -n "\$z" ] && unzip -Z1 "\$z" 2>/dev/null | awk -F/ 'NF>1{print \$1}' | sort -u
REMOTO
}

# =============================================================================
# Bases de datos: las que HestiaCP conoce y las que no
# =============================================================================
# Distinción que determina si una migración se replica bien.
#
#   Conocidas por HestiaCP   se dieron de alta con v-add-database. Tienen
#                            entrada en el panel, su usuario gestionado, y
#                            viajan dentro de v-backup-user.
#   Desconocidas             se crearon a mano en MySQL. HestiaCP no las ve,
#                            así que NO están en sus respaldos ni se recrean al
#                            restaurar una cuenta. Solo las salva backupctl.
#
# Al migrar, las desconocidas llegan con los datos pero SIN entrada en el panel
# ni usuario gestionado: hay que darlas de alta a mano en el destino. Sin esta
# lista, eso se descubre semanas después, cuando algo no conecta.
# =============================================================================
bc_hestia_dbs() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Bases de datos: cobertura real"

  # --- Las que HestiaCP conoce ----------------------------------------------
  local usuarios conocidas=""
  usuarios="$( { bc_hestia_read "$HESTIA_DIR/bin/v-list-users plain" || true; } | awk '{print $1}' )"
  local u
  while IFS= read -r u; do
    [[ -z "$u" || "$u" == "USER" ]] && continue
    local l
    l="$( { bc_hestia_read "$HESTIA_DIR/bin/v-list-databases $u plain" || true; } | awk 'NF{print $1}' )"
    [[ -n "$l" ]] && conocidas+="$l"$'
'
  done <<<"$usuarios"
  conocidas="$(sed '/^$/d' <<<"$conocidas" | sort -u)"

  # --- Las que hay de verdad en MySQL ---------------------------------------
  # Las tres fuentes tienen que salir de la MISMA máquina. Al trabajar contra un
  # servidor remoto, MySQL y los respaldos están allí: consultarlos en local
  # devolvería cero y el cruce diría cualquier cosa menos la verdad.
  local en_mysql=""
  if (( BC_HESTIA_REMOTO )); then
    en_mysql="$(bc_hestia_mysql_remoto | sort -u || true)"
    [[ -z "$en_mysql" ]] && bc_warn "no se pudo consultar MySQL en el servidor."
  elif bc_mysql_check >/dev/null 2>&1; then
    en_mysql="$(bc_mysql_databases 2>/dev/null | sort -u || true)"
  else
    bc_warn "no se pudo consultar MySQL: la comparación queda incompleta."
  fi

  # --- Las que están en el último respaldo ----------------------------------
  local en_respaldo=""
  if (( BC_HESTIA_REMOTO )); then
    en_respaldo="$(bc_hestia_respaldo_remoto | sort -u || true)"
  else
    local zip; zip="$(bc_backup_latest || true)"
    [[ -n "$zip" ]] && en_respaldo="$(unzip -Z1 "$zip" 2>/dev/null | awk -F/ 'NF>1{print $1}' | sort -u || true)"
  fi

  local n_con n_my
  n_con="$(grep -c . <<<"$conocidas" || true)"
  n_my="$(grep -c . <<<"$en_mysql" || true)"
  bc_log "HestiaCP conoce $n_con · en MySQL hay $n_my · en el último respaldo $(grep -c . <<<"$en_respaldo" || true)"
  echo

  # --- Cruce ----------------------------------------------------------------
  local filas; filas="$(mktemp)"
  printf 'BASE DE DATOS	HESTIACP	RESPALDO	SITUACIÓN
' > "$filas"
  local todas d hes res sit
  todas="$(printf '%s
%s
' "$conocidas" "$en_mysql" | sed '/^$/d' | sort -u)"
  local n_solo_bctl=0 n_sin=0 n_huerfana=0

  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    grep -qxF "$d" <<<"$conocidas"   && hes="sí" || hes="NO"
    grep -qxF "$d" <<<"$en_respaldo" && res="sí" || res="NO"

    if   [[ "$hes" == "NO" ]] && ! grep -qxF "$d" <<<"$en_mysql"; then
      sit="registro huérfano"; n_huerfana=$(( n_huerfana + 1 ))
    elif ! grep -qxF "$d" <<<"$en_mysql"; then
      sit="ya no existe en MySQL"; n_huerfana=$(( n_huerfana + 1 ))
    elif [[ "$res" == "NO" ]]; then
      sit="SIN RESPALDO"; n_sin=$(( n_sin + 1 ))
    elif [[ "$hes" == "NO" ]]; then
      sit="solo backupctl"; n_solo_bctl=$(( n_solo_bctl + 1 ))
    else
      sit="doble cobertura"
    fi
    printf '%s	%s	%s	%s
' "$d" "$hes" "$res" "$sit" >> "$filas"
  done <<<"$todas"

  bc_table < "$filas"; rm -f "$filas"
  echo

  # --- Qué significa cada cosa ----------------------------------------------
  bc_step "Cómo leer esto"
  bc_log "  doble cobertura   HestiaCP la respalda dentro de la cuenta Y backupctl aparte."
  bc_log "  solo backupctl    Se creó a mano en MySQL. HestiaCP NO la conoce, así que"
  bc_log "                    NO está en sus respaldos ni se recrea al restaurar la cuenta."
  bc_log "  SIN RESPALDO      Existe en MySQL y no está en el último respaldo. Grave."
  bc_log "  huérfana          Registrada o respaldada, pero ya no está en MySQL."
  echo

  if (( n_sin > 0 )); then
    bc_err "$n_sin bases SIN RESPALDO. Revisa EXCLUDE_DBS y lanza un respaldo."
  fi
  if (( n_solo_bctl > 0 )); then
    bc_warn "$n_solo_bctl bases que HestiaCP no conoce."
    bc_warn "AL MIGRAR: sus datos llegarán con backupctl, pero en el destino no"
    bc_warn "tendrán entrada en el panel ni usuario gestionado. Hay que darlas de"
    bc_warn "alta allí con  v-add-database  antes de apuntar la aplicación."
  fi
  (( n_sin == 0 && n_solo_bctl == 0 && n_huerfana == 0 )) && bc_ok "Todo cuadra."
  return 0
}

# =============================================================================
# ¿Dónde están mis claves?
# =============================================================================
# La pregunta que más importa y peor respondida suele estar. Se contesta con
# rutas concretas, no con explicaciones.
bc_hestia_donde() {
  bc_section "Dónde están tus claves"

  bc_log "backupctl NO inventa credenciales: guarda las que rescata del servidor."
  echo

  bc_step "1 · En el servidor (el original)"
  bc_log "        $HESTIA_DIR/data/users/*/restic.conf   descifra el repositorio"
  bc_log "        $BC_HESTIA_RCLONE_CONF   permite llegar a él"
  echo

  bc_step "2 · Rescatadas en este repositorio"
  local hay=0 f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    hay=1
    bc_ok "        $f   ($(bc_age_days "$f") días)"
  done < <( { find "$(bc_hestia_salida)" -maxdepth 1 \( -name 'Restic_Configs_*.txt' -o -name 'rclone_*.conf' \)               -printf '%T@ %p
' 2>/dev/null || true; } | sort -rn | cut -d' ' -f2- )
  if (( ! hay )); then
    bc_err "        NINGUNA. Rescátalas:  backupctl -p $BC_PROFILE hestia keys"
  fi
  echo

  bc_step "3 · Fuera de aquí"
  bc_warn "        Este repositorio vive en tu equipo. Si lo pierdes, pierdes las"
  bc_warn "        claves con él. Copia esos archivos a un gestor de contraseñas"
  bc_warn "        o a otra máquina."
  echo

  bc_step "Al desplegar en un servidor NUEVO"
  bc_log "        Si va a usar el MISMO destino S3, no hay que teclear nada:"
  bc_log "            backupctl -p <perfil> hestia rclone --desde-repo"
  bc_log "        instala allí el rclone.conf ya rescatado."
  bc_log ""
  bc_log "        Si va a un destino NUEVO, las claves salen del panel de tu"
  bc_log "        proveedor (Mega S4 → sección S4) y se introducen una vez con:"
  bc_log "            backupctl -p <perfil> hestia rclone"
}

# =============================================================================
# Reinstalar en un servidor el rclone.conf ya rescatado
# =============================================================================
# Cierra el ciclo: rescatar → repositorio → volver a poner en otra máquina.
# Sin esto, montar un servidor nuevo obligaría a ir a buscar las credenciales al
# panel del proveedor aunque ya las tuvieras guardadas.
bc_hestia_rclone_desde_repo() {
  local origen
  origen="$( { find "$(bc_hestia_salida)" -maxdepth 1 -name 'rclone_*.conf' -printf '%T@ %p
' 2>/dev/null || true; }              | sort -rn | head -1 | cut -d' ' -f2- )"
  [[ -n "$origen" ]] || bc_die "no hay ningún rclone.conf rescatado en $(bc_hestia_salida). Rescátalo antes desde un servidor que ya lo tenga: backupctl hestia keys"

  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Reinstalar la configuración de rclone guardada"
  bc_log "Origen: $origen  ($(bc_age_days "$origen") días)"
  bc_log "Remotos que contiene:"
  grep -oP '^\[\K[^]]+' "$origen" | sed 's/^/        /'
  bc_warn "Este archivo lleva tus claves de S3. Se instalará en el servidor con"
  bc_warn "permisos 600, guardando copia de lo que hubiera antes."

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha escrito nada."
    return 0
  fi
  bc_confirm "¿Instalarlo en $BC_HESTIA_RCLONE_CONF del servidor?" n     || { bc_log "Cancelado."; return 0; }

  # El directorio se calcula aquí, no en el servidor: anidar $( ) dentro de la
  # cadena entrecomillada que viaja por SSH obliga a un escapado frágil.
  local destino_dir; destino_dir="$(dirname "$BC_HESTIA_RCLONE_CONF")"

  bc_hestia_root_stdin "
    umask 077
    mkdir -p '$destino_dir'
    [ -f '$BC_HESTIA_RCLONE_CONF' ] && cp -a '$BC_HESTIA_RCLONE_CONF' '$BC_HESTIA_RCLONE_CONF.anterior'
    cat > '$BC_HESTIA_RCLONE_CONF'
    chmod 600 '$BC_HESTIA_RCLONE_CONF'
  " < "$origen" || bc_die "no se pudo escribir la configuración en el servidor."

  bc_ok "Instalado. Los remotos guardados ya funcionan en este servidor."
  bc_log "Comprueba uno con:  rclone lsd <remoto>:"
}

# =============================================================================
# Asistente completo
# =============================================================================
bc_hestia_setup() {
  bc_can_prompt || bc_die "el asistente necesita un terminal. Desde la web usa la pestaña HestiaCP."
  bc_section "Montar los respaldos incrementales de HestiaCP"
  bc_log "Cuatro pasos: remoto de rclone, host de respaldo, cron y rescate de claves."
  echo
  bc_hestia_rclone
  echo
  bc_hestia_restic
  echo
  bc_hestia_cron
  echo
  bc_hestia_keys
  echo
  bc_ok "Listo. Comprueba con:  backupctl hestia status"
}
