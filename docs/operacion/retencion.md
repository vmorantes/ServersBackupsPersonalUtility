# Retención

Sin retención, ~40 MB diarios se convierten en **1,2 GB al mes** y el disco
acaba lleno, que es la forma más tonta de quedarse sin respaldos.

Se aplica automáticamente al final de cada `backup`, o a mano:

```bash
backupctl retention --dry-run     # qué se borraría
backupctl retention               # borrarlo
```

## Política

| Variable | Por defecto | Qué controla |
|---|---|---|
| `BACKUP_RETENTION_DAYS` | `14` | Antigüedad máxima de los `.zip` |
| `LOG_RETENTION_DAYS` | `30` | Antigüedad máxima de los logs |
| `RESTIC_RETENTION_DAYS` | `90` | Antigüedad máxima de los volcados de claves Restic |
| `BACKUP_KEEP_MIN` | `3` | **Mínimo intocable** de respaldos recientes |

`0` en cualquiera de los días desactiva ese borrado.

## La red de seguridad

!!! danger "Por qué existe `BACKUP_KEEP_MIN`"
    Imagina que el cron lleva tres semanas parado sin que nadie lo note. Todos
    tus respaldos tienen más de 14 días. La primera ejecución que arregle el
    cron aplicaría la retención y **borraría absolutamente todo** justo antes
    de crear el primero nuevo — y si ese fallara, te quedas sin nada.

    `BACKUP_KEEP_MIN` protege los N más recientes **sin importar su
    antigüedad**. Es deliberadamente conservador.

```
[INFO ] Retención de respaldos: 4 borrados (152.3M liberados), 10 conservados. Mínimo protegido: 3.
```

## Temporales huérfanos

Si un respaldo muere de golpe (corte de luz, `kill -9`), su directorio temporal
queda en disco. Como lleva una marca de tiempo en el nombre, la siguiente
ejecución nunca lo borraría: solo limpia el suyo.

`backupctl` barre al empezar los `temp_sql_*` de más de 24 horas:

```
[AVISO] eliminando temporales huérfanos de ejecuciones anteriores:
        /home/admin/scripts/output/temp_sql_20260901_031500_9912
```

## Cuánto espacio necesito

```
espacio ≈ tamaño_del_zip × BACKUP_RETENTION_DAYS
```

Para 76 bases de datos que dan un zip de 38 MB y 14 días de retención: unos
**530 MB**. Añade margen para el trabajo temporal durante el volcado, que es
donde `MIN_FREE_MB` y `DISK_SAFETY_FACTOR` hacen su papel.

```bash
backupctl list        # ver el total ocupado ahora mismo
```

## Estrategia recomendada

Esto guarda copias **en el propio servidor**, que es la primera línea, no la
única. La segunda es Restic/HestiaCP llevándose ese directorio fuera de la
máquina.

!!! tip "La regla 3-2-1"
    Tres copias, en dos medios, una fuera del sitio. `backupctl` cubre la copia
    local; el envío externo lo hace Restic. Ver [Claves Restic](restic.md).
