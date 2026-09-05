#!/usr/bin/env bash
# =============================================================================
# lib/restic.sh — claves de repositorio Restic de HestiaCP
# =============================================================================
# Recorre la instalación de HestiaCP buscando restic.conf y los concatena en un
# único .txt etiquetado por usuario.
#
# Garantías, todas orientadas a no acabar con un archivo incompleto que parezca
# válido (la versión original podía generar uno vacío sin avisar de nada):
#   - exige root: sin él, find no puede entrar en los directorios de HestiaCP,
#   - aborta si no encuentra ningún restic.conf, en lugar de escribir un vacío,
#   - escribe en un temporal y solo publica si el volcado fue completo, de modo
#     que un fallo a mitad deja intacto el archivo del día anterior,
#   - deja el archivo como propiedad de $USER_NAME: el script corre como root
#     pero el archivo vive en el home del usuario, y su propio respaldo de
#     HestiaCP debe poder leerlo.
# =============================================================================

[[ -n "${BC_RESTIC_LOADED:-}" ]] && return 0
BC_RESTIC_LOADED=1

bc_restic_run() {
  bc_section "Claves de repositorio Restic (HestiaCP)"

  [[ "$(id -u)" -eq 0 ]] || bc_die "debe ejecutarse como root: sudo backupctl restic"
  [[ -d "$HESTIA_DIR" ]] || bc_die "no existe $HESTIA_DIR. ¿Es este un servidor HestiaCP? Ajusta HESTIA_DIR en $BC_ENV_FILE."

  mkdir -p "$HESTIA_OUTPUT_DIR"

  local out_path="$HESTIA_OUTPUT_DIR/Restic_Configs_$(date +%Y%m%d).txt"
  local tmp_path; tmp_path="$(mktemp "$HESTIA_OUTPUT_DIR/.Restic_Configs.XXXXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_path'" RETURN

  local confs=()
  mapfile -d '' -t confs < <(find "$HESTIA_DIR" -type f -name 'restic.conf' -print0 2>/dev/null)

  if (( ${#confs[@]} == 0 )); then
    bc_die "no se encontró ningún restic.conf en $HESTIA_DIR. No se escribe nada."
  fi
  bc_log "Encontrados ${#confs[@]} archivos restic.conf."

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_log "Simulación (--dry-run). Se habrían volcado:"
    local c
    for c in "${confs[@]}"; do bc_log "        $(basename "$(dirname "$c")")  ($c)"; done
    return 0
  fi

  local conf
  {
    printf '# Claves de repositorio Restic de HestiaCP\n'
    printf '# Servidor: %s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf '# Generado: %s por backupctl %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$BC_VERSION"
    printf '# Repositorios: %s\n' "${#confs[@]}"
    printf '\n=====================\n\n'
    for conf in "${confs[@]}"; do
      printf '# %s:\n' "$(basename "$(dirname "$conf")")"
      cat -- "$conf" || bc_die "no se pudo leer $conf"
      printf '\n\n=====================\n\n'
    done
  } > "$tmp_path"

  [[ -s "$tmp_path" ]] || bc_die "el archivo generado quedó vacío. No se publica."

  # Publicación atómica: hasta aquí no se ha tocado el archivo anterior
  mv -f "$tmp_path" "$out_path"
  trap - RETURN

  chown "$USER_NAME":"$USER_NAME" "$out_path" 2>/dev/null \
    || bc_warn "no se pudo cambiar el propietario a $USER_NAME (¿existe el usuario?)"

  bc_ok "Escrito: $out_path ($(bc_human_size "$(stat -c %s "$out_path")"), ${#confs[@]} repositorios)"

  bc_prune "$HESTIA_OUTPUT_DIR" 'Restic_Configs_*.txt' "$RESTIC_RETENTION_DAYS" 2 "claves Restic" 0
}

# Muestra qué repositorios hay registrados, sin volcar las claves
bc_restic_list() {
  [[ -d "$HESTIA_DIR" ]] || bc_die "no existe $HESTIA_DIR."
  bc_section "Repositorios Restic detectados en $HESTIA_DIR"
  local confs=() c
  mapfile -d '' -t confs < <(find "$HESTIA_DIR" -type f -name 'restic.conf' -print0 2>/dev/null)
  (( ${#confs[@]} == 0 )) && { bc_warn "ninguno. ¿Hace falta ser root para leerlos?"; return 1; }
  {
    printf 'USUARIO\tARCHIVO\n'
    for c in "${confs[@]}"; do
      printf '%s\t%s\n' "$(basename "$(dirname "$c")")" "$c"
    done
  } | bc_table
}
