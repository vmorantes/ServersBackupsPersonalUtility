# Referencia de órdenes

```bash
backupctl [opciones globales] <orden> [opciones]
```

## Resumen

| Orden | Qué hace |
|---|---|
| [`tui`](#tui) | Menú interactivo (por defecto sin argumentos) |
| [`status`](#status) | ¿Estoy protegido ahora mismo? |
| [`doctor`](#doctor) | Diagnóstico completo del entorno |
| [`backup`](#backup) | Respaldar las bases de datos |
| [`verify`](#verify) | Verificar un respaldo |
| [`restore`](#restore) | Restaurar una base de datos |
| [`list`](#list) | Respaldos disponibles |
| [`inspect`](#inspect) | Metadatos e inventario de un respaldo |
| [`deploy`](#deploy) | **Subir** backupctl y la config a un servidor |
| [`pull`](#pull) | **Descargar** al repo el estado real de un servidor |
| [`remote`](#remote) | Ejecutar cualquier orden **en** el servidor, desde tu equipo |
| [`migrate`](#migrate) | Migrar bases de datos a otro servidor |
| [`restic`](#restic) | Volcar las claves Restic de HestiaCP |
| [`restic-list`](#restic-list) | Ver los repositorios Restic detectados |
| [`retention`](#retention) | Aplicar la política de retención |
| [`cron`](#cron) | Programación automática |
| [`logs`](#logs) | Registros |
| [`config`](#config) | Configuración |
| [`notify-test`](#notify-test) | Enviar un aviso de prueba |
| [`profiles`](#profiles) | Listar perfiles |

## Ensayos

Admiten `--dry-run` (enseñan qué harían, sin hacerlo):

```
backup · restore · retention · restic · deploy · pull · migrate
```

Para `cron`, el ensayo es `cron --show`. Para `verify`, la versión más barata es
`--quick`.

Las demás órdenes o solo leen (`status`, `doctor`, `list`, `inspect`, `logs`,
`config --show`, `profiles`) o son en sí mismas la comprobación
(`notify-test`).

Ver la tabla completa de [qué escribe cada orden](../paso-a-paso/index.md#que-escribe-cada-orden).

## Opciones globales

| Opción | Efecto |
|---|---|
| `-p`, `--profile <nombre>` | Perfil con el que trabajar |
| `-y`, `--yes` | Responder que sí a todo |
| `--debug` | Salida detallada |
| `--no-color` | Sin colores |
| `--plain` | TUI en texto plano |
| `-h`, `--help` | Ayuda |
| `-V`, `--version` | Versión |

---

## tui

```bash
backupctl tui
backupctl              # equivalente, si hay terminal
```

Abre el menú interactivo. Requiere terminal.

## status

```bash
backupctl status
```

Panel de un vistazo: antigüedad del último respaldo, número guardado, espacio en
disco, conexión a MySQL, avisos configurados y errores del último log.

**Salida:** `0` si todo bien, `1` si algo requiere atención.

## doctor

```bash
backupctl doctor
```

Comprueba órdenes del sistema, configuración, directorios, disco, MySQL,
privilegios, capacidades de `mysqldump`, respaldos existentes y crontab.

**Salida:** `0` sin fallos (los avisos no cuentan), `1` con fallos.

## backup

```bash
backupctl backup [--only a,b] [--exclude c,d] [--no-data] [--dry-run]
```

| Opción | Efecto |
|---|---|
| `--only a,b` | Solo esas bases de datos |
| `--exclude c,d` | Todas menos esas |
| `--no-data` | Solo estructura |
| `--dry-run`, `-n` | Enseñar sin escribir |

Escribe su propio log. Toma bloqueo `flock`. Aplica retención al terminar.

**Salida:** `0` correcto, `1` alguna base falló, `2` no se pudo empezar.

## verify

```bash
backupctl verify [archivo] [--quick] [--restore-test <bd>] [--with-data]
```

| Opción | Efecto |
|---|---|
| *(sin archivo)* | El respaldo más reciente |
| `--quick` | Solo el CRC del zip |
| `--restore-test <bd>` | Restaurar de verdad en una BD desechable |
| `--with-data` | Incluir los datos en la prueba |

**Salida:** `0` sin problemas, `1` con problemas, `2` no se pudo empezar.

## restore

```bash
backupctl restore <archivo|''> <bd> [--into <otra>] [--segments a,b] [--dry-run]
```

| Opción | Efecto |
|---|---|
| `''` como archivo | El más reciente |
| `--into <otra>` | Restaurar con otro nombre |
| `--segments a,b` | Solo esos segmentos |
| `--dry-run`, `-n` | Enseñar sin ejecutar SQL |

Segmentos: `database`, `tables`, `data`, `functions`, `views`, `others`.
Pide confirmación si el destino existe (salvo `--yes`).

## list

```bash
backupctl list
backupctl list --databases [archivo]
```

Sin argumentos, tabla de respaldos con tamaño, fecha, antigüedad y número de
bases. Con `--databases`, las bases que contiene un respaldo.

## inspect

```bash
backupctl inspect [archivo]
```

Lee el `MANIFEST.txt` sin extraer el resto del zip: instantáneo. Muestra
metadatos de origen e inventario por base de datos.

## deploy

```bash
backupctl deploy [usuario@host] [--path <ruta>] [--dry-run]
```

Copia `bin/` y `lib/` más el `env.sh` del perfil, y ejecuta `doctor` en el
destino. Sin argumento usa `DEPLOY_USER@DEPLOY_HOST`.

## pull

```bash
backupctl pull [usuario@host] [--path <ruta>] [--dry-run]
```

El inverso de `deploy`. Compara el `env.sh` del servidor con el del repositorio
(mostrando el `diff` y preguntando cuál conservar) y escribe `ESTADO.md` en la
carpeta del perfil con la versión instalada, el crontab, los respaldos y el
diagnóstico. Crea `NOTAS.md` si no existe; nunca lo sobrescribe.

Sin argumento usa `DEPLOY_USER@DEPLOY_HOST`. Ver
[Subir y descargar](../migracion/despliegues.md).

## remote

```bash
backupctl remote [--to usuario@host] [--path <ruta>] <orden> [opciones]
```

Ejecuta cualquier orden de `backupctl` en el servidor, con la salida en vivo.
Sin `--to` usa `DEPLOY_USER@DEPLOY_HOST`.

```bash
backupctl -p MiVPS remote status
backupctl -p MiVPS remote backup
backupctl -p MiVPS remote verify --restore-test tienda --with-data
backupctl -p MiVPS remote cron --install
```

Las órdenes que allí necesitan root (`restic`, `cron --install/--remove`) se
detectan y se lanzan con `sudo` automáticamente. La contraseña, si hace falta,
se pide una sola vez gracias a la conexión reutilizada.

## migrate

```bash
backupctl migrate --to <destino> [opciones]
```

| Opción | Efecto |
|---|---|
| `--to usuario@host` | Destino |
| `--fresh` | Generar un respaldo nuevo antes |
| `--from <zip>` | Usar un respaldo concreto |
| `--databases a,b` | Solo esas bases |
| `--prefix <pre>` | Prefijo en el destino |
| `--path <ruta>` | Ruta de backupctl en el destino |
| `--dry-run` | Ensayo |

Exige `backupctl` operativo en el destino. Compara recuentos al final.

## restic

```bash
sudo backupctl restic [--dry-run]
```

Vuelca los `restic.conf` de HestiaCP a un único archivo. **Requiere root.**

## restic-list

```bash
backupctl restic-list
```

Lista los repositorios Restic detectados, sin volcar nada.

## retention

```bash
backupctl retention [--dry-run]
```

Aplica la política a respaldos, logs y volcados de Restic.

## cron

```bash
backupctl cron [--show|--install|--remove] [--hour H] [--minute M]
```

`--show` es el valor por defecto. La instalación es idempotente: reinstalar
sustituye el bloque del perfil, no lo duplica.

## logs

```bash
backupctl logs [--list|--errors|--tail|--full|--follow]
```

| Opción | Efecto |
|---|---|
| `--list` (por defecto) | Todos los logs con recuento de errores |
| `--errors` | Errores y avisos del último |
| `--tail` | Últimas 50 líneas del último |
| `--full` | Último log completo |
| `--follow`, `-f` | Seguir en vivo |

## config

```bash
backupctl config [--show|--check|--edit|--show-secrets|--path]
```

| Opción | Efecto |
|---|---|
| `--show` (por defecto) | Configuración efectiva, contraseña enmascarada |
| `--show-secrets` | Igual, con la contraseña visible |
| `--check` | Validar. Código `1` si hay problemas |
| `--edit` | Abrir en `$EDITOR` y validar la sintaxis al guardar |
| `--path` | Solo la ruta del `env.sh` |

## notify-test

```bash
backupctl notify-test
```

Envía un aviso de prueba por todos los canales configurados.

## profiles

```bash
backupctl profiles
```

Lista los perfiles disponibles y la ruta de su `env.sh`. No necesita un perfil
cargado.
