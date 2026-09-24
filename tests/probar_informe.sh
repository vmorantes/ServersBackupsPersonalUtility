#!/usr/bin/env bash
# =============================================================================
# tests/probar_informe.sh — el informe de lo que se hizo (ADR 0014)
# =============================================================================
# lib/informe.sh no habla con ningún servidor: acumula registros y compone un
# Markdown. Se prueba entero aquí, con un perfil sintético dentro del banco.
#
# Lo que de verdad vigila esta suite: que un secreto NO acabe escrito. El
# informe se guarda en el directorio del perfil, que está versionado — una
# contraseña ahí es una contraseña publicada.
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_informe.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_informe =="

# Ejecuta un guion con lib/core.sh y lib/informe.sh cargadas y un perfil
# sintético. $1 es el directorio del perfil; $2 el guion.
con_informe() {
  local perfil="$1" guion="$2"
  bash -c '
    source "$1/lib/core.sh"
    source "$1/lib/informe.sh"
    BC_PROFILE=Sintetico
    BC_PROFILE_DIR="$2"
    eval "$3"
  ' _ "$BANCO_RAIZ" "$perfil" "$guion" 2>&1
}

CLAVE_DE_PRUEBA='Zx9-clave-sintetica-de-prueba'

# Un informe con los siete elementos. Se comprueba el ARCHIVO, no lo que la
# función diga haber hecho.
test_a_full_report_contains_every_element() {
  nueva_prueba t1
  local perfil="$BANCO_TMP/t1/perfil"
  mkdir -p "$perfil"
  local ruta
  ruta="$(con_informe "$perfil" '
    bc_informe_abrir "Registrar el host de respaldo" "servidor.example.org"
    bc_informe_dato "Repositorio" "" "rclone:almacen:/IncrementalBackups"
    bc_informe_orden "v-add-backup-host-restic rclone:almacen:/IncrementalBackups"
    bc_informe_copia "/usr/local/hestia/conf/restic.conf" "/usr/local/hestia/conf/restic.conf.20260923"
    bc_informe_paso "Registrar" HECHO "quedó registrado y la relectura lo confirma"
    bc_informe_paso "Programar" SIN_CAMBIO "ya estaba programado"
    bc_informe_deshacer "v-delete-backup-host-restic"
    bc_informe_cerrar HECHO
  ')"

  afirmar_igual "$([[ -f "$ruta" ]] && echo si || echo no)" "si" \
    "el informe se escribió en un archivo"
  case "$ruta" in
    "$perfil"/informes/*-Registrar-el-host-de-respaldo.md)
      afirmar_igual "si" "si" "va en <Perfil>/informes/ con fecha y acción en el nombre" ;;
    *) afirmar_igual "no ('$ruta')" "si" "va en <Perfil>/informes/ con fecha y acción en el nombre" ;;
  esac

  afirmar_contiene "$ruta" "^# Registrar el host de respaldo — servidor.example.org" \
    "el título lleva la acción y el destino"
  afirmar_contiene "$ruta" "Perfil:.. Sintetico"         "dice de qué perfil es"
  afirmar_contiene "$ruta" "Resultado:.. HECHO"          "dice cómo acabó"
  afirmar_contiene "$ruta" "\| Registrar \| HECHO \|"    "el paso hecho"
  afirmar_contiene "$ruta" "\| Programar \| SIN_CAMBIO \|" "el paso que no hizo falta"
  afirmar_contiene "$ruta" "v-add-backup-host-restic"    "la orden ejecutada"
  afirmar_contiene "$ruta" "restic.conf.20260923"        "la copia que quedó en el servidor"
  afirmar_contiene "$ruta" "v-delete-backup-host-restic" "cómo deshacerlo"
}

# Un «antes» vacío es lo normal al registrar algo por primera vez. Si el
# separador de campos fuera un tabulador, bash colapsaría el hueco al leer y el
# valor NUEVO aparecería en la columna del viejo: el informe diría que antes
# había justo lo que se acaba de poner.
test_an_empty_before_does_not_shift_the_columns() {
  nueva_prueba t2
  local perfil="$BANCO_TMP/t2/perfil"
  mkdir -p "$perfil"
  local ruta
  ruta="$(con_informe "$perfil" '
    bc_informe_abrir "Alta" "servidor.example.org"
    bc_informe_dato "Repositorio" "" "rclone:almacen:/IncrementalBackups"
    bc_informe_cerrar HECHO
  ')"
  afirmar_contiene "$ruta" "\| Repositorio \|  \| rclone:almacen:/IncrementalBackups \|" \
    "el valor nuevo va en la columna 'Después', no en la de 'Antes'"
}

# LA PRUEBA QUE IMPORTA. Se le pasa una contraseña a bc_informe_dato y el
# archivo NO puede contenerla.
test_a_password_never_reaches_the_file() {
  nueva_prueba t3
  local perfil="$BANCO_TMP/t3/perfil"
  mkdir -p "$perfil"
  local ruta
  ruta="$(con_informe "$perfil" "
    bc_informe_abrir 'Alta' 'servidor.example.org'
    bc_informe_dato 'Contraseña del repositorio' '' '$CLAVE_DE_PRUEBA'
    bc_informe_cerrar HECHO
  ")"
  afirmar_no_contiene "$ruta" "$CLAVE_DE_PRUEBA" \
    "la contraseña NO aparece en el informe"
  afirmar_contiene "$ruta" "presente \(${#CLAVE_DE_PRUEBA} caracteres\)" \
    "en su lugar se anota que está y cuánto mide"
}

# Y la segunda defensa: un valor marcado como secreto se tacha aunque entre por
# una etiqueta que no lo parece, o dentro de una orden.
test_a_registered_secret_is_scrubbed_everywhere() {
  nueva_prueba t4
  local perfil="$BANCO_TMP/t4/perfil"
  mkdir -p "$perfil"
  local ruta
  ruta="$(con_informe "$perfil" "
    bc_informe_abrir 'Alta' 'servidor.example.org'
    bc_informe_ocultar '$CLAVE_DE_PRUEBA'
    bc_informe_dato 'Endpoint' '' 'https://s3.example.org/$CLAVE_DE_PRUEBA'
    bc_informe_orden 'rclone config create almacen s3 secret_access_key $CLAVE_DE_PRUEBA'
    bc_informe_cerrar HECHO
  ")"
  afirmar_no_contiene "$ruta" "$CLAVE_DE_PRUEBA" \
    "el secreto registrado no aparece ni en un valor ni en una orden"
  afirmar_contiene "$ruta" "oculto: ${#CLAVE_DE_PRUEBA} caracteres" \
    "queda constancia de que ahí había algo"
}

# Perder el registro de una operación que YA se hizo no puede tumbar la
# operación: se avisa y el informe sale por pantalla.
test_an_unwritable_destination_does_not_fail_the_operation() {
  nueva_prueba t5
  local perfil="$BANCO_TMP/t5/perfil"
  mkdir -p "$perfil"
  # Un archivo donde debería ir el directorio: mkdir -p no puede con esto.
  : > "$perfil/informes"

  local salida
  salida="$(con_informe "$perfil" '
    bc_informe_abrir "Alta" "servidor.example.org"
    bc_informe_paso "Registrar" HECHO "quedó registrado"
    bc_informe_cerrar HECHO
    echo "CODIGO:$?"
  ')"
  echo "$salida" > "$BANCO_TMP/t5/salida.log"

  afirmar_contiene "$BANCO_TMP/t5/salida.log" "CODIGO:0" \
    "cerrar el informe no falla aunque no se pueda escribir"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "no se pudo guardar el informe" \
    "y se avisa de que no se guardó"
  afirmar_contiene "$BANCO_TMP/t5/salida.log" "Registrar .* HECHO" \
    "el informe sale por pantalla, que es lo que había que salvar"
}

# El temporal no se queda por ahí: se apunta al registro de limpiezas y se
# suelta al cerrar.
test_the_temporary_file_is_not_left_behind() {
  nueva_prueba t6
  local perfil="$BANCO_TMP/t6/perfil"
  mkdir -p "$perfil"
  local salida
  salida="$(con_informe "$perfil" '
    bc_informe_abrir "Alta" "servidor.example.org"
    tmp="$BC_INFORME_TMP"
    bc_informe_paso "Registrar" HECHO "hecho"
    bc_informe_cerrar HECHO >/dev/null
    echo "EXISTE:$([[ -e "$tmp" ]] && echo si || echo no)"
    echo "REGISTRADAS:${#BC_CLEANUP_KEYS[@]}"
  ')"
  echo "$salida" > "$BANCO_TMP/t6/salida.log"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "EXISTE:no" "el temporal se borró al cerrar"
  afirmar_contiene "$BANCO_TMP/t6/salida.log" "REGISTRADAS:0" \
    "y su limpieza ya no está registrada"
}

# Un informe que nadie abrió no revienta: las primitivas se callan. Un informe
# es el registro de una operación, no la operación.
test_primitives_are_silent_without_an_open_report() {
  nueva_prueba t7
  local perfil="$BANCO_TMP/t7/perfil"
  mkdir -p "$perfil"
  local salida
  salida="$(con_informe "$perfil" '
    bc_informe_paso "Registrar" HECHO "hecho"
    bc_informe_dato "Repositorio" "a" "b"
    bc_informe_cerrar HECHO
    echo "CODIGO:$?"
  ')"
  echo "$salida" > "$BANCO_TMP/t7/salida.log"
  afirmar_contiene "$BANCO_TMP/t7/salida.log" "CODIGO:0" \
    "sin informe abierto, las primitivas no fallan"
}

test_a_full_report_contains_every_element
test_an_empty_before_does_not_shift_the_columns
test_a_password_never_reaches_the_file
test_a_registered_secret_is_scrubbed_everywhere
test_an_unwritable_destination_does_not_fail_the_operation
test_the_temporary_file_is_not_left_behind
test_primitives_are_silent_without_an_open_report

fin_de_suite
