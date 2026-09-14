# HestiaCP: de qué depende el código

**Versión objetivo: HestiaCP 1.10.4.** Es la del servidor de pruebas y la que citan los
comentarios del código (`lib/hestia.sh:217,441,503,706`, `lib/adoptar.sh:14`). Toda
verificación contra el código fuente se hace en esa etiqueta del repositorio
`hestiacp/hestiacp`, no en `main`:
`https://raw.githubusercontent.com/hestiacp/hestiacp/1.10.4/<ruta>`. Que la etiqueta se llame
así, sin `v`, es **sin verificar** en este repositorio (lo estaba en otro proyecto del PO).

Aviso de método: la lectura web a veces devuelve contenido plausible en vez de un 404. Lo
crítico se lee dos veces y se exige texto literal.

Estado de cada dato: **SERVIDOR** (comprobado por la sesión anterior contra el servidor de
pruebas, `../HERENCIA.md`), **CÓDIGO** (el código lo afirma en un comentario citando la
fuente de 1.10.4; no revisado de nuevo), **FUENTE** (comprobado aquí en la fuente, con
enlace), **SIN VERIFICAR**. Al verificar algo, se actualiza su estado con el enlace.

## Rutas

| Ruta | Qué es | Dónde se usa | Estado |
| --- | --- | --- | --- |
| `$HESTIA_DIR/conf/restic.conf` | Configuración de Restic del panel, **una para todo el HestiaCP**: `REPO`, `SNAPSHOTS`, `KEEP_DAILY`, `KEEP_WEEKLY`, `KEEP_MONTHLY`, `KEEP_YEARLY`. La escribe entera `v-add-backup-host-restic` | `hestia.sh:30,42`; `adoptar.sh` la pisa y restaura | SERVIDOR; claves FUENTE ([v-add-backup-host-restic](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-add-backup-host-restic)) |
| `$HESTIA_DIR/data/users/<u>/restic.conf` | **Solo la contraseña** del repositorio Restic de esa cuenta (una línea, `--password-file`). No lleva retención | `hestia.sh` (`users`); `backupctl restic`/`hestia keys` la guardan en `Restic_Configs_*.txt` | FUENTE ([v-backup-user-restic](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-backup-user-restic)) |
| `/root/.config/rclone/rclone.conf` | Remoto rclone del panel | `hestia.sh:25` (`BC_RCLONE_CONF`) | CÓDIGO |
| `/var/spool/cron/crontabs/hestiaweb` | Crontab interno de HestiaCP; aquí vive el cron de Restic | `hestia.sh:35,458-521` | SERVIDOR |
| `$HESTIA_DIR/data/users/<u>/cron.conf` | Origen del que HestiaCP regenera el crontab de cada usuario | `cron.sh:17-32` | CÓDIGO |
| `$HESTIA_DIR/data/users/<u>/db.conf` | Bases que el panel conoce | `adoptar.sh:419-422, 1136-1138` | CÓDIGO |
| `$HESTIA_DIR/data/users/<u>/{user,web,dns,mail}.conf` | `user.conf` y `dns.conf` **no** llevan el nombre de usuario dentro | `adoptar.sh:642-654` | SERVIDOR |
| `$HESTIA_DIR/data/ips/<IP>` | Campo `NAT` de cada IP | `adoptar.sh:1043-1046` | CÓDIGO |
| `/usr/local/hestia` a mano, no `$HESTIA_DIR` | — | `cron.sh:46,51`; `pull.sh:101`; ~15 líneas de `adoptar.sh`; `server.py:438-444,474,632` | CÓDIGO (ver T18) |

## Comandos `v-*`

