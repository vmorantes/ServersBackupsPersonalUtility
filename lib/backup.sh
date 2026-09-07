#!/usr/bin/env bash
# =============================================================================
# lib/backup.sh — respaldo de bases de datos
# =============================================================================
# Genera por cada base de datos seis archivos:
#   database.sql   CREATE DATABASE con charset y collation exactos
#   tables.sql     estructura de tablas (sin datos, sin triggers)
#   data.sql       datos (sin estructura, sin triggers)
#   views.sql      definiciones de vistas
#   functions.sql  funciones y procedimientos almacenados
#   others.sql     triggers y eventos
#
# Cada uno se comprime a .gz y todos se empaquetan en un .zip con un MANIFEST.
#
# El troceado no es capricho: permite restaurar solo la estructura, solo los
# datos, o solo las vistas, que es lo que hace manejable una migración.
# =============================================================================

[[ -n "${BC_BACKUP_LOADED:-}" ]] && return 0
BC_BACKUP_LOADED=1

BC_BACKUP_SEGMENTS=(database tables data views functions others)

# -----------------------------------------------------------------------------
# Localizar respaldos existentes
# -----------------------------------------------------------------------------
bc_backup_list_files() {
  [[ -d "$BACKUP_OUTPUT_DIR" ]] || return 0
  find "$BACKUP_OUTPUT_DIR" -maxdepth 1 -type f -name 'all_databases_*.zip' \
    -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-
}

bc_backup_latest() { bc_backup_list_files | head -1; }

# Resuelve el argumento del usuario: ruta, nombre de archivo o vacío (= el más
# reciente). Así `verify`, `restore` e `inspect` aceptan lo mismo.
bc_backup_resolve() {
  local want="${1:-}"
  if [[ -z "$want" ]]; then
    local latest; latest="$(bc_backup_latest)"
    [[ -n "$latest" ]] || return 1
    printf '%s' "$latest"; return 0
  fi
  [[ -f "$want" ]] && { printf '%s' "$want"; return 0; }
  [[ -f "$BACKUP_OUTPUT_DIR/$want" ]] && { printf '%s' "$BACKUP_OUTPUT_DIR/$want"; return 0; }
  return 1
}

# -----------------------------------------------------------------------------
# Volcado de un segmento, con detección real de errores
# -----------------------------------------------------------------------------
# Esta función es la garantía central del sistema. mysqldump con --force termina
# con código 0 aunque no haya podido volcar una tabla, así que el código de
# salida no basta: hay que leer stderr. Si se envía a /dev/null (como hacía la
# versión original de estos scripts), el resultado es un .zip de aspecto normal
# al que le faltan datos, sin ninguna señal de ello hasta el día que se
# necesita restaurar.
#
# Uso: bc_dump_segment <archivo_destino> <strip:yes|no> <opciones de mysqldump...>
# Devuelve 0 si el volcado fue limpio, 1 si hubo un error real.
# -----------------------------------------------------------------------------
# Bases de datos que exigen --lock-tables en vez de --single-transaction.
declare -A BC_DBS_NO_TRX=()

bc_dump_segment() {
  local out_file="$1"; shift
  local strip="$1"; shift
  local err_file="$BC_TEMP_DIR/.dump_err"
  local rc=0

  : > "$err_file"

  set +e
  if [[ "$strip" == "yes" ]]; then
    bc_mysqldump "${BC_DUMP_OPTS[@]}" "$@" 2>"$err_file" | bc_strip_definers >> "$out_file"
  else
    bc_mysqldump "${BC_DUMP_OPTS[@]}" "$@" 2>"$err_file" >> "$out_file"
  fi
  rc=${PIPESTATUS[0]}
  set -e

  if [[ -s "$err_file" ]]; then
    local fatal=0
    grep -qiE 'error|denied|corrupt|crashed|can.t connect|unknown|doesn.t exist' "$err_file" && fatal=1
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if (( fatal )); then bc_err "        mysqldump: $line"
      else bc_warn "        mysqldump: $line"; fi
    done < "$err_file"
    (( fatal )) && return 1
  fi

  return "$rc"
}

