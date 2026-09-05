# 1. Instalar — ensayo

**Nada de lo que hay aquí escribe, borra ni modifica nada.** Ni en tu equipo ni
en el VPS. Puedes ejecutarlo entero con total tranquilidad, incluso en un
servidor en producción que ahora mismo usa los scripts antiguos.

El objetivo es responder a tres preguntas antes de tocar nada:

1. ¿Está bien la configuración?
2. ¿Se puede llegar al VPS?
3. ¿Qué hay ahora mismo en él?

---

## Paso 1 — Preparar el perfil (en tu equipo)

Un perfil es un servidor: un directorio con un `env.sh`.

```bash
cd /ruta/al/repositorio

# ¿Qué perfiles conoce ya?
backupctl profiles
```

Si el servidor todavía no está:

```bash
mkdir MiVPS
cp config/env.sh.example MiVPS/env.sh
${EDITOR:-nano} MiVPS/env.sh
```

Lo mínimo que hay que rellenar:

```bash
export USER_NAME="admin"                    # usuario de HestiaCP
export MYSQL_USER="admin_general"
export MYSQL_PASS="..."

export DEPLOY_HOST="mivps.example.com"
export DEPLOY_USER="admin"
export DEPLOY_PATH="/home/admin/scripts"
```

!!! note "Crear el directorio y editar un archivo no cuenta como destruir nada"
    Es el único paso de esta guía que escribe, y solo en **tu** equipo, en un
    archivo nuevo.

## Paso 2 — Validar la configuración

```bash
backupctl -p MiVPS config --check     # ¿es válida?
backupctl -p MiVPS config --show      # valores efectivos, contraseña oculta
```

`--check` devuelve `0` si está bien y `1` si no. No escribe nada.

## Paso 3 — Requisitos en el VPS

Esto es lo único que hay que tener **antes** de desplegar. Todo lo demás lo crea
`deploy`.

### 3.1 Acceso SSH por clave

```bash
ssh admin@mivps.example.com 'hostname; bash --version | head -1'
```

Si pide contraseña:

```bash
ssh-copy-id admin@mivps.example.com
```

!!! warning "En HestiaCP, el usuario puede no tener shell"
    Los usuarios de HestiaCP se crean a menudo con `nologin`, así que la clave
    no basta: SSH acepta y cierra al instante.

    Actívalo en el panel: **Usuarios → editar el usuario → SSH Access → bash**.
    O desde la línea de órdenes:

    ```bash
    sudo v-change-user-shell admin bash
    ```

    El usuario `admin` suele tenerlo ya.

### 3.2 Paquetes

Una instalación mínima de Debian/Ubuntu **no trae `zip` ni `rsync`**, y son
imprescindibles. En el VPS:

```bash
sudo apt update && sudo apt install -y zip unzip rsync
```

`mysql`, `mysqldump`, `gzip`, `find`, `sha256sum` y `flock` ya vienen con
HestiaCP y con el sistema base.

!!! tip "No hace falta que lo memorices"
    `deploy` comprueba las dependencias del servidor **antes de copiar nada** y,
    si falta algo, te da la línea exacta de `apt install` con los nombres de
    paquete correctos:

    ```
    [ERROR] faltan órdenes en el servidor: rsync zip
    [ERROR] Instálalas allí y vuelve a intentarlo:
    [ERROR]     sudo apt update && sudo apt install -y rsync zip
    ```

### 3.3 Un usuario de MySQL con permisos

Si el VPS ya tenía respaldos, reutiliza el que ya usabas. Para uno nuevo:

```sql
CREATE USER 'admin_general'@'localhost' IDENTIFIED BY 'una-contraseña-larga';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS
  ON *.* TO 'admin_general'@'localhost';
FLUSH PRIVILEGES;
```

Compruébalo antes de seguir:

```bash
mysql -u admin_general -p -e "SHOW DATABASES;" | head
```

