#!/usr/bin/env bash
# =============================================================================
# lib/ssh.sh — conexión reutilizada con el servidor
# =============================================================================
# Un despliegue hace unas ocho conexiones: comprobar acceso, mirar
# dependencias, crear directorios, dos rsync, comparar env.sh y ejecutar el
# diagnóstico. Con autenticación por contraseña eso serían OCHO peticiones de
# contraseña, que es inaceptable.
#
# La solución es la multiplexión de OpenSSH: se abre UNA conexión maestra —ahí
# se pide la contraseña una sola vez— y el resto de órdenes y los rsync viajan
# por ese mismo túnel sin volver a autenticarse.
#
# Efectos secundarios agradables: es bastante más rápido (no hay handshake por
# orden) y funciona igual con clave o con contraseña, así que no hace falta
# configurar nada por adelantado.
# =============================================================================

[[ -n "${BC_SSH_LOADED:-}" ]] && return 0
BC_SSH_LOADED=1

BC_SSH_TARGET=""
BC_SSH_CTL=""

# bc_ssh_init <usuario@servidor>
# Abre la conexión maestra. Es el único punto donde puede pedirse una contraseña.
bc_ssh_init() {
  local target="$1"
  BC_SSH_TARGET="$target"

  # La ruta del socket tiene un límite de ~104 caracteres, así que se usa un
  # nombre corto derivado del destino en lugar de la ruta completa.
  local key; key="$(printf '%s' "$target" | cksum | cut -d' ' -f1)"
  BC_SSH_CTL="${TMPDIR:-/tmp}/.bcssh-$$-$key"

  local opts=(
    -o ControlMaster=auto
    -o "ControlPath=$BC_SSH_CTL"
    -o ControlPersist=600
    -o ConnectTimeout=15
    -o StrictHostKeyChecking=accept-new
  )

  # Sin terminal no hay a quién pedirle una contraseña: se exige clave y se
  # falla con un mensaje claro en lugar de quedarse colgado esperando.
  if ! bc_is_tty; then
    opts+=(-o BatchMode=yes)
  fi

  bc_debug "abriendo conexión maestra a $target (socket: $BC_SSH_CTL)"

  local err; err="$(mktemp)"
  if ! ssh "${opts[@]}" "$target" true 2>"$err"; then
    bc_err "no se pudo conectar por SSH a $target:"
    sed 's/^/        /' "$err" >&2
    rm -f "$err"
    if bc_is_tty; then
      bc_err "Comprueba el usuario, el servidor y que tenga acceso por SSH."
    else
      bc_err "Sin terminal solo se puede entrar con clave: ssh-copy-id $target"
    fi
    return 1
  fi
  rm -f "$err"
  BC_SSH_OPTS=(-o "ControlPath=$BC_SSH_CTL")
  return 0
}

# Ejecuta una orden en el servidor por la conexión ya abierta
bc_ssh() {
  ssh -o "ControlPath=$BC_SSH_CTL" "$BC_SSH_TARGET" "$@"
}

# Igual, pero con terminal asignado: necesario cuando la orden remota puede
# pedir algo por teclado, como sudo.
bc_ssh_tty() {
  ssh -t -o "ControlPath=$BC_SSH_CTL" "$BC_SSH_TARGET" "$@"
}

# rsync viajando por el mismo túnel: tampoco vuelve a pedir contraseña
bc_rsync() {
  rsync -e "ssh -o ControlPath=$BC_SSH_CTL" "$@"
}

# Cierra la conexión maestra. Se llama desde el trap de salida.
bc_ssh_close() {
  [[ -z "$BC_SSH_CTL" ]] && return 0
  ssh -O exit -o "ControlPath=$BC_SSH_CTL" "$BC_SSH_TARGET" 2>/dev/null || true
  BC_SSH_CTL=""; BC_SSH_TARGET=""
}

# -----------------------------------------------------------------------------
# Elevación en el servidor
# -----------------------------------------------------------------------------
# ¿Puede este usuario hacer sudo sin contraseña?
bc_ssh_can_sudo_nopass() {
  bc_ssh "sudo -n true" 2>/dev/null
}

# ¿Y con contraseña? (o sea, ¿está en el grupo sudo?)
bc_ssh_has_sudo() {
  bc_ssh "command -v sudo >/dev/null 2>&1" 2>/dev/null
}

# Igual que bc_ssh_sudo pero pasando la entrada estándar al otro lado, para
# enviar contenido (una clave, un archivo de configuración) sin que aparezca en
# la línea de órdenes, donde cualquiera con `ps` podría leerlo.
bc_ssh_sudo_stdin() {
  if bc_ssh "test \$(id -u) -eq 0" < /dev/null 2>/dev/null; then
    bc_ssh "$@"
  elif bc_ssh_can_sudo_nopass; then
    bc_ssh "sudo -n bash -c $(printf '%q' "$*")"
  else
    return 1
  fi
}

# Ejecuta algo como root en el servidor. Si hace falta contraseña de sudo, se
# pide con terminal asignado en lugar de fallar en silencio.
bc_ssh_sudo() {
  if bc_ssh "test \$(id -u) -eq 0" 2>/dev/null; then
    bc_ssh "$@"
  elif bc_ssh_can_sudo_nopass; then
    bc_ssh "sudo -n $*"
  elif bc_is_tty; then
    bc_ssh_tty "sudo $*"
  else
    return 1
  fi
}
