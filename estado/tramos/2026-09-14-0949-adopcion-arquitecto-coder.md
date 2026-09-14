# Tramo 2026-09-14 09:49 — Adopción del modelo arquitecto-coder

- **Inicio:** 2026-09-14 09:49 (el PO pega `.agents/`, `.claude/` y `.vscode/`)
- **Fin:** 2026-09-14 13:12 — **Duración:** 3 h 23 min
- **Mensajes:** #001–#016 (#016: reporte de la ronda que commitea esta documentación)
- **Mandato del PO:** «adaptar todos los insumos de este proyecto a la metodología
  arquitecto-coder», con permiso para consultar a la sesión anterior. Sobre el coder: «prefiero
  otro, y a ese úsalo solo en esta fase de configuración».

## Rondas

La configuración la hizo el arquitecto sin coder. Después:

| # | Qué | Resultado | Commits |
| --- | --- | --- | --- |
| #001→#002 | Saludo; el coder confirma (Claude Code / Sonnet 5, `master`) | completado | — |
| #003→#004 | Commitear la adopción en `chore/adopcion-arquitecto-coder` y fusionar | completado | `e26d637` `4021253` `4ebffe4` `70c9967` `b713923` `64ac581`; fusión `7977793` |
| #005→#006 | Banco de pruebas local (ADR 0009), rama `feat/banco-de-pruebas` | bloqueado: 2 críticos de revisión, sin fusionar | `9ff440f` `68ec043` `5672967` `80dbaad` `ddc93e8` `3b795cb` `c10cacf` `ce6b124` |
| #007→#008 | Corregir los críticos, endurecer, camino de fallo, mutaciones, fusionar | bloqueado: 1 crítico nuevo, sin fusionar; 6/6 mutaciones confirmadas | `b2ce989` `858910f` `76a0f64` `30b6f90` `0450cdd` `1e1680c` `e7ef47c` `e2df7b8` `f919645` `706faa4` `e440a02` |
| #009→#010 | Salvaguarda que falle en cerrado; advertencias 2, 3 y 5; mutaciones; fusionar | bloqueado: 1 crítico nuevo (PATH solo comprobado en `ejecutar.sh`); 5/5 mutaciones confirmadas | `18230d3` `0218ff6` `9add51e` `d5a7448` `553c7ab` |
| #011→#012 | Rediseño de salvaguardas (ADR 0010, reemplaza 0009), retención por nombre, evidencia previa | bloqueado: 1 crítico (rutas del perfil fuera del temporal, solo con una prueba modificada); 5/5 mutaciones; bug real T20 | `d94ed6e` `8206cf0` `f5d5b4b` `874be18` `860a30a` `6486ff4` |
| #013→#014 | Rutas del perfil, endurecimientos menores, fusionar | completado; 3/3 mutaciones; quinta revisión sin críticos (trazado con `strace`) | `9e3a0d1` `7a626db` `f1a3d46` `11285e2`; fusión `d5483d0` |
| #015→#016 | Commitear la documentación de cierre del tramo (rama `docs/cierre-tramo-adopcion`) y fusionar | enviada al cerrar | — |

Curador de contexto al cierre: sin falsedades en `context/`; T8 pasa a CUBIERTA; T18 cita el
ADR 0010; el roadmap pierde las dos tareas hechas; `HERENCIA.md` cumple ya una de sus cuatro
condiciones de borrado (falta cerrar lo pendiente en servidores).

Decisión de corte: la cuarta revisión bajó otra capa (un perfil escrito a mano con rutas
fuera). Se cierra, y desde aquí CRÍTICO exige que una suite existente sin modificar pueda
causar el daño. Si no, cada revisión encontraría un nivel más de «y si alguien escribe una
prueba mala», y el banco no se fusionaría nunca.

Decisión: tres críticos seguidos de la misma familia (salvaguarda que depende de su llamador)
indican un fallo de diseño, no de ejecución: ADR 0010. Se precisa además qué es CRÍTICO en la
revisión, para no bloquear por endurecimientos que no protegen de nada real.

Hallazgo de #008: el arquitecto había escrito en T18 (y en el ADR 0009) que `hestia` depende de
`/usr/local/hestia` escrito a mano; falso: `lib/hestia.sh` usa `$HESTIA_DIR` 23 veces. Corregido
en `context/`; el ADR no se edita.

Hallazgo de #006: dos afirmaciones pasaban con el código roto (demostrado por mutación por
`code-reviewer`). Y el arquitecto dictó en #005 nombres distintos de los del ADR 0009
(`despachador.sh` frente a `_despachador.sh`, `LANG=C.UTF-8` frente a `LC_ALL=C`); el ADR ya
estaba commiteado y no se edita: lo vigente está en `.agents/context/40-entorno.md`.

