# Tramo 2026-09-23 — Incidente de incrementales en producción y sus arreglos

- **Inicio:** 2026-09-23 ~21:45 (tras resolver el incidente con el PO)
- **Fin:** *(al cerrar)* — **Duración:** *(al cerrar)*
- **Mensajes:** #035–
- **Mandato del PO:** «Renombrados, trabajen en los arreglos encontrados.»

## De dónde sale este tramo

El PO configuró los incrementales en un servidor de producción siguiendo
`docs/hestiacp/protocolo-manual.md`. Tres errores de esa guía le crearon un repositorio de
respaldos **dentro de un `public_html`**, servido por internet, y dejaron el respaldo sin
funcionar. Resuelto con él por chat: repositorio rehecho en `/IncrementalBackups/stc-admin`,
instantánea `200953a7` de 2.4 GiB comprobada con `restic snapshots`, claves copiadas fuera.

Documentación ya corregida por el arquitecto (sin commitear al abrir el tramo):
`docs/hestiacp/protocolo-manual.md` (pasos 3, 4, 5 y 8), `docs/hestiacp/respaldos-incrementales.md`,
`.agents/context/30-trampas.md` (T24, T25, T26), `.agents/docs/roadmap.md`,
`.agents/rules/30-protocolo-coder.md` (los `/rename` también al cerrar, pedido del PO).

## Lo que el incidente demostró del código

| # | Qué miente o falta | Dónde |
| --- | --- | --- |
| T26 | «Anuales ilimitadas» para `KEEP_YEARLY=-1`, cuando no hay regla anual | `lib/hestia.sh:164,360,365,375`, `web/app.js:450` |
| T24 | El asistente propone una ruta **relativa** por defecto (`hestiacp/`) y nadie mira el tipo del remoto | `lib/hestia.sh:359` |
| T24 | Nada impide registrar una ruta dentro de `/home/*/web/*` | `lib/hestia.sh` |
| T25 | «Contraseña sin repositorio» no se diagnostica | fase 2 |
| — | El cron se da por bueno esté donde esté | fase 2 |
| — | Las bases excluidas no se muestran | fase 2 |

Las dos primeras son esta ronda; el resto queda en el roadmap para la fase 2.

## Rondas

| # | Qué | Resultado | Commits |
| --- | --- | --- | --- |
| #035→ | Commitear la documentación del incidente; rama nueva desde `release/2.1`: retención sin mentiras (A) y rutas de repositorio seguras (B) | en vuelo | — |

## Encontrado y decidido

- La documentación del incidente se commitea en `fix/limpieza-al-salir` (donde estaba el árbol) y
  llegará a `master` con la fusión de la fase 1. No se desvía por una rama aparte: el PO ya tiene
  las correcciones en el chat y en el árbol.
- Los arreglos de código van en rama propia (`fix/incrementales-rutas`) desde `release/2.1`, para
  que se revisen sin arrastrar la fase 1.
- La validación de rutas se extrae a una función pura (`bc_hestia_validar_repo`) para poder
  probarla en el banco sin servidor.

## Falló por el camino

## Espera al PO

Ver `estado/AHORA.md`.

## Resumen

*(al cerrar)*
