#!/usr/bin/env bash
# =============================================================================
# lib/remote.sh — ejecutar backupctl EN el servidor, desde tu equipo
# =============================================================================
# Cierra el círculo del "todo desde local": en lugar de abrir una sesión SSH y
# recordar la ruta, se antepone `remote` a cualquier orden y se ejecuta allí.
#
#   backupctl -p MiVPS remote status
#   backupctl -p MiVPS remote backup
#   backupctl -p MiVPS remote verify --restore-test tienda --with-data
#   backupctl -p MiVPS remote cron --install
#
# La contraseña, si hace falta, se pide una sola vez: se reutiliza la conexión
# maestra igual que en deploy.
#
# Las órdenes que necesitan root en el servidor (cron --install bajo HestiaCP,
# restic) se detectan y se lanzan con sudo automáticamente.
# =============================================================================

[[ -n "${BC_REMOTE_LOADED:-}" ]] && return 0
BC_REMOTE_LOADED=1

# Órdenes que en el servidor exigen privilegios de root
bc_remote_needs_root() {
  case "$1" in
    restic) return 0 ;;
    cron)   # solo --install y --remove, y solo si allí hay HestiaCP
            [[ "$*" == *--install* || "$*" == *--remove* ]] && return 0
            return 1 ;;
    *)      return 1 ;;
  esac
}

bc_remote_run() {
  local path="${BC_OPT_REMOTE_PATH:-$DEPLOY_PATH}"
  local target="${BC_OPT_TO:-}"

  if [[ -z "$target" ]]; then
    [[ -n "$DEPLOY_HOST" ]] || bc_die "no sé a qué servidor conectarme. Define DEPLOY_HOST en $BC_ENV_FILE o usa: backupctl remote --to usuario@servidor <orden>"
    target="$DEPLOY_USER@$DEPLOY_HOST"
  fi

  (( $# > 0 )) || bc_die "indica qué ejecutar. Ejemplo: backupctl -p $BC_PROFILE remote status"

  bc_require_cmd ssh
  bc_ssh_init "$target" || bc_die "no se pudo conectar a $target."
  trap 'bc_ssh_close' RETURN

  bc_ssh "test -x '$path/bin/backupctl'" 2>/dev/null \
    || bc_die "no hay backupctl en $target:$path. Despliégalo antes: backupctl -p $BC_PROFILE deploy $target"

  # Las órdenes se pasan citadas para que los argumentos con espacios lleguen
  # enteros al otro lado.
  local quoted; quoted="$(printf '%q ' "$@")"

  # ---------------------------------------------------------------------------
  # Se ejecuta como el DUEÑO de la instalación, no como quien entra por SSH.
  # ---------------------------------------------------------------------------
  # Al servidor se entra como root, porque los usuarios del panel de HestiaCP
  # tienen shell 'nologin'. Pero el cron corre como el usuario del panel: si el
  # respaldo lo genera root, el zip queda de root dentro del árbol de admin y
  # la retención del día siguiente NO puede borrarlo. El directorio se llena en
  # silencio hasta que se acaba el disco.
  #
  # Así que se mira de quién es la instalación y se ejecuta como él.
  local dueno=""
  if [[ "${DEPLOY_USER:-root}" == "root" ]]; then
    dueno="$(bc_ssh "stat -c %U '$path' 2>/dev/null" < /dev/null | tr -d '\r')" || dueno=""
    [[ "$dueno" == "root" ]] && dueno=""
  fi
  local como=""
  if [[ -n "$dueno" ]]; then
    # El `cd` NO es decorativo. sudo hereda el directorio de trabajo de quien
    # entró por SSH, que es /root, y admin no puede leerlo: `find` aborta con
    # «Failed to restore initial working directory» a mitad del empaquetado,
    # después de haber volcado las 81 bases. Se entra a la propia instalación,
    # que el dueño sí puede leer por definición.
    como="cd '$path' && sudo -u $dueno -H "
    bc_log "Se ejecutará como '$dueno', dueño de $path, para no dejar archivos de root."
  fi

  bc_section "$target · backupctl $*"

  local rc=0
  if bc_remote_needs_root "$@"; then
    bc_log "Esta orden necesita root en el servidor; se ejecutará con sudo."
    bc_ssh_sudo "'$path/bin/backupctl' $quoted" || rc=$?
  elif bc_is_tty; then
    # Con terminal se asigna uno para que se vea el progreso en vivo y para que
    # las confirmaciones del otro lado funcionen.
    bc_ssh_tty "$como'$path/bin/backupctl' $quoted" || rc=$?
  else
    bc_ssh "$como'$path/bin/backupctl' $quoted" || rc=$?
  fi

  echo
  if (( rc == 0 )); then
    bc_ok "Terminado en $target (código 0)."
  else
    bc_err "Terminó con código $rc en $target."
    BC_DELIBERATE_EXIT=1
  fi
  return $rc
}
