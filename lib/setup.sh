#!/usr/bin/env bash
# =============================================================================
# lib/setup.sh — asistente de alta de un servidor
# =============================================================================
# Pregunta lo que hace falta y escribe el env.sh. No hay que editar nada a mano.
#
# La parte importante es el usuario de MySQL. En lugar de exigir que lo crees tú
# por adelantado, el asistente te pide una credencial de ADMINISTRADOR de la
# base de datos, la usa una sola vez para crear el usuario de respaldo con sus
# permisos, y la descarta.
#
# QUÉ SE GUARDA Y QUÉ NO
#   Se guarda en env.sh   el usuario de respaldo y su contraseña (generada aquí)
#   NO se guarda nunca    la credencial de administrador que has tecleado
#
# La credencial de administrador viaja a un archivo temporal con permisos 600 en
# el servidor y se borra al terminar: nunca aparece en la línea de órdenes, así
# que no es visible en `ps` para el resto de usuarios de la máquina.
# =============================================================================

[[ -n "${BC_SETUP_LOADED:-}" ]] && return 0
BC_SETUP_LOADED=1

# -----------------------------------------------------------------------------
# Modo desatendido
# -----------------------------------------------------------------------------
# Los valores llegan por variables de entorno en lugar de por preguntas. Lo usa
# la interfaz web: así hay UNA sola implementación del alta y no dos que puedan
# divergir. También sirve para guionizarlo.
#
#   BC_SETUP_NAME NAME_HOST SSH_USER OWNER PATH DB_USER DB_PASS
#   BC_SETUP_ADMIN_USER ADMIN_PASS   (solo si CREATE_DB=si)
#   BC_SETUP_CREATE_DB=si|no   BC_SETUP_HEALTHCHECK   BC_SETUP_DEPLOY=si|no
# -----------------------------------------------------------------------------
bc_setup_auto() {
  local name="${BC_SETUP_NAME:-}"
  local host="${BC_SETUP_HOST:-}"
  local ssh_user="${BC_SETUP_SSH_USER:-admin}"
  local owner="${BC_SETUP_OWNER:-$ssh_user}"
  local path="${BC_SETUP_PATH:-/home/$owner/scripts}"
  local hc="${BC_SETUP_HEALTHCHECK:-}"
  local db_user="${BC_SETUP_DB_USER:-}"
  local db_pass="${BC_SETUP_DB_PASS:-}"

  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || bc_die "nombre de perfil no válido: '$name'"
  [[ -n "$host" ]] || bc_die "hace falta un servidor (BC_SETUP_HOST)."

  local dir="$BC_ROOT/$name"
  local target="$ssh_user@$host"

  bc_section "Alta de '$name' en $target"

  bc_log "Probando la conexión..."
  bc_ssh_init "$target" || bc_die "no se pudo conectar a $target."
  trap 'bc_ssh_close' RETURN
  bc_ok "conectado a $(bc_ssh 'hostname -f 2>/dev/null || hostname')"

  if [[ "${BC_SETUP_CREATE_DB:-no}" == "si" ]]; then
    local admin_user="${BC_SETUP_ADMIN_USER:-root}"
    local admin_pass="${BC_SETUP_ADMIN_PASS:-}"
    [[ -n "$db_user" ]] || db_user="backupctl"
    db_pass="$(bc_gen_password 28)"
    bc_log "Se creará el usuario '$db_user' con una contraseña de 28 caracteres."
    BC_ASSUME_YES=1 bc_setup_create_db_user "$admin_user" "$admin_pass" "$db_user" "$db_pass" \
      || bc_die "no se pudo crear el usuario de MySQL."
    admin_pass=""; admin_user=""
  else
    [[ -n "$db_user" ]] || bc_die "hace falta MYSQL_USER (BC_SETUP_DB_USER)."
    bc_setup_check_db "$db_user" "$db_pass" \
      || bc_warn "esas credenciales no funcionaron; se guardan igual para que las corrijas."
  fi

  mkdir -p "$dir"
  [[ -f "$dir/env.sh" ]] && cp "$dir/env.sh" "$dir/env.sh.anterior"
  bc_setup_escribir_env "$dir/env.sh" "$name" "$owner" "$path" \
                        "$db_user" "$db_pass" "$hc" "$host" "$ssh_user"
  bash -n "$dir/env.sh" || bc_die "el env.sh generado tiene errores de sintaxis."
  bc_ok "Escrito $dir/env.sh"

  if [[ "${BC_SETUP_DEPLOY:-no}" == "si" ]]; then
    bc_ssh_close
    bc_config_load "$dir/env.sh"
    BC_ASSUME_YES=1 bc_deploy_run "$target"
  fi

  bc_ok "Perfil '$name' listo."
}

