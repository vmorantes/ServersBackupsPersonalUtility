# 0016 — Respaldos incrementales de punta a punta desde la herramienta

- **Estado:** Propuesta (verificación de HestiaCP completa, 2026-09-16)
- **Fecha:** 2026-09-16
- **Decide:** Arquitecto, por mandato del PO
- **Estructural:** sí (qué escribe la herramienta en el servidor y con qué contrato)
- **Se apoya en:** 0013 (versión 2.1), 0014 (informe de lo hecho), 0015 (interfaz por tareas)

## En cristiano

Desde la herramienta se podrá dejar un servidor HestiaCP con sus respaldos incrementales
funcionando, cambiar cualquier ajuste y apagarlos, sin entrar al panel. Por debajo se usa el
mecanismo de Restic del propio HestiaCP, para que el panel siga pudiendo listar y restaurar esas
copias. Cada paso enseña antes lo que hay, dice qué va a cambiar, lo hace, lo comprueba y deja un
informe con cómo deshacerlo. Termina haciendo una primera copia y comprobando que existe.

## Contexto (verificado en la fuente de HestiaCP 1.10.4, 2026-09-16)

- Hacen falta **dos** interruptores: `BACKUP_INCREMENTAL=yes` global (`hestia.conf`, lo pone
  `v-add-backup-host-restic`) y `BACKUPS_INCREMENTAL=yes` en el `user.conf` de cada cuenta (viene
  del paquete). Sin el segundo, `v-backup-user-restic` sale con «incremental backups are disabled».
- `v-add-backup-host-restic REPO SNAPSHOTS DAILY WEEKLY MONTHLY YEARLY` reescribe
  `conf/restic.conf` entero (sin fusión), comprueba `rclone lsd` para `rclone:…`, instala Restic sin
  comprobar el resultado y no programa ningún cron.
- Ningún `v-*` gestiona `/root/.config/rclone/rclone.conf` ni `backup-excludes.conf`.
- HestiaCP no instala cron para `v-backup-users-restic`; el resultado de cada ejecución va a
  `$HESTIA/log/backup.log`.
- `v-delete-backup-host-restic` borra `restic.conf` y pone `BACKUP_INCREMENTAL=no`; no toca los
  datos del repositorio.
- Encolar restauraciones con `v-schedule-user-restore-restic` hereda un bug de 1.10.4 (cron): se
  llama a los binarios reales.
- Inventario de la herramienta: ya existen `hestia rclone`, `restic`, `cron`, `keys`, `status`,
  `verify`, pero sin desactivar, sin retención configurable fuera del modo interactivo, sin copia ni
  antes/después, sin cambiar la hora del cron, `verify` roto (ruta global sin contraseña) y sin
  leer `BACKUP_INCREMENTAL` ni la última instantánea.

## Decisión

### Estado leído (una sola lectura, por SSH, elevada cuando haga falta)

Versiones de `restic` y `rclone`; remotos de `rclone.conf` (solo nombres y tipo); `restic.conf`
(repositorio y retención); `BACKUP_INCREMENTAL`; por cuenta: paquete, `BACKUPS_INCREMENTAL`,
contraseña de repositorio presente, exclusiones, última instantánea (`v-list-user-backups-restic
… json`) y último resultado en `backup.log`; línea de cron de `v-backup-users-restic` y dónde
está; claves rescatadas en este equipo y su fecha. Lo que no se pueda leer se muestra como «no se
pudo leer», nunca como vacío.

### Pasos (cada uno: Ahora → Plan → confirmar → hacer → comprobar → informe, ADR 0014)

1. **Almacenamiento**: crear o actualizar un remoto de `rclone.conf` (copia fechada del archivo;
   sustitución atómica; `rclone lsd` para comprobar). Nunca sustituir el archivo entero sin decirlo.
2. **Repositorio y retención**: `v-add-backup-host-restic` con valores explícitos, prellenados con
   los actuales; nunca imponer 30/8/5/3/-1 en silencio. Salvaguarda de ruta compartida. Copia fechada
   de `restic.conf`; relectura tras escribir.
