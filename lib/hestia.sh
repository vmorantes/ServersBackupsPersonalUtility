#!/usr/bin/env bash
# =============================================================================
# lib/hestia.sh — configurar y blindar los respaldos de HestiaCP
# =============================================================================
# Deja montado el respaldo incremental con Restic sin tocar nada a mano: el
# remoto de rclone (S3/Mega S4, disco o NAS), el host de respaldo en HestiaCP,
# el cron, y el rescate de las claves sin las cuales el repositorio es
# ilegible.
#
# DÓNDE SE EJECUTA
#   Todas estas operaciones ocurren EN EL SERVIDOR. Si el perfil tiene
#   DEPLOY_HOST, se hacen por SSH; si backupctl ya vive en el servidor, se hacen
#   ahí mismo. Una sola implementación para los dos casos.
#
# LAS CREDENCIALES NUNCA VAN EN LA LÍNEA DE ÓRDENES
#   Las claves de S3 viajan por la entrada estándar hasta el archivo de destino.
#   Pasarlas como argumento las haría visibles en `ps` para cualquier otro
#   usuario del servidor.
# =============================================================================

[[ -n "${BC_HESTIA_LOADED:-}" ]] && return 0
BC_HESTIA_LOADED=1

BC_HESTIA_REMOTO=0          # ¿hay que ir por SSH?
BC_HESTIA_RCLONE_CONF="${BC_RCLONE_CONF:-/root/.config/rclone/rclone.conf}"

# -----------------------------------------------------------------------------
# Decidir dónde actuar y abrir la conexión si hace falta
# -----------------------------------------------------------------------------
bc_hestia_conectar() {
  if [[ -d "$HESTIA_DIR" ]]; then
    BC_HESTIA_REMOTO=0
    bc_debug "HestiaCP local en $HESTIA_DIR"
    return 0
  fi
  if [[ -n "$DEPLOY_HOST" ]]; then
    BC_HESTIA_REMOTO=1
    local target="$DEPLOY_USER@$DEPLOY_HOST"
    bc_log "HestiaCP no está aquí; se trabajará sobre $target."
    bc_ssh_init "$target" || bc_die "no se pudo conectar a $target."
    bc_ssh "test -d '$HESTIA_DIR'" 2>/dev/null \
      || bc_die "en $target tampoco existe $HESTIA_DIR. ¿Es un servidor HestiaCP?"
    return 0
  fi
  bc_die "no hay HestiaCP aquí ni DEPLOY_HOST configurado en $BC_ENV_FILE."
}

bc_hestia_cerrar() { (( BC_HESTIA_REMOTO )) && bc_ssh_close; return 0; }

# LECTURA: se intenta primero sin elevar. Muchos de estos archivos son
# legibles por el usuario, y pedir sudo para leerlos sería tan molesto como
# innecesario. Solo si falla se escala.
bc_hestia_read() {
  if (( BC_HESTIA_REMOTO )); then
    bc_ssh "$*" 2>/dev/null && return 0
    bc_ssh_sudo "$*" 2>/dev/null
  else
    bash -c "$*" 2>/dev/null && return 0
    [[ "$(id -u)" -eq 0 ]] && return 1
    sudo -n bash -c "$*" 2>/dev/null
  fi
}

# ESCRITURA: siempre elevado. Nunca se intenta sin sudo, porque un intento a
# medias podría dejar un archivo escrito a medias.
bc_hestia_root() {
  if (( BC_HESTIA_REMOTO )); then
    bc_ssh_sudo "$*"
  elif [[ "$(id -u)" -eq 0 ]]; then
    bash -c "$*"
  elif sudo -n true 2>/dev/null; then
    sudo -n bash -c "$*"
  elif bc_can_prompt; then
    sudo bash -c "$*"
  else
    return 1
  fi
}

