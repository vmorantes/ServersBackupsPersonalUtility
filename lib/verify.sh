#!/usr/bin/env bash
# =============================================================================
# lib/verify.sh — verificación de respaldos
# =============================================================================
# Un respaldo que nunca se ha restaurado no es un respaldo: es un archivo.
#
# Hay cuatro niveles, de más barato a más concluyente:
#   1. Estructura del zip (CRC)          — segundos
#   2. Integridad de cada .gz            — segundos
#   3. Sumas SHA-256 contra el MANIFEST  — detecta corrupción archivo a archivo
#   4. Restauración real en una BD desechable — la única prueba concluyente
# =============================================================================

[[ -n "${BC_VERIFY_LOADED:-}" ]] && return 0
BC_VERIFY_LOADED=1

BC_VERIFY_PROBLEMS=0
bc_verify_fail() { bc_err "$*"; BC_VERIFY_PROBLEMS=$(( BC_VERIFY_PROBLEMS + 1 )); }

BC_SCRATCH_DB=""
bc_verify_drop_scratch() {
  [[ -z "$BC_SCRATCH_DB" ]] && return 0
  if bc_mysql -e "DROP DATABASE IF EXISTS $(bc_sql_ident "$BC_SCRATCH_DB")" 2>/dev/null; then
    bc_log "Base de datos temporal $BC_SCRATCH_DB eliminada."
  else
    bc_warn "no se pudo eliminar la base de datos temporal $BC_SCRATCH_DB. Bórrala a mano."
  fi
  BC_SCRATCH_DB=""
}

