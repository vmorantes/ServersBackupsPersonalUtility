/* =============================================================================
   app.js — interfaz web de backupctl
   Sin dependencias. La credencial de sesión llega en la URL y se guarda solo
   en memoria: no se escribe en localStorage ni queda en el historial.
   ============================================================================= */
'use strict';

const TOKEN = new URLSearchParams(location.search).get('t') || '';
let perfilActual = null;
let ejecutando = false;

const $  = (s) => document.querySelector(s);
const $$ = (s) => Array.from(document.querySelectorAll(s));

// --- API ---------------------------------------------------------------------
async function api(ruta, opciones = {}) {
  const r = await fetch(ruta, {
    ...opciones,
    headers: { 'X-Backupctl-Token': TOKEN, ...(opciones.headers || {}) },
  });
  if (r.status === 403) throw new Error('Credencial no válida. Vuelve a abrir la URL que imprimió el servidor.');
  return r;
}

// --- Consola -----------------------------------------------------------------
const consola = $('#consola');

function claseLinea(t) {
  if (t.includes('[ERROR]')) return 'l-error';
  if (t.includes('[AVISO]')) return 'l-warn';
  if (t.includes('[  OK ]')) return 'l-ok';
  if (t.includes('[ >>  ]')) return 'l-paso';
  if (t.startsWith('==') || t.includes('== ')) return 'l-sec';
  return '';
}

function limpiarConsola(txt = '') { consola.textContent = txt; }

function anadirLinea(texto) {
  const cls = claseLinea(texto);
  if (cls) {
    const s = document.createElement('span');
    s.className = cls;
    s.textContent = texto + '\n';
    consola.appendChild(s);
  } else {
    consola.appendChild(document.createTextNode(texto + '\n'));
  }
  consola.scrollTop = consola.scrollHeight;
}

function marcarEstado(txt, clase) {
  const e = $('#estado-ejecucion');
  e.textContent = txt;
  e.className = 'etq ' + (clase || '');
}

// --- Ejecutar una acción -----------------------------------------------------
// Recoge los valores de un formulario: todo elemento con data-opt dentro del
// contenedor, más las casillas sueltas que declaren data-form apuntando a él.
function recogerOpciones(selector) {
  const opts = {};
  if (!selector) return opts;
  const cont = $(selector);
  if (cont) {
    cont.querySelectorAll('[data-opt]').forEach(el => {
      opts[el.dataset.opt] = el.type === 'checkbox' ? el.checked : el.value.trim();
    });
  }
  $$(`[data-opt][data-form="${selector}"]`).forEach(el => {
    opts[el.dataset.opt] = el.type === 'checkbox' ? el.checked : el.value.trim();
  });
  return opts;
}

function resumenOpciones(opts) {
  return Object.entries(opts)
    .filter(([k, v]) => v !== '' && v !== false && v != null)
    .map(([k, v]) => (v === true ? '--' + k.replace(/^_/, '') : `${k}=${v}`))
    .join(' ');
}

async function ejecutar(accion, opts, endpoint) {
  if (ejecutando) return;
  if (!perfilActual && !endpoint) { limpiarConsola('Elige un servidor primero.'); return; }
  opts = opts || {};

  ejecutando = true;
  $$('.btn').forEach(b => b.disabled = true);
  marcarEstado('ejecutando…', 'etq-warn');
  limpiarConsola('');
  anadirLinea(`$ backupctl -p ${perfilActual || '?'} ${accion} ${resumenOpciones(opts)}`.trimEnd());
  anadirLinea('');

  try {
    const r = await api(endpoint || '/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(endpoint
        ? opts
        : { profile: perfilActual, action: accion, opts }),
    });

    if (!r.ok) {
      const j = await r.json().catch(() => ({ error: 'error ' + r.status }));
      anadirLinea('[ERROR] ' + (j.error || r.status));
      marcarEstado('error', 'etq-error');
      return;
    }

    // Lectura en flujo: las órdenes largas se ven avanzar
    const lector = r.body.getReader();
    const dec = new TextDecoder();
    let resto = '';
    let codigo = null;

    for (;;) {
      const { done, value } = await lector.read();
      if (done) break;
      resto += dec.decode(value, { stream: true });
      const lineas = resto.split('\n');
      resto = lineas.pop();
      for (const ln of lineas) {
        const m = ln.match(/^__FIN__(\d+)$/);
        if (m) { codigo = parseInt(m[1], 10); continue; }
        anadirLinea(ln);
      }
    }
    if (resto) anadirLinea(resto);

    if (codigo === 0)      marcarEstado('correcto (0)', 'etq-ok');
    else if (codigo === null) marcarEstado('terminado', '');
    else                   marcarEstado('código ' + codigo, codigo === 1 ? 'etq-warn' : 'etq-error');

  } catch (e) {
    anadirLinea('[ERROR] ' + e.message);
    marcarEstado('error', 'etq-error');
  } finally {
    ejecutando = false;
    $$('.btn').forEach(b => b.disabled = false);
    if (perfilActual) { cargarRespaldos(perfilActual); sondear(perfilActual); }
    cargarPanel();
  }
}

