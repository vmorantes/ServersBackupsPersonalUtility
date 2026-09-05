# Restaurar

```bash
backupctl restore <archivo|''> <base_de_datos> [opciones]
```

`''` como archivo significa **el respaldo más reciente**.

## Lo primero: ensayar

```bash
backupctl restore '' tienda --dry-run
```

```
== Restauración ==
[INFO ] Respaldo: .../all_databases_20260905_033012.zip
[INFO ] Origen:   tienda
[INFO ] Destino:  tienda
[AVISO] la base de datos 'tienda' YA EXISTE en el servidor y tiene 41 tablas.
[INFO ] Plan:
        database.sql.gz  (134B)
        tables.sql.gz    (4.3K)
        data.sql.gz      (71.0K)
        ...
[  OK ] Simulación (--dry-run): no se ha ejecutado ningún SQL.
```

## Restaurar sin tocar la base viva

La opción más útil de todas:

```bash
backupctl restore '' tienda --into tienda_recuperada
```

Restaura el respaldo **con otro nombre**, dejando `tienda` intacta. Así puedes
comparar, extraer una tabla concreta o comprobar que el respaldo era bueno antes
de decidir nada.

```sql
-- Comparar recuentos
SELECT COUNT(*) FROM tienda.pedidos;
SELECT COUNT(*) FROM tienda_recuperada.pedidos;

-- Recuperar solo lo que falta
INSERT INTO tienda.pedidos
SELECT * FROM tienda_recuperada.pedidos WHERE id NOT IN (SELECT id FROM tienda.pedidos);
```

## Restaurar solo una parte

```bash
backupctl restore '' tienda --segments views              # solo las vistas
backupctl restore '' tienda --segments tables,views       # estructura
backupctl restore '' tienda --segments data               # solo datos
```

Segmentos válidos: `database`, `tables`, `data`, `functions`, `views`, `others`.

!!! tip "Caso típico"
    Alguien rompió una vista en producción. No hace falta restaurar 40 MB:

    ```bash
    backupctl restore '' tienda --segments views
    ```

## Orden de restauración

Cuando no se especifican segmentos se aplican en este orden, que **no es
arbitrario**:

```
database → tables → data → functions → views → others
```

Las vistas pueden depender de tablas y de funciones; los triggers, de las
tablas. `database` va primero porque crea la base con su charset correcto.

## Protecciones

!!! warning "Sobre una base existente"
    Si el destino ya existe, se avisa y se pide confirmación:

    ```
    [AVISO] la base de datos 'tienda' YA EXISTE en el servidor y tiene 41 tablas.
    [AVISO] Restaurar encima puede sobrescribir tablas con los datos del respaldo.
    ¿Continuar y restaurar sobre 'tienda'? [s/N]
    ```

    Con `--yes` se salta la pregunta. Úsalo solo en scripts donde ya sabes lo
    que hay.

Al terminar se cuenta lo que quedó realmente:

```
== Resultado ==
[INFO ] Base de datos 'tienda_recuperada': 41 tablas, 6 vistas, 3 rutinas, 2 triggers.
[INFO ] Segmentos aplicados: 6. Con fallos: 0.
[  OK ] Restauración completada.
```

## Restauración manual

Si prefieres hacerlo a mano, cada archivo es autónomo (lleva su propio `USE`):

```bash
cd /tmp && unzip /home/admin/scripts/output/mysql_backups/all_databases_XXXX.zip
cd tienda

zcat database.sql.gz  | mysql
zcat tables.sql.gz    | mysql
zcat data.sql.gz      | mysql
zcat functions.sql.gz | mysql
zcat views.sql.gz     | mysql
zcat others.sql.gz    | mysql
```

Para restaurar con otro nombre hay que quitar el `USE` y seleccionar el destino:

```bash
zcat tables.sql.gz | sed -E 's/^USE `[^`]*`;$//' | mysql otra_base
```

## Restaurar en otro servidor

Eso es una [migración](../migracion/migrar.md), y tiene orden propia.
