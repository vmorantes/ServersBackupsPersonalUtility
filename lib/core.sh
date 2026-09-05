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
  if ! bc_is_tty; then
    bc_debug "sin terminal, se usa el valor por defecto ($default): $prompt"
    [[ "$default" == "y" ]]
    return
  fi
  local hint="[s/N]"; [[ "$default" == "y" ]] && hint="[S/n]"
  local ans
  read -r -p "$(printf '%s%s%s %s ' "$BC_BLD" "$prompt" "$BC_RST" "$hint")" ans
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[sSyY]$ ]]
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
  exec 9>"$lock_file" || bc_die "no se pudo crear el bloqueo en $lock_file"
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
  mkdir -p "$(dirname "$log_file")"
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