# Igual, pero enviando algo por la entrada estándar. Es la vía por la que
# viajan las credenciales.
bc_hestia_root_stdin() {
  if (( BC_HESTIA_REMOTO )); then
    bc_ssh_sudo "$*"
  elif [[ "$(id -u)" -eq 0 ]]; then
    bash -c "$*"
  else
    sudo -n bash -c "$*" 2>/dev/null || sudo bash -c "$*"
  fi
}

bc_hestia_v() { bc_hestia_root "$HESTIA_DIR/bin/$*"; }

# =============================================================================
# Estado
# =============================================================================
bc_hestia_status() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Respaldos de HestiaCP — perfil '$BC_PROFILE'"

  # --- Host de respaldo Restic ----------------------------------------------
  local conf
  conf="$(bc_hestia_read "cat '$HESTIA_DIR/data/users/conf/restic.conf'" || true)"
  if [[ -z "$conf" ]]; then
    bc_warn "Restic NO está configurado en este servidor."
    bc_log  "Móntalo con:  backupctl hestia setup"
  else
    local repo snaps d w m y
    repo="$(sed -n "s/^REPO='\(.*\)'$/\1/p"          <<<"$conf")"
    snaps="$(sed -n "s/^SNAPSHOTS='\(.*\)'$/\1/p"    <<<"$conf")"
    d="$(sed -n "s/^KEEP_DAILY='\(.*\)'$/\1/p"       <<<"$conf")"
    w="$(sed -n "s/^KEEP_WEEKLY='\(.*\)'$/\1/p"      <<<"$conf")"
    m="$(sed -n "s/^KEEP_MONTHLY='\(.*\)'$/\1/p"     <<<"$conf")"
    y="$(sed -n "s/^KEEP_YEARLY='\(.*\)'$/\1/p"      <<<"$conf")"
    bc_ok "Restic configurado."
    {
      printf 'Repositorio\t%s\n' "$repo"
      printf 'Instantáneas totales\t%s\n' "$snaps"
      printf 'Diarias\t%s\n'   "$d"
      printf 'Semanales\t%s\n' "$w"
      printf 'Mensuales\t%s\n' "$m"
      printf 'Anuales\t%s\n'   "$([[ "$y" == "-1" ]] && echo "ilimitadas (-1)" || echo "$y")"
    } | bc_table | sed 's/^/        /'
  fi

  # --- Remoto de rclone ------------------------------------------------------
  local remotos
  remotos="$(bc_hestia_read "grep -oP '^\[\K[^]]+' '$BC_HESTIA_RCLONE_CONF'" || true)"
  if [[ -n "$remotos" ]]; then
    bc_ok "Remotos de rclone: $(tr '\n' ' ' <<<"$remotos")"
  else
    bc_warn "no hay remotos de rclone configurados (o no se pudo leer $BC_HESTIA_RCLONE_CONF)."
  fi

  # --- Cron ------------------------------------------------------------------
  local cron
  cron="$(bc_hestia_read "crontab -l" || true)"
  if grep -q 'v-backup-users-restic' <<<"$cron"; then
    bc_ok "Cron de Restic activo:"
    grep 'v-backup-users-restic' <<<"$cron" | sed 's/^/        /'
  else
    bc_warn "el cron de Restic NO está activo: nunca se respaldará solo."
    bc_log  "Actívalo con:  backupctl hestia cron"
  fi

  # --- Usuarios y último respaldo -------------------------------------------
  local usuarios
  usuarios="$( { bc_hestia_v "v-list-users plain" 2>/dev/null || true; } | awk '{print $1}')"
  if [[ -n "$usuarios" ]]; then
    bc_log "Usuarios de HestiaCP: $(tr '\n' ' ' <<<"$usuarios")"
  fi

  # --- Claves rescatadas -----------------------------------------------------
  local restic_local rclone_local
  restic_local="$( { find "$HESTIA_OUTPUT_DIR" -maxdepth 1 -name 'Restic_Configs_*.txt' 2>/dev/null || true; } | wc -l)"
  rclone_local="$( { find "$HESTIA_OUTPUT_DIR" -maxdepth 1 -name 'rclone_*.conf' 2>/dev/null || true; } | wc -l)"
  if (( restic_local > 0 )); then bc_ok "Claves Restic rescatadas: $restic_local archivo(s)."
  else bc_err "las claves Restic NO están rescatadas. Sin ellas el repositorio es ILEGIBLE."; fi
  if (( rclone_local > 0 )); then bc_ok "rclone.conf rescatado: $rclone_local archivo(s)."
  else bc_err "el rclone.conf NO está rescatado. Sin él no se puede LLEGAR al repositorio."; fi
  (( restic_local == 0 || rclone_local == 0 )) && bc_log "Rescátalas con:  sudo backupctl hestia keys"
  return 0
}

