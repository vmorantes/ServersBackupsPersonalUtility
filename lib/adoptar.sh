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
bc_ad_leer_claves() {
  local dir; dir="$(bc_hestia_salida)"
  local archivo
  archivo="$( { find "$dir" -maxdepth 1 -name 'Restic_Configs_*.txt' -printf '%T@ %p\n' 2>/dev/null || true; } \
              | sort -rn | head -1 | cut -d' ' -f2- )"
  [[ -n "$archivo" ]] || { bc_err "no hay ninguna clave rescatada en $dir."; return 1; }
  bc_log "Claves rescatadas: $archivo ($(bc_age_days "$archivo") días)" >&2

  awk '
    /^# [A-Za-z0-9._-]+:$/ { u = substr($2, 1, length($2)-1); next }
    /^=+$/                 { u = ""; next }
    /^#/                   { next }
    NF == 0                { next }
    u != "" && $0 !~ /=/    { print u "\t" $0; u = "" }
  ' "$archivo"
}

# El repositorio se lee aparte y NO dentro de bc_ad_leer_claves: esa función se
# invoca como "$(...)", o sea en una subshell, y cualquier variable que asignara
# allí se perdería al volver. Ya me pasó con los contadores de verify.
bc_ad_repo_rescatado() {
  local dir; dir="$(bc_hestia_salida)"
  local archivo
  archivo="$( { find "$dir" -maxdepth 1 -name 'Restic_Configs_*.txt' -printf '%T@ %p\n' 2>/dev/null || true; } \
              | sort -rn | head -1 | cut -d' ' -f2- )"
  [[ -n "$archivo" ]] || return 1
  sed -n "s/^REPO='\(.*\)'$/\1/p" "$archivo" | head -1
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
  while IFS=$'\t' read -r u k; do
    [[ -n "$u" && -n "$k" ]] || continue
    printf '%s' "$k" > "$tmp/clave"; chmod 600 "$tmp/clave"
    local salida
    salida="$(RCLONE_CONFIG="$tmp/rclone.conf" RESTIC_PASSWORD_FILE="$tmp/clave" \
              restic -r "${BC_AD_REPO%/}/$u" snapshots --json 2>/dev/null || true)"
    if [[ -z "$salida" || "$salida" == "null" ]]; then
      printf '%s\tNO SE PUDO ABRIR\t-\t-\n' "$u" >> "$filas"
      continue
    fi
    n="$(python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' <<<"$salida" 2>/dev/null || echo 0)"
    ultima="$(python3 -c 'import json,sys;d=json.load(sys.stdin);print(d[-1]["time"][:19].replace("T"," ")+"  "+d[-1]["short_id"]) if d else print("-")' <<<"$salida" 2>/dev/null || echo '-')"
    printf '%s\tsí\t%s\t%s\n' "$u" "$n" "$ultima" >> "$filas"
  done <<<"$claves"

  {
    printf 'USUARIO\tDESCIFRA\tINSTANTÁNEAS\tLA MÁS RECIENTE\n'
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
  bc_ssh_sudo "command -v restic >/dev/null" >/dev/null 2>&1 \
    && bc_ok "restic presente" \
    || bc_log "restic no está: HestiaCP lo instalará solo la primera vez que haga falta."

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
    k="$(awk -F'\t' -v u="$u" '$1==u{print $2}' <<<"$claves")"
    snap="${BC_OPT_SNAPSHOT:-latest}"
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
