#!/bin/bash

# Mover al directorio del script para que las rutas relativas sean predecibles
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

source ./env.sh

OUTPUT_DIR="./HestiaCP"
OUTPUT_PATH="${OUTPUT_DIR}/Restic_Configs_$(date +%Y%m%d).txt"

mkdir -p "$OUTPUT_DIR" 2>/dev/null

find /usr/local/hestia -type f -name "restic.conf" -exec sh -c 'for f do printf "# %s:\n" "$(basename "$(dirname "$f")")"; cat "$f"; printf "\n\n=====================\n"; done' sh {} + > "$OUTPUT_PATH"


