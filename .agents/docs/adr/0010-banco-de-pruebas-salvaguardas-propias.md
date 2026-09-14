# 0010 — Banco de pruebas: cada salvaguarda se comprueba a sí misma

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Arquitecto, por mandato del PO («banco de pruebas local»)
- **Estructural:** sí (dónde viven las pruebas y qué garantiza el banco)
- **Reemplaza:** 0009

## En cristiano

El banco de pruebas ejecuta `backupctl` de verdad en esta máquina, pero con imitaciones de
`mysql`, `ssh` y compañía, dentro de una carpeta temporal. Esta decisión corrige la anterior en
un punto: las protecciones del banco no pueden depender de que se lance por la puerta buena.
Cada pieza comprueba por sí misma que las imitaciones están delante, que la carpeta es la del
banco y que la creó el lanzador oficial; si algo falla, no ejecuta nada. Así una prueba lanzada
a mano, al depurar, tampoco puede acabar hablando con un MySQL o un servidor reales.

## Contexto

- El ADR 0009 describió el banco antes de construirlo. Tres revisiones de `code-reviewer`
  (rondas #006, #008 y #010) encontraron, cada una, una salvaguarda que **fallaba en abierto**
  porque dependía de su llamador:
  1. los contadores vivían en variables y se perdían en una subshell;
  2. con `BANCO_TMP` vacío, la comparación de rutas aceptaba cualquier ruta;
  3. la comprobación de que `mysql`, `ssh`… resuelven a sus falsos vivía solo en
     `tests/ejecutar.sh`: una suite lanzada a mano usaba el `PATH` real (en esta máquina hay
     `mysql`, `restic` y `rclone` instalados; `40-entorno.md`).
- Además, lo construido difiere del 0009 en nombres (`despachador.sh`, sin `tests/datos/`,
  entorno con `env -i` y `LANG=C.UTF-8`) y en alcance (`hestia` usa `$HESTIA_DIR` y se puede
  cubrir en parte; T18).

## Decisión

Lo del ADR 0009 sigue (órdenes falsas delante en el `PATH`, perfiles sintéticos, `tests/`,
bash sin dependencias), con este diseño, que es el vigente:

| Pieza | Qué garantiza por sí misma |
| --- | --- |
| `tests/falsos/ordenes.txt` | Lista única de órdenes peligrosas. La leen `ejecutar.sh` y `lib.sh`: no hay dos copias que diverjan |
| `tests/ejecutar.sh` | Crea el temporal en `/tmp/backupctl-pruebas.XXXXXX` **sin depender de `TMPDIR`**; escribe en él una marca `.banco` con un testigo aleatorio y lo pasa a las suites como `BANCO_TESTIGO`; crea los enlaces a los falsos; lanza cada suite con `env -i` |
| `tests/lib.sh`, al cargarse | Antes de crear o borrar nada: `BANCO_TMP` y `BANCO_RAIZ` válidas; la marca del directorio padre de `BANCO_TMP` coincide con `BANCO_TESTIGO`; **cada orden de `ordenes.txt` resuelve con `command -v` a `<temporal>/bin/<orden>`, y ese es un enlace a `tests/falsos/despachador.sh`**. Si algo falla, `exit 2` |
| `backupctl_prueba` | Repite la comprobación del `PATH` justo antes de ejecutar; exige que el perfil esté dentro de `BANCO_TMP` y que su `env.sh` no sea un enlace simbólico |
| Cada suite | `source` de `lib.sh` con `|| exit 2` |
| `tests/falsos/despachador.sh` | `set -u`; sin `BANCO_TMP` válido, sale con 96 sin registrar nada; nunca ejecuta la orden real |
| Afirmaciones | Se cuentan en un archivo; una suite con 0 afirmaciones falla; una afirmación sobre un archivo o directorio exige antes que exista |

Práctica obligatoria: **cada afirmación clave se demuestra con una mutación** (se estropea el
código en una copia con `bin/ lib/ tests/` en un temporal y la prueba tiene que ponerse en
rojo).

Alcance: perfil, respaldo, verificación, retención y restauración hoy; `hestia` se puede cubrir
con `HESTIA_DIR` en el temporal salvo el crontab de `hestiaweb`; `adoptar` necesita antes un
cambio de código (T18).

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Mantener las salvaguardas solo en `ejecutar.sh` | Es lo que produjo los tres fallos en abierto: depurar una suite suelta es el gesto natural |
| Comprobar el `PATH` sin marca | Un directorio cualquiera llamado `/tmp/backupctl-pruebas.*` con enlaces propios pasaría; la marca con testigo liga la suite al lanzador que la creó |
| Dos listas de órdenes peligrosas | Divergen: la que se amplía en `ejecutar.sh` no protege a `lib.sh` |
| `bats` | Sigue sin estar instalado; es una dependencia (00-core) |

## Consecuencias

- Una suite no se puede lanzar a mano sin reproducir el entorno de `ejecutar.sh`: para depurar,
  se ejecuta `tests/ejecutar.sh` (tarda segundos).
- Los falsos pueden mentir: una prueba en verde no demuestra que MySQL real responda igual. La
  prueba del PO en un servidor sigue siendo necesaria (ADR 0006).
- Más código de salvaguarda que de prueba. Es el precio de probar una herramienta que, mal
  lanzada, habla con producción.

## Reversión

1. `git rm -r tests/`.
2. `verificar.sh` tolera su ausencia («NO HAY»).
3. Quitar las menciones en `.agents/context/40-entorno.md` y `20-convenciones.md`.

## Verificación

`bash tests/ejecutar.sh` sale con 0. Lanzar una suite a mano con `BANCO_RAIZ` y `BANCO_TMP`
exportados, sin pasar por `ejecutar.sh`, aborta con código 2 antes de ejecutar nada.
