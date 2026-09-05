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
async function ejecutar(accion, arg) {
  if (ejecutando) return;
  if (!perfilActual) { limpiarConsola('Elige un servidor primero.'); return; }

  ejecutando = true;
  $$('.btn').forEach(b => b.disabled = true);
  marcarEstado('ejecutando…', 'etq-warn');
  limpiarConsola('');
  anadirLinea(`$ backupctl -p ${perfilActual} ${accion}${arg ? ' ' + arg : ''}`);
  anadirLinea('');

  try {
    const r = await api('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ profile: perfilActual, action: accion, arg: arg || null }),
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
    if (perfilActual) cargarRespaldos(perfilActual);
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
            ev.stopPropagation(); seleccionar(p.name); ejecutar('config', null);
          }, { once: false });
        }
        if (p.destino) {
          b.addEventListener('click', (ev) => {
            ev.stopPropagation(); seleccionar(p.name); ejecutar('remote-status', null);
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

// --- Detalle de un perfil ----------------------------------------------------
function seleccionar(nombre) {
  perfilActual = nombre;
  $('#titulo-perfil').textContent = nombre;
  $('#panel-detalle').hidden = false;
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
    cont.querySelectorAll('[data-inspect]').forEach(b =>
      b.addEventListener('click', () => ejecutar('inspect', b.dataset.inspect)));
  } catch (e) {
    cont.innerHTML = '<p class="ayuda n-error">' + esc(e.message) + '</p>';
  }
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// --- Eventos -----------------------------------------------------------------
document.addEventListener('click', async (ev) => {
  const b = ev.target.closest('[data-act]');
  if (!b) return;
  const aviso = b.dataset.confirmar;
  if (aviso && !(await confirmar(aviso))) return;
  ejecutar(b.dataset.act, null);
});

$('#pestanas').addEventListener('click', (ev) => {
  const p = ev.target.closest('.pestana');
  if (!p) return;
  $$('.pestana').forEach(x => x.classList.toggle('activa', x === p));
  $$('.tab').forEach(t => t.hidden = t.dataset.tab !== p.dataset.tab);
});

$('#btn-restore-test').addEventListener('click', async () => {
  const bd = $('#bd-prueba').value.trim();
  if (!bd) { limpiarConsola('Escribe el nombre de una base de datos.'); return; }
  const ok = await confirmar(
    `Se creará una base de datos temporal, se restaurará "${bd}" dentro y se ` +
    `eliminará al terminar. Tu producción no se toca.`);
  if (ok) ejecutar('verify-restore-test', bd);
});

$('#btn-refrescar').addEventListener('click', cargarPanel);
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
