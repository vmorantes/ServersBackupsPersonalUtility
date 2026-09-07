#!/usr/bin/env bash
# =============================================================================
# lib/shield.sh — informe de blindaje
# =============================================================================
# Responde a una sola pregunta: ¿qué pasa si mañana pierdo este servidor?
#
# Cruza las tres capas que tienen que estar para que la respuesta sea "nada":
#
#   1. Bases de datos  → backupctl, verificable y portable
#   2. Cuenta completa → Restic vía HestiaCP (archivos, correo, DNS, config)
#   3. Las CLAVES      → sin ellas las dos capas anteriores son papel mojado
#
# Cada capa puede fallar por su cuenta y ninguna herramienta lo mira todo junto.
# Esa es la razón de que exista esta orden.
# =============================================================================

[[ -n "${BC_SHIELD_LOADED:-}" ]] && return 0
BC_SHIELD_LOADED=1

BC_SH_FALLOS=0
BC_SH_AVISOS=0
bc_sh_ok()   { printf '  %s✓%s %s\n' "$BC_GRN" "$BC_RST" "$*"; }
bc_sh_warn() { BC_SH_AVISOS=$((BC_SH_AVISOS+1)); printf '  %s!%s %s\n' "$BC_YEL" "$BC_RST" "$*"; }
bc_sh_fail() { BC_SH_FALLOS=$((BC_SH_FALLOS+1)); printf '  %s✗%s %s\n' "$BC_RED" "$BC_RST" "$*"; }
bc_sh_cab()  { printf '\n%s%s%s\n' "$BC_BLD" "$*" "$BC_RST"; }

