#!/bin/bash

# ============================================================
# LECTURA DE CONFIGURACIÓN DE APLICACIONES
# ============================================================
#
# Define funciones para leer, SIN modificar nada, las
# credenciales que tiene escritas una aplicación.
#
# Lo usan:
#
#   BASE_GENERAL.sh    para leer el servidor ORIGEN y armar
#                       las equivalencias
#
#   BASE_VERIFICAR.sh  para leer el servidor DESTINO y
#                       comprobar el resultado
#
#
# ============================================================
#
# FUNCIONES
#
#   leer_config_local ARCHIVO TIPO
#   leer_config_origen ARCHIVO TIPO
#
# Ambas imprimen tres líneas:
#
#   DB=...
#   USER=...
#   HOST=...
#
# La contraseña NUNCA se lee ni se imprime. No hace falta
# para nada: las credenciales nuevas ya las conocemos y las
# viejas no se usan.
#
# ============================================================



LEER_TMP="$(mktemp -d)";

LEER_PHP="$LEER_TMP/leer_config.php";


cat > "$LEER_PHP" <<'PHP'
<?php

/*
 * Uso: leer_config.php ARCHIVO FORMATO
 *
 * Se queda con la ÚLTIMA aparición de cada campo, que es la
 * configuración de producción cuando el archivo tiene varias.
 */

if ($argc !== 3) {
    fwrite(STDERR, "Uso: leer_config.php ARCHIVO FORMATO\n");
    exit(1);
}

$file = $argv[1];
$format = $argv[2];

if (!is_file($file)) {
    fwrite(STDERR, "No existe: {$file}\n");
    exit(1);
}

$content = file_get_contents($file);


$php = function (string $field): string {
    return
        '~\$config\s*\[\s*[\'"]database[\'"]\s*\]'
        . '\s*\[\s*[\'"]default[\'"]\s*\]'
        . '\s*\[\s*[\'"]' . preg_quote($field, '~') . '[\'"]\s*\]'
        . '\s*=\s*[\'"](.*?)[\'"]\s*;~';
};

$def = function (string $constant): string {
    return
        '~define\s*\(\s*[\'"]' . preg_quote($constant, '~') . '[\'"]'
        . '\s*,\s*[\'"](.*?)[\'"]\s*\)\s*;~';
};

$prop = function (string $property): string {
    return
        '~(?:public|var)\s+\$' . preg_quote($property, '~')
        . '\s*=\s*[\'"](.*?)[\'"]\s*;~';
};

$arr = function (string $key): string {
    return '~[\'"]' . preg_quote($key, '~') . '[\'"]\s*=>\s*[\'"](.*?)[\'"]~';
};

$env = function (string $key): string {
    return '~^[ \t]*' . preg_quote($key, '~') . '[ \t]*=[ \t]*"?([^"\r\n]*)"?[ \t]*$~m';
};

/*
 * CodeIgniter 3, las dos formas de su database.php:
 *
 *   $db['default'] = array('database' => 'valor', ...);
 *   $db['default']['database'] = 'valor';
 *
 * El (?|...) es un branch reset de PCRE: las dos ramas comparten
 * la numeración de grupos, así que el valor es $m[1] venga de la
 * forma que venga.
 *
 * La primera rama no cruza a otro grupo: (?!\$db\s*\[) corta
 * antes de un $db['otro'] que viniera detrás.
 */

$ci3 = function (string $key): string {

    $k = preg_quote($key, '~');

    return
        '~(?|'
        . '\$db\s*\[\s*[\'"]default[\'"]\s*\]\s*=\s*(?:array\s*\(|\[)'
        . '(?:(?!\$db\s*\[)[\s\S])*?'
        . '[\'"]' . $k . '[\'"]\s*=>\s*[\'"](.*?)[\'"]'
        . '|'
        . '\$db\s*\[\s*[\'"]default[\'"]\s*\]\s*\[\s*[\'"]' . $k . '[\'"]\s*\]'
        . '\s*=\s*[\'"](.*?)[\'"]\s*;'
        . ')~';
};


$formats = [
    'piecesphp'    => ['db' => $php('db'),            'user' => $php('user'),            'host' => $php('host')],
    'wordpress'    => ['db' => $def('DB_NAME'),       'user' => $def('DB_USER'),         'host' => $def('DB_HOST')],
    'joomla'       => ['db' => $prop('db'),           'user' => $prop('user'),           'host' => $prop('host')],
    'prestashop'   => ['db' => $arr('database_name'), 'user' => $arr('database_user'),   'host' => $arr('database_host')],
    'prestashop16' => ['db' => $def('_DB_NAME_'),     'user' => $def('_DB_USER_'),       'host' => $def('_DB_SERVER_')],
    'laravel'      => ['db' => $env('DB_DATABASE'),   'user' => $env('DB_USERNAME'),     'host' => $env('DB_HOST')],
    'drupal'       => ['db' => $arr('database'),      'user' => $arr('username'),       'host' => $arr('host')],
    'codeigniter3' => ['db' => $ci3('database'),      'user' => $ci3('username'),       'host' => $ci3('hostname')],
];