# =============================================================================
# Configurar el remoto de rclone
# =============================================================================
# Se escribe la sección directamente en rclone.conf en lugar de lanzar
# `rclone config`, que es interactivo y no se puede guionizar. El resultado es
# idéntico y además es reproducible.
bc_hestia_rclone() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local nombre="${BC_OPT_RC_NAME:-}" tipo="${BC_OPT_RC_TYPE:-}"
  local key="${BC_OPT_RC_KEY:-}" secret="${BC_OPT_RC_SECRET:-}"
  local endpoint="${BC_OPT_RC_ENDPOINT:-}" region="${BC_OPT_RC_REGION:-}"

  # Con BC_OPT_RC_NAME ya puesto (lo hace la interfaz web) no se pregunta nada
  if [[ -z "$nombre" ]] && bc_can_prompt; then
    bc_section "Nuevo remoto de rclone"
    nombre="$(bc_ask "Nombre del remoto" "almacenamiento")"
    tipo="$(bc_ask "Tipo: s3 (Mega S4, compatible S3) o local" "s3")"
    if [[ "$tipo" == "s3" ]]; then
      key="$(bc_ask "Access key ID")"
      secret="$(bc_ask_secret "Secret access key")"
      endpoint="$(bc_ask "Endpoint S3 (obligatorio: sin él rclone hablaría con Amazon)")"
      region="$(bc_ask "Región (vacío si no aplica)" "")"
    fi
  fi

  [[ -n "$nombre" ]] || bc_die "hace falta el nombre del remoto."
  [[ "$nombre" =~ ^[A-Za-z0-9._-]+$ ]] || bc_die "nombre de remoto no válido."
  tipo="${tipo:-s3}"

  local seccion
  if [[ "$tipo" == "local" ]]; then
    seccion="[$nombre]
type = local
"
  else
    [[ -n "$key" && -n "$secret" ]] || bc_die "hacen falta access key y secret."
    [[ -n "$endpoint" ]] || bc_die "hace falta el endpoint: Mega S4 no es Amazon, y sin él rclone iría a AWS."
    seccion="[$nombre]