bc_shield_run() {
  BC_SH_FALLOS=0; BC_SH_AVISOS=0
  bc_section "Blindaje — perfil '$BC_PROFILE'"
  bc_log "¿Qué se perdería si mañana desapareciera este servidor?"

  local remoto=0
  if [[ ! -d "$HESTIA_DIR" && -n "$DEPLOY_HOST" ]]; then
    remoto=1
    bc_hestia_conectar
    trap 'bc_hestia_cerrar' RETURN
  elif [[ -d "$HESTIA_DIR" ]]; then
    bc_hestia_conectar
    trap 'bc_hestia_cerrar' RETURN
  fi

  # === 1. Bases de datos =====================================================
  bc_sh_cab "1 · Bases de datos"
  local zip edad n_bd n_zip
  zip="$(bc_backup_latest || true)"
  if [[ -z "$zip" ]]; then
    bc_sh_fail "no hay ningún respaldo de bases de datos en $BACKUP_OUTPUT_DIR"
  else
    edad="$(bc_age_days "$zip")"
    n_zip="$(unzip -Z1 "$zip" 2>/dev/null | awk -F/ 'NF>1{print $1}' | sort -u | grep -c . || true)"
    if   (( edad <= 1 )); then bc_sh_ok "último respaldo de hace $edad días, $n_zip bases"
    elif (( edad <= 3 )); then bc_sh_warn "último respaldo de hace $edad días, $n_zip bases"
    else bc_sh_fail "último respaldo de hace $edad días: el cron podría estar parado"; fi

    # ¿Coincide con lo que hay ahora en MySQL? Una base nueva que nadie respalda
    # es el fallo silencioso más caro de todos.
    if bc_mysql_check >/dev/null 2>&1; then
      n_bd="$(bc_mysql_databases 2>/dev/null | grep -c . || echo 0)"
      if (( n_bd == n_zip )); then
        bc_sh_ok "las $n_bd bases de datos del servidor están en el respaldo"
      elif (( n_bd > n_zip )); then
        bc_sh_fail "hay $n_bd bases en MySQL pero solo $n_zip en el último respaldo"
        local faltan
        faltan="$(comm -23 <(bc_mysql_databases | sort) \
                           <(unzip -Z1 "$zip" 2>/dev/null | awk -F/ 'NF>1{print $1}' | sort -u) 2>/dev/null || true)"
        [[ -n "$faltan" ]] && { bc_log "        SIN RESPALDAR:"; sed 's/^/          - /' <<<"$faltan"; }
      else
        bc_sh_warn "el respaldo tiene $n_zip bases y ahora hay $n_bd (¿alguna borrada?)"
      fi
    else
      bc_sh_warn "no se pudo consultar MySQL para comparar"
    fi
  fi

  # === 2. Cuenta completa (Restic) ==========================================
  bc_sh_cab "2 · Cuenta completa (archivos, correo, DNS)"
  local conf repo
  conf="$(bc_hestia_read "cat '$HESTIA_CONF_RESTIC'" 2>/dev/null || true)"
  if [[ -z "$conf" ]]; then
    bc_sh_fail "Restic NO está configurado: los archivos web, el correo y la"
    bc_sh_fail "  configuración de HestiaCP no se respaldan en ningún sitio"
    bc_log "        Móntalo:  backupctl hestia setup"
  else
    repo="$(sed -n "s/^REPO='\(.*\)'$/\1/p" <<<"$conf")"
    bc_sh_ok "Restic configurado: $repo"

    # ¿Sale del servidor? Un repositorio en el mismo disco no protege de nada.
    case "$repo" in
      rclone:*:/*|*local*) bc_sh_warn "el repositorio parece estar en el propio servidor: no protege ante su pérdida" ;;
      *) bc_sh_ok "el repositorio está fuera del servidor" ;;
    esac

    local cron
    cron="$(bc_hestia_read "crontab -l" 2>/dev/null || true)"
    if grep -q 'v-backup-users-restic' <<<"$cron"; then
      bc_sh_ok "el cron de Restic está activo"
    else
      bc_sh_fail "el cron de Restic NO está activo: configurado pero nunca se ejecuta"
      bc_log "        Actívalo:  backupctl hestia cron"
    fi
  fi

  # === 3. Las claves =========================================================
  bc_sh_cab "3 · Claves de recuperación"
  local n_restic n_rclone
  n_restic="$( { find "$HESTIA_OUTPUT_DIR" -maxdepth 1 -name 'Restic_Configs_*.txt' 2>/dev/null || true; } | wc -l)"
  n_rclone="$( { find "$HESTIA_OUTPUT_DIR" -maxdepth 1 -name 'rclone_*.conf' 2>/dev/null || true; } | wc -l)"

  if (( n_restic > 0 )); then
    local ultima
    ultima="$( { find "$HESTIA_OUTPUT_DIR" -maxdepth 1 -name 'Restic_Configs_*.txt' -printf '%T@ %p\n' 2>/dev/null || true; } | sort -rn | head -1 | cut -d' ' -f2-)"
    bc_sh_ok "claves Restic rescatadas (hace $(bc_age_days "$ultima") días)"
  else
    bc_sh_fail "claves Restic NO rescatadas: el repositorio sería ILEGIBLE"
  fi

  if (( n_rclone > 0 )); then
    bc_sh_ok "rclone.conf rescatado"
  else
    bc_sh_fail "rclone.conf NO rescatado: no se podría LLEGAR al repositorio"
  fi
  (( n_restic == 0 || n_rclone == 0 )) && bc_log "        Rescátalas:  backupctl hestia keys"

  # === 4. Fuera del servidor =================================================
  bc_sh_cab "4 · ¿Hay algo fuera del servidor?"
  if [[ -n "$repo" ]]; then
    case "$repo" in
      rclone:*:/*|*local*) bc_sh_warn "solo hay copias locales: un incendio se lo lleva todo" ;;
      *) bc_sh_ok "Restic envía la cuenta completa a un destino externo" ;;
    esac
  fi
  bc_sh_warn "las claves rescatadas viven en este repositorio git: cópialas también"
  bc_sh_warn "  a un gestor de contraseñas o a otra máquina"

  # === Veredicto =============================================================
  echo
  if (( BC_SH_FALLOS == 0 && BC_SH_AVISOS == 0 )); then
    bc_ok "Blindaje completo: perderías, como mucho, lo del último día."
    return 0
  fi
  if (( BC_SH_FALLOS == 0 )); then
    bc_warn "Blindaje aceptable, con $BC_SH_AVISOS puntos a mejorar."
    return 0
  fi
  bc_err "BLINDAJE INCOMPLETO: $BC_SH_FALLOS fallos y $BC_SH_AVISOS avisos."
  bc_err "Con el servidor perdido hoy, habría cosas que NO podrías recuperar."
  BC_DELIBERATE_EXIT=1
  return 1
}
