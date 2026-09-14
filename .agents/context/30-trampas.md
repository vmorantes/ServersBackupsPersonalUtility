# Trampas

Lo que muerde. Cada una con su evidencia y su estado: **CONFIRMADA** (leída en el código o
comprobada), **SOSPECHA** (plausible, falta verificar lo que se indica) o **CUBIERTA** (hay
prueba o guarda). Revisado 2026-09-14 sobre `4435064`.

Origen de la evidencia: «código» = lectura del código el 2026-09-14; «servidor» = la sesión
que construyó el proyecto lo comprobó contra el servidor de pruebas (`../HERENCIA.md`).

Las cuatro trampas que ya cuenta `docs/desarrollo/arquitectura.md` («Detalles que no son
obvios») no se repiten aquí: tuberías que crean subshells y pierden contadores, separador
decimal y locale, menús en stderr, `mysqldump --force` que miente.

## Seguridad y datos del PO

### T1. Credenciales reales dentro del repositorio — CONFIRMADA

`TejidoTesting/env.sh` (contraseña de MySQL) y `TejidoTesting/output/HestiaCP/`
(`rclone_*.conf` con claves S3; `Restic_Configs_*.txt` con claves de Restic, según la sesión
anterior) están versionados y en el remoto. `docs/desarrollo/repositorio.md` presenta como
deliberado versionar `output/HestiaCP/`. Además: `pull` escribe en `ESTADO.md` el diff del
`env.sh` (`pull.sh:135-143`) y `ESTADO.md` no está ignorado; `/api/config-raw` manda el
`env.sh` al navegador (`server.py:755-771`); `adoptar --como` imprime contraseñas en claro
(`adoptar.sh:1130,1210`). Siguen versionadas por decisión del PO (ADR 0008). La guarda impide a
los agentes leerlas (CUBIERTA para agentes).

### T2. `bc_ssh_sudo` se come la entrada estándar — CONFIRMADA (código y servidor)

`bc_ssh_sudo` (`lib/ssh.sh:120`) comprueba `id -u` con un `bc_ssh` que lee stdin (121): si se
le manda un script, SQL o un secreto por tubería o heredoc, esa comprobación se lo come, el
lado remoto recibe nada, sale con 0 y la orden informa de un éxito que no ocurrió. Para enviar
contenido: `bc_ssh_sudo_stdin` (108), que cierra stdin en la comprobación. Casos tratados:
`adoptar.sh:454-460, 861-864`.

### T3. Sin `-p`, cualquier orden usa el perfil real — CONFIRMADA (código)

Con un solo perfil en el repositorio, es el de por defecto (`config.sh:56-63`). Una prueba o
un ejemplo que olvide `-p <temporal>/env.sh` trabaja con credenciales reales.

### T4. Ningún `--dry-run` está libre de efectos — CONFIRMADA (código)

`backup`, `restic` y `migrate` crean el log y el bloqueo antes de mirar opciones
(`bin/backupctl:278-285`); `backup` crea directorios y conecta a MySQL antes de salir
(`backup.sh:265-331`); `restic` hace `mkdir` y `mktemp` antes (`restic.sh:38-41`); `restic` y
`retention` solo reconocen `--dry-run` como primer argumento (`bin:353,359`); `deploy`, `pull`,
`migrate` y `adoptar` conectan y leen; `hestia keys` escribe igual con `hestia setup
--dry-run`. `docs/desarrollo/arquitectura.md:151` sugiere lo contrario.

### T5. Sin terminal, las confirmaciones devuelven su valor por defecto — CONFIRMADA (código)

`bc_confirm` (`core.sh:89-93`). `install` (61), `cron --install` (153, 287) y `deploy`
(85, 154) tienen «sí» por defecto: sin terminal, siguen sin preguntar. La web pasa siempre
`-y` (`server.py:229`). Contradice «confirmaciones que se degradan a no» de
`docs/desarrollo/decisiones.md` para esas tres órdenes.

### T6. Código que merece auditoría — SOSPECHA

- `adoptar.sh:885`: `eval "$(cat backup.conf)"` como root sobre un archivo sacado de una
  instantánea de Restic. Si el repositorio de respaldos estuviera comprometido, es ejecución
  como root en el destino. Falta decidir si el origen se considera de confianza.
- `adoptar.sh:1299`: `'$cuantas'` se interpola sin validar dentro de código Python.
- `hestia status` eleva privilegios para una lectura (`hestia.sh:190`).

