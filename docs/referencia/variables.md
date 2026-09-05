# Variables de configuración

Todas viven en el `env.sh` del perfil. **Todas tienen un valor por defecto
razonable**: un `env.sh` mínimo son dos líneas.

```bash
export MYSQL_USER="admin_general"
export MYSQL_PASS="la-contraseña"
```

```bash
backupctl config --show      # ver los valores efectivos
backupctl config --check     # validarlos
backupctl config --edit      # editar y validar la sintaxis al guardar
```

## Generales

| Variable | Por defecto | Descripción |
|---|---|---|
| `USER_NAME` | usuario actual | Usuario del sistema propietario de scripts y salidas |
| `SCRIPTS_DIR` | directorio del perfil | Raíz de la instalación; los demás directorios cuelgan de aquí |

## Conexión a MySQL

| Variable | Por defecto | Descripción |
|---|---|---|
| `MYSQL_USER` | *(vacío)* | **Obligatoria.** Usuario de MySQL |
| `MYSQL_PASS` | *(vacío)* | Contraseña. Vacía = sin contraseña |
| `MYSQL_HOST` | *(vacío)* | Vacío = socket local |
| `MYSQL_PORT` | *(vacío)* | Vacío = puerto por defecto |
| `MYSQL_SOCKET` | *(vacío)* | Ruta del socket, si no es la estándar |
| `MYSQL_CHARSET` | `utf8mb4` | Juego de caracteres del volcado |

!!! warning "MYSQL_CHARSET"
    Cambiarlo a `utf8` o `latin1` **corrompe emojis y caracteres multibyte de
    forma silenciosa**. Solo tiene sentido en servidores muy antiguos.

## Selección de bases de datos

| Variable | Por defecto |
|---|---|
| `EXCLUDE_DBS` | `('information_schema','performance_schema','mysql','sys','phpmyadmin')` |

Lista SQL entre paréntesis. Se usa tal cual en un `NOT IN`.

```bash
export EXCLUDE_DBS="('information_schema','performance_schema','mysql','sys','phpmyadmin','cache_temporal')"
```

!!! note
    Excluir `mysql` significa que **usuarios y privilegios no se respaldan**.
    Es intencionado: restaurarlos en otra máquina causa más problemas de los que
    resuelve. Ver [Portabilidad](../migracion/portabilidad.md).

## Rutas

| Variable | Por defecto |
|---|---|
| `BACKUP_OUTPUT_DIR` | `$SCRIPTS_DIR/output/mysql_backups` |
| `BACKUP_WORK_DIR` | `$SCRIPTS_DIR/output` |
| `HESTIA_OUTPUT_DIR` | `$SCRIPTS_DIR/output/HestiaCP` |
| `LOG_DIR` | `$SCRIPTS_DIR/logs` |

`BACKUP_WORK_DIR` es donde se construye el respaldo antes de empaquetarlo:
necesita espacio para el volcado **sin comprimir**.

## Retención

| Variable | Por defecto | Descripción |
|---|---|---|
| `BACKUP_RETENTION_DAYS` | `14` | Días que se guardan los `.zip`. `0` desactiva |
| `LOG_RETENTION_DAYS` | `30` | Días que se guardan los logs. `0` desactiva |
| `RESTIC_RETENTION_DAYS` | `90` | Días que se guardan los volcados de Restic |
| `BACKUP_KEEP_MIN` | `3` | Mínimo intocable de respaldos recientes |

Ver [Retención](../operacion/retencion.md).

## Comprobaciones previas

| Variable | Por defecto | Descripción |
|---|---|---|
| `MIN_FREE_MB` | `2048` | Espacio libre mínimo exigido (suelo absoluto) |
| `DISK_SAFETY_FACTOR` | `2` | Multiplicador sobre el tamaño de los datos |

El espacio exigido es `tamaño_datos × DISK_SAFETY_FACTOR`, con `MIN_FREE_MB`
como suelo. El volcado sin comprimir ocupa más que los datos en disco.

## Avisos

| Variable | Por defecto | Descripción |
|---|---|---|
| `NOTIFY_EMAIL` | *(vacío)* | Correo. Requiere `mail` instalado |
| `NOTIFY_COMMAND` | *(vacío)* | Orden a ejecutar. Recibe `NOTIFY_SUBJECT` y `NOTIFY_BODY` |
| `HEALTHCHECK_URL` | *(vacío)* | Ping al terminar bien, `<URL>/fail` al fallar |

Ver [Avisos](../operacion/avisos.md).

## HestiaCP

| Variable | Por defecto |
|---|---|
| `HESTIA_DIR` | `/usr/local/hestia` |

## Despliegue y migración

| Variable | Por defecto | Descripción |
|---|---|---|
| `DEPLOY_HOST` | *(vacío)* | Servidor destino por defecto |
| `DEPLOY_USER` | `$USER_NAME` | **Quién se conecta** por SSH. Necesita shell |
| `DEPLOY_PATH` | `/home/$USER_NAME/scripts` | Ruta en el destino |

!!! tip "`DEPLOY_USER` y `USER_NAME` son papeles distintos"
    | Variable | Papel | ¿Necesita shell? |
    |---|---|---|
    | `DEPLOY_USER` | Quién abre la sesión SSH | **Sí** |
    | `USER_NAME` | De quién es la instalación y los respaldos | No |

    En HestiaCP muchos usuarios se crean con `nologin`. En vez de darles acceso,
    conéctate como `admin` e instala en el home del otro: `deploy` ajusta el
    propietario con `chown` al terminar.

Con estas definidas, `backupctl deploy` y `migrate` funcionan sin argumentos.

## Variables de entorno (no van en env.sh)

| Variable | Efecto |
|---|---|
| `BC_DEBUG=1` | Equivale a `--debug` |
| `BC_NO_COLOR=1` | Equivale a `--no-color` |
| `BC_TUI_PLAIN=1` | Equivale a `--plain` |
| `EDITOR` | Editor que usa `config --edit` |
| `TMPDIR` | Dónde se crean los temporales |

## Ejemplo completo

```bash
#!/usr/bin/env bash
# env.sh — servidor de producción

export USER_NAME="admin"
export SCRIPTS_DIR="/home/${USER_NAME}/scripts"

export MYSQL_USER="admin_general"
export MYSQL_PASS="..."
export MYSQL_CHARSET="utf8mb4"

export EXCLUDE_DBS="('information_schema','performance_schema','mysql','sys','phpmyadmin')"

export BACKUP_RETENTION_DAYS="14"
export LOG_RETENTION_DAYS="30"
export BACKUP_KEEP_MIN="3"
export MIN_FREE_MB="4096"

export HEALTHCHECK_URL="https://hc-ping.com/xxxx-xxxx"

export DEPLOY_HOST="nuevo.example"
export DEPLOY_USER="admin"
```