# -----------------------------------------------------------------------------
# bc_verify_run <archivo|vacío>
# Opciones por variables: BC_OPT_RESTORE_TEST, BC_OPT_WITH_DATA, BC_OPT_QUICK
# -----------------------------------------------------------------------------
bc_verify_run() {
  local zip_path
  zip_path="$(bc_backup_resolve "${1:-}")" \
    || bc_die "no se encontró ningún respaldo. Busca en: $BACKUP_OUTPUT_DIR"

  bc_require_cmd unzip gzip find

  local size age
  size="$(stat -c %s "$zip_path")"
  age="$(bc_age_days "$zip_path")"

  bc_section "Verificación de $(basename "$zip_path")"
  bc_log "Archivo:     $zip_path"
  bc_log "Tamaño:      $(bc_human_size "$size")"
  bc_log "Antigüedad:  $age días"
  # Un respaldo viejo casi siempre significa que el cron dejó de ejecutarse,
  # que es el fallo más silencioso de todos.
  (( age > 2 )) && bc_warn "el respaldo tiene $age días. ¿Sigue funcionando el cron?"

  BC_VERIFY_PROBLEMS=0
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/backupctl-verify.XXXXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'; bc_verify_drop_scratch" RETURN

  # --- 1. Integridad del zip -------------------------------------------------
  bc_step "[1/5] Estructura del zip"
  if unzip -tq "$zip_path" >/dev/null 2>&1; then
    bc_ok "el zip es íntegro (CRC correcto)."
  else
    bc_verify_fail "el zip está corrupto o incompleto. No se puede seguir."
    return 1
  fi

  if [[ "${BC_OPT_QUICK:-0}" == "1" ]]; then
    bc_ok "Verificación rápida superada (--quick: solo se comprobó el zip)."
    return 0
  fi

  # --- 2. Integridad de los .gz ----------------------------------------------
  bc_step "[2/5] Integridad de los archivos comprimidos"
  unzip -qq "$zip_path" -d "$tmp"
  local gz_total=0 gz_bad=0 gz
  while IFS= read -r -d '' gz; do
    gz_total=$(( gz_total + 1 ))
    gzip -t "$gz" 2>/dev/null || { bc_verify_fail "gz corrupto: ${gz#$tmp/}"; gz_bad=$(( gz_bad + 1 )); }
  done < <(find "$tmp" -name '*.gz' -print0)
  (( gz_bad == 0 )) && bc_ok "$gz_total archivos .gz descomprimen correctamente."

  # --- 3. Manifiesto y sumas -------------------------------------------------
  bc_step "[3/5] Manifiesto y sumas de verificación"
  if [[ -f "$tmp/MANIFEST.txt" ]]; then
    local origen fecha mysqlv incluye
    origen="$(awk -F': ' '/^servidor:/{print $2}'  "$tmp/MANIFEST.txt")"
    fecha="$(awk  -F': ' '/^generado:/{print $2}'  "$tmp/MANIFEST.txt")"
    mysqlv="$(awk -F': ' '/^mysql_version:/{print $2}' "$tmp/MANIFEST.txt")"
    incluye="$(awk -F': ' '/^incluye_datos:/{print $2}' "$tmp/MANIFEST.txt")"
    bc_log "Origen: ${origen:-?} · Generado: ${fecha:-?} · MySQL ${mysqlv:-?} · Con datos: ${incluye:-?}"

    local declared_fail
    declared_fail="$(awk -F': ' '/^bases_con_fallos:/{print $2}' "$tmp/MANIFEST.txt")"
    if [[ -n "$declared_fail" && "$declared_fail" != "0" ]]; then
      bc_verify_fail "el propio respaldo declara $declared_fail bases de datos con fallos: $(awk -F': ' '/^lista_fallos:/{print $2}' "$tmp/MANIFEST.txt")"
    fi

    if bc_has_cmd sha256sum; then
      local sums; sums="$(mktemp)"
      # Del manifiesto solo interesan las líneas de suma (hash + ruta ./...)
      grep -E '^[0-9a-f]{64}  \./' "$tmp/MANIFEST.txt" > "$sums" || true
      if [[ -s "$sums" ]]; then
        # sha256sum -c devuelve != 0 cuando alguna suma no cuadra, que es
        # precisamente el caso que queremos tratar aquí: el || true evita que
        # set -e lo convierta en un fallo no controlado.
        local bad
        bad="$( cd "$tmp" && sha256sum -c --quiet "$sums" 2>&1 | head -20 || true )"
        if [[ -n "$bad" ]]; then
          bc_verify_fail "hay archivos cuya suma no coincide con el manifiesto:"
          sed 's/^/        /' <<<"$bad" >&2
        else
          bc_ok "$(wc -l < "$sums") sumas SHA-256 coinciden con el manifiesto."
        fi
      else
        bc_warn "el manifiesto no contiene sumas de verificación."
      fi
      rm -f "$sums"
    fi
  else
    # Los respaldos de versiones anteriores no lo tienen: es un aviso, no un error
    bc_warn "sin MANIFEST.txt (respaldo generado por una versión anterior). Se omiten las sumas."
  fi

  # --- 4. Estructura y contenido por base de datos ----------------------------
  bc_step "[4/5] Estructura y contenido"
  local expected=(database.sql.gz tables.sql.gz data.sql.gz views.sql.gz functions.sql.gz others.sql.gz)
  local db_total=0 db_empty=0 db_dir db_name f tables rows

  # Las filas se acumulan en un archivo y se formatean DESPUÉS, en lugar de
  # canalizar el bucle a bc_table. Una tubería crea una subshell, y allí los
  # incrementos de db_total y —lo importante— de BC_VERIFY_PROBLEMS se
  # perderían: un archivo ausente no llegaría a marcar la verificación como
  # fallida.
  local rows_file; rows_file="$(mktemp)"
  printf 'BASE DE DATOS\tTABLAS\tINSERT\tESTADO\n' > "$rows_file"

  while IFS= read -r db_dir; do
    db_name="$(basename "$db_dir")"
    db_total=$(( db_total + 1 ))
    local state="ok"

    for f in "${expected[@]}"; do
      [[ -f "$db_dir/$f" ]] || { bc_verify_fail "$db_name: falta $f"; state="INCOMPLETA"; }
    done

    # Que un archivo exista y descomprima no significa que tenga contenido:
    # un volcado interrumpido deja archivos válidos pero vacíos.
    if [[ -f "$db_dir/database.sql.gz" ]]; then
      zgrep -q 'CREATE DATABASE' "$db_dir/database.sql.gz" 2>/dev/null \
      || { bc_verify_fail "$db_name: database.sql sin CREATE DATABASE"; state="INCOMPLETA"; }
    fi

    tables=0; rows=0
    [[ -f "$db_dir/tables.sql.gz" ]] && tables="$(zgrep -c 'CREATE TABLE' "$db_dir/tables.sql.gz" 2>/dev/null || true)"
    [[ -f "$db_dir/data.sql.gz"   ]] && rows="$(zgrep -c '^INSERT INTO' "$db_dir/data.sql.gz" 2>/dev/null || true)"

    # Solo se etiqueta el contenido si la estructura estaba completa: un
    # "sin datos" no debe tapar un "INCOMPLETA", que es más grave.
    if [[ "$state" == "ok" ]]; then
      if (( tables == 0 )); then
        state="vacía"
      elif (( rows == 0 )); then
        # Estructura sin datos: puede ser legítimo o un volcado fallido
        state="sin datos"
        db_empty=$(( db_empty + 1 ))
      fi
    fi

    printf '%s\t%s\t%s\t%s\n' "$db_name" "$tables" "$rows" "$state" >> "$rows_file"
  done < <(find "$tmp" -mindepth 1 -maxdepth 1 -type d -not -name 'MANIFEST*' | sort)

  bc_table < "$rows_file"
  rm -f "$rows_file"

  bc_log "Bases de datos en el respaldo: $db_total"
  (( db_empty > 0 )) && bc_warn "$db_empty bases de datos con estructura pero sin ningún INSERT. Comprueba si es lo esperado."

  # --- 5. Prueba de restauración ---------------------------------------------
  if [[ -n "${BC_OPT_RESTORE_TEST:-}" ]]; then
    bc_step "[5/5] Prueba de restauración real"
    bc_verify_restore_test "$tmp" "$BC_OPT_RESTORE_TEST"
  else
    bc_step "[5/5] Prueba de restauración"
    bc_log "Omitida. Úsala con: backupctl verify --restore-test <bd> [--with-data]"
  fi

  echo
  if (( BC_VERIFY_PROBLEMS == 0 )); then
    bc_ok "Verificación superada: $db_total bases de datos, $gz_total archivos."
    return 0
  fi
  bc_err "Verificación FALLIDA: $BC_VERIFY_PROBLEMS problemas."
  BC_DELIBERATE_EXIT=1
  return 1
}

