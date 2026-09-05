#!/usr/bin/env bash
# =============================================================================
# lib/logs.sh — consulta de registros
# =============================================================================
[[ -n "${BC_LOGS_LOADED:-}" ]] && return 0
BC_LOGS_LOADED=1

bc_logs_files() {
  [[ -d "$LOG_DIR" ]] || return 0
  find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn | cut -f2-
}

bc_logs_list() {
  local files=()
  mapfile -t files < <(bc_logs_files)
  (( ${#files[@]} == 0 )) && { bc_warn "no hay logs en $LOG_DIR"; return 1; }

  bc_section "Logs en $LOG_DIR"
  {
    printf 'ARCHIVO\tTAMAÑO\tFECHA\tERRORES\tAVISOS\n'
    local f errs warns
    for f in "${files[@]}"; do
      errs="$(grep -c '\[ERROR\]' "$f" 2>/dev/null || true)"
      warns="$(grep -c '\[AVISO\]' "$f" 2>/dev/null || true)"
      printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(basename "$f")" "$(bc_human_size "$(stat -c %s "$f")")" \
        "$(date -d "@$(stat -c %Y "$f")" '+%Y-%m-%d %H:%M')" "$errs" "$warns"
    done
  } | bc_table
}

# Muestra el último log completo, o solo sus errores
bc_logs_show() {
  local mode="${1:-full}"
  local latest; latest="$(bc_logs_files | head -1)"
  [[ -n "$latest" ]] || { bc_warn "no hay logs en $LOG_DIR"; return 1; }

  bc_section "$(basename "$latest")"
  case "$mode" in
    errors)
      # Se muestran también las dos líneas siguientes: los errores de mysqldump
      # llegan en bloque y la primera sola no dice lo suficiente.
      grep -A2 -E '\[(ERROR|AVISO)\]' "$latest" || bc_ok "sin errores ni avisos en este log."
      ;;
    tail) tail -50 "$latest" ;;
    *)    cat "$latest" ;;
  esac
}

# Sigue en vivo el log más reciente
bc_logs_follow() {
  local latest; latest="$(bc_logs_files | head -1)"
  [[ -n "$latest" ]] || bc_die "no hay logs en $LOG_DIR"
  bc_log "Siguiendo $latest (Ctrl-C para salir)"
  tail -f "$latest"
}
