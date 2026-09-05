#!/usr/bin/env bash
# =============================================================================
# lib/tui.sh — interfaz interactiva
# =============================================================================
# La "compuerta" para personas: los mismos módulos que usa el cron, pero
# navegables. Pensada para cuando no recuerdas el nombre exacto de una orden.
#
# Usa whiptail o dialog si están instalados; si no, cae a un menú numerado en
# texto plano que funciona en cualquier terminal, incluida una sesión SSH mínima.
#
# Las operaciones largas (respaldo, migración) NO se ejecutan dentro de una
# ventana de diálogo: se sale al terminal para ver el progreso en vivo y se
# vuelve al menú al terminar. Una barra de progreso que oculta el log es peor
# que no tener barra.
# =============================================================================

[[ -n "${BC_TUI_LOADED:-}" ]] && return 0
BC_TUI_LOADED=1

BC_DIALOG=""
bc_tui_detect() {
  if   [[ "${BC_TUI_PLAIN:-0}" == "1" ]]; then BC_DIALOG=""
  elif bc_has_cmd whiptail; then BC_DIALOG="whiptail"
  elif bc_has_cmd dialog;   then BC_DIALOG="dialog"
  else BC_DIALOG=""; fi
  bc_debug "TUI: ${BC_DIALOG:-texto plano}"
}

# -----------------------------------------------------------------------------
# Primitivas
# -----------------------------------------------------------------------------
# bc_tui_menu <título> <texto> <etiqueta> <descripción> ...
# Escribe la etiqueta elegida por stdout. Código != 0 si se cancela.
bc_tui_menu() {
  local title="$1" text="$2"; shift 2

  if [[ -n "$BC_DIALOG" ]]; then
    local n=$(( $# / 2 ))
    # 3>&1 1>&2 2>&3 intercambia stdout y stderr: whiptail dibuja en stderr y
    # devuelve la selección por stdout.
    "$BC_DIALOG" --title "$title" --notags --menu "$text" $(( n + 9 )) 76 "$n" "$@" 3>&1 1>&2 2>&3
    return $?
  fi

  # --- Menú en texto plano ---------------------------------------------------
  local tags=() items=() i=1
  while (( $# > 0 )); do tags+=("$1"); items+=("$2"); shift 2; done

  # El menú se DIBUJA EN STDERR a propósito. El llamador captura stdout con
  # $(...) para leer la etiqueta elegida; si el menú saliera por stdout se lo
  # tragaría la sustitución de órdenes y la pantalla quedaría en blanco. Es el
  # mismo convenio que sigue whiptail.
  {
    printf '\n%s%s%s\n' "$BC_BLD$BC_CYA" "$title" "$BC_RST"
    printf '%b\n\n' "$text"
    for i in "${!tags[@]}"; do
      printf '  %s%2d%s) %s\n' "$BC_BLD" $(( i + 1 )) "$BC_RST" "${items[$i]}"
    done
    printf '\n   %s0%s) Volver / Salir\n\n' "$BC_BLD" "$BC_RST"
  } >&2

  local choice
  read -r -p "Opción: " choice
  [[ "$choice" == "0" || -z "$choice" ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#tags[@]} )) || return 1
  printf '%s' "${tags[$(( choice - 1 ))]}"
}

bc_tui_input() {
  local title="$1" text="$2" default="${3:-}"
  if [[ -n "$BC_DIALOG" ]]; then
    "$BC_DIALOG" --title "$title" --inputbox "$text" 10 70 "$default" 3>&1 1>&2 2>&3
    return $?
  fi
  # Igual que en el menú: la pregunta va a stderr, la respuesta a stdout.
  local v
  printf '%s%s%s [%s]: ' "$BC_BLD" "$text" "$BC_RST" "${default:-vacío}" >&2
  read -r v
  printf '%s' "${v:-$default}"
}

bc_tui_yesno() {
  local title="$1" text="$2"
  if [[ -n "$BC_DIALOG" ]]; then
    "$BC_DIALOG" --title "$title" --yesno "$text" 12 70
    return $?
  fi
  bc_confirm "$text" n
}

bc_tui_msg() {
  local title="$1" text="$2"
  if [[ -n "$BC_DIALOG" ]]; then
    "$BC_DIALOG" --title "$title" --msgbox "$text" 14 70
  else
    printf '\n%s%s%s\n%b\n' "$BC_BLD" "$title" "$BC_RST" "$text"
    read -r -p "Pulsa Enter para continuar... " _
  fi
}

# Ejecuta una operación en el terminal limpio, con salida en vivo, y espera.
# Es lo que permite ver el progreso de un respaldo de 76 bases de datos.
bc_tui_exec() {
  local title="$1"; shift
  clear 2>/dev/null || true
  printf '%s%s== %s ==%s\n\n' "$BC_BLD" "$BC_CYA" "$title" "$BC_RST"
  local rc=0
  "$@" || rc=$?
  echo
  if (( rc == 0 )); then printf '%s✓ Operación terminada correctamente.%s\n' "$BC_GRN" "$BC_RST"
  else printf '%s✗ Terminó con código %d. Revisa la salida.%s\n' "$BC_RED" "$rc" "$BC_RST"; fi
  echo
  read -r -p "Pulsa Enter para volver al menú... " _
  return 0
}

# Elige una base de datos de las que hay en un respaldo
bc_tui_pick_database() {
  local zip_path="$1"
  local dbs=() args=() db
  mapfile -t dbs < <(bc_archive_databases "$zip_path")
  (( ${#dbs[@]} == 0 )) && return 1
  for db in "${dbs[@]}"; do args+=("$db" "$db"); done
  bc_tui_menu "Bases de datos" "Elige una base de datos del respaldo:" "${args[@]}"
}

# Elige un archivo de respaldo
bc_tui_pick_backup() {
  local files=() args=() f
  mapfile -t files < <(bc_backup_list_files)
  (( ${#files[@]} == 0 )) && return 1
  for f in "${files[@]}"; do
    args+=("$f" "$(basename "$f")  [$(bc_human_size "$(stat -c %s "$f")"), $(bc_age_days "$f")d]")
  done
  bc_tui_menu "Respaldos" "Elige un respaldo:" "${args[@]}"
}

# -----------------------------------------------------------------------------
# Menú principal
# -----------------------------------------------------------------------------
bc_tui_main() {
  bc_tui_detect
  local choice
  while true; do
    choice="$(bc_tui_menu \
      "backupctl $BC_VERSION — perfil '$BC_PROFILE'" \
      "Ecosistema de respaldo y migración.\nServidor: $(hostname 2>/dev/null)" \
      estado    "Estado actual del sistema de respaldo" \
      doctor    "Diagnóstico completo del entorno" \
      backup    "Respaldar las bases de datos ahora" \
      verify    "Verificar un respaldo" \
      restore   "Restaurar una base de datos" \
      migrate   "Servidores remotos: subir, descargar, migrar" \
      archivos  "Respaldos guardados" \
      restic    "Claves Restic de HestiaCP" \
      cron      "Programación automática" \
      config    "Configuración del perfil" \
      logs      "Registros" \
      perfil    "Cambiar de perfil / servidor" \
    )" || break

    case "$choice" in
      estado)   bc_tui_exec "Estado"       bc_archive_status ;;
      doctor)   bc_tui_exec "Diagnóstico"  bc_doctor_run ;;
      backup)   bc_tui_menu_backup ;;
      verify)   bc_tui_menu_verify ;;
      restore)  bc_tui_menu_restore ;;
      migrate)  bc_tui_menu_migrate ;;
      archivos) bc_tui_menu_archive ;;
      restic)   bc_tui_menu_restic ;;
      cron)     bc_tui_menu_cron ;;
      config)   bc_tui_menu_config ;;
      logs)     bc_tui_menu_logs ;;
      perfil)   bc_tui_switch_profile ;;
    esac
  done
  clear 2>/dev/null || true
  printf 'Hasta luego.\n'
}

