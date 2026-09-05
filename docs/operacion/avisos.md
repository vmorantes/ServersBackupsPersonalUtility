# Avisos

!!! quote "Un cron que falla en silencio es un respaldo que no existe."

Hay tres canales, todos opcionales. **Configura al menos uno.**

```bash
backupctl notify-test     # comprobar que llegan
```

## Los tres canales

=== "Healthcheck (recomendado)"

    ```bash
    export HEALTHCHECK_URL="https://hc-ping.com/tu-uuid"
    ```

    Se hace ping a la URL cuando el respaldo termina bien, y a `<URL>/fail` con
    el detalle cuando falla.

    !!! success "Es el único que detecta el silencio"
        Los otros dos canales solo pueden avisar si el respaldo **se ejecuta**.
        Si el cron se para, la máquina se apaga o el disco se llena de forma que
        el script ni arranca, no hay nada que envíe un correo.

        Un healthcheck espera un ping periódico y **avisa si no llega**. Es la
        única forma de detectar que dejó de ejecutarse.

    Servicios: [healthchecks.io](https://healthchecks.io), Uptime Kuma
    (autoalojado), Cronitor.

=== "Correo"

    ```bash
    export NOTIFY_EMAIL="tu@correo.com"
    ```

    Requiere `mail` instalado y configurado en el servidor. Si no lo está,
    `backupctl` avisa en lugar de fallar en silencio:

    ```
    [AVISO] NOTIFY_EMAIL está configurado pero 'mail' no está instalado
    ```

=== "Orden arbitraria"

    ```bash
    export NOTIFY_COMMAND='curl -fsS -H "Title: $NOTIFY_SUBJECT" -d "$NOTIFY_BODY" https://ntfy.sh/mi-canal'
    ```

    Recibe dos variables de entorno:

    | Variable | Contenido |
    |---|---|
    | `NOTIFY_SUBJECT` | `[perfil] Respaldo MySQL INCOMPLETO: 2 BD con fallos` |
    | `NOTIFY_BODY` | Servidor, perfil, archivo, duración, lista de bases fallidas y ruta del log |

    Ejemplos:

    ```bash
    # Telegram
    export NOTIFY_COMMAND='curl -fsS -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" -d chat_id=$CHAT -d text="$NOTIFY_SUBJECT
    $NOTIFY_BODY"'

    # Slack
    export NOTIFY_COMMAND='curl -fsS -X POST -H "Content-type: application/json" -d "{\"text\":\"$NOTIFY_SUBJECT\"}" $SLACK_WEBHOOK'

    # Escribir en el log del sistema
    export NOTIFY_COMMAND='logger -t backupctl -p daemon.err "$NOTIFY_SUBJECT"'
    ```

Se pueden combinar los tres: se disparan todos.

## Cuándo se avisa

| Situación | Aviso |
|---|---|
| Respaldo con bases de datos fallidas | Fallo, con la lista |
| Respaldo correcto | Ping de éxito al healthcheck |
| El script ni arranca | Solo lo detecta el healthcheck (por ausencia de ping) |

## Un fallo notificando no rompe el respaldo

Todos los canales son tolerantes a su propio error. Si el healthcheck no
responde o `mail` falla, se registra un aviso y el respaldo sigue su curso con
su código de salida real:

```
[AVISO] no se pudo avisar al healthcheck
```

Un fallo notificando jamás debe enmascarar el resultado de la operación.

## Comprobar

```bash
backupctl notify-test
```

```
[INFO ] Enviando aviso de prueba por los canales configurados...
[  OK ] Aviso de prueba enviado. Comprueba que ha llegado.
```

Si no hay ninguno configurado, lo dice:

```
[AVISO] no hay ningún canal de aviso configurado en /home/admin/scripts/env.sh.
```

`backupctl status` y `backupctl doctor` también lo señalan.