type = s3
provider = Other
env_auth = false
access_key_id = $key
secret_access_key = $secret
endpoint = $endpoint
$( [[ -n "$region" ]] && echo "region = $region" )acl = private
"
  fi

  bc_log "Se configurará el remoto '$nombre' (tipo $tipo) en $BC_HESTIA_RCLONE_CONF"
  [[ "$tipo" == "s3" ]] && bc_log "Endpoint: $endpoint"
  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha escrito nada."
    return 0
  fi
  bc_confirm "¿Escribirlo en el servidor?" y || { bc_log "Cancelado."; return 0; }

  # Copia de seguridad y sustitución de la sección si ya existía. El archivo se
  # reconstruye con awk en el servidor; las credenciales llegan por stdin.
  printf '%s' "$seccion" | bc_hestia_root_stdin "
    umask 077
    mkdir -p \"\$(dirname '$BC_HESTIA_RCLONE_CONF')\"
    touch '$BC_HESTIA_RCLONE_CONF'
    cp -a '$BC_HESTIA_RCLONE_CONF' '$BC_HESTIA_RCLONE_CONF.anterior' 2>/dev/null || true
    nueva=\$(cat)
    awk -v n='[$nombre]' '
      \$0 == n { saltar=1; next }
      /^\[/    { saltar=0 }
      !saltar  { print }
    ' '$BC_HESTIA_RCLONE_CONF.anterior' > '$BC_HESTIA_RCLONE_CONF.tmp' 2>/dev/null || true
    printf '%s\n' \"\$nueva\" >> '$BC_HESTIA_RCLONE_CONF.tmp'
    mv '$BC_HESTIA_RCLONE_CONF.tmp' '$BC_HESTIA_RCLONE_CONF'
    chmod 600 '$BC_HESTIA_RCLONE_CONF'
  " || bc_die "no se pudo escribir la configuración de rclone."

  bc_ok "Remoto '$nombre' escrito. La versión anterior queda como rclone.conf.anterior"

  bc_log "Comprobando que el remoto responde..."
  if bc_hestia_root "rclone lsd '$nombre:' 2>&1 | head -5"; then
    bc_ok "El remoto responde."
  else
    bc_warn "no se pudo listar el remoto. Revisa las credenciales y el endpoint."
  fi
}

# =============================================================================
# Registrar el host de respaldo en HestiaCP
# =============================================================================
bc_hestia_restic() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local repo="${BC_OPT_REPO:-}"
  local snaps="${BC_OPT_SNAPSHOTS:-30}" d="${BC_OPT_DAILY:-8}"
  local w="${BC_OPT_WEEKLY:-5}" m="${BC_OPT_MONTHLY:-3}" y="${BC_OPT_YEARLY:--1}"

  if [[ -z "$repo" ]] && bc_can_prompt; then
    bc_section "Host de respaldo Restic"
    local rem ruta
    rem="$(bc_ask "Remoto de rclone" "almacenamiento")"
    ruta="$(bc_ask "Ruta dentro del remoto" "hestiacp/")"
    repo="rclone:$rem:$ruta"
    bc_log "Política de retención (por defecto: 30 instantáneas, 8 diarias, 5 semanales, 3 mensuales, anuales ilimitadas)"
    snaps="$(bc_ask "Instantáneas totales" "30")"
    d="$(bc_ask "Diarias a conservar" "8")"
    w="$(bc_ask "Semanales" "5")"
    m="$(bc_ask "Mensuales" "3")"
    y="$(bc_ask "Anuales (-1 = ilimitadas)" "-1")"
  fi
  [[ -n "$repo" ]] || bc_die "hace falta el repositorio."

  bc_section "Registrar el host de respaldo"
  bc_log "Repositorio: $repo"
  {
    printf 'Instantáneas totales\t%s\n' "$snaps"
    printf 'Diarias\t%s\n' "$d"; printf 'Semanales\t%s\n' "$w"
    printf 'Mensuales\t%s\n' "$m"
    printf 'Anuales\t%s\n' "$([[ "$y" == "-1" ]] && echo 'ilimitadas' || echo "$y")"
  } | bc_table | sed 's/^/        /'
  bc_warn "El PRIMER número es el total de instantáneas, no los días. Es el error"
  bc_warn "más común al configurar esto a mano."

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha registrado nada."
    return 0
  fi
  bc_confirm "¿Registrarlo en HestiaCP?" y || { bc_log "Cancelado."; return 0; }

  bc_hestia_v "v-add-backup-host-restic '$repo' '$snaps' '$d' '$w' '$m' '$y'" \
    || bc_die "v-add-backup-host-restic falló. Revisa el repositorio y el remoto."
  bc_ok "Host de respaldo registrado."

  # HestiaCP no inicializa el repositorio: la primera vez hay que hacerlo
  bc_log "Comprobando que el repositorio existe..."
  if ! bc_hestia_root "restic -r '$repo' snapshots >/dev/null 2>&1"; then
    bc_warn "el repositorio no está inicializado todavía."
    if bc_confirm "¿Inicializarlo ahora (restic init)?" y; then
      bc_hestia_root "restic -r '$repo' init" \
        && bc_ok "repositorio inicializado." \
        || bc_warn "no se pudo inicializar. Hazlo a mano: restic init -r '$repo'"
    fi
  else
    bc_ok "El repositorio ya existe."
  fi
}

