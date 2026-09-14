# Ahora

- **Actualizado:** 2026-09-14, tras el cierre inesperado de los editores del PO (se
  interrumpieron las sesiones).
- **Último mensaje:** #020 (ARQ) — terminar B tras el corte: corregir un detalle de `set -e`
  en el registro de limpiezas, repetir las revisiones cortadas y preparar la guía para el PO. Se
  espera #021. (#018/#019: el coder conserva la conversación; A completada con la fusión
  `9f82430`; B commiteada en `fix/limpieza-al-salir`, 7 commits, M20 y M21 confirmadas; la
  prueba de `adoptar` se descartó: 12 respuestas de falsos; las revisiones se cortaron sin
  resultado.)
- **Tramo en curso:** `estado/tramos/2026-09-14-1448-limpieza-al-salir.md` (el anterior,
  `2026-09-14-0949-adopcion-arquitecto-coder.md`, está cerrado).

## Espera al PO

1. **Quitar el enlace de `~/.local/bin`** (lo pediste; la guarda no deja a ningún agente escribir
   fuera del repositorio): `rm ~/.local/bin/backupctl`. Solo borra el enlace, no el programa. El
   lanzador de escritorio ya instalado no lo necesita.
2. **Aviso para tu migración real** mientras no se fusione `fix/limpieza-al-salir`: **no
   interrumpas `adoptar` (Ctrl-C ni cerrar la web) durante una migración.** Si se corta o falla a
   mitad, revisa en el servidor de destino `/usr/local/hestia/conf/restic.conf`: puede haberse
   quedado apuntando al repositorio rescatado (T20).
3. **Tu pregunta 5 — conservar las instantáneas del servidor de pruebas.** **Resuelto por el
   PO**: quitó del cron del sistema la ejecución nocturna de Restic (2026-09-14). Eso detiene la
   poda nocturna: la poda solo ocurre dentro del respaldo (`v-backup-user-restic`), y ese
   respaldo solo corría desde ese cron. Queda un resquicio SIN VERIFICAR: un respaldo lanzado a
   mano desde el panel también podaría. Para cerrarlo del todo, el paso 3 de abajo (opcional).
   Comprobación de solo lectura, en ese servidor:
   `grep -rn restic /var/spool/cron/crontabs/ /etc/cron.d/ /etc/crontab` → no debe salir
   `v-backup-users-restic`. Lo que sigue queda como referencia. Verificado en el código de
   HestiaCP 1.10.4:
   - Las instantáneas viven en el almacenamiento S3, no en el servidor. Las borra **el propio
     servidor** cada noche (`v-backup-user-restic` hace `forget --prune` con la retención de
     `/usr/local/hestia/conf/restic.conf`, una sola para todo el panel). Si ese servidor deja de
     hacer el respaldo Restic, se conservan. Apagar el servidor también lo detiene.
   - HestiaCP 1.10.4 no tiene pantalla para esto: se hace por SSH, como root, en ESE servidor.
   - Pasos (los ejecutas tú):
     1. Mirar, sin cambiar nada: `cat /usr/local/hestia/conf/restic.conf` (repositorio y
        retención; no contiene contraseñas).
     2. Guardar una copia: `cp /usr/local/hestia/conf/restic.conf /root/restic.conf.guardado`.
     3. Detener respaldo y poda Restic de **todas** las cuentas de ese panel:
        `/usr/local/hestia/bin/v-delete-backup-host-restic`. Según su código, borra solo ese
        archivo de configuración y pone `BACKUP_INCREMENTAL=no`; el código leído no toca los
        datos del repositorio. Para volver atrás: `v-add-backup-host-restic` con los valores
        guardados en el paso 2.
   - Para usarlas después en pruebas hacen falta las contraseñas por cuenta; `backupctl` ya las
     guardó en el perfil (`output/HestiaCP/Restic_Configs_*.txt`), que es lo que usa `adoptar`.
   - Opcional, si quieres una copia que nada pueda podar: copiar la carpeta del repositorio de esa
     cuenta a otra ruta del bucket con `rclone copy` (duplica espacio). Te doy el comando exacto si
     lo quieres; necesito que me digas la ruta `REPO` que muestre el paso 1.
   - Sin verificar: si los dos bloqueos de Restic que dejó el agente anterior frenan hoy la poda
     (HestiaCP no los quita, pero no se comprobó qué hace restic ante ellos). No te fíes de ellos:
     el paso 3 sí es seguro.
4. **`git push` de `master`** cuando quieras («Luego subo»).
5. En cada sesión nueva, los dos `/rename`.

## En curso

Ronda #017 en vuelo, dos tareas con puerta propia:

- A: rama `docs/adr-0011-0012`: guarda (borrado de ramas, redirecciones), ADR 0011 y 0012,
  reglas, trampas, roadmap, `estado/`; fusionar; borrar `chore/adopcion-arquitecto-coder`,
  `feat/banco-de-pruebas`, `docs/cierre-tramo-adopcion` y la propia `docs/adr-0011-0012`.
- B: rama `fix/limpieza-al-salir`: registro de limpiezas en `lib/core.sh` y su uso en `restore`,
  `verify`, `pull`, `restic`, `adoptar`; pruebas en el banco. NO se fusiona: toca lo que corre en
  servidores, espera tu prueba con la guía que dejará aquí el arquitecto (ADR 0007).

Si se corta ahora: A es solo documentación; B quedaría en su rama.

## Para una sesión nueva

`serversbackupspersonalutility-68` y `humilde_trabajador_presente_backups` no son parte del
trabajo. El coder es `ServersBackupsPersonalUtility-Coder-Main`.
