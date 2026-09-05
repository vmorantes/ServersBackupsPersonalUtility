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
      *)               pkgs="$pkgs $c" ;;   # zip, unzip, rsync, gzip, bash
    esac
  done
  # Sin repetidos: mysql y mysqldump vienen del mismo paquete
  tr ' ' '\n' <<<"$pkgs" | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# bc_deploy_run [destino_ssh]
#   destino: user@host   (por defecto, DEPLOY_USER@DEPLOY_HOST del perfil)
bc_deploy_run() {
  local target="${1:-}"
  BC_DEPLOY_SKIP_ENV=0
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

  # --- Dependencias en el DESTINO --------------------------------------------
  # Se comprueban ANTES de copiar nada. Sin esto, un servidor sin rsync fallaba
  # a mitad de la transferencia con un error poco claro, y uno sin zip no daba
  # la cara hasta el primer respaldo.
  bc_log "Comprobando las dependencias del servidor..."
  local remote_missing
  remote_missing="$(ssh "$target" '
    faltan=""
    for c in bash rsync mysql mysqldump gzip zip unzip find sha256sum flock; do
      command -v "$c" >/dev/null 2>&1 || faltan="$faltan $c"
    done
    echo "$faltan"' 2>/dev/null || echo "?")"

  if [[ "$remote_missing" == "?" ]]; then
    bc_warn "no se pudieron comprobar las dependencias del destino."
  elif [[ -n "${remote_missing// /}" ]]; then
    bc_err "faltan órdenes en el servidor:${remote_missing}"
    bc_err "Instálalas allí y vuelve a intentarlo:"
    bc_err "    sudo apt update && sudo apt install -y $(bc_deploy_packages "$remote_missing")"
    # rsync es imprescindible para la propia copia; el resto puede esperar
    if [[ "$remote_missing" == *rsync* ]]; then
      bc_die "sin rsync en el destino no se puede desplegar."
    fi
    bc_confirm "¿Desplegar de todas formas? El respaldo no funcionará hasta instalarlas." n \
      || bc_die "cancelado."
  else
    bc_ok "todas las dependencias están presentes en el servidor."
  fi

  # --- Qué se va a copiar ----------------------------------------------------
  local files=(bin lib)
  bc_log "Se copiarán: ${files[*]} + env.sh del perfil '$BC_PROFILE'"

  # --- env.sh: comparar antes de sobrescribir ---------------------------------
  # Es el único archivo del despliegue que puede llevar cambios hechos
  # directamente en el servidor. Sobrescribirlo en silencio destruiría un ajuste
  # que quizá era el bueno.
  bc_log "Comparando la configuración con la del servidor..."
  local remote_env; remote_env="$(mktemp)"
  if ssh "$target" "cat '$path/env.sh'" > "$remote_env" 2>/dev/null && [[ -s "$remote_env" ]]; then
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
        bc_log "Simulación: el env.sh del servidor NO se tocaría en este ensayo."
        BC_DEPLOY_SKIP_ENV=1
      elif bc_confirm "¿Sobrescribir el env.sh del servidor con el del repositorio?" n; then
        # Copia de seguridad en el propio servidor, por si el ajuste hacía falta
        ssh "$target" "cp '$path/env.sh' '$path/env.sh.anterior'" 2>/dev/null \
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


  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_log "Simulación (--dry-run):"
    # La salida se captura en lugar de canalizarse: con set -e y pipefail, un
    # rsync fallido en una tubería aborta el programa con un "fallo no
    # controlado" en vez de explicar qué pasó.
    local preview rc=0
    preview="$(rsync -avn --delete \
      --exclude '.git' --exclude 'output' --exclude 'logs' \
      "${files[@]/#/$BC_ROOT/}" "$target:$path/" 2>&1)" || rc=$?
    sed 's/^/        /' <<<"$preview"
    if (( rc != 0 )); then
      bc_die "rsync no pudo hablar con el destino (código $rc). Revisa el acceso SSH y que rsync esté instalado allí."
    fi
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

  if [[ "${BC_DEPLOY_SKIP_ENV:-0}" == "1" ]]; then
    bc_log "env.sh: se conserva el del servidor (decidido antes de copiar nada)."
  else
    bc_log "Copiando la configuración del perfil '$BC_PROFILE'..."
    rsync -az "$BC_ENV_FILE" "$target:$path/env.sh" \
      || bc_die "falló la copia de env.sh."
  fi

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
