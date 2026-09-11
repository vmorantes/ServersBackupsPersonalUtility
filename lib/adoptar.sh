#!/usr/bin/env bash
# =============================================================================
# lib/adoptar.sh — resucitar usuarios en OTRO HestiaCP
# =============================================================================
# La prueba de fuego de todo el ecosistema: el servidor original ya no existe,
# o está a punto de no existir, y hay que devolver a la vida a uno o varios de
# sus usuarios en un HestiaCP cualquiera, partiendo solo de:
#
#   - el rclone.conf rescatado   → cómo LLEGAR al repositorio
#   - las claves rescatadas      → cómo DESCIFRARLO
#
# Nada más. Ni el servidor viejo, ni su base de datos, ni su configuración.
#
# CÓMO LO HACE HESTIACP (leído de v-restore-user-full-restic 1.10.4)
#   v-restore-user-full-restic USUARIO INSTANTÁNEA CLAVE
#   está pensada explícitamente «from a non existing user»: si el usuario no
#   existe, lo crea con v-add-user usando la CLAVE RESTIC como contraseña
#   inicial, escribe esa clave en data/users/<u>/restic.conf, y después
#   restaura dominios web, DNS, correo, bases de datos, crones y archivos.
#
# EL CONFLICTO QUE HAY QUE MANEJAR CON CUIDADO
#   HestiaCP tiene UN SOLO repositorio global, en conf/restic.conf, y la orden
#   de restauración lee de ahí. Para leer un repositorio ajeno hay que apuntar
#   ese archivo al repositorio ajeno... lo que dejaría al servidor de destino
#   respaldándose en el sitio equivocado si se olvida devolverlo a su sitio.
#
#   Así que: se guarda el original, se apunta al ajeno, se restaura, y se
#   devuelve el original SIEMPRE, incluso si algo falla por el camino.
# =============================================================================

[[ -n "${BC_ADOPTAR_LOADED:-}" ]] && return 0
BC_ADOPTAR_LOADED=1

BC_AD_CONF_ORIGINAL=""
BC_AD_DESTINO=""

# Devuelve el conf/restic.conf del destino a como estaba. Se llama pase lo que
# pase: si no, el servidor de destino quedaría respaldándose en un repositorio
# que no es suyo, y nadie se daría cuenta hasta necesitarlo.
bc_ad_restaurar_conf() {
  [[ -n "$BC_AD_DESTINO" ]] || return 0
  local remoto="/usr/local/hestia/conf/restic.conf"
  if [[ -n "$BC_AD_CONF_ORIGINAL" ]]; then
    printf '%s\n' "$BC_AD_CONF_ORIGINAL" | bc_ssh_sudo "cat > '$remoto'" >/dev/null 2>&1 \
      && bc_ok "Devuelta la configuración de respaldo propia del destino." \
      || bc_err "NO se pudo devolver conf/restic.conf del destino. Revísalo a mano."
  else
    bc_ssh_sudo "rm -f '$remoto'" >/dev/null 2>&1 \
      && bc_log "Retirado el conf/restic.conf temporal (el destino no tenía uno)." \
      || true
  fi
  BC_AD_CONF_ORIGINAL=""; BC_AD_DESTINO=""
}

# Lee las claves rescatadas. Devuelve, por la salida estándar, líneas
# «usuario<TAB>clave», y por BC_AD_REPO el repositorio global rescatado.
BC_AD_REPO=""