3. **Cuentas**: qué cuentas entran. Se muestra, por cuenta, su paquete, el
   `BACKUPS_INCREMENTAL` del paquete y el de la cuenta (el paquete `default` trae `no`).
   - **Por cuenta (recomendado)**: `v-change-user-config-value <cuenta> BACKUPS_INCREMENTAL yes`
     y relectura de `user.conf`. Si la cuenta no tiene esa clave (cuentas antiguas), esa orden
     termina en éxito sin escribir nada: la herramienta lo detecta antes y no lo intenta; ofrece la
     vía del paquete. Aviso permanente: volver a aplicar el paquete a la cuenta
     (`v-change-user-package`, `v-update-user-package`) devuelve el valor del paquete.
   - **Por paquete**: `v-add-user-package <archivo> <paquete> yes` (reescribe el paquete) y
     `v-update-user-package <paquete>`, que reaplica el paquete a TODAS sus cuentas con FORCE:
     cambia el shell, aplica cuotas y límites si están activos, ejecuta el disparador del paquete y
     salta la comprobación de capacidad. El plan lista las cuentas afectadas y estos efectos antes
     de confirmar.
4. **Programación**: poner, cambiar la hora o quitar la línea de `v-backup-users-restic` en el
   crontab de `hestiaweb` (copia fechada, escritura atómica, permisos y dueño, relectura).
5. **Exclusiones** (opcional): editar `backup-excludes.conf` de una cuenta, diciendo que solo
   afectan a lo que se copia a `backup/`.
6. **Primera copia y comprobación**: `v-backup-user-restic <cuenta>` de una cuenta elegida; se
   comprueba la instantánea nueva en `v-list-user-backups-restic` y el resultado en `backup.log`.
   Se informa por lo leído, no por el mensaje de la orden.
7. **Claves de recuperación**: rescatarlas a este equipo al terminar (lo que permite `adoptar` si el
   servidor desaparece), con aviso si las guardadas son más antiguas que la configuración.
8. **Desactivar**: quitar la línea de cron y `v-delete-backup-host-restic`, diciendo con claridad que
   los datos del almacenamiento se quedan y cómo volver a activarlo con los mismos valores.

### Órdenes

Se amplía el grupo `backupctl hestia` (las órdenes existentes siguen funcionando):
`hestia estado`, `hestia rclone`, `hestia restic --snapshots --daily --weekly --monthly --yearly`,
`hestia cuentas`, `hestia cron --hora HH:MM | --quitar`, `hestia exclusiones`, `hestia probar
<cuenta>`, `hestia keys`, `hestia desactivar`. Todas con `--dry-run` que lee el estado y produce el
plan sin escribir. La web las llama (ADR 0015, tarea «Proteger»).

### Pruebas

Banco con `ssh` falso que registra cada orden y su entrada, y `v-*`, `restic`, `rclone` simulados
por guion: se comprueba la orden exacta enviada, la copia fechada previa, que el ensayo no escribe
nada, y el informe (antes, después, reversión). Camino de fallo de cada paso: el original queda
intacto. Lo que solo demuestra el servidor va a la guía única del PO.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Restic propio, al margen de HestiaCP | El panel dejaría de listar y restaurar esas copias; interpretación elegida y revertible por el PO |
| Encolar operaciones en `backup.pipe` como hace el panel | Hereda el bug de 1.10.4 y falla en silencio |
| Editar `restic.conf` a mano en vez de `v-add-backup-host-restic` | Se salta `BACKUP_INCREMENTAL` y la instalación de Restic que hace HestiaCP |
| Un asistente único que lo haga todo de golpe | Si falla a mitad no se sabe qué quedó; los pasos con informe propio sí |

## Consecuencias

- La herramienta pasa a escribir en archivos del sistema que HestiaCP no gestiona (`rclone.conf`,
  crontab de `hestiaweb`, `backup-excludes.conf`): cada escritura con copia fechada y reversión.
- «Desactivar» no libera espacio remoto: se dice.
- Depende del comportamiento de 1.10.4; otra versión de HestiaCP necesita volver a verificar.

## Reversión

Las órdenes nuevas se retiran sin afectar a las existentes; lo que ya se configuró en un servidor
se deshace con los informes (copias fechadas) o con `hestia desactivar`.

## Verificación

Banco: cada paso con su prueba de orden enviada, ensayo sin escritura, informe y camino de fallo,
con mutaciones. Servidor (PO, guía única): activar en el servidor de pruebas, primera copia visible
en el panel, cambiar la hora, desactivar.