# -----------------------------------------------------------------------------
# Restauración de prueba en una base de datos desechable
# -----------------------------------------------------------------------------
# Es la única comprobación que demuestra que el volcado troceado se puede volver
# a montar. Crea una BD con nombre propio, restaura ahí y la borra siempre.
# -----------------------------------------------------------------------------
bc_verify_restore_test() {
  local extracted="$1" db="$2"
  local src="$extracted/$(bc_safe_name "$db")"

  [[ -d "$src" ]] || { bc_verify_fail "'$db' no está en este respaldo."; return 1; }
  bc_mysql_check || { bc_verify_fail "sin conexión a MySQL: no se puede probar la restauración."; return 1; }

  BC_SCRATCH_DB="verifybk_$(date +%Y%m%d%H%M%S)_$$"
  if ! bc_mysql -e "CREATE DATABASE $(bc_sql_ident "$BC_SCRATCH_DB") CHARACTER SET $MYSQL_CHARSET"; then
    bc_verify_fail "no se pudo crear la base de datos temporal (¿falta el privilegio CREATE?)."
    BC_SCRATCH_DB=""; return 1
  fi
  bc_log "Base de datos temporal: $BC_SCRATCH_DB"

  # database.sql se ignora a propósito: contiene un CREATE DATABASE del nombre
  # ORIGINAL y lo recrearía en el servidor. Las líneas 'USE `original`;' se
  # eliminan para que todo caiga en la BD desechable.
  local seg
  for seg in tables data functions views others; do
    if [[ "$seg" == "data" && "${BC_OPT_WITH_DATA:-0}" != "1" ]]; then
      bc_log "  data omitido (usa --with-data para incluirlo)"
      continue
    fi
    bc_verify_restore_segment "$src" "$seg" "$BC_SCRATCH_DB"
  done

  local t v r g
  t="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.tables   WHERE table_schema=$(bc_sql_quote "$BC_SCRATCH_DB") AND table_type='BASE TABLE'")"
  v="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.views    WHERE table_schema=$(bc_sql_quote "$BC_SCRATCH_DB")")"
  r="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema=$(bc_sql_quote "$BC_SCRATCH_DB")")"
  g="$(bc_mysql_q "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema=$(bc_sql_quote "$BC_SCRATCH_DB")")"

  bc_log "Restaurado: $t tablas, $v vistas, $r rutinas, $g triggers."
  (( t == 0 )) && bc_verify_fail "no se restauró ninguna tabla."

  bc_verify_drop_scratch
}

bc_verify_restore_segment() {
  local src="$1" seg="$2" target="$3"
  local file="$src/$seg.sql.gz"
  [[ -f "$file" ]] || { bc_warn "  $seg: no está en el respaldo"; return 0; }

  local errf; errf="$(mktemp)"
  if zcat "$file" | sed -E 's/^USE `[^`]*`;$//' | bc_mysql "$target" 2>"$errf"; then
    bc_ok "  $seg restaurado."
  else
    bc_verify_fail "  $seg NO se pudo restaurar:"
    sed 's/^/          /' "$errf" >&2
  fi
  rm -f "$errf"
}
