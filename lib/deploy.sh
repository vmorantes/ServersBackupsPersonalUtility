#!/usr/bin/env bash
# =============================================================================
# lib/deploy.sh — instalar o actualizar backupctl en un servidor
# =============================================================================
# Copia el tooling (bin/ y lib/) más el env.sh del perfil al servidor destino.
#
# Como el código es idéntico en todas las máquinas y lo único que cambia es
# env.sh, desplegar es copiar un árbol: no hay plantillas que rellenar ni
# variantes por servidor que puedan divergir.
#
# En el destino, el env.sh queda junto al tooling, de modo que allí el perfil se
# llama simplemente 'local' y no hay que indicarlo en cada orden.
# =============================================================================

[[ -n "${BC_DEPLOY_LOADED:-}" ]] && return 0
BC_DEPLOY_LOADED=1

# bc_deploy_run [destino_ssh]
#   destino: user@host   (por defecto, DEPLOY_USER@DEPLOY_HOST del perfil)
bc_deploy_run() {
  local target="${1:-}"
  local path="${BC_OPT_REMOTE_PATH:-$DEPLOY_PATH}"

  if [[ -z "$target" ]]; then
    [[ -n "$DEPLOY_HOST" ]] || bc_die "indica el destino: backupctl deploy usuario@servidor (o define DEPLOY_HOST en $BC_ENV_FILE)"
    target="$DEPLOY_USER@$DEPLOY_HOST"
  fi

  bc_require_cmd rsync ssh
  bc_section "Despliegue en $target:$path"

  # --- Conectividad ----------------------------------------------------------
  bc_log "Comprobando acceso SSH..."
  local remote_info
  if ! remote_info="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" \
        'echo "$(hostname -f 2>/dev/null || hostname)|$(bash --version | head -1)"' 2>&1)"; then
    bc_err "no se pudo conectar por SSH a $target:"
    sed 's/^/        /' <<<"$remote_info" >&2
    bc_die "configura el acceso por clave (ssh-copy-id $target) y reinténtalo."
  fi
  bc_ok "conectado a ${remote_info%%|*}"
  bc_log "  ${remote_info#*|}"

  # --- Qué se va a copiar ----------------------------------------------------
  local files=(bin lib)
  bc_log "Se copiarán: ${files[*]} + env.sh del perfil '$BC_PROFILE'"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_log "Simulación (--dry-run):"
    rsync -avn --delete \
      --exclude '.git' --exclude 'output' --exclude 'logs' \
      "${files[@]/#/$BC_ROOT/}" "$target:$path/" | sed 's/^/        /'
    bc_ok "Nada se ha copiado."
    return 0
  fi

  bc_confirm "¿Copiar backupctl a $target:$path?" y || { bc_log "Cancelado."; return 0; }

  # --- Copia -----------------------------------------------------------------
  ssh "$target" "mkdir -p '$path'/{logs,output}" \
    || bc_die "no se pudieron crear los directorios en el destino."

  bc_log "Copiando el tooling..."
  rsync -az --delete \
    --exclude '.git' --exclude 'output' --exclude 'logs' \
    "${files[@]/#/$BC_ROOT/}" "$target:$path/" \
    || bc_die "falló la copia de bin/ y lib/."

  bc_log "Copiando la configuración del perfil '$BC_PROFILE'..."
  rsync -az "$BC_ENV_FILE" "$target:$path/env.sh" \
    || bc_die "falló la copia de env.sh."

  ssh "$target" "chmod +x '$path/bin/backupctl'" || true

  bc_ok "Desplegado en $target:$path"

  # --- Comprobación en el destino --------------------------------------------
  bc_section "Diagnóstico en el destino"
  if ssh "$target" "'$path/bin/backupctl' doctor" 2>&1 | sed 's/^/    /'; then
    bc_ok "El destino está listo."
  else
    bc_warn "El diagnóstico remoto encontró problemas. Revísalos arriba."
  fi

  echo
  bc_log "Siguiente paso, en el servidor destino:"
  bc_log "    $path/bin/backupctl cron --install"
}
