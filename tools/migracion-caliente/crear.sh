#!/bin/bash

# ============================================================
# CREAR UNA MIGRACIÓN
# ============================================================
#
#   ./crear.sh
#
# Abre una interfaz local en el navegador para armar el
# archivo de migración: servidores, dominios, bases, correo
# y cronjobs.
#
# El archivo se va escribiendo a la vista mientras rellenas.
# Al guardar, queda en el directorio actual y, si lo pides,
# se construye el paquete.
#
#
# ============================================================
#
# ES VOLÁTIL
#
#   El servidor escucha solo en 127.0.0.1, en un puerto
#   aleatorio, y se apaga en cuanto guardas.
#
#   Todo lo que crea vive en un directorio temporal que se
#   borra al salir. Lo único que queda es el archivo de
#   migración.
#
#
# REQUISITOS
#
#   python3, que trae su propio servidor HTTP. Nada más.
#
# ============================================================


set -u


DIR_FUENTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";

DESTINO="$PWD";


if ! command -v python3 >/dev/null 2>&1; then

  echo;
  echo "ERROR: hace falta python3.";
  echo;
  echo "Solo se usa para servir la interfaz en local.";
  echo;

  exit 1;

fi;


TMP="$(mktemp -d)";

limpiar() {
  rm -rf "$TMP";
}

trap limpiar EXIT;



# ============================================================
# === INTERFAZ ===
# ============================================================

