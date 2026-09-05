# Automatización

```bash
backupctl cron --show       # ver qué propone
backupctl cron --install    # instalarlo
backupctl cron --remove     # quitarlo
```

## Lo que instala

```cron
# backupctl:TejidoTesting  (generado por: backupctl cron --install)
# Respaldo diario de las bases de datos
30 3 * * * /home/admin/scripts/bin/backupctl -p TejidoTesting backup || echo "Respaldo MySQL FALLIDO en servidor — revisa /home/admin/scripts/logs"
# Verificación estructural del último respaldo, los domingos
0 5 * * 0 /home/admin/scripts/bin/backupctl -p TejidoTesting verify --quick || echo "Verificación de respaldo FALLIDA en servidor"
# Estado semanal: avisa si el respaldo más reciente se está quedando viejo
0 9 * * 1 /home/admin/scripts/bin/backupctl -p TejidoTesting status || true
# backupctl:TejidoTesting end
```

Las marcas de inicio y fin hacen que reinstalar sea **idempotente**: se
sustituye el bloque de ese perfil, no se acumulan duplicados.

Puedes cambiar la hora:

```bash
backupctl cron --install --hour 2 --minute 15
```

## El fallo del porcentaje

!!! danger "Esta línea NO funciona"
    ```cron
    30 3 * * * /home/admin/scripts/RunBackupDB.sh >> /home/admin/scripts/logs/RunBackupDB_$(date +%Y%m%d_%H%M%S).log 2>&1
    ```

    En crontab, un **`%` sin escapar se traduce a un salto de línea**, y todo lo
    que sigue al primero se envía al proceso por la entrada estándar. La orden
    se parte y no hace lo que parece.

    Es un fallo real, silencioso y muy difícil de ver leyendo el crontab.

**La solución** es que no haga falta redirigir: `backupctl` escribe y rota su
propio log, así que la línea de cron no lleva ninguna fecha.

Si aun así necesitas un `%` en un crontab, escápalo:

```cron
30 3 * * * comando > salida_$(date +\%Y\%m\%d).log
```

`backupctl doctor` detecta este problema si existe en tu crontab:

```
✗ hay un % sin escapar en el crontab: cron lo convierte en salto de línea y parte la orden
```

## Por qué cron no te avisará solo

Bajo cron, `backupctl` **no imprime nada por pantalla**: todo va al log. Es
deliberado — si no, recibirías un correo diario con 500 líneas y dejarías de
leerlos en una semana.

La consecuencia es que **cron no enviará correo aunque el respaldo falle**. Por
eso:

1. La línea incluye `|| echo "..."`, que produce salida solo en caso de fallo.
   Con `MAILTO` configurado, eso sí llega.
2. Lo verdaderamente fiable es configurar un [aviso](avisos.md).

```cron
MAILTO=tu@correo.com
```

## Diferencias del entorno de cron

Cron ejecuta con un `PATH` mínimo y sin cargar tu perfil de shell. Si algo
funciona a mano y falla en cron, empieza por ahí:

```bash
# Reproducir el entorno de cron
env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '/home/admin/scripts/bin/backupctl status'
```

`backupctl` usa rutas absolutas y comprueba sus dependencias al arrancar
(`bc_require_cmd`), así que un `PATH` incompleto se manifiesta como un mensaje
claro y no como un fallo raro a mitad del volcado.

## Comprobar que se está ejecutando

```bash
crontab -l                          # ¿está la línea?
grep CRON /var/log/syslog | tail    # ¿la ejecuta el sistema?
backupctl list                      # ¿hay un zip de esta madrugada?
backupctl status                    # ¿está reciente?
backupctl logs --list               # errores por ejecución
```

!!! tip "La comprobación definitiva"
    Un `HEALTHCHECK_URL` es lo único que detecta que el cron **dejó de
    ejecutarse**. Ni el correo ni una orden de aviso pueden: si el respaldo
    nunca arranca, nunca hay nada que avisar. Ver [Avisos](avisos.md).
