# Tramo 2026-09-14 09:49 — Adopción del modelo arquitecto-coder

- **Inicio:** 2026-09-14 09:49 (el PO pega `.agents/`, `.claude/` y `.vscode/`)
- **Fin:** *(abierto: espera al PO)* — **Duración:** *(al cerrar)*
- **Mensajes:** ninguno todavía (el primero será `#001`)
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
| #011→#012 | Rediseño de salvaguardas (ADR 0010, reemplaza 0009), retención por nombre, evidencia previa | en vuelo | — |

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

Lo mismo que `estado/AHORA.md`, «Espera al PO».

## Resumen

*(al cerrar)*