/*
 * ------------------------------------------------------------
 * GUARDAS POR FORMATO
 * ------------------------------------------------------------
 *
 * Condiciones que se comprueban antes de leer nada. Cada
 * formato tiene una LISTA de guardas; cada una recibe el
 * contenido y devuelve el motivo del rechazo, o null.
 *
 * Si un formato no define guardas, aquí no pasa nada: los
 * formatos anteriores a esto se comportan igual que siempre.
 * ------------------------------------------------------------
 */

$ci3Cuerpo = function (string $content): string {

    $re =
        '~\$db\s*\[\s*[\'"]default[\'"]\s*\]\s*=\s*(?:array\s*\(|\[)'
        . '((?:(?!\$db\s*\[)[\s\S])*)~';

    if (preg_match($re, $content, $m)) {
        return $m[1];
    }

    return '';
};

$ci3Repetidas = function (string $content, array $claves) use ($ci3Cuerpo): ?string {

    $cuerpo = $ci3Cuerpo($content);

    foreach ($claves as $clave) {

        $k = preg_quote($clave, '~');

        $n = 0;

        if ($cuerpo !== '') {
            $n += preg_match_all('~[\'"]' . $k . '[\'"]\s*=>~', $cuerpo);
        }

        $n += preg_match_all(
            '~\$db\s*\[\s*[\'"]default[\'"]\s*\]\s*\[\s*[\'"]' . $k . '[\'"]\s*\]\s*=~',
            $content
        );

        if ($n > 1) {

            return sprintf(
                "la clave '%s' aparece %d veces en el grupo default: revisar a mano",
                $clave,
                $n
            );

        }

    }

    return null;
};


$guards = [];

$guards['codeigniter3'] = [

    /*
     * El grupo activo. Con otro grupo activo, leer el de default
     * daría las credenciales de una base que no es la que usa la
     * aplicación: se migraría la base equivocada sin un solo
     * error. Mejor no devolver nada.
     *
     * Si $active_group no aparece, CodeIgniter usa 'default'.
     */

    function (string $content): ?string {

        if (
            preg_match('~\$active_group\s*=\s*[\'"]([^\'"]*)[\'"]~', $content, $m)
            && $m[1] !== 'default'
        ) {

            return sprintf(
                "active_group es '%s', no 'default': revisar a mano",
                $m[1]
            );

        }

        return null;
    },


    /*
     * Claves repetidas. Aquí entra también hostname, que esta
     * lectura devuelve: con dos hostname se leería el del grupo
     * equivocado y la comprobación posterior compararía contra
     * un host que la aplicación no usa.
     */

    function (string $content) use ($ci3Repetidas): ?string {

        return $ci3Repetidas($content, ['database', 'username', 'hostname']);
    },

];


if (!isset($formats[$format])) {
    fwrite(STDERR, "Formato desconocido: {$format}\n");
    exit(1);
}


if (isset($guards[$format])) {

    foreach ($guards[$format] as $guard) {

        $motivo = $guard($content);

        if ($motivo !== null) {

            fwrite(STDERR, $motivo . "\n");

            exit(1);
        }

    }

}


foreach (['db', 'user', 'host'] as $campo) {

    $encontrado = '';

    if (preg_match_all($formats[$format][$campo], $content, $m)) {
        $encontrado = end($m[1]);
    }

    echo strtoupper($campo) . "={$encontrado}\n";
}
PHP


chmod 700 "$LEER_PHP";



# ------------------------------------------------------------
# Lee un archivo de configuración de ESTE servidor.
# ------------------------------------------------------------

leer_config_local() {

  local archivo="$1";
  local tipo="$2";

  if [ ! -f "$archivo" ]; then
    return 1;
  fi;

  php "$LEER_PHP" "$archivo" "$tipo" 2>/dev/null;

}


# ------------------------------------------------------------
# Lee un archivo de configuración del servidor ORIGEN.
#
# Se trae una copia temporal y se lee aquí, para no exigir
# que el origen tenga PHP disponible.
#
# La copia se borra de inmediato.
# ------------------------------------------------------------

leer_config_origen() {

  local archivo="$1";
  local tipo="$2";

  local copia="$LEER_TMP/origen_$$_$RANDOM";


  if ! origen_exec "cat $(printf '%q' "$archivo")" "" \
       </dev/null > "$copia" 2>/dev/null; then

    rm -f "$copia";

    return 1;

  fi;


  if [ ! -s "$copia" ]; then

    rm -f "$copia";

    return 1;

  fi;


  chmod 600 "$copia";


  php "$LEER_PHP" "$copia" "$tipo" 2>/dev/null;

  local resultado=$?;


  rm -f "$copia";


  return "$resultado";

}


# ------------------------------------------------------------
# Extrae un campo del resultado de las funciones anteriores.
#
#   valor_de "$LEIDO" DB
# ------------------------------------------------------------

valor_de() {

  echo "$1" | grep "^$2=" | cut -d= -f2-;

}


leer_config_cleanup() {

  if [ -n "$LEER_TMP" ]; then
    rm -rf "$LEER_TMP";
    LEER_TMP="";
  fi;

}
