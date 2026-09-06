#!/usr/bin/env bash
# =============================================================================
# lib/sshkey.sh — dejar instalado el acceso por clave
# =============================================================================
# Sin esto, la interfaz web no puede hablar con un servidor que solo acepte
# contraseña: se lanza sin terminal, así que no hay dónde teclearla.
#
# La solución no es arrastrar la contraseña por todas las operaciones, sino
# usarla UNA vez para dejar la clave pública instalada. A partir de ahí todo
# —web, cron, guiones— entra sin pedir nada.
#
# La contraseña nunca pasa por la línea de órdenes: viaja en un archivo 0600 que
# lee un ayudante SSH_ASKPASS y se borra al terminar. En `ps` no aparece.
# =============================================================================

[[ -n "${BC_SSHKEY_LOADED:-}" ]] && return 0
BC_SSHKEY_LOADED=1

# Primera clave pública utilizable; se genera una si no hay ninguna.
bc_sshkey_publica() {
  local k
  for k in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
    [[ -f "$k" ]] && { printf '%s' "$k"; return 0; }
  done
  return 1
}

bc_sshkey_generar() {
  bc_log "No tienes ninguna clave SSH. Se genera una (ed25519, sin frase)."
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "backupctl@$(hostname 2>/dev/null)" \
             -f "$HOME/.ssh/id_ed25519" >/dev/null 2>&1 \
    || return 1
  bc_ok "Clave generada: $HOME/.ssh/id_ed25519"
}

# bc_sshkey_instalar <usuario@servidor> [archivo_con_la_contraseña]
#
# Sin archivo de contraseña se usa el flujo normal de ssh (pide por teclado).
# Con archivo, se usa SSH_ASKPASS para poder hacerlo sin terminal, que es lo
# que necesita la interfaz web.
bc_sshkey_instalar() {
  local target="$1" passfile="${2:-}"
  bc_require_cmd ssh ssh-keygen

  local pub
  if ! pub="$(bc_sshkey_publica)"; then
    bc_sshkey_generar || bc_die "no se pudo generar la clave."
    pub="$(bc_sshkey_publica)" || bc_die "no se encontró la clave recién generada."
  fi
  bc_log "Clave a instalar: $pub"

  # ¿Ya entra por clave? Entonces no hay nada que hacer.
  if ssh -o BatchMode=yes -o ConnectTimeout=8 \
         -o StrictHostKeyChecking=accept-new "$target" true 2>/dev/null; then
    bc_ok "ya se entra por clave en $target: no hace falta instalar nada."
    return 0
  fi

  # Sin contraseña y sin terminal no hay nada que intentar: ssh acabaría
  # llamando al askpass gráfico del sistema, que en un servidor no existe y da
  # un error que no explica nada.
  if [[ -z "$passfile" ]] && ! bc_can_prompt; then
    bc_err "hace falta la contraseña SSH de $target y no hay dónde pedirla."
    bc_err "Desde el terminal:  backupctl -p $BC_PROFILE sshkey"
    bc_err "Desde la web:       botón «Configurar acceso por clave»"
    return 2
  fi

  local -a env_askpass=()
  local helper=""
  if [[ -n "$passfile" ]]; then
    [[ -r "$passfile" ]] || bc_die "no se puede leer el archivo de contraseña."
    helper="$(mktemp)"
    chmod 700 "$helper"
    # El ayudante solo imprime el contenido del archivo. ssh lo invoca cuando
    # necesita la contraseña, así que esta nunca aparece en ninguna línea de
    # órdenes ni en el entorno de ssh.
    printf '#!/bin/sh\ncat %q\n' "$passfile" > "$helper"
    env_askpass=(env "SSH_ASKPASS=$helper" "SSH_ASKPASS_REQUIRE=force" "DISPLAY=${DISPLAY:-:0}")
  fi

  bc_log "Instalando la clave en $target..."
  local err rc=0
  err="$(mktemp)"

  # Se fuerza autenticación por contraseña: si la clave ya estuviera a medias
  # instalada, ssh podría intentarla, fallar y agotar los intentos.
  "${env_askpass[@]}" ssh \
      -o PreferredAuthentications=password,keyboard-interactive \
      -o PubkeyAuthentication=no \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=15 \
      -o NumberOfPasswordPrompts=1 \
      "$target" \
      'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys;
       clave="$(cat)";
       grep -qxF "$clave" ~/.ssh/authorized_keys || printf "%s\n" "$clave" >> ~/.ssh/authorized_keys;
       chmod 600 ~/.ssh/authorized_keys' \
      < "$pub" 2>"$err" || rc=$?

  [[ -n "$helper" ]] && rm -f "$helper"

  if (( rc != 0 )); then
    bc_err "no se pudo instalar la clave en $target:"
    sed 's/^/        /' "$err" >&2
    rm -f "$err"
    if grep -qi 'permission denied' "$err" 2>/dev/null; then
      bc_err "La contraseña parece incorrecta."
    fi
    return 1
  fi
  rm -f "$err"

  # Comprobación de verdad: que ahora entre SIN contraseña
  if ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" true 2>/dev/null; then
    bc_ok "Listo: $target ya acepta tu clave. No volverá a pedir contraseña."
    return 0
  fi
  bc_err "la clave se copió pero el servidor sigue sin aceptarla."
  bc_err "Comprueba en el servidor que PubkeyAuthentication esté en yes y los"
  bc_err "permisos de ~/.ssh (700) y ~/.ssh/authorized_keys (600)."
  return 1
}

# Orden `backupctl sshkey [usuario@servidor]`
bc_sshkey_run() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    [[ -n "$DEPLOY_HOST" ]] || bc_die "indica el destino: backupctl sshkey usuario@servidor"
    target="$DEPLOY_USER@$DEPLOY_HOST"
  fi

  bc_section "Acceso por clave a $target"

  local passfile=""
  if [[ -n "${BC_SSH_PASSWORD_FILE:-}" ]]; then
    passfile="$BC_SSH_PASSWORD_FILE"          # lo usa la interfaz web
  elif bc_can_prompt; then
    local p; p="$(bc_ask_secret "Contraseña SSH de $target")"
    if [[ -n "$p" ]]; then
      passfile="$(mktemp)"; chmod 600 "$passfile"
      printf '%s' "$p" > "$passfile"
      p=""
    fi
  fi

  local rc=0
  bc_sshkey_instalar "$target" "$passfile" || rc=$?
  [[ -n "$passfile" && -z "${BC_SSH_PASSWORD_FILE:-}" ]] && rm -f "$passfile"
  # Salida controlada: el trap ERR no debe informar de un "fallo no controlado"
  (( rc != 0 )) && BC_DELIBERATE_EXIT=1
  return $rc
}
