#!/usr/bin/env bash
# =============================================================================
# tests/ejecutar.sh — banco de pruebas local (ADR 0009)
# =============================================================================
# Única entrada. Sin argumentos. Lanza cada tests/probar_*.sh en un proceso
# propio, con un PATH que antepone órdenes falsas y un entorno limpio: ninguna
# suite puede tocar un servidor, MySQL ni el sistema de quien la ejecuta.
# Sale con 0 solo si todas las suites pasan.
# =============================================================================
set -u

if [[ "$(id -u)" == "0" ]]; then
  echo "tests/ejecutar.sh: no se ejecuta como root." >&2
  exit 2
fi

RAIZ="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

T="$(mktemp -d -t backupctl-pruebas.XXXXXX)"
if [[ -z "$T" || ! -d "$T" ]]; then
  echo "tests/ejecutar.sh: mktemp -d no devolvió un directorio utilizable." >&2
  exit 2
fi
trap 'rm -rf "$T"' EXIT

ORDENES_PELIGROSAS=(
  ssh scp sftp sshpass ssh-keygen ssh-copy-id rsync
  mysql mysqldump sudo crontab restic rclone mail curl
)

mkdir -p "$T/bin" "$T/home" "$T/tmp"
for orden in "${ORDENES_PELIGROSAS[@]}"; do
  ln -s "$RAIZ/tests/falsos/despachador.sh" "$T/bin/$orden"
done

BANCO_PATH="$T/bin:/usr/local/bin:/usr/bin:/bin"

# --- Comprobación de seguridad: antes de ejecutar NINGUNA suite --------------
fallo_seguridad=0
for orden in "${ORDENES_PELIGROSAS[@]}"; do
  resuelto="$(PATH="$BANCO_PATH" command -v "$orden" 2>/dev/null || true)"
  if [[ "$resuelto" != "$T/bin/$orden" ]]; then
    echo "ABORTADO: '$orden' no resuelve a su falso (resolvió a: '${resuelto:-<nada>}')." >&2
    fallo_seguridad=1
  fi
done
if (( fallo_seguridad )); then
  echo "No se ha ejecutado ninguna suite." >&2
  exit 2
fi

# --- Suites --------------------------------------------------------------
total=0
fallidas=0
for suite in "$RAIZ"/tests/probar_*.sh; do
  [[ -f "$suite" ]] || continue
  nombre="$(basename "$suite" .sh)"
  total=$(( total + 1 ))
  mkdir -p "$T/$nombre"
  echo
  echo "== $nombre =="
  if env -i \
      HOME="$T/home" \
      TMPDIR="$T/tmp" \
      PATH="$BANCO_PATH" \
      LANG=C.UTF-8 \
      BANCO_RAIZ="$RAIZ" \
      BANCO_TMP="$T/$nombre" \
      bash "$suite"
  then
    :
  else
    fallidas=$(( fallidas + 1 ))
  fi
done

echo
if (( total == 0 )); then
  echo "tests/ejecutar.sh: no se encontró ninguna suite (tests/probar_*.sh)." >&2
  exit 1
fi
echo "suites: $total, fallidas: $fallidas"
(( fallidas == 0 ))
