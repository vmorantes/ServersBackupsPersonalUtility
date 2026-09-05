#!/usr/bin/env bash
# =============================================================================
# lib/install.sh — dejar `backupctl` disponible en el PATH
# =============================================================================
# Sin esto hay que escribir ./bin/backupctl desde el directorio del repositorio,
# que es incómodo y hace que las órdenes de la documentación no funcionen tal
# cual.
#
# Se crea un enlace simbólico, no una copia: así al actualizar el repositorio
# la orden apunta sola a la versión nueva. backupctl resuelve los enlaces para
# encontrar su lib/, de modo que funciona desde cualquier ruta.
# =============================================================================

[[ -n "${BC_INSTALL_LOADED:-}" ]] && return 0
BC_INSTALL_LOADED=1

# Primer directorio del PATH donde podemos escribir sin sudo
bc_install_target() {
  local d
  for d in "$HOME/.local/bin" "$HOME/bin"; do
    case ":$PATH:" in *":$d:"*) [[ -d "$d" && -w "$d" ]] && { printf '%s' "$d"; return 0; } ;; esac
  done
  # ~/.local/bin es el estándar actual: si está en el PATH pero no existe, se crea
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) printf '%s' "$HOME/.local/bin"; return 0 ;;
  esac
  return 1
}

bc_install_run() {
  local origen="$BC_ROOT/bin/backupctl"
  [[ -x "$origen" ]] || bc_die "no encuentro $origen"

  bc_section "Dejar backupctl disponible en el PATH"

  local destino_dir necesita_sudo=0
  if destino_dir="$(bc_install_target)"; then
    bc_log "Se usará $destino_dir (está en tu PATH, no hace falta sudo)."
  else
    destino_dir="/usr/local/bin"
    necesita_sudo=1
    bc_log "No hay ningún directorio propio en tu PATH donde escribir."
    bc_log "Se usará $destino_dir, que necesita sudo."
  fi

  local destino="$destino_dir/backupctl"

  if [[ -e "$destino" || -L "$destino" ]]; then
    local actual; actual="$(readlink -f "$destino" 2>/dev/null || echo "$destino")"
    if [[ "$actual" == "$(readlink -f "$origen")" ]]; then
      bc_ok "ya está instalado y apunta aquí: $destino"
      bc_install_comprobar "$destino_dir"
      return 0
    fi
    bc_warn "$destino ya existe y apunta a: $actual"
    bc_confirm "¿Sustituirlo por un enlace a este repositorio?" n \
      || { bc_log "Cancelado."; return 0; }
  fi

  bc_log "Enlace: $destino  ->  $origen"
  bc_confirm "¿Crearlo?" y || { bc_log "Cancelado."; return 0; }

  if (( necesita_sudo )); then
    sudo mkdir -p "$destino_dir" && sudo ln -sfn "$origen" "$destino" \
      || bc_die "no se pudo crear el enlace en $destino_dir."
  else
    mkdir -p "$destino_dir" && ln -sfn "$origen" "$destino" \
      || bc_die "no se pudo crear el enlace en $destino_dir."
  fi

  bc_ok "Creado."
  bc_install_comprobar "$destino_dir"
}

bc_install_comprobar() {
  local dir="$1"
  echo
  if command -v backupctl >/dev/null 2>&1; then
    bc_ok "'backupctl' ya funciona desde cualquier directorio:"
    bc_log "    $(command -v backupctl)"
    bc_log "Pruébalo:  backupctl profiles"
  else
    bc_warn "el enlace está creado, pero '$dir' no está en tu PATH ahora mismo."
    bc_log "Añádelo a tu shell:"
    bc_log "    echo 'export PATH=\"$dir:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
    bc_log "O abre un terminal nuevo, que a veces basta."
  fi
}

bc_uninstall_run() {
  bc_section "Quitar backupctl del PATH"
  local encontrado=0 d destino
  for d in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin /usr/bin; do
    destino="$d/backupctl"
    [[ -L "$destino" ]] || continue
    encontrado=1
    bc_log "Enlace en $destino -> $(readlink -f "$destino")"
    if bc_confirm "¿Eliminarlo?" n; then
      if [[ -w "$d" ]]; then rm -f "$destino"; else sudo rm -f "$destino"; fi
      bc_ok "eliminado."
    fi
  done
  (( encontrado )) || bc_log "No hay ningún enlace a backupctl en el PATH."
}
