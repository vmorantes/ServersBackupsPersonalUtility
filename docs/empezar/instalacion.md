# Instalación

## Requisitos

**Imprescindibles** (el diagnóstico falla sin ellos):

```
bash 4+   mysql   mysqldump   gzip   zip   unzip   find   sha256sum   flock
```

**Opcionales** (cada uno habilita una función):

| Orden | Habilita |
|---|---|
| `curl` | Avisos por `HEALTHCHECK_URL` |
| `mail` | Avisos por `NOTIFY_EMAIL` |
| `rsync`, `ssh` | `deploy` y `migrate` |
| `whiptail` o `dialog` | Menús gráficos en la TUI (sin ellos, menú de texto) |
| `column` | Tablas mejor alineadas |

Comprueba todo de una vez:

```bash
backupctl doctor
```

## Qué hay que preparar en el servidor

Solo tres cosas. El resto lo crea `deploy`.

| Requisito | Comprobación | Si falta |
|---|---|---|
| **Un usuario con acceso SSH** | `ssh root@servidor hostname` | Vale contraseña; se pide una sola vez |
| **`zip`, `unzip`, `rsync`** | `deploy` lo comprueba solo | **`deploy` se ofrece a instalarlos** |
| **Usuario de MySQL** | `mysql -u X -p -e "SHOW DATABASES;"` | **`backupctl setup` puede crearlo** |

!!! tip "O deja que el asistente lo haga todo"
    ```bash
    backupctl setup
    ```
    Pregunta lo necesario, crea el usuario de MySQL si le das una credencial de
    administrador —que no se guarda—, escribe el `env.sh` y despliega.

!!! tip "HestiaCP: si el usuario no tiene shell, NO hace falta dárselo"
    Los usuarios de HestiaCP suelen crearse con `nologin`, así que SSH acepta y
    cierra al instante. En lugar de cambiarles el acceso, conéctate con uno que
    sí tenga shell (`admin` o `root`) y declara de quién es la instalación:

    ```bash
    export DEPLOY_USER="root"      # quien se conecta; los usuarios del panel no tienen consola      # quién se conecta
    export USER_NAME="cliente07"    # de quién es la instalación
    ```

    Solo si prefieres darle shell: **Usuarios → SSH Access → bash**, o
    `sudo v-change-user-shell admin bash`.

**No hace falta** crear `/home/admin/scripts`, ni `logs/`, ni `output/`: los crea
`deploy`.

## Instalar en un servidor

=== "Desde otra máquina (recomendado)"

    Si ya tienes el repositorio en tu equipo, despliega por SSH:

    ```bash
    backupctl -p TejidoTesting deploy root@servidor.example
    ```

    Copia `bin/` y `lib/`, sube el `env.sh` del perfil y ejecuta el diagnóstico
    en el destino. Ver [Desplegar](../migracion/desplegar.md).

=== "A mano"

    ```bash
    # 1. Copiar el tooling
    scp -r bin lib root@servidor:/home/admin/scripts/

    # 2. Configuración
    scp config/env.sh.example root@servidor:/home/admin/scripts/env.sh

    # 3. En el servidor
    ssh root@servidor
    cd /home/admin/scripts
    mkdir -p logs output
    chmod +x bin/backupctl
    ${EDITOR:-nano} env.sh          # completar MYSQL_USER y MYSQL_PASS
    ```

## Configurar

Edita `env.sh`. Lo mínimo son dos líneas:

```bash
export MYSQL_USER="admin_general"
export MYSQL_PASS="la-contraseña"
```

Todo lo demás tiene un valor por defecto razonable. La
[referencia de variables](../referencia/variables.md) las lista todas.

Comprueba que es válida:

```bash
backupctl config --check
backupctl config --show      # ver los valores efectivos, con los defectos ya aplicados
```

## Privilegios de MySQL

El usuario necesita esto para un volcado completo:

```sql
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS
  ON *.* TO 'admin_general'@'localhost';
FLUSH PRIVILEGES;
```

| Privilegio | Sin él |
|---|---|
| `SELECT` | No hay volcado posible |
| `SHOW VIEW` | Las vistas salen vacías |
| `TRIGGER` | Faltan los triggers |
| `EVENT` | Faltan los eventos programados |
| `LOCK TABLES` | Necesario para tablas no InnoDB |
| `PROCESS` | Solo si quitas `--no-tablespaces` |

`backupctl doctor` comprueba cuáles tienes y avisa de los que falten.

## Comprobar y programar

```bash
# 1. Diagnóstico: debe salir sin fallos
backupctl doctor

# 2. Primer respaldo a mano
backupctl backup
echo "código: $?"          # 0 = correcto

# 3. Verificarlo
backupctl verify

# 4. La prueba de verdad
backupctl verify --restore-test <una_base_de_datos> --with-data

# 5. Programarlo
backupctl cron --install
```

!!! danger "No des por instalado hasta el paso 4"
    Los pasos 1–3 comprueban que el archivo existe y está íntegro. El paso 4
    es el único que comprueba que **sirve para restaurar**.

## Poder llamarlo sin `./bin/`

Lo primero que querrás hacer en tu equipo:

```bash
./bin/backupctl install
```

Crea un enlace en el primer directorio de tu `PATH` donde se pueda escribir
—normalmente `~/.local/bin`, **sin sudo**— y comprueba que funciona:

```
[INFO ] Se usará /home/tu-usuario/.local/bin (está en tu PATH, no hace falta sudo).
[INFO ] Enlace: /home/tu-usuario/.local/bin/backupctl  ->  /ruta/al/repo/bin/backupctl
[  OK ] 'backupctl' ya funciona desde cualquier directorio.
```

Si no hay ninguno propio en el `PATH`, usa `/usr/local/bin` y pide `sudo`.

Es un **enlace, no una copia**: al actualizar el repositorio la orden apunta
sola a la versión nueva. `backupctl` resuelve los enlaces simbólicos, así que
encuentra su `lib/` aunque se le llame desde otra ruta.

Para deshacerlo:

```bash
backupctl install --remove
```