# -----------------------------------------------------------------------------
# Submenús
# -----------------------------------------------------------------------------
bc_tui_menu_backup() {
  local c
  c="$(bc_tui_menu "Respaldo" "¿Qué quieres respaldar?" \
    todo     "Todas las bases de datos" \
    una      "Solo una base de datos" \
    estruct  "Todas, solo estructura (sin datos)" \
    simular  "Simular: enseñar qué haría, sin escribir" \
  )" || return 0

  case "$c" in
    todo)    BC_OPT_ONLY=""; BC_OPT_NO_DATA=0; BC_OPT_DRY=0; bc_tui_exec "Respaldo completo" bc_backup_run ;;
    estruct) BC_OPT_ONLY=""; BC_OPT_NO_DATA=1; BC_OPT_DRY=0; bc_tui_exec "Respaldo sin datos" bc_backup_run ;;
    simular) BC_OPT_ONLY=""; BC_OPT_NO_DATA=0; BC_OPT_DRY=1; bc_tui_exec "Simulación" bc_backup_run; BC_OPT_DRY=0 ;;
    una)
      local dbs=() args=() db
      mapfile -t dbs < <(bc_mysql_databases 2>/dev/null)
      (( ${#dbs[@]} == 0 )) && { bc_tui_msg "Sin bases de datos" "No se pudo listar ninguna base de datos. Ejecuta el diagnóstico."; return 0; }
      for db in "${dbs[@]}"; do args+=("$db" "$db"); done
      local pick; pick="$(bc_tui_menu "Bases de datos" "Elige cuál respaldar:" "${args[@]}")" || return 0
      BC_OPT_ONLY="$pick"; BC_OPT_NO_DATA=0; BC_OPT_DRY=0
      bc_tui_exec "Respaldo de $pick" bc_backup_run
      BC_OPT_ONLY=""
      ;;
  esac
}

bc_tui_menu_verify() {
  local c
  c="$(bc_tui_menu "Verificación" "Del más rápido al más concluyente:" \
    rapido   "Rápida: solo el zip (segundos)" \
    completa "Completa: zip, .gz, sumas y contenido" \
    elegir   "Completa, eligiendo qué respaldo" \
    restaura "Prueba de restauración REAL en una BD desechable" \
  )" || return 0

  case "$c" in
    rapido)   BC_OPT_QUICK=1; BC_OPT_RESTORE_TEST=""; bc_tui_exec "Verificación rápida" bc_verify_run ""; BC_OPT_QUICK=0 ;;
    completa) BC_OPT_QUICK=0; BC_OPT_RESTORE_TEST=""; bc_tui_exec "Verificación completa" bc_verify_run "" ;;
    elegir)
      local f; f="$(bc_tui_pick_backup)" || return 0
      BC_OPT_QUICK=0; BC_OPT_RESTORE_TEST=""
      bc_tui_exec "Verificación de $(basename "$f")" bc_verify_run "$f"
      ;;
    restaura)
      local f; f="$(bc_tui_pick_backup)" || return 0
      local db; db="$(bc_tui_pick_database "$f")" || return 0
      if bc_tui_yesno "Datos" "¿Incluir también los datos?\n\nEs más lento pero comprueba mucho más.\nLa base de datos temporal se elimina al terminar."; then
        BC_OPT_WITH_DATA=1
      else
        BC_OPT_WITH_DATA=0
      fi
      BC_OPT_QUICK=0; BC_OPT_RESTORE_TEST="$db"
      bc_tui_exec "Prueba de restauración de $db" bc_verify_run "$f"
      BC_OPT_RESTORE_TEST=""; BC_OPT_WITH_DATA=0
      ;;
  esac
}

