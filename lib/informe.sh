#!/usr/bin/env bash
# =============================================================================
# lib/informe.sh — el informe de lo que se hizo (ADR 0014)
# =============================================================================
# Cuando esta herramienta escribe en un servidor, lo que el usuario necesita
# después no es un «listo»: es qué había antes, qué hay ahora, con qué orden se
# cambió y cómo se deshace. Eso es este informe.
#
# CÓMO SE USA
#   bc_informe_abrir "Registrar el host de respaldo" "servidor.example.org"
#   bc_informe_dato  "Repositorio" "$antes" "$despues"
#   bc_informe_orden "v-add-backup-host-restic ..."
#   bc_informe_copia "/usr/local/hestia/conf/restic.conf" "...restic.conf.20260923"
#   bc_informe_paso  "Registrar" HECHO "el repositorio quedó registrado"
#   bc_informe_deshacer "v-delete-backup-host-restic"
#   ruta="$(bc_informe_cerrar "HECHO")"
#
# LOS DATOS PRIMERO, EL MARKDOWN AL FINAL
#   Lo que se va acumulando en el temporal son registros con campos separados,
#   no texto ya maquetado. El Markdown se compone entero al cerrar. Así el orden
#   del informe no depende del orden en que ocurrieron las cosas, y quien
#   quiera otra presentación (la web) parte de los mismos datos.
#
# NINGÚN SECRETO, NUNCA
#   Este archivo acaba en el directorio del perfil, que está versionado. Una
#   contraseña aquí es una contraseña publicada. Hay dos defensas:
#     - por la ETIQUETA: un valor cuyo nombre habla de contraseñas o claves se
#       anota como «presente (N caracteres)», nunca por su valor;
#     - por el VALOR: lo que se registre con bc_informe_ocultar se tacha en
#       todo el informe, lo escriba quien lo escriba.
#   La primera no distingue una «clave de cifrado» de una «ruta de la clave»:
#   tacha las dos. Es a propósito — el lado seguro—, y por eso las etiquetas de
#   cosas que no son secretas se escriben sin esas palabras.
# =============================================================================

[[ -n "${BC_INFORME_LOADED:-}" ]] && return 0
BC_INFORME_LOADED=1

BC_INFORME_TMP=""
BC_INFORME_ACCION=""
BC_INFORME_DESTINO=""
BC_INFORME_CUANDO=""
BC_INFORME_SECRETOS=()

# Etiquetas cuyo VALOR no se escribe nunca.
BC_INFORME_RE_SECRETO='contrase|password|passwd|clave|secret|token|api[-_ ]?key|llave'

# -----------------------------------------------------------------------------
# Abrir y acumular
# -----------------------------------------------------------------------------
# $1 acción (lo que se está haciendo)   $2 destino (servidor, cuenta, …)
bc_informe_abrir() {
  BC_INFORME_ACCION="${1:-operación}"
  BC_INFORME_DESTINO="${2:-}"
  BC_INFORME_CUANDO="$(date '+%Y-%m-%d %H:%M:%S')"
  BC_INFORME_SECRETOS=()
  BC_INFORME_TMP="$(mktemp)" || { BC_INFORME_TMP=""; return 1; }
  # El temporal se apunta al registro de limpiezas (ADR 0012), que sobrevive a
  # un bc_die y a un Ctrl-C. Un `trap … RETURN` aquí no serviría: bc_die sale
  # con exit y nunca lo dispararía.
  bc_cleanup_register "informe:$BC_INFORME_TMP" "rm -f $(printf '%q' "$BC_INFORME_TMP")"
  return 0
}

# ¿Hay un informe abierto? Las primitivas no fallan si no lo hay: se callan.
# Un informe es el registro de una operación, no la operación.
bc_informe_activo() { [[ -n "$BC_INFORME_TMP" && -f "$BC_INFORME_TMP" ]]; }

