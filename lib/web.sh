#!/usr/bin/env bash
# =============================================================================
# lib/web.sh — interfaz web local
# =============================================================================
# Tercera fachada sobre la misma lógica: TUI para el terminal, CLI para el cron,
# y esta para el navegador. No reimplementa nada: el servidor llama al propio
# backupctl y retransmite su salida.
#
# Lo que aporta sobre la TUI es ver TODOS los perfiles a la vez: el estado de
# cada VPS en una sola pantalla, que en el terminal exige recorrerlos uno a uno.
#
# SEGURIDAD
#   - Escucha solo en 127.0.0.1. Exponerla en la red sería regalar una consola
#     con tus credenciales, así que hay que forzarlo explícitamente.
#   - Cada arranque genera una credencial de sesión: sin ella la API no
#     responde. Impide que una página web cualquiera abierta en el navegador
#     dispare órdenes contra tu localhost.
#   - No ejecuta órdenes arbitrarias: hay una lista blanca de acciones y los
#     argumentos se construyen en el servidor.
# =============================================================================

[[ -n "${BC_WEB_LOADED:-}" ]] && return 0
BC_WEB_LOADED=1

bc_web_run() {
  local port="${BC_OPT_PORT:-8787}"
  local host="${BC_OPT_HOST:-127.0.0.1}"

  bc_require_cmd python3

  if [[ "$host" != "127.0.0.1" && "$host" != "localhost" ]]; then
    bc_warn "vas a escuchar en $host, no solo en localhost."
    bc_warn "Esta interfaz ejecuta órdenes con tus credenciales: exponerla en la"
    bc_warn "red equivale a dar una consola a quien llegue a ese puerto."
    bc_confirm "¿Seguro que quieres escuchar en $host?" n || bc_die "cancelado."
  fi

  [[ -f "$BC_ROOT/web/server.py" ]] || bc_die "falta $BC_ROOT/web/server.py"

  bc_log "Arrancando la interfaz web..."
  # -u: sin búfer. Si no, al redirigir la salida a un archivo la dirección con
  # la credencial se queda en el búfer y no aparece hasta que el servidor muere.
  BC_ROOT="$BC_ROOT" BC_VERSION="$BC_VERSION" \
    exec python3 -u "$BC_ROOT/web/server.py" \
      --host "$host" --port "$port" \
      ${BC_OPT_OPEN:+--open}
}