// --- Confirmación ------------------------------------------------------------
// El diálogo es un overlay a pantalla completa: si se queda abierto, bloquea
// toda la interfaz. Por eso tiene tres salidas —Cancelar, Escape y pulsar
// fuera— y se fuerza cerrado al arrancar.
function confirmar(texto) {
  return new Promise((resolver) => {
    const modal = $('#modal');
    $('#modal-texto').textContent = texto || '¿Continuar con esta acción?';
    modal.hidden = false;

    const si = $('#modal-si'), no = $('#modal-no');
    const cerrar = (v) => {
      modal.hidden = true;
      si.removeEventListener('click', aSi);
      no.removeEventListener('click', aNo);
      modal.removeEventListener('click', aFuera);
      document.removeEventListener('keydown', aTecla);
      resolver(v);
    };
    const aSi = () => cerrar(true);
    const aNo = () => cerrar(false);
    const aFuera = (ev) => { if (ev.target === modal) cerrar(false); };
    const aTecla = (ev) => {
      if (ev.key === 'Escape') cerrar(false);
      if (ev.key === 'Enter') cerrar(true);
    };

    si.addEventListener('click', aSi);
    no.addEventListener('click', aNo);
    modal.addEventListener('click', aFuera);
    document.addEventListener('keydown', aTecla);
    no.focus();
  });
}

// --- Panel de servidores -----------------------------------------------------
async function cargarPanel() {
  const cont = $('#tarjetas');
  try {
    const r = await api('/api/overview');
    const d = await r.json();
    if (!d.perfiles || !d.perfiles.length) {
      cont.innerHTML = '<div class="cargando">No hay ningún perfil. Crea uno con <code>backupctl setup</code>.</div>';
      return;
    }
    cont.innerHTML = '';
    for (const p of d.perfiles) {
      const t = document.createElement('div');
      t.className = 'tarjeta' + (p.name === perfilActual ? ' sel' : '');
      t.tabIndex = 0;

      const cab = document.createElement('div');
      cab.className = 'tarjeta-cab';
      const n = document.createElement('span');
      n.className = 'tarjeta-nombre'; n.textContent = p.name;
      const e = document.createElement('span');
      if (p.remoto) {
        // El estado local no aplica: este perfil describe otra máquina
        e.className = 'etq etq-lee';
        e.textContent = 'remoto';
      } else {
        e.className = 'etq ' + (p.ok ? 'etq-ok' : 'etq-warn');
        e.textContent = p.ok ? 'correcto' : 'requiere atención';
      }
      cab.append(n, e);

      const ls = document.createElement('div');
      ls.className = 'tarjeta-lineas';

      if (p.remoto) {
        const nota = document.createElement('div');
        nota.className = 'nota-remoto';
        nota.innerHTML = p.destino
          ? ('Este perfil describe <strong>' + esc(p.destino) + '</strong>. Sus rutas ' +
             'están allí, no en tu equipo, así que el estado local no dice nada útil.')
          : ('Las rutas de este perfil no existen en tu equipo: describe otra máquina. ' +
             'Define <strong>DEPLOY_HOST</strong> en su env.sh para poder consultarla desde aquí.');
        ls.appendChild(nota);
        const b = document.createElement('button');
        b.className = 'btn btn-sec';
        b.style.marginTop = '8px';
        b.textContent = p.destino ? 'Consultar el servidor' : 'Ver la configuración';
        if (!p.destino) {
          b.addEventListener('click', (ev) => {
            ev.stopPropagation(); seleccionar(p.name); ejecutar('config', {});
          }, { once: false });
        }
        if (p.destino) {
          b.addEventListener('click', (ev) => {
            ev.stopPropagation(); seleccionar(p.name); ejecutar('remote-status', {});
          });
        }
        ls.appendChild(b);
        t.append(cab, ls);
        const abrirR = () => seleccionar(p.name);
        t.addEventListener('click', abrirR);
        t.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') abrirR(); });
        cont.appendChild(t);
        continue;
      }

      for (const l of (p.lineas || []).slice(0, 6)) {
        const d2 = document.createElement('div');
        d2.className = 'tarjeta-linea n-' + l.nivel;
        const i = document.createElement('span');
        i.className = 'ico';
        i.textContent = l.nivel === 'ok' ? '✓' : l.nivel === 'warn' ? '!' : l.nivel === 'error' ? '✗' : '·';
        const s = document.createElement('span');
        s.textContent = l.texto;
        d2.append(i, s);
        ls.appendChild(d2);
      }

      t.append(cab, ls);
      const abrir = () => seleccionar(p.name);
      t.addEventListener('click', abrir);
      t.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') abrir(); });
      cont.appendChild(t);
    }
  } catch (e) {
    cont.innerHTML = '<div class="cargando n-error">' + e.message + '</div>';
  }
}

