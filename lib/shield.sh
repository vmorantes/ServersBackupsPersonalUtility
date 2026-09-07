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
  # Cuando el perfil apunta a otro servidor, los respaldos y MySQL están ALLÍ.
  # La versión anterior miraba siempre las rutas locales y, desde el portátil,
  # informaba «no hay ningún respaldo» de un servidor que respalda cada noche.
  bc_sh_cab "1 · Bases de datos"
  local edad="" en_zip="" en_mysql="" fuente=""

  if (( remoto )); then
    fuente="$DEPLOY_HOST:$BACKUP_OUTPUT_DIR"
    # Edad en días del zip más reciente, calculada en el servidor.
    edad="$(bc_hestia_read "
      z=\$(ls -t '$BACKUP_OUTPUT_DIR'/all_databases_*.zip 2>/dev/null | head -1)
      [ -n \"\$z\" ] && echo \$(( ( \$(date +%s) - \$(stat -c %Y \"\$z\") ) / 86400 ))" || true)"
    [[ -n "$edad" ]] && en_zip="$(bc_hestia_respaldo_remoto || true)"
    en_mysql="$(bc_hestia_mysql_remoto || true)"
  else
    fuente="$BACKUP_OUTPUT_DIR"
    local zip; zip="$(bc_backup_latest || true)"
    if [[ -n "$zip" ]]; then
      edad="$(bc_age_days "$zip")"
      en_zip="$(unzip -Z1 "$zip" 2>/dev/null | awk -F/ 'NF>1{print $1}' | sort -u || true)"
    fi
    bc_mysql_check >/dev/null 2>&1 && en_mysql="$(bc_mysql_databases 2>/dev/null || true)"
  fi

  if [[ -z "$edad" ]]; then
    bc_sh_fail "no hay ningún respaldo de bases de datos en $fuente"
  else
    local n_zip cuando; n_zip="$(grep -c . <<<"$en_zip" || true)"
    case "$edad" in 0) cuando="de hoy" ;; 1) cuando="de ayer" ;; *) cuando="de hace $edad días" ;; esac
    if   (( edad <= 1 )); then bc_sh_ok "último respaldo $cuando, $n_zip bases"
    elif (( edad <= 3 )); then bc_sh_warn "último respaldo $cuando, $n_zip bases"
    else bc_sh_fail "último respaldo $cuando: el cron podría estar parado"; fi
  fi

  # ¿Coincide con lo que hay AHORA en MySQL? Una base nueva que nadie respalda
  # es el fallo silencioso más caro de todos.
  if [[ -z "$en_mysql" ]]; then
    bc_sh_warn "no se pudo consultar MySQL para comparar"
  else
    local n_bd n_zip2 faltan
    n_bd="$(grep -c . <<<"$en_mysql" || true)"
    n_zip2="$(grep -c . <<<"$en_zip" || true)"
    faltan="$(comm -23 <(sort <<<"$en_mysql") <(sort -u <<<"$en_zip") 2>/dev/null || true)"
    faltan="$(sed '/^$/d' <<<"$faltan")"
    if [[ -z "$faltan" ]] && (( n_bd > 0 )); then
      bc_sh_ok "las $n_bd bases de datos del servidor están en el respaldo"
    else
      bc_sh_fail "hay $n_bd bases en MySQL y $n_zip2 en el último respaldo"
      if [[ -n "$faltan" ]]; then
        bc_log "        SIN RESPALDAR ($(grep -c . <<<"$faltan")):"
        sed 's/^/          - /' <<<"$faltan" | head -20
        (( $(grep -c . <<<"$faltan") > 20 )) && bc_log "          ... y más"
      fi
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

    # Se busca en todos los crontabs: la entrada vive en el de hestiaweb, no en
    # el de root. Ver bc_hestia_cron_donde.
    local cron
    cron="$(bc_hestia_cron_donde)"
    if [[ -n "$cron" ]]; then
      bc_sh_ok "el cron de Restic está activo: ${cron##*:}"
    else
      bc_sh_fail "el cron de Restic NO está activo: configurado pero nunca se ejecuta"
      bc_log "        Actívalo:  backupctl hestia cron"
    fi
  fi

  # === 3. Las claves =========================================================
  bc_sh_cab "3 · Claves de recuperación"
  local n_restic n_rclone
  n_restic="$( { find "$(bc_hestia_salida)" -maxdepth 1 -name 'Restic_Configs_*.txt' 2>/dev/null || true; } | wc -l)"
  n_rclone="$( { find "$(bc_hestia_salida)" -maxdepth 1 -name 'rclone_*.conf' 2>/dev/null || true; } | wc -l)"

  if (( n_restic > 0 )); then
    local ultima
    ultima="$( { find "$(bc_hestia_salida)" -maxdepth 1 -name 'Restic_Configs_*.txt' -printf '%T@ %p\n' 2>/dev/null || true; } | sort -rn | head -1 | cut -d' ' -f2-)"
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
