#!/usr/bin/env bash
# =============================================================================
# tests/lib.sh — biblioteca mínima del banco de pruebas (ADR 0010)
# =============================================================================
# La cargan las suites (tests/probar_*.sh). Nada de esto se ejecuta contra un
# servidor: los perfiles que crea viven siempre dentro de $BANCO_TMP, y
# backupctl_prueba se niega a usar uno que no lo esté.
#
# Las afirmaciones se cuentan desde un ARCHIVO ($BANCO_TMP/.resultados), no
# desde variables: una variable que cambia dentro de "$(...)" no sobrevive al
# subshell (docs/desarrollo/arquitectura.md, «Detalles que no son obvios»); un
# archivo, sí. Con esto una llamada a backupctl_prueba dentro de una
# sustitución de comandos sigue contando aunque se niegue a ejecutar.
# =============================================================================

[[ -n "${BC_PRUEBA_LIB_LOADED:-}" ]] && return 0
BC_PRUEBA_LIB_LOADED=1

# -----------------------------------------------------------------------------
# Salvaguarda de entorno — falla en CERRADO, no en abierto
# -----------------------------------------------------------------------------
# BANCO_TMP y BANCO_RAIZ sostienen todas las demás salvaguardas de este
# archivo (backupctl_prueba, nueva_prueba): si cualquiera de las dos está
# vacía, no es absoluta, o no es un directorio, cualquier comparación de rutas
# posterior puede degenerar en "acepta cualquiera" (revisión de la ronda
# #008: con $BANCO_TMP="", el patrón "$base"/*|"$base" se volvía /*|"", que
# aceptaba cualquier ruta absoluta). Se comprueba ANTES de cualquier mkdir o
# rm, y de nuevo dentro de nueva_prueba (defensa en profundidad).
#
# ADR 0010: esto NO basta. La ronda #010 encontró que una suite lanzada a
# mano, sin pasar por tests/ejecutar.sh, superaba todo lo anterior con solo
# exportar BANCO_RAIZ/BANCO_TMP a un directorio real — y entonces
# backupctl_prueba ejecutaba con el PATH real del usuario (mysql, ssh...
# reales en esta máquina). Por eso, además: la marca .banco que escribe
# ejecutar.sh en el directorio PADRE de BANCO_TMP tiene que coincidir con
# BANCO_TESTIGO, y cada orden de ordenes.txt tiene que resolver al enlace que
# el propio ejecutar.sh creó.
bc_comprobar_entorno_banco() {
  if [[ "$(id -u)" == "0" ]]; then
    echo "tests/lib.sh: no se ejecuta como root." >&2
    exit 2
  fi

  local nombre valor real
  for nombre in BANCO_TMP BANCO_RAIZ; do
    valor="${!nombre:-}"
    if [[ -z "$valor" ]]; then
      echo "tests/lib.sh: \$$nombre no está definida o está vacía: se aborta." >&2
      exit 2
    fi
    if [[ "$valor" != /* ]]; then
      echo "tests/lib.sh: \$$nombre no es una ruta absoluta ('$valor'): se aborta." >&2
      exit 2
    fi
    if [[ ! -d "$valor" ]]; then
      echo "tests/lib.sh: \$$nombre no es un directorio existente ('$valor'): se aborta." >&2
      exit 2
    fi
  done

  real="$(realpath -e -- "$BANCO_TMP" 2>/dev/null || true)"
  case "$real" in
    /tmp/backupctl-pruebas.*) ;;
    *)
      echo "tests/lib.sh: \$BANCO_TMP ('$BANCO_TMP', resuelto '$real') no está dentro de /tmp/backupctl-pruebas.*: se aborta." >&2
      exit 2
      ;;
  esac

  if [[ -z "${BANCO_TESTIGO:-}" ]]; then
    echo "tests/lib.sh: \$BANCO_TESTIGO no está definida o está vacía: se aborta." >&2
    exit 2
  fi
  local padre marca
  padre="$(dirname "$BANCO_TMP")"
  if [[ ! -f "$padre/.banco" ]]; then
    echo "tests/lib.sh: no existe $padre/.banco: se aborta." >&2
    exit 2
  fi
  marca="$(cat "$padre/.banco" 2>/dev/null || true)"
  if [[ -z "$marca" || "$marca" != "$BANCO_TESTIGO" ]]; then
    echo "tests/lib.sh: la marca de $padre/.banco no coincide con \$BANCO_TESTIGO: se aborta." >&2
    exit 2
  fi

  if ! bc_comprobar_orden_falsa; then
    echo "tests/lib.sh: el PATH no resuelve las órdenes peligrosas a sus falsas: se aborta." >&2
    exit 2
  fi
}

# Comprueba, orden por orden de tests/falsos/ordenes.txt, que "command -v"
# resuelve al enlace que crea tests/ejecutar.sh (bajo el padre de BANCO_TMP) y
# que ese enlace apunta de verdad a tests/falsos/despachador.sh. No sale del
# proceso: solo informa por stderr y devuelve 1 si algo falla, para que tanto
# la carga de la biblioteca (exit 2) como backupctl_prueba (return 97) puedan
# decidir qué hacer con eso.
bc_comprobar_orden_falsa() {
  local archivo="$BANCO_RAIZ/tests/falsos/ordenes.txt"
  if [[ ! -s "$archivo" ]]; then
    echo "tests/lib.sh: falta o está vacío $archivo." >&2
    return 1
  fi

  local despachador_real
  despachador_real="$(realpath -e -- "$BANCO_RAIZ/tests/falsos/despachador.sh" 2>/dev/null || true)"
  if [[ -z "$despachador_real" ]]; then
    echo "tests/lib.sh: no se pudo resolver tests/falsos/despachador.sh." >&2
    return 1
  fi

  local base_bin
  base_bin="$(dirname "$BANCO_TMP")/bin"

  local orden resuelto enlace_real
  while IFS= read -r orden || [[ -n "$orden" ]]; do
    [[ -z "$orden" ]] && continue
    if [[ ! "$orden" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      echo "tests/lib.sh: línea inválida en $archivo: '$orden'." >&2
      return 1
    fi
    resuelto="$(command -v "$orden" 2>/dev/null || true)"
    if [[ "$resuelto" != "$base_bin/$orden" ]]; then
      echo "tests/lib.sh: '$orden' no resuelve al falso del banco (resolvió a: '${resuelto:-<nada>}')." >&2
      return 1
    fi
    if [[ ! -L "$base_bin/$orden" ]]; then
      echo "tests/lib.sh: '$base_bin/$orden' no es un enlace simbólico." >&2
      return 1
    fi
    enlace_real="$(realpath -e -- "$base_bin/$orden" 2>/dev/null || true)"
    if [[ -z "$enlace_real" || "$enlace_real" != "$despachador_real" ]]; then
      echo "tests/lib.sh: '$base_bin/$orden' no apunta a tests/falsos/despachador.sh." >&2
      return 1
    fi
  done < "$archivo"
  return 0
}

bc_comprobar_entorno_banco

mkdir -p "$BANCO_TMP/registro" "$BANCO_TMP/guion"
: > "$BANCO_TMP/.resultados"

# -----------------------------------------------------------------------------
# Afirmaciones
# -----------------------------------------------------------------------------
# Cada afirmar_* escribe su detalle en $BANCO_TMP/.resultados en UNA sola
# línea: fin_de_suite cuenta líneas, y un valor interpolado con saltos de
# línea (un nombre de archivo con ruta larga, una lista) inflaría el
# recuento. bc_una_linea sustituye cada salto por " | ".
bc_una_linea() {
  local s="$1"
  printf '%s' "${s//$'\n'/ | }"
}

afirmar_codigo() {
  local esperado="$1" obtenido="$2" desc="$3"
  if [[ "$esperado" == "$obtenido" ]]; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$(bc_una_linea "$desc")" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc (esperado código $esperado, obtenido $obtenido)" >&2
    printf 'FALLO\t%s\n' "$(bc_una_linea "$desc (esperado codigo $esperado, obtenido $obtenido)")" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_igual() {
  local a="$1" b="$2" desc="$3"
  if [[ "$a" == "$b" ]]; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$(bc_una_linea "$desc")" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc (esperado '$b', obtenido '$a')" >&2
    printf 'FALLO\t%s\n' "$(bc_una_linea "$desc (esperado $b, obtenido $a)")" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_contiene() {
  local archivo="$1" patron="$2" desc="$3"
  if [[ -f "$archivo" ]] && grep -qE -- "$patron" "$archivo"; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$(bc_una_linea "$desc")" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc (no se encontró '$patron' en $archivo)" >&2
    printf 'FALLO\t%s\n' "$(bc_una_linea "$desc (no se encontro $patron en $archivo)")" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_no_contiene() {
  local archivo="$1" patron="$2" desc="$3"
  if [[ ! -f "$archivo" ]]; then
    echo "  FALLO: $desc (no existe $archivo)" >&2
    printf 'FALLO\t%s\n' "$(bc_una_linea "$desc (no existe $archivo)")" >> "$BANCO_TMP/.resultados"
  elif grep -qE -- "$patron" "$archivo"; then
    echo "  FALLO: $desc (se encontró '$patron' en $archivo)" >&2
    printf 'FALLO\t%s\n' "$(bc_una_linea "$desc (se encontro $patron en $archivo)")" >> "$BANCO_TMP/.resultados"
  else
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$(bc_una_linea "$desc")" >> "$BANCO_TMP/.resultados"
  fi
}

afirmar_intacto() {
  local archivo="$1" copia="$2" desc="$3"
  if cmp -s "$archivo" "$copia"; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$(bc_una_linea "$desc")" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc ($archivo difiere de $copia)" >&2
    printf 'FALLO\t%s\n' "$(bc_una_linea "$desc ($archivo difiere de $copia)")" >> "$BANCO_TMP/.resultados"
  fi
}

# Archivo o directorio. Se usa ANTES de una afirmación que inspecciona una
# ruta (grep, find...): esas pasan en verde también cuando la ruta no existe,
# que es justo lo que no debe pasar desapercibido (40-entorno.md, «Cómo se
# prueba sin servidor»).
afirmar_existe() {
  local ruta="$1" desc="$2"
  if [[ -e "$ruta" ]]; then
    echo "  ok: $desc" >&2
    printf 'ok\t%s\n' "$(bc_una_linea "$desc")" >> "$BANCO_TMP/.resultados"
  else
    echo "  FALLO: $desc (no existe $ruta)" >&2
    printf 'FALLO\t%s\n' "$(bc_una_linea "$desc (no existe $ruta)")" >> "$BANCO_TMP/.resultados"
  fi
}

# Cuenta SIEMPRE desde el archivo, y solo líneas que empiezan por "ok<TAB>" o
# "FALLO<TAB>": el detalle de una afirmación (un nombre de archivo, una
# lista) va siempre en una sola línea (ver el saneo en cada afirmar_*), pero
# contar con wc -l se habría inflado igual si alguna vez no lo fuera. Una
# suite sin ninguna afirmación no ha probado nada: cuenta como fallo, no como
# éxito vacío.
fin_de_suite() {
  local total=0 fallos=0
  if [[ -f "$BANCO_TMP/.resultados" ]]; then
    total="$(grep -cE $'^(ok|FALLO)\t' "$BANCO_TMP/.resultados" || true)"
    fallos="$(grep -cE $'^FALLO\t' "$BANCO_TMP/.resultados" || true)"
  fi
  echo "  -- $total afirmaciones, $fallos fallidas --" >&2
  if (( total == 0 )); then
    echo "  FALLO: la suite no hizo ninguna afirmación" >&2
    return 1
  fi
  (( fallos == 0 ))
}

# -----------------------------------------------------------------------------
# Aislamiento entre pruebas
# -----------------------------------------------------------------------------
# Cada test_… empieza llamando a esto: deja registro/ y guion/ limpios (sin
# arrastrar invocaciones ni respuestas de la prueba anterior dentro de la
# misma suite) y un directorio propio donde trabajar.
nueva_prueba() {
  local nombre="$1"
  bc_comprobar_entorno_banco
  rm -rf "$BANCO_TMP/registro" "$BANCO_TMP/guion"
  mkdir -p "$BANCO_TMP/registro" "$BANCO_TMP/guion" "$BANCO_TMP/$nombre"
  cd "$BANCO_TMP/$nombre"
}

# -----------------------------------------------------------------------------
# Perfil sintético
# -----------------------------------------------------------------------------
# Declara TODAS las variables de forma explícita: nada se hereda del entorno
# (T13, .agents/context/30-trampas.md). BACKUP_WORK_DIR existe ya al volver de
# esta función: el bloqueo de 'backup' se toma antes de crear directorios y,
# si no existe, sale con 2 (core.sh:188, bin/backupctl:283). MYSQL_PASS lleva
# un valor distintivo para poder comprobar que nunca llega a un registro ni a
# un log (test_profile_password_never_reaches_the_logs).
crear_perfil() {
  local dir="$1"
  mkdir -p "$dir/output/mysql_backups" "$dir/output/HestiaCP" "$dir/logs"
  cat > "$dir/env.sh" <<EOF
export MYSQL_USER="prueba"
export MYSQL_PASS="clave-sintetica-no-real-7Q2"
export MYSQL_HOST=""
export MYSQL_PORT=""
export MYSQL_SOCKET=""
export MYSQL_CHARSET="utf8mb4"
export USER_NAME="prueba"
export DEPLOY_HOST=""
export SCRIPTS_DIR="$dir"
export BACKUP_OUTPUT_DIR="$dir/output/mysql_backups"
export BACKUP_WORK_DIR="$dir/output"
export HESTIA_OUTPUT_DIR="$dir/output/HestiaCP"
export LOG_DIR="$dir/logs"
export BACKUP_RETENTION_DAYS="14"
export LOG_RETENTION_DAYS="30"
export RESTIC_RETENTION_DAYS="90"
export BACKUP_KEEP_MIN="3"
export MIN_FREE_MB="0"
export DISK_SAFETY_FACTOR="1"
export NOTIFY_EMAIL=""
export NOTIFY_COMMAND=""
export HEALTHCHECK_URL=""
EOF
}

# Carga "$1/env.sh" en un subshell AISLADO (env -i, solo PATH/HOME/TMPDIR
# actuales) — nunca en el proceso de la suite — y comprueba que las rutas que
# quedan tras aplicarles los MISMOS valores por defecto que
# lib/config.sh:146-197 (bc_config_apply_defaults) caen dentro de $BANCO_TMP,
# y que DEPLOY_HOST está vacío. HESTIA_DIR solo se comprueba si el perfil lo
# declara: su valor por defecto, /usr/local/hestia, no es lo que aquí se
# vigila (nunca va a estar dentro de un temporal, y no tiene por qué).
#
# Ronda #012: un perfil dentro de $BANCO_TMP con env.sh normal (no enlace)
# podía declarar BACKUP_OUTPUT_DIR/LOG_DIR apuntando FUERA, y backupctl
# escribía —y con retention, borraba— ahí sin que nada lo impidiera. Esto lo
# cierra: se valida el CONTENIDO del perfil, no solo su ubicación.
#
# Deja el motivo del fallo en BC_MOTIVO_RUTAS_PERFIL; no imprime ni escribe
# en .resultados por su cuenta (lo hace quien la llama, como las demás
# negativas de backupctl_prueba).
bc_comprobar_rutas_perfil() {
  local perfil_dir="$1"
  BC_MOTIVO_RUTAS_PERFIL=""

  local salida rc
  salida="$(env -i HOME="${HOME:-}" TMPDIR="${TMPDIR:-}" PATH="$PATH" bash -c '
    source "$1/env.sh" || exit 3
    printf "%s\n" "${SCRIPTS_DIR:-}" "${BACKUP_OUTPUT_DIR:-}" "${BACKUP_WORK_DIR:-}" \
                  "${HESTIA_OUTPUT_DIR:-}" "${LOG_DIR:-}" "${HESTIA_DIR:-}" "${DEPLOY_HOST:-}"
  ' _ "$perfil_dir" 2>/dev/null)"
  rc=$?
  if (( rc != 0 )); then
    BC_MOTIVO_RUTAS_PERFIL="no se pudo cargar '$perfil_dir/env.sh' (código $rc)"
    return 1
  fi

  local scripts_dir out_dir work_dir hestia_out log_dir hestia_dir deploy_host
  { IFS= read -r scripts_dir; IFS= read -r out_dir; IFS= read -r work_dir;
    IFS= read -r hestia_out; IFS= read -r log_dir; IFS= read -r hestia_dir;
    IFS= read -r deploy_host; } <<<"$salida"

  # Mismos valores por defecto que bc_config_apply_defaults: SCRIPTS_DIR cae
  # al directorio del perfil (BC_PROFILE_DIR allí es "$perfil_dir" aquí); el
  # resto cuelga de SCRIPTS_DIR.
  [[ -n "$scripts_dir" ]] || scripts_dir="$perfil_dir"
  [[ -n "$out_dir"    ]] || out_dir="$scripts_dir/output/mysql_backups"
  [[ -n "$work_dir"   ]] || work_dir="$scripts_dir/output"
  [[ -n "$hestia_out" ]] || hestia_out="$scripts_dir/output/HestiaCP"
  [[ -n "$log_dir"    ]] || log_dir="$scripts_dir/logs"

  if [[ -n "$deploy_host" ]]; then
    BC_MOTIVO_RUTAS_PERFIL="el perfil declara DEPLOY_HOST ('$deploy_host'); debe estar vacío"
    return 1
  fi

  local base_tmp
  base_tmp="$(realpath -e -- "$BANCO_TMP" 2>/dev/null || true)"
  if [[ -z "$base_tmp" ]]; then
    BC_MOTIVO_RUTAS_PERFIL="no se pudo resolver \$BANCO_TMP"
    return 1
  fi

  local nombre valor real
  for nombre in SCRIPTS_DIR BACKUP_OUTPUT_DIR BACKUP_WORK_DIR HESTIA_OUTPUT_DIR LOG_DIR; do
    case "$nombre" in
      SCRIPTS_DIR)       valor="$scripts_dir" ;;
      BACKUP_OUTPUT_DIR) valor="$out_dir" ;;
      BACKUP_WORK_DIR)   valor="$work_dir" ;;
      HESTIA_OUTPUT_DIR) valor="$hestia_out" ;;
      LOG_DIR)           valor="$log_dir" ;;
    esac
    real="$(realpath -m -- "$valor" 2>/dev/null || true)"
    if [[ -z "$real" ]]; then
      BC_MOTIVO_RUTAS_PERFIL="no se pudo resolver $nombre ('$valor')"
      return 1
    fi
    case "$real" in
      "$base_tmp"/*|"$base_tmp") ;;
      *)
        BC_MOTIVO_RUTAS_PERFIL="$nombre ('$valor', resuelto '$real') queda fuera de \$BANCO_TMP"
        return 1
        ;;
    esac
  done

  if [[ -n "$hestia_dir" ]]; then
    real="$(realpath -m -- "$hestia_dir" 2>/dev/null || true)"
    if [[ -z "$real" ]]; then
      BC_MOTIVO_RUTAS_PERFIL="no se pudo resolver HESTIA_DIR ('$hestia_dir')"
      return 1
    fi
    case "$real" in
      "$base_tmp"/*|"$base_tmp") ;;
      *)
        BC_MOTIVO_RUTAS_PERFIL="HESTIA_DIR ('$hestia_dir', resuelto '$real') queda fuera de \$BANCO_TMP"
        return 1
        ;;
    esac
  fi

  return 0
}

# -----------------------------------------------------------------------------
# Ejecución de backupctl bajo prueba
# -----------------------------------------------------------------------------
# Siempre con -p y con la entrada estándar cerrada. Se niega —y lo deja escrito
# en $BANCO_TMP/.resultados, no solo en una variable— en cuatro casos: el
# perfil no está dentro de $BANCO_TMP (T3); su env.sh es un enlace simbólico
# (podría llevar a cualquier sitio, credenciales reales incluidas); el propio
# env.sh declara una ruta fuera de $BANCO_TMP (ronda #012:
# bc_comprobar_rutas_perfil); o el PATH ya no resuelve las órdenes peligrosas
# a sus falsas (ADR 0010 — la misma comprobación de bc_comprobar_orden_falsa,
# repetida aquí porque el entorno pudo cambiar entre la carga de la
# biblioteca y esta llamada). Compara realpath -e/-m de perfil y $BANCO_TMP;
# si cualquiera de los dos falla o devuelve vacío, SE NIEGA (ronda #008: con
# base="", "$base"/*|"$base" se volvía /*|"", que aceptaba cualquier ruta).
backupctl_prueba() {
  local perfil_dir="$1"; shift
  local real base negar=1 motivo=""

  real="$(realpath -m -- "$perfil_dir" 2>/dev/null || true)"
  base="$(realpath -e -- "$BANCO_TMP" 2>/dev/null || true)"
  if [[ -n "$real" && -n "$base" ]]; then
    case "$real" in
      "$base"/*|"$base") negar=0 ;;
    esac
  fi

  if (( negar == 0 )) && [[ -L "$perfil_dir/env.sh" ]]; then
    negar=1
    motivo="'$perfil_dir/env.sh' es un enlace simbólico"
  fi

  if (( negar == 0 )) && ! bc_comprobar_rutas_perfil "$perfil_dir"; then
    negar=1
    motivo="$BC_MOTIVO_RUTAS_PERFIL"
  fi

  if (( negar == 0 )) && ! bc_comprobar_orden_falsa; then
    negar=1
    motivo="el PATH ya no resuelve las órdenes peligrosas a sus falsas"
  fi

  if (( negar == 0 )); then
    "$BANCO_RAIZ/bin/backupctl" -p "$perfil_dir/env.sh" "$@" </dev/null
    return $?
  fi

  [[ -z "$motivo" ]] && motivo="'$perfil_dir' (resuelto: '$real') está fuera de \$BANCO_TMP ('$base')"
  echo "  FALLO: backupctl_prueba se niega a ejecutar: $motivo" >&2
  printf 'FALLO\tbackupctl_prueba se niega: %s\n' "$(bc_una_linea "$motivo")" >> "$BANCO_TMP/.resultados"
  return 97
}

# -----------------------------------------------------------------------------
# Guiones para las órdenes falsas de MySQL
# -----------------------------------------------------------------------------
# Un único guion de 'mysql' sirve para respaldo, verificación y restauración:
# cubre la conexión, las consultas de inventario y, sin -e, el SQL que llega
# por la entrada estándar (restore.sh). Las respuestas están documentadas en
# el ADR 0009 y .agents/context/40-entorno.md, y confirmadas contra
# lib/mysql.sh, lib/backup.sh y lib/restore.sh — son sintéticas, no salidas
# reales de MySQL.
#
# Parámetros, todos opcionales tras <tmp>:
#   destino_existe    "SELECT COUNT(*) ... schema_name='<x>'" (restore.sh:74,
#                     lib/mysql.sh bc_mysql_table_count) responde esto en vez
#                     de "0": el destino de un --into ya existe.
#   tablas_existentes "SELECT COUNT(*) ... table_type='BASE TABLE'" responde
#                     esto: cuántas tablas tiene ya ese destino.
#   fallar_conexion   "1" hace que "SELECT 1" (bc_mysql_check) escriba un
#                     error en stderr y salga con 1, en vez de conectar.
escribir_guion_mysql() {
  local tmp="$1" destino_existe="${2:-0}" tablas_existentes="${3:-0}" fallar_conexion="${4:-0}"
  mkdir -p "$tmp/guion" "$tmp/registro"
  {
    printf 'BC_DESTINO_EXISTE=%q\n' "$destino_existe"
    printf 'BC_TABLAS_EXISTENTES=%q\n' "$tablas_existentes"
    printf 'BC_FALLAR_CONEXION=%q\n' "$fallar_conexion"
    cat <<'GUION'
consulta=""
for ((_i = 1; _i <= $#; _i++)); do
  if [[ "${!_i}" == "-e" ]]; then
    _j=$(( _i + 1 ))
    consulta="${!_j}"
  fi
done

if [[ -z "$consulta" ]]; then
  # SQL por la entrada estándar: solo lo usa restore (y verify --restore-test,
  # que estas suites no ejercitan). Se numera por orden de llegada.
  n=1
  while [[ -f "$BANCO_TMP/registro/mysql.stdin.$n" ]]; do n=$(( n + 1 )); done
  cat > "$BANCO_TMP/registro/mysql.stdin.$n"
  { printf '%q ' "$@"; echo; } > "$BANCO_TMP/registro/mysql.stdin.$n.args"
  exit 0
fi

case "$consulta" in
  *'SELECT 1'*)
    if [[ "$BC_FALLAR_CONEXION" == "1" ]]; then
      echo "ERROR 1045 (28000): Access denied for user" >&2
      exit 1
    fi
    exit 0 ;;
  *"schema_name='"*) echo "$BC_DESTINO_EXISTE"; exit 0 ;;
  *"table_type='BASE TABLE'"*) echo "$BC_TABLAS_EXISTENTES"; exit 0 ;;
  *'COUNT(*)'*) echo "0"; exit 0 ;;
  *'VERSION()'*) echo "10.11.0-sintetico"; exit 0 ;;
  *'SUM(data_length'*) echo "1024"; exit 0 ;;
  *"NOT IN ('InnoDB')"*) exit 0 ;;
  *'default_character_set_name'*) printf 'utf8mb4\tutf8mb4_general_ci\n'; exit 0 ;;
  *'information_schema.VIEWS'*) exit 0 ;;
  *'information_schema.schemata'*) printf 'blog\ntienda\n'; exit 0 ;;
  *) echo "falso mysql: consulta inesperada: $consulta" >&2; exit 97 ;;
esac
GUION
  } > "$tmp/guion/mysql.sh"
}

# Guion de 'mysqldump'. Sin fallo (db_falla vacío) siempre limpio; con
# db_falla/segmento_falla, ESE volcado concreto escribe un error en stderr y
# sale con 0 — la mentira de --force que hace fallar el respaldo sin que lo
# delate el código de salida (lib/backup.sh:52-60).
escribir_guion_mysqldump() {
  local tmp="$1" db_falla="${2:-}" segmento_falla="${3:-}"
  mkdir -p "$tmp/guion" "$tmp/registro"
  {
    printf 'BC_DB_FALLA=%q\n' "$db_falla"
    printf 'BC_SEGMENTO_FALLA=%q\n' "$segmento_falla"
    cat <<'GUION'
if [[ "${1:-}" == "--help" ]]; then
  exit 0
fi

_no_data=0; _no_create_info=0; _skip_triggers=0; _routines=0; _triggers=0
_db=""
for _a in "$@"; do
  case "$_a" in
    --no-data) _no_data=1 ;;
    --no-create-info) _no_create_info=1 ;;
    --skip-triggers) _skip_triggers=1 ;;
    --routines) _routines=1 ;;
    --triggers) _triggers=1 ;;
    --*) ;;
    *) _db="$_a" ;;
  esac
done

if (( _routines )); then
  echo "-- backupctl-pruebas: funciones sintéticas"
  exit 0
elif (( _triggers )); then
  echo "-- backupctl-pruebas: triggers y eventos sintéticos"
  exit 0
elif (( _no_data && _skip_triggers && ! _no_create_info )); then
  if [[ -n "$BC_DB_FALLA" && "$_db" == "$BC_DB_FALLA" && "$BC_SEGMENTO_FALLA" == "tables" ]]; then
    echo "mysqldump: Got error: 1045: Access denied" >&2
    exit 0
  fi
  echo "CREATE TABLE \`t\` (\`id\` int);"
  exit 0
elif (( _no_create_info && _skip_triggers && ! _no_data )); then
  if [[ -n "$BC_DB_FALLA" && "$_db" == "$BC_DB_FALLA" && "$BC_SEGMENTO_FALLA" == "data" ]]; then
    echo "mysqldump: Got error: 1045: Access denied" >&2
    exit 0
  fi
  echo "INSERT INTO \`t\` VALUES (1);"
  exit 0
else
  echo "falso mysqldump: combinación de opciones inesperada: $*" >&2
  exit 97
fi
GUION
  } > "$tmp/guion/mysqldump.sh"
}