### T7. Datos reales del PO en código — CONFIRMADA (código)

Dominio de un cliente en `lib/adoptar.sh:658`; usuario y bases reales en
`lib/adoptar.sh:69,593,1357`; como `placeholder` en `web/index.html:411,423,425`; huellas del
servidor en comentarios (recuentos de bases en `remote.sh:76`, `config.sh:134`,
`adoptar.sh:406,1346`, `mysql.sh:21`; IDs de instantáneas en `adoptar.sh:1221-1223`). Incumple
la regla 40 §1 (roadmap). El nombre del perfil `TejidoTesting` aparece en `bin/backupctl:178`
y en `README.md`.

## Volcados e importación (MySQL / HestiaCP)

### T8. La cabecera `USE` aplica el SQL a la base original — CONFIRMADA (código y servidor)

Un volcado empieza con ``USE `base_original`;``. Enviado con `mysql <otra_base>`, ese `USE`
manda y el SQL se aplica a la original, sin error. Toda ruta que importe en otra base lo quita
con `sed -E 's/^USE `[^`]*`;$//'`: `adoptar.sh:598,1149`, `restore.sh:157,163`,
`verify.sh:248`. Una ruta de importación nueva sin ese filtro es un hallazgo crítico.

### T9. `DEFINER` en vistas y rutinas corta la importación — CONFIRMADA (servidor)

Apunta al usuario MySQL del origen; si no existe en el destino, `ERROR 1449` corta la
importación entera. Se quita en `adoptar.sh:1141-1153` (y `SQL SECURITY DEFINER` pasa a
`INVOKER`).

## Ejecución remota y bash

### T10. `ssh` dentro de `while read` se come el bucle — CONFIRMADA (código)

Sin `< /dev/null`, el `ssh` consume las líneas pendientes y el bucle procesa solo la primera
(`hestia.sh:65-68`). Con la misma raíz: un heredoc y una tubería sobre el mismo `bash -s` se
pisan (`adoptar.sh:844-849, 1426-1428`).

### T11. `bc_hestia_read` duplicaba la salida — CUBIERTA en código, sin prueba

El patrón `orden && return 0`, reintentado con sudo si fallaba, imprimía dos veces; y `grep`
devuelve 1 aunque haya encontrado antes. Hoy captura y decide (`hestia.sh:69-99`).

### T12. `sudo -u` hereda el directorio de trabajo — CONFIRMADA (código y servidor)

Por ssh como root, el cwd es `/root`; `sudo -u <usuario>` lo hereda y un `find`/`cd` falla a
mitad con «Failed to restore initial working directory». El `cd` previo no es decorativo
(`remote.sh:57-80`). Los archivos creados como root en el árbol del usuario rompen después la
retención.

### T13. Variables `BC_OPT_*` heredadas del entorno — CONFIRMADA (código)

Muchas no se inicializan en `bin/backupctl:42-47` (`BC_OPT_REPO`, `BC_OPT_RC_*`,
`BC_OPT_USERS`, `BC_OPT_COMO`, `BC_OPT_PREFIJO`, `BC_OPT_DBS`…): llegan del entorno. La web
lo usa a propósito para pasar credenciales (`server.py:929-934`). Una variable olvidada en el
entorno de quien ejecuta cambia el comportamiento. También vienen del entorno `BC_SETUP_*`,
`BC_SSH_PASSWORD_FILE`, `BC_DEBUG`.

### T14. Trampas `RETURN` globales — CONFIRMADA (código); impacto SOSPECHA

Un `trap ... RETURN` puesto dentro de una función sigue puesto al volver y puede dispararse en
el llamador. Solo `restic.sh:78` hace `trap - RETURN`. Aparecen en `remote.sh:47`,
`deploy.sh:59`, `pull.sh:41`, `hestia.sh` (varias), `adoptar.sh:272,549,855,1291` (esta, en un
bucle). Con comillas dobles se expanden al ponerse (`restore.sh:62`, `verify.sh:57`).

### Menores — CONFIRMADAS (código)

| Qué | Dónde |
| --- | --- |
| `[[ ]] && echo` al final de un bloque con pipefail hace fallar el grupo: `true` final | `mysql.sh:37`, `hestia.sh:811-815` |
| SIGPIPE de `head` con pipefail | `core.sh:132-134` |
| `bc_can_prompt` frente a `bc_is_tty` dentro de `$(...)` | `core.sh:57-63` |
| `--defaults-file`, no `--defaults-extra-file`: `~/.my.cnf` pisaba la contraseña | `mysql.sh:48-57` (commit `e25f021`) |
| `%` sin escapar en crontab | `cron.sh:5-15` |
| El error de `exec 9>` lo imprime el propio shell | `core.sh:184-187` |
| `exec > >(tee)` produce salida asíncrona | `core.sh:221-225` |
| `BC_DELIBERATE_EXIT=1` antes de `return 1`, o sale «fallo no controlado» | p. ej. `shield.sh:173` |
| `set +e` alrededor de `PIPESTATUS`; índice `[2]` | `backup.sh:73-80`, `restore.sh:159,165` |

## HestiaCP

Detalle y fuentes en `50-hestiacp.md`.

### T15. El cron de Restic vive en el crontab de `hestiaweb` — CONFIRMADA (servidor y fuente)

No en el de ningún usuario del panel. `v-add-backup-host-restic` no lo programa. HestiaCP
regenera los crontabs de sus usuarios desde `cron.conf`, salvo el de `hestiaweb`
(`cron.sh:17-32`, `hestia.sh:35,458-521`). Se corrigió dos veces (`b125085`, `86faa09`).

### T16. La configuración de Restic del panel es una sola — CONFIRMADA (servidor)

`$HESTIA_DIR/conf/restic.conf` vale para todo el HestiaCP: una acción que la sustituye afecta
a todas las cuentas. `adoptar --to` la pisa durante la operación y la devuelve al salir
(`adoptar.sh:40-53, 272, 362-364`). El mensaje de `hestia.sh:787` cita una ruta que no es la
real (`data/users/conf/restic.conf` frente a `conf/restic.conf`).

### T17. HestiaCP no renombra cuentas; `v-add-database` concatena — CONFIRMADA (servidor)

`v-change-user-name` cambia el nombre de contacto, no la cuenta; renombrar es reconstruirla con
otro nombre, posible porque `user.conf` y `dns.conf` no llevan el usuario dentro
(`adoptar.sh:642-654`). `v-add-database` forma `usuario_sufijo` y no admite el nombre completo
(`adoptar.sh:1091, 1351-1356`).

## Pruebas y herramientas

### T18. No hay forma de probar sin servidor — CONFIRMADA (código)

No existe ninguna prueba automatizada. `ssh`, `rsync`, `mysql`, `mysqldump`, `sudo`,
`crontab`, `restic` y `rclone` se invocan por nombre: solo se sustituyen poniendo falsos
delante en el `PATH`. `HESTIA_DIR` no es una raíz completa: `/usr/local/hestia` está escrito a
mano en `cron.sh:46,51`, `pull.sh:101`, unas 15 líneas de `adoptar.sh` y `server.py:438-444,
474, 632`. Ver `40-entorno.md`.

### T19. `web/comprobar.py` reescribe un `.pyc` versionado — CUBIERTA

Importa `server.py` y regenera `web/__pycache__/server.cpython-312.pyc`, que está en git.
`verificar.sh` lo ejecuta con `-B` y `PYTHONDONTWRITEBYTECODE=1`.

## Documentación que miente — CONFIRMADA (código)

- `docs/desarrollo/arquitectura.md`: el árbol lista 16 de los 26 módulos; dice «~360 líneas»
  (son 573); su trampa ERR (79) no es la de `bc_trap_err` (`bin:59-73`); el diagrama y «Añadir
  una orden nueva» no incluyen la web; `--debug <orden> --dry-run` (151) sugiere un ensayo
  inocuo (T4).
- `TejidoTesting/Instrucciones.md` enlaza a `docs/servidores/tejidotesting.md`, que no existe.
- `bin/backupctl:503`: comentario de `exec-count` fuera de su sitio; la lista de órdenes con
  ensayo de la ayuda (143-144) omite `hestia rclone/restic/cron` y `adoptar*`.
- `docs/desarrollo/repositorio.md` «Ramas»: actualizado con el ADR 0007 el 2026-09-14.
- `DEPLOY_USER` vale `root` por defecto en `lib/config.sh`; `docs/referencia/variables.md`
  dice `$USER_NAME`.
- `status` con un perfil sin `NOTIFY_*` ni `HEALTHCHECK_URL` sale siempre con 1: cuenta «ningún
  aviso configurado» como problema (`lib/archive.sh:106-204`).
