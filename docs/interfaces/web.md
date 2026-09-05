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

## Lo que la web NO hace

Deliberadamente:

- **`restore` y `migrate`**, que escriben en bases de datos. Son las dos
  operaciones donde equivocarse duele de verdad y merecen el terminal, con su
  ensayo previo delante.
- **`setup`**, que pide credenciales de administrador. Teclear una contraseña de
  root en un formulario web local es una costumbre que no conviene coger.
- **`cron --install`**, que necesita `sudo` interactivo.

Para eso están [la CLI](cli.md) y [las guías paso a paso](../paso-a-paso/index.md).

## Cuándo usar cada fachada

| Situación | Fachada |
|---|---|
| Revisar de un vistazo si todo va bien | **Web** |
| Administrar varios VPS a la vez | **Web** |
| Operar un servidor concreto sin recordar órdenes | **TUI** |
| Restaurar o migrar | **CLI**, con su ensayo |
| Cron y scripts | **CLI** |
