# Interfaz web local

```bash
backupctl web --open
```

La tercera fachada sobre la misma lógica. Lo que aporta sobre la TUI es ver
**todos tus servidores a la vez**: en el terminal hay que recorrerlos uno a uno.

```
  backupctl web 2.0.0
  ──────────────────────────────────────────────────────────────
  Abre esta dirección en el navegador:

    http://127.0.0.1:8787/?t=2ea4wDA7n1nAcuBky0UUglrL-gIns8OR

  La credencial de la URL se regenera en cada arranque.
  Escuchando solo en 127.0.0.1. Ctrl-C para parar.
```

Sin dependencias: solo Python 3, que ya está en cualquier sistema.

## Qué muestra

**Panel de servidores.** Una tarjeta por perfil, con su estado resumido y un
distintivo de *correcto* o *requiere atención*. Se consultan **en paralelo**, así
que con diez VPS tarda lo mismo que con uno.

**Detalle por servidor**, en cuatro pestañas:

| Pestaña | Contiene |
|---|---|
| Revisar | Estado, diagnóstico, configuración, programación, tabla de respaldos |
| Respaldar | Ensayos, respaldo, verificación, retención, prueba de restauración |
| Servidor | Ensayos de despliegue, ejecutar órdenes en el servidor, subir y descargar |
| Registros | Listar, solo errores, último completo |

**Consola.** La salida real de `backupctl`, en vivo y coloreada por nivel. No es
un resumen: es exactamente lo que verías en el terminal.

## Seguridad

!!! danger "Esta interfaz ejecuta órdenes con tus credenciales"
    Tres medidas, y conviene entender por qué está cada una.

**Escucha solo en `127.0.0.1`.** Para exponerla en la red hay que pasar `--host`
explícitamente y confirmar un aviso. No lo hagas.

**Credencial de sesión.** Se genera en cada arranque y viaja en la URL. Sin
ella, la API responde `403`. No es paranoia: cualquier página web que tengas
abierta puede hacer peticiones a tu `localhost`, y sin credencial podría
dispararte un respaldo o algo peor.

**Comprobación del `Host`.** Se rechaza cualquier petición cuyo `Host` no sea
local, lo que corta los ataques por reasignación de DNS.

**Lista blanca de acciones.** El navegador no manda órdenes: manda el nombre de
una acción de una lista fija, y el argumento se valida contra una expresión
regular. Nada de lo que llegue del navegador acaba en una shell.

??? example "Comprobado con estos intentos"
    ```
    sin credencial:            HTTP 403
    credencial incorrecta:     HTTP 403
    Host falseado:             HTTP 403
    {"action":"rm -rf /"}      → acción no permitida
    {"profile":"; touch /tmp/pwned;"}  → acción no permitida
    {"arg":"../../etc/passwd"} → acción no permitida
    ```

## Si el puerto está ocupado

Casi siempre es una interfaz anterior que quedó abierta. Se explica en lugar de
soltar un rastreo de Python:

```
  El puerto 8787 ya está ocupado.
  Lo tiene: LISTEN 127.0.0.1:8787 users:(("python3",pid=110760))

  Puede ser una interfaz web que dejaste abierta. Opciones:

    backupctl web --port 8788      usar otro puerto
    pkill -f web/server.py         cerrar la anterior
```

## Opciones

```bash
backupctl web                    # http://127.0.0.1:8787
backupctl web --port 9000
backupctl web --open             # abre el navegador solo
```

## Acciones destructivas

Las que escriben van marcadas en ámbar, las que borran en rojo, y **piden
confirmación en un diálogo** que explica qué va a pasar antes de lanzarlas.

La prueba de restauración pide el nombre de la base de datos y avisa de que
creará una desechable y la eliminará al terminar.

## Dar de alta un servidor

El botón **+ Añadir servidor** abre un formulario que hace lo mismo que
`backupctl setup`: comprueba la conexión, escribe el `env.sh` y, si lo pides,
despliega.

Si no tienes usuario de MySQL para respaldos, elige *«Créalo tú»* y te pedirá
una credencial de **administrador** de la base de datos. Se usa una vez para
crear el usuario con sus permisos y **se descarta**: no se guarda en ningún
archivo, y el formulario la borra en cuanto se envía.

Por debajo es el mismo `backupctl setup` en modo desatendido, así que no hay dos
implementaciones que puedan divergir.

## Editar la configuración

La pestaña **Configuración** edita el `env.sh` del perfil. Antes de guardar se
valida la sintaxis con `bash -n`, y la versión anterior queda como
`env.sh.anterior`.

!!! warning "El env.sh lleva la contraseña de MySQL en claro"
    Es tu archivo, en tu equipo, servido por loopback. Pero tenlo en cuenta si
    hay alguien mirando la pantalla.

## Cobertura

Todo lo de la CLI está en la web, salvo lo que no tiene sentido allí:

| Orden | En la web |
|---|---|
| `status` `doctor` `list` `inspect` `logs` `config` | ✅ pestaña Revisar |
| `backup` (con `--only`, `--exclude`, `--no-data`) | ✅ pestaña Respaldar |
| `verify` (`--quick`, `--restore-test`, `--with-data`) | ✅ pestaña Respaldar |
| `retention` | ✅ pestaña Respaldar |
| `restore` (`--into`, `--segments`) | ✅ pestaña Restaurar |
| `deploy` `pull` `remote` `migrate` | ✅ pestaña Servidor |
| `cron` `notify-test` `restic` | ✅ pestaña Programación |
| `setup` | ✅ botón + Añadir servidor |
| `config --edit` | ✅ pestaña Configuración |
| `tui` | ❌ es una interfaz de terminal |
| `install` `web` | ❌ solo tienen sentido desde el terminal |

Todas las acciones que escriben piden confirmación explicando qué va a pasar, y
las que tienen ensayo lo ofrecen al lado.

!!! warning "Las órdenes que necesitan `sudo`"
    `restic` y `cron --install` necesitan root. Desde la web no hay terminal
    donde teclear la contraseña de `sudo`, así que solo funcionan si `sudo` no
    la pide. Si falla, la salida lo dice y hay que hacerlo desde el terminal.

## Cuándo usar cada fachada

| Situación | Fachada |
|---|---|
| Revisar de un vistazo si todo va bien | **Web** |
| Administrar varios VPS a la vez | **Web** |
| Operar un servidor concreto sin recordar órdenes | **TUI** |
| Restaurar o migrar | **CLI**, con su ensayo |
| Cron y scripts | **CLI** |