# =============================================================================
# Cron de Restic
# =============================================================================
bc_hestia_cron() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local hora="${BC_OPT_HOUR:-5}" minuto="${BC_OPT_MINUTE:-30}"
  local admin="${BC_OPT_HESTIA_USER:-admin}"

  bc_section "Cron de respaldos Restic"
  bc_warn "HestiaCP NO activa este cron al añadir el host de respaldo. Sin él,"
  bc_warn "Restic queda configurado pero no se ejecuta nunca."

  local actual
  actual="$(bc_hestia_v "v-list-cron-jobs $admin plain" 2>/dev/null || true)"
  if grep -q 'v-backup-users-restic' <<<"$actual"; then
    bc_ok "ya existe un cron de v-backup-users-restic:"
    grep 'v-backup-users-restic' <<<"$actual" | sed 's/^/        /'
    return 0
  fi

  bc_log "Se registrará:  $minuto $hora * * *  v-backup-users-restic"
  bc_log "A una hora distinta de los respaldos tradicionales, para no solaparlos."
  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha registrado nada."
    return 0
  fi
  bc_confirm "¿Registrarlo para el usuario '$admin'?" y || { bc_log "Cancelado."; return 0; }

  bc_hestia_v "v-add-cron-job $admin '$minuto' '$hora' '*' '*' '*' 'v-backup-users-restic'" \
    || bc_die "no se pudo registrar el cron."
  bc_ok "Cron registrado. Aparecerá en el panel, en Cron."
}

# =============================================================================
# Verificación del repositorio
# =============================================================================
bc_hestia_verify() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  local repo
  repo="$(bc_hestia_read "sed -n \"s/^REPO='\(.*\)'\$/\1/p\" '$HESTIA_DIR/data/users/conf/restic.conf'" || true)"
  [[ -n "$repo" ]] || bc_die "Restic no está configurado. Móntalo con: backupctl hestia setup"

  bc_section "Verificación del repositorio Restic"
  bc_log "Repositorio: $repo"

  bc_step "Instantáneas"
  bc_hestia_root "restic -r '$repo' snapshots 2>&1 | tail -20" | sed 's/^/        /' \
    || bc_warn "no se pudieron listar."

  bc_step "Estado del repositorio"
  if bc_hestia_root "restic -r '$repo' check 2>&1 | tail -10" | sed 's/^/        /'; then
    bc_ok "repositorio íntegro."
  else
    bc_err "el repositorio NO pasa la comprobación."
  fi

  bc_step "Espacio (tras deduplicar)"
  bc_hestia_root "restic -r '$repo' stats 2>&1 | tail -8" | sed 's/^/        /' || true
}

