#!/usr/bin/env bash
# =============================================================================
# env.sh — configuración de TejidoTesting
# =============================================================================
# Único archivo específico de este servidor. Los scripts son idénticos en todos
# y leen de aquí todo lo que cambia entre máquinas.
#
# Referencia completa de las variables disponibles: env.sh.example
# =============================================================================

# --- Generales ---------------------------------------------------------------
export USER_NAME=admin
export SCRIPTS_DIR="/home/${USER_NAME}/scripts"

# --- Conexión a MySQL --------------------------------------------------------
export MYSQL_USER=admin_general
export MYSQL_PASS=Bdcc69DITTZHUgbu4Wc6

# Vacíos: conexión por socket local.
export MYSQL_HOST=""
export MYSQL_PORT=""
export MYSQL_SOCKET=""
export MYSQL_CHARSET="utf8mb4"

export EXCLUDE_DBS="('information_schema','performance_schema','mysql','sys','phpmyadmin')"

# --- Rutas de salida ---------------------------------------------------------
export BACKUP_OUTPUT_DIR="${SCRIPTS_DIR}/output/mysql_backups"
export BACKUP_WORK_DIR="${SCRIPTS_DIR}/output"
export HESTIA_OUTPUT_DIR="${SCRIPTS_DIR}/output/HestiaCP"
export LOG_DIR="${SCRIPTS_DIR}/logs"

# --- Retención ---------------------------------------------------------------
# 76 bases de datos ≈ 40 MB por ejecución diaria. Sin retención esto crecía
# 1,2 GB al mes sin que nada lo limpiara.
export BACKUP_RETENTION_DAYS="14"
export LOG_RETENTION_DAYS="30"
export RESTIC_RETENTION_DAYS="90"
export BACKUP_KEEP_MIN="3"

# --- Comprobaciones ----------------------------------------------------------
export MIN_FREE_MB="2048"

# --- Avisos ante fallo -------------------------------------------------------
# ⚠ SIN CONFIGURAR. Mientras estén vacíos, un respaldo fallido no avisa a nadie.
#   Configura al menos uno. Ver ScriptsTemplates/env.sh.example.
export NOTIFY_EMAIL=""
export NOTIFY_COMMAND=""
export HEALTHCHECK_URL=""

# --- HestiaCP ----------------------------------------------------------------
export HESTIA_DIR="/usr/local/hestia"