# Escritura del env.sh, común a los dos modos
bc_setup_escribir_env() {
  local archivo="$1" name="$2" owner="$3" path="$4"
  local db_user="$5" db_pass="$6" hc="$7" host="$8" ssh_user="$9"
  cat > "$archivo" <<CONF
#!/usr/bin/env bash
# =============================================================================
# env.sh — $name
# =============================================================================
# Generado por: backupctl setup, el $(date '+%Y-%m-%d %H:%M')
# Referencia completa de las variables: config/env.sh.example
# =============================================================================

export USER_NAME="$owner"
export SCRIPTS_DIR="$path"

export MYSQL_USER="$db_user"
export MYSQL_PASS="$db_pass"
export MYSQL_HOST=""
export MYSQL_PORT=""
export MYSQL_SOCKET=""
export MYSQL_CHARSET="utf8mb4"

export EXCLUDE_DBS="('information_schema','performance_schema','mysql','sys','phpmyadmin')"

export BACKUP_RETENTION_DAYS="14"
export LOG_RETENTION_DAYS="30"
export RESTIC_RETENTION_DAYS="90"
export BACKUP_KEEP_MIN="3"
export MIN_FREE_MB="2048"

export NOTIFY_EMAIL=""
export NOTIFY_COMMAND=""
export HEALTHCHECK_URL="$hc"

export HESTIA_DIR="/usr/local/hestia"

export DEPLOY_HOST="$host"
export DEPLOY_USER="$ssh_user"
export DEPLOY_PATH="$path"
CONF
}

bc_setup_run() {
  local name="${1:-}"

  # La web y los guiones entran por aquí
  [[ -n "${BC_SETUP_NAME:-}" ]] && { bc_setup_auto; return $?; }

  bc_can_prompt || bc_die "el asistente necesita un terminal interactivo."

  bc_section "Alta de un servidor"
  bc_log "Se te preguntará lo necesario y se escribirá el env.sh."
  bc_log "Nada se aplica sin confirmarlo antes."
  echo

  # --- 1. Nombre del perfil --------------------------------------------------
  while [[ -z "$name" ]]; do
    name="$(bc_ask "Nombre para este servidor (será el nombre de la carpeta)" "MiVPS")"
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      bc_warn "usa solo letras, números, punto, guion y guion bajo."
      name=""
    fi
  done

  local dir="$BC_ROOT/$name"
  if [[ -f "$dir/env.sh" ]]; then
    bc_warn "el perfil '$name' ya existe: $dir/env.sh"
    bc_confirm "¿Reconfigurarlo? Se guardará una copia como env.sh.anterior" n \
      || { bc_log "Cancelado."; return 0; }
  fi

  # --- 2. Acceso al servidor -------------------------------------------------
  echo
  bc_step "Acceso al servidor"
  local host ssh_user
  host="$(bc_ask "Servidor (nombre o IP)" "${DEPLOY_HOST:-}")"
  [[ -n "$host" ]] || bc_die "hace falta un servidor."
  ssh_user="$(bc_ask "Usuario para conectarse por SSH (necesita shell)" "admin")"

  local target="$ssh_user@$host"
  bc_log "Probando la conexión (si pide contraseña, se pedirá una sola vez)..."
  bc_ssh_init "$target" || bc_die "no se pudo conectar a $target."
  trap 'bc_ssh_close' RETURN
  bc_ok "conectado a $(bc_ssh 'hostname -f 2>/dev/null || hostname')"

  # --- 3. Usuario propietario ------------------------------------------------
  echo
  bc_step "Instalación"
  bc_log "El usuario propietario NO necesita acceso por SSH: puede tener nologin."
  local owner path
  owner="$(bc_ask "Usuario propietario de la instalación" "$ssh_user")"
  path="$(bc_ask "Ruta en el servidor" "/home/$owner/scripts")"

  # --- 4. Base de datos ------------------------------------------------------
  echo
  bc_step "Acceso a MySQL"
  local db_user db_pass
  local existe
  existe="$(bc_ask "¿Ya tienes un usuario de MySQL para los respaldos? (s/n)" "n")"

  if [[ "$existe" =~ ^[sSyY] ]]; then
    db_user="$(bc_ask "Usuario de MySQL" "admin_general")"
    db_pass="$(bc_ask_secret "Contraseña de '$db_user'")"
    bc_setup_check_db "$db_user" "$db_pass" || {
      bc_warn "esas credenciales no funcionaron en el servidor."
      bc_confirm "¿Guardarlas de todas formas y arreglarlo luego?" n || bc_die "cancelado."
    }
  else
    bc_log "Se creará uno. Para ello hace falta una credencial de ADMINISTRADOR"
    bc_log "de MySQL (root o equivalente). No se guardará en ningún sitio:"
    bc_log "se usa una vez para crear el usuario de respaldo y se descarta."
    echo
    local admin_user admin_pass
    admin_user="$(bc_ask "Usuario administrador de MySQL" "root")"
    admin_pass="$(bc_ask_secret "Contraseña de '$admin_user' (vacío si entra por socket)")"

    db_user="$(bc_ask "Nombre del usuario de respaldo a crear" "backupctl")"
    db_pass="$(bc_gen_password 28)"
    bc_log "Contraseña generada para '$db_user': 28 caracteres aleatorios."

    bc_setup_create_db_user "$admin_user" "$admin_pass" "$db_user" "$db_pass" \
      || bc_die "no se pudo crear el usuario de MySQL."
    # La credencial de administrador deja de existir aquí
    admin_pass=""; admin_user=""
  fi

  # --- 5. Avisos -------------------------------------------------------------
  echo
  bc_step "Avisos ante fallo"
  bc_log "Sin al menos uno, un respaldo fallido bajo cron no avisaría a nadie."
  local hc
  hc="$(bc_ask "URL de healthcheck (Enter para dejarlo para luego)" "")"

  # --- 6. Escribir env.sh ----------------------------------------------------
  echo
  bc_step "Resumen"
  {
    printf 'Perfil\t%s\n'           "$name"
    printf 'Archivo\t%s\n'          "$dir/env.sh"
    printf 'Servidor\t%s\n'         "$target"
    printf 'Ruta\t%s\n'             "$path"
    printf 'Propietario\t%s\n'      "$owner"
    printf 'Usuario MySQL\t%s\n'    "$db_user"
    printf 'Contraseña\t%s\n'       "(${#db_pass} caracteres)"
    printf 'Healthcheck\t%s\n'      "${hc:-(sin configurar)}"
  } | bc_table
  echo

  bc_confirm "¿Escribir la configuración?" y || { bc_log "Cancelado."; return 0; }

  mkdir -p "$dir"
  [[ -f "$dir/env.sh" ]] && cp "$dir/env.sh" "$dir/env.sh.anterior"

  bc_setup_escribir_env "$dir/env.sh" "$name" "$owner" "$path" \
                        "$db_user" "$db_pass" "$hc" "$host" "$ssh_user"


  bash -n "$dir/env.sh" || bc_die "el env.sh generado tiene errores de sintaxis."
  bc_ok "Escrito $dir/env.sh"

  # --- 7. Desplegar ----------------------------------------------------------
  echo
  if bc_confirm "¿Desplegar ahora backupctl en $target?" y; then
    bc_ssh_close                 # deploy abre la suya
    bc_config_load "$dir/env.sh"
    bc_deploy_run "$target"
  else
    bc_log "Cuando quieras:"
    bc_log "    backupctl -p $name deploy $target"
  fi

  echo
  bc_ok "Perfil '$name' listo."
  bc_log "Siguientes pasos:"
  bc_log "    backupctl -p $name remote doctor"
  bc_log "    backupctl -p $name remote backup"
  bc_log "    backupctl -p $name remote cron --install"
}

