#!/usr/bin/env bash
# =============================================================================
# lib/retention.sh — borrado de artefactos antiguos
# =============================================================================
# Sin retención, ~40 MB diarios se convierten en 1,2 GB al mes y el disco acaba
# lleno, que es la forma más tonta de quedarse sin respaldos.
# =============================================================================

[[ -n "${BC_RETENTION_LOADED:-}" ]] && return 0
BC_RETENTION_LOADED=1

# bc_prune <dir> <patrón> <días> <mínimo_a_conservar> <etiqueta> [dry_run]
#
# El "mínimo a conservar" es una red de seguridad deliberada: nunca se borran
# los N más recientes aunque superen la antigüedad máxima. Sin eso, un cron
# parado varias semanas haría que la primera ejecución borrase absolutamente
# todos los respaldos por viejos.
bc_prune() {
  local dir="$1" pattern="$2" days="$3" keep_min="$4" label="$5" dry="${6:-0}"

  [[ -d "$dir" ]] || return 0
  if (( days <= 0 )); then
    bc_log "Retención de $label desactivada (0 días)."
    return 0
  fi

  local files=()
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name "$pattern" \
                        -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
  (( ${#files[@]} == 0 )) && { bc_log "Retención de $label: nada que revisar."; return 0; }

  local now; now="$(date +%s)"
  local i f mtime age deleted=0 freed=0 size

  for (( i = keep_min; i < ${#files[@]}; i++ )); do
    f="${files[$i]}"
    mtime="$(stat -c %Y "$f" 2>/dev/null || echo "$now")"
    age=$(( (now - mtime) / 86400 ))
    (( age > days )) || continue

    size="$(stat -c %s "$f" 2>/dev/null || echo 0)"
    if (( dry )); then
      bc_log "  [simulación] se borraría $(basename "$f") (${age} días, $(bc_human_size "$size"))"
    else
      rm -f "$f" && bc_log "  borrado $(basename "$f") (${age} días, $(bc_human_size "$size"))"
    fi
    deleted=$(( deleted + 1 )); freed=$(( freed + size ))
  done

  bc_log "Retención de $label: $deleted borrados ($(bc_human_size "$freed") liberados), $(( ${#files[@]} - deleted )) conservados. Mínimo protegido: $keep_min."
}

# Aplica toda la política de retención del perfil
bc_retention_apply() {
  local dry="${1:-0}"
  bc_section "Retención"
  bc_prune "$BACKUP_OUTPUT_DIR" 'all_databases_*.zip'  "$BACKUP_RETENTION_DAYS" "$BACKUP_KEEP_MIN" "respaldos"     "$dry"
  bc_prune "$LOG_DIR"           '*.log'                "$LOG_RETENTION_DAYS"    2                  "logs"          "$dry"
  bc_prune "$HESTIA_OUTPUT_DIR" 'Restic_Configs_*.txt' "$RESTIC_RETENTION_DAYS" 2                  "claves Restic" "$dry"
}

# Temporales de ejecuciones que murieron sin poder limpiar. Antes se acumulaban
# indefinidamente porque cada corrida solo borraba el suyo (lleva marca de
# tiempo en el nombre, así que nunca coincidía con los ajenos).
bc_clean_orphans() {
  local dir="${1:-$BACKUP_WORK_DIR}"
  [[ -d "$dir" ]] || return 0
  local orphans
  orphans="$(find "$dir" -maxdepth 1 -type d -name 'temp_sql_*' -mmin +1440 2>/dev/null || true)"
  [[ -z "$orphans" ]] && return 0
  bc_warn "eliminando temporales huérfanos de ejecuciones anteriores:"
  printf '%s\n' "$orphans" | sed 's/^/        /'
  printf '%s\n' "$orphans" | while IFS= read -r d; do [[ -n "$d" ]] && rm -rf "$d"; done
}
