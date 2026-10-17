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
| `v-list-user-backups-restic` | última instantánea. **El formato no es suyo**: no formatea nada, ejecuta la herramienta de respaldo y deja pasar su salida, así que las claves del json dependen de la versión instalada en cada servidor, no de HestiaCP | `hestia.sh:716-733` | FUENTE |
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
- Esa condición `>= 0` gobierna **las cinco** variables, no solo la anual: un `-1` en cualquiera
  de ellas hace que esa regla **no se pase a `restic forget`**. `-1` no es «ilimitadas»: es «sin
  ese tramo». Con `-1` en todas, `forget --prune` se queda sin política. Verificado en la fuente
  el 2026-09-23 y en una salida real del servidor del PO (`Applying Policy: keep 30 latest, 8
  daily, 5 weekly, 3 monthly snapshots`, sin anuales). FUENTE + SERVIDOR.

### Un respaldo incremental que falla se registra como correcto (fuente, 2026-09-23)

- `v-backup-user-restic:80` llama a `check_result $E_BACKUP "Unable to backup user"`, y
  **`E_BACKUP` no existe**: no está en `func/main.sh` (las constantes van de `OK=0` a
  `E_RESTART=20`) ni en los otros tres `func/` que el script carga. Con la constante vacía esa
  rama no ejecuta su `exit`, el script continúa y termina en `log_event "$OK"` (115). FUENTE
  (lectura); la consecuencia exacta en bash, razonada, SIN VERIFICAR por ejecución.
- **Nunca uses el código de salida ni el registro de HestiaCP como prueba de que un respaldo
  incremental se hizo.** La única prueba es una instantánea nueva (ADR 0017).
- `$HESTIA/log/backup.log` lo escribe **solo** `v-backup-users` (el clásico).
  `v-backup-user-restic` no lo menciona: el incremental no deja rastro en ningún log de archivo,
  solo en `v-log-action`. FUENTE. (El ADR 0016 afirmaba lo contrario; lo corrige el 0017.)
- Códigos de salida de `v-backup-user-restic`: repo inaccesible o no creado, `E_CONNECT`=15;
  sistema deshabilitado y incremental deshabilitado, **los dos** `E_DISABLED`=11 (el código no
  los distingue, solo el mensaje); cuenta suspendida, `E_SUSPENDED`=5. FUENTE.
- `v-list-user-backups-restic` solo implementa `json` y `plain`, **no valida el formato** y no
  tiene rama por defecto: un formato desconocido devuelve **vacío con código 0**, que se leería
  como «no hay copias». Tampoco comprueba que exista la contraseña de la cuenta ni maneja ningún
  error de restic. FUENTE.
- `v-change-user-config-value` con una clave que falta **dispara `v-rebuild-user` completo**
  (`useradd`, permisos, `usermod`, jaula sftp, colas) y después `update_user_value` solo escribe
  si la línea existe. `rebuild_user_conf` solo repara una lista cerrada de claves y
  `BACKUPS_INCREMENTAL` **no está** en ella. Comprobar antes; no llamarlo a ciegas. FUENTE.
- `v-delete-backup-host-restic` **no desactiva las cuentas**: pone el flag de sistema
  `BACKUP_INCREMENTAL='no'` en `hestia.conf`, que no es el `BACKUPS_INCREMENTAL` por cuenta que
  leen los respaldos. Las cuentas siguen en `yes`. FUENTE.
- `backup-excludes.conf` vive en `$HESTIA/data/users/<cuenta>/`, es **uno por cuenta**, y se
  carga con `source` (es bash: **lo que se escriba ahí se ejecuta** en el próximo respaldo). El
  valor `*` de una clave salta esa sección entera. FUENTE.
- **Hay DOS implementaciones gemelas del filtrado**, cada una con su propio `source`, y ninguna
  llama a la otra (verificado el 2026-09-24, zanjando dos verificaciones contradictorias):
  `v-backup-user` (el clásico) filtra con **seis** claves —`WEB`, `DNS`, `MAIL`, `DB`, `CRON` y
  `USER`—; `v-backup-user-config` (el que ejecuta el camino incremental, llamado por
  `v-backup-user-restic`) con **cinco**, sin `USER`. En los dos, el `source` va **antes** de las
  secciones que filtran. El `UDIR` del `backup.conf` nunca se rellena. FUENTE.
  *(Corrige la versión anterior de esta ficha, que decía «no hay clave USER».)*
