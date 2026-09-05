#!/usr/bin/env bash
# =============================================================================
# lib/deploy.sh — instalar o actualizar backupctl en un servidor
# =============================================================================
# Todo se hace desde tu equipo. En el servidor no hay que preparar nada a mano:
# deploy comprueba lo que falta, ofrece instalarlo y crea los directorios.
#
# AUTENTICACIÓN
#   Funciona con clave o con contraseña. Se abre UNA conexión maestra y todo lo
#   demás viaja por ella, así que la contraseña se pide una sola vez aunque el
#   despliegue haga ocho conexiones. Ver lib/ssh.sh.
#
# USUARIO QUE CONECTA vs USUARIO PROPIETARIO
#   No hacen falta ser el mismo. En HestiaCP muchos usuarios se crean con
#   'nologin' y no pueden entrar por SSH; en ese caso se conecta con uno que sí
#   tenga shell (admin o root) y se instala en el home del otro, ajustando el
#   propietario al final.
#
#     DEPLOY_USER  quién se conecta por SSH   (necesita shell)
#     USER_NAME    de quién es la instalación (no necesita shell)
# =============================================================================

[[ -n "${BC_DEPLOY_LOADED:-}" ]] && return 0
BC_DEPLOY_LOADED=1

# Traduce nombres de orden a nombres de paquete de Debian/Ubuntu. Sugerir
# "apt install find" sería un consejo inútil: el paquete se llama findutils.
bc_deploy_packages() {
  local c pkgs=""
  for c in $1; do
    case "$c" in
      mysql|mysqldump) pkgs="$pkgs mariadb-client" ;;
      find)            pkgs="$pkgs findutils" ;;
      sha256sum)       pkgs="$pkgs coreutils" ;;
      flock)           pkgs="$pkgs util-linux" ;;
      *)               pkgs="$pkgs $c" ;;
    esac
  done
  tr ' ' '\n' <<<"$pkgs" | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

