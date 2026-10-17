#!/usr/bin/env bash
# =============================================================================
# tests/probar_migracion_plan_dominio.sh — plan_dominio_existe
# =============================================================================
# El defecto que esto cierra: cuando el dominio NO existe, HestiaCP contesta
# "Error: web domain <dominio> doesn't exist" por la salida ESTÁNDAR, no por
# la de error, y con código 3. hestia_salida no filtra nada en modo cli
# (BASE_PRIVILEGIOS.sh, rama else), así que buscar el nombre del dominio en
# esa salida lo encontraba DENTRO del mensaje de error y la función respondía
# «existe» para todo dominio nuevo. Consecuencia: el plan anunciaba «ya
# existe, se omitirá» para dominios que había que crear, y verificar daba por
# bueno un dominio inexistente.
#
# Aquí no se habla con ningún HestiaCP: se extrae la función de su archivo y
# se le pone delante una hestia_salida falsa que devuelve salidas enlatadas.
# La del caso E2 es la que HestiaCP imprime de verdad, citada en
# .agents/context/50-hestiacp.md.
#
# E5 es el control del defecto: la MISMA prueba contra la función anterior al
# arreglo, extraída del commit donde todavía estaba mal. Sin ese caso, esta
# suite no demostraría que el arreglo arregla algo.
# =============================================================================
set -u

if [[ -z "${BANCO_RAIZ:-}" || ! -f "$BANCO_RAIZ/tests/lib.sh" ]]; then
  echo "probar_migracion_plan_dominio.sh: \$BANCO_RAIZ no está definida o tests/lib.sh no existe ahí." >&2
  exit 2
fi
# shellcheck source=./lib.sh
source "$BANCO_RAIZ/tests/lib.sh" || exit 2

echo "== probar_migracion_plan_dominio =="

MIG="$BANCO_RAIZ/tools/migracion-caliente"

# Commit con la función TODAVÍA defectuosa, para el control E5.
BASE_CON_DEFECTO="96e7908"

# -----------------------------------------------------------------------------
# Extracción de la función
# -----------------------------------------------------------------------------
# De su línea de apertura hasta la primera línea que es solo "}". Por
# marcadores, no por número de línea: cualquier añadido al archivo los mueve.
extraer_funcion() {
  local archivo="$1" destino="$2"
  awk '
    $0 == "plan_dominio_existe() {" { dentro = 1 }
    dentro { print }
    dentro && $0 == "}" { exit }
  ' "$archivo" > "$destino"
}

FUNCION="$BANCO_TMP/plan_dominio_existe.sh"
extraer_funcion "$MIG/BASE_PLAN.sh" "$FUNCION"

# -----------------------------------------------------------------------------
# Salidas enlatadas
# -----------------------------------------------------------------------------
# La ficha json tal como la arma HestiaCP: el dominio es una CLAVE, y por eso
# va entre comillas dobles. Valores recortados a lo que importa aquí.
json_de() {
  printf '{\n    "%s": {\n        "IP": "203.0.113.10",\n        "SSL": "yes",\n        "BACKEND": "PHP-8_1"\n    }\n}\n' "$1"
}

# El mensaje real de HestiaCP cuando el objeto no existe.
error_no_existe() {
  printf 'Error: web domain %s doesn'"'"'t exist\n' "$1"
}

# Ejecuta la función extraída de $1 con la salida enlatada $2, preguntando por
# el dominio $3. Devuelve su código de salida.
#
# La función se carga en un bash aparte, con una hestia_salida falsa delante:
# así no hay forma de que llegue a ejecutar nada del panel ni de que la suite
# herede estado de una prueba anterior.
preguntar() {
  local funcion="$1" salida_enlatada="$2" dominio="$3"
  bash -c '
    hestia_salida() { printf "%s" "$BC_SALIDA_FALSA"; }
    USER_DESTINO="cuentaejemplo"
    source "$1"
    plan_dominio_existe "$2"
  ' _ "$funcion" "$dominio" 2>/dev/null
}

# -----------------------------------------------------------------------------
# La función arreglada
# -----------------------------------------------------------------------------

test_extraction_really_got_the_function() {
  nueva_prueba pd0
  afirmar_contiene "$FUNCION" "plan_dominio_existe\(\) \{" \
    "la función se extrajo de verdad"
  afirmar_contiene "$FUNCION" "v-list-web-domain" \
    "la función extraída es la que consulta el dominio"
}

