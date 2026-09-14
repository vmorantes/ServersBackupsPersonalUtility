# 0002 — Banco de pruebas local

- **Fecha:** 2026-09-14
- **Pedido por:** Product Owner («banco de pruebas local», respuesta 7 del 2026-09-14)
- **ADR relacionados:** 0006, 0009 (reemplazado), 0010

## Qué se pidió

Tras decidir que las pruebas contra un servidor las hace solo el PO (ADR 0006), la primera
tarea de producto: un banco que permita probar `backupctl` sin servidor.

## Qué se encontró al explorar

- No existía ninguna prueba. `mysql`, `mysqldump`, `ssh`… se invocan por nombre: la única forma
  de sustituirlos sin tocar el código es anteponer falsos en el `PATH`.
- Sin terminal, `backup` no escribe nada en pantalla: todo va a su log. `backup` exige que
  `BACKUP_WORK_DIR` exista antes de crearlo (el bloqueo va primero).
- `backup` llama a `mysql` dentro de un `while read`: un falso que leyera la entrada estándar se
  comería la lista de bases.
- `lib/hestia.sh` sí usa `$HESTIA_DIR`; el que no se puede probar sin tocar código es
  `lib/adoptar.sh` (el arquitecto lo había escrito mal en T18 y en el ADR 0009).

## Qué se instruyó

#005 el banco y cinco suites (perfil, respaldo, verificación, retención, restauración). #007,
#009, #011 y #013, correcciones tras cada revisión. Desde #007, cada afirmación clave se
demuestra con una mutación en una copia en un temporal. En #011, rediseño (ADR 0010). En #013,
criterio de corte para la revisión.

## Qué reportó el coder

- #006: 28 afirmaciones en verde, pero `code-reviewer` demostró por mutación que dos pasaban con
  el código roto (la restauración no comprobaba el `CREATE DATABASE`; los fallos de la
  salvaguarda se perdían en una subshell).
- #008: corregidas; 6 mutaciones confirmadas. Crítico nuevo: con `BANCO_TMP` vacío la
  comparación de rutas aceptaba cualquiera.
- #010: corregido; 5 mutaciones. Crítico nuevo: la comprobación del `PATH` solo existía en el
  lanzador; una suite lanzada a mano usaba `mysql`, `ssh`, `restic` y `rclone` reales.
- #012: ADR 0010 implementado; 5 mutaciones. Crítico nuevo (con una prueba modificada): un perfil
  podía declarar rutas fuera del temporal. Y **un bug real de `backupctl`** (T20).
- #014: corregido; 3 mutaciones; la quinta revisión, con el criterio de corte, sin críticos, y lo
  demostró trazando la batería con `strace`: ninguna orden real, ninguna escritura fuera del
  temporal. Fusión `d5483d0`. 51 afirmaciones, 5 suites.
- Desviación aceptada: en #014, dos commits repartieron distinto los cambios de `tests/lib.sh`.

## Qué quedó fuera

- T20 (`restore` cancelado deja volcados en `/tmp`): bug de producto, decide el PO.
- Suites de `ssh`/`deploy`/`pull`/`remote`, `hestia`, y las confirmaciones con defecto «sí»
  (`install`, `cron --install`, `deploy`; T5).
- Advertencias de la quinta revisión (perfil leído por posición, `NOTIFY_COMMAND` sin auditar,
  rutas relativas, `nueva_prueba` sin comprobar su `cd`): todas exigen escribir una prueba
  equivocada; al roadmap.

## Aprendido

- **Una batería en verde no dice nada hasta que se la ve fallar.** Las dos primeras afirmaciones
  rotas solo aparecieron al estropear el código a propósito. La mutación es ahora práctica
  obligatoria (ADR 0010).
- **Tres fallos seguidos de la misma familia son un fallo de diseño.** Parchear cada salvaguarda
  que dependía de su llamador no convergía; hacer que cada una se compruebe a sí misma, sí.
- **Una revisión sin criterio de corte no termina**: cada vuelta encontraba un nivel más de «y si
  alguien escribe una prueba mala». El criterio (suite existente, sin modificar, daño real o
  código roto en verde, demostrado) cerró el tramo sin rebajar lo que importa.
- **El arquitecto también se equivoca al dictar**: nombres distintos de su propio ADR y una
  afirmación falsa sobre `hestia`. La revisión del coder los encontró; un ADR commiteado no se
  parchea, se reemplaza.
- El banco ya ha pagado su coste: encontró un bug real (T20) que nadie había visto en un
  servidor.