# -----------------------------------------------------------------------------
# Todas las claves rescatadas, no solo las del último rescate
# -----------------------------------------------------------------------------
# Cada rescate es una foto de los usuarios que existían ESE día. Cuando se borra
# un usuario del servidor, los rescates posteriores dejan de incluirlo... pero su
# repositorio sigue en el almacenamiento, entero, y su clave sigue estando en los
# rescates anteriores.
#
# Mirar solo el archivo más reciente hacía desaparecer del inventario justo a los
# usuarios que ya no existen en ningún sitio: los únicos que de verdad dependen
# de esto. Comprobado con 'naturalsurf', borrado del servidor el 2026-09-08.
#
# Así que se recorren TODOS los rescates, del más antiguo al más nuevo, y para
# cada usuario se queda la clave más reciente que se le conozca. Salida:
#   usuario<TAB>clave<TAB>archivo-de-donde-salió
bc_ad_leer_claves() {
  local dir; dir="$(bc_hestia_salida)"
  local -a archivos=()
  mapfile -t archivos < <( { find "$dir" -maxdepth 1 -name 'Restic_Configs_*.txt' -printf '%T@ %p\n' 2>/dev/null || true; } \
                           | sort -n | cut -d' ' -f2- )
  (( ${#archivos[@]} > 0 )) || { bc_err "no hay ninguna clave rescatada en $dir." >&2; return 1; }
  bc_log "Rescates leídos: ${#archivos[@]} (del más antiguo al más nuevo)" >&2

  local f
  for f in "${archivos[@]}"; do
    awk -v origen="$(basename "$f")" '
      /^# [A-Za-z0-9._-]+:$/ { u = substr($2, 1, length($2)-1); next }
      /^=+$/                 { u = ""; next }
      /^#/                   { next }
      NF == 0                { next }
      u != "" && $0 !~ /=/    { print u "\t" $0 "\t" origen; u = "" }
    ' "$f"
  done | awk -F'\t' '{ ultimo[$1] = $0 } END { for (u in ultimo) print ultimo[u] }' | sort
}

# El repositorio se lee aparte y NO dentro de bc_ad_leer_claves: esa función se
# invoca como "$(...)", o sea en una subshell, y cualquier variable que asignara
# allí se perdería al volver. Ya me pasó con los contadores de verify.
bc_ad_repo_rescatado() {
  local dir; dir="$(bc_hestia_salida)"
  local archivo
  # Del más reciente hacia atrás: el primero que lo tenga. Un rescate posterior
  # podría no incluirlo si la configuración global se hubiera borrado.
  local f
  while IFS= read -r f; do
    local r; r="$(sed -n "s/^REPO='\(.*\)'$/\1/p" "$f" | head -1)"
    [[ -n "$r" ]] && { printf '%s\n' "$r"; return 0; }
  done < <( { find "$dir" -maxdepth 1 -name 'Restic_Configs_*.txt' -printf '%T@ %p\n' 2>/dev/null || true; } \
            | sort -rn | cut -d' ' -f2- )
  return 1
}

bc_ad_rclone_rescatado() {
  local dir; dir="$(bc_hestia_salida)"
  { find "$dir" -maxdepth 1 -name 'rclone_*.conf' -printf '%T@ %p\n' 2>/dev/null || true; } \
    | sort -rn | head -1 | cut -d' ' -f2-
}

# -----------------------------------------------------------------------------
# Inventario: qué se puede resucitar, sin tocar ningún servidor
# -----------------------------------------------------------------------------
bc_adoptar_inventario() {
  bc_section "Qué se puede resucitar"
  bc_log "Solo se lee: el almacenamiento remoto y las claves rescatadas."
  bc_log "No se toca ningún servidor."

  local claves; claves="$(bc_ad_leer_claves)" || return 1
  [[ -n "$claves" ]] || { bc_err "el archivo de claves no contiene ninguna clave de usuario."; return 1; }
  BC_AD_REPO="$(bc_ad_repo_rescatado || true)"
  local rc; rc="$(bc_ad_rclone_rescatado)"
  [[ -n "$rc" ]] || { bc_err "no hay ningún rclone.conf rescatado: no se puede LLEGAR al repositorio."; return 1; }

  bc_log "Repositorio: ${BC_AD_REPO:-(no consta en el rescate)}"
  bc_log "Acceso:      $rc"
  echo

  bc_require_cmd restic
  bc_require_cmd rclone

  local tmp; tmp="$(mktemp -d)"; chmod 700 "$tmp"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  cp "$rc" "$tmp/rclone.conf"; chmod 600 "$tmp/rclone.conf"

  local filas="$tmp/filas"; : > "$filas"
  local u k n ultima
  local origen
  while IFS=$'\t' read -r u k origen; do
    [[ -n "$u" && -n "$k" ]] || continue
    printf '%s' "$k" > "$tmp/clave"; chmod 600 "$tmp/clave"
    local salida
    salida="$(RCLONE_CONFIG="$tmp/rclone.conf" RESTIC_PASSWORD_FILE="$tmp/clave" \
              restic -r "${BC_AD_REPO%/}/$u" snapshots --json 2>/dev/null || true)"
    if [[ -z "$salida" || "$salida" == "null" ]]; then
      printf '%s\tNO SE PUDO ABRIR\t-\t-\t%s\n' "$u" "${origen#Restic_Configs_}" >> "$filas"
      continue
    fi
    n="$(python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' <<<"$salida" 2>/dev/null || echo 0)"
    ultima="$(python3 -c 'import json,sys;d=json.load(sys.stdin);print(d[-1]["time"][:19].replace("T"," ")+"  "+d[-1]["short_id"]) if d else print("-")' <<<"$salida" 2>/dev/null || echo '-')"
    printf '%s\tsí\t%s\t%s\t%s\n' "$u" "$n" "$ultima" "${origen#Restic_Configs_}" >> "$filas"
  done <<<"$claves"

  {
    printf 'USUARIO\tDESCIFRA\tINSTANTÁNEAS\tLA MÁS RECIENTE\tCLAVE DE\n'
    cat "$filas"
  } | bc_table | sed 's/^/        /'

  echo
  local malos; malos="$(awk -F'\t' '$2 ~ /NO SE PUDO/' "$filas" | wc -l)"
  if (( malos > 0 )); then
    bc_err "$malos usuario(s) no se pudieron abrir: clave equivocada o repositorio ausente."
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  bc_ok "Todo lo rescatado se descifra y se puede resucitar."
  bc_log "Para llevarlo a un servidor:  backupctl -p $BC_PROFILE adoptar --to root@servidor --usuarios <u1,u2>"
  return 0
}

# -----------------------------------------------------------------------------
# Resucitar en un servidor de destino
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# restic en el destino, y en una versión que sepa leer el repositorio
# -----------------------------------------------------------------------------
# Los repositorios que crea HestiaCP con restic moderno usan el FORMATO v2
# (compresión), comprobado con `restic cat config`. Ese formato exige restic
# 0.14 o superior.
#
# En Ubuntu 22.04, `apt install restic` da la 0.12.1, que NO lo lee. En un
# servidor limpio la resurrección se paraba al primer paso con un error de
# formato que no dice la causa. HestiaCP lo resuelve con `apt install` +
# `restic self-update` dentro de v-add-backup-host-restic, y en el servidor de
# pruebas se ve el resultado: el paquete de apt figura instalado y el binario
# es la 0.18.1. Aquí se hace lo mismo, y se COMPRUEBA la versión después en
# vez de darla por buena.
bc_ad_asegurar_restic() {
  local seco="${1:-0}" v num ma mi
  v="$(bc_ssh_sudo "restic version 2>/dev/null | head -1" < /dev/null | tr -d '\r')"
  if [[ -z "$v" ]]; then
    bc_warn "restic NO está en el destino."
    if (( seco )); then
      bc_log "Simulación: se instalaría con apt y se actualizaría con «restic self-update»."
      return 0
    fi
    bc_confirm "¿Instalarlo en el destino?" y || bc_die "sin restic no se puede leer el almacenamiento."
    bc_ssh_sudo "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq restic" < /dev/null \
      || bc_die "no se pudo instalar restic en el destino."
    v="$(bc_ssh_sudo "restic version 2>/dev/null | head -1" < /dev/null | tr -d '\r')"
  fi
  num="$(grep -oP 'restic \K[0-9]+\.[0-9]+' <<<"$v" || true)"
  IFS=. read -r ma mi <<<"${num:-0.0}"
  if (( ma == 0 && mi < 14 )); then
    bc_warn "restic $num en el destino: NO lee el formato v2 de tus repositorios (hace falta 0.14+)."
    if (( seco )); then
      bc_log "Simulación: se actualizaría con «restic self-update»."
      return 0
    fi
    bc_ssh_sudo "restic self-update" < /dev/null >/dev/null 2>&1 || true
    v="$(bc_ssh_sudo "restic version 2>/dev/null | head -1" < /dev/null | tr -d '\r')"
    num="$(grep -oP 'restic \K[0-9]+\.[0-9]+' <<<"$v" || true)"
    IFS=. read -r ma mi <<<"${num:-0.0}"
    if (( ma == 0 && mi < 14 )); then
      bc_err "No se pudo actualizar restic en el destino (sigue en $num)."
      bc_log "Instala a mano el binario oficial de https://github.com/restic/restic/releases"
      bc_log "y repite. No se ha escrito nada en el destino."
      BC_DELIBERATE_EXIT=1
      return 1
    fi
  fi
  bc_ok "restic en el destino: $v"
}

bc_adoptar_run() {
  local destino="${BC_OPT_TO:-}"
  local pedidos="${BC_OPT_USERS:-}"
  local seco="${BC_OPT_DRY:-0}"

  [[ -n "$destino" ]] || bc_die "indica el servidor de destino: --to root@servidor"

  bc_section "Resucitar usuarios en $destino"
  bc_warn "El destino se MODIFICA: se crean usuarios, dominios, correo y bases de datos."
  bc_log  "Lo que NO se toca: el servidor de origen, que puede no existir ya."

  # --- 1. Lo que tenemos ------------------------------------------------------
  bc_step "1 · Material rescatado"
  local claves; claves="$(bc_ad_leer_claves)" || return 1
  BC_AD_REPO="$(bc_ad_repo_rescatado || true)"
  local rc; rc="$(bc_ad_rclone_rescatado)"
  [[ -n "$rc" ]] || { bc_err "no hay rclone.conf rescatado: sin él no se llega al repositorio."; return 1; }
  [[ -n "$BC_AD_REPO" ]] || { bc_err "el rescate no incluye el repositorio (REPO). Sin él no se sabe dónde mirar."; return 1; }
  bc_ok "Repositorio: $BC_AD_REPO"

  local disponibles; disponibles="$(cut -f1 <<<"$claves" | tr '\n' ' ')"
  bc_ok "Usuarios con clave: $disponibles"

  # --- 2. Cuáles ------------------------------------------------------------
  local -a lista=()
  if [[ -n "$pedidos" ]]; then
    local u
    for u in ${pedidos//,/ }; do
      grep -q "^$u	" <<<"$claves" || bc_die "no hay clave rescatada de '$u'. Disponibles: $disponibles"
      lista+=("$u")
    done
  else
    mapfile -t lista < <(cut -f1 <<<"$claves")
  fi
  bc_log "Se resucitarán: ${lista[*]}"

  # --- 3. El destino ---------------------------------------------------------
  bc_step "2 · El servidor de destino"
  bc_require_cmd ssh
  bc_ssh_init "$destino" || bc_die "no se pudo conectar a $destino."
  trap 'bc_ad_restaurar_conf; bc_ssh_close' RETURN

  bc_ssh_sudo "test -x /usr/local/hestia/bin/v-add-user" >/dev/null 2>&1 \
    || bc_die "en $destino no hay HestiaCP (falta /usr/local/hestia/bin/v-add-user)."
  local version; version="$(bc_ssh_sudo "cat /usr/local/hestia/conf/hestia.conf 2>/dev/null | grep -oP \"VERSION='\\K[^']+\"" 2>/dev/null | tr -d '\r')"
  bc_ok "HestiaCP presente${version:+ (versión $version)}"

  # Usuarios que YA existen allí: no se pisan jamás
  local existentes
  existentes="$(bc_ssh_sudo "ls /usr/local/hestia/data/users/ 2>/dev/null" < /dev/null | tr -d '\r')"
  bc_log "Cuentas que ya hay en el destino: $(tr '\n' ' ' <<<"$existentes")"
  local u choque=0
  for u in "${lista[@]}"; do
    if grep -qx "$u" <<<"$existentes"; then
      bc_err "  '$u' YA EXISTE en el destino. No se toca: resucitarlo encima destruiría lo que haya."
      choque=1
    fi
  done
  if (( choque )); then
    bc_err "Renombra o elimina esas cuentas en el destino, o pide solo las demás con --usuarios."
    BC_DELIBERATE_EXIT=1
    return 1
  fi

  # --- 4. Herramientas -------------------------------------------------------
  bc_step "3 · Herramientas en el destino"
  local v_rclone
  v_rclone="$(bc_ssh_sudo "rclone version 2>/dev/null | head -1" < /dev/null | tr -d '\r')"
  if [[ -z "$v_rclone" ]]; then
    bc_warn "rclone NO está en el destino. Sin él no se puede llegar al almacenamiento."
    if (( seco )); then
      bc_log "Simulación: se instalaría con apt."
    else
      bc_confirm "¿Instalarlo con apt en $destino?" y || bc_die "sin rclone no se puede continuar."
      bc_ssh_sudo "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rclone" \
        || bc_die "no se pudo instalar rclone en el destino."
      v_rclone="$(bc_ssh_sudo "rclone version 2>/dev/null | head -1" < /dev/null | tr -d '\r')"
      bc_ok "rclone instalado: $v_rclone"
    fi
  else
    bc_ok "rclone: $v_rclone"
  fi
  # «HestiaCP lo instalará solo» era falso: solo lo hace v-add-backup-host-restic,
  # que este flujo no llama. Y aunque lo hiciera, la versión de apt no basta.
  bc_ad_asegurar_restic "$seco" || return 1

  if (( seco )); then
    echo
    bc_ok "Simulación (--dry-run). Lo que se haría a partir de aquí:"
    bc_log "  1. Copiar el rclone.conf rescatado al destino (guardando el suyo)."
    bc_log "  2. Apuntar temporalmente conf/restic.conf al repositorio rescatado."
    bc_log "  3. Por cada usuario: v-restore-user-full-restic <u> <instantánea> <clave>"
    bc_log "     que lo CREA, restaura web, DNS, correo, bases de datos, crones y archivos."
    bc_log "  4. Devolver el conf/restic.conf propio del destino, pase lo que pase."
    return 0
  fi

  echo
  bc_warn "A partir de aquí se ESCRIBE en $destino."
  bc_confirm "¿Resucitar ${#lista[@]} usuario(s) en $destino?" n || { bc_log "Cancelado."; return 0; }

  # --- 5. Acceso al repositorio ---------------------------------------------
  bc_step "4 · Dar acceso al repositorio"
  bc_ssh_sudo "mkdir -p /root/.config/rclone && cp -a /root/.config/rclone/rclone.conf /root/.config/rclone/rclone.conf.antes-de-adoptar 2>/dev/null; true" >/dev/null 2>&1 || true
  # Se AÑADE la sección rescatada al final, sin borrar los remotos que el
  # destino ya tuviera: podría estar respaldándose en otro sitio.
  local nombre_remoto; nombre_remoto="$(grep -oP '^\[\K[^]]+' "$rc" | head -1)"
  if bc_ssh_sudo "grep -q '^\[$nombre_remoto\]' /root/.config/rclone/rclone.conf 2>/dev/null"; then
    bc_ok "El remoto '$nombre_remoto' ya existe en el destino; no se toca."
  else
    bc_ssh_sudo_stdin "umask 077; mkdir -p /root/.config/rclone; cat >> /root/.config/rclone/rclone.conf; chmod 600 /root/.config/rclone/rclone.conf" < "$rc" \
      || bc_die "no se pudo copiar el acceso al almacenamiento."
    bc_ok "Remoto '$nombre_remoto' añadido (los que ya hubiera siguen intactos)."
  fi

  # --- 6. Apuntar al repositorio ajeno, temporalmente -----------------------
  bc_step "5 · Apuntar al repositorio rescatado (temporal)"
  BC_AD_DESTINO="$destino"
  BC_AD_CONF_ORIGINAL="$(bc_ssh_sudo "cat /usr/local/hestia/conf/restic.conf 2>/dev/null" < /dev/null || true)"
  if [[ -n "$BC_AD_CONF_ORIGINAL" ]]; then
    bc_warn "El destino ya tenía su propia configuración de respaldo. Se guarda y se"
    bc_warn "devolverá al terminar, pase lo que pase."
  fi
  printf "REPO='%s'\nSNAPSHOTS='30'\nKEEP_DAILY='8'\nKEEP_WEEKLY='5'\nKEEP_MONTHLY='3'\nKEEP_YEARLY='-1'\n" "${BC_AD_REPO%/}" \
    | bc_ssh_sudo_stdin "cat > /usr/local/hestia/conf/restic.conf" \
    || bc_die "no se pudo apuntar al repositorio rescatado."
  bc_ok "Apuntando a: ${BC_AD_REPO%/}"

  # --- 7. Resucitar ----------------------------------------------------------
  bc_step "6 · Resucitar"
  local fallos=0 k snap
  for u in "${lista[@]}"; do
    k="$(awk -F'\t' -v u="$u" '$1==u{print $2; exit}' <<<"$claves")"
    snap="${BC_OPT_SNAPSHOT:-latest}"
    if ! bc_ad_avisar_si_menguada "$BC_AD_REPO" "$u" "$snap" "$claves" "$rc"; then
      bc_confirm "¿Restaurar '$u' de todas formas?" n \
        || { bc_log "'$u' omitido."; continue; }
    fi
    echo
    bc_log "── $u  (instantánea: $snap)"
    if bc_ssh_sudo "/usr/local/hestia/bin/v-restore-user-full-restic '$u' '$snap' '$k'"; then
      bc_ok "'$u' resucitado."
    else
      bc_err "'$u' FALLÓ. Los demás siguen."
      fallos=$((fallos+1))
    fi
  done

  echo
  bc_ad_restaurar_conf

  echo
  if (( fallos )); then
    bc_err "Terminado con $fallos fallo(s) de ${#lista[@]}."
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  bc_ok "Los ${#lista[@]} usuarios están vivos en $destino."
  bc_warn "Su contraseña de panel es, de momento, su clave Restic: cámbiala."
  bc_log  "Comprueba en el panel: dominios, correo y bases de datos."
  return 0
}

# =============================================================================
# Las bases de datos que HestiaCP NO conoce
# =============================================================================
# El respaldo de HestiaCP solo incluye las bases que están registradas en su
# panel. En el servidor de pruebas eran 14 de 80: las otras 66 se habían creado
# a mano en MySQL y no existen en NINGUNA instantánea de Restic.
#
# Esas viven solo en el zip de backupctl, que vuelca todo lo que hay en MySQL.
# Esta orden las lleva a otro servidor, y de paso permite renombrarlas: una base
# puede llamarse distinto en el destino sin tocar el respaldo de origen.
#
# El SQL viaja por la entrada estándar de un `mysql` remoto: no se deja ningún
# archivo intermedio en el servidor de destino.
# =============================================================================

# Las bases que HestiaCP conoce, según el rescate. Sirve para no duplicar: las
# que HestiaCP conoce llegan solas al restaurar el usuario.
bc_ad_bases_de_hestia() {
  local destino="$1"
  bc_ssh_sudo "cat /usr/local/hestia/data/users/*/db.conf 2>/dev/null | grep -oP \"^DB='\\K[^']+\"" < /dev/null 2>/dev/null || true
}

bc_adoptar_bases() {
  local destino="${BC_OPT_TO:-}"
  local pedidas="${BC_OPT_DBS:-}"
  local prefijo="${BC_OPT_PREFIJO:-}"
  local seco="${BC_OPT_DRY:-0}"

  [[ -n "$destino" ]] || bc_die "indica el servidor de destino: --to root@servidor"

  local zip_path
  zip_path="$(bc_backup_resolve "${BC_OPT_ZIP:-}")" \
    || bc_die "no se encontró el respaldo. Mira cuáles hay con: backupctl -p $BC_PROFILE list"

  bc_section "Llevar bases de datos a $destino"
  bc_log "Respaldo de origen: $zip_path"
  bc_require_cmd unzip

  # --- Qué hay en el zip ------------------------------------------------------
  local -a en_zip=()
  mapfile -t en_zip < <(unzip -Z1 "$zip_path" 2>/dev/null | awk -F/ 'NF>1{print $1}' | sort -u)
  (( ${#en_zip[@]} > 0 )) || bc_die "el respaldo no contiene ninguna base de datos."
  bc_ok "El respaldo contiene ${#en_zip[@]} bases de datos."

  # --- Conectar ---------------------------------------------------------------
  bc_require_cmd ssh
  bc_ssh_init "$destino" || bc_die "no se pudo conectar a $destino."
  trap 'bc_ssh_close' RETURN
  bc_ssh_sudo "mysql -e 'SELECT 1'" >/dev/null 2>&1 \
    || bc_die "no se puede usar MySQL como root en $destino."
  bc_ok "MySQL accesible en el destino."

  # El prefijo de privilegios se decide UNA vez y se guarda. bc_ssh_sudo empieza
  # comprobando `id -u` en el servidor, y esa comprobación LEE DE LA ENTRADA
  # ESTÁNDAR: al enviarle un volcado SQL por tubería se comía el principio y
  # mysql recibía una sentencia cortada por la mitad. El error que salía
  # («syntax error near...») no apuntaba ni de lejos a la causa.
  local sudo_pre=""
  bc_ssh "test \$(id -u) -eq 0" < /dev/null 2>/dev/null || sudo_pre="sudo -n "

  # --- Cuáles ------------------------------------------------------------------
  local -a lista=()
  if [[ -n "$pedidas" ]]; then
    local b
    for b in ${pedidas//,/ }; do
      printf '%s\n' "${en_zip[@]}" | grep -qx "$b" || bc_die "'$b' no está en el respaldo."
      lista+=("$b")
    done
  elif [[ "${BC_OPT_SOLO_DESCONOCIDAS:-0}" == "1" ]]; then
    # Las que HestiaCP ya restaurará por su cuenta se excluyen para no duplicar
    local conocidas; conocidas="$(bc_ad_bases_de_hestia "$destino")"
    local b
    for b in "${en_zip[@]}"; do
      grep -qx "$b" <<<"$conocidas" || lista+=("$b")
    done
    bc_log "HestiaCP ya conoce $(grep -c . <<<"$conocidas" || true) en el destino; se omiten."
  else
    lista=("${en_zip[@]}")
  fi
  # Las bases del sistema no son de ningún cliente: roundcube es el webmail y
  # phpmyadmin el gestor. El zip las trae porque vuelca todo MySQL, pero en el
  # destino ya existen las suyas. Solo viajan si se piden por su nombre.
  if [[ -z "$pedidas" ]]; then
    local -a sin_sistema=()
    for b in "${lista[@]}"; do
      case "$b" in
        roundcube|phpmyadmin|mysql|sys|information_schema|performance_schema|test) ;;
        *) sin_sistema+=("$b") ;;
      esac
    done
    if (( ${#sin_sistema[@]} < ${#lista[@]} )); then
      bc_log "Se omiten $(( ${#lista[@]} - ${#sin_sistema[@]} )) base(s) del sistema (roundcube, phpmyadmin...)."
    fi
    lista=("${sin_sistema[@]}")
  fi
  bc_log "Se llevarán ${#lista[@]} base(s)."
  [[ -n "$prefijo" ]] && bc_log "Se renombrarán con el prefijo: $prefijo"

  # --- Cuáles chocarían -------------------------------------------------------
  local ya
  ya="$(bc_ssh_sudo "mysql -N -e \"SELECT schema_name FROM information_schema.schemata\"" < /dev/null 2>/dev/null || true)"
  local -a choques=()
  local b destino_b
  for b in "${lista[@]}"; do
    destino_b="${prefijo}${b}"
    grep -qx "$destino_b" <<<"$ya" && choques+=("$destino_b")
  done
  # Una base que ya existe en el destino NO se toca nunca. Antes se preguntaba
  # «¿escribir encima?», y bastaba una confirmación automática —la de la
  # interfaz, o un --yes— para machacar la base de otro cliente, o la de
  # roundcube del propio servidor, que el zip también trae.
  if (( ${#choques[@]} > 0 )); then
    bc_warn "Estas bases YA EXISTEN en el destino. No se tocan:"
    printf '        - %s\n' "${choques[@]}" >&2
    bc_log "Para traerlas igualmente, usa --prefijo y llegarán con otro nombre."
    local -a quedan=()
    for b in "${lista[@]}"; do
      printf '%s\n' "${choques[@]}" | grep -qx "${prefijo}${b}" || quedan+=("$b")
    done
    lista=("${quedan[@]}")
    if (( ${#lista[@]} == 0 )); then
      bc_ok "No queda ninguna base por llevar."
      return 0
    fi
    bc_log "Se llevarán las ${#lista[@]} restantes."
  fi

  if (( seco )); then
    echo
    bc_ok "Simulación (--dry-run). Se llevarían:"
    for b in "${lista[@]}"; do printf '        %s  ->  %s\n' "$b" "${prefijo}${b}"; done
    return 0
  fi

  bc_confirm "¿Llevar ${#lista[@]} base(s) a $destino?" n || { bc_log "Cancelado."; return 0; }

  # --- Traslado ---------------------------------------------------------------
  local tmp; tmp="$(mktemp -d)"; chmod 700 "$tmp"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'; bc_ssh_close" RETURN

  local fallos=0 hechas=0 seg
  for b in "${lista[@]}"; do
    destino_b="${prefijo}${b}"
    echo
    bc_log "── $b  ->  $destino_b"
    rm -rf "${tmp:?}/x"; mkdir -p "$tmp/x"
    if ! unzip -qq "$zip_path" "$b/*" -d "$tmp/x" 2>/dev/null; then
      bc_err "   no se pudo extraer del respaldo."; fallos=$((fallos+1)); continue
    fi

    # El CREATE DATABASE se rehace aquí para poder cambiar el nombre; se
    # conservan el juego de caracteres y la colación originales, que es donde
    # se pierden los acentos y los emojis si uno los da por supuestos.
    # database.sql viaja comprimido dentro del zip, como todos los segmentos.
    local charset colacion cabecera=""
    if [[ -f "$tmp/x/$b/database.sql.gz" ]]; then
      cabecera="$(gzip -dc "$tmp/x/$b/database.sql.gz" 2>/dev/null || true)"
    elif [[ -f "$tmp/x/$b/database.sql" ]]; then
      cabecera="$(cat "$tmp/x/$b/database.sql" 2>/dev/null || true)"
    fi
    charset="$( { sed -n 's/.*CHARACTER SET \([A-Za-z0-9_]*\).*/\1/p' <<<"$cabecera" || true; } | head -1)"
    colacion="$( { sed -n 's/.*COLLATE \([A-Za-z0-9_]*\).*/\1/p'      <<<"$cabecera" || true; } | head -1)"
    charset="${charset:-utf8mb4}"; colacion="${colacion:-utf8mb4_general_ci}"
    bc_log "   juego de caracteres: $charset / $colacion"

    if ! bc_ssh_sudo "mysql -e \"CREATE DATABASE IF NOT EXISTS \\\`$destino_b\\\` CHARACTER SET $charset COLLATE $colacion\"" < /dev/null; then
      bc_err "   no se pudo crear '$destino_b' en el destino."; fallos=$((fallos+1)); continue
    fi

    local error=0
    for seg in database tables data views functions others; do
      [[ -f "$tmp/x/$b/$seg.sql.gz" ]] || continue
      [[ "$seg" == "database" ]] && continue   # ya la hemos creado, con el nombre nuevo
      # ---------------------------------------------------------------------
      # El `USE` de la cabecera hay que quitarlo, SIEMPRE.
      # ---------------------------------------------------------------------
      # Cada segmento empieza con  USE `nombre_original`;  Si se envía tal cual
      # a `mysql <destino>`, el USE manda: el SQL entero se aplica a la base
      # ORIGINAL y no a la nueva. Sin ningún error, porque para MySQL es una
      # orden perfectamente válida.
      #
      # Comprobado a mi costa: en la primera prueba esto recreó las tablas de
      # 'augustoangel' en el servidor de origen, vaciándola, mientras informaba
      # de que la base de destino estaba vacía. Con el nombre original presente
      # en el destino —lo normal al migrar entre servidores parecidos— habría
      # arrasado la base buena creyendo que escribía en la nueva.
      if ! gzip -dc "$tmp/x/$b/$seg.sql.gz" \
           | sed -E 's/^USE `[^`]*`;$//' \
           | bc_ssh "${sudo_pre}mysql --default-character-set=$charset '$destino_b'"; then
        bc_err "   falló el segmento $seg"; error=1
      fi
    done
    if (( error )); then fallos=$((fallos+1)); continue; fi

    # Comprobación posterior: lo que cuenta es lo que hay en el destino, no que
    # las órdenes salieran sin error. Una base creada y vacía es un fallo que
    # antes se contaba como éxito, y es justo el que no se nota hasta que hace
    # falta el dato.
    local n esperadas
    n="$(bc_ssh_sudo "mysql -N -e \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$destino_b'\"" < /dev/null 2>/dev/null | tr -d '\r')"
    esperadas="$( { gzip -dc "$tmp/x/$b/tables.sql.gz" 2>/dev/null | grep -c '^CREATE TABLE' || true; } )"
    if [[ "${n:-0}" -eq 0 ]] && [[ "${esperadas:-0}" -gt 0 ]]; then
      bc_err "   '$destino_b' quedó VACÍA y el respaldo tiene $esperadas tablas."
      fallos=$((fallos+1)); continue
    fi
    if [[ "${esperadas:-0}" -gt 0 ]] && [[ "${n:-0}" -lt "$esperadas" ]]; then
      bc_warn "   '$destino_b' con $n tablas, pero el respaldo tiene $esperadas."
      fallos=$((fallos+1)); continue
    fi
    bc_ok "   '$destino_b' con $n tablas (el respaldo tiene $esperadas)."
    hechas=$((hechas+1))
  done

  echo
  bc_log "Llevadas: $hechas. Con fallos: $fallos."
  if (( fallos )); then
    bc_err "Terminado con fallos. Las que sí pasaron están completas."
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  bc_ok "Las $hechas bases están en $destino."
  bc_warn "Falta darles usuario y permisos: estas bases no las conoce HestiaCP,"
  bc_warn "igual que no las conocía en el origen. Créales su usuario MySQL donde"
  bc_warn "haga falta, o regístralas en el panel con v-add-database."
  return 0
}

# =============================================================================
# Resucitar CON OTRO NOMBRE
# =============================================================================
# v-restore-user-full-restic restaura siempre con el nombre original: todas sus
# rutas internas son "/home/$user/...". Y HestiaCP no sabe renombrar cuentas:
# v-change-user-name cambia el nombre de pila del contacto, no la cuenta.
#
# Pero al abrir una instantánea se ve que el nombre del usuario apenas está
# dentro de los archivos:
#
#   hestia/user.conf     NO lo contiene: la cuenta se identifica por su CARPETA
#   dns/<d>/hestia/*.conf NO lo contiene: solo el dominio
#   pam/passwd            sí, y de ahí solo se usa el uid antiguo
#   db/<b>/hestia/db.conf sí, en DB= y DBUSER=, por el prefijo <usuario>_
#
# Y HestiaCP reconstruye una cuenta entera desde data/users/<u>/*.conf con
# v-rebuild-user. Así que renombrar es: crear la cuenta con el nombre nuevo,
# dejarle sus archivos y sus .conf, dar de alta sus bases, y reconstruir.
#
# Los DOMINIOS no se tocan: son nombres DNS, no del usuario. Que un dominio
# contenga el nombre viejo —naturalsurf.co para el usuario naturalsurf— es una
# coincidencia, y renombrarlo rompería el sitio. Un reemplazo a lo bruto sobre
# el árbol habría hecho justo eso.
# =============================================================================

# Comprobación obligatoria antes de restaurar: ¿la instantánea elegida tiene
# menos que alguna anterior? Devuelve 1 si conviene detenerse.
bc_ad_avisar_si_menguada() {
  local repo="$1" u="$2" snap="$3" claves="$4" rc="$5"
  bc_has_cmd restic || return 0
  bc_ad_preparar "$u" "$claves" "$rc" || return 0

  local ids
  ids="$(RCLONE_CONFIG="$BC_AD_TMP/rclone.conf" RESTIC_PASSWORD_FILE="$BC_AD_TMP/clave" \
         restic -r "${repo%/}/$u" snapshots --json 2>/dev/null \
         | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d[-6:][::-1]: print(s['short_id'])
" 2>/dev/null || true)"
  [[ -n "$ids" ]] || { rm -rf "$BC_AD_TMP"; BC_AD_TMP=""; return 0; }

  local elegida="$snap"
  [[ "$elegida" == "latest" ]] && elegida="$(head -1 <<<"$ids")"

  local filas; filas="$(mktemp)"
  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    printf '%s\t%s\n' "$id" "$(bc_ad_contenido "$repo" "$u" "$id")" >> "$filas"
  done <<<"$ids"
  rm -rf "$BC_AD_TMP"; BC_AD_TMP=""

  local act mejor_w mejor_m mejor_d act_w act_m act_d
  act="$(awk -F'\t' -v s="$elegida" '$1 ~ "^"s {print; exit}' "$filas")"
  [[ -n "$act" ]] || { rm -f "$filas"; return 0; }
  act_w="$(cut -f3 <<<"$act")"; act_m="$(cut -f5 <<<"$act")"; act_d="$(cut -f6 <<<"$act")"
  [[ "$act_w" =~ ^[0-9]+$ ]] || { rm -f "$filas"; return 0; }
  mejor_w="$( { cut -f3 "$filas" | grep -E '^[0-9]+$' || true; } | sort -n | tail -1)"
  mejor_m="$( { cut -f5 "$filas" | grep -E '^[0-9]+$' || true; } | sort -n | tail -1)"
  mejor_d="$( { cut -f6 "$filas" | grep -E '^[0-9]+$' || true; } | sort -n | tail -1)"

  if (( act_w < mejor_w )) || (( act_m < mejor_m )) || (( act_d < mejor_d )); then
    local recomendada
    recomendada="$(awk -F'\t' -v w="$mejor_w" '$3==w {print $1" ("$2")"; exit}' "$filas")"
    echo
    bc_err "LA INSTANTÁNEA ELEGIDA ESTÁ MENGUADA respecto a otras del mismo usuario:"
    {
      printf 'INSTANTÁNEA\tFECHA\tWEB\tDNS\tCORREO\tBASES\n'
      cat "$filas"
    } | bc_table | sed 's/^/        /'
    bc_log "        Elegida: web $act_w · correo $act_m · bases $act_d"
    bc_log "        La más completa: $recomendada"
    bc_log "        Si borraste cosas a propósito, sigue. Si no, repite con:"
    bc_log "            --snapshot ${recomendada%% *}"
    rm -f "$filas"
    return 1
  fi
  rm -f "$filas"
  bc_ok "La instantánea elegida es la más completa del usuario."
  return 0
}

bc_adoptar_como() {
  local destino="${BC_OPT_TO:-}"
  local viejo="${BC_OPT_USERS:-}"
  local nuevo="${BC_OPT_COMO:-}"
  local snap="${BC_OPT_SNAPSHOT:-latest}"
  local seco="${BC_OPT_DRY:-0}"

  [[ -n "$destino" ]] || bc_die "indica el destino: --to root@servidor"
  [[ -n "$viejo"   ]] || bc_die "indica el usuario de origen: --usuarios <nombre>"
  [[ -n "$nuevo"   ]] || bc_die "indica el nombre nuevo: --como <nombre>"
  [[ "$viejo" != *,* ]] || bc_die "con --como solo se puede traer un usuario a la vez."
  [[ "$nuevo" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] \
    || bc_die "'$nuevo' no vale como nombre de cuenta: minúsculas, dígitos, guiones y _."

  bc_section "Traer '$viejo' a $destino con el nombre '$nuevo'"

  # --- Material --------------------------------------------------------------
  local claves; claves="$(bc_ad_leer_claves)" || return 1
  BC_AD_REPO="$(bc_ad_repo_rescatado || true)"
  [[ -n "$BC_AD_REPO" ]] || bc_die "el rescate no dice cuál es el repositorio."
  local clave; clave="$(awk -F'\t' -v u="$viejo" '$1==u{print $2; exit}' <<<"$claves")"
  [[ -n "$clave" ]] || bc_die "no hay clave rescatada de '$viejo'."
  local rc; rc="$(bc_ad_rclone_rescatado)"
  [[ -n "$rc" ]] || bc_die "no hay rclone.conf rescatado."
  bc_ok "Clave y acceso disponibles para '$viejo'."

  # --- Destino ---------------------------------------------------------------
  bc_require_cmd ssh
  bc_ssh_init "$destino" || bc_die "no se pudo conectar a $destino."
  trap 'bc_ssh_close' RETURN
  bc_ssh_sudo "test -x /usr/local/hestia/bin/v-add-user" >/dev/null 2>&1 \
    || bc_die "en $destino no hay HestiaCP."

  if bc_ssh_sudo "test -d /usr/local/hestia/data/users/$nuevo" >/dev/null 2>&1; then
    bc_err "'$nuevo' YA EXISTE en $destino. No se toca nada."
    bc_log "Elige otro nombre con --como."
    BC_DELIBERATE_EXIT=1; return 1
  fi
  bc_ok "'$nuevo' está libre en el destino."
  bc_ad_asegurar_restic "$seco" || return 1

  # Espacio: hace falta el árbol extraído además de la copia final
  local libre_mb
  libre_mb="$(bc_ssh_sudo "df -Pm /home | awk 'NR==2{print \$4}'" < /dev/null | tr -d '\r')"
  bc_log "Espacio libre en /home del destino: ${libre_mb} MB"

  # Antes de nada, incluido el ensayo: ¿la instantánea elegida está menguada?
  # En el ensayo es donde más falta hace verlo, que es cuando aún se puede
  # cambiar de instantánea sin haber tocado el destino.
  local menguada=0
  bc_ad_avisar_si_menguada "$BC_AD_REPO" "$viejo" "$snap" "$claves" "$rc" || menguada=1

  if (( seco )); then
    echo
    bc_ok "Simulación (--dry-run). Se haría, en este orden:"
    bc_log "  1. v-add-user '$nuevo' <contraseña generada> <contacto>"
    bc_log "  2. restic restore de '$viejo' ($snap) a un directorio temporal"
    bc_log "  3. mover sus archivos a /home/$nuevo/ (los dominios NO se renombran)"
    bc_log "  4. copiar user.conf, web, dns y mail a data/users/$nuevo/"
    bc_log "  5. recrear cada base con su MISMO nombre, usuario y contraseña, e importarla"
    bc_log "  6. v-rebuild-user '$nuevo' yes"
    bc_log "Nada de esto se ha ejecutado."
    return 0
  fi

  if (( menguada )); then
    echo
    bc_confirm "¿Restaurar de todas formas la instantánea menguada?" n \
      || { bc_log "Cancelado. Vuelve con --snapshot <id>."; return 0; }
  fi

  echo
  bc_warn "Se va a CREAR la cuenta '$nuevo' en $destino con todo el contenido de '$viejo'."
  bc_confirm "¿Continuar?" n || { bc_log "Cancelado."; return 0; }

  # --- Ejecución en el destino ----------------------------------------------
  # Va como un script por la entrada estándar: meterlo entrecomillado en la
  # orden de ssh sería una fuente inagotable de errores de escapado, y además
  # dejaría la clave Restic a la vista de cualquier `ps`.
  local contrasena; contrasena="$(bc_gen_password 24)"
  bc_log "Trabajando en el destino. Esto puede tardar varios minutos..."

  # Los secretos y el script NO pueden ir por el mismo canal: `bash -s` lee el
  # script de la entrada estándar, así que un heredoc y una tubería sobre la
  # misma orden se pisan —el heredoc gana y la tubería se pierde—. Se hace en
  # dos pasos: primero los secretos a archivos del servidor, con permisos 600 y
  # por la entrada estándar para que no aparezcan en la línea de órdenes; luego
  # el script, que recibe la ruta del directorio de trabajo.
  local ws
  ws="$(bc_ssh_sudo "mktemp -d /root/.adoptar.XXXXXXXX" < /dev/null | tr -d '\r')"
  [[ -n "$ws" ]] || bc_die "no se pudo crear el directorio de trabajo en el destino."
  bc_ssh_sudo "chmod 700 '$ws'" < /dev/null || true
  # shellcheck disable=SC2064
  trap "bc_ssh_sudo \"rm -rf '$ws'\" </dev/null >/dev/null 2>&1 || true; bc_ssh_close" RETURN

  printf '%s' "$clave"      | bc_ssh_sudo_stdin "umask 077; cat > '$ws/clave'"       || bc_die "no se pudo enviar la clave."
  printf '%s' "$contrasena" | bc_ssh_sudo_stdin "umask 077; cat > '$ws/pass'"        || bc_die "no se pudo enviar la contraseña."
  cat "$rc"                 | bc_ssh_sudo_stdin "umask 077; cat > '$ws/rclone.conf'" || bc_die "no se pudo enviar el acceso."

  # bc_ssh_sudo_stdin y no bc_ssh_sudo: el segundo empieza comprobando `id -u`
  # en el servidor, y esa comprobación LEE DE LA ENTRADA ESTÁNDAR. Se tragaba
  # el script entero, `bash -s` recibía la nada, salía con cero, y la orden
  # informaba de un traslado perfecto sin haber hecho absolutamente nada.
  local rc_final=0
  bc_ssh_sudo_stdin "bash -s '$viejo' '$nuevo' '$snap' '${BC_AD_REPO%/}' '$ws'" <<'REMOTO' || rc_final=$?
set -uo pipefail
VIEJO="$1"; NUEVO="$2"; SNAP="$3"; REPO="$4"; WS="$5"
H=/usr/local/hestia
CLAVE="$(cat "$WS/clave")"
PASS="$(cat "$WS/pass")"

export RCLONE_CONFIG="$WS/rclone.conf" RESTIC_PASSWORD_FILE="$WS/clave"
R="${REPO%/}/$VIEJO"

echo "[1/6] Trayendo la instantánea..."
mkdir -p "$WS/arbol"
restic -r "$R" restore "$SNAP" --target "$WS/arbol" || { echo "FALLO: restic restore"; exit 1; }
SRC="$WS/arbol/home/$VIEJO"
[ -d "$SRC" ] || { echo "FALLO: la instantánea no contiene /home/$VIEJO"; exit 1; }
B="$SRC/backup"
[ -f "$B/backup.conf" ] || { echo "FALLO: falta backup.conf en la instantánea"; exit 1; }

# shellcheck disable=SC1090
eval "$(cat "$B/backup.conf")"
echo "    web='$WEB'  dns='$DNS'  mail='$MAIL'  db='$DB'"

echo "[2/6] Creando la cuenta '$NUEVO'..."
CONTACTO="$(grep -oP "^CONTACT='\K[^']*" "$B/hestia/user.conf" 2>/dev/null || true)"
[ -n "$CONTACTO" ] || CONTACTO="$NUEVO@localhost"
$H/bin/v-add-user "$NUEVO" "$PASS" "$CONTACTO" || { echo "FALLO: v-add-user"; exit 1; }

echo "[3/7] Preparando dominios..."
# ---------------------------------------------------------------------------
# Los dominios se crean ANTES de poner los archivos.
# ---------------------------------------------------------------------------
# v-add-web-domain se niega si la carpeta ya existe («Web domain folder should
# not exist»). Copiando primero, la creación fallaba y el sitio quedaba con sus
# archivos en disco pero invisible para el panel: sin vhost, sin servir nada.
#
# Y si el respaldo no trae la configuración de los dominios —pasa cuando el
# usuario tenía WEB='*' en backup-excludes.conf, que excluye los dominios del
# respaldo de HestiaCP— se reconstruyen a partir de las carpetas que sí
# viajaron dentro del /home. Es la diferencia entre recuperar los archivos y
# recuperar el sitio.
lista_dominios() {   # $1: web|mail
  local tipo="$1" desde_conf="$2"
  if [ -n "$desde_conf" ]; then
    echo "$desde_conf" | tr ',' '\n' | grep -v '^$'
  elif [ -d "$SRC/$tipo" ]; then
    ls -1 "$SRC/$tipo" 2>/dev/null
  fi
}
WEBDOMS="$(lista_dominios web "${WEB:-}")"
MAILDOMS="$(lista_dominios mail "${MAIL:-}")"
[ -z "${WEB:-}" ] && [ -n "$WEBDOMS" ] && \
  echo "    AVISO: el respaldo no traía la configuración de los dominios web."
[ -z "${WEB:-}" ] && [ -n "$WEBDOMS" ] && \
  echo "           Se reconstruyen desde las carpetas: $(echo $WEBDOMS | tr '\n' ' ')"

for dom in $WEBDOMS; do
  [ -n "$dom" ] || continue
  $H/bin/v-add-web-domain "$NUEVO" "$dom" >/dev/null 2>&1 \
    && echo "    web: $dom" \
    || echo "    AVISO: no se pudo crear el dominio web '$dom'"
done
for dom in $MAILDOMS; do
  [ -n "$dom" ] || continue
  $H/bin/v-add-mail-domain "$NUEVO" "$dom" >/dev/null 2>&1 \
    && echo "    correo: $dom" \
    || echo "    AVISO: no se pudo crear el dominio de correo '$dom'"
done

echo "[4/7] Colocando archivos en /home/$NUEVO ..."
# `mv` y no `cp`: es el mismo sistema de archivos, así que renombrar es
# instantáneo y NO ocupa el doble. Copiando, un usuario de 11 GB pedía 22 GB
# libres y llenaba el disco del servidor a mitad de faena.
for d in "$SRC"/* "$SRC"/.[!.]*; do
  [ -e "$d" ] || continue
  n="$(basename "$d")"
  case "$n" in
    backup) continue ;;                 # envoltorio del respaldo, no del usuario
    conf)   continue ;;                 # lo genera HestiaCP al reconstruir
    web|mail)
      # Su estructura ya la creó v-add-*-domain: se vuelca el contenido dentro
      for sub in "$d"/*; do
        [ -e "$sub" ] || continue
        dom="$(basename "$sub")"
        if [ -d "/home/$NUEVO/$n/$dom" ]; then
          for x in "$sub"/*; do
            [ -e "$x" ] || continue
            rm -rf "/home/$NUEVO/$n/$dom/$(basename "$x")"
            mv "$x" "/home/$NUEVO/$n/$dom/"
          done
        else
          mv "$sub" "/home/$NUEVO/$n/"
        fi
      done
      continue ;;
  esac
  rm -rf "/home/$NUEVO/$n"
  mv "$d" "/home/$NUEVO/$n"
done
# /home/<usuario>/conf pertenece a root por diseño: se excluye del chown para
# no llenar la salida de avisos que no son problemas.
find "/home/$NUEVO" -maxdepth 1 ! -name conf ! -path "/home/$NUEVO" \
  -exec chown -R "$NUEVO:$NUEVO" {} + 2>/dev/null || true

echo "[5/7] Colocando la configuración..."
UD="$H/data/users/$NUEVO"
if [ -f "$B/hestia/user.conf" ]; then
  cp "$B/hestia/user.conf" "$UD/user.conf.original"
  for k in PACKAGE WEB_TEMPLATE BACKEND_TEMPLATE PROXY_TEMPLATE DNS_TEMPLATE \
           WEB_DOMAINS WEB_ALIASES DNS_DOMAINS DNS_RECORDS MAIL_DOMAINS \
           MAIL_ACCOUNTS RATE_LIMIT DATABASES CRON_JOBS DISK_QUOTA BANDWIDTH \
           NS SHELL LANGUAGE; do
    v="$(grep -oP "^$k='\K[^']*" "$B/hestia/user.conf" 2>/dev/null || true)"
    [ -n "$v" ] && $H/bin/v-change-user-config-value "$NUEVO" "$k" "$v" >/dev/null 2>&1
  done
fi
[ -d "$B/hestia/ssl" ] && cp -a "$B/hestia/ssl" "$UD/" 2>/dev/null || true

# Dentro del respaldo, cada objeto guarda DOS .conf con papeles distintos:
#   <tipo>/<obj>/hestia/<tipo>.conf   su LÍNEA para la lista del usuario
#   <tipo>/<obj>/hestia/<obj>.conf    su CONTENIDO (registros DNS, alias web)
# El web y el correo ya se crearon arriba; aquí se recupera lo que el respaldo
# sí traiga, que es más fiel que lo reconstruido.
for tipo in dns web mail; do
  [ -d "$B/$tipo" ] || continue
  : > "$UD/$tipo.conf.nuevo"
  mkdir -p "$UD/$tipo"
  for obj in "$B/$tipo"/*/; do
    [ -d "$obj" ] || continue
    n="$(basename "$obj")"
    [ -f "$obj/hestia/$tipo.conf" ] && cat "$obj/hestia/$tipo.conf" >> "$UD/$tipo.conf.nuevo"
    [ -f "$obj/hestia/$n.conf" ]    && cp  "$obj/hestia/$n.conf" "$UD/$tipo/$n.conf"
  done
  if [ -s "$UD/$tipo.conf.nuevo" ]; then mv "$UD/$tipo.conf.nuevo" "$UD/$tipo.conf"
  else rm -f "$UD/$tipo.conf.nuevo"; fi
done
[ -f "$B/cron/cron.conf" ] && cp "$B/cron/cron.conf" "$UD/cron.conf"
chown -R "$NUEVO:$NUEVO" "$UD" 2>/dev/null || true

echo "[6/7] Bases de datos..."
FALLO_DB=0
if [ -n "${DB:-}" ]; then
  IFS=',' read -ra BASES <<< "$DB"
  for b in "${BASES[@]}"; do
    [ -n "$b" ] || continue
    dconf="$B/db/$b/hestia/db.conf"
    dump="$(ls "$B/db/$b/"*.sql.zst "$B/db/$b/"*.sql.gz "$B/db/$b/"*.sql 2>/dev/null | head -1)"

    # -----------------------------------------------------------------------
    # Se CONSERVAN el nombre de la base, su usuario y su contraseña.
    # -----------------------------------------------------------------------
    # Lo que se renombra es la CUENTA, no sus bases. Las aplicaciones del
    # cliente —wp-config.php, .env, configuration.php— tienen escritos el
    # nombre de la base, el usuario y la contraseña. Si cambia cualquiera de
    # los tres, el sitio pierde la conexión a sus datos aunque todo esté en su
    # sitio.
    #
    # La versión anterior creaba <nuevo>_<sufijo> con una contraseña al azar:
    # el panel se veía perfecto y todos los sitios con base de datos quedaban
    # caídos. Ahora se recrea el usuario con el MISMO hash que guarda el
    # respaldo (*<40 hex>, mysql_native_password), así que la contraseña que
    # tienen escrita las aplicaciones sigue valiendo sin que nadie la conozca.
    #
    # v-add-database no sirve para esto: obliga a llamar a la base
    # <cuenta>_<sufijo> y genera la contraseña. Se hace lo mismo que hace él
    # por dentro —crear, dar permisos, apuntar en db.conf— sin esas dos cosas.
    dbuser_viejo="$(grep -oP "DBUSER='\\K[^']*" "$dconf" 2>/dev/null || echo "$b")"
    hash="$(grep -oP "MD5='\\K[^']*" "$dconf" 2>/dev/null || true)"
    charset="$(grep -oP "CHARSET='\\K[^']*" "$dconf" 2>/dev/null || echo utf8mb4)"
    nueva="$b"

    # Nada se escribe encima: si el nombre ya está ocupado en el destino, esa
    # base se salta y se dice. Pisarla destruiría la de otro cliente.
    if [ -n "$(mysql -N -e "SELECT 1 FROM information_schema.schemata WHERE schema_name='$b'" 2>/dev/null)" ]; then
      echo "    AVISO: la base '$b' YA EXISTE en el destino. No se toca."
      echo "           Tráela con otro nombre desde el zip:  adoptar-bases --bases $b --prefijo <algo>_"
      echo "           y cambia el nombre en la configuración de su aplicación."
      FALLO_DB=1; continue
    fi
    if [ -n "$(mysql -N -e "SELECT 1 FROM mysql.user WHERE user='$dbuser_viejo'" 2>/dev/null)" ]; then
      echo "    AVISO: el usuario MySQL '$dbuser_viejo' YA EXISTE en el destino. '$b' no se toca."
      FALLO_DB=1; continue
    fi

    echo "    $b  (usuario $dbuser_viejo, $charset)"
    mysql -e "CREATE DATABASE \`$b\` CHARACTER SET $(printf '%s' "$charset" | tr '[:upper:]' '[:lower:]')" \
      || { echo "    AVISO: no se pudo crear '$b'"; FALLO_DB=1; continue; }

    creado=0
    if [ "${hash:0:1}" = "*" ] && [ ${#hash} -eq 41 ]; then
      # Sintaxis de MariaDB primero, de MySQL 8 después: la que acepte el servidor.
      mysql -e "CREATE USER '$dbuser_viejo'@'localhost' IDENTIFIED BY PASSWORD '$hash'" 2>/dev/null && creado=1
      [ $creado -eq 0 ] && mysql -e "CREATE USER '$dbuser_viejo'@'localhost' IDENTIFIED WITH mysql_native_password AS '$hash'" 2>/dev/null && creado=1
      [ $creado -eq 1 ] && echo "    contraseña original conservada"
    fi
    if [ $creado -eq 0 ]; then
      # Sin hash utilizable no hay forma de conservarla: se genera una y se
      # dice, porque la aplicación dejará de conectar hasta que se cambie.
      nuevapass="$(head -c 200 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20)"
      mysql -e "CREATE USER '$dbuser_viejo'@'localhost' IDENTIFIED BY '$nuevapass'" \
        || { echo "    AVISO: no se pudo crear el usuario '$dbuser_viejo'"; FALLO_DB=1; continue; }
      hash="$(mysql -N -e "SHOW CREATE USER '$dbuser_viejo'@'localhost'" 2>/dev/null | grep -oP '\*[A-F0-9]{40}' | head -1)"
      echo "    AVISO: el respaldo no traía un hash utilizable. Contraseña NUEVA para '$dbuser_viejo': $nuevapass"
      echo "           Ponla en la configuración de la aplicación o el sitio no conectará."
    fi
    mysql -e "GRANT ALL PRIVILEGES ON \`$b\`.* TO '$dbuser_viejo'@'localhost'; FLUSH PRIVILEGES"

    t="$(date +'%T')"; d="$(date +'%F')"
    printf "DB='%s' DBUSER='%s' MD5='%s' HOST='localhost' TYPE='mysql' CHARSET='%s' U_DISK='0' SUSPENDED='no' TIME='%s' DATE='%s'\n" \
      "$b" "$dbuser_viejo" "$hash" "$(printf '%s' "$charset" | tr '[:lower:]' '[:upper:]')" "$t" "$d" >> "$UD/db.conf"
    chmod 660 "$UD/db.conf"
    if [ -n "$dump" ]; then
      # El USE apunta a la base ORIGINAL: sin quitarlo, el volcado entero se
      # aplicaría allí. Y el DEFINER de vistas y rutinas apunta al usuario
      # MySQL del servidor viejo, que aquí no existe: MySQL corta con
      # «ERROR 1449 ... definer does not exist».
      case "$dump" in
        *.zst) zstd -dc "$dump" ;;
        *.gz)  gzip -dc "$dump" ;;
        *)     cat "$dump" ;;
      esac | sed -E \
              -e 's/^USE `[^`]*`;$//' \
              -e 's/DEFINER=`[^`]*`@`[^`]*`[[:space:]]*//g' \
              -e "s/DEFINER='[^']*'@'[^']*'[[:space:]]*//g" \
              -e 's#/\*![0-9]{5} DEFINER=[^*]*\*/##g' \
              -e 's/SQL SECURITY DEFINER/SQL SECURITY INVOKER/g' \
           | mysql "$nueva" \
        && echo "    datos importados en '$nueva'" \
        || { echo "    AVISO: fallo importando en '$nueva'"; FALLO_DB=1; }
      n_tablas="$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$nueva'" 2>/dev/null || echo 0)"
      echo "    '$nueva' tiene $n_tablas tablas"
      [ "${n_tablas:-0}" -eq 0 ] && { echo "    AVISO: '$nueva' quedó VACÍA"; FALLO_DB=1; }
    fi
  done
fi

echo "[7/7] Reconstruyendo la cuenta..."
$H/bin/v-rebuild-user "$NUEVO" yes || echo "AVISO: v-rebuild-user devolvió error"
$H/bin/v-rebuild-web-domains "$NUEVO" yes >/dev/null 2>&1 || true
$H/bin/v-rebuild-dns-domains "$NUEVO" yes >/dev/null 2>&1 || true
$H/bin/v-update-user-counters "$NUEVO" >/dev/null 2>&1 || true
$H/bin/v-update-user-disk "$NUEVO" >/dev/null 2>&1 || true
echo "  web:   $($H/bin/v-list-web-domains "$NUEVO" plain 2>/dev/null | wc -l)"
echo "  dns:   $($H/bin/v-list-dns-domains "$NUEVO" plain 2>/dev/null | wc -l)"
echo "  correo:$($H/bin/v-list-mail-domains "$NUEVO" plain 2>/dev/null | wc -l)"
echo "  bases: $($H/bin/v-list-databases "$NUEVO" plain 2>/dev/null | wc -l)"
# Marca en disco, no solo en pantalla: es lo que comprueba quien llama.
# Si alguna base falló, NO se marca: un usuario sin sus datos no es un éxito.
# La marca solo si además están todas las bases que anunciaba el respaldo: un
# usuario sin sus datos no es un traslado correcto, y al borrar sin querer este
# bloque la orden llegó a informar de un éxito con CERO bases restauradas.
ESPERADAS=$( { echo "${DB:-}" | tr ',' '\n' | grep -c . ; } || echo 0)
LOGRADAS=$($H/bin/v-list-databases "$NUEVO" plain 2>/dev/null | grep -c . || echo 0)
if [ "$ESPERADAS" -gt 0 ] && [ "$LOGRADAS" -lt "$ESPERADAS" ]; then
  echo "AVISO: el respaldo tenía $ESPERADAS base(s) y solo hay $LOGRADAS."
  FALLO_DB=1
fi
[ "${FALLO_DB:-0}" -eq 0 ] && touch "$WS/LISTO"
echo "LISTO"
REMOTO

  echo
  # El código de salida no basta: una tubería vacía también sale con cero. Se
  # exige la marca que solo escribe el script tras completar los seis pasos.
  if (( rc_final == 0 )) && ! bc_ssh_sudo "test -f '$ws/LISTO'" < /dev/null 2>/dev/null; then
    bc_err "El script del destino no llegó al final: no se hizo el traslado."
    rc_final=1
  fi
  if (( rc_final != 0 )); then
    bc_err "El traslado terminó con errores. La cuenta '$nuevo' puede haber quedado a medias."
    bc_log "Revísala en el panel, o elimínala con: v-delete-user $nuevo"
    BC_DELIBERATE_EXIT=1
    return 1
  fi
  bc_ok "'$viejo' está en $destino como '$nuevo'."
  bc_warn "Contraseña del panel para '$nuevo': $contrasena"
  bc_log  "Apúntala ahora: no se guarda en ninguna parte."
  bc_log  "Comprueba dominios, correo y bases en el panel antes de dar por buena la migración."
  return 0
}

# =============================================================================
# La instantánea más reciente NO siempre es la que quieres
# =============================================================================
# Comprobado en el servidor de pruebas, y por poco no se ve:
#
#   53b3d6c5  2026-09-08   web:1   correo:0   bases:14   <- la más reciente
#   2dd24c3a  2026-09-07   web:23  correo:6   bases:14
#   4c7261e4  2026-09-06   web:23  correo:6   bases:14
#
# Se habían borrado los dominios el día 8, y el respaldo de esa madrugada
# recogió fielmente el servidor ya vaciado. Restaurar con «latest» habría
# devuelto UN dominio de 23 y ningún buzón, sin un solo aviso: para la
# herramienta, un respaldo correcto de un servidor vacío es indistinguible de
# un respaldo correcto de un servidor lleno.
#
# Por eso se compara siempre con las anteriores. Un descenso brusco no es
# necesariamente un error —a veces se borra a propósito— pero tiene que
# saltar a la vista ANTES de restaurar, no después.
# =============================================================================

# Prepara un directorio temporal con el acceso y la clave de un usuario.
# Deja en BC_AD_TMP la ruta; quien llama se encarga de borrarla.
BC_AD_TMP=""
bc_ad_preparar() {
  local usuario="$1" claves="$2" rc="$3"
  BC_AD_TMP="$(mktemp -d)"; chmod 700 "$BC_AD_TMP"
  cp "$rc" "$BC_AD_TMP/rclone.conf"; chmod 600 "$BC_AD_TMP/rclone.conf"
  local k; k="$(awk -F'\t' -v u="$usuario" '$1==u{print $2; exit}' <<<"$claves")"
  [[ -n "$k" ]] || return 1
  printf '%s' "$k" > "$BC_AD_TMP/clave"; chmod 600 "$BC_AD_TMP/clave"
}

# Qué contiene una instantánea, según el backup.conf que HestiaCP guarda dentro.
# Salida: fecha<TAB>nweb<TAB>ndns<TAB>ncorreo<TAB>nbases
bc_ad_contenido() {
  local repo="$1" u="$2" snap="$3"
  local c
  c="$(RCLONE_CONFIG="$BC_AD_TMP/rclone.conf" RESTIC_PASSWORD_FILE="$BC_AD_TMP/clave" \
       restic -r "${repo%/}/$u" dump "$snap" "/home/$u/backup/backup.conf" 2>/dev/null || true)"
  [[ -n "$c" ]] || { printf '?\t?\t?\t?\t?\n'; return 0; }
  local campo valor
  local -a n=()
  for campo in WEB DNS MAIL DB; do
    valor="$(tr ' ' '\n' <<<"$c" | grep "^$campo=" | cut -d\' -f2)"
    n+=("$( { tr ',' '\n' <<<"$valor" | grep -c . || true; } )")
  done
  local fecha; fecha="$(tr ' ' '\n' <<<"$c" | grep '^DATE=' | cut -d\' -f2)"
  printf '%s\t%s\t%s\t%s\t%s\n' "${fecha:-?}" "${n[0]}" "${n[1]}" "${n[2]}" "${n[3]}"
}

# Historial de un usuario: qué había en cada una de las últimas instantáneas.
bc_adoptar_historial() {
  local usuario="${BC_OPT_USERS:-}"
  local cuantas="${BC_OPT_CUANTAS:-8}"

  local claves; claves="$(bc_ad_leer_claves)" || return 1
  BC_AD_REPO="$(bc_ad_repo_rescatado || true)"
  [[ -n "$BC_AD_REPO" ]] || { bc_err "el rescate no dice cuál es el repositorio."; return 1; }
  local rc; rc="$(bc_ad_rclone_rescatado)"
  [[ -n "$rc" ]] || { bc_err "no hay rclone.conf rescatado."; return 1; }
  bc_require_cmd restic rclone

  local -a usuarios=()
  if [[ -n "$usuario" ]]; then
    local u
    for u in ${usuario//,/ }; do usuarios+=("$u"); done
  else
    mapfile -t usuarios < <(cut -f1 <<<"$claves")
  fi

  local u
  for u in "${usuarios[@]}"; do
    bc_section "Historial de '$u'"
    bc_ad_preparar "$u" "$claves" "$rc" || { bc_err "no hay clave de '$u'."; continue; }
    # shellcheck disable=SC2064
    trap "rm -rf '$BC_AD_TMP'" RETURN

    local ids
    ids="$(RCLONE_CONFIG="$BC_AD_TMP/rclone.conf" RESTIC_PASSWORD_FILE="$BC_AD_TMP/clave" \
           restic -r "${BC_AD_REPO%/}/$u" snapshots --json 2>/dev/null \
           | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d[-int('$cuantas'):][::-1]: print(s['short_id'])
" 2>/dev/null || true)"
    if [[ -z "$ids" ]]; then
      bc_err "no se pudo abrir el repositorio de '$u'."
      rm -rf "$BC_AD_TMP"; continue
    fi

    local filas; filas="$(mktemp)"
    local id linea
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      linea="$(bc_ad_contenido "$BC_AD_REPO" "$u" "$id")"
      printf '%s\t%s\n' "$id" "$linea" >> "$filas"
    done <<<"$ids"

    {
      printf 'INSTANTÁNEA\tFECHA\tWEB\tDNS\tCORREO\tBASES\n'
      cat "$filas"
    } | bc_table | sed 's/^/        /'

    # ¿La más reciente tiene menos que alguna anterior?
    local top_w top_m top_d act_w act_m act_d
    act_w="$(head -1 "$filas" | cut -f3)"; act_m="$(head -1 "$filas" | cut -f5)"; act_d="$(head -1 "$filas" | cut -f6)"
    top_w="$( { cut -f3 "$filas" | grep -E '^[0-9]+$' || true; } | sort -n | tail -1)"
    top_m="$( { cut -f5 "$filas" | grep -E '^[0-9]+$' || true; } | sort -n | tail -1)"
    top_d="$( { cut -f6 "$filas" | grep -E '^[0-9]+$' || true; } | sort -n | tail -1)"
    local mejor; mejor="$(awk -F'\t' -v w="$top_w" '$3==w {print $1"  ("$2")"; exit}' "$filas")"

    echo
    if [[ "$act_w" =~ ^[0-9]+$ ]] && { (( act_w < top_w )) || (( act_m < top_m )) || (( act_d < top_d )); }; then
      bc_err "LA MÁS RECIENTE TIENE MENOS QUE UNA ANTERIOR."
      bc_log "        ahora: web $act_w · correo $act_m · bases $act_d"
      bc_log "        antes: web $top_w · correo $top_m · bases $top_d"
      bc_log "        Si se borró algo a propósito, todo en orden. Si no, restaura desde:"
      bc_log "            --snapshot $mejor"
      BC_DELIBERATE_EXIT=1
    else
      bc_ok "La más reciente es la más completa: se puede usar «latest» con confianza."
    fi
    rm -rf "$BC_AD_TMP"; BC_AD_TMP=""
  done
  return 0
}

# =============================================================================
# Que las bases que HestiaCP no conoce dejen de ser invisibles
# =============================================================================
# En el servidor de pruebas, HestiaCP conocía 14 bases de 80. Las otras 66 se
# habían creado a mano en MySQL. `adoptar-bases` las lleva a otro servidor con
# sus datos intactos... y allí siguen siendo invisibles: no salen en el panel,
# no se respaldan con la cuenta, y nadie se acuerda de ellas.
#
# Registrarlas es reproducir lo que hace v-add-database SIN volver a crear la
# base: un usuario MySQL con permisos, y una línea en data/users/<u>/db.conf.
# El campo MD5 no se calcula: HestiaCP lo LEE del propio MySQL con
# SHOW CREATE USER, así que aquí se hace igual.
#
# v-add-database no sirve para esto: crea la base (y falla si existe) y además
# obliga a llamarla <usuario>_<sufijo>. Una base que ya se llama 'augustoangel'
# no puede adoptarse por esa vía sin renombrarla, y renombrarla rompería la
# aplicación que la usa.
# =============================================================================

bc_adoptar_registrar() {
  local destino="${BC_OPT_TO:-}"
  local uh="${BC_OPT_HESTIA_USER:-}"
  local pedidas="${BC_OPT_DBS:-}"
  local seco="${BC_OPT_DRY:-0}"

  [[ -n "$destino" ]] || bc_die "indica el servidor: --to root@servidor"
  [[ -n "$uh"      ]] || bc_die "indica bajo qué cuenta de HestiaCP registrarlas: --usuario-hestia <cuenta>"

  bc_section "Registrar en el panel las bases que HestiaCP no conoce"
  bc_log "No se crea ni se borra ninguna base: solo se hacen visibles y"
  bc_log "administrables desde el panel, bajo la cuenta '$uh'."

  bc_require_cmd ssh
  bc_ssh_init "$destino" || bc_die "no se pudo conectar a $destino."
  trap 'bc_ssh_close' RETURN
  bc_ssh_sudo "test -d /usr/local/hestia/data/users/$uh" >/dev/null 2>&1 \
    || bc_die "en $destino no existe la cuenta de HestiaCP '$uh'."

  local desconocidas
  desconocidas="$(bc_ssh_sudo "bash -s '$uh'" < /dev/null <<'REMOTO' 2>/dev/null || true
H=/usr/local/hestia
conocidas="$(cat $H/data/users/*/db.conf 2>/dev/null | grep -oP "^DB='\K[^']+" | sort -u)"
# roundcube es la base del webmail y phpmyadmin la del gestor: son del
# sistema, no de ningún cliente. Registrarlas bajo una cuenta las pondría a
# merced de quien administre esa cuenta.
mysql -N -e "SELECT schema_name FROM information_schema.schemata
             WHERE schema_name NOT IN ('information_schema','performance_schema',
                                       'mysql','sys','phpmyadmin','roundcube','test')" \
  | while IFS= read -r b; do
      [ -n "$b" ] || continue
      grep -qx "$b" <<< "$conocidas" || echo "$b"
    done
REMOTO
)"
  desconocidas="$(sed '/^$/d' <<<"$desconocidas")"

  if [[ -z "$desconocidas" ]]; then
    bc_ok "No hay ninguna base fuera del panel: todo lo que hay en MySQL ya se conoce."
    return 0
  fi

  local -a lista=()
  if [[ -n "$pedidas" ]]; then
    local b
    for b in ${pedidas//,/ }; do
      grep -qx "$b" <<<"$desconocidas" || bc_die "'$b' no está entre las desconocidas, o no existe."
      lista+=("$b")
    done
  else
    mapfile -t lista <<<"$desconocidas"
  fi

  bc_warn "$(grep -c . <<<"$desconocidas") base(s) existen en MySQL y el panel no las ve."
  bc_log "Se registrarán ${#lista[@]}:"
  printf '        - %s\n' "${lista[@]}"

  if (( seco )); then
    echo
    bc_ok "Simulación (--dry-run): no se ha registrado nada."
    return 0
  fi
  bc_confirm "¿Registrarlas bajo la cuenta '$uh'?" n || { bc_log "Cancelado."; return 0; }

  # La lista va como ARGUMENTOS y el script por la entrada estándar: `bash -s`
  # lee el script de ahí, así que meter la lista por el mismo sitio se la
  # comería. Es el mismo error que ya me costó un traslado en falso.
  local args; args="$(printf '%q ' "${lista[@]}")"
  bc_ssh_sudo_stdin "bash -s '$uh' $args" <<'REMOTO' 2>&1 | sed 's/^/        /'
set -uo pipefail
UH="$1"; shift
H=/usr/local/hestia
UD="$H/data/users/$UH"

for b in "$@"; do
  [ -n "$b" ] || continue

  # El usuario MySQL no puede pasar de 32 caracteres. Si el nombre de la base
  # ya los ocupa, se recorta y se avisa: mejor un nombre feo que ninguna base.
  dbuser="$b"
  if [ ${#dbuser} -gt 32 ]; then
    dbuser="$(printf '%s' "$b" | cut -c1-26)_$(printf '%s' "$b" | md5sum | cut -c1-5)"
    echo "$b: el usuario MySQL se acorta a '$dbuser' (el nombre pasaba de 32)"
  fi

  if grep -q "^DB='$b' " "$UD/db.conf" 2>/dev/null; then
    echo "$b: ya estaba registrado, no se toca"
    continue
  fi

  pass="$(head -c 200 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20)"
  mysql -e "CREATE USER IF NOT EXISTS \`$dbuser\`@'localhost' IDENTIFIED BY '$pass'" 2>/dev/null     || { echo "$b: no se pudo crear el usuario MySQL '$dbuser'"; continue; }
  mysql -e "GRANT ALL PRIVILEGES ON \`$b\`.* TO \`$dbuser\`@'localhost'" 2>/dev/null     || { echo "$b: no se pudieron dar permisos a '$dbuser'"; continue; }
  mysql -e "FLUSH PRIVILEGES" 2>/dev/null || true

  # HestiaCP no calcula este hash: lo LEE del propio MySQL. Se hace igual, y
  # se acepta cualquiera de los formatos que devuelve MySQL o MariaDB.
  crea="$(mysql -N -e "SHOW CREATE USER \`$dbuser\`@'localhost'" 2>/dev/null || true)"
  md5="$(grep -oP "(?<=AS ')[^']+" <<< "$crea" | head -1)"
  [ -n "$md5" ] || md5="$(grep -oP '\*[A-F0-9]{40}' <<< "$crea" | head -1)"
  [ -n "$md5" ] || md5=""

  charset="$(mysql -N -e "SELECT default_character_set_name FROM information_schema.schemata WHERE schema_name='$b'" 2>/dev/null || echo utf8mb4)"
  t="$(date +'%T')"; d="$(date +'%F')"
  printf "DB='%s' DBUSER='%s' MD5='%s' HOST='localhost' TYPE='mysql' CHARSET='%s' U_DISK='0' SUSPENDED='no' TIME='%s' DATE='%s'\n"     "$b" "$dbuser" "$md5" "$(printf '%s' "$charset" | tr '[:lower:]' '[:upper:]')" "$t" "$d" >> "$UD/db.conf"
  chmod 660 "$UD/db.conf"
  n="$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$b'" 2>/dev/null || echo '?')"
  echo "$b: registrado (usuario $dbuser, $n tablas)"
done
chown "$UH:$UH" "$UD/db.conf" 2>/dev/null || true
REMOTO

  bc_ssh_sudo "/usr/local/hestia/bin/v-update-user-counters '$uh'" < /dev/null >/dev/null 2>&1 || true
  local n
  n="$(bc_ssh_sudo "/usr/local/hestia/bin/v-list-databases '$uh' plain" < /dev/null 2>/dev/null | grep -c . || true)"
  echo
  bc_ok "La cuenta '$uh' tiene ahora $n base(s) visibles en el panel."
  bc_log "Cada una con su propio usuario MySQL. Las contraseñas se pueden cambiar"
  bc_log "desde el panel; las aplicaciones que ya usaban esas bases siguen con sus"
  bc_log "credenciales de siempre, que no se han tocado."
  return 0
}
