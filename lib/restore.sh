#!/usr/bin/env bash
# =============================================================================
# lib/restore.sh — restauración
# =============================================================================
# Restaura una o varias bases de datos desde un respaldo. Pensado tanto para
# recuperar tras un desastre como para migrar a otro servidor.
#
# Precauciones deliberadas:
#   - Nunca sobrescribe una base de datos existente sin confirmación explícita.
#   - --into permite restaurar con OTRO nombre, que es lo que hace posible
#     probar una restauración en paralelo a la base de datos viva.
#   - --dry-run enseña exactamente lo que haría sin tocar nada.
# =============================================================================

[[ -n "${BC_RESTORE_LOADED:-}" ]] && return 0
BC_RESTORE_LOADED=1

# Orden de restauración. No es arbitrario: las vistas pueden depender de tablas
# y de funciones, y los triggers de las tablas. database va primero porque crea
# la base de datos con su charset correcto.
BC_RESTORE_ORDER=(database tables data functions views others)

# -----------------------------------------------------------------------------
# bc_restore_run <archivo|vacío> <bd_origen>
# Opciones: BC_OPT_INTO, BC_OPT_SEGMENTS, BC_OPT_DRY, BC_ASSUME_YES
# -----------------------------------------------------------------------------
bc_restore_run() {
  local zip_arg="${1:-}" db="${2:-}"
  [[ -n "$db" ]] || bc_die "indica qué base de datos restaurar. Ver: backupctl list --databases"

  local zip_path
  zip_path="$(bc_backup_resolve "$zip_arg")" \
    || bc_die "no se encontró el respaldo indicado. Busca en: $BACKUP_OUTPUT_DIR"

  bc_require_cmd unzip gzip mysql
  bc_mysql_check || bc_die "sin conexión a MySQL."

  local target="${BC_OPT_INTO:-$db}"

  bc_section "Restauración"
  bc_log "Respaldo: $zip_path"
  bc_log "Origen:   $db"
  bc_log "Destino:  $target$([[ "$target" != "$db" ]] && echo '   (renombrada con --into)')"

  # --- Segmentos a restaurar -------------------------------------------------
  local segments=("${BC_RESTORE_ORDER[@]}")
  if [[ -n "${BC_OPT_SEGMENTS:-}" ]]; then
    mapfile -t segments < <(tr ',' '\n' <<<"$BC_OPT_SEGMENTS" | sed '/^$/d')
    local s ok
    for s in "${segments[@]}"; do
      ok=0
      local known
      for known in "${BC_RESTORE_ORDER[@]}"; do [[ "$s" == "$known" ]] && ok=1; done
      (( ok )) || bc_die "segmento desconocido: '$s'. Válidos: ${BC_RESTORE_ORDER[*]}"
    done
  fi
  bc_log "Segmentos: ${segments[*]}"

  # --- Extracción ------------------------------------------------------------
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/backupctl-restore.XXXXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  local member; member="$(bc_safe_name "$db")"
  if ! unzip -qq "$zip_path" "$member/*" -d "$tmp" 2>/dev/null; then
    bc_err "'$db' no está en este respaldo. Contiene:"
    unzip -Z1 "$zip_path" | awk -F/ 'NF>1 {print $1}' | sort -u | sed 's/^/        /' >&2
    bc_die "elige una de las anteriores."
  fi
  local src="$tmp/$member"

  # --- Comprobación de destino ----------------------------------------------
  local exists tables_now
  exists="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name=$(bc_sql_quote "$target")")"
  if [[ "$exists" != "0" ]]; then
    tables_now="$(bc_mysql_table_count "$target")"
    bc_warn "la base de datos '$target' YA EXISTE en el servidor y tiene $tables_now tablas."
    bc_warn "Restaurar encima puede sobrescribir tablas con los datos del respaldo."
    if [[ "${BC_OPT_DRY:-0}" != "1" ]]; then
      bc_confirm "¿Continuar y restaurar sobre '$target'?" n \
        || bc_die "cancelado por el usuario."
    fi
  fi

  # --- Plan ------------------------------------------------------------------
  local seg file total_bytes=0 size
  bc_log "Plan:"
  for seg in "${segments[@]}"; do
    file="$src/$seg.sql.gz"
    if [[ -f "$file" ]]; then
      size="$(stat -c %s "$file")"
      total_bytes=$(( total_bytes + size ))
      bc_log "        $seg.sql.gz  ($(bc_human_size "$size"))"
    else
      bc_warn "        $seg.sql.gz  NO ESTÁ en el respaldo, se omite"
    fi
  done

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha ejecutado ningún SQL. Se habrían aplicado $(bc_human_size "$total_bytes") comprimidos."
    return 0
  fi

  # --- Ejecución -------------------------------------------------------------
  local failed=0 applied=0
  for seg in "${segments[@]}"; do
    file="$src/$seg.sql.gz"
    [[ -f "$file" ]] || continue
    bc_step "  aplicando $seg..."
    if bc_restore_apply "$file" "$seg" "$db" "$target"; then
      applied=$(( applied + 1 ))
    else
      failed=$(( failed + 1 ))
    fi
  done

  # --- Comprobación posterior ------------------------------------------------
  local t v r g
  t="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.tables   WHERE table_schema=$(bc_sql_quote "$target") AND table_type='BASE TABLE'")"
  v="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.views    WHERE table_schema=$(bc_sql_quote "$target")")"
  r="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema=$(bc_sql_quote "$target")")"
  g="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema=$(bc_sql_quote "$target")")"

  bc_section "Resultado"
  bc_log "Base de datos '$target': $t tablas, $v vistas, $r rutinas, $g triggers."
  bc_log "Segmentos aplicados: $applied. Con fallos: $failed."

  if (( failed > 0 )); then
    bc_err "La restauración terminó con errores. Revisa la salida anterior."
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  bc_ok "Restauración completada."
  return 0
}