# =============================================================================
# Rescate de claves — lo que hace que el respaldo sea recuperable
# =============================================================================
bc_hestia_keys() {
  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Rescate de claves"
  bc_warn "Sin estos dos archivos, tus respaldos son irrecuperables aunque estén"
  bc_warn "intactos: uno descifra el repositorio y el otro permite llegar a él."

  mkdir -p "$HESTIA_OUTPUT_DIR"
  local fecha; fecha="$(date +%Y%m%d)"
  local n_restic=0

  # --- restic.conf de cada usuario ------------------------------------------
  local salida="$HESTIA_OUTPUT_DIR/Restic_Configs_${fecha}.txt"
  local confs
  confs="$(bc_hestia_read "find '$HESTIA_DIR' -type f -name restic.conf" || true)"
  if [[ -n "$confs" ]]; then
    n_restic="$(grep -c . <<<"$confs")"
    {
      printf '# Claves de repositorio Restic de HestiaCP\n'
      printf '# Servidor: %s\n' "$( (( BC_HESTIA_REMOTO )) && echo "$DEPLOY_HOST" || hostname -f 2>/dev/null || hostname )"
      printf '# Generado: %s por backupctl %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$BC_VERSION"
      while IFS= read -r c; do
        [[ -z "$c" ]] && continue
        printf '# %s:\n' "$(basename "$(dirname "$c")")"
        bc_hestia_read "cat '$c'"
        printf '\n=====================\n\n'
      done <<<"$confs"
    } > "$salida"
    bc_ok "Claves Restic: $salida"
  else
    bc_err "no se encontró ningún restic.conf."
  fi

  # --- rclone.conf ----------------------------------------------------------
  # Este es el que casi nadie guarda: Restic respalda las cuentas de usuario,
  # no la configuración de root. Sin él no se puede LLEGAR al repositorio,
  # aunque se tengan las claves para descifrarlo.
  local rc_salida="$HESTIA_OUTPUT_DIR/rclone_${fecha}.conf"
  if bc_hestia_read "cat '$BC_HESTIA_RCLONE_CONF'" > "$rc_salida" && [[ -s "$rc_salida" ]]; then
    bc_ok "Configuración de rclone: $rc_salida"
  else
    rm -f "$rc_salida"
    bc_warn "no se pudo leer $BC_HESTIA_RCLONE_CONF (¿hacen falta permisos de root?)."
  fi

  echo
  bc_err "GUARDA ESTOS ARCHIVOS FUERA DEL SERVIDOR."
  bc_log "En un gestor de contraseñas o en otra máquina. Si solo están aquí, se"
  bc_log "pierden con el servidor, y con ellos la posibilidad de recuperar nada."

  bc_prune "$HESTIA_OUTPUT_DIR" 'Restic_Configs_*.txt' "$RESTIC_RETENTION_DAYS" 2 "claves Restic" 0
  bc_prune "$HESTIA_OUTPUT_DIR" 'rclone_*.conf'        "$RESTIC_RETENTION_DAYS" 2 "config rclone"  0
}

