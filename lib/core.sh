#!/usr/bin/env bash
# =============================================================================
# lib/core.sh — utilidades comunes: registro, errores, formato, bloqueos
# =============================================================================
# Lo cargan todos los demás módulos. No ejecuta nada por sí mismo.
# =============================================================================

# Evita cargar dos veces si varios módulos hacen source
[[ -n "${BC_CORE_LOADED:-}" ]] && return 0
BC_CORE_LOADED=1

# -----------------------------------------------------------------------------
# Colores: solo si la salida es un terminal. Bajo cron o redirigido a archivo se
# desactivan solos, para que los logs no se llenen de códigos de escape.
# -----------------------------------------------------------------------------
if [[ -t 1 && "${BC_NO_COLOR:-0}" != "1" ]]; then
  BC_RED=$'\033[31m'; BC_GRN=$'\033[32m'; BC_YEL=$'\033[33m'
  BC_BLU=$'\033[34m'; BC_CYA=$'\033[36m'; BC_DIM=$'\033[2m'
  BC_BLD=$'\033[1m'; BC_RST=$'\033[0m'
else
  BC_RED=""; BC_GRN=""; BC_YEL=""; BC_BLU=""; BC_CYA=""
  BC_DIM=""; BC_BLD=""; BC_RST=""
fi

# Contadores globales del proceso; los consulta el resumen final
BC_WARN_COUNT=0
BC_ERR_COUNT=0
# Marca que una salida fue decidida por nosotros (die/exit controlado) para que
# el trap ERR no informe de un "fallo no controlado" que sí estaba controlado.
BC_DELIBERATE_EXIT=0

bc_ts() { date '+%Y-%m-%d %H:%M:%S'; }

bc_log()  { printf '%s %s[INFO ]%s %s\n' "$(bc_ts)" "$BC_DIM"  "$BC_RST" "$*"; }
bc_ok()   { printf '%s %s[  OK ]%s %s\n' "$(bc_ts)" "$BC_GRN"  "$BC_RST" "$*"; }
bc_step() { printf '%s %s[ >>  ]%s %s%s%s\n' "$(bc_ts)" "$BC_CYA" "$BC_RST" "$BC_BLD" "$*" "$BC_RST"; }
bc_warn() { BC_WARN_COUNT=$((BC_WARN_COUNT+1)); printf '%s %s[AVISO]%s %s\n' "$(bc_ts)" "$BC_YEL" "$BC_RST" "$*"; }
bc_err()  { BC_ERR_COUNT=$((BC_ERR_COUNT+1));  printf '%s %s[ERROR]%s %s\n' "$(bc_ts)" "$BC_RED" "$BC_RST" "$*" >&2; }
bc_die()  { bc_err "$*"; BC_DELIBERATE_EXIT=1; exit "${2:-2}"; }

# -----------------------------------------------------------------------------
# Registro de limpieza (ADR 0012)
# -----------------------------------------------------------------------------
# bc_die y la señal INT/TERM salen con `exit`, no con `return`: un
# `trap … RETURN` puesto dentro de la función que crea un temporal (o pisa
# algo remoto) nunca llega a dispararse en esos casos. Este registro es lo que
# SÍ corre siempre, porque lo ejecuta bc_cleanup_all desde el `trap … EXIT` de
# bin/backupctl (52), que no se salta nunca.
#
# Cada módulo registra la limpieza EN CUANTO crea lo que habrá que deshacer,
# antes de cualquier operación que pueda fallar, y en el camino normal la
# ejecuta con bc_cleanup_run (el trap … RETURN de siempre puede quedarse,
# llamando a bc_cleanup_run en vez de hacer el rm -rf a mano). Las órdenes se
# guardan como TEXTO y se ejecutan con `eval` en este mismo proceso —nunca en
# una subshell—, así que una función definida en el módulo (bc_verify_drop_scratch,
# por ejemplo) sigue pudiendo nombrarse en el texto registrado.
#
# Deben ser idempotentes: con INT/TERM a mitad de una limpieza, o si el mismo
# camino normal también llama a bc_cleanup_run, pueden llegar a "ejecutarse"
# dos veces (la segunda no encuentra la clave y no hace nada).
#
# OJO con las subshells: lo que se registra dentro de "$(...)" o de una
# tubería vive en un proceso hijo y se pierde con él; una función que cree
# algo ahí necesita resolverlo por su cuenta, no con este registro.
declare -ga BC_CLEANUP_KEYS=()
declare -gA BC_CLEANUP_CMDS=()

