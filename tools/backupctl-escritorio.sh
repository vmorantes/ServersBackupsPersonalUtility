#!/usr/bin/env bash
# =============================================================================
# backupctl-escritorio.sh — la interfaz web como una aplicación del escritorio
# =============================================================================
# Integra backupctl en el menú de aplicaciones. Al abrirla arranca el servidor
# local y abre una ventana propia; al cerrar esa ventana, el servidor se apaga.
# No queda nada escuchando cuando no la estás usando.
#
#   ./tools/backupctl-escritorio.sh instalar      crea el lanzador y el icono
#   ./tools/backupctl-escritorio.sh desinstalar   lo quita todo
#   ./tools/backupctl-escritorio.sh estado        ¿instalada? ¿corriendo?
#   ./tools/backupctl-escritorio.sh lanzar        lo que ejecuta el lanzador
#
# CÓMO SE APAGA AL CERRAR
#   La ventana se abre en modo aplicación con un perfil de navegador propio.
#   Eso es lo que garantiza un proceso NUEVO al que esperar: sin perfil propio,
#   Chrome reutiliza la instancia que ya tengas abierta y el proceso lanzado
#   termina de inmediato, con lo que no habría nada que esperar y el servidor se
#   quedaría encendido para siempre.
# =============================================================================

set -Eeuo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUPCTL="$RAIZ/bin/backupctl"

APP_ID="backupctl"
DESKTOP="$HOME/.local/share/applications/$APP_ID.desktop"
ICONO="$HOME/.local/share/icons/hicolor/scalable/apps/$APP_ID.svg"
PERFIL="$HOME/.local/share/backupctl/navegador"
ESTADO_DIR="${XDG_RUNTIME_DIR:-/tmp}/backupctl-escritorio"

# PID del servidor. Global a propósito: el trap de salida se ejecuta cuando
# lanzar() ya ha retornado, y una variable local habría dejado de existir. Con
# `set -u` el trap fallaría y el servidor quedaría encendido — exactamente lo
# que esta utilidad existe para evitar.
BC_SRV_PID=""
BC_NAV_PID=""

rojo=$'\033[31m'; verde=$'\033[32m'; ama=$'\033[33m'; neg=$'\033[0m'; bold=$'\033[1m'
ok()   { printf '  %s✓%s %s\n' "$verde" "$neg" "$*"; }
avi()  { printf '  %s!%s %s\n' "$ama" "$neg" "$*"; }
err()  { printf '  %s✗%s %s\n' "$rojo" "$neg" "$*" >&2; }
tit()  { printf '\n%s%s%s\n' "$bold" "$*" "$neg"; }
morir(){ err "$*"; exit 1; }

# -----------------------------------------------------------------------------
# Navegador
# -----------------------------------------------------------------------------
# Se prefieren los de la familia Chromium porque admiten --app, que abre una
# ventana sin barra de direcciones ni pestañas: parece una aplicación y no una
# página. Firefox no tiene equivalente utilizable aquí.
navegador_app() {
  local b
  for b in google-chrome google-chrome-stable chromium chromium-browser \
           brave-browser microsoft-edge vivaldi-stable; do
    command -v "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return 0; }
  done
  return 1
}

# =============================================================================
# instalar
# =============================================================================
instalar() {
  tit "Instalando backupctl en el escritorio"

  [[ -x "$BACKUPCTL" ]] || morir "no encuentro $BACKUPCTL"
  command -v python3 >/dev/null || morir "hace falta python3"

  mkdir -p "$(dirname "$DESKTOP")" "$(dirname "$ICONO")" "$PERFIL"

  # --- Icono ---------------------------------------------------------------
  cat > "$ICONO" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#14b8a6"/><stop offset="1" stop-color="#0f766e"/>
  </linearGradient></defs>
  <rect x="4" y="4" width="56" height="56" rx="13" fill="url(#g)"/>
  <g fill="none" stroke="#ffffff" stroke-width="3.2" stroke-linecap="round">
    <ellipse cx="32" cy="20" rx="14" ry="5.5"/>
    <path d="M18 20v11c0 3 6.3 5.5 14 5.5s14-2.5 14-5.5V20"/>
    <path d="M18 31v11c0 3 6.3 5.5 14 5.5"/>
  </g>
  <circle cx="44" cy="44" r="10.5" fill="#0f766e" stroke="#ffffff" stroke-width="2.6"/>
  <path d="M39.5 44l3.2 3.2 6-6.4" fill="none" stroke="#ffffff"
        stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
SVG
  ok "icono: $ICONO"

  # --- Entrada del menú ----------------------------------------------------
  cat > "$DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Version=1.0
Name=Respaldos HestiaCP
GenericName=Respaldos de servidores
Comment=Respaldo, verificación y migración de tus servidores HestiaCP
Exec=$RAIZ/tools/backupctl-escritorio.sh lanzar
Icon=$APP_ID
Terminal=false
Categories=System;Utility;Archiving;
Keywords=respaldo;backup;hestia;mysql;restic;servidor;
StartupNotify=true
SingleMainWindow=true
DESK
  chmod +x "$DESKTOP"
  ok "lanzador: $DESKTOP"

  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 \
    && gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

  tit "Listo"
  echo "  Búscala en el menú como «backupctl»."
  echo "  Al abrirla arranca el servidor; al cerrar la ventana, se apaga."
  echo
  echo "  Para quitarla:  $0 desinstalar"
}

