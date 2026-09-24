# Ahora

- **Actualizado:** 2026-09-23, noche.
- **Último mensaje:** #061 (ARQ). El próximo será #062. Ronda en vuelo: correcciones del
  diagnóstico (H6–H12 del reporte #060).
- **Tramo abierto:** `estado/tramos/2026-09-23-2300-fases-1-y-2.md`. Mandato del PO: «Dale fase
  1 y 2».
- **Ramas:** solo `master` (estable, sin la 2.1) y `release/2.1`, con todo el trabajo. El PO
  pidió unificar. `master` espera su prueba en un servidor (ADR 0007 y 0013).
- **Aviso de fechas:** el arquitecto estuvo fechando documentos como 2026-09-24 durante la
  madrugada; el reloj dice **2026-09-23**. Corregidos `estado/`; quedan por corregir la fecha
  del ADR 0017 y la de la sección nueva de `.agents/context/50-hestiacp.md` (no se tocan con una
  ronda en vuelo).

## Espera al PO

1. **Su servidor de producción funciona**: repositorio en `/IncrementalBackups/stc-admin`,
   instantánea `200953a7` comprobada, cron a la 01:00 en el crontab de `hestiaweb`.
2. **Mañana:** comprobar que el cron respaldó —**con `restic snapshots`, no con el panel**, ver
   el aviso de abajo— y rehacer el `.tgz` de las claves, que cada cuenta nueva trae la suya.
3. **AVISO GRAVE, verificado hoy en la fuente de HestiaCP 1.10.4:** `v-backup-user-restic` usa
   una constante de error que no existe (`E_BACKUP`), así que **un respaldo que falla termina
   registrando éxito**. Ni el código de salida ni ningún log valen como prueba. Solo vale una
   instantánea con fecha.
4. **Decidido con él, sin ejecutar:** puede quitar el respaldo clásico (`v-backup-users`, 05:10)
   y borrar `/backup/*.tar`. **No** debe vaciar `BACKUP_SYSTEM`: apagaría también los
   incrementales.
5. Fuera del alcance de los respaldos, visto en su servidor: `public_html` en `777`, y
   `secure-keys/` y `dumps/` dentro de la raíz web.
6. `git push` cuando quiera. `rm ~/.local/bin/backupctl` sigue pendiente.
7. **AVISO (T21):** antes de un `adoptar --to` real, copiar el `restic.conf` del destino y
   compararlo al terminar.
8. Los dos `/rename`, que el arquitecto le da al abrir y al cerrar cada sesión.

## Dónde va la versión 2.1 (ADR 0013)

- **Fase 1 — terminada** (#053–#056). La CLI valida lo que validaba la web; cerrada la clase
  entera de valores sin escapar que llegaban a órdenes con privilegios.
- **Fase 2 — en curso.** Pieza 1: el diagnóstico de `hestia status`, que pasa de describir la
  configuración a decir si funciona. El juicio vive en funciones puras probadas sin servidor.
  Falta: las acciones que escriben, con su informe (ADR 0014), y el resto de pasos del ADR 0017.
- **Fases 3 y 4** sin empezar. La 3 (interfaz) necesita una sesión de diseño con el PO.

## Pendiente del arquitecto, anotado para no perderlo

- **La guarda bloquea `git commit` por el TEXTO del mensaje** (H13 de #060): nombrar una
  herramienta prohibida en prosa, dentro de `-m`, se toma por una orden. El coder tuvo que
  empobrecer dos mensajes de commit. Hay que mirar la posición de orden, no la aparición del
  texto, con su prueba en `probar_guardia.py`.
- **El formato de las instantáneas no lo decide HestiaCP** (H8 de #060): la orden que las lista
  no formatea nada, solo deja pasar la salida de la herramienta de respaldo instalada. Las
  claves del json dependen de SU versión, no de la de HestiaCP. El parseo nuevo se apoya solo en
  `time` por eso. La ficha de `.agents/context/50-hestiacp.md` habla de ese formato como si
  fuera de HestiaCP: hay que corregirla.
- **Sin verificar contra un servidor real** (H9 de #060): que la columna de la última
  instantánea de `hestia users` siga saliendo igual tras pedir json. Probado solo con datos
  sintéticos en el banco.

## Para una sesión nueva

- Lee el tramo abierto, el del incidente (`2026-09-23-2145`), y los ADR 0013, 0014, 0015 y
  **0017** (el 0016 está reemplazado).
- `.agents/context/30-trampas.md` T2, T20–T26, y `50-hestiacp.md` entero: lo verificado ahí no
  se vuelve a verificar.
