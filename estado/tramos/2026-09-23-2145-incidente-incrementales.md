# Tramo 2026-09-23 — Incidente de incrementales en producción y sus arreglos

- **Inicio:** 2026-09-23 ~21:45 (tras resolver el incidente con el PO)
- **Fin:** 2026-09-24 ~00:30 — **Duración:** unas 3 h
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
| #035→#036 | Commitear la documentación del incidente; rama nueva desde `release/2.1`: retención sin mentiras (A) y rutas de repositorio seguras (B) | completado; dos mutaciones demostradas | `9b9e4a8` `0de2dc6` (docs, en `fix/limpieza-al-salir`); `9f2f6d3` `f342c41` |
| #038→#039 | Cerrar los hallazgos de las dos revisiones | completado; 15 afirmaciones en la suite nueva, cuatro mutaciones | `f16f18c` `b07d51e` (cherry-pick) `9586ebf` `1c2ea41` `8b9df77` |
| #041→#042 | Acotar la validación a los esquemas donde aplica; fusionar en `release/2.1` | completado; 22 afirmaciones, fusión limpia, rama borrada | `75047b5`; fusión `b811405` |

## Hallazgos de las revisiones de #036 (código y seguridad coincidieron en lo grave)

- **Inyección de órdenes como root (CRÍTICO, preexistente).** El repositorio del alta de la web
  (`web/server.py`, sin validador) y de `--repo` llegaba sin validar a órdenes que corren como
  root. Demostrado en aislado. El botón «Registrar en HestiaCP» sí validaba.
- **La validación se rodeaba**: solo miraba repositorios `rclone:`, y HestiaCP acepta rutas
  locales, así que `--repo /home/u/web/…` repetía el incidente.
- **`--dry-run` tocaba el servidor** y podía instalar rclone por apt antes de enseñar nada.
- **«Ruta absoluta» no protege en un remoto `alias`** (verificado en la fuente de rclone): manda
  la raíz del alias. Los envolventes (`crypt`, `union`, `combine`, `chunker`, `compress`) ni se
  miraban, y el tipo se comparaba distinguiendo mayúsculas.
- **Se degradaba a aviso** si no se podía determinar el tipo; con `-y` eso no protege a nadie.
- **`setup` programaba el cron aunque el registro fallara**, y dejaba `BC_DELIBERATE_EXIT=1`,
  enmudeciendo el trap ERR del resto del alta.
- **La web seguía enseñando la ruta relativa** que causó el incidente.
- Las credenciales de `rclone.conf` cruzaban el canal antes de filtrarse: ahora el filtrado corre
  en el servidor.

## Encontrado y decidido

- La documentación del incidente se commitea en `fix/limpieza-al-salir` (donde estaba el árbol) y
  llegará a `master` con la fusión de la fase 1. No se desvía por una rama aparte: el PO ya tiene
  las correcciones en el chat y en el árbol.
- Los arreglos de código van en rama propia (`fix/incrementales-rutas`) desde `release/2.1`, para
  que se revisen sin arrastrar la fase 1.
- La validación de rutas se extrae a una función pura (`bc_hestia_validar_repo`) para poder
  probarla en el banco sin servidor.

## Falló por el camino

- **El arquitecto se precipitó dos veces.** Primero dio por hecho que el remoto `local` del PO
  era la trampa T23 (nuestra herramienta vaciando `rclone.conf`); el PO aclaró que el destino
  local es deliberado. Después, al dictar #038, mandó aplicar todas las reglas a todos los
  esquemas: eso rechazaba repositorios legítimos de `s3:` y `sftp:`. Lo cazó la lectura del
  código antes de fusionar, no las pruebas (#041).
- La documentación del incidente hubo que traerla por `cherry-pick` a la rama nueva: al crear
  una rama desde `release/2.1` el árbol mostró las versiones viejas de esos archivos. Es la misma
  lección del 2026-09-14, que ya estaba escrita y se volvió a tropezar con ella.

## Espera al PO

Ver `estado/AHORA.md`.

## Resumen

Un servidor de producción del PO se rompió siguiendo nuestra documentación: tres errores de la
guía manual (ruta relativa, inicializar el nivel equivocado y mandar el cron a la pestaña del
panel) le dejaron un repositorio de restic dentro de un `public_html` servido por internet y el
respaldo sin funcionar. Se resolvió con él por chat, verificando cada paso contra la fuente de
HestiaCP 1.10.4: repositorio rehecho, instantánea comprobada por fuera, claves copiadas fuera del
servidor. Después se corrigió la documentación (cuatro errores, incluido uno de retención: `-1`
no es «ilimitadas», es «sin ese tramo», y vale para las cinco variables) y se llevó al código lo
que habría impedido el incidente: una validación que rechaza rutas relativas con remotos que
resuelven contra el sistema de archivos, rutas dentro de `/home/*/web`, y repositorios con
caracteres que permitían **ejecutar órdenes como root** —un agujero que ya existía y que nadie
había visto—. Todo fusionado en `release/2.1` con el banco en verde. Lo aprendido del ciclo
completo de los incrementales (interruptores, área de preparación, cron) quedó en
`.agents/context/50-hestiacp.md` y alimenta la fase 2.