Hallazgo de esta preparación: la denegación `Read(./*/env.sh.*)` de `.claude/settings.json`
bloqueaba `config/env.sh.example`; corregida (solo `env.sh.anterior` y `env.sh.nuevo`).

## Encontrado y decidido

- El andamiaje pegado describía otro proyecto (plugins PHP de HestiaCP). Retirado al
  scratchpad de la sesión, sin borrar: 14 ADR, bitácora, herencia, contexto, la skill
  `nuevo-plugin-hestiacp` (el PO ya había borrado su carpeta y quedaba un symlink roto).
- La guarda pegada se activó al pegarla para todas las sesiones del directorio: bloqueó un
  `ssh` de la sesión anterior.
- Escritos: ADR 0001–0005, reglas 30/40/60, 9 personas, contexto 10–50, `HERENCIA.md`,
  roadmap, `AGENTS.md`, `CLAUDE.md`, guarda y sus pruebas (172 casos, sobre un repositorio
  sintético), `verificar.sh` para bash, Python, JS y la web.
- Hallazgos de seguridad: credenciales reales versionadas y en GitHub; token en la URL del
  remoto; la web devuelve el `env.sh` al navegador; `pull` escribe el diff del `env.sh` en
  `ESTADO.md`.
- 31 commits con `Co-Authored-By` en el remoto: `menciones_ia.py` revisa desde `4435064`.
- 🤖 en 5 líneas de documentación como marca de «generado»: cambiado a ⚙️.
- Coder: `serversbackupspersonalutility-68` (Opus 5, sesión nueva, confirmó directorio y que
  no escribió nada). La sesión anterior cerró su traspaso y no escribirá más.

## Respuestas del PO (2026-09-14)

- El `git add` de las 10:00 fue suyo, «para comparar».
- Pruebas en servidor: «prefiero probar yo si no hay garantía de seguridad» → ADR 0006.
- `git push`: «solo yo».
- Ramas: «master rama estable; ustedes pueden mergear y commitear cuando quieran, pero
  estable» → ADR 0007.
- Credenciales: «este repositorio es de uso propio, acá las guardo» → ADR 0008.
- Commits con `Co-Authored-By`: se quedan.
- Primera tarea: banco de pruebas local.
- Renombró las sesiones; el coder es una sesión nueva, `ServersBackupsPersonalUtility-Coder-Main`
  (no la -68). Pide que se le recuerden los `/rename` en cada arranque.

## Falló por el camino

- Hacia las 10:00:01, alguien ejecutó un `git add` sobre `.agents/`, `.claude/` y `.vscode/`
  sin orden, mientras el arquitecto escribía (deducido de qué archivos quedaron preparados tal
  cual y cuáles modificados después; `.git/index` con esa hora). Sin commits nuevos. Pendiente
  de saber quién; la primera ronda del coder vacía el índice.
- Un `mv`+`rm` en un solo comando fue denegado por el clasificador de permisos; se rehízo solo
  con `mv` al scratchpad.
- La guarda bloqueó un `grep` cuyo patrón contenía `v-add-database`: miraba el comando entero.
  Ahora mira solo la orden. Caso de prueba añadido.
- `git grep` con exclusiones `':!*/env.sh*'` se bloqueaba: la exclusión nombra el secreto.
  Corregido, con su caso.

## Espera al PO

1. Subir `master` a GitHub (`git push`): lleva la adopción y el banco.
2. Borrar, si quieres, las ramas ya fusionadas `chore/adopcion-arquitecto-coder`,
   `feat/banco-de-pruebas` y, tras #016, `docs/cierre-tramo-adopcion`.
3. Qué sigue. Candidata: arreglar T20 (`restore` cancelado deja volcados en `/tmp`), con su
   prueba en el banco.
4. `~/.local/bin/backupctl`: conservarlo o quitarlo.
5. Servidor de pruebas: baja, dos bloqueos de Restic, poda hacia principios de octubre.
6. En cada sesión nueva, los dos `/rename`.

## Resumen

Se adoptó el modelo arquitecto-coder: el andamiaje de otro proyecto se retiró entero y se
reescribió para `backupctl` (ADR 0001–0008), con una guarda que impide a los agentes tocar
servidores, MySQL, credenciales o el sistema del PO, probada sobre un repositorio sintético. El PO
decidió que las pruebas en servidor y las subidas a GitHub son solo suyas, que `master` es
estable y que las credenciales siguen versionadas.

Después se construyó el banco de pruebas local (`tests/`, ADR 0010): 5 suites y 51
afirmaciones que ejecutan `backupctl` de verdad contra imitaciones de `mysql`, `ssh` y compañía.
Llevó cinco rondas de revisión: cuatro defectos críticos en las propias pruebas, encontrados y
cerrados, 19 mutaciones que lo demuestran, y una última revisión sin críticos trazada con
`strace`. El banco encontró un bug real de `backupctl` (T20) que espera la decisión del PO.