# =============================================================================
# desinstalar
# =============================================================================
desinstalar() {
  tit "Quitando backupctl del escritorio"

  # Si está abierta, primero se cierra: dejar el servidor huérfano sería peor
  # que no desinstalar nada.
  if [[ -f "$ESTADO_DIR/servidor.pid" ]]; then
    local pid; pid="$(cat "$ESTADO_DIR/servidor.pid" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      avi "se ha detenido el servidor que estaba corriendo (PID $pid)"
    fi
  fi

  local algo=0
  [[ -f "$DESKTOP" ]] && { rm -f "$DESKTOP"; ok "lanzador eliminado"; algo=1; }
  [[ -f "$ICONO"   ]] && { rm -f "$ICONO";   ok "icono eliminado";    algo=1; }
  rm -rf "$ESTADO_DIR"

  if [[ -d "$PERFIL" ]]; then
    echo
    echo "  Queda el perfil de navegador de la aplicación:"
    echo "    $PERFIL   ($(du -sh "$PERFIL" 2>/dev/null | cut -f1))"
    read -r -p "  ¿Eliminarlo también? [s/N] " r
    [[ "$r" =~ ^[sSyY]$ ]] && { rm -rf "$PERFIL"; ok "perfil eliminado"; }
  fi

  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true

  (( algo )) || avi "no estaba instalada."
  echo
  echo "  Nada del repositorio ni de tus servidores se ha tocado."
}

# =============================================================================
# estado
# =============================================================================
estado() {
  tit "Estado"
  if [[ -f "$DESKTOP" ]]; then ok "instalada en el menú"; else avi "no instalada"; fi

  local pid=""
  [[ -f "$ESTADO_DIR/servidor.pid" ]] && pid="$(cat "$ESTADO_DIR/servidor.pid" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    ok "servidor corriendo (PID $pid)"
    [[ -f "$ESTADO_DIR/url" ]] && echo "    $(cat "$ESTADO_DIR/url")"
  else
    ok "sin servidor corriendo"
  fi

  local nav
  if nav="$(navegador_app)"; then ok "ventana propia con: $nav"
  else avi "sin navegador tipo Chromium: se abrirá en el navegador por defecto"; fi
}

# =============================================================================
# lanzar — lo que ejecuta el icono del menú
# =============================================================================
lanzar() {
  mkdir -p "$ESTADO_DIR"

  # Si ya hay una instancia viva, no se levanta otra: se reabre su ventana.
  if [[ -f "$ESTADO_DIR/servidor.pid" ]]; then
    local viejo; viejo="$(cat "$ESTADO_DIR/servidor.pid" 2>/dev/null || true)"
    if [[ -n "$viejo" ]] && kill -0 "$viejo" 2>/dev/null && [[ -f "$ESTADO_DIR/url" ]]; then
      abrir_ventana "$(cat "$ESTADO_DIR/url")"
      return 0
    fi
    rm -f "$ESTADO_DIR/servidor.pid" "$ESTADO_DIR/url"
  fi

  # --- Puerto libre --------------------------------------------------------
  local puerto=8787
  while (( puerto < 8820 )) && python3 -c "
import socket,sys
s=socket.socket()
try: s.bind(('127.0.0.1',$puerto)); sys.exit(1)
except OSError: sys.exit(0)
finally: s.close()" 2>/dev/null; do
    puerto=$(( puerto + 1 ))
  done

  local salida="$ESTADO_DIR/servidor.log"
  : > "$salida"

  "$BACKUPCTL" web --port "$puerto" > "$salida" 2>&1 &
  BC_SRV_PID=$!
  echo "$BC_SRV_PID" > "$ESTADO_DIR/servidor.pid"

  # Al salir de este script, por la vía que sea, el servidor se va con él
  trap apagar EXIT INT TERM

  # --- Esperar a que esté listo -------------------------------------------
  local url="" i
  for i in $(seq 1 60); do
    url="$(grep -oP 'http://127\.0\.0\.1:[0-9]+/\?t=[A-Za-z0-9_-]+' "$salida" 2>/dev/null | head -1 || true)"
    [[ -n "$url" ]] && break
    kill -0 "$BC_SRV_PID" 2>/dev/null || break
    sleep 0.25
  done

  if [[ -z "$url" ]]; then
    avisar_error "$salida"
    return 1
  fi
  echo "$url" > "$ESTADO_DIR/url"

  abrir_ventana "$url"
}

