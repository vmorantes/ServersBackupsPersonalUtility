#!/usr/bin/env bash
# =============================================================================
# lib/cron.sh — programación desatendida
# =============================================================================
# ATENCIÓN AL PORCENTAJE
# ----------------------
# En crontab, un '%' sin escapar se traduce a un salto de línea, y todo lo que
# sigue al primero se envía al proceso por la entrada estándar. Una línea como
#
#     ... >> log_$(date +%Y%m%d).log 2>&1
#
# se parte y no hace lo que parece. Es un fallo real y difícil de ver.
#
# backupctl lo evita de raíz: escribe y rota su propio log, así que la línea de
# cron no necesita ninguna redirección con fecha.
#
# HESTIACP GESTIONA EL CRON POR SU CUENTA
# ---------------------------------------
# En un servidor HestiaCP, el crontab del sistema NO es la fuente de verdad. Lo
# es /usr/local/hestia/data/users/<user>/cron.conf, y HestiaCP regenera
# /var/spool/cron/crontabs/<user> a partir de ahí cada vez que ejecuta
# v-rebuild-cron-jobs — al añadir o borrar un cron desde el panel, en
# v-rebuild-user, al suspender o reactivar el usuario y en algunas
# actualizaciones.
#
# Consecuencia: una línea puesta con `crontab -e` NO aparece en el panel y puede
# DESAPARECER sin aviso en el siguiente rebuild. Es una forma silenciosa de
# quedarse sin respaldos.
#
# Por eso, si se detecta HestiaCP, la instalación se hace con v-add-cron-job:
# así el trabajo queda registrado en cron.conf, se ve en el panel y sobrevive a
# los rebuilds.
# =============================================================================

[[ -n "${BC_CRON_LOADED:-}" ]] && return 0
BC_CRON_LOADED=1

# Marca que delimita el bloque de este perfil dentro del crontab. Es una
# función y no una variable porque se evalúa al cargar el módulo, cuando
# todavía no hay ningún perfil cargado.
bc_cron_mark() { printf '# backupctl:%s' "$BC_PROFILE"; }

# -----------------------------------------------------------------------------
# HestiaCP
# -----------------------------------------------------------------------------
BC_HESTIA_BIN="/usr/local/hestia/bin"

# ¿Estamos en un HestiaCP y el usuario del perfil está dado de alta en él?
bc_cron_hestia_available() {
  [[ -x "$BC_HESTIA_BIN/v-add-cron-job" ]] || return 1
  [[ -d "/usr/local/hestia/data/users/$USER_NAME" ]] || return 1
  return 0
}

# Las órdenes v-* de HestiaCP exigen root
bc_cron_hestia_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

bc_cron_hestia_jobs() {
  bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-list-cron-jobs" "$USER_NAME" plain 2>/dev/null || true
}

# Identificadores de los trabajos que apuntan a nuestro backupctl
bc_cron_hestia_our_jobs() {
  bc_cron_hestia_jobs | awk -F'\t' '$0 ~ /backupctl/ {print $1}'
}