bc_deploy_run() {
  local target="${1:-}"
  local path="${BC_OPT_REMOTE_PATH:-$DEPLOY_PATH}"
  BC_DEPLOY_SKIP_ENV=0

  if [[ -z "$target" ]]; then
    [[ -n "$DEPLOY_HOST" ]] || bc_die "indica el destino: backupctl deploy usuario@servidor (o define DEPLOY_HOST en $BC_ENV_FILE)"
    target="$DEPLOY_USER@$DEPLOY_HOST"
  fi

  bc_require_cmd rsync ssh
  bc_section "Despliegue en $target:$path"

  # --- Conexión única --------------------------------------------------------
  # A partir de aquí ninguna orden vuelve a pedir contraseña.
  bc_log "Conectando (si hace falta contraseña, se pedirá una sola vez)..."
  bc_ssh_init "$target" || bc_die "no se pudo establecer la conexión."
  trap 'bc_ssh_close' RETURN

  local host_info remote_user
  host_info="$(bc_ssh 'hostname -f 2>/dev/null || hostname')"
  remote_user="$(bc_ssh 'id -un')"
  bc_ok "conectado a $host_info como '$remote_user'"
  bc_log "  $(bc_ssh 'bash --version | head -1')"

  # --- Dependencias ----------------------------------------------------------
  bc_log "Comprobando las dependencias del servidor..."
  local remote_missing
  remote_missing="$(bc_ssh '
    faltan=""
    for c in bash rsync mysql mysqldump gzip zip unzip find sha256sum flock; do
      command -v "$c" >/dev/null 2>&1 || faltan="$faltan $c"
    done
    echo "$faltan"' 2>/dev/null || echo "?")"

  if [[ "$remote_missing" == "?" ]]; then
    bc_warn "no se pudieron comprobar las dependencias del destino."
  elif [[ -n "${remote_missing// /}" ]]; then
    local pkgs; pkgs="$(bc_deploy_packages "$remote_missing")"
    bc_warn "faltan órdenes en el servidor:${remote_missing}"

    if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
      bc_log "Simulación: se ofrecería instalar: $pkgs"
    elif bc_confirm "¿Instalarlas ahora en el servidor (apt install $pkgs)?" y; then
      bc_log "Instalando en el servidor..."
      if bc_ssh_sudo "apt-get update -qq && apt-get install -y -qq $pkgs"; then
        bc_ok "paquetes instalados."
      else
        bc_err "no se pudieron instalar. Hazlo a mano en el servidor:"
        bc_err "    sudo apt update && sudo apt install -y $pkgs"
        [[ "$remote_missing" == *rsync* ]] && bc_die "sin rsync no se puede desplegar."
        bc_confirm "¿Continuar de todas formas?" n || bc_die "cancelado."
      fi
    else
      [[ "$remote_missing" == *rsync* ]] && bc_die "sin rsync en el destino no se puede desplegar."
      bc_warn "El respaldo no funcionará hasta instalarlas: sudo apt install -y $pkgs"
      bc_confirm "¿Desplegar de todas formas?" n || bc_die "cancelado."
    fi
  else
    bc_ok "todas las dependencias están presentes en el servidor."
  fi

  # --- env.sh: comparar antes de sobrescribir --------------------------------
  # Es el único archivo del despliegue que puede llevar cambios hechos
  # directamente en el servidor. Sobrescribirlo en silencio destruiría un ajuste
  # que quizá era el bueno. Se comprueba ANTES de copiar nada.
  bc_log "Comparando la configuración con la del servidor..."
  local remote_env; remote_env="$(mktemp)"
  if bc_ssh "cat '$path/env.sh'" > "$remote_env" 2>/dev/null && [[ -s "$remote_env" ]]; then
    if diff -q "$BC_ENV_FILE" "$remote_env" >/dev/null 2>&1; then
      bc_ok "el env.sh del servidor ya es idéntico: no hay nada que cambiar."
    else
      bc_warn "el env.sh del SERVIDOR difiere del que vas a subir:"
      echo
      diff -u "$remote_env" "$BC_ENV_FILE" \
        --label "servidor (se PERDERÁ): $target:$path/env.sh" \
        --label "repositorio (se sube): $BC_ENV_FILE" | sed 's/^/    /' || true
      echo
      bc_warn "Si el bueno es el del servidor, cancela y tráetelo antes:"
      bc_warn "    backupctl -p $BC_PROFILE pull $target"
      if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
        bc_log "Simulación: el env.sh del servidor NO se tocaría."
        BC_DEPLOY_SKIP_ENV=1
      elif bc_confirm "¿Sobrescribir el env.sh del servidor con el del repositorio?" n; then
        bc_ssh "cp '$path/env.sh' '$path/env.sh.anterior'" 2>/dev/null \
          && bc_log "La versión del servidor quedará como env.sh.anterior"
      else
        bc_warn "NO se tocará el env.sh del servidor. Solo se actualizará el código."
        BC_DEPLOY_SKIP_ENV=1
      fi
    fi
  else
    bc_log "el servidor todavía no tiene env.sh: se creará."
  fi
  rm -f "$remote_env"

  # --- Ensayo ----------------------------------------------------------------
  local files=(bin lib)
  bc_log "Se copiarán: ${files[*]} + env.sh del perfil '$BC_PROFILE'"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_log "Simulación (--dry-run):"
    local preview rc=0
    preview="$(bc_rsync -avn --delete \
      --exclude '.git' --exclude 'output' --exclude 'logs' \
      "${files[@]/#/$BC_ROOT/}" "$target:$path/" 2>&1)" || rc=$?
    sed 's/^/        /' <<<"$preview"
    (( rc == 0 )) || bc_die "rsync no pudo hablar con el destino (código $rc)."
    bc_ok "Nada se ha copiado."
    return 0
  fi

  bc_confirm "¿Copiar backupctl a $target:$path?" y || { bc_log "Cancelado."; return 0; }

  # --- Crear lo que haga falta -----------------------------------------------
  bc_log "Preparando los directorios en el servidor..."
  if ! bc_ssh "mkdir -p '$path'/{logs,output}" 2>/dev/null; then
    # El home del propietario puede no ser escribible por quien conecta
    bc_warn "no se pudieron crear como '$remote_user'; se intenta con permisos de root..."
    bc_ssh_sudo "mkdir -p '$path'/{logs,output}" \
      || bc_die "no se pudieron crear los directorios en $path."
    bc_ssh_sudo "chown -R $USER_NAME:$USER_NAME '$path'" 2>/dev/null || true
  fi

  # --- Copia -----------------------------------------------------------------
  bc_log "Copiando el tooling..."
  bc_rsync -az --delete \
    --exclude '.git' --exclude 'output' --exclude 'logs' \
    "${files[@]/#/$BC_ROOT/}" "$target:$path/" \
    || bc_die "falló la copia de bin/ y lib/."

  if [[ "${BC_DEPLOY_SKIP_ENV:-0}" == "1" ]]; then
    bc_log "env.sh: se conserva el del servidor (decidido antes de copiar nada)."
  else
    bc_log "Copiando la configuración del perfil '$BC_PROFILE'..."
    bc_rsync -az "$BC_ENV_FILE" "$target:$path/env.sh" \
      || bc_die "falló la copia de env.sh."
  fi

  bc_ssh "chmod +x '$path/bin/backupctl'" || true

  # --- Propietario -----------------------------------------------------------
  # Si conectas como 'admin' pero la instalación es de otro usuario —lo normal
  # cuando ese otro no tiene shell—, hay que devolverle sus archivos.
  if [[ "$remote_user" != "$USER_NAME" ]]; then
    bc_log "La instalación es de '$USER_NAME' pero has conectado como '$remote_user'."
    if bc_ssh_sudo "chown -R $USER_NAME:$USER_NAME '$path'"; then
      bc_ok "propietario ajustado a $USER_NAME."
    else
      bc_warn "no se pudo cambiar el propietario. Hazlo en el servidor:"
      bc_warn "    sudo chown -R $USER_NAME:$USER_NAME $path"
    fi
  fi

  bc_ok "Desplegado en $target:$path"

  # --- Diagnóstico en el destino ---------------------------------------------
  bc_section "Diagnóstico en el destino"
  if bc_ssh "'$path/bin/backupctl' --no-color doctor" 2>&1 | sed 's/^/    /'; then
    bc_ok "El destino está listo."
  else
    bc_warn "El diagnóstico remoto encontró problemas. Revísalos arriba."
  fi

  echo
  bc_log "Siguiente paso, desde aquí mismo:"
  bc_log "    backupctl -p $BC_PROFILE remote backup     # respaldo de prueba"
  bc_log "    backupctl -p $BC_PROFILE remote cron --install"
}