cat > "$TMP/index.html" <<'FIN_HTML'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nueva migración</title>
<style>
  :root {
    --tinta: #16222E;
    --tinta-suave: #44586B;
    --papel: #E9EDF0;
    --superficie: #FFFFFF;
    --linea: #C9D3DB;
    --pino: #2E6E4E;
    --granate: #8C2F2F;
    --ambar: #8A6D1F;
  }

  * { box-sizing: border-box; }

  html, body { height: 100%; }

  body {
    margin: 0;
    background: var(--papel);
    color: var(--tinta);
    font: 15px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  }

  .marco {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 34rem);
    height: 100vh;
  }

  .panel {
    overflow-y: auto;
    padding: 2rem 2.25rem 6rem;
  }

  .archivo {
    background: var(--tinta);
    color: #C6D4DF;
    overflow-y: auto;
    padding: 1.5rem 1.75rem 6rem;
    font: 12.5px/1.7 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    white-space: pre-wrap;
    word-break: break-word;
  }

  h1 {
    font-size: 1.45rem;
    font-weight: 600;
    letter-spacing: -0.01em;
    margin: 0 0 .35rem;
  }

  .intro {
    color: var(--tinta-suave);
    margin: 0 0 2rem;
    max-width: 52ch;
  }

  h2 {
    font-size: 1rem;
    font-weight: 600;
    margin: 2.25rem 0 .9rem;
    padding-bottom: .4rem;
    border-bottom: 1px solid var(--linea);
  }

  h2:first-of-type { margin-top: 0; }

  .ayuda {
    color: var(--tinta-suave);
    font-size: .85rem;
    margin: -.55rem 0 .9rem;
    max-width: 60ch;
  }

  .rejilla {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
    gap: .75rem;
  }

  label {
    display: block;
    font-size: .8rem;
    color: var(--tinta-suave);
    margin-bottom: .2rem;
  }

  input[type=text], input[type=password], select {
    width: 100%;
    padding: .45rem .55rem;
    border: 1px solid var(--linea);
    border-radius: 3px;
    background: var(--superficie);
    color: var(--tinta);
    font: inherit;
    font-size: .9rem;
  }

  input:focus-visible, select:focus-visible, button:focus-visible {
    outline: 2px solid var(--pino);
    outline-offset: 1px;
  }

  .interruptores {
    display: flex;
    flex-wrap: wrap;
    gap: .35rem .9rem;
    margin-top: .6rem;
  }

  .interruptor {
    display: inline-flex;
    align-items: center;
    gap: .35rem;
    font-size: .85rem;
    color: var(--tinta);
  }

  .interruptor input { accent-color: var(--pino); }

  .interruptor.riesgo { color: var(--granate); }
  .interruptor.riesgo input { accent-color: var(--granate); }

  .bloque {
    background: var(--superficie);
    border: 1px solid var(--linea);
    border-left: 4px solid var(--pino);
    border-radius: 3px;
    padding: .9rem 1rem;
    margin-bottom: .75rem;
  }

  .bloque.solocorreo { border-left-color: var(--ambar); }
  .bloque.destructivo { border-left-color: var(--granate); }

  .bloque-cab {
    display: flex;
    align-items: baseline;
    gap: .6rem;
    margin-bottom: .7rem;
  }

  .orden {
    font: 600 .8rem/1 ui-monospace, monospace;
    color: var(--tinta-suave);
    min-width: 1.4rem;
  }

  .bloque-cab input { flex: 1; }

  .avanzado {
    margin-top: .7rem;
    border-top: 1px dashed var(--linea);
    padding-top: .7rem;
  }

  summary {
    cursor: pointer;
    font-size: .82rem;
    color: var(--tinta-suave);
  }

  button {
    font: inherit;
    font-size: .88rem;
    padding: .45rem .85rem;
    border-radius: 3px;
    border: 1px solid var(--linea);
    background: var(--superficie);
    color: var(--tinta);
    cursor: pointer;
  }

  button:hover { border-color: var(--tinta-suave); }

  .quitar {
    border: none;
    background: none;
    color: var(--granate);
    padding: .2rem .3rem;
    font-size: .82rem;
  }

  .barra {
    position: fixed;
    left: 0;
    bottom: 0;
    width: calc(100% - 34rem);
    display: flex;
    align-items: center;
    gap: .9rem;
    padding: .8rem 2.25rem;
    background: var(--superficie);
    border-top: 1px solid var(--linea);
  }

  .guardar {
    background: var(--pino);
    border-color: var(--pino);
    color: #fff;
    font-weight: 600;
  }

  .guardar:hover { background: #245840; }

  .estado {
    font-size: .85rem;
    color: var(--tinta-suave);
  }

  .estado.error { color: var(--granate); }
  .estado.ok { color: var(--pino); }

  .c-com { color: #6E8598; }
  .c-var { color: #9FC7E8; }
  .c-tex { color: #A9D9B4; }
  .c-fun { color: #E8C77B; }

  @media (max-width: 60rem) {
    .marco { grid-template-columns: 1fr; height: auto; }
    .archivo { max-height: 22rem; }
    .barra { width: 100%; position: static; }
  }
</style>
</head>
<body>
<div class="marco">

  <div class="panel">
    <h1>Nueva migración</h1>
    <p class="intro">Rellena lo que sepas. A la derecha se va escribiendo el archivo
    que vas a guardar, así que puedes leerlo antes de generarlo.</p>

    <h2>Archivo</h2>
    <div class="rejilla">
      <div>
        <label for="nombre">Nombre</label>
        <input type="text" id="nombre" value="migracion-cliente.sh">
      </div>
      <div>
        <label for="fase">Fase inicial</label>
        <select id="fase">
          <option value="1">1</option>
          <option value="plan">plan</option>
          <option value="2">2</option>
        </select>
      </div>
    </div>
    <p class="ayuda">La fase también se pasa como último argumento al ejecutar,
    y ese argumento manda sobre lo que diga el archivo.</p>

    <h2>Servidores</h2>
    <div class="rejilla">
      <div><label for="user_destino">Usuario del panel, destino</label>
        <input type="text" id="user_destino" placeholder="usuario_nuevo"></div>
      <div><label for="user_origen">Usuario del panel, origen</label>
        <input type="text" id="user_origen" placeholder="usuario_viejo"></div>
      <div><label for="ip_origen">IP del servidor viejo</label>
        <input type="text" id="ip_origen" placeholder="203.0.113.10"></div>
      <div><label for="ip_destino">IP del servidor nuevo</label>
        <input type="text" id="ip_destino" placeholder="203.0.113.20"></div>
      <div><label for="ssh_origen">Usuario SSH, origen</label>
        <input type="text" id="ssh_origen" value="root"></div>
      <div><label for="ssh_destino">Usuario SSH, destino</label>
        <input type="text" id="ssh_destino" value="root"></div>
    </div>

    <h2>Cómo se ejecuta</h2>
    <div class="interruptores">
      <label class="interruptor"><input type="checkbox" id="confirmar" checked> Pedir confirmación antes de ejecutar</label>
      <label class="interruptor"><input type="checkbox" id="renovar_ssl"> Reemitir certificados existentes</label>
      <label class="interruptor riesgo"><input type="checkbox" id="sinc_fase2"> Re-sincronizar archivos en la fase 2</label>
    </div>
    <p class="ayuda">Reemitir certificados consume cuota de Let's Encrypt.
    Re-sincronizar en la fase 2 borra lo que hayan escrito los visitantes en el
    servidor nuevo.</p>

    <h2>Cronjobs</h2>
    <div class="rejilla">
      <div>
        <label for="cronjobs">Qué hacer</label>
        <select id="cronjobs">
          <option value="preguntar">Preguntar uno a uno</option>
          <option value="todos">Migrarlos todos</option>
          <option value="ninguno">No migrar ninguno</option>
        </select>
      </div>
      <div>
        <label for="cron_usuarios">Usuarios del servidor viejo</label>
        <input type="text" id="cron_usuarios" placeholder="usuario_viejo otro_usuario">
      </div>
    </div>
    <p class="ayuda">Separados por espacios. Si lo dejas vacío se usa el usuario
    de origen. No hace falta saber qué cronjobs tiene cada uno.</p>

    <h2>Valores predeterminados</h2>
    <p class="ayuda">Los heredan todos los dominios que añadas después. En cada
    dominio solo tendrás que escribir lo que sea distinto.</p>
    <div class="rejilla">
      <div><label for="def_php">Plantilla PHP</label>
        <input type="text" id="def_php" value="PHP-8_3" list="phps"></div>
      <div><label for="def_tipo">Aplicación</label>
        <select id="def_tipo">
          <option value="piecesphp">PiecesPHP / CodeIgniter</option>
          <option value="codeigniter3">CodeIgniter 3</option>
          <option value="wordpress">WordPress</option>
          <option value="joomla">Joomla</option>
          <option value="drupal">Drupal</option>
          <option value="laravel">Laravel (.env)</option>
          <option value="prestashop">PrestaShop 1.7</option>
          <option value="prestashop16">PrestaShop 1.6</option>
          <option value="ninguno">Ninguna</option>
        </select></div>
    </div>
    <div class="interruptores">
      <label class="interruptor"><input type="checkbox" id="def_ssl" checked> Emitir SSL</label>
      <label class="interruptor"><input type="checkbox" id="def_forzar" checked> Forzar HTTPS</label>
      <label class="interruptor riesgo"><input type="checkbox" id="def_dns"> Eliminar zona DNS</label>
      <label class="interruptor riesgo"><input type="checkbox" id="def_mail"> Eliminar dominio de correo</label>
    </div>

    <datalist id="phps">
      <option value="no-php"><option value="PHP-7_4"><option value="PHP-8_0">
      <option value="PHP-8_1"><option value="PHP-8_2"><option value="PHP-8_3">
      <option value="PHP-8_4"><option value="PHP-8_5">
    </datalist>

    <h2>Dominios</h2>
    <p class="ayuda">El orden en que los añadas es el orden de la migración.
    No declares de dónde sale cada base: eso se lee del servidor viejo.</p>
    <div id="dominios"></div>
    <button type="button" onclick="anadirDominio()">Añadir dominio</button>

    <h2>Bases de datos sueltas</h2>
    <p class="ayuda">Las que no cuelgan de ningún dominio: históricas, de un cron,
    de una aplicación externa. Aquí sí hay que decir de dónde salen.</p>
    <div id="bases"></div>
    <button type="button" onclick="anadirBase()">Añadir base suelta</button>
  </div>

  <pre class="archivo" id="salida"></pre>
</div>

<div class="barra">
  <button type="button" class="guardar" onclick="guardar()">Guardar archivo</button>
  <label class="interruptor"><input type="checkbox" id="construir" checked> Construir el paquete</label>
  <span class="estado" id="estado"></span>
</div>

<script>
const $ = id => document.getElementById(id);

let contadorD = 0;
let contadorB = 0;

const TIPOS = ['piecesphp','codeigniter3','wordpress','joomla','drupal','laravel','prestashop','prestashop16','ninguno'];

function opciones(sel) {
  return TIPOS.map(t => `<option value="${t}"${t===sel?' selected':''}>${t}</option>`).join('');
}

function anadirDominio() {
  contadorD++;
  const id = 'd' + contadorD;
  const div = document.createElement('div');
  div.className = 'bloque';
  div.id = id;
  div.innerHTML = `
    <div class="bloque-cab">
      <span class="orden"></span>
      <input type="text" data-c="dominio" placeholder="example.org">
      <button type="button" class="quitar" onclick="quitar('${id}')">quitar</button>
    </div>
    <div class="rejilla">
      <div><label>Plantilla PHP</label><input type="text" data-c="php" list="phps" placeholder="heredado"></div>
      <div><label>Aplicación</label><select data-c="tipo"><option value="">heredado</option>${opciones('')}</select></div>
      <div><label>Base de datos</label><input type="text" data-c="bd" placeholder="sin base"></div>
      <div><label>Usuario de la base</label><input type="text" data-c="bd_user" placeholder="igual que la base"></div>
      <div><label>Contraseña de la base</label><input type="text" data-c="bd_pass"></div>
    </div>
    <div class="interruptores">
      <label class="interruptor"><input type="checkbox" data-c="web" checked> Tiene sitio web</label>
      <label class="interruptor">Migrar su correo <select data-c="correo">
        <option value="auto" selected>auto (si tiene cuentas)</option>
        <option value="true">sí</option><option value="false">no</option></select></label>
      <span class="ayuda" data-c="nota" style="margin:0"></span>
    </div>
    <details class="avanzado">
      <summary>Ajustes poco frecuentes</summary>
      <div class="rejilla" style="margin-top:.6rem">
        <div><label>Carpeta en el origen</label><input type="text" data-c="origen" placeholder="igual al dominio"></div>
        <div><label>Ruta de la configuración</label><input type="text" data-c="ruta_db" placeholder="según la aplicación"></div>
        <div><label>Dominio de correo en el origen</label><input type="text" data-c="correo_origen" placeholder="igual al dominio"></div>
        <div><label>Permisos</label><input type="text" data-c="chmod" placeholder="D755,F644"></div>
        <div><label>Grupo</label><input type="text" data-c="grupo" placeholder="www-data"></div>
        <div><label>Alias www</label><select data-c="alias_www">
          <option value="">auto</option><option value="true">eliminarlo siempre</option>
          <option value="false">conservarlo</option></select></div>
      </div>
      <div class="interruptores">
        <label class="interruptor"><input type="checkbox" data-c="ssl_on"> SSL distinto del predeterminado</label>
        <label class="interruptor"><input type="checkbox" data-c="ssl_val"> &nbsp;emitir SSL</label>
        <label class="interruptor riesgo"><input type="checkbox" data-c="dns_on"> DNS distinto</label>
        <label class="interruptor riesgo"><input type="checkbox" data-c="dns_val"> &nbsp;eliminar zona DNS</label>
        <label class="interruptor riesgo"><input type="checkbox" data-c="mail_on"> Correo distinto</label>
        <label class="interruptor riesgo"><input type="checkbox" data-c="mail_val"> &nbsp;eliminar dominio de correo</label>
      </div>
    </details>`;
  $('dominios').appendChild(div);
  div.querySelector('[data-c=dominio]').focus();
  pintar();
}

function anadirBase() {
  contadorB++;
  const id = 'b' + contadorB;
  const div = document.createElement('div');
  div.className = 'bloque';
  div.id = id;
  div.innerHTML = `
    <div class="bloque-cab">
      <span class="orden"></span>
      <input type="text" data-c="nombre" placeholder="legacy">
      <button type="button" class="quitar" onclick="quitar('${id}')">quitar</button>
    </div>
    <div class="rejilla">
      <div><label>Nombre en el servidor viejo</label><input type="text" data-c="origen" placeholder="nombre_en_el_viejo"></div>
      <div><label>Usuario</label><input type="text" data-c="user" placeholder="igual que el nombre"></div>
      <div><label>Contraseña</label><input type="text" data-c="pass"></div>
    </div>`;
  $('bases').appendChild(div);
  div.querySelector('[data-c=nombre]').focus();
  pintar();
}

function quitar(id) { $(id).remove(); pintar(); }

function v(cont, campo) {
  const el = cont.querySelector(`[data-c=${campo}]`);
  if (!el) return '';
  return el.type === 'checkbox' ? el.checked : el.value.trim();
}

function esc(s) { return String(s).replace(/[\\"$`]/g, '\\$&'); }

function generar() {
  const L = [];
  const nom = $('nombre').value.trim() || 'migracion.sh';

  L.push('#!/bin/bash');
  L.push('');
  L.push('# ============================================================');
  L.push('# MIGRACIÓN');
  L.push('# ============================================================');
  L.push('#');
  L.push('#   bash BASE_GENERAL.sh ' + nom + ' [fase]');
  L.push('#');
  L.push('# La fase pasada como argumento manda sobre FASE.');
  L.push('# ============================================================');
  L.push('');
  L.push('FASE="' + $('fase').value + '";');
  L.push('CONFIRMAR="' + ($('confirmar').checked ? 'true' : 'false') + '";');
  if ($('renovar_ssl').checked) L.push('RENOVAR_SSL="true";');
  if ($('sinc_fase2').checked) L.push('SINCRONIZAR_EN_FASE2="true";');
  L.push('');
  L.push('');
  L.push('# === SERVIDORES ===');
  L.push('');
  L.push('USER_DESTINO="' + esc($('user_destino').value.trim()) + '";');
  L.push('USER_ORIGEN="' + esc($('user_origen').value.trim()) + '";');
  L.push('');
  L.push('IP_ORIGEN="' + esc($('ip_origen').value.trim()) + '";');
  L.push('IP_DESTINO="' + esc($('ip_destino').value.trim()) + '";');
  L.push('');
  L.push('SSH_ORIGEN="' + esc($('ssh_origen').value.trim()) + '";');
  L.push('SSH_DESTINO="' + esc($('ssh_destino').value.trim()) + '";');
  L.push('');
  L.push('');
  L.push('# === CRONJOBS ===');
  L.push('');
  L.push('CRONJOBS="' + $('cronjobs').value + '";');
  const cu = $('cron_usuarios').value.trim();
  L.push('CRONJOBS_USUARIOS=(' + (cu ? cu.split(/\s+/).map(u => '"' + esc(u) + '"').join(' ') : '') + ');');
  L.push('');
  L.push('');
  L.push('# === PREDETERMINADOS ===');
  L.push('');
  const pd = [];
  pd.push('php="' + esc($('def_php').value.trim() || 'PHP-8_3') + '"');
  pd.push('tipo="' + $('def_tipo').value + '"');
  pd.push('ssl="' + ($('def_ssl').checked ? 'true' : 'false') + '"');
  pd.push('forzar_ssl="' + ($('def_forzar').checked ? 'true' : 'false') + '"');
  pd.push('eliminar_dns="' + ($('def_dns').checked ? 'true' : 'false') + '"');
  pd.push('eliminar_mail="' + ($('def_mail').checked ? 'true' : 'false') + '"');
  L.push('predeterminados \\');
  L.push(pd.map((x, i) => '  ' + x + (i === pd.length - 1 ? ';' : ' \\')).join('\n'));

  const doms = [...$('dominios').children];
  if (doms.length) {
    L.push('');
    L.push('');
    L.push('# === DOMINIOS ===');
  }

  doms.forEach(d => {
    const nombre = v(d, 'dominio');
    if (!nombre) return;
    const ln = [];
    const web = v(d, 'web');
    if (!web) {
      ln.push('web="false"');
      // Sin sitio web no hay certificado que emitir.
      if ($('def_ssl').checked) ln.push('ssl="false"');
      if ($('def_forzar').checked) ln.push('forzar_ssl="false"');
    }
    if (v(d, 'php')) ln.push('php="' + esc(v(d, 'php')) + '"');
    if (v(d, 'tipo')) ln.push('tipo="' + v(d, 'tipo') + '"');
    // auto es el predeterminado: no se escribe.
    if (v(d, 'correo') === 'false') ln.push('correo="false"');
    if (v(d, 'correo') === 'true') {
      ln.push('correo="true"');
      // Migrar el correo y borrar el dominio de correo se contradicen.
      // Si el predeterminado lo borra, aquí se anula.
      if ($('def_mail').checked) ln.push('eliminar_mail="false"');
    }
    if (v(d, 'correo_origen')) ln.push('correo_origen="' + esc(v(d, 'correo_origen')) + '"');
    if (v(d, 'ssl_on')) {
      ln.push('ssl="' + (v(d, 'ssl_val') ? 'true' : 'false') + '"');
      ln.push('forzar_ssl="' + (v(d, 'ssl_val') ? 'true' : 'false') + '"');
    }
    if (v(d, 'dns_on')) ln.push('eliminar_dns="' + (v(d, 'dns_val') ? 'true' : 'false') + '"');
    if (v(d, 'mail_on')) ln.push('eliminar_mail="' + (v(d, 'mail_val') ? 'true' : 'false') + '"');
    if (v(d, 'origen')) ln.push('origen="' + esc(v(d, 'origen')) + '"');
    if (v(d, 'ruta_db')) ln.push('ruta_db="' + esc(v(d, 'ruta_db')) + '"');
    if (v(d, 'chmod')) ln.push('chmod="' + esc(v(d, 'chmod')) + '"');
    if (v(d, 'grupo')) ln.push('grupo="' + esc(v(d, 'grupo')) + '"');
    if (v(d, 'alias_www')) ln.push('alias_www="' + v(d, 'alias_www') + '"');
    if (v(d, 'bd')) {
      ln.push('bd="' + esc(v(d, 'bd')) + '"');
      if (v(d, 'bd_user')) ln.push('bd_user="' + esc(v(d, 'bd_user')) + '"');
      ln.push('bd_pass="' + esc(v(d, 'bd_pass')) + '"');
    }
    L.push('');
    if (!ln.length) {
      L.push('dominio "' + esc(nombre) + '";');
    } else {
      L.push('dominio "' + esc(nombre) + '" \\');
      L.push(ln.map((x, i) => '  ' + x + (i === ln.length - 1 ? ';' : ' \\')).join('\n'));
    }
  });

  const bases = [...$('bases').children];
  if (bases.length) {
    L.push('');
    L.push('');
    L.push('# === BASES SUELTAS ===');
  }

  bases.forEach(b => {
    const nombre = v(b, 'nombre');
    if (!nombre) return;
    const ln = ['origen="' + esc(v(b, 'origen')) + '"'];
    if (v(b, 'user')) ln.push('user="' + esc(v(b, 'user')) + '"');
    ln.push('pass="' + esc(v(b, 'pass')) + '"');
    L.push('');
    L.push('base_de_datos "' + esc(nombre) + '" \\');
    L.push(ln.map((x, i) => '  ' + x + (i === ln.length - 1 ? ';' : ' \\')).join('\n'));
  });

  L.push('');
  return L.join('\n');
}

function resaltar(t) {
  return t
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .split('\n').map(l => {
      if (/^\s*#/.test(l)) return '<span class="c-com">' + l + '</span>';
      return l
        .replace(/^(dominio|base_de_datos|predeterminados)\b/, '<span class="c-fun">$1</span>')
        .replace(/"([^"]*)"/g, '"<span class="c-tex">$1</span>"')
        .replace(/^([A-Z_]+)=/, '<span class="c-var">$1</span>=');
    }).join('\n');
}

function pintar() {
  [...$('dominios').children].forEach((d, i) => {
    d.querySelector('.orden').textContent = (i + 1);
    d.classList.toggle('solocorreo', !v(d, 'web'));
    d.classList.toggle('destructivo', v(d, 'dns_on') && v(d, 'dns_val') || v(d, 'mail_on') && v(d, 'mail_val'));

    const nota = d.querySelector('[data-c=nota]');
    if (nota) {
      const avisos = [];
      if (v(d, 'correo') === 'true' && $('def_mail').checked) avisos.push('se conservará su dominio de correo');
      if (!v(d, 'web') && $('def_ssl').checked) avisos.push('sin web no se emite certificado');
      nota.textContent = avisos.join('; ');
    }
  });
  [...$('bases').children].forEach((b, i) => {
    b.querySelector('.orden').textContent = 'bd';
  });
  $('salida').innerHTML = resaltar(generar());
}

document.addEventListener('input', pintar);
document.addEventListener('change', pintar);

async function guardar() {
  const est = $('estado');
  const nombre = $('nombre').value.trim();

  const faltan = [];
  if (!nombre) faltan.push('el nombre del archivo');
  if (!$('user_destino').value.trim()) faltan.push('el usuario de destino');
  if (!$('user_origen').value.trim()) faltan.push('el usuario de origen');
  if (!$('ip_origen').value.trim()) faltan.push('la IP del servidor viejo');
  if (!$('ip_destino').value.trim()) faltan.push('la IP del servidor nuevo');

  const hayAlgo = [...$('dominios').children].some(d => v(d, 'dominio'))
    || [...$('bases').children].some(b => v(b, 'nombre'));
  if (!hayAlgo) faltan.push('al menos un dominio o una base');

  if (faltan.length) {
    est.className = 'estado error';
    est.textContent = 'Falta ' + faltan.join(', ') + '.';
    return;
  }

  est.className = 'estado';
  est.textContent = 'Guardando…';

  const r = await fetch('/guardar', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      nombre: nombre,
      contenido: generar(),
      construir: $('construir').checked
    })
  });

  const t = await r.text();

  if (r.ok) {
    est.className = 'estado ok';
    est.textContent = t;
    document.querySelector('.guardar').disabled = true;
  } else {
    est.className = 'estado error';
    est.textContent = t;
  }
}

anadirDominio();
pintar();
</script>
</body>
</html>
FIN_HTML



# ============================================================
# === SERVIDOR ===
# ============================================================

cat > "$TMP/servidor.py" <<'FIN_PY'
import http.server, json, os, re, socketserver, sys, threading

RAIZ = sys.argv[1]
DESTINO = sys.argv[2]
SENAL = sys.argv[3]

class Manejador(http.server.BaseHTTPRequestHandler):

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path not in ('/', '/index.html'):
            self.send_error(404)
            return
        cuerpo = open(os.path.join(RAIZ, 'index.html'), 'rb').read()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def do_POST(self):
        if self.path != '/guardar':
            self.send_error(404)
            return

        n = int(self.headers.get('Content-Length', 0))
        datos = json.loads(self.rfile.read(n))

        nombre = os.path.basename(datos.get('nombre', ''))

        if not nombre or not re.fullmatch(r'[A-Za-z0-9._-]+', nombre):
            self.responder(400, 'El nombre solo puede llevar letras, números, punto, guion y guion bajo.')
            return

        if not nombre.endswith('.sh'):
            nombre += '.sh'

        ruta = os.path.join(DESTINO, nombre)

        try:
            with open(ruta, 'w', encoding='utf-8') as f:
                f.write(datos.get('contenido', ''))
            os.chmod(ruta, 0o600)
        except OSError as e:
            self.responder(500, 'No se pudo escribir el archivo: %s' % e)
            return

        with open(SENAL, 'w') as f:
            f.write(nombre + '\n')
            f.write('si' if datos.get('construir') else 'no')

        self.responder(200, 'Guardado como %s. Ya puedes cerrar esta pestaña.' % nombre)

        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def responder(self, codigo, texto):
        cuerpo = texto.encode('utf-8')
        self.send_response(codigo)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)


with socketserver.TCPServer(('127.0.0.1', 0), Manejador) as s:
    print(s.server_address[1], flush=True)
    s.serve_forever()
FIN_PY



# ============================================================
# === ARRANCAR ===
# ============================================================

SENAL="$TMP/guardado";


exec 3< <(python3 "$TMP/servidor.py" "$TMP" "$DESTINO" "$SENAL");

read -r PUERTO <&3;


if [ -z "${PUERTO:-}" ]; then

  echo;
  echo "ERROR: no se pudo arrancar el servidor local.";
  echo;

  exit 1;

fi;


URL="http://127.0.0.1:$PUERTO/";


echo;
echo "============================================================";
echo "NUEVA MIGRACIÓN";
echo "============================================================";
echo;
echo "  $URL";
echo;
echo "El archivo se guardará en:";
echo "  $DESTINO";
echo;
echo "Ctrl-C para salir sin guardar.";
echo;


for abrir in xdg-open open; do

  if command -v "$abrir" >/dev/null 2>&1; then
    "$abrir" "$URL" >/dev/null 2>&1 &
    break;
  fi;

done;


# ------------------------------------------------------------
# Esperar a que la interfaz guarde.
#
# El servidor se apaga solo al hacerlo, y ahí termina la
# lectura del descriptor.
# ------------------------------------------------------------

cat <&3 >/dev/null 2>&1;


if [ ! -f "$SENAL" ]; then

  echo;
  echo "Se cerró sin guardar. No se ha creado ningún archivo.";
  echo;

  exit 0;

fi;


NOMBRE="$(sed -n '1p' "$SENAL")";
CONSTRUIR="$(sed -n '2p' "$SENAL")";


echo;
echo "Guardado:";
echo;
echo "  $DESTINO/$NOMBRE";


if [ "$CONSTRUIR" = "si" ] && [ -x "$DIR_FUENTE/construir.sh" ]; then

  echo;

  "$DIR_FUENTE/construir.sh" "$DESTINO/$NOMBRE";

else

  echo;
  echo "Para construir el paquete:";
  echo;
  echo "  ./construir.sh $NOMBRE";
  echo;

fi;