# Las órdenes se dejan SIN "|| echo ..." a propósito: HestiaCP valida el campo
# del comando y las comillas y los operadores pueden hacer que lo rechace. El
# aviso de fallo se delega en NOTIFY_EMAIL / NOTIFY_COMMAND / HEALTHCHECK_URL,
# que además funcionan aunque el respaldo ni llegue a arrancar.
bc_cron_hestia_install() {
  local exe="$BC_ROOT/bin/backupctl"
  local hour="${BC_OPT_HOUR:-3}" minute="${BC_OPT_MINUTE:-30}"

  bc_section "Instalación mediante HestiaCP"
  bc_log "Usuario HestiaCP: $USER_NAME"
  bc_log "Los trabajos quedarán registrados en cron.conf y visibles en el panel."

  if [[ -z "${NOTIFY_EMAIL:-}${NOTIFY_COMMAND:-}${HEALTHCHECK_URL:-}" ]]; then
    bc_warn "no hay ningún aviso configurado en $BC_ENV_FILE."
    bc_warn "Sin él, un respaldo fallido no avisará a nadie. Ver: backupctl notify-test"
  fi

  # Se retiran primero los trabajos previos de backupctl, para que reinstalar
  # sea idempotente y no se acumulen duplicados.
  local existing job
  existing="$(bc_cron_hestia_our_jobs)"
  if [[ -n "$existing" ]]; then
    bc_log "Trabajos de backupctl ya registrados: $(tr '\n' ' ' <<<"$existing")"
  fi

  bc_log "Se van a registrar:"
  bc_log "        $minute $hour * * *   $exe -p $BC_PROFILE backup"
  bc_log "        0 5 * * 0             $exe -p $BC_PROFILE verify --quick"
  bc_log "        0 9 * * 1             $exe -p $BC_PROFILE status"
  echo

  bc_confirm "¿Registrarlos en HestiaCP para el usuario '$USER_NAME'?" y \
    || { bc_log "Cancelado."; return 0; }

  if [[ -n "$existing" ]]; then
    while IFS= read -r job; do
      [[ -z "$job" ]] && continue
      bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-delete-cron-job" "$USER_NAME" "$job" \
        && bc_log "  retirado el trabajo previo $job" \
        || bc_warn "  no se pudo retirar el trabajo $job"
    done <<<"$existing"
  fi

  local rc=0
  bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-add-cron-job" "$USER_NAME" \
    "$minute" "$hour" '*' '*' '*' "$exe -p $BC_PROFILE backup" || rc=1
  bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-add-cron-job" "$USER_NAME" \
    '0' '5' '*' '*' '0' "$exe -p $BC_PROFILE verify --quick" || rc=1
  bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-add-cron-job" "$USER_NAME" \
    '0' '9' '*' '*' '1' "$exe -p $BC_PROFILE status" || rc=1

  if (( rc )); then
    bc_err "alguna orden v-add-cron-job falló. Revísalo en el panel."
    bc_err "Si HestiaCP rechazó el comando, instálalo a mano desde el panel con:"
    bc_err "    $exe -p $BC_PROFILE backup"
    return 1
  fi

  bc_ok "Registrado en HestiaCP. Aparecerá en el panel, en Cron."
  echo
  bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-list-cron-jobs" "$USER_NAME" 2>/dev/null | sed 's/^/    /' || true
}

bc_cron_hestia_remove() {
  local existing job
  existing="$(bc_cron_hestia_our_jobs)"
  if [[ -z "$existing" ]]; then
    bc_log "No hay trabajos de backupctl registrados en HestiaCP para '$USER_NAME'."
    return 0
  fi
  bc_log "Trabajos de backupctl en HestiaCP: $(tr '\n' ' ' <<<"$existing")"
  bc_confirm "¿Eliminarlos?" n || { bc_log "Cancelado."; return 0; }
  while IFS= read -r job; do
    [[ -z "$job" ]] && continue
    bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-delete-cron-job" "$USER_NAME" "$job" \
      && bc_log "  eliminado $job" || bc_warn "  no se pudo eliminar $job"
  done <<<"$existing"
  bc_ok "Hecho."
}

# Genera las líneas de cron propuestas para este perfil
bc_cron_lines() {
  local hour="${BC_OPT_HOUR:-3}" minute="${BC_OPT_MINUTE:-30}"
  local exe="$BC_ROOT/bin/backupctl"
  local host; host="$(hostname 2>/dev/null || echo servidor)"

  cat <<CRON
$(bc_cron_mark)  (generado por: backupctl cron --install)
# Respaldo diario de las bases de datos
$minute $hour * * * $exe -p $BC_PROFILE backup || echo "Respaldo MySQL FALLIDO en $host — revisa $LOG_DIR"
# Verificación estructural del último respaldo, los domingos
0 5 * * 0 $exe -p $BC_PROFILE verify --quick || echo "Verificación de respaldo FALLIDA en $host"
# Estado semanal: avisa si el respaldo más reciente se está quedando viejo
0 9 * * 1 $exe -p $BC_PROFILE status || true
$(bc_cron_mark) end
CRON
}