- **Excluir no significa lo mismo en los dos respaldos.** `v-backup-user-config` solo prepara
  *configuración* y *volcados* en `/home/<cuenta>/backup/`; el incremental copia después
  `/home/<cuenta>` entero **sin exclusiones**. Por tanto, en el incremental:
  **`WEB` no impide que los archivos del sitio se copien** (viven en
  `/home/<cuenta>/web/<dominio>/public_html`, dentro de lo que copia restic): solo evita que se
  preparen sus metadatos. **`DB` sí funciona**, porque el volcado no existe en disco hasta que
  ese script lo genera. `DNS` no tiene el problema: el archivo de zona es el contenido.
  `MAIL` tampoco: los buzones viven en `/home/<cuenta>/mail/`, dentro de lo que copia restic
  (verificado el 2026-10-17, sección «Leer un HestiaCP sin escribir nada»). FUENTE (sin números de línea: la
  verificación se hizo sin shell).
- El respaldo clásico lo instala el instalador como `10 05 * * * sudo …/v-backup-users` en el
  crontab de `hestiaweb`, que HestiaCP edita **siempre a mano** (`echo >>`, `sed -i`), nunca con
  `crontab -u`, con dueño `hestiaweb:hestiaweb` y permisos `600`. Ningún script de los leídos lo
  regenera entero salvo el instalador. Si el paquete `.deb` lo rehace en una actualización: SIN
  VERIFICAR.

### Clásico e incremental son independientes (verificado en la fuente, 2026-09-23)

- Cada uno mira **su propio interruptor** en `user.conf`: `v-backup-user` comprueba `BACKUPS`
  (`is_backup_enabled`), `v-backup-user-restic` comprueba `BACKUPS_INCREMENTAL`
  (`is_incremental_backup_enabled`). `BACKUPS=0` **no** detiene Restic. FUENTE.
