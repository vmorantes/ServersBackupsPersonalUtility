# Decisiones de diseño

Por qué el sistema es así y no de otra manera. Cada decisión sale de un fallo
real.

## Detección de errores

!!! danger "El problema"
    `mysqldump --force` termina con **código de salida 0** aunque no haya podido
    volcar una tabla. Si su salida de error se manda a `/dev/null`, el resultado
    es un `.zip` de aspecto perfectamente normal al que le faltan datos, sin
    ninguna señal hasta el día que hace falta restaurar.

**La decisión.** Capturar stderr de cada volcado a un archivo, registrarlo
íntegro, distinguir avisos de errores reales, y hacer que el respaldo devuelva
código 1 con la lista de bases fallidas.

**Por qué se conserva `--force`.** Ante un objeto roto es preferible un volcado
parcial **con aviso** a no tener nada. Lo inaceptable no es el volcado parcial:
es no enterarse.

## Fichero de credenciales en vez de `-p`

Con `-p`, el cliente escribe en stderr `Using a password on the command line
interface can be insecure` en **cada** invocación. Son 6 volcados por base de
datos: con 76 bases, ~456 líneas de ruido — y la detección de errores se basa
precisamente en leer stderr.

Con `--defaults-extra-file`, stderr queda limpio y cualquier línea que aparezca
ahí es señal real de fallo. De paso centraliza usuario, host, puerto, socket y
charset.

## Seis segmentos por base de datos

Un `.sql` monolítico obliga a restaurarlo entero. Con seis archivos se puede
recuperar solo lo que hace falta:

```bash
backupctl restore '' tienda --segments views     # sin tocar 40 MB de datos
```

Además, cada `.gz` es independiente: si uno se corrompe, los otros cinco siguen
sirviendo.

## `data.sql` no pasa por el filtro de DEFINER

Dos razones:

1. Una fila que contuviera el texto `DEFINER=` quedaría **alterada**.
2. Es con diferencia el archivo más grande; pasarlo por `sed` alarga el respaldo
   sin ninguna ganancia, porque los datos no llevan `DEFINER`.

## `SQL SECURITY DEFINER` → `INVOKER`

Quitar el `DEFINER` pero dejar `SQL SECURITY DEFINER` deja el objeto en un
estado ambiguo. Se comprobó sobre respaldos ya generados que la versión anterior
dejaba `/*!50013  SQL SECURITY DEFINER */` intacto en los `views.sql`.

## `BACKUP_KEEP_MIN`

Si el cron lleva tres semanas parado, todos los respaldos superan la antigüedad
máxima. La primera ejecución que arregle el cron los borraría **todos** justo
antes de crear el primero nuevo. Si ese fallara, cero respaldos.

`BACKUP_KEEP_MIN` protege los N más recientes sin importar su antigüedad. Es
deliberadamente conservador: el coste de guardar tres archivos de más es
despreciable comparado con el de quedarse sin ninguno.

## El script escribe su propio log

!!! danger "El fallo del porcentaje"
    En crontab, un `%` sin escapar se traduce a un salto de línea. Esta línea,
    que parece razonable, **no funciona**:

    ```cron
    30 3 * * * /ruta/script.sh >> /ruta/log_$(date +%Y%m%d).log 2>&1
    ```

La solución no fue documentar el escapado, sino **eliminar la necesidad**: si el
script gestiona y rota su propio log, la línea de cron no lleva ninguna fecha y
el problema no puede aparecer.

`backupctl doctor` además lo detecta si existe en el crontab.

## Silencio bajo cron

Con terminal, la salida se ve y se guarda. Sin terminal, solo se guarda.

Si `backup` imprimiera siempre, cron enviaría un correo diario con 500 líneas y
en una semana nadie los leería. Un canal de aviso que se ignora es peor que no
tenerlo, porque da falsa sensación de cobertura.

La contrapartida es que cron no avisa de los fallos por sí solo, y de ahí que
los [avisos](../operacion/avisos.md) sean una pieza de primera clase.

## Un solo código, N configuraciones

**El problema original.** Dos copias del mismo script de 260 líneas, mantenidas
a mano, con nombres distintos (`BackupAllMySQLServer.sh` y `RunBackupDB.sh`) y
ya divergiendo.

**La decisión.** El código es idéntico en todas las máquinas y todo lo que
cambia vive en `env.sh`. Desplegar es copiar `bin/` y `lib/` más un archivo de
configuración. No hay plantillas que rellenar ni variantes que puedan divergir.

## Formato abierto

`zip` + `gzip` + SQL plano. Nada propietario.

Si `backupctl` desapareciera mañana, cualquiera con `unzip` y `mysql` puede
restaurar. Un formato propietario en un sistema de respaldo es un riesgo, no una
función. La [receta de restauración manual](../guias/recetas.md#restaurar-sin-backupctl)
está documentada a propósito.

## Manifiesto con sumas SHA-256

Un zip puede tener el CRC correcto y aun así contener datos alterados si se
reempaquetó. Las sumas por archivo cierran ese hueco y permiten señalar
exactamente **qué** archivo cambió.

Además el manifiesto registra si el respaldo se generó con fallos, de modo que
`verify` puede detectarlo aunque el log ya no exista.

## `--dry-run` en casi todo

Ver qué haría una orden antes de lanzarla es lo que permite usarla con
confianza. Está en `backup`, `restore`, `retention`, `restic`, `deploy` y
`migrate`.

## `--into` en la restauración

Restaurar encima destruye lo que quedaba, que puede ser más reciente que el
respaldo. Restaurar **al lado** deja decidir con las dos versiones delante.

Es la opción más usada en una recuperación real y por eso está en el primer
nivel del menú.

## Confirmaciones que se degradan a «no»

Sin terminal, una confirmación cuyo valor por defecto es «no» responde **no**.
Las operaciones destructivas no se ejecutan por accidente en un script. Para que
sí, hay que pedirlo con `--yes` explícitamente.

## Lo que se dejó fuera a propósito

| Se descartó | Por qué |
|---|---|
| Respaldos incrementales | Complejidad alta; a esta escala (38 MB/día) el ahorro no compensa el riesgo de una cadena rota |
| Cifrado del `.zip` | Restic ya cifra en el destino remoto. Cifrar dos veces complica la recuperación sin añadir garantía |
| Base de datos de estado | El sistema de archivos ya es el estado. Un índice que se desincroniza es un problema nuevo |
| Barra de progreso en la TUI | Ocultaría el log, que es donde está la información útil |
| Respaldo de usuarios de MySQL | Restaurarlos en otra máquina causa más problemas de los que resuelve |