| Comando | Para qué | Dónde | Estado |
| --- | --- | --- | --- |
| `v-list-users` | inventario; `hestia status` lo pide **con sudo** | `hestia.sh:190, 740-801` | CÓDIGO |
| `v-list-web-domains`, `v-list-mail-domains`, `v-list-databases`, `v-list-user-backups` | inventario por usuario | `hestia.sh:740-801` | CÓDIGO |
| `v-list-user-backups-restic` | última instantánea | `hestia.sh:716-733` | CÓDIGO |
| `v-add-backup-host-restic` | alta del destino Restic. **No programa el cron** | `hestia.sh:434` | SERVIDOR |
| `v-backup-users-restic` | respaldo nocturno; se programa en el crontab de `hestiaweb` | `hestia.sh:538` | SERVIDOR |
| `v-list-cron-jobs`, `v-add-cron-job`, `v-delete-cron-job` | cron del perfil local en un HestiaCP | `cron.sh:159-171, 228-230` | CÓDIGO |
| `v-restore-user-full-restic` | restauración de una cuenta desde Restic | `adoptar.sh:14, 379` | CÓDIGO |
| `v-search-domain-owner` | detectar dominios que ya existen en el destino | `adoptar.sh:729-759`, script de `--como` | CÓDIGO |
| `v-add-user`, `v-add-web-domain`, `v-add-mail-domain`, `v-change-user-config-value` | reconstruir una cuenta con otro nombre | `adoptar.sh:913, 945, 951, 1000` | CÓDIGO |
| `v-change-user-name` | **solo** el nombre de contacto; no renombra la cuenta | `adoptar.sh:642-643` | SERVIDOR |
| `v-add-database` | crea `usuario_sufijo`; no acepta el nombre completo; falla si existe | `adoptar.sh:1091, 1351-1356` | SERVIDOR |
| `v-list-user-ips`, `v-list-sys-ips` | IP para el remapeo (prefiere `NAT`) | `adoptar.sh:1043-1046` | CÓDIGO |
| `v-rebuild-user`, `v-rebuild-web-domains`, `v-rebuild-dns-domains`, `v-update-user-counters`, `v-update-user-disk` | cerrar la reconstrucción | `adoptar.sh:1165-1180, 1474-1476` | CÓDIGO |

## Comportamientos

- Restic en HestiaCP es **por usuario** (un repositorio por cuenta), no uno global
  (`b125085`). SERVIDOR.

### Retención de Restic (verificado en la fuente, 2026-09-14)

- `v-backup-users-restic` (lo que se programa en el crontab de `hestiaweb`) solo recorre los
  usuarios no suspendidos y llama a `v-backup-user-restic <u>`; sale sin hacer nada si
  `BACKUP_INCREMENTAL` no es `yes`. FUENTE.
- `v-backup-user-restic` lee `$HESTIA/conf/restic.conf` en cada ejecución y termina con
  `restic --repo "${REPO%/}/$user" --password-file $USER_DATA/restic.conf forget <política> --prune`:
  `--keep-last $SNAPSHOTS` y `--keep-daily/weekly/monthly/yearly` si la variable es `>= 0`.
  **La poda va dentro del respaldo** y la retención es **global** del panel. FUENTE.
- No hay `v-change-*` para la retención: se repite `v-add-backup-host-restic` con el mismo
  `REPO` o se edita el archivo. FUENTE (listado de `bin/` en la etiqueta).
- `v-delete-backup-host-restic` borra `conf/restic.conf` y pone `BACKUP_INCREMENTAL=no`: detiene
  respaldo y poda de todas las cuentas. FUENTE.
- Ningún script Restic de 1.10.4 usa `restic unlock` ni `--no-lock`, y el `forget --prune` final
  no comprueba su código de salida. FUENTE (lectura); qué hace restic ante bloqueos viejos: SIN
  VERIFICAR.
- `v-backup-user-restic` se quita de una cola (`$HESTIA/data/queue/backup.pipe`): puede haber un
  respaldo manual lanzado desde el panel. Qué lo encola: SIN VERIFICAR.
- La interfaz web de 1.10.4 solo lista y restaura instantáneas Restic
  (`web/list/backup/incremental/index.php`); alta, retención y baja son solo por CLI. FUENTE.
- Los respaldos nativos del panel y su formato (`backup.conf` dentro de la instantánea, leído
  con `eval` en `adoptar.sh:885`): CÓDIGO; su formato exacto, SIN VERIFICAR aquí.
- Versión de Restic mínima que exige `adoptar`: 0.14 (`adoptar.sh:195-230`). CÓDIGO.
