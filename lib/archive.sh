#!/usr/bin/env bash
# =============================================================================
# lib/archive.sh — consulta de respaldos ya existentes
# =============================================================================
# list    — qué respaldos hay
# inspect — qué contiene uno concreto (lee el MANIFEST, no extrae nada)
# status  — ¿está sano el sistema de respaldo ahora mismo?
# =============================================================================

[[ -n "${BC_ARCHIVE_LOADED:-}" ]] && return 0
BC_ARCHIVE_LOADED=1

# -----------------------------------------------------------------------------
# list
# -----------------------------------------------------------------------------
bc_archive_list() {
  local files=()
  mapfile -t files < <(bc_backup_list_files)

  if (( ${#files[@]} == 0 )); then
    bc_warn "no hay ningún respaldo en $BACKUP_OUTPUT_DIR"
    return 1
  fi

  bc_section "Respaldos en $BACKUP_OUTPUT_DIR"
  {
    printf 'ARCHIVO\tTAMAÑO\tFECHA\tEDAD\tBD\n'
    local f size age date_str dbs
    for f in "${files[@]}"; do
      size="$(stat -c %s "$f")"
      age="$(bc_age_days "$f")"
      date_str="$(date -d "@$(stat -c %Y "$f")" '+%Y-%m-%d %H:%M')"
      # Contar entradas del zip es barato; no hace falta extraer nada
      dbs="$(unzip -Z1 "$f" 2>/dev/null | awk -F/ 'NF>1 {print $1}' | sort -u | grep -c . || true)"
      printf '%s\t%s\t%s\t%sd\t%s\n' "$(basename "$f")" "$(bc_human_size "$size")" "$date_str" "$age" "$dbs"
    done
  } | bc_table

  local total
  total="$(du -sh "$BACKUP_OUTPUT_DIR" 2>/dev/null | cut -f1)"
  echo
  bc_log "Total: ${#files[@]} respaldos, $total en disco."
  bc_log "Retención: $BACKUP_RETENTION_DAYS días, conservando siempre los $BACKUP_KEEP_MIN más recientes."
}

# Lista las bases de datos que contiene un respaldo
bc_archive_databases() {
  local zip_path
  zip_path="$(bc_backup_resolve "${1:-}")" || bc_die "no se encontró el respaldo."
  unzip -Z1 "$zip_path" 2>/dev/null | awk -F/ 'NF>1 {print $1}' | sort -u
}

# -----------------------------------------------------------------------------
# inspect
# -----------------------------------------------------------------------------
# Lee el MANIFEST sin extraer el resto del zip: instantáneo incluso con 40 MB.
bc_archive_inspect() {
  local zip_path
  zip_path="$(bc_backup_resolve "${1:-}")" \
    || bc_die "no se encontró el respaldo. Busca en: $BACKUP_OUTPUT_DIR"

  bc_section "Contenido de $(basename "$zip_path")"
  bc_log "Ruta:       $zip_path"
  bc_log "Tamaño:     $(bc_human_size "$(stat -c %s "$zip_path")")"
  bc_log "Antigüedad: $(bc_age_days "$zip_path") días"
  echo

  local manifest
  manifest="$(unzip -p "$zip_path" MANIFEST.txt 2>/dev/null || true)"

  if [[ -z "$manifest" ]]; then
    bc_warn "este respaldo no tiene MANIFEST.txt (versión anterior de backupctl)."
    bc_log "Bases de datos que contiene:"
    bc_archive_databases "$zip_path" | sed 's/^/        /'
    return 0
  fi

  bc_step "Metadatos"
  grep -E '^[a-z_]+:' <<<"$manifest" | sed 's/^/        /'

  echo
  bc_step "Inventario"
  {
    printf 'BASE DE DATOS\tTABLAS\tVISTAS\tINSERT\tTAMAÑO ORIGEN\n'
    # El inventario son las líneas con 5 campos separados por tabulador
    awk -F'\t' 'NF==5 && $1 !~ /^#/ {print}' <<<"$manifest" \
      | while IFS=$'\t' read -r db t v r bytes; do
          printf '%s\t%s\t%s\t%s\t%s\n' "$db" "$t" "$v" "$r" "$(bc_human_size "${bytes:-0}")"
        done
  } | bc_table

  echo
  local sums
  sums="$(grep -cE '^[0-9a-f]{64}  \./' <<<"$manifest" || true)"
  bc_log "Sumas SHA-256 registradas: $sums"
  bc_log "Verifícalas con: backupctl verify $(basename "$zip_path")"
}

# -----------------------------------------------------------------------------
# status — el panel de un vistazo
# -----------------------------------------------------------------------------
# Responde a la pregunta que uno se hace de verdad: "¿estoy protegido ahora
# mismo?". Devuelve código != 0 si algo no está bien, para poder encadenarlo
# en una comprobación automática.
# -----------------------------------------------------------------------------
bc_archive_status() {
  local problems=0

  bc_section "Estado del respaldo — perfil '$BC_PROFILE'"

  # --- Último respaldo -------------------------------------------------------
  local latest
  latest="$(bc_backup_latest || true)"
  if [[ -z "$latest" ]]; then
    bc_err "NO HAY NINGÚN RESPALDO en $BACKUP_OUTPUT_DIR"
    problems=$(( problems + 1 ))
  else
    local age size
    age="$(bc_age_days "$latest")"
    size="$(bc_human_size "$(stat -c %s "$latest")")"
    if (( age <= 1 )); then
      bc_ok "Último respaldo: $(basename "$latest") — hace $age días, $size"
    elif (( age <= 3 )); then
      bc_warn "Último respaldo: $(basename "$latest") — hace $age días, $size"
      problems=$(( problems + 1 ))
    else
      bc_err "Último respaldo: $(basename "$latest") — hace $age días, $size. ¿El cron está parado?"
      problems=$(( problems + 1 ))
    fi
  fi

  # --- Inventario ------------------------------------------------------------
  local count total
  count="$(bc_backup_list_files | grep -c . || true)"
  total="$(du -sh "$BACKUP_OUTPUT_DIR" 2>/dev/null | cut -f1 || echo '?')"
  bc_log "Respaldos guardados: $count ($total)"

  # --- Disco -----------------------------------------------------------------
  local free_mb pct
  free_mb="$(df -Pm "$BACKUP_OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
  pct="$(df -P "$BACKUP_OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' || true)"
  if [[ -z "$free_mb" ]]; then
    bc_warn "Disco: no se pudo consultar $BACKUP_OUTPUT_DIR (¿todavía no existe?)"
  else
    if (( free_mb < MIN_FREE_MB )); then
      bc_err "Disco: ${free_mb}MB libres (${pct}% usado). Por debajo del mínimo de ${MIN_FREE_MB}MB."
      problems=$(( problems + 1 ))
    else
      bc_ok "Disco: ${free_mb}MB libres (${pct}% usado)."
    fi
  fi

  # --- MySQL -----------------------------------------------------------------
  if bc_mysql_check >/dev/null 2>&1; then
    local dbs
    dbs="$(bc_mysql_databases 2>/dev/null | grep -c . || echo 0)"
    bc_ok "MySQL: accesible como '$MYSQL_USER', $dbs bases de datos a respaldar."
  else
    bc_err "MySQL: NO se puede conectar como '$MYSQL_USER'."
    problems=$(( problems + 1 ))
  fi

  # --- Avisos ----------------------------------------------------------------
  if [[ -n "${NOTIFY_EMAIL:-}${NOTIFY_COMMAND:-}${HEALTHCHECK_URL:-}" ]]; then
    local canales=""
    [[ -n "${NOTIFY_EMAIL:-}"    ]] && canales+="correo "
    [[ -n "${NOTIFY_COMMAND:-}"  ]] && canales+="orden "
    [[ -n "${HEALTHCHECK_URL:-}" ]] && canales+="healthcheck "
    bc_ok "Avisos configurados: $canales"
  else
    bc_warn "Sin avisos configurados: un fallo bajo cron pasaría inadvertido."
    problems=$(( problems + 1 ))
  fi

  # --- Último log ------------------------------------------------------------
  local last_log
  last_log="$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -printf '%T@\t%p\n' 2>/dev/null \
              | sort -rn | head -1 | cut -f2- || true)"
  if [[ -n "$last_log" ]]; then
    local errs
    errs="$(grep -c '\[ERROR\]' "$last_log" 2>/dev/null || true)"
    if (( errs > 0 )); then
      bc_err "Último log ($(basename "$last_log")): $errs errores."
      problems=$(( problems + 1 ))
    else
      bc_ok "Último log ($(basename "$last_log")): sin errores."
    fi
  fi

  echo
  if (( problems == 0 )); then
    bc_ok "Todo correcto."
    return 0
  fi
  bc_warn "$problems puntos requieren atención."
  BC_DELIBERATE_EXIT=1
  return 1
}