bc_tui_menu_restore() {
  local f; f="$(bc_tui_pick_backup)" || return 0
  local db; db="$(bc_tui_pick_database "$f")" || return 0

  local c
  c="$(bc_tui_menu "Restaurar $db" "¿Dónde quieres restaurarla?" \
    misma    "Sobre la misma base de datos '$db'" \
    otra     "En otra base de datos (con otro nombre)" \
    simular  "Simular: enseñar qué haría, sin tocar nada" \
  )" || return 0

  BC_OPT_INTO=""; BC_OPT_DRY=0
  case "$c" in
    misma) : ;;
    otra)
      local into; into="$(bc_tui_input "Destino" "Nombre de la base de datos destino:" "${db}_copia")" || return 0
      [[ -n "$into" ]] || return 0
      BC_OPT_INTO="$into"
      ;;
    simular) BC_OPT_DRY=1 ;;
  esac

  bc_tui_exec "Restauración de $db" bc_restore_run "$f" "$db"
  BC_OPT_INTO=""; BC_OPT_DRY=0
}

bc_tui_menu_migrate() {
  local c
  c="$(bc_tui_menu "Servidores remotos" \
    "SUBIR   = llevar backupctl y la config del repo al servidor.\nDESCARGAR = traer al repo lo que hay realmente en el servidor.\nMIGRAR  = copiar las bases de datos a OTRA máquina." \
    desplegar "SUBIR: instalar o actualizar backupctl en un servidor" \
    descargar "DESCARGAR: traer al repo el estado real de un servidor" \
    simular   "Simular una migración de bases de datos" \
    migrar    "MIGRAR las bases de datos a otro servidor" \
  )" || return 0

  local target
  target="$(bc_tui_input "Destino" "Servidor destino (usuario@servidor):" "${DEPLOY_USER}@${DEPLOY_HOST}")" || return 0
  [[ -n "$target" && "$target" != "@" ]] || { bc_tui_msg "Destino" "No se indicó un destino válido."; return 0; }

  case "$c" in
    desplegar) BC_OPT_DRY=0; bc_tui_exec "Subiendo a $target" bc_deploy_run "$target" ;;
    descargar) BC_OPT_DRY=0; bc_tui_exec "Descargando de $target" bc_pull_run "$target" ;;
    simular)   BC_OPT_TO="$target"; BC_OPT_DRY=1; bc_tui_exec "Simulación de migración" bc_migrate_run; BC_OPT_DRY=0 ;;
    migrar)
      if bc_tui_yesno "Respaldo fresco" "¿Generar un respaldo NUEVO antes de migrar?\n\nSí = se migran los datos de ahora mismo.\nNo = se usa el último respaldo existente."; then
        BC_OPT_FRESH=1
      else
        BC_OPT_FRESH=0
      fi
      BC_OPT_TO="$target"; BC_OPT_DRY=0
      bc_tui_exec "Migración hacia $target" bc_migrate_run
      BC_OPT_FRESH=0
      ;;
  esac
  BC_OPT_TO=""
}

