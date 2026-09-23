# Ahora

- **Actualizado:** 2026-09-23, incidente en producción del PO (servidor `stc-admin`).
- **Último mensaje:** #035 (ARQ). El próximo será #036. Ronda en vuelo con el coder.
- **Tramo abierto:** `estado/tramos/2026-09-23-2145-incidente-incrementales.md`. El del 16 quedó
  cerrado.
- **El PO no está.** Dijo: «No estaré, así que trabajen solos», y que sea rápido, solo estos
  hallazgos. Nada de ampliar el alcance ni esperarle.
- **Sin commitear:** este archivo, el tramo del 16, y las correcciones de documentación de hoy
  (`docs/hestiacp/protocolo-manual.md`, `docs/hestiacp/respaldos-incrementales.md`,
  `.agents/context/30-trampas.md`, `.agents/docs/roadmap.md`). Rama `fix/limpieza-al-salir`.
  Las commitea la primera ronda de la próxima sesión, en commits `docs:` y `docs(estado):`.

## El incidente del 2026-09-23 (documentación que hizo daño)

El PO configuró incrementales en un servidor de **producción** siguiendo
`docs/hestiacp/protocolo-manual.md`. Tres errores de esa guía, los tres corregidos hoy:

1. El ejemplo de `restic init` usaba una **ruta relativa**. Con su remoto de rclone de tipo
   `local`, la ruta se resolvió desde el directorio de trabajo y el repositorio se creó **dentro
   de un `public_html`**, servido por internet (T24).
2. Mandaba inicializar la **ruta registrada**, que es el padre: HestiaCP guarda un repositorio
   **por cuenta** en `<ruta>/<cuenta>`. El repositorio quedó huérfano y el respaldo siguió
   fallando (T25).
3. Ofrecía la **pestaña *Cron* del panel** para programar `v-backup-users-restic`. Eso escribe en
   el crontab de una cuenta, sin `sudo` ni `PATH`: el PO tenía ahí
   `30 5 * * * v-backup-users-restic`, que probablemente no ha respaldado nunca.

Sobre el remoto `local` el arquitecto se precipitó: dio por hecho que era la trampa T23 (nuestra
herramienta vaciando `rclone.conf`) y el PO aclaró que el destino local es **intencionado**.

Guía de recuperación entregada al PO: apartar la contraseña de la cuenta para que HestiaCP
inicialice solo, rehacer `/IncrementalBackups` con permisos 700, activar `BACKUPS_INCREMENTAL`,
respaldo manual, comprobación con `restic snapshots` y copia de las contraseñas fuera del
servidor. Pendiente de su salida.

## Espera al PO

1. Ejecutar `/root/rehacer-incrementales.sh` y pegar la salida.
2. Bajarse a su máquina `/root/claves-restic-*.tgz`: sin esas contraseñas, ningún repositorio se
   vuelve a abrir.
3. Mañana, comprobar si el cron de las 05:30 respaldó de verdad (`restic ... snapshots`). Si no,
   moverlo al crontab de `hestiaweb` con ruta absoluta.
4. Fuera del alcance de los respaldos, visto en su servidor: `public_html` entero en `777` y los
   directorios `secure-keys/` y `dumps/` dentro de la raíz web.
5. **AVISO (T21):** antes de un `adoptar --to` real, copiar el `restic.conf` del destino y
   compararlo al terminar.
6. En este servidor, no usar todavía `backupctl hestia rclone` ni «Configurar el remoto» de la
   web (T23, corregido en `fix/limpieza-al-salir`, sin publicar).
7. `git push` de `master` cuando quiera. `rm ~/.local/bin/backupctl` sigue pendiente.
8. Los dos `/rename`, que el arquitecto le da al abrir y al cerrar cada sesión (pedido el
   2026-09-23; antes solo al abrir).

## Siguiente (mandato del PO: versión 2.1, ADR 0013)

Fase 1, segunda vuelta (#032), en `fix/limpieza-al-salir`: quedan S4 (menciones a agentes en
comentarios; hoy `verificar.sh` falla solo por `lib/adoptar.sh:39`), S5, S6, S7, S8 y la parte C
(revisiones y fusión en `release/2.1`). Hechos: A, S1, S2, S3.

La fase 2 (ADR 0016) crece con lo aprendido hoy: ver el bloque nuevo del roadmap. Lo de hoy no es
teoría, es un servidor de producción que se rompió siguiendo nuestra documentación.

## Para una sesión nueva

- Lee el tramo del 16, ADR 0013–0016 y `.agents/context/30-trampas.md` T2, T20–T25.
- Ramas: `master` (estable), `release/2.1` (versión en curso), `fix/limpieza-al-salir` (fase 1).