# -----------------------------------------------------------------------------
# Ejecuta SQL en el servidor con una credencial que NO debe aparecer en `ps`.
# -----------------------------------------------------------------------------
# La credencial viaja por stdin a un archivo temporal 600 en el destino y se
# borra al terminar. Pasarla como -pCONTRASEÑA la haría visible en la tabla de
# procesos para cualquier otro usuario de la máquina.
# -----------------------------------------------------------------------------
bc_setup_mysql_remote() {
  local user="$1" pass="$2" sql="$3"
  local cnf rc=0
  cnf="$(bc_ssh 'mktemp')" || return 1

  {
    echo "[client]"
    echo "user=$user"
    [[ -n "$pass" ]] && echo "password=$pass"
  } | bc_ssh "cat > '$cnf' && chmod 600 '$cnf'" || { bc_ssh "rm -f '$cnf'"; return 1; }

  bc_ssh "mysql --defaults-extra-file='$cnf'" <<<"$sql" || rc=$?
  bc_ssh "rm -f '$cnf'"
  return $rc
}

bc_setup_check_db() {
  local user="$1" pass="$2"
  bc_log "Comprobando el acceso a MySQL en el servidor..."
  if bc_setup_mysql_remote "$user" "$pass" "SELECT 1;" >/dev/null 2>&1; then
    bc_ok "las credenciales funcionan."
    return 0
  fi
  return 1
}

bc_setup_create_db_user() {
  local admin_user="$1" admin_pass="$2" db_user="$3" db_pass="$4"

  # Se enseña exactamente lo que se va a ejecutar, con la contraseña oculta
  local sql_shown="CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '********';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS, CREATE, DROP
  ON *.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;"

  echo
  bc_log "Se ejecutará en el servidor:"
  sed 's/^/        /' <<<"$sql_shown"
  bc_log "CREATE y DROP son para poder probar la restauración con una base"
  bc_log "de datos desechable (verify --restore-test)."
  echo
  bc_confirm "¿Crear el usuario '$db_user'?" y || return 1

  local sql="CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
ALTER USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS, CREATE, DROP ON *.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;"

  if ! bc_setup_mysql_remote "$admin_user" "$admin_pass" "$sql"; then
    bc_err "falló la creación. Comprueba la credencial de administrador."
    return 1
  fi
  bc_ok "usuario '$db_user' creado con sus permisos."

  bc_setup_check_db "$db_user" "$db_pass" || {
    bc_err "el usuario se creó pero no se puede entrar con él."
    return 1
  }
  return 0
}