# Apunta (o sustituye) una limpieza pendiente bajo <clave>. Si la clave ya
# existía, la orden se sustituye pero NO se duplica en el orden de ejecución.
bc_cleanup_register() {
  local clave="$1" orden="$2"
  [[ -n "${BC_CLEANUP_CMDS[$clave]+x}" ]] || BC_CLEANUP_KEYS+=("$clave")
  BC_CLEANUP_CMDS["$clave"]="$orden"
}

# Ejecuta ya la limpieza de <clave>, si existe, y la quita del registro. NUNCA
# en una subshell: bc_verify_drop_scratch, por ejemplo, tiene que poder dejar
# BC_SCRATCH_DB="" en ESTE proceso, no en uno que desaparece al terminar.
bc_cleanup_run() {
  local clave="$1"
  [[ -n "${BC_CLEANUP_CMDS[$clave]+x}" ]] || return 0
  local orden="${BC_CLEANUP_CMDS[$clave]}"
  unset 'BC_CLEANUP_CMDS[$clave]'
  bc_cleanup_quitar_clave "$clave"
  bc_cleanup_eval "$orden"
}

# Evalúa una orden de limpieza sin que su fallo interrumpa el proceso (set -e
# global de bin/backupctl) ni dispare el trap ERR como "fallo no controlado":
# una limpieza que falla es una limpieza a medias, no un bug. Se restauran
# los dos exactamente como estaban, nunca con una subshell de por medio.
#
# Nombres de variable con prefijo _bc_cleanup_ a propósito: la orden que se
# evalúa es texto de otro módulo y no debe poder pisar estas locales.
#
# "Restaurar exactamente como estaba" incluye el propio errexit: un `set -e`
# incondicional al final impondría errexit sobre quien llamó con `set +e`
# (bc_cleanup_all, por ejemplo, hace `set +e` antes de bc_cleanup_pending) en
# vez de devolverle su estado. Se guarda con `[[ $- == *e* ]]` (igual que se
# guarda el trap ERR) y se reactiva SOLO si estaba activo.
#
# Termina con `return 0` explícito: sin un trap ERR previo (fuera de
# bin/backupctl, que siempre lo pone, esto puede pasar en una prueba), la
# última línea de abajo devuelve 1 con toda normalidad (su lado izquierdo es
# falso) y, sin el return, ESE 1 se convertiría en el código de salida de
# bc_cleanup_eval — y de bc_cleanup_run, que termina llamándola — activando
# el errexit que se acaba de restaurar por algo que no fue ningún fallo.
bc_cleanup_eval() {
  local _bc_cleanup_orden="$1" _bc_cleanup_previo _bc_cleanup_errexit=0
  [[ $- == *e* ]] && _bc_cleanup_errexit=1
  _bc_cleanup_previo="$(trap -p ERR)"
  trap - ERR
  set +e
  eval "$_bc_cleanup_orden"
  (( _bc_cleanup_errexit )) && set -e
  [[ -n "$_bc_cleanup_previo" ]] && eval "$_bc_cleanup_previo"
  return 0
}

# Quita <clave> del registro SIN ejecutar su limpieza (para cuando ya no hace
# falta deshacer nada: por ejemplo, tras publicar con éxito lo que la
# limpieza habría borrado — restic.sh, tras el mv final).
bc_cleanup_forget() {
  local clave="$1"
  [[ -n "${BC_CLEANUP_CMDS[$clave]+x}" ]] || return 0
  unset 'BC_CLEANUP_CMDS[$clave]'
  bc_cleanup_quitar_clave "$clave"
}

bc_cleanup_quitar_clave() {
  local clave="$1" k restantes=()
  for k in "${BC_CLEANUP_KEYS[@]}"; do
    [[ "$k" == "$clave" ]] || restantes+=("$k")
  done
  BC_CLEANUP_KEYS=("${restantes[@]}")
}