# -----------------------------------------------------------------------------
# Abrir la ventana y esperar a que se cierre
# -----------------------------------------------------------------------------
abrir_ventana() {
  local url="$1" nav
  if nav="$(navegador_app)"; then
    # --user-data-dir propio: sin él, Chrome delega en la instancia que ya
    # tengas abierta y el proceso lanzado termina al instante, con lo que no
    # habría forma de saber cuándo cierras la ventana.
    # El navegador va en SEGUNDO PLANO y se espera con `wait`, no en primer
    # plano. Con un hijo en primer plano, bash aplaza los traps hasta que ese
    # hijo termine: una señal al cerrar la sesión no se atendería y el servidor
    # sobreviviría. Con `wait`, la señal interrumpe la espera y el trap corre.
    "$nav" --app="$url" \
           --user-data-dir="$PERFIL" \
           --class=backupctl \
           --no-first-run --no-default-browser-check \
           --window-size=1280,860 >/dev/null 2>&1 &
    BC_NAV_PID=$!
    wait "$BC_NAV_PID" 2>/dev/null || true
    BC_NAV_PID=""
    # Al volver de aquí, la ventana se cerró: el trap apaga el servidor.
  else
    # Sin navegador de familia Chromium no se puede saber cuándo cierras la
    # pestaña. Se abre en el navegador por defecto y se avisa de cómo parar.
    xdg-open "$url" >/dev/null 2>&1 || true
    notificar "backupctl en marcha" \
      "Se ha abierto en tu navegador. El servidor seguirá encendido hasta que ejecutes: $0 parar"
    wait
  fi
}

apagar() {
  # Si nos van a matar a nosotros, la ventana se cierra también: dejarla
  # abierta contra un servidor que ya no existe solo confunde.
  if [[ -n "${BC_NAV_PID:-}" ]] && kill -0 "$BC_NAV_PID" 2>/dev/null; then
    kill "$BC_NAV_PID" 2>/dev/null || true
  fi
  if [[ -n "${BC_SRV_PID:-}" ]] && kill -0 "$BC_SRV_PID" 2>/dev/null; then
    kill "$BC_SRV_PID" 2>/dev/null || true
    # Si no muere por las buenas en 3 segundos, se insiste
    local i
    for i in 1 2 3 4 5 6; do
      kill -0 "$BC_SRV_PID" 2>/dev/null || break
      sleep 0.5
    done
    kill -9 "$BC_SRV_PID" 2>/dev/null || true
  fi
  rm -f "$ESTADO_DIR/servidor.pid" "$ESTADO_DIR/url"
}

parar() {
  local pid=""
  [[ -f "$ESTADO_DIR/servidor.pid" ]] && pid="$(cat "$ESTADO_DIR/servidor.pid" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    ok "servidor detenido (PID $pid)"
  else
    ok "no había ninguno corriendo"
  fi
  rm -f "$ESTADO_DIR/servidor.pid" "$ESTADO_DIR/url"
}

notificar() {
  command -v notify-send >/dev/null 2>&1 \
    && notify-send -i "$APP_ID" "$1" "$2" 2>/dev/null || true
  printf '%s: %s\n' "$1" "$2"
}

avisar_error() {
  local salida="$1"
  local detalle; detalle="$(tail -5 "$salida" 2>/dev/null | tr '\n' ' ')"
  notificar "backupctl no pudo arrancar" "${detalle:-sin detalle}"
  err "el servidor no llegó a arrancar. Salida:"
  sed 's/^/      /' "$salida" >&2
}

# =============================================================================
case "${1:-ayuda}" in
  instalar)     instalar ;;
  desinstalar)  desinstalar ;;
  estado)       estado ;;
  lanzar)       lanzar ;;
  parar)        parar ;;
  *)
    cat <<AYUDA
backupctl en el escritorio

  $0 instalar      añade backupctl al menú de aplicaciones
  $0 desinstalar   lo quita (y detiene el servidor si está corriendo)
  $0 estado        ¿instalada? ¿corriendo?
  $0 parar         detiene el servidor
  $0 lanzar        lo que ejecuta el icono del menú

Al abrir la aplicación se enciende el servidor local; al cerrar la ventana, se
apaga. No queda nada escuchando cuando no la usas.
AYUDA
    ;;
esac