bc_tui_menu_archive() {
  local c
  c="$(bc_tui_menu "Respaldos guardados" "" \
    listar    "Listar todos los respaldos" \
    inspec    "Inspeccionar uno (metadatos e inventario)" \
    retencion "Aplicar la retención ahora" \
    simretenc "Simular la retención (qué se borraría)" \
  )" || return 0

  case "$c" in
    listar)    bc_tui_exec "Respaldos" bc_archive_list ;;
    inspec)
      local f; f="$(bc_tui_pick_backup)" || return 0
      bc_tui_exec "Contenido de $(basename "$f")" bc_archive_inspect "$f"
      ;;
    retencion)
      bc_tui_yesno "Retención" "Se borrarán los respaldos de más de $BACKUP_RETENTION_DAYS días,\nconservando siempre los $BACKUP_KEEP_MIN más recientes.\n\n¿Continuar?" \
        && bc_tui_exec "Retención" bc_retention_apply 0
      ;;
    simretenc) bc_tui_exec "Simulación de retención" bc_retention_apply 1 ;;
  esac
}

bc_tui_menu_restic() {
  local c
  c="$(bc_tui_menu "Claves Restic (HestiaCP)" "" \
    listar  "Ver qué repositorios hay" \
    volcar  "Volcar las claves a un archivo (requiere root)" \
    simular "Simular el volcado" \
  )" || return 0
  case "$c" in
    listar)  bc_tui_exec "Repositorios Restic" bc_restic_list ;;
    volcar)  BC_OPT_DRY=0; bc_tui_exec "Volcado de claves Restic" bc_restic_run ;;
    simular) BC_OPT_DRY=1; bc_tui_exec "Simulación" bc_restic_run; BC_OPT_DRY=0 ;;
  esac
}

bc_tui_menu_cron() {
  local c
  c="$(bc_tui_menu "Programación" "" \
    ver       "Ver el crontab propuesto y el actual" \
    instalar  "Instalar la programación de este perfil" \
    quitar    "Quitar la programación de este perfil" \
    probar    "Enviar un aviso de prueba" \
  )" || return 0
  case "$c" in
    ver)      bc_tui_exec "Crontab" bc_cron_show ;;
    instalar) bc_tui_exec "Instalar en crontab" bc_cron_install ;;
    quitar)   bc_tui_exec "Quitar del crontab" bc_cron_remove ;;
    probar)   bc_tui_exec "Aviso de prueba" bc_notify_test ;;
  esac
}

bc_tui_menu_config() {
  local c
  c="$(bc_tui_menu "Configuración" "Perfil '$BC_PROFILE' — $BC_ENV_FILE" \
    ver      "Ver la configuración efectiva" \
    comprob  "Comprobar que es válida" \
    editar   "Editar env.sh" \
  )" || return 0
  case "$c" in
    ver)     bc_tui_exec "Configuración" bc_config_show 0 ;;
    comprob) bc_tui_exec "Comprobación" bc_config_check ;;
    editar)
      "${EDITOR:-nano}" "$BC_ENV_FILE"
      bc_config_load "$BC_ENV_FILE"
      bc_tui_msg "Configuración" "Recargada desde:\n$BC_ENV_FILE"
      ;;
  esac
}

bc_tui_menu_logs() {
  local c
  c="$(bc_tui_menu "Registros" "$LOG_DIR" \
    listar  "Listar los logs con su recuento de errores" \
    ultimo  "Ver el último log completo" \
    errores "Ver solo los errores y avisos del último" \
    seguir  "Seguir el último log en vivo" \
  )" || return 0
  case "$c" in
    listar)  bc_tui_exec "Logs" bc_logs_list ;;
    ultimo)  bc_tui_exec "Último log" bc_logs_show full ;;
    errores) bc_tui_exec "Errores" bc_logs_show errors ;;
    seguir)  bc_tui_exec "Seguimiento" bc_logs_follow ;;
  esac
}

bc_tui_switch_profile() {
  local args=() name path
  while IFS=$'\t' read -r name path; do args+=("$name" "$name  ($path)"); done < <(bc_config_list)
  (( ${#args[@]} == 0 )) && { bc_tui_msg "Perfiles" "No se encontró ningún perfil."; return 0; }
  local pick; pick="$(bc_tui_menu "Perfiles" "Elige el servidor con el que trabajar:" "${args[@]}")" || return 0
  bc_config_load "$pick"
  bc_tui_msg "Perfil" "Ahora trabajas con el perfil:\n\n  $BC_PROFILE\n  $BC_ENV_FILE"
}
