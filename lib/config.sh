#!/usr/bin/env bash
# =============================================================================
# lib/config.sh — descubrimiento, carga y validación de la configuración
# =============================================================================
# Un "perfil" es un servidor. Cada perfil es un directorio con un env.sh dentro.
# El mismo código sirve para todos: lo único que cambia entre servidores vive en
# ese env.sh. Por eso no hay copias del script por servidor.
#
# Rutas donde se buscan perfiles, en orden:
#   1. $BC_ROOT/env.sh          → instalación en un servidor (perfil "local")
#   2. $BC_ROOT/servers/*/env.sh
#   3. $BC_ROOT/*/env.sh        → disposición histórica del repositorio
# =============================================================================

[[ -n "${BC_CONFIG_LOADED:-}" ]] && return 0
BC_CONFIG_LOADED=1

# Lista los perfiles disponibles: una línea "nombre<TAB>ruta_del_env.sh"
bc_config_list() {
  local seen=""

  # Instalación en servidor: un único env.sh junto al tooling
  if [[ -f "$BC_ROOT/env.sh" ]]; then
    printf 'local\t%s\n' "$BC_ROOT/env.sh"
    seen="local"
  fi

  local d name
  for d in "$BC_ROOT"/servers/*/ "$BC_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    [[ -f "$d/env.sh" ]] || continue
    name="$(basename "$d")"
    # Directorios internos del proyecto que nunca son perfiles
    case "$name" in
      bin|lib|docs|config|site|.git|servers|node_modules) continue ;;
    esac
    [[ " $seen " == *" $name "* ]] && continue
    seen="$seen $name"
    printf '%s\t%s\n' "$name" "${d%/}/env.sh"
  done
}

bc_config_names() { bc_config_list | cut -f1; }

# Resuelve un nombre de perfil a la ruta de su env.sh
bc_config_path() {
  local want="$1" name path
  while IFS=$'\t' read -r name path; do
    [[ "$name" == "$want" ]] && { printf '%s' "$path"; return 0; }
  done < <(bc_config_list)
  return 1
}

# Si solo hay un perfil, se usa sin tener que nombrarlo. Con varios, hay que
# elegir: adivinar cuál es el servidor de producción sería peligroso.
bc_config_default_name() {
  local names count
  names="$(bc_config_names)"
  count="$(grep -c . <<<"$names" || true)"
  if (( count == 1 )); then printf '%s' "$names"; return 0; fi
  if grep -qx 'local' <<<"$names"; then printf 'local'; return 0; fi
  return 1
}

# -----------------------------------------------------------------------------
# Carga de un perfil
# -----------------------------------------------------------------------------
bc_config_load() {
  local want="${1:-}"
  local path

  if [[ -z "$want" ]]; then
    want="$(bc_config_default_name)" || bc_die \
      "hay varios perfiles y ninguno por defecto. Indica uno con -p <perfil>. Disponibles: $(bc_config_names | tr '\n' ' ')"
  fi

  if [[ -f "$want" ]]; then
    path="$want"; want="$(basename "$(dirname "$path")")"
  else
    path="$(bc_config_path "$want")" || bc_die \
      "perfil '$want' no encontrado. Disponibles: $(bc_config_names | tr '\n' ' ')"
  fi

  BC_PROFILE="$want"
  BC_PROFILE_DIR="$(cd "$(dirname "$path")" && pwd)"
  BC_ENV_FILE="$path"

  # shellcheck source=/dev/null
  source "$path" || bc_die "no se pudo cargar $path (revisa su sintaxis con: bash -n $path)"

  bc_config_apply_defaults
  bc_debug "perfil '$BC_PROFILE' cargado desde $BC_ENV_FILE"
}

# -----------------------------------------------------------------------------
# Valores por defecto
# -----------------------------------------------------------------------------
# Todo tiene un valor razonable: env.sh solo necesita declarar lo que se aparte
# de él. Así un perfil nuevo puede ser de tres líneas.
bc_config_apply_defaults() {
  USER_NAME="${USER_NAME:-$(id -un)}"
  SCRIPTS_DIR="${SCRIPTS_DIR:-$BC_PROFILE_DIR}"

  MYSQL_USER="${MYSQL_USER:-}"
  MYSQL_PASS="${MYSQL_PASS:-}"
  MYSQL_HOST="${MYSQL_HOST:-}"
  MYSQL_PORT="${MYSQL_PORT:-}"
  MYSQL_SOCKET="${MYSQL_SOCKET:-}"
  MYSQL_CHARSET="${MYSQL_CHARSET:-utf8mb4}"

  EXCLUDE_DBS="${EXCLUDE_DBS:-('information_schema','performance_schema','mysql','sys','phpmyadmin')}"

  BACKUP_OUTPUT_DIR="${BACKUP_OUTPUT_DIR:-$SCRIPTS_DIR/output/mysql_backups}"
  BACKUP_WORK_DIR="${BACKUP_WORK_DIR:-$SCRIPTS_DIR/output}"
  HESTIA_OUTPUT_DIR="${HESTIA_OUTPUT_DIR:-$SCRIPTS_DIR/output/HestiaCP}"
  LOG_DIR="${LOG_DIR:-$SCRIPTS_DIR/logs}"

  BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
  LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
  RESTIC_RETENTION_DAYS="${RESTIC_RETENTION_DAYS:-90}"
  BACKUP_KEEP_MIN="${BACKUP_KEEP_MIN:-3}"

  MIN_FREE_MB="${MIN_FREE_MB:-2048}"
  # Margen sobre el tamaño de las BD: el volcado sin comprimir ocupa más que
  # los datos en disco, así que se exige espacio para ese factor.
  DISK_SAFETY_FACTOR="${DISK_SAFETY_FACTOR:-2}"

  NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"
  NOTIFY_COMMAND="${NOTIFY_COMMAND:-}"
  HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"

  HESTIA_DIR="${HESTIA_DIR:-/usr/local/hestia}"

  # Destino para `backupctl deploy` y `backupctl migrate`
  DEPLOY_HOST="${DEPLOY_HOST:-}"
  # Quien abre la sesión SSH. Por defecto root: en HestiaCP los usuarios del
  # panel NO tienen consola —su shell es nologin—, así que no se puede entrar
  # como ellos. Además las órdenes v-* exigen root.
  # USER_NAME es otra cosa: el usuario de HestiaCP dueño de la instalación.
  DEPLOY_USER="${DEPLOY_USER:-root}"
  DEPLOY_PATH="${DEPLOY_PATH:-/home/$USER_NAME/scripts}"
  # Usuarios de HestiaCP cuyos respaldos nos interesan. Vacío = todos.
  HESTIA_USERS="${HESTIA_USERS:-}"
}

# -----------------------------------------------------------------------------
# Validación
# -----------------------------------------------------------------------------
# Devuelve 0 si la configuración es utilizable. Los problemas se informan pero
# solo los que impiden trabajar hacen fallar.
bc_config_check() {
  local fatal=0

  [[ -n "$MYSQL_USER" ]] || { bc_err "MYSQL_USER está vacío en $BC_ENV_FILE"; fatal=1; }

  local d
  for d in "$BACKUP_OUTPUT_DIR" "$BACKUP_WORK_DIR" "$LOG_DIR"; do
    if [[ -e "$d" && ! -w "$d" ]]; then
      bc_err "sin permiso de escritura en $d"; fatal=1
    fi
  done

  local n
  for n in BACKUP_RETENTION_DAYS LOG_RETENTION_DAYS BACKUP_KEEP_MIN MIN_FREE_MB; do
    [[ "${!n}" =~ ^[0-9]+$ ]] || { bc_err "$n debe ser un número entero (vale '${!n}')"; fatal=1; }
  done

  if (( BACKUP_KEEP_MIN < 1 )); then
    bc_warn "BACKUP_KEEP_MIN=0: la retención podría dejarte sin ningún respaldo."
  fi

  if [[ -z "$NOTIFY_EMAIL$NOTIFY_COMMAND$HEALTHCHECK_URL" ]]; then
    bc_warn "no hay ningún aviso configurado: un fallo bajo cron pasaría inadvertido."
  fi

  return $fatal
}

# -----------------------------------------------------------------------------
# Cambiar un valor del env.sh sin abrir un editor
# -----------------------------------------------------------------------------
# La interfaz web tiene que poder corregir un dato suelto —el usuario de SSH,
# por ejemplo— sin obligar a nadie a editar un archivo de configuración a mano.
# Se sustituye la línea si existe y se añade si no, validando la sintaxis antes
# de tocar el archivo bueno.
bc_config_set() {
  local clave="$1" valor="$2"
  [[ "$clave" =~ ^[A-Z_][A-Z0-9_]*$ ]] || { bc_err "clave no válida: $clave"; return 1; }
  [[ -f "$BC_ENV_FILE" ]] || { bc_err "no existe $BC_ENV_FILE"; return 1; }

  local tmp; tmp="$(mktemp)"
  if grep -qE "^[[:space:]]*export[[:space:]]+$clave=" "$BC_ENV_FILE"; then
    awk -v k="$clave" -v v="$valor" '
      $0 ~ "^[[:space:]]*export[[:space:]]+" k "=" { print "export " k "="" v """; next }
      { print }' "$BC_ENV_FILE" > "$tmp"
  else
    cat "$BC_ENV_FILE" > "$tmp"
    printf '
export %s="%s"
' "$clave" "$valor" >> "$tmp"
  fi

  if ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"; bc_err "el cambio dejaría el env.sh con errores de sintaxis."; return 1
  fi
  cp -a "$BC_ENV_FILE" "$BC_ENV_FILE.anterior" 2>/dev/null || true
  mv "$tmp" "$BC_ENV_FILE"
  bc_ok "$clave = $valor   (guardado en $(basename "$BC_ENV_FILE"))"
}

# Muestra la configuración efectiva (valores por defecto ya aplicados)
bc_config_show() {
  local show_secrets="${1:-0}"
  local pass_display="(vacía)"
  if [[ -n "$MYSQL_PASS" ]]; then
    if [[ "$show_secrets" == "1" ]]; then pass_display="$MYSQL_PASS"
    else pass_display="(definida, ${#MYSQL_PASS} caracteres)"; fi
  fi

  {
    printf 'Perfil\t%s\n' "$BC_PROFILE"
    printf 'Archivo\t%s\n' "$BC_ENV_FILE"
    printf '\t\n'
    printf 'USER_NAME\t%s\n' "$USER_NAME"
    printf 'SCRIPTS_DIR\t%s\n' "$SCRIPTS_DIR"
    printf '\t\n'
    printf 'MYSQL_USER\t%s\n' "$MYSQL_USER"
    printf 'MYSQL_PASS\t%s\n' "$pass_display"
    printf 'MYSQL_HOST\t%s\n' "${MYSQL_HOST:-(socket local)}"
    printf 'MYSQL_PORT\t%s\n' "${MYSQL_PORT:-(por defecto)}"
    printf 'MYSQL_CHARSET\t%s\n' "$MYSQL_CHARSET"
    printf 'EXCLUDE_DBS\t%s\n' "$EXCLUDE_DBS"
    printf '\t\n'
    printf 'BACKUP_OUTPUT_DIR\t%s\n' "$BACKUP_OUTPUT_DIR"
    printf 'BACKUP_WORK_DIR\t%s\n' "$BACKUP_WORK_DIR"
    printf 'HESTIA_OUTPUT_DIR\t%s\n' "$HESTIA_OUTPUT_DIR"
    printf 'LOG_DIR\t%s\n' "$LOG_DIR"
    printf '\t\n'
    printf 'BACKUP_RETENTION_DAYS\t%s\n' "$BACKUP_RETENTION_DAYS"
    printf 'LOG_RETENTION_DAYS\t%s\n' "$LOG_RETENTION_DAYS"
    printf 'RESTIC_RETENTION_DAYS\t%s\n' "$RESTIC_RETENTION_DAYS"
    printf 'BACKUP_KEEP_MIN\t%s\n' "$BACKUP_KEEP_MIN"
    printf 'MIN_FREE_MB\t%s\n' "$MIN_FREE_MB"
    printf '\t\n'
    printf 'NOTIFY_EMAIL\t%s\n' "${NOTIFY_EMAIL:-(sin configurar)}"
    printf 'NOTIFY_COMMAND\t%s\n' "${NOTIFY_COMMAND:-(sin configurar)}"
    printf 'HEALTHCHECK_URL\t%s\n' "${HEALTHCHECK_URL:-(sin configurar)}"
    printf '\t\n'
    printf 'HESTIA_DIR\t%s\n' "$HESTIA_DIR"
    printf 'DEPLOY_HOST\t%s\n' "${DEPLOY_HOST:-(sin configurar)}"
    printf 'DEPLOY_USER\t%s\n' "$DEPLOY_USER"
    printf 'DEPLOY_PATH\t%s\n' "$DEPLOY_PATH"
  } | bc_table
}