# =============================================================================
# ¿Dónde están mis claves?
# =============================================================================
# La pregunta que más importa y peor respondida suele estar. Se contesta con
# rutas concretas, no con explicaciones.
bc_hestia_donde() {
  bc_section "Dónde están tus claves"

  bc_log "backupctl NO inventa credenciales: guarda las que rescata del servidor."
  echo

  bc_step "1 · En el servidor (el original)"
  bc_log "        $HESTIA_DIR/data/users/*/restic.conf   descifra el repositorio"
  bc_log "        $BC_HESTIA_RCLONE_CONF   permite llegar a él"
  echo

  bc_step "2 · Rescatadas en este repositorio"
  local hay=0 f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    hay=1
    bc_ok "        $f   ($(bc_age_days "$f") días)"
  done < <( { find "$HESTIA_OUTPUT_DIR" -maxdepth 1 \( -name 'Restic_Configs_*.txt' -o -name 'rclone_*.conf' \)               -printf '%T@ %p
' 2>/dev/null || true; } | sort -rn | cut -d' ' -f2- )
  if (( ! hay )); then
    bc_err "        NINGUNA. Rescátalas:  backupctl -p $BC_PROFILE hestia keys"
  fi
  echo

  bc_step "3 · Fuera de aquí"
  bc_warn "        Este repositorio vive en tu equipo. Si lo pierdes, pierdes las"
  bc_warn "        claves con él. Copia esos archivos a un gestor de contraseñas"
  bc_warn "        o a otra máquina."
  echo

  bc_step "Al desplegar en un servidor NUEVO"
  bc_log "        Si va a usar el MISMO destino S3, no hay que teclear nada:"
  bc_log "            backupctl -p <perfil> hestia rclone --desde-repo"
  bc_log "        instala allí el rclone.conf ya rescatado."
  bc_log ""
  bc_log "        Si va a un destino NUEVO, las claves salen del panel de tu"
  bc_log "        proveedor (Mega S4 → sección S4) y se introducen una vez con:"
  bc_log "            backupctl -p <perfil> hestia rclone"
}

# =============================================================================
# Reinstalar en un servidor el rclone.conf ya rescatado
# =============================================================================
# Cierra el ciclo: rescatar → repositorio → volver a poner en otra máquina.
# Sin esto, montar un servidor nuevo obligaría a ir a buscar las credenciales al
# panel del proveedor aunque ya las tuvieras guardadas.
bc_hestia_rclone_desde_repo() {
  local origen
  origen="$( { find "$HESTIA_OUTPUT_DIR" -maxdepth 1 -name 'rclone_*.conf' -printf '%T@ %p
' 2>/dev/null || true; }              | sort -rn | head -1 | cut -d' ' -f2- )"
  [[ -n "$origen" ]] || bc_die "no hay ningún rclone.conf rescatado en $HESTIA_OUTPUT_DIR. Rescátalo antes desde un servidor que ya lo tenga: backupctl hestia keys"

  bc_hestia_conectar
  trap 'bc_hestia_cerrar' RETURN

  bc_section "Reinstalar la configuración de rclone guardada"
  bc_log "Origen: $origen  ($(bc_age_days "$origen") días)"
  bc_log "Remotos que contiene:"
  grep -oP '^\[\K[^]]+' "$origen" | sed 's/^/        /'
  bc_warn "Este archivo lleva tus claves de S3. Se instalará en el servidor con"
  bc_warn "permisos 600, guardando copia de lo que hubiera antes."

  if [[ "${BC_OPT_DRY:-0}" == "1" ]]; then
    bc_ok "Simulación (--dry-run): no se ha escrito nada."
    return 0
  fi
  bc_confirm "¿Instalarlo en $BC_HESTIA_RCLONE_CONF del servidor?" n     || { bc_log "Cancelado."; return 0; }

  # El directorio se calcula aquí, no en el servidor: anidar $( ) dentro de la
  # cadena entrecomillada que viaja por SSH obliga a un escapado frágil.
  local destino_dir; destino_dir="$(dirname "$BC_HESTIA_RCLONE_CONF")"

  bc_hestia_root_stdin "
    umask 077
    mkdir -p '$destino_dir'
    [ -f '$BC_HESTIA_RCLONE_CONF' ] && cp -a '$BC_HESTIA_RCLONE_CONF' '$BC_HESTIA_RCLONE_CONF.anterior'
    cat > '$BC_HESTIA_RCLONE_CONF'
    chmod 600 '$BC_HESTIA_RCLONE_CONF'
  " < "$origen" || bc_die "no se pudo escribir la configuración en el servidor."

  bc_ok "Instalado. Los remotos guardados ya funcionan en este servidor."
  bc_log "Comprueba uno con:  rclone lsd <remoto>:"
}

# =============================================================================
# Asistente completo
# =============================================================================
bc_hestia_setup() {
  bc_can_prompt || bc_die "el asistente necesita un terminal. Desde la web usa la pestaña HestiaCP."
  bc_section "Montar los respaldos incrementales de HestiaCP"
  bc_log "Cuatro pasos: remoto de rclone, host de respaldo, cron y rescate de claves."
  echo
  bc_hestia_rclone
  echo
  bc_hestia_restic
  echo
  bc_hestia_cron
  echo
  bc_hestia_keys
  echo
  bc_ok "Listo. Comprueba con:  backupctl hestia status"
}