// --- Estado del despliegue ---------------------------------------------------
// Responde a "¿en qué punto estoy?" antes de que el usuario tenga que
// deducirlo de una pared de botones.
async function sondear(nombre) {
  const ico = (el, s) => { const e = $(el); e.textContent = s;
    e.className = 'ico-estado ' + (s === '✓' ? 'i-ok' : s === '✗' ? 'i-mal' : 'i-duda'); };
  ico('#e-ssh', '·'); ico('#e-ctl', '·');
  $('#t-ssh').textContent = 'Comprobando el servidor…';
  $('#t-ctl').textContent = '';
  $('#t-siguiente').textContent = '';

  let d;
  try {
    d = await (await api('/api/probe?profile=' + encodeURIComponent(nombre))).json();
  } catch (e) { $('#t-ssh').textContent = e.message; return; }

  const mapa = {
    'ok':          ['✓', 'Conectado a ' + d.destino],
    'sin-clave':   ['✗', 'Sin acceso por clave a ' + d.destino],
    'error':       ['✗', 'No se llega a ' + d.destino + (d.detalle ? ' — ' + d.detalle : '')],
    'sin-destino': ['✗', 'Sin DEPLOY_HOST: este perfil no sabe a qué servidor conectarse'],
  };
  const [i, t] = mapa[d.ssh] || ['?', 'Estado desconocido'];
  ico('#e-ssh', i); $('#t-ssh').textContent = t;

  if (d.ssh === 'ok') {
    ico('#e-ctl', d.backupctl === 'si' ? '✓' : '✗');
    $('#t-ctl').textContent = d.backupctl === 'si'
      ? 'backupctl instalado en ' + d.ruta
      : 'backupctl NO está en ' + d.ruta;
  } else {
    ico('#e-ctl', '·');
    $('#t-ctl').textContent = d.local
      ? 'Las rutas del perfil sí existen en este equipo'
      : 'Las rutas del perfil no existen en este equipo';
  }
  $('#t-siguiente').textContent = d.siguiente ? 'Siguiente paso: ' + d.siguiente : '';

  // El botón solo aparece cuando de verdad resuelve algo
  const acc = $('#acciones-estado');
  acc.hidden = d.ssh !== 'sin-clave';
  if (d.ssh === 'sin-clave') $('#k-target').value = d.destino || '';

  // Si el perfil es de otra máquina, avisar en las pestañas que actúan aquí
  const rot = $('#rotulo-local');
  if (rot) {
    rot.classList.toggle('rotulo-aviso', !d.local);
    rot.innerHTML = d.local
      ? 'Estas acciones se ejecutan <strong>en este equipo</strong>, sobre las rutas del perfil.'
      : 'Ojo: estas acciones se ejecutan <strong>en este equipo</strong>, pero las rutas ' +
        'de este perfil están en el servidor. Lo que buscas está en la pestaña <strong>Servidor</strong>.';
  }
}

