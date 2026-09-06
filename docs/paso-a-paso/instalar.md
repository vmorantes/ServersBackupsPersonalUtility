# 2. Instalar en serio

!!! warning "Antes de empezar"
    Haz primero **[1. Instalar — ensayo](instalar-ensayo.md)**. Esta guía da por
    hecho que ya validaste la configuración y el acceso SSH.

## Qué se va a escribir

| Dónde | Qué |
|---|---|
| VPS `/home/admin/scripts/bin/` y `lib/` | Se crean o se actualizan |
| VPS `/home/admin/scripts/env.sh` | **Se sobrescribe** con el del perfil |
| VPS `logs/` y `output/` | Se crean si no existen |
| HestiaCP `cron.conf` del usuario | Se añaden 3 trabajos (paso 5) |

## Qué NO se toca

- Los scripts antiguos que ya haya en `/home/admin/scripts/` (`RunBackupDB.sh` y
  compañía). **Siguen ahí y siguen funcionando.**
- Los respaldos y logs que ya existan.
- Los crons que ya tengas, salvo los de `backupctl`.

!!! success "Los dos sistemas conviven"
    `deploy` usa `rsync --delete` solo **dentro** de `bin/` y `lib/`, que son
    directorios nuevos. Nada de lo que ya hay al lado se borra. Puedes tener el
    sistema antiguo y el nuevo funcionando en paralelo unos días.

    El `env.sh` nuevo conserva `USER_NAME`, `MYSQL_USER` y `MYSQL_PASS`, así que
    los scripts antiguos siguen leyendo lo que necesitan.

---

## Paso 1 — Guardar constancia de cómo está ahora

```bash
backupctl -p MiVPS pull root@mivps.example.com
```

!!! danger "Aquí te va a preguntar algo"
    Si el VPS ya tenía un `env.sh` (el antiguo, de tres líneas), te enseñará el
    `diff` y preguntará si traértelo. **Responde `n`**: quieres conservar el del
    repositorio, que es el nuevo y completo.

Escribe `MiVPS/ESTADO.md` con la foto previa y crea `MiVPS/NOTAS.md` para tus
apuntes. Tener el "antes" guardado vale mucho si algo sale raro.

## Paso 2 — Copiar el ecosistema

```bash
backupctl -p MiVPS deploy root@mivps.example.com
```

Pide confirmación, copia `bin/`, `lib/` y `env.sh`, y ejecuta el diagnóstico en
el destino.

## Paso 3 — Diagnóstico en el VPS

```bash
ssh root@mivps.example.com
cd /home/admin/scripts
./bin/backupctl doctor
```

`doctor` **no escribe nada**. Debe salir sin fallos (✗). Los avisos (!) son
aceptables al principio.

??? question "¿Qué hago si falla algo?"
    | Fallo | Solución |
    |---|---|
    | `mysql NO ESTÁ INSTALADO` | `apt install mariadb-client` |
    | `NO se puede conectar como '...'` | Revisa `MYSQL_USER`/`MYSQL_PASS` en `env.sh` |
    | `sin privilegio SHOW VIEW` | Ver más abajo |
    | `... no es escribible` | `chown -R admin:admin /home/admin/scripts` |

    Privilegios que necesita el usuario de MySQL:

    ```sql
    GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS
      ON *.* TO 'admin_general'@'localhost';
    FLUSH PRIVILEGES;
    ```

## Paso 4 — El primer respaldo, a mano

```bash
./bin/backupctl backup
echo "código: $?"      # 0 = correcto
```

Escribe un `.zip` en `output/mysql_backups/` y un log en `logs/`. Como es el
primero, la retención no borra nada.

Ahora la comprobación que de verdad importa:

```bash
./bin/backupctl verify
./bin/backupctl verify --restore-test <una_base_de_datos> --with-data
```

La segunda crea una base de datos desechable, restaura ahí y **la elimina**. Tu
producción no se toca.

!!! danger "No sigas si este paso falla"
    Los pasos anteriores comprueban que el archivo existe. Este es el único que
    comprueba que **sirve para restaurar**.

## Paso 5 — Programarlo en HestiaCP

```bash
./bin/backupctl cron --show
```

Al detectar HestiaCP te lo dirá y te enseñará los trabajos actuales del usuario.

```bash
sudo ./bin/backupctl cron --install
```

!!! info "Por qué con `sudo` y por qué importa"
    En HestiaCP el crontab del sistema es un archivo **generado** a partir de
    `/usr/local/hestia/data/users/admin/cron.conf`. Una línea puesta con
    `crontab -e` no aparece en el panel y **desaparece** en el siguiente
    `v-rebuild-cron-jobs` — al tocar cualquier cron desde el panel, al
    reconstruir el usuario o al suspenderlo.

    Por eso `backupctl` usa `v-add-cron-job`, que exige root. Así el trabajo
    queda en `cron.conf`, se ve en el panel y sobrevive a los rebuilds.

Compruébalo en el panel de HestiaCP, sección **Cron**. Deberías ver tres
trabajos.

## Paso 6 — Configurar los avisos

Los trabajos que instala HestiaCP no llevan `|| echo`, porque el panel puede
rechazar comandos con operadores. El aviso de fallo se delega en `env.sh`:

```bash
./bin/backupctl config --edit
```

```bash
export HEALTHCHECK_URL="https://hc-ping.com/tu-uuid"
```

```bash
./bin/backupctl notify-test
```

!!! tip "Por qué un healthcheck y no un correo"
    Es el único canal que detecta que el cron **dejó de ejecutarse**. Si el
    respaldo nunca arranca, no hay nada que envíe un correo; en cambio el
    healthcheck avisa porque el ping no llega.

## Paso 7 — Quitar el sistema antiguo (unos días después)

Deja los dos conviviendo hasta que el nuevo lleve varios días respaldando solo y
sin errores.

```bash
./bin/backupctl status
./bin/backupctl logs --list
```

Cuando te fíes, quita el cron antiguo. **Desde el panel de HestiaCP**, no con
`crontab -e`, o volverá a aparecer:

```bash
sudo /usr/local/hestia/bin/v-list-cron-jobs admin
sudo /usr/local/hestia/bin/v-delete-cron-job admin <ID>
```

Y ya puedes borrar los scripts viejos:

```bash
rm /home/admin/scripts/RunBackupDB.sh
rm /home/admin/scripts/HestiaCPResticUserPassBackup.sh
```

## Paso 8 — Dejar constancia en el repositorio

En tu equipo:

```bash
backupctl -p MiVPS pull root@mivps.example.com
git add MiVPS/
git commit -m "MiVPS: backupctl instalado y programado"
```

`ESTADO.md` queda con la versión instalada, el crontab, los respaldos y el
diagnóstico. El repositorio recuerda el despliegue.

## Lista de comprobación

- [ ] `doctor` sin fallos en el VPS
- [ ] `backup` termina con código `0`
- [ ] `verify --restore-test --with-data` pasa
- [ ] Los tres trabajos se ven en el panel de HestiaCP
- [ ] `notify-test` llega
- [ ] `ESTADO.md` actualizado y cometido
- [ ] Anotado en `NOTAS.md` lo que sea propio de este VPS