# Registro interno: tipo + campos, separados por el carácter de unidad (0x1F).
#
# NO se usa un tabulador, y el motivo no es estético: el tabulador es un
# espacio en blanco para IFS, y bash COLAPSA las series de separadores en
# blanco al leer. Con tabuladores, un campo vacío en medio desaparece y todos
# los de detrás se corren un sitio:
#   IFS=$'\t'   read -r a b c <<< "dato<TAB><TAB>valor"  -> b=valor, c=vacío
#   IFS=$'\x1f' read -r a b c <<< "dato<US><US>valor"    -> b=vacío, c=valor
# Un «antes» vacío es justo lo normal al registrar algo por primera vez, así
# que con tabuladores el informe enseñaría el valor nuevo en la columna del
# viejo. Lo que venga dentro de un valor se limpia antes de escribirlo.
BC_INFORME_SEP=$'\x1f'

bc_informe_registro() {
  bc_informe_activo || return 0
  local campo linea=""
  for campo in "$@"; do
    linea+="${campo//$BC_INFORME_SEP/ }$BC_INFORME_SEP"
  done
  printf '%s\n' "${linea%$BC_INFORME_SEP}" >> "$BC_INFORME_TMP"
}

# Un valor a registrar no puede llevar saltos de línea: partirían el registro.
bc_informe_llano() { printf '%s' "${1//$'\n'/ }"; }

# Marca un valor como secreto: se tacha en TODO el informe al cerrar, lo
# escriba quien lo escriba y con la etiqueta que sea.
bc_informe_ocultar() {
  local valor="${1:-}"
  [[ -n "$valor" ]] || return 0
  BC_INFORME_SECRETOS+=("$valor")
}

# Cómo se anota un valor cuya etiqueta dice que es un secreto.
bc_informe_presencia() {
  local valor="${1:-}"
  if [[ -z "$valor" ]]; then echo "ausente"
  else echo "presente (${#valor} caracteres)"
  fi
}

# $1 qué es   $2 valor antes   $3 valor después
bc_informe_dato() {
  local que="${1:-}" antes="${2:-}" despues="${3:-}"
  if [[ "${que,,}" =~ $BC_INFORME_RE_SECRETO ]]; then
    antes="$(bc_informe_presencia "$antes")"
    despues="$(bc_informe_presencia "$despues")"
  fi
  bc_informe_registro dato "$(bc_informe_llano "$que")" \
    "$(bc_informe_llano "$antes")" "$(bc_informe_llano "$despues")"
}

# $1 la orden ejecutada, tal cual, SIN secretos dentro
bc_informe_orden() { bc_informe_registro orden "$(bc_informe_llano "${1:-}")"; }

# $1 el archivo original en el servidor   $2 la copia fechada que se dejó
bc_informe_copia() {
  bc_informe_registro copia "$(bc_informe_llano "${1:-}")" "$(bc_informe_llano "${2:-}")"
}

# $1 etiqueta   $2 estado (SIN_CAMBIO|HECHO|SIN_CONFIRMAR|FALLO|CIEGO)   $3 detalle
bc_informe_paso() {
  bc_informe_registro paso "$(bc_informe_llano "${1:-}")" \
    "$(bc_informe_llano "${2:-}")" "$(bc_informe_llano "${3:-}")"
}

# $1 cómo se revierte, en órdenes concretas
bc_informe_deshacer() { bc_informe_registro deshacer "$(bc_informe_llano "${1:-}")"; }

# -----------------------------------------------------------------------------
# Cerrar
# -----------------------------------------------------------------------------
# Compone el Markdown, lo escribe en <Perfil>/informes/ y devuelve su ruta por
# la salida estándar.
#
# Si no se puede escribir el archivo, la orden NO falla por eso: se avisa y el
# informe sale por pantalla (por stderr, para no ensuciar la ruta que esta
# función devuelve). Perder el registro de una operación que ya se hizo no
# puede tumbar la operación.
bc_informe_cerrar() {
  local resultado="${1:-}"
  bc_informe_activo || return 0

  local cuerpo; cuerpo="$(bc_informe_componer "$resultado")"

  local dir="${BC_PROFILE_DIR:-}/informes"
  local nombre archivo
  nombre="$(date -d "$BC_INFORME_CUANDO" '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%Y%m%d-%H%M%S')"
  nombre+="-$(bc_informe_nombre_seguro "$BC_INFORME_ACCION").md"
  archivo="$dir/$nombre"

  if [[ -n "${BC_PROFILE_DIR:-}" ]] && mkdir -p "$dir" 2>/dev/null \
     && printf '%s\n' "$cuerpo" > "$archivo" 2>/dev/null; then
    bc_informe_soltar
    printf '%s\n' "$archivo"
    return 0
  fi

  bc_warn "no se pudo guardar el informe en ${dir:-<sin perfil>}: va por pantalla."
  printf '%s\n' "$cuerpo" >&2
  bc_informe_soltar
  return 0
}