- **Pero comparten `is_system_enabled "$BACKUP_SYSTEM"`**: si `BACKUP_SYSTEM` está vacío o es
  `no`, se detienen **los dos**, aunque `BACKUP_INCREMENTAL` sea `yes`
  ([v-backup-user-restic:36](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-backup-user-restic#L36)).
  Para quedarse solo con incrementales se quita del cron el trabajo clásico, no el permiso.
- Restic **no usa el `.tar`**: `v-backup-user-restic` llama a `v-backup-user-config` (volcados de
  BD y configuración en `/home/<u>/backup/`) y luego `restic backup /home/<u>`
  ([73-76](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-backup-user-restic#L73-L76)).
- Ese `/home/<u>/backup/` **no se borra al terminar** (solo se pisa en la corrida siguiente) y
  **entra dentro de la instantánea**: el respaldo no lleva ninguna exclusión. FUENTE.
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

## Leer un HestiaCP sin escribir nada (1.10.5, verificado el 2026-10-17)

Para el analizador de la migración caliente (ADR 0018). Fuente: etiqueta `1.10.5` de
`hestiacp/hestiacp` (existe, **sin `v`**). Verificación sin shell, por lector web: números de
línea de `bin/` con ±1 de margen; los de `func/main.sh`, aproximados (se cita función y texto).

### Las órdenes de listado: solo lectura en el camino feliz, NO en el de error

- Las listas del panel (usuarios, dominios web, bases, correo, DNS, cron, IPs, información del
  sistema, PHP) no escriben, no bloquean y no reinician nada **cuando el objeto existe**. FUENTE.
- **Si se consulta un objeto que no existe, o faltan argumentos, SÍ escriben**: `check_result`
  hace `echo "Error: …"` **por la salida estándar** (no json) y `log_event`, que añade una línea a
  `$HESTIA/log/error.log`. Código de salida `E_NOTEXIST=3`. FUENTE.
  Consecuencia: nunca se sondea por nombre; se lista primero y se consulta solo lo listado.
- Un formato desconocido devuelve **vacío con código 0** (no hay rama por defecto). FUENTE.
- El json se arma con `echo` y **los valores no se escapan**: una comilla en un valor produce json
  inválido. FUENTE.
- No comprueban ser root, pero los datos de `data/users/` tienen modos 770/660: en la práctica
  hace falta root. SOSPECHA razonable.
- La información del sistema (`v-list-sys-config`) **lleva secretos** en su json
  (`SERVER_SMTP_PASSWD`, `PHPMYADMIN_KEY`): no se usa para leer la versión. FUENTE.

**Decisión para el analizador**: no llama a ninguna orden del panel. Lee los `.conf` de
`$HESTIA/data/users/<u>/` (formato `CLAVE='valor'`, como ya hace la herramienta copiada) y mide
con `du` y `find`. Así es de solo lectura sin excepciones.

### Qué hay en cada archivo

- **Usuarios**: los que tienen `@` en el GECOS de `/etc/passwd` y un `user.conf`. En los listados,
  `NAME` es el nombre de **contacto**, no el usuario. FUENTE.
- **`web.conf`**, una línea por dominio: `DOMAIN, IP, IP6, CUSTOM_DOCROOT, ALIAS, TPL, SSL,
  SSL_FORCE, SSL_HOME, LETSENCRYPT, FTP_USER, FTP_MD5, BACKEND, PROXY, PROXY_EXT, STATS,
  STATS_USER, STATS_CRYPT, U_DISK, U_BANDWIDTH, SUSPENDED, TIME, DATE`
  (`bin/v-add-web-domain:240-244`). FUENTE.
  - Forzar HTTPS es `SSL_FORCE`. La plantilla de proxy es **`PROXY`**, no `PROXY_TPL`.
  - `FTP_MD5` y `STATS_CRYPT` son hashes: **no se imprimen**.
  - Raíz del sitio: `CUSTOM_DOCROOT` si no está vacío; si no, `/home/<u>/web/<dominio>/public_html/`.
- **Versión de PHP**: `BACKEND` guarda el nombre de la plantilla, p. ej. `PHP-8_1`, o `default`.
  La versión sale de `^.*PHP-([0-9])_([0-9])$`; si no casa, es la predeterminada del multiphp
  (`bin/v-change-web-domain-backend-tpl:168-171`). FUENTE. **A qué versión equivale `default`
  en un servidor concreto: SIN VERIFICAR**; hay que resolverla allí.
- Versiones de PHP instaladas: directorios `/etc/php/*/fpm` (con backend) o `/etc/php/*/cli`.
  Detecta directorios, no paquetes. FUENTE.
- **`db.conf`**: `DB, DBUSER, HOST, TYPE, CHARSET, U_DISK, SUSPENDED, TIME, DATE`. FUENTE.
- **`mail/<dominio>.conf`**: cuentas con `ALIAS, FWD, FWD_ONLY, AUTOREPLY, QUOTA, U_DISK, …`.
  `QUOTA` en MB o `unlimited`. FUENTE.
- **`cron.conf`**: `MIN, HOUR, DAY, MONTH, WDAY, CMD, JOB, SUSPENDED`. Un cron puesto a mano con
  `crontab -e` **no** aparece aquí. FUENTE.
- **`dns.conf`** y `dns/<dominio>.conf`. FUENTE.
- **IPs**: `$HESTIA/data/ips/<IP>`, con `OWNER, STATUS, NAME, NAT, …`. FUENTE.
- **Versión del panel**: `grep '^VERSION=' $HESTIA/conf/hestia.conf`. FUENTE (la clave); que no
  haya otra clave que también contenga `VERSION`: SIN VERIFICAR, por eso se ancla.
- Separador de las listas `ALIAS` y `FWD`: SIN VERIFICAR.

### Los tamaños guardados son viejos

`U_DISK` en `user.conf`, `web.conf`, `db.conf` y los de correo **no se recalculan al listar**: los
refrescan las órdenes de actualización de disco, que **escriben** (y el analizador no llama).
Para un dato fresco se mide con `du`. FUENTE. Cada cuánto los refresca el panel: SIN VERIFICAR.

### Dónde viven los buzones (cierra el SIN VERIFICAR de MAIL)

- `/home/<u>/mail/<dominio>/<cuenta>/`, en **Maildir** (`cur/ new/ tmp/` y carpetas `.Sent`, …).
  Lo crea `v-add-mail-account:101-103` (`chown <u>:mail`, `chmod 700`). FUENTE.
  - Dovecot 2.3: `mail_location = maildir:%h/mail/%d/%n`. Dovecot 2.4: `mail_path = ~` con el
    home de la cuenta en ese mismo directorio. Mismo resultado. FUENTE (configuración).
  - Para dominios con acentos el directorio usa la forma punycode; el `passwd` de Dovecot 2.4 usa
    la otra forma. Efecto: SIN VERIFICAR.
- Contraseñas (hashes): `/home/<u>/conf/mail/<dominio>/passwd`. **No se imprimen.**
- Número de mensajes: ninguna orden de correo del panel lo da. Se cuenta con
  `find <buzón> -path '*/cur/*' -o -path '*/new/*' -type f`. `doveadm` se evita: puede actualizar
  índices (SIN VERIFICAR).
- **Consecuencia para las exclusiones del incremental** (paso 8 de la fase 2): el correo vive
  dentro de `/home/<cuenta>`, igual que la web. **Excluir `MAIL` no impide que los buzones entren
  en la instantánea**, por la misma razón que `WEB`. FUENTE (por la ruta; razonado).

### Dos defectos en el código copiado, por lectura

- `tools/migracion-caliente/BASE_COMPROBAR.sh:285` busca `PROXY_TPL=` en `web.conf`: la clave es
  `PROXY`. La plantilla de proxy nunca se reporta. FUENTE (lectura).
- `tools/migracion-caliente/BASE_PLAN.sh:50`, `plan_dominio_existe`: busca el nombre del dominio
  en la salida de la consulta. Si el dominio **no** existe, HestiaCP imprime
  `Error: web domain <dominio> doesn't exist` por la salida estándar, que contiene el nombre: la
  función respondería «existe». `hestia_salida` (`BASE_PRIVILEGIOS.sh:452-491`) no filtra nada en
  modo cli. CONFIRMADO por lectura, no ejecutado; en modo API, SIN VERIFICAR.
  - La fase 1 crea los dominios sin consultarla (`BASE_GENERAL.sh:1549`): **no destruye nada**.
  - Pero el `plan` (`BASE_PLAN.sh:175`) anunciaría «ya existe, se omitirá» para dominios nuevos, y
    `verificar` (`BASE_VERIFICAR.sh:106`) daría por existente un dominio que no existe: **falso OK**.
  - Y cada consulta fallida añade una línea al `error.log` del destino.
  - **Arreglado el 2026-10-17** (`641733a`), con un segundo defecto que encontró el coder al
    probarlo: el `grep` sin `-F` trataba el punto como comodín, y **la ficha de un subdominio
    hacía «existir» al dominio padre**. Hoy exige la clave json entre comillas y descarta
    `Error:`. En modo API, la forma del error: SIN VERIFICAR.

## Zonas DNS al migrar (1.10.5, verificado el 2026-10-17)

Fuente: etiqueta `1.10.5`, leída sin shell con un lector web que resume: las citas no están
comprobadas byte a byte y los números de línea con `~` son aproximados. Plantillas DNS en
`$HESTIA/data/templates/dns` (`func/main.sh:111`); en el repositorio de HestiaCP,
`install/common/templates/dns/`: `default`, `default-nomail`, `office365`, `gmail`, `zoho`,
`child-ns`.

### Lo que crea el alta de un dominio

- **`v-add-domain USER DOMAIN [IP] [RESTART]` crea web, DNS y correo**, cada uno solo si el
  servidor tiene ese sistema (`WEB_SYSTEM`, `DNS_SYSTEM`, `MAIL_SYSTEM`) y el paquete tiene cupo.
  Es la orden que usa la migración caliente (`tools/migracion-caliente/BASE_GENERAL.sh:1549`),
  sin IP: toma la del usuario. CONFIRMADO. (`v-add-web-domain` solo crea el web.)
- La zona sale de la plantilla `DNS_TEMPLATE` del paquete del usuario. Con `default`, 21 registros:
  `@ NS` (uno por NS), `@ A %ip%`, `www`, `ftp` y `webmail` CNAME, `mail A`, `@ MX 0 mail.%domain%.`,
  `@ TXT "v=spf1 a mx ip4:%ip% -all"`, `_dmarc TXT` y cinco SRV de correo. CONFIRMADO (las líneas
  15-21, por campos, no literal). `office365.tpl` no trae MX y su SPF incluye
  `spf.protection.outlook.com`. Qué plantilla tiene el paquete en un servidor concreto: SIN
  VERIFICAR, se lee allí.
- El alta del dominio de correo añade a la zona `mail._domainkey TXT` con la clave DKIM nueva.

### Añadir registros: duplica

- `v-add-dns-record USER DOMAIN RECORD TYPE VALUE [PRIORITY] [ID] [RESTART] [TTL]`. **No compara
  contenido: siempre añade una línea nueva.** Solo falla si se fuerza un ID ya usado. CONFIRMADO.
  Sobre una zona creada desde plantilla, recrear los registros del origen deja dos `@ A`, dos SPF y
  **dos MX**: el correo se reparte.
- Comillas en TXT: quita todas las dobles y vuelve a entrecomillar si el valor tiene espacio o `;`.
  No duplica comillas. Un valor de más de 255 caracteres se trocea al generar la zona. MX con
  prioridad 0: válido. CNAME en `@`: rechazado. Cada alta reconstruye la zona y reinicia el DNS
  salvo `RESTART=no`. CONFIRMADO.
- `v-change-dns-record USER DOMAIN ID RECORD TYPE VALUE [PRIORITY] [RESTART] [TTL]`: **el orden de
  la cola es distinto** al de `v-add-dns-record`. `v-delete-dns-record USER DOMAIN ID [RESTART]` no
  deja borrar el último `A` ni el último `NS`. No hay orden para vaciar una zona. CONFIRMADO.
- `v-add-dns-domain USER DOMAIN IP [NS1..NS8] [RESTART]`: **si falta NS2, toma TODOS los NS del
  usuario**, también el NS1 pasado. CONFIRMADO.

### La copia fiel

- `v-insert-dns-records USER DOMAIN ARCHIVO` **reemplaza** `dns/<dominio>.conf` por el archivo (lo
  mueve, sin validarlo); la zona tiene que existir. `v-rebuild-dns-domains USER` regenera el `.db`
  de cada zona desde su `.conf`, sin tocar los registros, y recalcula bien los contadores (la forma
  singular parece sobrescribirlos: SOSPECHA). CONFIRMADO salvo lo marcado.
- Al copiar del origen hay que ajustar: las IP de los `A`/`AAAA`, los valores `NS` (nombres del
  servidor viejo) y el `mail._domainkey` (clave del servidor viejo). DNSSEC: si el origen lo usa,
  el destino genera claves nuevas y el DS del registrador dejaría de coincidir (SOSPECHA razonada).

### Correo fuera del servidor (MX en Microsoft 365, por ejemplo)

- Exim considera local todo dominio que tenga entrada en `/etc/exim4/domains/` (`dsearch`,
  `install/deb/exim/exim4.conf.template:21-22`), y esa entrada la crea el alta del dominio de
  correo. Los routers de salida llevan `domains = !+local_domains`: **para un dominio local Exim no
  consulta el MX**. El correo que envíe el propio servidor (formularios, cron) a ese dominio **no
  llega a Microsoft 365**. CONFIRMADO el enrutamiento; si rebota o se pierde: SIN VERIFICAR.
- Se evita borrando el dominio de correo en el destino (`v-delete-mail-domain`, que borra también
  sus cuentas). En la migración caliente: `eliminar_mail="true"` y `correo="false"`.