// --- Detalle de un perfil ----------------------------------------------------
function seleccionar(nombre) {
  perfilActual = nombre;
  $('#titulo-perfil').textContent = nombre;
  $('#panel-detalle').hidden = false;
  sondear(nombre);
  $$('.tarjeta').forEach(t => t.classList.toggle(
    'sel', t.querySelector('.tarjeta-nombre').textContent === nombre));
  cargarRespaldos(nombre);
  $('#panel-detalle').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

async function cargarRespaldos(nombre) {
  const cont = $('#tabla-respaldos');
  try {
    const r = await api('/api/backups?profile=' + encodeURIComponent(nombre));
    const d = await r.json();
    if (!d.respaldos || !d.respaldos.length) {
      cont.innerHTML = '<p class="ayuda">Todavía no hay respaldos.</p>';
      return;
    }
    const filas = d.respaldos.map(b => `
      <tr>
        <td class="mono">${esc(b.archivo)}</td>
        <td>${esc(b.tamano)}</td>
        <td>${esc(b.fecha)}</td>
        <td>${esc(b.edad)}</td>
        <td>${esc(b.bd)}</td>
        <td><button class="btn btn-sec" data-inspect="${esc(b.archivo)}">Ver</button></td>
      </tr>`).join('');
    cont.innerHTML = `<table>
      <thead><tr><th>Archivo</th><th>Tamaño</th><th>Fecha</th><th>Edad</th><th>BD</th><th></th></tr></thead>
      <tbody>${filas}</tbody></table>`;
    rellenarSelectores(d.respaldos);
    cont.querySelectorAll('[data-inspect]').forEach(b =>
      b.addEventListener('click', () => ejecutar('inspect', { zip: b.dataset.inspect })));
  } catch (e) {
    cont.innerHTML = '<p class="ayuda n-error">' + esc(e.message) + '</p>';
  }
}

// Los <select> de respaldo se rellenan con lo que hay realmente
function rellenarSelectores(respaldos) {
  $$('.sel-respaldo').forEach(sel => {
    const actual = sel.value;
    sel.innerHTML = '<option value="">el más reciente</option>';
    for (const b of respaldos) {
      const o = document.createElement('option');
      o.value = b.archivo;
      o.textContent = `${b.archivo}  (${b.tamano}, ${b.edad})`;
      sel.appendChild(o);
    }
    sel.value = actual;
  });
}

// --- Editor de configuración -------------------------------------------------
async function cargarConfig() {
  if (!perfilActual) { limpiarConsola('Elige un servidor primero.'); return; }
  try {
    const r = await api('/api/config-raw?profile=' + encodeURIComponent(perfilActual));
    const d = await r.json();
    if (d.error) { limpiarConsola('[ERROR] ' + d.error); return; }
    $('#editor-config').value = d.contenido;
    $('#ruta-config').textContent = d.ruta;
  } catch (e) { limpiarConsola('[ERROR] ' + e.message); }
}

async function guardarConfig() {
  if (!perfilActual) return;
  const contenido = $('#editor-config').value;
  if (!contenido.trim()) { limpiarConsola('El editor está vacío. Pulsa «Cargar» primero.'); return; }
  if (!(await confirmar('Se sobrescribirá el env.sh de «' + perfilActual +
                        '». La versión actual quedará como env.sh.anterior.'))) return;
  try {
    const r = await api('/api/config-save', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ profile: perfilActual, contenido }),
    });
    const d = await r.json();
    if (d.error) { limpiarConsola('[ERROR] ' + d.error); marcarEstado('error', 'etq-error'); return; }
    limpiarConsola('Guardado: ' + d.ruta);
    marcarEstado('guardado', 'etq-ok');
    cargarPanel();
  } catch (e) { limpiarConsola('[ERROR] ' + e.message); }
}

// --- Instalar la clave SSH ---------------------------------------------------
async function instalarClave() {
  const target = $('#k-target').value.trim();
  const password = $('#k-pass').value;
  if (!target || !password) { alert('Hacen falta el servidor y la contraseña.'); return; }
  $('#clave').hidden = true;
  $('#k-pass').value = '';          // no se queda en el formulario
  await ejecutar('sshkey', { profile: perfilActual, target, password }, '/api/sshkey');
  if (perfilActual) sondear(perfilActual);
}

// --- Remoto de rclone --------------------------------------------------------
async function configurarRclone() {
  const datos = {
    profile: perfilActual,
    name:     $('#rc-name').value.trim(),
    type:     $('#rc-type').value,
    key:      $('#rc-key').value.trim(),
    secret:   $('#rc-secret').value,
    endpoint: $('#rc-endpoint').value.trim(),
    region:   $('#rc-region').value.trim(),
  };
  if (!perfilActual) { limpiarConsola('Elige un servidor primero.'); return; }
  if (!datos.name) { alert('Falta el nombre del remoto.'); return; }
  if (datos.type === 's3' && (!datos.key || !datos.secret || !datos.endpoint)) {
    alert('Para S3 hacen falta access key, secret y endpoint.\n\n' +
          'El endpoint es obligatorio: Mega S4 no es Amazon.');
    return;
  }
  if (!(await confirmar('Se escribirá el remoto «' + datos.name + '» en el rclone.conf ' +
                        'del servidor. Se guardará copia de la versión anterior.'))) return;
  $('#rc-secret').value = '';        // no se queda en el formulario
  await ejecutar('hestia rclone', datos, '/api/rclone');
}

// --- Alta de un servidor -----------------------------------------------------
function abrirAlta()  { $('#alta').hidden = false; $('#f-name').focus(); }
function cerrarAlta() { $('#alta').hidden = true; }