# Suelta el temporal y su limpieza registrada.
bc_informe_soltar() {
  [[ -n "$BC_INFORME_TMP" ]] || return 0
  rm -f "$BC_INFORME_TMP"
  bc_cleanup_forget "informe:$BC_INFORME_TMP"
  BC_INFORME_TMP=""
}

# Un nombre de archivo sin sorpresas a partir de la acción.
bc_informe_nombre_seguro() {
  local v="${1:-operacion}"
  v="${v// /-}"
  v="$(tr -cd 'A-Za-z0-9._-' <<<"$v")"
  printf '%s' "${v:-operacion}"
}

# Tacha del texto todo lo que se haya marcado como secreto. Se hace al final,
# sobre el informe entero: así da igual por qué primitiva entró.
bc_informe_tachar() {
  local texto="$1" secreto
  for secreto in ${BC_INFORME_SECRETOS+"${BC_INFORME_SECRETOS[@]}"}; do
    [[ -n "$secreto" ]] || continue
    texto="${texto//"$secreto"/«oculto: ${#secreto} caracteres»}"
  done
  printf '%s' "$texto"
}

# Compone el Markdown a partir de los registros acumulados. Solo saca las
# secciones que tienen algo: un informe con apartados vacíos se lee peor.
bc_informe_componer() {
  local resultado="${1:-}"
  local salida="# ${BC_INFORME_ACCION}"
  [[ -n "$BC_INFORME_DESTINO" ]] && salida+=" — ${BC_INFORME_DESTINO}"
  salida+=$'\n\n'
  salida+="- **Cuándo:** ${BC_INFORME_CUANDO}"$'\n'
  [[ -n "${BC_PROFILE:-}" ]] && salida+="- **Perfil:** ${BC_PROFILE}"$'\n'
  [[ -n "$resultado" ]] && salida+="- **Resultado:** ${resultado}"$'\n'

  local tipo a b c
  local pasos="" datos="" ordenes="" copias="" deshacer=""
  while IFS="$BC_INFORME_SEP" read -r tipo a b c; do
    case "$tipo" in
      paso)     pasos+="| ${a} | ${b} | ${c} |"$'\n' ;;
      dato)     datos+="| ${a} | ${b} | ${c} |"$'\n' ;;
      orden)    ordenes+="${a}"$'\n' ;;
      copia)    copias+="| ${a} | ${b} |"$'\n' ;;
      deshacer) deshacer+="${a}"$'\n' ;;
    esac
  done < "$BC_INFORME_TMP"

  if [[ -n "$pasos" ]]; then
    salida+=$'\n'"## Pasos"$'\n\n'"| Paso | Estado | Detalle |"$'\n'"| --- | --- | --- |"$'\n'"$pasos"
  fi
  if [[ -n "$datos" ]]; then
    salida+=$'\n'"## Qué cambió"$'\n\n'"| Qué | Antes | Después |"$'\n'"| --- | --- | --- |"$'\n'"$datos"
  fi
  if [[ -n "$ordenes" ]]; then
    salida+=$'\n'"## Órdenes ejecutadas"$'\n\n'"\`\`\`"$'\n'"$ordenes"'```'$'\n'
  fi
  if [[ -n "$copias" ]]; then
    salida+=$'\n'"## Copias dejadas en el servidor"$'\n\n'"| Original | Copia |"$'\n'"| --- | --- |"$'\n'"$copias"
  fi
  if [[ -n "$deshacer" ]]; then
    salida+=$'\n'"## Cómo deshacerlo"$'\n\n'"\`\`\`"$'\n'"$deshacer"'```'$'\n'
  fi

  bc_informe_tachar "$salida"
}