# E1. La ficha json del dominio por el que se pregunta: existe.
test_json_of_the_asked_domain_means_it_exists() {
  nueva_prueba pd1
  BC_SALIDA_FALSA="$(json_de "example.org")"
  export BC_SALIDA_FALSA
  preguntar "$FUNCION" "$BC_SALIDA_FALSA" "example.org"
  afirmar_codigo 0 "$?" "E1: con la ficha json del dominio, responde que existe"
}

# E2. EL DEFECTO. El mensaje de error lleva el nombre del dominio dentro, y
# antes bastaba para que la función dijera «existe».
test_hestia_error_message_does_not_mean_it_exists() {
  nueva_prueba pd2
  BC_SALIDA_FALSA="$(error_no_existe "example.org")"
  export BC_SALIDA_FALSA
  preguntar "$FUNCION" "$BC_SALIDA_FALSA" "example.org"
  afirmar_codigo 1 "$?" \
    "E2: con 'Error: web domain example.org doesn't exist', responde que NO existe"
}

# E3. Salida vacía: no existe (y es lo que daba ya antes).
test_empty_output_means_it_does_not_exist() {
  nueva_prueba pd3
  BC_SALIDA_FALSA=""
  export BC_SALIDA_FALSA
  preguntar "$FUNCION" "$BC_SALIDA_FALSA" "example.org"
  afirmar_codigo 1 "$?" "E3: con la salida vacía, responde que NO existe"
}

# E4. La ficha de OTRO dominio no cuenta. Los dos casos que importan:
# un nombre que contiene al preguntado como sufijo (un subdominio) y uno que
# solo se le parece. El primero es el que un grep sin comillas ni -F dejaría
# pasar.
test_another_domains_record_does_not_count() {
  nueva_prueba pd4

  BC_SALIDA_FALSA="$(json_de "sub.example.org")"
  export BC_SALIDA_FALSA
  preguntar "$FUNCION" "$BC_SALIDA_FALSA" "example.org"
  afirmar_codigo 1 "$?" \
    "E4: la ficha de sub.example.org no hace existir a example.org"

  BC_SALIDA_FALSA="$(json_de "exampleXorg")"
  export BC_SALIDA_FALSA
  preguntar "$FUNCION" "$BC_SALIDA_FALSA" "example.org"
  afirmar_codigo 1 "$?" \
    "E4: la ficha de exampleXorg tampoco (el punto no es un comodín)"

  # Y al revés: preguntando por el subdominio, su propia ficha sí vale.
  BC_SALIDA_FALSA="$(json_de "sub.example.org")"
  export BC_SALIDA_FALSA
  preguntar "$FUNCION" "$BC_SALIDA_FALSA" "sub.example.org"
  afirmar_codigo 0 "$?" \
    "E4: preguntando por sub.example.org, su ficha sí dice que existe"
}

# -----------------------------------------------------------------------------
# E5 — CONTROL DEL DEFECTO
# -----------------------------------------------------------------------------
# La función de antes del arreglo, con la misma entrada de E2, tiene que
# responder 0: «existe». Si algún día esto deja de ser verdad, es que la
# extracción dejó de funcionar y E2 estaría pasando en verde por nada.
test_the_old_function_had_the_bug() {
  nueva_prueba pd5
  local d="$BANCO_TMP/pd5"

  git -C "$BANCO_RAIZ" show \
    "$BASE_CON_DEFECTO:tools/migracion-caliente/BASE_PLAN.sh" \
    > "$d/BASE_PLAN.anterior.sh" 2>/dev/null

  afirmar_existe "$d/BASE_PLAN.anterior.sh" \
    "E5: se recuperó BASE_PLAN.sh de $BASE_CON_DEFECTO"

  local anterior="$d/plan_dominio_existe.anterior.sh"
  extraer_funcion "$d/BASE_PLAN.anterior.sh" "$anterior"

  afirmar_contiene "$anterior" "v-list-web-domain" \
    "E5: la función anterior se extrajo de verdad"
  afirmar_no_contiene "$anterior" 'grep -qF' \
    "E5: la función anterior no tenía el arreglo"

  BC_SALIDA_FALSA="$(error_no_existe "example.org")"
  export BC_SALIDA_FALSA
  preguntar "$anterior" "$BC_SALIDA_FALSA" "example.org"
  afirmar_codigo 0 "$?" \
    "E5: la función ANTERIOR decía que existe ante el mensaje de error (el defecto)"
}

test_extraction_really_got_the_function
test_json_of_the_asked_domain_means_it_exists
test_hestia_error_message_does_not_mean_it_exists
test_empty_output_means_it_does_not_exist
test_another_domains_record_does_not_count
test_the_old_function_had_the_bug

fin_de_suite