async function crearPerfil() {
  const crear = document.querySelector('input[name=db]:checked').value === 'crear';
  const datos = {
    name:        $('#f-name').value.trim(),
    host:        $('#f-host').value.trim(),
    ssh_user:    $('#f-ssh').value.trim() || 'admin',
    owner:       $('#f-owner').value.trim() || $('#f-ssh').value.trim() || 'admin',
    path:        $('#f-path').value.trim(),
    healthcheck: $('#f-hc').value.trim(),
    crear_db:    crear,
    db_user:     crear ? $('#f-newdbuser').value.trim() : $('#f-dbuser').value.trim(),
    db_pass:     crear ? '' : $('#f-dbpass').value,
    admin_user:  crear ? $('#f-adminuser').value.trim() : '',
    admin_pass:  crear ? $('#f-adminpass').value : '',
    desplegar:   $('#f-deploy').checked,
  };
  if (!datos.name || !datos.host) {
    alert('Hacen falta al menos el nombre del perfil y el servidor.');
    return;
  }
  if (!datos.path) datos.path = '/home/' + datos.owner + '/scripts';
  cerrarAlta();
  // Las contraseñas se limpian del formulario en cuanto se envían
  $('#f-dbpass').value = ''; $('#f-adminpass').value = '';
  await ejecutar('setup', datos, '/api/setup');
  perfilActual = datos.name;
  cargarPanel();
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// --- Eventos -----------------------------------------------------------------
document.addEventListener('click', async (ev) => {
  const b = ev.target.closest('[data-act]');
  if (!b) return;
  const opts = recogerOpciones(b.dataset.form);
  const aviso = b.dataset.confirmar;
  if (aviso && !(await confirmar(aviso))) return;
  ejecutar(b.dataset.act, opts);
});

$('#pestanas').addEventListener('click', (ev) => {
  const p = ev.target.closest('.pestana');
  if (!p) return;
  $$('.pestana').forEach(x => x.classList.toggle('activa', x === p));
  $$('.tab').forEach(t => t.hidden = t.dataset.tab !== p.dataset.tab);
});

$('#btn-refrescar').addEventListener('click', cargarPanel);
$('#btn-nuevo').addEventListener('click', abrirAlta);
$('#btn-sshkey').addEventListener('click', () => {
  $('#clave').hidden = false; $('#k-pass').focus();
});
$('#clave-no').addEventListener('click', () => { $('#clave').hidden = true; $('#k-pass').value = ''; });
$('#clave-si').addEventListener('click', instalarClave);
$('#clave').addEventListener('click', (ev) => {
  if (ev.target === $('#clave')) { $('#clave').hidden = true; $('#k-pass').value = ''; }
});
$('#alta-no').addEventListener('click', cerrarAlta);
$('#alta-si').addEventListener('click', crearPerfil);
$('#btn-rclone').addEventListener('click', configurarRclone);
$('#rc-type').addEventListener('change', () => {
  const s3 = $('#rc-type').value === 's3';
  ['rc-key','rc-secret','rc-endpoint','rc-region'].forEach(
    id => { $('#'+id).closest('label').hidden = !s3; });
});
$('#btn-cargar-config').addEventListener('click', cargarConfig);
$('#btn-guardar-config').addEventListener('click', guardarConfig);
$$('input[name=db]').forEach(r => r.addEventListener('change', () => {
  const crear = document.querySelector('input[name=db]:checked').value === 'crear';
  $('#db-existente').hidden = crear;
  $('#db-crear').hidden = !crear;
}));
$('#alta').addEventListener('click', (ev) => { if (ev.target === $('#alta')) cerrarAlta(); });
$('#btn-limpiar').addEventListener('click', () => { limpiarConsola(''); marcarEstado('', ''); });
$('#btn-cerrar').addEventListener('click', () => {
  $('#panel-detalle').hidden = true;
  perfilActual = null;
  $$('.tarjeta').forEach(t => t.classList.remove('sel'));
});

// --- Arranque ----------------------------------------------------------------
(async function inicio() {
  // Por si alguna regla de estilo volviera a anular el atributo `hidden`
  $('#modal').hidden = true;
  $('#alta').hidden = true;
  $('#clave').hidden = true;
  if (!TOKEN) {
    limpiarConsola('Falta la credencial de sesión.\n\nAbre la dirección completa que imprimió el servidor, la que lleva ?t=…');
    return;
  }
  try {
    const r = await api('/api/profiles');
    const d = await r.json();
    $('#version').textContent = d.version || '';
  } catch (e) {
    limpiarConsola(e.message);
    return;
  }
  cargarPanel();
})();