bc_cron_show() {
  if bc_cron_hestia_available; then
    bc_section "HestiaCP detectado"
    bc_log "Este servidor gestiona el cron con HestiaCP, así que la instalación"
    bc_log "se hará con v-add-cron-job y el trabajo aparecerá en el panel."
    bc_log "Trabajos actuales del usuario '$USER_NAME':"
    bc_cron_hestia_sudo "$BC_HESTIA_BIN/v-list-cron-jobs" "$USER_NAME" 2>/dev/null \
      | sed 's/^/    /' || bc_warn "    no se pudieron listar (¿hace falta sudo?)"
    echo
  fi

  bc_section "Crontab propuesto para el perfil '$BC_PROFILE'"
  bc_cron_lines
  echo
  bc_log "Instálalo con: backupctl -p $BC_PROFILE cron --install"
  echo
  bc_section "Crontab actual del usuario $(id -un)"
  local ct; ct="$(crontab -l 2>/dev/null || true)"
  if [[ -z "$ct" ]]; then
    bc_log "(vacío)"
  else
    printf '%s\n' "$ct"
    if grep 'backupctl' <<<"$ct" | grep -qE '[^\\]%'; then
      echo
      bc_err "Hay un '%' sin escapar en una línea de backupctl: cron lo convierte en"
      bc_err "salto de línea y parte la orden. Escápalo como \\% o deja que backupctl"
      bc_err "gestione su propio log (recomendado)."
    fi
  fi
}

bc_cron_install() {
  # En HestiaCP el crontab del sistema es un archivo GENERADO: escribir en él
  # con `crontab -` funciona hasta el siguiente v-rebuild-cron-jobs, que lo
  # borra sin avisar. Se usa la vía oficial.
  if bc_cron_hestia_available; then
    bc_cron_hestia_install
    return $?
  fi

  bc_require_cmd crontab
  local current new mark
  mark="$(bc_cron_mark)"
  current="$(crontab -l 2>/dev/null || true)"

  # Se eliminan las entradas previas de ESTE perfil, para que reinstalar sea
  # idempotente y no se acumulen duplicados.
  new="$(awk -v mark="$mark" '
    index($0, mark) == 1 { skip = 1 }
    !skip { print }
    index($0, mark " end") == 1 { skip = 0 }
  ' <<<"$current")"

  local proposed; proposed="$(bc_cron_lines)"

  bc_section "Instalación en crontab"
  bc_log "Se van a añadir estas líneas:"
  sed 's/^/        /' <<<"$proposed"
  echo

  bc_confirm "¿Instalar en el crontab de $(id -un)?" y || { bc_log "Cancelado."; return 0; }

  printf '%s\n%s\n' "$new" "$proposed" | sed '/^$/N;/^\n$/D' | crontab - \
    || bc_die "no se pudo escribir el crontab."
  bc_ok "Crontab actualizado."
  bc_log "Compruébalo con: crontab -l"
}

bc_cron_remove() {
  if bc_cron_hestia_available; then
    bc_cron_hestia_remove
    return $?
  fi

  bc_require_cmd crontab
  local current new mark
  mark="$(bc_cron_mark)"
  current="$(crontab -l 2>/dev/null || true)"
  [[ -n "$current" ]] || { bc_log "El crontab ya está vacío."; return 0; }

  new="$(awk -v mark="$mark" '
    index($0, mark) == 1 { skip = 1 }
    !skip { print }
    index($0, mark " end") == 1 { skip = 0 }
  ' <<<"$current")"

  if [[ "$new" == "$current" ]]; then
    bc_log "No hay entradas de backupctl para el perfil '$BC_PROFILE'."
    return 0
  fi

  bc_confirm "¿Eliminar las entradas de backupctl del perfil '$BC_PROFILE'?" n \
    || { bc_log "Cancelado."; return 0; }
  printf '%s\n' "$new" | crontab - || bc_die "no se pudo escribir el crontab."
  bc_ok "Entradas eliminadas."
}
