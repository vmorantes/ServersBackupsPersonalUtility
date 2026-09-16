# Ahora

- **Actualizado:** 2026-09-16 — mandato del PO: versión 2.1 estable (ADR 0013).
- **Último mensaje:** #032 (ARQ) — fase 1, segunda vuelta: corregir los hallazgos graves de las
  revisiones de #031 y volver a revisar. Se espera #033. (#031: C1–C7 commiteados en
  `fix/limpieza-al-salir`; no se fusionó: las revisiones encontraron que las señales podían truncar
  la devolución de `restic.conf`, una expansión aritmética con datos del servidor que permite
  ejecutar órdenes locales, una limpieza con secretos que no avisa si falla, y menciones a agentes
  en comentarios de código.)
- **Tramo en curso:** `estado/tramos/2026-09-16-1400-version-2-1.md`. En el árbol, sin commitear:
  ADR 0013, roadmap, este archivo y el tramo; los commitea la primera ronda.

## Espera al PO

- **AVISO nuevo (T23)**: si alguna vez usaste en la web «Configurar el remoto» o «Reusar las
  claves guardadas» (pestaña HestiaCP) contra un servidor, la versión actual pudo dejar **vacío**
  su `/root/.config/rclone/rclone.conf` diciendo que lo había escrito. Compruébalo en ese
  servidor: `wc -c /root/.config/rclone/rclone.conf` (si da 0 o muy poco, la copia anterior está
  en `/root/.config/rclone/rclone.conf.anterior`). Sin ese archivo, los respaldos incrementales
  de ese servidor no pueden llegar al almacenamiento.

0. **Decisión tomada por el arquitecto, revertible por ti:** «activar los incrementales sin
   HestiaCP» se entiende como hacerlo desde la herramienta, sin entrar al panel ni a su consola,
   pero usando por debajo el mecanismo de Restic de HestiaCP (así la pantalla del panel que lista y
   restaura esas copias sigue funcionando). Si querías un Restic propio al margen de HestiaCP,
   dilo.

1. **AVISO para tu migración real** (T21, en `master` hoy):
   - `adoptar --to` puede dejar **vacío** el `/usr/local/hestia/conf/restic.conf` del servidor de
     destino **al terminar, aunque todo vaya bien**, y decir que lo devolvió; y si falla al leerlo,
     puede **borrarlo**. Solo importa si ese servidor ya tenía su propio respaldo Restic.
   - Antes de migrar, en el destino:
     `cp /usr/local/hestia/conf/restic.conf /root/restic.conf.antes-de-adoptar`
   - Después: `diff /usr/local/hestia/conf/restic.conf /root/restic.conf.antes-de-adoptar` → sin
     diferencias. Si difiere, está vacío o no existe:
     `cp /root/restic.conf.antes-de-adoptar /usr/local/hestia/conf/restic.conf`
   - No interrumpas `adoptar` (Ctrl-C ni cerrar la web) durante una migración.
2. **Todavía no hay nada que probar en el servidor.** La rama `fix/limpieza-al-salir` arregla
   parte de T20/T21, pero las revisiones encontraron dos agujeros graves abiertos (roadmap). Se
   cierran en el próximo tramo y entonces te llega la guía.
3. **Quitar el enlace de `~/.local/bin`**: `rm ~/.local/bin/backupctl` (solo el enlace; el
   lanzador de escritorio no lo necesita).
4. **`git push` de `master`** cuando quieras.
5. **En cada sesión nueva, los dos `/rename`**: `ServersBackupsPersonalUtility-Arquitecto-Main` y
   `ServersBackupsPersonalUtility-Coder-Main`.
6. Resuelto hoy: tu pregunta 5. Quitaste el respaldo Restic nocturno del cron del servidor de
   pruebas: ya no poda (detalle en `.agents/context/50-hestiacp.md`, «Retención de Restic»).
   Comprobación de solo lectura, en ese servidor:
   `grep -rn restic /var/spool/cron/crontabs/ /etc/cron.d/ /etc/crontab` → sin
   `v-backup-users-restic`.

## En curso

Ronda #024: el coder commitea en `master` la documentación de cierre (trampas T2/T20/T21,
roadmap, `estado/`) y deja el árbol en `master`. Si se corta: solo es documentación.

## Siguiente (nombrado por el PO: T20, «Adelante, trabajen»)

Cerrar en `fix/limpieza-al-salir` los cuatro puntos del roadmap «Antes de pedir la prueba al PO»:
`bc_ssh_sudo_stdin` con usuario no-root (T2), existencia de `restic.conf` con centinela, limpieza
que termina en error, y `trap '' INT TERM` heredado. Después, revisión y guía de prueba para el PO.
La rama necesitará antes traer `master` otra vez (`git merge --no-ff master`).

## Para una sesión nueva

- Lee también el tramo de hoy y `.agents/context/30-trampas.md` T2, T20 y T21.
- El árbol queda en `master`; el trabajo sigue en `fix/limpieza-al-salir` (sin fusionar).
- `serversbackupspersonalutility-68` y `humilde_trabajador_presente_backups` no son parte del
  trabajo. El coder es `ServersBackupsPersonalUtility-Coder-Main`.