# -----------------------------------------------------------------------------
# Aplica un segmento
# -----------------------------------------------------------------------------
# Reescribe la cabecera 'USE `origen`;' cuando el destino tiene otro nombre. Es
# lo que permite restaurar una copia junto a la base de datos viva sin tocarla.
#
# En el segmento 'database' además se reescribe el CREATE DATABASE, que si no
# recrearía el nombre original.
# -----------------------------------------------------------------------------
bc_restore_apply() {
  local file="$1" seg="$2" origen="$3" target="$4"
  local errf; errf="$(mktemp)"
  local rc=0
  local t_ident; t_ident="$(bc_sql_ident "$target")"

  set +e
  if [[ "$seg" == "database" ]]; then
    # Se sustituye cualquier identificador tras CREATE DATABASE / USE por el
    # destino, y se ejecuta sin seleccionar base de datos previa.
    zcat "$file" \
      | sed -E "s/^(CREATE DATABASE IF NOT EXISTS )\`[^\`]*\`/\1$t_ident/; s/^USE \`[^\`]*\`;/USE $t_ident;/" \
      | bc_mysql 2>"$errf"
    rc=${PIPESTATUS[2]}
  else
    # Para el resto se elimina el USE y se selecciona el destino en el cliente
    zcat "$file" \
      | sed -E 's/^USE `[^`]*`;$//' \
      | bc_mysql "$target" 2>"$errf"
    rc=${PIPESTATUS[2]}
  fi
  set -e

  if (( rc != 0 )) || [[ -s "$errf" ]]; then
    if grep -qiE 'error' "$errf"; then
      bc_err "    $seg falló:"
      sed 's/^/          /' "$errf" >&2
      rm -f "$errf"; return 1
    fi
    [[ -s "$errf" ]] && { bc_warn "    $seg (avisos):"; sed 's/^/          /' "$errf" >&2; }
  fi
  rm -f "$errf"
  bc_ok "    $seg aplicado."
  return 0
}