# -----------------------------------------------------------------------------
# Respaldo de UNA base de datos. Devuelve 0 si todo fue bien.
# -----------------------------------------------------------------------------
bc_backup_database() {
  local db="$1" idx="$2" total="$3"
  local failed=0

  bc_step "[$idx/$total] $db"

  local db_path="$BC_TEMP_DIR/$(bc_safe_name "$db")"
  mkdir -p "$db_path"

  local db_q db_i header
  db_q="$(bc_sql_quote "$db")"
  db_i="$(bc_sql_ident "$db")"
  # Cabecera USE que hace cada archivo autónomo: se restaura con `mysql < x.sql`
  header="USE $db_i;"

  # --- 1. database.sql -------------------------------------------------------
  # Se construye a mano (no lo da mysqldump con un solo nombre de BD) para
  # conservar charset y collation exactos del origen. Restaurar con el charset
  # equivocado corrompe los datos de forma silenciosa.
  local info charset collate
  info="$(bc_mysql_db_charset "$db" || true)"
  charset="$(awk '{print $1}' <<<"$info")"
  collate="$(awk '{print $2}' <<<"$info")"
  if [[ -z "$charset" || -z "$collate" ]]; then
    bc_err "    no se pudo leer charset/collation de '$db'"
    failed=1
    charset="${charset:-$MYSQL_CHARSET}"
    collate="${collate:-${MYSQL_CHARSET}_general_ci}"
  fi
  {
    echo "-- backupctl: CREATE DATABASE de '$db'"
    echo "CREATE DATABASE IF NOT EXISTS $db_i"
    echo "  CHARACTER SET $charset"
    echo "  COLLATE $collate;"
    echo "$header"
  } > "$db_path/database.sql"

  # Esta base se vuelca con bloqueo si tiene tablas no transaccionales. Se
  # cambia la opción, no se añade: --single-transaction y --lock-tables son
  # mutuamente excluyentes y mysqldump ignora una de las dos en silencio.
  local -a opts_previas=("${BC_DUMP_OPTS[@]}")
  if [[ -n "${BC_DBS_NO_TRX[$db]:-}" ]]; then
    local i
    for i in "${!BC_DUMP_OPTS[@]}"; do
      [[ "${BC_DUMP_OPTS[$i]}" == "--single-transaction" ]] && BC_DUMP_OPTS[$i]="--lock-tables"
    done
    bc_debug "    '$db' tiene tablas no transaccionales: --lock-tables"
  fi
  # shellcheck disable=SC2064
  trap 'BC_DUMP_OPTS=("${opts_previas[@]}")' RETURN

  # --- 2. tables.sql ---------------------------------------------------------
  echo "$header" > "$db_path/tables.sql"
  bc_dump_segment "$db_path/tables.sql" yes --no-data --skip-triggers "$db" || failed=1

  # --- 3. data.sql -----------------------------------------------------------
  # Sin paso por sed: los datos no llevan DEFINER y una fila que contuviera ese
  # texto quedaría alterada. Además es el archivo más grande con diferencia.
  echo "$header" > "$db_path/data.sql"
  if [[ "${BC_OPT_NO_DATA:-0}" == "1" ]]; then
    echo "-- backupctl: volcado sin datos (--no-data)" >> "$db_path/data.sql"
  else
    bc_dump_segment "$db_path/data.sql" no --no-create-info --skip-triggers "$db" || failed=1
  fi

  # --- 4. views.sql ----------------------------------------------------------
  # Cada vista por separado, para poder nombrarla en el log y tratar con
  # seguridad los nombres con espacios. --no-data es lo que produce el
  # CREATE VIEW; --no-create-info lo suprimiría.
  echo "$header" > "$db_path/views.sql"
  local views view_count=0 view
  views="$(bc_mysql_views "$db" || true)"
  if [[ -n "$views" ]]; then
    while IFS= read -r view; do
      [[ -z "$view" ]] && continue
      view_count=$(( view_count + 1 ))
      bc_debug "    vista: $view"
      bc_dump_segment "$db_path/views.sql" yes \
        --no-data --skip-triggers "$db" "$view" || failed=1
    done <<<"$views"
  fi

  # --- 5. functions.sql ------------------------------------------------------
  echo "$header" > "$db_path/functions.sql"
  bc_dump_segment "$db_path/functions.sql" yes \
    --no-create-info --no-data --routines --skip-triggers "$db" || failed=1

  # --- 6. others.sql ---------------------------------------------------------
  echo "$header" > "$db_path/others.sql"
  bc_dump_segment "$db_path/others.sql" yes \
    --no-create-info --no-data --triggers --events "$db" || failed=1

  # --- Recuento para el manifiesto -------------------------------------------
  local tables rows bytes
  tables="$(grep -c '^CREATE TABLE' "$db_path/tables.sql" 2>/dev/null || true)"
  rows="$(grep -c '^INSERT INTO' "$db_path/data.sql" 2>/dev/null || true)"
  bytes="$(bc_mysql_db_size "$db" 2>/dev/null || echo 0)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$db" "$tables" "$view_count" "$rows" "$bytes" \
    >> "$BC_TEMP_DIR/.stats"

  if (( failed )); then
    bc_err "    FALLO en '$db': el volcado puede estar incompleto"
    return 1
  fi
  bc_ok "    $db — $tables tablas, $view_count vistas, $rows INSERT"
  return 0
}