??? question "¿Y si quiero usar `verify --restore-test`?"
    Esa prueba crea y borra una base de datos desechable, así que necesita
    también `CREATE` y `DROP`:

    ```sql
    GRANT CREATE, DROP ON *.* TO 'admin_general'@'localhost';
    ```

    Es la comprobación que demuestra que el respaldo sirve. Si prefieres
    mantener el usuario de respaldo en solo lectura, usa otro usuario para esa
    prueba concreta.

### 3.4 Espacio en disco

```bash
df -h /home/admin
```

Regla: `tamaño_de_los_datos × 2` para el volcado, más
`tamaño_del_zip × días_de_retención` para el archivo.

### 3.5 Lo que NO hay que hacer

- **No crees `/home/admin/scripts`**: lo crea `deploy`.
- **No crees `logs/` ni `output/`**: los crea `deploy`.
- **No copies nada a mano**: de eso se encarga `deploy`.
- **No borres los scripts antiguos**: pueden convivir. Ver la
  [guía 2](instalar.md).

## Paso 4 — Ver qué se copiaría, sin copiar

```bash
backupctl -p MiVPS deploy admin@mivps.example.com --dry-run
```

Se conecta, comprueba la versión de bash del destino y **lista los archivos que
se copiarían**. No escribe ni un byte allí.

```
[INFO ] Comprobando acceso SSH...
[  OK ] conectado a mivps.example.com
[INFO ] Se copiarán: bin lib + env.sh del perfil 'MiVPS'
[INFO ] Simulación (--dry-run):
        bin/
        bin/backupctl
        lib/
        lib/backup.sh
        ...
[  OK ] Nada se ha copiado.
```

## Paso 5 — Fotografiar el estado actual del VPS

```bash
backupctl -p MiVPS pull admin@mivps.example.com --dry-run
```

Se conecta y te enseña qué encontraría, sin escribir `ESTADO.md` ni tocar tu
`env.sh`. En un servidor que aún no tiene `backupctl` verás:

```
[AVISO] no hay backupctl en admin@mivps:/home/admin/scripts. Se recogerá lo que se pueda.
```

Es normal: todavía no lo has instalado.

## Paso 6 — Inspeccionar el VPS a mano

Todo esto es de solo lectura:

```bash
ssh admin@mivps.example.com
```

```bash
# ¿Qué hay ya en el directorio de scripts?
ls -la /home/admin/scripts/

# ¿Qué crons tiene el usuario según HestiaCP? (la fuente de verdad)
cat /usr/local/hestia/data/users/admin/cron.conf

# ¿Y el crontab del sistema, que HestiaCP genera a partir de lo anterior?
crontab -l

# ¿Cuánto espacio hay?
df -h /home/admin

# ¿Qué tamaño tienen las bases de datos?
mysql -e "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024) AS mb
          FROM information_schema.tables GROUP BY table_schema ORDER BY mb DESC;"
```

!!! tip "Apunta el tamaño total"
    Te hará falta para saber si hay disco suficiente. La regla es
    `tamaño_datos × 2` para el volcado, más `tamaño_del_zip × días_de_retención`
    para el archivo.

## Lista de comprobación

Antes de pasar a la instalación en serio:

- [ ] `backupctl -p MiVPS config --check` devuelve `0`
- [ ] `ssh admin@mivps` entra sin pedir contraseña **y da una shell**
- [ ] `zip`, `unzip` y `rsync` instalados en el VPS
- [ ] Usuario de MySQL creado y con permisos comprobados
- [ ] `deploy --dry-run` dice que no falta ninguna dependencia
- [ ] Sé cuánto ocupan las bases de datos y cuánto disco libre hay
- [ ] Sé qué crons tiene ya el usuario en HestiaCP
- [ ] Tengo claro que los scripts que ya haya allí **no se van a borrar**

---

Cuando todo esté marcado: **[2. Instalar en serio](instalar.md)**.
