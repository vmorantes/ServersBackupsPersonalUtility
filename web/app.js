/* =============================================================================
   app.js — interfaz web de backupctl
   Sin dependencias. La credencial de sesión llega en la URL y se guarda solo
   en memoria: no se escribe en localStorage ni queda en el historial.
   ============================================================================= */
'use strict';

const TOKEN = new URLSearchParams(location.search).get('t') || '';
let perfilActual = null;
let ultimaSonda = null;
let ejecutando = false;

const $  = (s) => document.querySelector(s);
const $$ = (s) => Array.from(document.querySelectorAll(s));

// Enganchar un manejador SIN romperse si el elemento no existe.
//
// Con addEventListener directo, un solo id que desaparezca del HTML lanza un
// TypeError que aborta el resto del script: los manejadores siguientes no se
// registran y el arranque nunca llega a ejecutarse. El síntoma es una interfaz
// en blanco sin ninguna pista de la causa. Ya pasó una vez.
function on(sel, ev, fn) {
  const el = $(sel);
  if (!el) { console.warn('backupctl: no existe ' + sel); return false; }
  el.addEventListener(ev, fn);
  return true;
}

// Abre el diálogo de acceso con los datos que ya conocemos del perfil
function abrirDialogoClave() {
  const d = ultimaSonda || {};
  const [u, h] = (d.destino || '@').split('@');
  $('#k-user').value = (d.ssh === 'usuario-malo' || !u) ? 'root' : u;
  $('#k-host').value = h || '';
  $('#clave').hidden = false;
  ($('#k-host').value ? $('#k-pass') : $('#k-host')).focus();
}

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

  ultimaSonda = d;
  const mapa = {
    'ok':          ['✓', 'Conectado a ' + d.destino],
    'sin-clave':   ['✗', 'Sin acceso por clave a ' + d.destino],
    'usuario-malo':['✗', 'El usuario «' + (d.destino || '').split('@')[0] + '» no puede entrar por SSH'],
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

  // Plan ordenado: qué falta y en qué orden
  const ol = $('#plan');
  ol.innerHTML = '';
  for (const paso of (d.plan || [])) {
    const li = document.createElement('li');
    li.className = paso.hecho ? 'paso-ok' : 'paso-falta';
    const t = document.createElement('span');
    t.className = 'paso-titulo';
    t.textContent = (paso.hecho ? '✓ ' : '○ ') + paso.titulo;
    li.appendChild(t);
    if (!paso.hecho) {
      const h = document.createElement('span');
      h.className = 'paso-hacer'; h.textContent = paso.hacer;
      li.appendChild(h);
    }
    ol.appendChild(li);
  }

  // El botón solo aparece cuando de verdad resuelve algo
  const acc = $('#acciones-estado');
  // El botón de instalar la clave solo tiene sentido si el usuario SÍ puede
  // entrar; con un usuario sin consola, instalarle una clave no arregla nada.
  // El botón aparece tanto si falta la clave como si el usuario configurado no
  // puede entrar: en los dos casos el diálogo resuelve el problema.
  acc.hidden = !(d.ssh === 'sin-clave' || d.ssh === 'usuario-malo');
  if (!acc.hidden) {
    const [u, h] = (d.destino || '@').split('@');
    // Un usuario del panel no puede entrar: se propone root
    $('#k-user').value = (d.ssh === 'usuario-malo' || !u) ? 'root' : u;
    $('#k-host').value = h || '';
  }

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
  cargarEstadoHestia(nombre);
  $('#panel-detalle').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

// --- Estado real de HestiaCP -------------------------------------------------
// Se lee ANTES de ofrecer nada. Un botón que escribe sin decir qué hay ya
// puesto es una trampa: conf/restic.conf es uno solo por HestiaCP entero.
async function cargarEstadoHestia(nombre) {
  const cajas = ['#est-rclone', '#est-restic', '#est-claves'];
  cajas.forEach(c => { const e = $(c); if (e) { e.className = 'estado-real'; e.textContent = 'Leyendo el servidor…'; } });

  let d;
  try {
    d = await (await api('/api/hestia-estado?profile=' + encodeURIComponent(nombre))).json();
  } catch (e) {
    cajas.forEach(c => pintarEstado(c, 'sin-datos', 'No se pudo leer el servidor. Los botones de esta pestaña escribirían a ciegas: no los uses hasta resolverlo.'));
    return;
  }
  if (!d.conectado) {
    cajas.forEach(c => pintarEstado(c, 'sin-datos',
      'No se pudo leer el servidor' + (d.detalle ? ': ' + esc(d.detalle) : '') +
      '.<br>Sin saber qué hay configurado, cualquier botón que escriba podría pisar algo. Resuélvelo en la pestaña Servidor.'));
    marcarPisa(null);
    pintarEstadoGeneral(d);
    return;
  }

  // --- 1. Remoto de rclone --------------------------------------------------
  const rem = d.rclone.remotos || [];
  if (rem.length) {
    pintarEstado('#est-rclone', 'ok',
      '<strong>Ya configurado.</strong> Remotos que existen en el servidor: ' +
      rem.map(x => '<code>' + esc(x) + '</code>').join(', ') +
      '<span class="aviso-pisa">«Configurar el remoto» <strong>reescribe</strong> el rclone.conf del servidor. ' +
      'Si usas un nombre que ya está en la lista, esas claves se sustituyen. Se guarda copia de la versión anterior.</span>');
  } else {
    pintarEstado('#est-rclone', 'vacio',
      'Todavía no hay ningún remoto de rclone en el servidor. Nada que pisar: puedes configurarlo con tranquilidad.');
  }

  // --- 2. Host de respaldo Restic ------------------------------------------
  const R = d.restic;
  const campoRepo = $('#form-hrestic input[data-opt="repo"]');
  if (R.repo) {
    pintarEstado('#est-restic', 'ok',
      '<strong>Ya configurado.</strong> Esta configuración es <strong>una sola para todo el HestiaCP</strong>, ' +
      'no una por usuario:' +
      '<dl>' +
      '<dt>Repositorio</dt><dd>' + esc(R.repo) + '</dd>' +
      '<dt>Instantáneas</dt><dd>' + esc(R.snapshots || '?') + ' en total</dd>' +
      '<dt>Retención</dt><dd>' + esc(R.diarias) + ' diarias · ' + esc(R.semanales) + ' semanales · ' +
        esc(R.mensuales) + ' mensuales · ' + (R.anuales === '-1' ? 'anuales ilimitadas' : esc(R.anuales) + ' anuales') + '</dd>' +
      '</dl>' +
      '<span class="aviso-pisa">«Registrar en HestiaCP» <strong>sustituye</strong> estos valores para todas las cuentas. ' +
      'Si solo querías mirar, no lo pulses.</span>');
    // El campo se rellena con lo que hay: así no se cambia por teclearlo de nuevo
    if (campoRepo && !campoRepo.value) campoRepo.value = R.repo;
  } else {
    pintarEstado('#est-restic', 'vacio',
      'Restic no está configurado en este servidor. Nada que pisar.');
  }

  // El cron, en la misma sección: es el botón de al lado
  const cron = d.cron.lineas || [];
  const caja = $('#est-restic');
  if (caja && cron.length) {
    caja.insertAdjacentHTML('beforeend',
      '<div style="margin-top:.6rem"><strong>El cron ya está activo:</strong> ' +
      '<code>' + esc(cron[0]) + '</code><br>' +
      '«Activar su cron» comprobará que existe y <strong>no</strong> añadirá otro.</div>');
  } else if (caja && R.repo) {
    caja.insertAdjacentHTML('beforeend',
      '<div style="margin-top:.6rem;color:#f85149"><strong>El cron NO está activo.</strong> ' +
      'Restic está configurado pero no se ejecuta nunca. Pulsa «Activar su cron».</div>');
  }

  // --- 3. Claves ------------------------------------------------------------
  const C = d.claves;
  const conClave = C.con_clave || [], usuarios = C.usuarios || [];
  let txt = 'En el servidor hay <strong>' + usuarios.length + '</strong> cuenta(s) de HestiaCP y <strong>' +
            conClave.length + '</strong> con clave de cifrado propia' +
            (conClave.length ? ': ' + conClave.map(x => '<code>' + esc(x) + '</code>').join(', ') : '') + '.';
  if (C.rescatadas_aqui > 0) {
    txt += '<br>Rescatadas en este equipo: <strong>' + C.rescatadas_aqui + '</strong> archivo(s) en <code>' +
             esc(C.donde || '') + '</code>.' +
           '<span class="aviso-pisa">Rescatar otra vez <strong>no borra nada</strong>: cada rescate lleva la fecha ' +
           'en el nombre y se conservan los anteriores.</span>';
    pintarEstado('#est-claves', 'ok', txt);
  } else {
    txt += '<br><strong style="color:#f85149">No hay ninguna rescatada en este equipo.</strong> ' +
           'Si el servidor desapareciera hoy, el repositorio sería ilegible. Pulsa «Traer las claves del servidor».';
    pintarEstado('#est-claves', 'problema', txt);
  }

  marcarPisa(d);
  pintarEstadoGeneral(d);
}

// Las demás pestañas: qué hay ya, qué falta, y qué botón lo resuelve.
function pintarEstadoGeneral(d) {
  const cuando = (e) => {
    const dias = Math.floor((Date.now() / 1000 - e) / 86400);
    if (dias <= 0) return 'hoy';
    if (dias === 1) return 'ayer';
    return 'hace ' + dias + ' días';
  };
  const peso = (b) => (b / 1048576).toFixed(1) + ' MB';
  const srv = (d.servidor && d.servidor.zips) || [];
  const loc = (d.local && d.local.zips) || [];

  // Sin conexión no se sabe qué hay en el servidor. Decir «no está programado»
  // o «no hay respaldos» sería afirmar una ausencia que nadie comprobó: el
  // mismo error, del revés, que dar por bueno un canal de avisos sin probarlo.
  // Solo se afirma lo que sí se pudo mirar: lo que está en este equipo.
  if (!d.conectado) {
    const nose = (sel, que) => pintarEstado(sel, 'sin-datos',
      '<strong>No se pudo leer el servidor</strong>' + (d.detalle ? ': ' + esc(d.detalle) : '') +
      '.<br>No se sabe ' + que + '. Resuélvelo en la pestaña Servidor antes de fiarte de nada de aquí.');
    nose('#est-respaldar',    'qué respaldos tiene');
    nose('#est-programacion', 'si está programado');
    nose('#est-servidor',     'si está instalado allí');
    pintarEstado('#est-retencion', 'vacio',
      'Política configurada en este perfil: ' +
      esc((d.retencion || {}).BACKUP_RETENTION_DAYS || '?') + ' días de respaldos, mínimo ' +
      esc((d.retencion || {}).BACKUP_KEEP_MIN || '?') + ' intocables. ' +
      'No se pudo comprobar qué hay en el servidor.');
    const t = loc.length
      ? 'En este equipo hay ' + loc.length + ' respaldo(s) descargado(s); el más reciente, <code>' +
        esc(loc[0].archivo) + '</code>. No se pudo ver los del servidor.'
      : 'No hay respaldos en este equipo, y no se pudo consultar el servidor.';
    ['#est-verificar', '#est-restaurar', '#est-migrar'].forEach(x => pintarEstado(x, 'sin-datos', t));
    return;
  }

  // --- Respaldar ------------------------------------------------------------
  if (srv.length) {
    const u = srv[0];
    let h = '<strong>Hay ' + srv.length + ' respaldo(s) en el servidor.</strong> El último, ' +
            esc(cuando(u.epoch)) + ': <code>' + esc(u.archivo) + '</code> (' + peso(u.bytes) + ').';
    const dias = Math.floor((Date.now() / 1000 - u.epoch) / 86400);
    if (dias > 2) h += '<span class="aviso-pisa">Más de ' + dias + ' días. Si hay cron, podría estar parado: míralo en Programación.</span>';
    h += '<br>' + (loc.length
      ? 'Aquí tienes ' + loc.length + ' copia(s) descargada(s).'
      : '<strong style="color:#d29922">Ninguna copia en este equipo.</strong> Todos viven en el servidor: si lo pierdes, los pierdes con él.');
    pintarEstado('#est-respaldar', dias > 2 ? 'problema' : 'ok', h);
  } else {
    pintarEstado('#est-respaldar', 'sin-datos',
      '<strong>No hay ningún respaldo de bases de datos en el servidor.</strong> ' +
      'Pulsa «Respaldar en el servidor» aquí abajo para crear el primero, y luego ' +
      'prográmalo en la pestaña Programación para que no dependa de que te acuerdes.');
  }

  // --- Programación ---------------------------------------------------------
  const cctl = (d.cronctl && d.cronctl.lineas) || [];
  const crst = (d.cron && d.cron.lineas) || [];
  const av = d.avisos || {};
  const canales = Object.keys(av).filter(k => av[k]);
  let hp = '';
  hp += cctl.length
    ? '<strong>✓ Respaldo de bases de datos programado</strong> (' + cctl.length + ' tarea(s), visibles en el panel de HestiaCP):<dl>' +
      cctl.map(l => '<dd>' + esc(l) + '</dd>').join('') + '</dl>'
    : '<strong style="color:#f85149">✗ El respaldo de bases de datos NO está programado.</strong> ' +
      'Solo corre cuando lo lanzas a mano. Pulsa «Programar en el servidor».<br>';
  hp += crst.length
    ? '<strong>✓ Respaldo Restic programado:</strong> <code>' + esc(crst[0]) + '</code><br>'
    : '<strong style="color:#f85149">✗ Restic NO está programado.</strong> Actívalo en la pestaña HestiaCP.<br>';
  hp += canales.length
    ? '<strong>✓ Avisos por:</strong> ' + canales.map(c => '<code>' + esc(c) + '</code>').join(', ')
    : '<strong style="color:#f85149">✗ Sin ningún canal de aviso.</strong> Un respaldo fallido no avisaría a nadie.';
  if (canales.length && !av.HEALTHCHECK_URL) {
    hp += '<span class="aviso-pisa">Sin <code>HEALTHCHECK_URL</code>: el correo avisa cuando un respaldo ' +
          '<strong>corre y falla</strong>. Si el cron deja de ejecutarse no hay correo que mandar, y el silencio parece normal.</span>';
  }
  pintarEstado('#est-programacion',
    (cctl.length && crst.length && canales.length) ? 'ok' : 'problema', hp);

  // --- Servidor -------------------------------------------------------------
  const ctl = (d.servidor && d.servidor.backupctl) || '';
  pintarEstado('#est-servidor', ctl ? 'ok' : 'vacio', ctl
    ? '<strong>✓ Instalado en el servidor:</strong> <code>' + esc(ctl) + '</code>. ' +
      'Instalar de nuevo solo copia el código; el <code>env.sh</code> se compara antes y se avisa si difiere.'
    : '<strong>No está instalado en el servidor.</strong> Sin él, el servidor no puede respaldarse solo: ' +
      'las órdenes tendrían que salir siempre de este equipo. Empieza por «Ensayo: qué copiaría».');

  // --- Retención ------------------------------------------------------------
  const R = d.retencion || {};
  pintarEstado('#est-retencion', 'ok',
    '<strong>Política vigente</strong>, la misma que aplican las tareas automáticas:' +
    '<dl>' +
    '<dt>Respaldos</dt><dd>' + esc(R.BACKUP_RETENTION_DAYS || '?') + ' días</dd>' +
    '<dt>Logs</dt><dd>' + esc(R.LOG_RETENTION_DAYS || '?') + ' días</dd>' +
    '<dt>Claves Restic</dt><dd>' + esc(R.RESTIC_RETENTION_DAYS || '?') + ' días</dd>' +
    '<dt>Mínimo intocable</dt><dd>' + esc(R.BACKUP_KEEP_MIN || '?') + ' respaldos, pase lo que pase</dd>' +
    '</dl>' +
    '<span class="aviso-pisa">Aplicar la retención <strong>borra archivos</strong>. El mínimo protege de ' +
    'quedarte sin nada por una fecha mal puesta. Usa siempre antes el ensayo.</span>');

  // --- Verificar / Restaurar / Migrar --------------------------------------
  const ref = srv[0] || loc[0];
  const texto = ref
    ? 'Se trabajará sobre el respaldo más reciente salvo que elijas otro: <code>' +
      esc(ref.archivo) + '</code>, de ' + esc(cuando(ref.epoch)) + '.'
    : '<strong>No hay ningún respaldo todavía.</strong> Créalo primero en la pestaña Respaldar.';
  const clase = ref ? 'ok' : 'vacio';
  pintarEstado('#est-verificar', clase, texto +
    '<br>Verificar <strong>no toca</strong> ni el respaldo ni tus bases: lee el archivo y comprueba que está entero.');
  pintarEstado('#est-restaurar', ref ? 'problema' : 'vacio', texto +
    '<span class="aviso-pisa">Restaurar <strong>SUSTITUYE</strong> los datos que hay ahora por los del respaldo. ' +
    'Lo perdido desde esa fecha no vuelve. Haz antes un respaldo del estado actual.</span>');
  pintarEstado('#est-migrar', clase, texto +
    '<span class="aviso-pisa">Migrar <strong>escribe en el servidor de destino</strong>. Empieza siempre por el ensayo.</span>');
}

function pintarEstado(sel, clase, html) {
  const e = $(sel);
  if (!e) return;
  e.className = 'estado-real ' + clase;
  e.innerHTML = html;
}

// Reescribe el texto de confirmación de los botones que pisan algo, para que
// el aviso diga QUÉ se pierde, no un genérico «¿continuar?».
function marcarPisa(d) {
  const btnRestic = $('[data-act="hestia-restic"]');
  if (btnRestic) {
    btnRestic.dataset.confirmar = (d && d.restic && d.restic.repo)
      ? 'YA HAY UN REPOSITORIO CONFIGURADO EN ESTE HESTIACP:\n\n  ' + d.restic.repo +
        '\n\nSe va a SUSTITUIR por lo que hayas escrito arriba, para TODAS las cuentas.\n¿Seguro?'
      : 'Se registrará el host de respaldo Restic en HestiaCP. Ahora mismo no hay ninguno, así que no se pisa nada.';
  }
  const btnRclone = $('#btn-rclone');
  if (btnRclone) {
    const rem = (d && d.rclone && d.rclone.remotos) || [];
    btnRclone.dataset.confirmar = rem.length
      ? 'En el servidor ya existen estos remotos:\n\n  ' + rem.join(', ') +
        '\n\nSi el nombre que escribiste coincide con uno de ellos, sus claves se sustituyen.\nSe guarda copia de la versión anterior.\n¿Seguro?'
      : 'Se creará el remoto de rclone en el servidor. No hay ninguno todavía: no se pisa nada.';
  }
  const btnCron = $('[data-act="remote-hestia-cron"]');
  if (btnCron) {
    const hay = d && d.cron && (d.cron.lineas || []).length;
    btnCron.classList.toggle('ya-hecho', !!hay);
    btnCron.dataset.confirmar = hay
      ? 'El cron ya existe. Esta acción solo lo comprobará y NO añadirá un segundo.\n¿Continuar?'
      : 'Se activará el cron de Restic EN el servidor.';
  }
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
  const user = ($('#k-user').value.trim() || 'root');
  const host = $('#k-host').value.trim();
  const target = user + '@' + host;
  const password = $('#k-pass').value;
  if (!host || !password) { alert('Hacen falta el servidor y la contraseña.'); return; }
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
    ssh_user:    $('#f-ssh').value.trim() || 'root',
    owner:       $('#f-owner').value.trim() || 'admin',
    path:        $('#f-path').value.trim(),
    healthcheck: $('#f-hc').value.trim(),
    crear_db:    crear,
    db_user:     crear ? $('#f-newdbuser').value.trim() : $('#f-dbuser').value.trim(),
    db_pass:     crear ? '' : $('#f-dbpass').value,
    admin_user:  crear ? $('#f-adminuser').value.trim() : '',
    admin_pass:  crear ? $('#f-adminpass').value : '',
    desplegar:   $('#f-deploy').checked,
  };

  // Respaldos incrementales, si se han pedido en el mismo alta
  if ($('#f-restic').checked) {
    const tipo = $('#f-rctype').value;
    datos.rc_name     = $('#f-rcname').value.trim();
    datos.rc_type     = tipo;
    datos.rc_key      = $('#f-rckey').value.trim();
    datos.rc_secret   = $('#f-rcsecret').value;
    datos.rc_endpoint = $('#f-rcendpoint').value.trim();
    datos.rc_region   = $('#f-rcregion').value.trim();
    const ruta = $('#f-repo').value.trim();
    datos.repo = ruta ? ('rclone:' + datos.rc_name + ':' + ruta) : '';
    if (!datos.rc_name) { alert('Falta el nombre del remoto de rclone.'); return; }
    if (tipo === 's3' && (!datos.rc_key || !datos.rc_secret || !datos.rc_endpoint)) {
      alert('Para S3 hacen falta access key, secret y endpoint.\n\n' +
            'El endpoint es obligatorio: Mega S4 no es Amazon.');
      return;
    }
  }
  if (!datos.name || !datos.host) {
    alert('Hacen falta al menos el nombre del perfil y el servidor.');
    return;
  }
  if (!datos.path) datos.path = '/home/' + datos.owner + '/scripts';
  cerrarAlta();
  // Las contraseñas se limpian del formulario en cuanto se envían
  $('#f-dbpass').value = ''; $('#f-adminpass').value = ''; $('#f-rcsecret').value = '';
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

on('#pestanas', 'click', (ev) => {
  const p = ev.target.closest('.pestana');
  if (!p) return;
  $$('.pestana').forEach(x => x.classList.toggle('activa', x === p));
  $$('.tab').forEach(t => t.hidden = t.dataset.tab !== p.dataset.tab);
});

on('#btn-refrescar', 'click', cargarPanel);
on('#btn-nuevo', 'click', abrirAlta);
on('#btn-sshkey', 'click', abrirDialogoClave);
on('#clave-no', 'click', () => { $('#clave').hidden = true; $('#k-pass').value = ''; });
on('#clave-si', 'click', instalarClave);
on('#clave', 'click', (ev) => {
  if (ev.target === $('#clave')) { $('#clave').hidden = true; $('#k-pass').value = ''; }
});
on('#alta-no', 'click', cerrarAlta);
on('#alta-si', 'click', crearPerfil);
on('#f-restic', 'change', () => { $('#bloque-restic').hidden = !$('#f-restic').checked; });
on('#btn-rclone', 'click', configurarRclone);
on('#btn-rclone-repo', 'click', async () => {
  if (!(await confirmar('Se instalará en el servidor el rclone.conf que ya está ' +
                        'rescatado en este repositorio, con tus claves guardadas. ' +
                        'Se guardará copia de lo que hubiera antes.'))) return;
  ejecutar('hestia-rclone-repo', {});
});
on('#btn-sshkey2', 'click', abrirDialogoClave);
on('#rc-type', 'change', () => {
  const s3 = $('#rc-type').value === 's3';
  ['rc-key','rc-secret','rc-endpoint','rc-region'].forEach(
    id => { $('#'+id).closest('label').hidden = !s3; });
});
on('#btn-cargar-config', 'click', cargarConfig);
on('#btn-guardar-config', 'click', guardarConfig);
$$('input[name=db]').forEach(r => r.addEventListener('change', () => {
  const crear = document.querySelector('input[name=db]:checked').value === 'crear';
  $('#db-existente').hidden = crear;
  $('#db-crear').hidden = !crear;
}));
on('#alta', 'click', (ev) => { if (ev.target === $('#alta')) cerrarAlta(); });
on('#btn-limpiar', 'click', () => { limpiarConsola(''); marcarEstado('', ''); });
on('#btn-cerrar', 'click', () => {
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