# -----------------------------------------------------------------------------
# Manifiesto
# -----------------------------------------------------------------------------
# Va dentro del zip y describe lo que contiene: origen, fecha, versión del
# servidor, inventario por base de datos y suma SHA-256 de cada archivo.
#
# Sirve para tres cosas: inspeccionar un respaldo sin extraerlo entero, detectar
# manipulación o corrupción archivo a archivo, y saber qué esperabas encontrar
# cuando algo no cuadra.
# -----------------------------------------------------------------------------
bc_backup_write_manifest() {
  local manifest="$BC_TEMP_DIR/MANIFEST.txt"
  local host; host="$(hostname -f 2>/dev/null || hostname)"

  {
    echo "# backupctl MANIFEST"
    echo "formato_version: 1"
    echo "generado: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "perfil: $BC_PROFILE"
    echo "servidor: $host"
    echo "usuario_mysql: $MYSQL_USER"
    echo "mysql_version: $(bc_mysql_version)"
    echo "charset: $MYSQL_CHARSET"
    echo "backupctl_version: $BC_VERSION"
    echo "incluye_datos: $([[ "${BC_OPT_NO_DATA:-0}" == "1" ]] && echo no || echo si)"
    echo "definers_eliminados: si"
    echo "bases_de_datos: $BC_DB_COUNT"
    echo "bases_con_fallos: ${#BC_FAILED_DBS[@]}"
    if (( ${#BC_FAILED_DBS[@]} > 0 )); then
      echo "lista_fallos: ${BC_FAILED_DBS[*]}"
    fi
    echo ""
    echo "# inventario: base_de_datos<TAB>tablas<TAB>vistas<TAB>inserts<TAB>bytes_en_origen"
    if [[ -f "$BC_TEMP_DIR/.stats" ]]; then sort "$BC_TEMP_DIR/.stats"; fi
    echo ""
    echo "# sumas SHA-256 de cada archivo comprimido"
    ( cd "$BC_TEMP_DIR" && find . -name '*.gz' -print0 | sort -z \
        | xargs -0 sha256sum 2>/dev/null || true )
  } > "$manifest"

  bc_log "Manifiesto escrito ($(wc -l < "$manifest") líneas)."
}

# -----------------------------------------------------------------------------
# Operación completa
# -----------------------------------------------------------------------------
bc_backup_run() {
  local started; started="$(date +%s)"
  local stamp; stamp="$(date +%Y%m%d_%H%M%S)"

  BC_FAILED_DBS=()
  BC_DB_COUNT=0

  bc_section "Respaldo de bases de datos — perfil '$BC_PROFILE'"

  # --- Comprobaciones previas ------------------------------------------------
  bc_require_cmd mysql mysqldump gzip zip unzip find sha256sum
  mkdir -p "$BACKUP_OUTPUT_DIR" "$BACKUP_WORK_DIR" "$LOG_DIR"
  bc_mysql_check || bc_die "revisa MYSQL_USER / MYSQL_PASS / MYSQL_HOST en $BC_ENV_FILE"
  bc_log "Conectado a MySQL $(bc_mysql_version) como '$MYSQL_USER'."

  # Espacio en disco: mejor no empezar que llenar el disco a mitad del volcado
  # y dejar un respaldo truncado (y de paso tumbar el servidor).
  local free_mb; free_mb="$(df -Pm "$BACKUP_WORK_DIR" | awk 'NR==2 {print $4}')"
  local data_bytes; data_bytes="$(bc_mysql_total_size 2>/dev/null || echo 0)"
  local need_mb=$(( (data_bytes / 1048576) * DISK_SAFETY_FACTOR ))
  (( need_mb < MIN_FREE_MB )) && need_mb="$MIN_FREE_MB"
  bc_log "Datos a respaldar: $(bc_human_size "$data_bytes"). Libre en disco: ${free_mb}MB. Necesario estimado: ${need_mb}MB."
  if (( free_mb < need_mb )); then
    bc_die "espacio insuficiente: ${free_mb}MB libres, se estiman ${need_mb}MB necesarios."
  fi

  # --- Motores no transaccionales --------------------------------------------
  # --single-transaction toma una instantánea coherente, pero solo de InnoDB.
  # En una tabla MyISAM o MEMORY no hace nada: si alguien escribe mientras se
  # vuelca, el respaldo puede quedar internamente incoherente —una fila hija sin
  # su fila padre— y eso no se nota hasta el día que hay que restaurar.
  #
  # Antes esto solo se avisaba. Ahora, las bases que tengan alguna tabla así se
  # vuelcan con --lock-tables, que sí garantiza coherencia. El bloqueo es de
  # lectura, dura lo que dura el volcado de ESA base, y no afecta a las demás.
  BC_DBS_NO_TRX=()
  local esquemas; esquemas="$(bc_mysql_schemas_no_transaccionales 2>/dev/null || true)"
  if [[ -n "$esquemas" ]]; then
    local e
    while IFS= read -r e; do [[ -n "$e" ]] && BC_DBS_NO_TRX["$e"]=1; done <<<"$esquemas"
    bc_warn "bases con tablas no InnoDB ($(grep -c . <<<"$esquemas")): se volcarán con --lock-tables"
    bc_log  "        $(tr '\n' ' ' <<<"$esquemas")"
    bc_log  "        --single-transaction no cubre MyISAM ni MEMORY. El bloqueo es"
    bc_log  "        de lectura y solo mientras se vuelca esa base."
    local detalle; detalle="$(bc_mysql_non_innodb 2>/dev/null || true)"
    [[ -n "$detalle" ]] && { printf '%s\n' "$detalle" | head -5 | sed 's/^/          /'; \
      local n; n="$(grep -c . <<<"$detalle" || true)"; (( n > 5 )) && bc_log "          ... y $(( n - 5 )) tablas más."; }
  fi

  # --- Selección de bases de datos -------------------------------------------
  local dbs
  dbs="$(bc_mysql_databases)" || bc_die "no se pudo listar las bases de datos."
  [[ -n "$dbs" ]] || bc_die "no hay ninguna base de datos que respaldar (revisa EXCLUDE_DBS y los permisos)."

  if [[ -n "${BC_OPT_ONLY:-}" ]]; then
    local filtered="" want
    while IFS= read -r want; do
      [[ -z "$want" ]] && continue
      if grep -qxF "$want" <<<"$dbs"; then filtered+="$want"$'\n'
      else bc_warn "la base de datos '$want' no existe o está excluida; se omite."; fi
    done < <(tr ',' '\n' <<<"$BC_OPT_ONLY")
    dbs="$(sed '/^$/d' <<<"$filtered")"
    [[ -n "$dbs" ]] || bc_die "ninguna de las bases de datos indicadas en --only existe."
  fi

  if [[ -n "${BC_OPT_EXCLUDE:-}" ]]; then
    local skip
    while IFS= read -r skip; do
      [[ -z "$skip" ]] && continue
      dbs="$(grep -vxF "$skip" <<<"$dbs" || true)"
    done < <(tr ',' '\n' <<<"$BC_OPT_EXCLUDE")
  fi

  BC_DB_COUNT="$(grep -c . <<<"$dbs" || true)"
  bc_log "Bases de datos a respaldar: $BC_DB_COUNT"
  sed 's/^/        - /' <<<"$dbs"

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha escrito nada. Se habrían respaldado $BC_DB_COUNT bases de datos."
    return 0
  fi

  # --- Preparación del área de trabajo ---------------------------------------
  bc_clean_orphans "$BACKUP_WORK_DIR"
  BC_TEMP_DIR="$BACKUP_WORK_DIR/temp_sql_${stamp}_$$"
  mkdir -p "$BC_TEMP_DIR"
  : > "$BC_TEMP_DIR/.stats"

  local zip_name="all_databases_${stamp}.zip"
  local final_zip="$BACKUP_OUTPUT_DIR/$zip_name"
  bc_log "Trabajo temporal: $BC_TEMP_DIR"
  bc_log "Destino final:    $final_zip"

  # Cachea las opciones de mysqldump una sola vez
  mapfile -t BC_DUMP_OPTS < <(bc_mysqldump_opts)
  bc_debug "opciones mysqldump: ${BC_DUMP_OPTS[*]}"

  # --- Bucle principal -------------------------------------------------------
  local idx=0 db
  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    idx=$(( idx + 1 ))
    bc_backup_database "$db" "$idx" "$BC_DB_COUNT" || BC_FAILED_DBS+=("$db")
  done <<<"$dbs"

  rm -f "$BC_TEMP_DIR/.dump_err"

  # --- Compresión ------------------------------------------------------------
  bc_section "Empaquetado"
  bc_log "Comprimiendo los .sql a .gz..."
  find "$BC_TEMP_DIR" -name '*.sql' -exec gzip -9 {} +

  # Verificación de la compresión ANTES de empaquetar: un .gz truncado aquí
  # sería un respaldo irrecuperable que nadie notaría hasta la restauración.
  bc_log "Verificando integridad de los .gz..."
  if ! find "$BC_TEMP_DIR" -name '*.gz' -exec gzip -t {} + 2>&1; then
    bc_die "hay archivos .gz corruptos. Se aborta sin publicar el respaldo."
  fi

  bc_backup_write_manifest

  bc_log "Creando el zip: $final_zip"
  # -0: no recomprimir. El contenido ya viene comprimido con gzip -9; volver a
  # comprimirlo gastaría CPU sin reducir el tamaño.
  ( cd "$BC_TEMP_DIR" && zip -r0 -q "$final_zip" . ) \
    || bc_die "falló la creación del zip."

  # --- Verificación del artefacto publicado ----------------------------------
  bc_log "Verificando el zip..."
  if ! unzip -tq "$final_zip" >/dev/null 2>&1; then
    rm -f "$final_zip"
    bc_die "el zip generado no supera la verificación. Se ha eliminado en lugar de publicarlo."
  fi

  local entries expected size
  entries="$(unzip -Z1 "$final_zip" | grep -c '\.sql\.gz$' || true)"
  expected=$(( BC_DB_COUNT * 6 ))
  size="$(stat -c %s "$final_zip")"
  bc_ok "Zip verificado: $(bc_human_size "$size"), $entries archivos .sql.gz (esperados $expected)."
  (( entries < expected )) && bc_warn "faltan archivos en el zip: algún volcado no se generó."

  # --- Retención -------------------------------------------------------------
  bc_retention_apply 0

  # --- Resumen ---------------------------------------------------------------
  local elapsed=$(( $(date +%s) - started ))
  bc_section "Resumen"
  bc_log "Perfil:              $BC_PROFILE"
  bc_log "Bases procesadas:    $BC_DB_COUNT"
  bc_log "Avisos:              $BC_WARN_COUNT"
  bc_log "Duración:            $(bc_duration "$elapsed")"
  bc_log "Archivo:             $final_zip ($(bc_human_size "$size"))"

  if (( ${#BC_FAILED_DBS[@]} > 0 )); then
    bc_err "Bases de datos CON FALLOS (${#BC_FAILED_DBS[@]}):"
    printf '        - %s\n' "${BC_FAILED_DBS[@]}" >&2
    bc_err "El respaldo está INCOMPLETO. Log: ${BC_LOG_FILE:-(pantalla)}"
    bc_notify_failure \
      "[$BC_PROFILE] Respaldo MySQL INCOMPLETO: ${#BC_FAILED_DBS[@]} BD con fallos" \
      "$(printf 'Servidor: %s\nPerfil: %s\nArchivo: %s\nDuración: %s\n\nBases de datos con fallos:\n%s\n\nLog: %s\n' \
          "$(hostname -f 2>/dev/null || hostname)" "$BC_PROFILE" "$final_zip" \
          "$(bc_duration "$elapsed")" "$(printf '  - %s\n' "${BC_FAILED_DBS[@]}")" \
          "${BC_LOG_FILE:-n/d}")" || true
    # Que el respaldo falle es malo; que además nadie se entere es lo que
    # convierte el fallo en pérdida. Se dice aparte, y bien alto.
    if (( BC_NOTIFY_OK == 0 )); then
      bc_err "Y NO SE PUDO AVISAR A NADIE de este fallo:"
      printf '%s' "$BC_NOTIFY_MOTIVOS" >&2
    fi
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  bc_ok "Respaldo completado correctamente."
  bc_notify_success
  return 0
}
