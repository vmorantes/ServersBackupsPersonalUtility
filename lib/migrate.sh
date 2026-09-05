#!/usr/bin/env bash
# =============================================================================
# lib/migrate.sh — migración de bases de datos entre servidores
# =============================================================================
# Lleva una o varias bases de datos de este servidor a otro, usando el mismo
# formato de respaldo. El volcado ya viene preparado para ser portable: sin
# DEFINER, con SQL SECURITY INVOKER, charset explícito y sin estado de GTID.
#
# Flujo:
#   1. Se usa un respaldo existente o se genera uno nuevo.
#   2. Se transfiere el .zip al destino.
#   3. Se restaura allí con el propio backupctl del destino.
#   4. Se comparan los recuentos de origen y destino.
#
# El paso 4 es el que convierte "he copiado un archivo" en "la migración es
# correcta".
# =============================================================================

[[ -n "${BC_MIGRATE_LOADED:-}" ]] && return 0
BC_MIGRATE_LOADED=1

bc_migrate_run() {
  local target="${BC_OPT_TO:-}"
  local path="${BC_OPT_REMOTE_PATH:-$DEPLOY_PATH}"

  if [[ -z "$target" ]]; then
    [[ -n "$DEPLOY_HOST" ]] || bc_die "indica el destino: backupctl migrate --to usuario@servidor"
    target="$DEPLOY_USER@$DEPLOY_HOST"
  fi

  bc_require_cmd ssh rsync
  bc_section "Migración hacia $target"

  # --- 1. Comprobaciones previas ---------------------------------------------
  bc_log "Comprobando el destino..."
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" "test -x '$path/bin/backupctl'" 2>/dev/null \
    || bc_die "no hay un backupctl ejecutable en $target:$path. Despliégalo antes: backupctl deploy $target"
  bc_ok "backupctl encontrado en el destino."

  local remote_ok
  remote_ok="$(ssh "$target" "'$path/bin/backupctl' config --check >/dev/null 2>&1 && echo si || echo no")"
  [[ "$remote_ok" == "si" ]] || bc_die "la configuración del destino no es válida. Ejecuta allí: $path/bin/backupctl doctor"
  bc_ok "la configuración del destino es válida."

  # --- 2. Respaldo de origen -------------------------------------------------
  local zip_path
  if [[ -n "${BC_OPT_FROM:-}" ]]; then
    zip_path="$(bc_backup_resolve "$BC_OPT_FROM")" || bc_die "no se encontró el respaldo '$BC_OPT_FROM'."
    bc_log "Usando el respaldo existente: $(basename "$zip_path")"
  elif [[ "${BC_OPT_FRESH:-0}" == "1" ]]; then
    bc_log "Generando un respaldo nuevo antes de migrar..."
    bc_backup_run || bc_die "el respaldo de origen falló; no se migra nada."
    zip_path="$(bc_backup_latest)"
  else
    zip_path="$(bc_backup_latest || true)"
    [[ -n "$zip_path" ]] || bc_die "no hay ningún respaldo. Usa --fresh para generar uno ahora."
    local age; age="$(bc_age_days "$zip_path")"
    bc_log "Usando el respaldo más reciente: $(basename "$zip_path") ($age días)"
    (( age > 1 )) && bc_warn "tiene $age días: los cambios posteriores NO se migrarán. Usa --fresh para uno nuevo."
  fi

  # --- 3. Bases de datos a migrar --------------------------------------------
  local dbs
  if [[ -n "${BC_OPT_DATABASES:-}" ]]; then
    dbs="$(tr ',' '\n' <<<"$BC_OPT_DATABASES" | sed '/^$/d')"
  else
    dbs="$(bc_archive_databases "$zip_path")"
  fi
  local n; n="$(grep -c . <<<"$dbs" || true)"
  bc_log "Bases de datos a migrar: $n"
  sed 's/^/        - /' <<<"$dbs"

  # Recuentos en origen, para poder comparar después
  local origin_counts; origin_counts="$(mktemp)"
  local db
  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    printf '%s\t%s\n' "$db" "$(bc_mysql_table_count "$db" 2>/dev/null || echo '?')" >> "$origin_counts"
  done <<<"$dbs"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): se habría transferido $(basename "$zip_path") ($(bc_human_size "$(stat -c %s "$zip_path")")) y restaurado $n bases de datos en $target."
    rm -f "$origin_counts"
    return 0
  fi

  bc_warn "Esto va a ESCRIBIR en las bases de datos del servidor $target."
  bc_confirm "¿Continuar con la migración de $n bases de datos?" n \
    || { bc_log "Cancelado."; rm -f "$origin_counts"; return 0; }

  # --- 4. Transferencia ------------------------------------------------------
  local remote_zip="$path/output/mysql_backups/$(basename "$zip_path")"
  bc_section "Transferencia"
  bc_log "Enviando $(bc_human_size "$(stat -c %s "$zip_path")")..."
  ssh "$target" "mkdir -p '$path/output/mysql_backups'"
  # -P: reanudable y con progreso. Un respaldo de 40 MB por una línea lenta
  # agradece poder continuar donde se cortó.
  rsync -azP "$zip_path" "$target:$remote_zip" \
    || bc_die "falló la transferencia."
  bc_ok "Transferido a $target:$remote_zip"

  # Verificación del archivo YA EN DESTINO: una transferencia corrupta que se
  # restaura es peor que una que falla.
  bc_log "Verificando el archivo en el destino..."
  ssh "$target" "'$path/bin/backupctl' verify '$remote_zip' --quick" >/dev/null 2>&1 \
    || bc_die "el archivo transferido no supera la verificación en el destino."
  bc_ok "El archivo llegó íntegro."

  # --- 5. Restauración en el destino -----------------------------------------
  bc_section "Restauración en $target"
  local failed=0 done_n=0
  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    local into="$db"
    [[ -n "${BC_OPT_PREFIX:-}" ]] && into="${BC_OPT_PREFIX}${db}"
    bc_step "  $db → $into"
    if ssh "$target" "'$path/bin/backupctl' restore '$remote_zip' '$db' --into '$into' --yes" 2>&1 | sed 's/^/        /'; then
      done_n=$(( done_n + 1 ))
    else
      bc_err "  falló la restauración de '$db'"
      failed=$(( failed + 1 ))
    fi
  done <<<"$dbs"

  # --- 6. Comparación origen / destino ---------------------------------------
  bc_section "Comprobación"
  local mismatch=0
  # Igual que en verify: las filas se acumulan y se formatean después. Si el
  # bucle se canalizara a bc_table correría en una subshell y el recuento de
  # discrepancias volvería siempre 0, dando por buena una migración incompleta.
  local rows_file; rows_file="$(mktemp)"
  printf 'BASE DE DATOS\tORIGEN\tDESTINO\tRESULTADO\n' > "$rows_file"

  while IFS=$'\t' read -r db o_tables; do
    local into="$db"
    [[ -n "${BC_OPT_PREFIX:-}" ]] && into="${BC_OPT_PREFIX}${db}"
    local d_tables
    d_tables="$(ssh "$target" "'$path/bin/backupctl' exec-count '$into'" 2>/dev/null || echo '?')"
    local verdict="ok"
    if [[ "$o_tables" != "$d_tables" ]]; then verdict="DIFIERE"; mismatch=$(( mismatch + 1 )); fi
    printf '%s\t%s\t%s\t%s\n' "$db" "$o_tables" "$d_tables" "$verdict" >> "$rows_file"
  done < "$origin_counts"

  bc_table < "$rows_file"
  rm -f "$rows_file" "$origin_counts"

  echo
  bc_log "Restauradas: $done_n. Con fallos: $failed. Recuentos que no cuadran: $mismatch."

  if (( failed > 0 || mismatch > 0 )); then
    bc_err "La migración terminó con incidencias. Revisa el detalle antes de dar por buena la máquina nueva."
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  bc_ok "Migración completada y comprobada."
  bc_log "Antes de apagar el origen, ejecuta en el destino:"
  bc_log "    $path/bin/backupctl backup && $path/bin/backupctl verify --restore-test <una_bd> --with-data"
  return 0
}
