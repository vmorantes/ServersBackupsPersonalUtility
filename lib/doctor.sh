#!/usr/bin/env bash
# =============================================================================
# lib/doctor.sh — diagnóstico del entorno
# =============================================================================
# Comprueba, en un solo paso, todo lo que hace falta para que el respaldo
# funcione. Es lo primero que hay que ejecutar cuando algo va mal, y lo último
# tras instalar en un servidor nuevo.
# =============================================================================

[[ -n "${BC_DOCTOR_LOADED:-}" ]] && return 0
BC_DOCTOR_LOADED=1

BC_DOC_FAIL=0
BC_DOC_WARN=0
bc_doc_ok()   { printf '  %s✓%s %s\n' "$BC_GRN" "$BC_RST" "$*"; }
bc_doc_warn() { BC_DOC_WARN=$((BC_DOC_WARN+1)); printf '  %s!%s %s\n' "$BC_YEL" "$BC_RST" "$*"; }
bc_doc_fail() { BC_DOC_FAIL=$((BC_DOC_FAIL+1)); printf '  %s✗%s %s\n' "$BC_RED" "$BC_RST" "$*"; }

bc_doctor_run() {
  BC_DOC_FAIL=0; BC_DOC_WARN=0

  bc_section "Diagnóstico — perfil '$BC_PROFILE'"

  # --- 1. Órdenes del sistema ------------------------------------------------
  printf '\n%sÓrdenes necesarias%s\n' "$BC_BLD" "$BC_RST"
  local c
  for c in mysql mysqldump gzip zip unzip find sha256sum flock df stat awk sed; do
    if bc_has_cmd "$c"; then bc_doc_ok "$c  ($(command -v "$c"))"
    else bc_doc_fail "$c NO ESTÁ INSTALADO"; fi
  done
  printf '\n%sÓrdenes opcionales%s\n' "$BC_BLD" "$BC_RST"
  for c in curl mail rsync ssh whiptail dialog column zgrep; do
    if bc_has_cmd "$c"; then bc_doc_ok "$c"
    else bc_doc_warn "$c ausente $(bc_doctor_why "$c")"; fi
  done

  # --- 2. Configuración ------------------------------------------------------
  printf '\n%sConfiguración%s\n' "$BC_BLD" "$BC_RST"
  bc_doc_ok "perfil '$BC_PROFILE' desde $BC_ENV_FILE"
  if bc_config_check >/dev/null 2>&1; then bc_doc_ok "la configuración es válida"
  else bc_doc_fail "la configuración tiene problemas (ejecuta: backupctl config --check)"; fi

  # --- 3. Directorios --------------------------------------------------------
  printf '\n%sDirectorios%s\n' "$BC_BLD" "$BC_RST"
  local d
  for d in "$BACKUP_OUTPUT_DIR" "$BACKUP_WORK_DIR" "$LOG_DIR"; do
    if [[ -d "$d" ]]; then
      if [[ -w "$d" ]]; then bc_doc_ok "$d (escribible)"
      else bc_doc_fail "$d existe pero NO es escribible"; fi
    else
      if mkdir -p "$d" 2>/dev/null; then bc_doc_ok "$d (creado ahora)"
      else bc_doc_fail "$d no existe y no se puede crear"; fi
    fi
  done

  # --- 4. Espacio en disco ---------------------------------------------------
  printf '\n%sEspacio en disco%s\n' "$BC_BLD" "$BC_RST"
  local free_mb pct
  free_mb="$(df -Pm "$BACKUP_WORK_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
  pct="$(df -P "$BACKUP_WORK_DIR" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
  if [[ -z "$free_mb" ]]; then bc_doc_fail "no se pudo consultar el espacio libre"
  elif (( free_mb < MIN_FREE_MB )); then bc_doc_fail "${free_mb}MB libres, por debajo del mínimo (${MIN_FREE_MB}MB)"
  elif (( pct > 90 )); then bc_doc_warn "${free_mb}MB libres pero el disco está al ${pct}%"
  else bc_doc_ok "${free_mb}MB libres (${pct}% usado)"; fi

  # --- 5. MySQL --------------------------------------------------------------
  printf '\n%sMySQL%s\n' "$BC_BLD" "$BC_RST"
  if bc_mysql_check >/dev/null 2>&1; then
    bc_doc_ok "conexión correcta como '$MYSQL_USER'"
    bc_doc_ok "versión del servidor: $(bc_mysql_version)"
    local n; n="$(bc_mysql_databases 2>/dev/null | grep -c . || echo 0)"
    if (( n > 0 )); then bc_doc_ok "$n bases de datos a respaldar"
    else bc_doc_fail "0 bases de datos: revisa EXCLUDE_DBS y los privilegios"; fi

    # Privilegios concretos que exige el volcado completo
    local grants; grants="$(bc_mysql_grants)"
    local priv
    for priv in SELECT "SHOW VIEW" TRIGGER "LOCK TABLES"; do
      if grep -qiE "ALL PRIVILEGES|$priv" <<<"$grants"; then bc_doc_ok "privilegio $priv"
      else bc_doc_warn "sin privilegio $priv: parte del volcado podría fallar"; fi
    done

    local nid; nid="$(bc_mysql_non_innodb 2>/dev/null | grep -c . || echo 0)"
    if (( nid > 0 )); then
      bc_doc_warn "$nid tablas no InnoDB: --single-transaction no garantiza coherencia en ellas"
    else
      bc_doc_ok "todas las tablas son InnoDB (instantánea coherente garantizada)"
    fi
  else
    bc_doc_fail "NO se puede conectar como '$MYSQL_USER'. Revisa $BC_ENV_FILE."
  fi

  # --- 6. Capacidades de mysqldump -------------------------------------------
  printf '\n%sCapacidades de mysqldump%s\n' "$BC_BLD" "$BC_RST"
  if bc_has_cmd mysqldump; then
    local help; help="$(mysqldump --help 2>/dev/null || true)"
    grep -q -- '--single-transaction' <<<"$help" && bc_doc_ok "--single-transaction" || bc_doc_fail "sin --single-transaction"
    grep -q -- '--hex-blob'           <<<"$help" && bc_doc_ok "--hex-blob" || bc_doc_warn "sin --hex-blob: riesgo con columnas binarias"
    grep -q -- '--column-statistics'  <<<"$help" && bc_doc_ok "--column-statistics (se desactivará)" || bc_doc_ok "sin --column-statistics (cliente MariaDB, correcto)"
    grep -q -- '--set-gtid-purged'    <<<"$help" && bc_doc_ok "--set-gtid-purged (se pondrá en OFF)" || bc_doc_ok "sin --set-gtid-purged (no aplica)"
  fi

  # --- 7. Respaldos existentes -----------------------------------------------
  printf '\n%sRespaldos%s\n' "$BC_BLD" "$BC_RST"
  local latest
  latest="$(bc_backup_latest || true)"
  if [[ -z "$latest" ]]; then
    bc_doc_warn "todavía no hay ningún respaldo"
  else
    local age; age="$(bc_age_days "$latest")"
    if   (( age <= 1 )); then bc_doc_ok "el más reciente tiene $age días"
    elif (( age <= 3 )); then bc_doc_warn "el más reciente tiene $age días"
    else bc_doc_fail "el más reciente tiene $age días: el cron podría estar parado"; fi
    local n; n="$(bc_backup_list_files | grep -c . || true)"
    bc_doc_ok "$n respaldos guardados ($(du -sh "$BACKUP_OUTPUT_DIR" 2>/dev/null | cut -f1))"
  fi

  # --- 8. Automatización -----------------------------------------------------
  printf '\n%sAutomatización%s\n' "$BC_BLD" "$BC_RST"
  local ct
  ct="$(crontab -l 2>/dev/null || true)"
  if grep -q 'backupctl' <<<"$ct"; then
    bc_doc_ok "hay entradas de backupctl en el crontab"
    # El % sin escapar en crontab se traduce a salto de línea y parte la orden
    if grep 'backupctl' <<<"$ct" | grep -qE '[^\\]%'; then
      bc_doc_fail "hay un % sin escapar en el crontab: cron lo convierte en salto de línea y parte la orden"
    fi
  else
    bc_doc_warn "sin entradas de backupctl en el crontab (usa: backupctl cron --install)"
  fi

  if [[ -n "${NOTIFY_EMAIL:-}${NOTIFY_COMMAND:-}${HEALTHCHECK_URL:-}" ]]; then
    bc_doc_ok "hay al menos un canal de aviso configurado"
  else
    bc_doc_warn "sin avisos: un fallo bajo cron pasaría inadvertido"
  fi

  # --- Resumen ---------------------------------------------------------------
  echo
  if (( BC_DOC_FAIL == 0 && BC_DOC_WARN == 0 )); then
    bc_ok "Diagnóstico superado sin incidencias."
    return 0
  fi
  if (( BC_DOC_FAIL == 0 )); then
    bc_warn "Diagnóstico con $BC_DOC_WARN avisos y ningún fallo. Se puede operar."
    return 0
  fi
  bc_err "Diagnóstico: $BC_DOC_FAIL fallos y $BC_DOC_WARN avisos. Corrige los fallos antes de confiar en el respaldo."
  BC_DELIBERATE_EXIT=1
  return 1
}

# Explica para qué sirve cada orden opcional, para que el aviso sea accionable
bc_doctor_why() {
  case "$1" in
    curl)     echo "(hace falta para HEALTHCHECK_URL)" ;;
    mail)     echo "(hace falta para NOTIFY_EMAIL)" ;;
    rsync|ssh) echo "(hacen falta para deploy y migrate)" ;;
    whiptail|dialog) echo "(la TUI usará el menú de texto simple)" ;;
    column)   echo "(las tablas se alinearán peor)" ;;
    zgrep)    echo "(verify no podrá inspeccionar el contenido comprimido)" ;;
    *)        echo "" ;;
  esac
}