# Ejecuta TODAS las limpiezas pendientes, en orden INVERSO al de registro (lo
# último creado es lo primero en deshacerse: si una limpieza remota depende de
# que la conexión ssh siga abierta, y esta se registró antes que la conexión
# se cerrara, el orden inverso la ejecuta primero). Cada una en su propio
# `set +e`: que una falle no impide las siguientes. Vacía el registro entero.
bc_cleanup_pending() {
  local i clave orden
  for (( i = ${#BC_CLEANUP_KEYS[@]} - 1; i >= 0; i-- )); do
    clave="${BC_CLEANUP_KEYS[$i]}"
    orden="${BC_CLEANUP_CMDS[$clave]:-}"
    [[ -n "$orden" ]] && bc_cleanup_eval "$orden"
  done
  BC_CLEANUP_KEYS=()
  BC_CLEANUP_CMDS=()
}

# Solo se ve con BC_DEBUG=1. Útil para depurar sin ensuciar el uso normal.
bc_debug() { [[ "${BC_DEBUG:-0}" == "1" ]] || return 0; printf '%s %s[DEBUG]%s %s\n' "$(bc_ts)" "$BC_BLU" "$BC_RST" "$*" >&2; }

# Encabezado de sección, para que los logs largos sean legibles
bc_section() {
  printf '\n%s%s== %s ==%s\n' "$BC_BLD" "$BC_CYA" "$*" "$BC_RST"
}

# -----------------------------------------------------------------------------
# Utilidades
# -----------------------------------------------------------------------------

# ¿Estamos en un terminal interactivo? Determina si se puede preguntar al usuario
# o si hay que asumir valores por defecto (modo desatendido).
bc_is_tty() { [[ -t 0 && -t 1 ]]; }

# ¿Se puede preguntar algo por teclado?
#
# Comprueba SOLO la entrada, no la salida. La diferencia importa: las funciones
# que preguntan se invocan dentro de $(...), donde stdout es una tubería y no un
# terminal. Usar bc_is_tty aquí haría que nunca llegaran a preguntar y
# devolvieran siempre el valor por defecto en silencio.
bc_can_prompt() { [[ -t 0 ]]; }

# Comprueba que existan las órdenes indicadas. Falla con un mensaje que dice
# exactamente qué falta, en lugar de un "command not found" a mitad del proceso.
bc_require_cmd() {
  local missing=()
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if (( ${#missing[@]} > 0 )); then
    bc_die "faltan órdenes necesarias: ${missing[*]}. Instálalas y reinténtalo."
  fi
}

bc_has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Confirmación. En modo desatendido (--yes o sin terminal) devuelve el valor por
# defecto sin bloquearse, que es lo que permite usar los mismos módulos desde
# cron y desde la TUI.
bc_confirm() {
  local prompt="$1" default="${2:-n}"
  if [[ "${BC_ASSUME_YES:-0}" == "1" ]]; then
    bc_debug "confirmación automática (--yes): $prompt"
    return 0
  fi
  if ! bc_can_prompt; then
    bc_debug "sin terminal, se usa el valor por defecto ($default): $prompt"
    [[ "$default" == "y" ]]
    return
  fi
  local hint="[s/N]"; [[ "$default" == "y" ]] && hint="[S/n]"
  local ans
  # El prompt va a stderr: bc_confirm puede llamarse dentro de $(...)
  printf '%s%s%s %s ' "$BC_BLD" "$prompt" "$BC_RST" "$hint" >&2
  read -r ans
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[sSyY]$ ]]
}

# -----------------------------------------------------------------------------
# Preguntas interactivas
# -----------------------------------------------------------------------------
# Pregunta visible, con valor por defecto.
bc_ask() {
  local prompt="$1" default="${2:-}" v
  if ! bc_can_prompt; then printf '%s' "$default"; return 0; fi
  if [[ -n "$default" ]]; then
    printf '%s%s%s [%s]: ' "$BC_BLD" "$prompt" "$BC_RST" "$default" >&2
  else
    printf '%s%s%s: ' "$BC_BLD" "$prompt" "$BC_RST" >&2
  fi
  read -r v
  printf '%s' "${v:-$default}"
}

# Pregunta oculta, para contraseñas. Nunca se muestra ni queda en el historial.
bc_ask_secret() {
  local prompt="$1" v
  bc_can_prompt || return 1
  printf '%s%s%s: ' "$BC_BLD" "$prompt" "$BC_RST" >&2
  read -rs v
  printf '\n' >&2
  printf '%s' "$v"
}

# Contraseña aleatoria fuerte. Se limita a caracteres alfanuméricos a propósito:
# evita cualquier problema de citado al pasar por SQL, por shell y por env.sh.
#
# Se lee en bloques acotados en lugar de `tr < /dev/urandom | head -c N`: ahí
# head cierra la tubería al llegar a N, tr muere con SIGPIPE y, con pipefail,
# eso aborta el programa entero.
bc_gen_password() {
  local n="${1:-28}" out="" chunk
  while (( ${#out} < n )); do
    chunk="$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' || true)"
    out="$out$chunk"
  done
  printf '%s' "${out:0:n}"
}

# Tamaño legible a partir de bytes.
#
# Todo el formato se hace dentro de awk con LC_ALL=C a propósito: si se deja que
# awk produzca el número y printf(1) de bash lo reformatee, en un locale con
# coma decimal (es_ES) bash rechaza el "38.3" que devuelve awk. Una sola llamada
# evita el desajuste de separador decimal entre ambos.
bc_human_size() {
  LC_ALL=C awk -v b="${1:-0}" 'BEGIN{
    if      (b >= 1073741824) printf "%.1fG", b/1073741824;
    else if (b >= 1048576)    printf "%.1fM", b/1048576;
    else if (b >= 1024)       printf "%.1fK", b/1024;
    else                      printf "%dB",   b;
  }'
}

# Antigüedad de un archivo en días
bc_age_days() {
  local f="$1"
  [[ -e "$f" ]] || { echo "-1"; return; }
  echo $(( ( $(date +%s) - $(stat -c %Y "$f") ) / 86400 ))
}

# Duración legible a partir de segundos
bc_duration() {
  local s="${1:-0}"
  if   (( s >= 3600 )); then printf '%dh %dm %ds' $((s/3600)) $(((s%3600)/60)) $((s%60))
  elif (( s >= 60   )); then printf '%dm %ds' $((s/60)) $((s%60))
  else printf '%ds' "$s"; fi
}

# -----------------------------------------------------------------------------
# Bloqueo por nombre de operación
# -----------------------------------------------------------------------------
# Impide que dos respaldos se pisen. Sin esto, dos ejecuciones solapadas
# compiten por disco y CPU y pueden dejar el servidor sin espacio a mitad.
bc_lock_acquire() {
  local name="$1" dir="${2:-${TMPDIR:-/tmp}}"
  local lock_file="$dir/.backupctl.${name}.lock"
  # El descriptor 9 se mantiene abierto mientras viva el proceso; al terminar,
  # el sistema libera el bloqueo solo, incluso si el script muere de golpe.
  # Se comprueba el DIRECTORIO, no el archivo. Con `exec 9>fichero` el error de
  # redirección lo imprime el propio shell antes de que podamos capturarlo, y
  # silenciarlo con 2>/dev/null junto al exec redirigiría stderr de todo el
  # proceso, no solo de esa orden.
  if [[ ! -d "$dir" || ! -w "$dir" ]]; then
    bc_err "no se pudo crear el bloqueo en $lock_file"
    bc_err "El directorio no existe o no es escribible. Si este perfil describe"
    bc_err "otro servidor, la orden que buscas es: backupctl -p $BC_PROFILE remote <orden>"
    BC_DELIBERATE_EXIT=1
    exit 2
  fi
  exec 9>"$lock_file"
  if ! flock -n 9; then
    bc_die "ya hay una operación '$name' en curso (bloqueo: $lock_file)."
  fi
  bc_debug "bloqueo adquirido: $lock_file"
}

# -----------------------------------------------------------------------------
# Registro a archivo
# -----------------------------------------------------------------------------
# Con terminal: se ve por pantalla Y se guarda. Sin terminal (cron): solo se
# guarda, para que cron no envíe un correo diario con la salida completa. Los
# fallos se comunican por el código de salida y por los avisos configurados.
bc_start_logging() {
  local log_file="$1"
  # Si el directorio de logs no se puede crear —un perfil que describe otra
  # máquina, permisos ajenos—, se sigue sin archivo en lugar de abortar con un
  # "fallo no controlado" que no explica nada. El problema de fondo saldrá a la
  # luz igualmente, y con un mensaje que sí se entiende.
  if ! mkdir -p "$(dirname "$log_file")" 2>/dev/null; then
    bc_warn "no se pudo crear $(dirname "$log_file"): esta ejecución no se registrará en un archivo."
    bc_warn "Si este perfil describe otro servidor, la orden que buscas es 'remote'."
    BC_LOG_FILE=""
    return 0
  fi
  BC_LOG_FILE="$log_file"
  if [[ -t 1 ]]; then
    exec > >(tee -a "$log_file") 2>&1
  else
    exec >>"$log_file" 2>&1
  fi
}

# -----------------------------------------------------------------------------
# Tablas alineadas sin depender de column(1)
# -----------------------------------------------------------------------------
# Entrada: líneas con campos separados por TAB. Se usa en `list`, `status`, etc.
bc_table() {
  if bc_has_cmd column; then
    column -t -s $'\t'
  else
    awk -F'\t' '{for(i=1;i<=NF;i++) printf "%-24s", $i; print ""}'
  fi
}
