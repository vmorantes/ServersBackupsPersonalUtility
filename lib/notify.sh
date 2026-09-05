#!/usr/bin/env bash
# =============================================================================
# lib/notify.sh — avisos
# =============================================================================
# Un cron que falla en silencio es un respaldo que no existe. Hay tres canales,
# todos opcionales y todos tolerantes a su propio error: un fallo notificando
# jamás debe enmascarar el resultado real de la operación.
# =============================================================================

[[ -n "${BC_NOTIFY_LOADED:-}" ]] && return 0
BC_NOTIFY_LOADED=1

bc_notify_failure() {
  local subject="$1" body="$2"
  bc_debug "notificando fallo: $subject"

  if [[ -n "${NOTIFY_COMMAND:-}" ]]; then
    NOTIFY_SUBJECT="$subject" NOTIFY_BODY="$body" bash -c "$NOTIFY_COMMAND" \
      || bc_warn "NOTIFY_COMMAND devolvió error"
  fi

  if [[ -n "${NOTIFY_EMAIL:-}" ]]; then
    if bc_has_cmd mail; then
      printf '%s\n' "$body" | mail -s "$subject" "$NOTIFY_EMAIL" \
        || bc_warn "no se pudo enviar el correo de aviso"
    else
      bc_warn "NOTIFY_EMAIL está configurado pero 'mail' no está instalado"
    fi
  fi

  # Un healthcheck es el único canal que además detecta que el cron DEJÓ de
  # ejecutarse: si no llega el ping esperado, el servicio avisa por su cuenta.
  if [[ -n "${HEALTHCHECK_URL:-}" ]] && bc_has_cmd curl; then
    curl -fsS --max-time 10 -o /dev/null --data-raw "$body" \
      "${HEALTHCHECK_URL%/}/fail" || bc_warn "no se pudo avisar al healthcheck"
  fi
}

bc_notify_success() {
  if [[ -n "${HEALTHCHECK_URL:-}" ]] && bc_has_cmd curl; then
    curl -fsS --max-time 10 -o /dev/null "$HEALTHCHECK_URL" \
      || bc_warn "no se pudo avisar al healthcheck"
  fi
}

# Prueba los canales configurados sin esperar a que falle un respaldo de verdad
bc_notify_test() {
  local host; host="$(hostname -f 2>/dev/null || hostname)"
  if [[ -z "${NOTIFY_EMAIL:-}${NOTIFY_COMMAND:-}${HEALTHCHECK_URL:-}" ]]; then
    bc_warn "no hay ningún canal de aviso configurado en $BC_ENV_FILE."
    bc_log "Configura NOTIFY_EMAIL, NOTIFY_COMMAND o HEALTHCHECK_URL."
    return 1
  fi
  bc_log "Enviando aviso de prueba por los canales configurados..."
  bc_notify_failure \
    "[$BC_PROFILE] Prueba de aviso de backupctl" \
    "$(printf 'Esto es una PRUEBA lanzada a mano desde %s.\nSi lo estás leyendo, el canal funciona.\nPerfil: %s\nFecha: %s\n' \
        "$host" "$BC_PROFILE" "$(bc_ts)")"
  bc_ok "Aviso de prueba enviado. Comprueba que ha llegado."
}
