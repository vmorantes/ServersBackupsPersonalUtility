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

# Cuántos canales han funcionado de verdad en el último envío. Sin esto, la
# prueba decía «✓ enviado» después de avisar de que 'mail' no está instalado:
# un OK en falso sobre el canal de avisos es peor que no tener avisos, porque
# te deja creyendo que estás cubierto.
BC_NOTIFY_OK=0
BC_NOTIFY_FALLOS=0
BC_NOTIFY_MOTIVOS=""

bc_notify_anota() {   # $1: ok|fallo   $2: motivo
  if [[ "$1" == "ok" ]]; then
    BC_NOTIFY_OK=$((BC_NOTIFY_OK+1))
  else
    BC_NOTIFY_FALLOS=$((BC_NOTIFY_FALLOS+1))
    BC_NOTIFY_MOTIVOS+="  - $2"$'\n'
  fi
}

bc_notify_failure() {
  local subject="$1" body="$2"
  bc_debug "notificando fallo: $subject"

  BC_NOTIFY_OK=0; BC_NOTIFY_FALLOS=0; BC_NOTIFY_MOTIVOS=""

  if [[ -n "${NOTIFY_COMMAND:-}" ]]; then
    if NOTIFY_SUBJECT="$subject" NOTIFY_BODY="$body" bash -c "$NOTIFY_COMMAND"; then
      bc_notify_anota ok
    else
      bc_warn "NOTIFY_COMMAND devolvió error"
      bc_notify_anota fallo "NOTIFY_COMMAND terminó con error"
    fi
  fi

  if [[ -n "${NOTIFY_EMAIL:-}" ]]; then
    if ! bc_has_cmd mail; then
      bc_warn "NOTIFY_EMAIL está configurado pero 'mail' no está instalado"
      bc_notify_anota fallo "correo: falta la orden 'mail' (instala mailutils o bsd-mailx)"
    elif printf '%s\n' "$body" | mail -s "$subject" "$NOTIFY_EMAIL"; then
      # Ojo: 'mail' solo confirma que lo aceptó el sistema de correo local.
      # Que salga del servidor y no acabe en spam ya no depende de nosotros.
      bc_notify_anota ok
    else
      bc_warn "no se pudo enviar el correo de aviso"
      bc_notify_anota fallo "correo: 'mail' devolvió error"
    fi
  fi

  # Un healthcheck es el único canal que además detecta que el cron DEJÓ de
  # ejecutarse: si no llega el ping esperado, el servicio avisa por su cuenta.
  if [[ -n "${HEALTHCHECK_URL:-}" ]]; then
    if ! bc_has_cmd curl; then
      bc_warn "HEALTHCHECK_URL está configurado pero 'curl' no está instalado"
      bc_notify_anota fallo "healthcheck: falta la orden 'curl'"
    elif curl -fsS --max-time 10 -o /dev/null --data-raw "$body" "${HEALTHCHECK_URL%/}/fail"; then
      bc_notify_anota ok
    else
      bc_warn "no se pudo avisar al healthcheck"
      bc_notify_anota fallo "healthcheck: la URL no respondió"
    fi
  fi

  (( BC_NOTIFY_OK > 0 ))
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
  # `|| true`: bc_notify_failure devuelve 1 si ningún canal funcionó, y con
  # set -e eso abortaría antes de poder explicar por qué.
  bc_notify_failure \
    "[$BC_PROFILE] Prueba de aviso de backupctl" \
    "$(printf 'Esto es una PRUEBA lanzada a mano desde %s.\nSi lo estás leyendo, el canal funciona.\nPerfil: %s\nFecha: %s\n' \
        "$host" "$BC_PROFILE" "$(bc_ts)")" || true
  if (( BC_NOTIFY_OK > 0 )); then
    bc_ok "Entregado por $BC_NOTIFY_OK canal(es). Comprueba que te llega de verdad:"
    bc_log "que 'mail' lo acepte no garantiza que salga del servidor ni que no caiga en spam."
    if (( BC_NOTIFY_FALLOS > 0 )); then
      bc_warn "Pero $BC_NOTIFY_FALLOS canal(es) NO funcionaron:"
      printf '%s' "$BC_NOTIFY_MOTIVOS"
    fi
    return 0
  fi

  bc_err "NO se envió NADA. Ningún canal funciona:"
  printf '%s' "$BC_NOTIFY_MOTIVOS"
  bc_log "Mientras siga así, un respaldo fallido bajo cron no avisará a nadie."
  bc_log "Lo que importa es que funcione EN EL SERVIDOR, que es donde corre el"
  bc_log "cron. Pruébalo allí con:  backupctl -p $BC_PROFILE remote notify-test"
  BC_DELIBERATE_EXIT=1
  return 1
}
