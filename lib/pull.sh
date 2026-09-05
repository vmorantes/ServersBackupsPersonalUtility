#!/usr/bin/env bash
# =============================================================================
# lib/pull.sh — traer del servidor al repositorio
# =============================================================================
# El inverso de `deploy`. Se conecta a un servidor ya desplegado y trae:
#
#   1. Su env.sh real       → se compara con el del repositorio y se avisa de
#                             cualquier diferencia antes de tocar nada.
#   2. Su estado desplegado → se escribe en ESTADO.md dentro de la carpeta del
#                             servidor: versión, rutas, crontab instalado,
#                             respaldos, inventario y resultado del diagnóstico.
#
# Para qué sirve: que el repositorio recuerde qué hay realmente en cada máquina
# sin tener que conectarse a mirarlo. Si alguien tocó el env.sh directamente en
# el servidor, `pull` lo detecta.
#
# ESTADO.md se regenera entero en cada pull. NOTAS.md, en cambio, es tuyo y
# nunca se sobrescribe.
# =============================================================================

[[ -n "${BC_PULL_LOADED:-}" ]] && return 0
BC_PULL_LOADED=1

bc_pull_run() {
  local target="${1:-}"
  local path="${BC_OPT_REMOTE_PATH:-$DEPLOY_PATH}"

  if [[ -z "$target" ]]; then
    [[ -n "$DEPLOY_HOST" ]] || bc_die "indica el servidor: backupctl pull usuario@servidor (o define DEPLOY_HOST en $BC_ENV_FILE)"
    target="$DEPLOY_USER@$DEPLOY_HOST"
  fi

  bc_require_cmd ssh
  bc_section "Trayendo el estado de $target al perfil '$BC_PROFILE'"

  # --- Conectividad ----------------------------------------------------------
  local host_info
  if ! host_info="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" \
        'hostname -f 2>/dev/null || hostname' 2>&1)"; then
    bc_err "no se pudo conectar por SSH a $target:"
    sed 's/^/        /' <<<"$host_info" >&2
    bc_die "configura el acceso por clave (ssh-copy-id $target) y reinténtalo."
  fi
  bc_ok "conectado a $host_info"

  local has_ctl="no"
  ssh "$target" "test -x '$path/bin/backupctl'" 2>/dev/null && has_ctl="si"
  if [[ "$has_ctl" == "no" ]]; then
    bc_warn "no hay backupctl en $target:$path. Se recogerá lo que se pueda."
    bc_warn "Para desplegarlo: backupctl -p $BC_PROFILE deploy $target"
  fi

  # --- 1. env.sh remoto ------------------------------------------------------
  bc_step "Comparando la configuración"
  local remote_env; remote_env="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$remote_env'" RETURN

  if ssh "$target" "cat '$path/env.sh'" > "$remote_env" 2>/dev/null && [[ -s "$remote_env" ]]; then
    if diff -q "$BC_ENV_FILE" "$remote_env" >/dev/null 2>&1; then
      bc_ok "el env.sh del servidor es idéntico al del repositorio."
    else
      bc_warn "el env.sh del SERVIDOR difiere del que hay en el repositorio:"
      echo
      diff -u "$BC_ENV_FILE" "$remote_env" \
        --label "repositorio: $BC_ENV_FILE" \
        --label "servidor:    $target:$path/env.sh" | sed 's/^/    /' || true
      echo
      if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
        bc_log "Simulación (--dry-run): no se ha modificado el env.sh local."
      elif bc_confirm "¿Traer la versión del SERVIDOR al repositorio (sobrescribe la local)?" n; then
        cp "$BC_ENV_FILE" "$BC_ENV_FILE.anterior"
        cp "$remote_env" "$BC_ENV_FILE"
        bc_ok "env.sh actualizado. La versión anterior queda en $(basename "$BC_ENV_FILE").anterior"
        bc_config_load "$BC_ENV_FILE"
      else
        bc_log "Se conserva el env.sh del repositorio. La diferencia queda anotada en ESTADO.md."
      fi
    fi
  else
    bc_warn "no se pudo leer $path/env.sh en el servidor."
  fi

  # --- 2. Estado del despliegue ----------------------------------------------
  bc_step "Recogiendo el estado del despliegue"

  local ctl_version="(sin backupctl)" ctl_status="" ctl_doctor="" ctl_list="" db_count="?"
  local crontab_block remote_tree disk

  if [[ "$has_ctl" == "si" ]]; then
    ctl_version="$(ssh "$target" "'$path/bin/backupctl' --version" 2>/dev/null || echo '?')"
    ctl_status="$(ssh "$target"  "'$path/bin/backupctl' --no-color status" 2>&1 || true)"
    ctl_doctor="$(ssh "$target"  "'$path/bin/backupctl' --no-color doctor" 2>&1 || true)"
    ctl_list="$(ssh "$target"    "'$path/bin/backupctl' --no-color list"   2>&1 || true)"
    db_count="$(ssh "$target"    "'$path/bin/backupctl' --no-color list --databases 2>/dev/null | grep -c ." 2>/dev/null || echo '?')"
  fi

  crontab_block="$(ssh "$target" "crontab -l 2>/dev/null | grep -v '^#\$'" 2>/dev/null || echo '(sin crontab o sin acceso)')"
  remote_tree="$(ssh "$target" "ls -la '$path' 2>/dev/null" 2>/dev/null || echo '(no accesible)')"
  disk="$(ssh "$target" "df -h '$path' 2>/dev/null | tail -1" 2>/dev/null || echo '?')"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha escrito ESTADO.md."
    return 0
  fi

  # --- 3. Escribir ESTADO.md -------------------------------------------------
  local estado="$BC_PROFILE_DIR/ESTADO.md"
  {
    cat <<CAB
# Estado del despliegue — $BC_PROFILE

> **Archivo generado.** No lo edites a mano: \`backupctl -p $BC_PROFILE pull\`
> lo regenera entero. Tus apuntes van en \`NOTAS.md\`, que nunca se sobrescribe.

| Dato | Valor |
|---|---|
| Servidor | \`$host_info\` |
| Acceso SSH | \`$target\` |
| Ruta del despliegue | \`$path\` |
| backupctl instalado | $ctl_version |
| Bases de datos | $db_count |
| Recogido el | $(date '+%Y-%m-%d %H:%M:%S %Z') |
| Desde | \`$(hostname 2>/dev/null)\` |

## Configuración

El \`env.sh\` de este directorio es la configuración de este servidor.

CAB

    if [[ -s "$remote_env" ]] && ! diff -q "$BC_ENV_FILE" "$remote_env" >/dev/null 2>&1; then
      echo "> **ATENCIÓN.** En el momento de esta recogida, el \`env.sh\` del servidor"
      echo "> DIFERÍA del que hay en el repositorio, y se decidió conservar el local."
      echo "> Si el bueno es el del servidor, vuelve a ejecutar \`pull\` y acepta traerlo."
      echo
      echo '```diff'
      diff -u "$BC_ENV_FILE" "$remote_env" --label "repositorio" --label "servidor" 2>/dev/null | head -60 || true
      echo '```'
      echo
    else
      echo "En el momento de esta recogida coincidía con el del servidor."
      echo
    fi

    echo "## Crontab instalado"
    echo
    echo '```cron'
    printf '%s\n' "$crontab_block"
    echo '```'
    echo

    echo "## Espacio en disco"
    echo
    echo '```'
    printf '%s\n' "$disk"
    echo '```'
    echo

    echo "## Contenido de \`$path\`"
    echo
    echo '```'
    printf '%s\n' "$remote_tree"
    echo '```'
    echo

    if [[ -n "$ctl_status" ]]; then
      echo "## Estado (\`backupctl status\`)"
      echo
      echo '```'
      printf '%s\n' "$ctl_status"
      echo '```'
      echo
    fi

    if [[ -n "$ctl_list" ]]; then
      echo "## Respaldos guardados (\`backupctl list\`)"
      echo
      echo '```'
      printf '%s\n' "$ctl_list"
      echo '```'
      echo
    fi

    if [[ -n "$ctl_doctor" ]]; then
      echo "## Diagnóstico (\`backupctl doctor\`)"
      echo
      echo '```'
      printf '%s\n' "$ctl_doctor"
      echo '```'
      echo
    fi

    echo "---"
    echo
    echo "Para actualizar este archivo: \`backupctl -p $BC_PROFILE pull\`"
    echo "Para subir cambios al servidor: \`backupctl -p $BC_PROFILE deploy\`"
  } > "$estado"

  bc_ok "Escrito $estado ($(wc -l < "$estado") líneas)"

  # --- 4. NOTAS.md, solo si no existe ----------------------------------------
  local notas="$BC_PROFILE_DIR/NOTAS.md"
  if [[ ! -f "$notas" ]]; then
    cat > "$notas" <<NOTAS
# Notas de despliegue — $BC_PROFILE

> Este archivo es **tuyo**. \`backupctl pull\` no lo toca nunca.
> Aquí van las particularidades de este servidor que no quieres volver a pensar.

## Particularidades

-

## Cosas que hay que recordar

-

## Historial

- $(date '+%Y-%m-%d'): primera recogida de estado con \`backupctl pull\`.
NOTAS
    bc_log "Creado $notas (plantilla vacía para tus apuntes)."
  else
    bc_log "$notas ya existe: no se toca."
  fi

  echo
  bc_ok "El repositorio ya refleja lo que hay en $target."
}
