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
# =============================================================================

[[ -n "${BC_CRON_LOADED:-}" ]] && return 0
BC_CRON_LOADED=1

# Marca que delimita el bloque de este perfil dentro del crontab. Es una
# función y no una variable porque se evalúa al cargar el módulo, cuando
# todavía no hay ningún perfil cargado.
bc_cron_mark() { printf '# backupctl:%s' "$BC_PROFILE"; }

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
