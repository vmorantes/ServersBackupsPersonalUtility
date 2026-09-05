# Respaldar

```bash
backupctl backup
```

## Qué hace, paso a paso

1. **Comprueba el entorno**: órdenes disponibles, conexión real a MySQL y
   espacio en disco suficiente. Falla aquí antes que a mitad del volcado.
2. **Lista las bases de datos**, excluyendo las del sistema.
3. **Vuelca cada una en seis [segmentos](../empezar/conceptos.md#2-segmentos)**,
   eliminando los `DEFINER` de la estructura.
4. **Comprime** cada `.sql` a `.gz` y **verifica** que todos descomprimen.
5. **Escribe el manifiesto** con inventario y sumas SHA-256.
6. **Empaqueta** en un `.zip` y **lo verifica**; si no pasa, lo borra en lugar
   de publicarlo.
7. **Aplica la retención**.
8. **Resume** y devuelve un código de salida honesto.

## Opciones

| Opción | Efecto |
|---|---|
| `--only a,b` | Solo esas bases de datos |
| `--exclude c,d` | Todas menos esas |
| `--no-data` | Solo estructura: rápido, útil para comparar esquemas |
| `--dry-run`, `-n` | Enseña qué haría, sin escribir nada |

```bash
backupctl backup --only tienda,blog
backupctl backup --exclude logs_temporales
backupctl backup --no-data              # radiografía del esquema
backupctl backup --dry-run              # ensayo
```

## La garantía central

!!! danger "Por qué esto importa más que ninguna otra cosa"
    `mysqldump` con `--force` termina con **código 0 aunque no haya podido
    volcar una tabla**. Si su salida de error se descarta, el resultado es un
    `.zip` de aspecto perfectamente normal al que le faltan datos, y no hay
    ninguna señal de ello hasta el día que necesitas restaurar.

`backupctl` lee la salida de error de cada volcado, la registra íntegra en el
log, distingue avisos de errores reales y:

- marca la base de datos como fallida,
- la anota en el `MANIFEST` del propio respaldo,
- **devuelve código de salida 1**,
- y dispara los [avisos configurados](avisos.md).

```
[ERROR] Bases de datos CON FALLOS (2):
        - tienda
        - facturacion
[ERROR] El respaldo está INCOMPLETO. Log: /home/admin/scripts/logs/backup_...log
```

Se mantiene `--force` a propósito: ante un objeto roto es preferible un volcado
parcial **con aviso** a no tener nada.

## Registro

El respaldo **escribe y rota su propio log** en `$LOG_DIR`:

```
backup_20260905_033012.log
```

Esto no es un detalle menor: es lo que hace que la línea de cron no necesite
ninguna redirección con fecha, que es exactamente donde estaba
[el fallo del `%`](automatizacion.md#el-fallo-del-porcentaje).

Con terminal la salida se ve **y** se guarda. Bajo cron solo se guarda, para
que no llegue un correo diario con el log completo.

```bash
backupctl logs --errors     # solo lo que falló
backupctl logs --follow     # seguirlo en vivo
```

## Un solo respaldo a la vez

Se toma un bloqueo con `flock`. Si ya hay uno en curso, la segunda ejecución
aborta con un mensaje claro en lugar de competir por disco y CPU.

```
[ERROR] ya hay una operación 'backup' en curso (bloqueo: .../.backupctl.backup.lock).
```

## Espacio en disco

Antes de empezar se estima cuánto hará falta:

```
Datos a respaldar: 4.2G. Libre en disco: 55812MB. Necesario estimado: 8601MB.
```

El cálculo es el tamaño de los datos por `DISK_SAFETY_FACTOR` (2 por defecto),
con un suelo de `MIN_FREE_MB`. El volcado sin comprimir ocupa más que los datos
en disco, de ahí el factor.

## Avisos que verás

!!! warning "Tablas no InnoDB"
    ```
    [AVISO] hay tablas no InnoDB; --single-transaction NO garantiza coherencia en ellas
    ```
    `--single-transaction` toma una instantánea coherente **solo en InnoDB**.
    Con MyISAM o Aria, las tablas se vuelcan una a una y podrían no ser
    coherentes entre sí si hay escrituras durante el respaldo.

    **Qué hacer**: convertirlas a InnoDB si puedes, o respaldar en una ventana
    sin escrituras.

!!! warning "Faltan archivos en el zip"
    ```
    [AVISO] faltan archivos en el zip: algún volcado no se generó.
    ```
    Se esperaban `bases × 6` archivos y hay menos. Mira el log completo.

## Qué produce

```
output/mysql_backups/all_databases_20260905_033012.zip
├── MANIFEST.txt
├── tienda/
│   ├── database.sql.gz
│   ├── tables.sql.gz
│   ├── data.sql.gz
│   ├── views.sql.gz
│   ├── functions.sql.gz
│   └── others.sql.gz
└── blog/
    └── ...
```

Detalle completo en [Formato del respaldo](../referencia/formato.md).

## Desde la TUI

`backupctl` → **Respaldar las bases de datos ahora**, con opciones para
respaldar todo, una sola base, solo estructura, o simular.
