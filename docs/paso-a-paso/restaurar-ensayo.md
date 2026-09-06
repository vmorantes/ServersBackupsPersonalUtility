# 3. Restaurar — ensayo

**Nada de esta guía escribe en ninguna base de datos.** Sirve para saber qué
tienes, comprobar que sirve y ver exactamente qué haría una restauración.

Es lo que quieres ejecutar **mientras piensas** si restaurar o no.

---

## Paso 1 — ¿Qué respaldos tengo?

```bash
ssh root@mivps.example.com
cd /home/admin/scripts

./bin/backupctl list
```

```
ARCHIVO                            TAMAÑO  FECHA             EDAD  BD
all_databases_20260905_033012.zip  38.3M   2026-09-05 03:30  0d    76
all_databases_20260904_033010.zip  38.1M   2026-09-04 03:30  1d    76
```

Elige por fecha: quieres el último **anterior** al momento en que se rompió algo.

## Paso 2 — ¿Qué hay dentro?

```bash
./bin/backupctl inspect all_databases_20260904_033010.zip
```

Lee solo el manifiesto, así que es instantáneo aunque el archivo pese 38 MB.
Verás el origen, la fecha, la versión de MySQL y el inventario:

```
BASE DE DATOS   TABLAS  VISTAS  INSERT  TAMAÑO ORIGEN
tienda          41      6       160     50.0M
blog            22      0       31      10.5M
```

!!! tip "Compara con lo que hay ahora"
    ```bash
    mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='tienda';"
    ```
    Si el respaldo dice 41 tablas y ahora hay 38, ya sabes qué falta.

Y la lista completa de bases:

```bash
./bin/backupctl list --databases all_databases_20260904_033010.zip
```

## Paso 3 — ¿Ese respaldo sirve?

```bash
./bin/backupctl verify all_databases_20260904_033010.zip
```

Comprueba el zip, cada `.gz`, las sumas SHA-256 del manifiesto y el contenido
base a base. Solo extrae a un temporal, que borra al salir.

```
[  OK ] el zip es íntegro (CRC correcto).
[  OK ] 486 archivos .gz descomprimen correctamente.
[  OK ] 486 sumas SHA-256 coinciden con el manifiesto.
```

!!! warning "Fíjate en la columna ESTADO"
    | Estado | Qué significa |
    |---|---|
    | `ok` | Todo correcto |
    | `vacía` | Sin tablas. Puede ser legítimo |
    | `sin datos` | Hay tablas pero ningún `INSERT`. **Míralo** |
    | `INCOMPLETA` | Falta un archivo. **Ese respaldo no sirve** |

## Paso 4 — Ver qué haría la restauración

```bash
./bin/backupctl restore all_databases_20260904_033010.zip tienda --dry-run
```

```
[INFO ] Respaldo: .../all_databases_20260904_033010.zip
[INFO ] Origen:   tienda
[INFO ] Destino:  tienda
[AVISO] la base de datos 'tienda' YA EXISTE en el servidor y tiene 38 tablas.
[INFO ] Plan:
        database.sql.gz  (134B)
        tables.sql.gz    (4.3K)
        data.sql.gz      (71.0K)
        views.sql.gz     (1.4K)
        functions.sql.gz (1.0K)
        others.sql.gz    (513B)
[  OK ] Simulación (--dry-run): no se ha ejecutado ningún SQL.
```

El aviso de que la base ya existe es la información clave: restaurar encima
sobrescribiría las 38 tablas actuales.

## Paso 5 — Ensayar la variante segura

Casi siempre lo que quieres no es restaurar encima, sino **al lado**:

```bash
./bin/backupctl restore all_databases_20260904_033010.zip tienda \
    --into tienda_recuperada --dry-run
```

Así podrás comparar las dos versiones antes de decidir nada.

## Paso 6 — Ensayar solo una parte

```bash
# Solo las vistas
./bin/backupctl restore '' tienda --segments views --dry-run

# Solo la estructura
./bin/backupctl restore '' tienda --segments tables,views --dry-run
```

Si lo que se rompió fue una vista, no hace falta mover 40 MB de datos.

## Paso 7 — La prueba de fuego, sin tocar producción

```bash
./bin/backupctl verify all_databases_20260904_033010.zip \
    --restore-test tienda --with-data
```

!!! info "Esto sí escribe, pero se limpia solo"
    Crea una base de datos `verifybk_<marca>`, restaura ahí de verdad, cuenta lo
    que quedó y **la elimina siempre**, incluso si algo falla. Ni `tienda` ni
    ninguna otra base tuya se toca.

    Es la única comprobación que demuestra que el respaldo se puede volver a
    montar. Necesita privilegios `CREATE` y `DROP`.

```
[INFO ] Base de datos temporal: verifybk_20260905153012_4471
[  OK ]   tables restaurado.
[  OK ]   data restaurado.
[INFO ] Restaurado: 41 tablas, 6 vistas, 3 rutinas, 2 triggers.
[INFO ] Base de datos temporal verifybk_20260905153012_4471 eliminada.
```

## Lista de comprobación

- [ ] Sé qué respaldo quiero y de qué fecha es
- [ ] `verify` de ese respaldo pasa sin problemas
- [ ] El inventario cuadra con lo que espero recuperar
- [ ] `--restore-test --with-data` de esa base pasa
- [ ] He decidido si restauro **encima** o **al lado** (`--into`)
- [ ] He decidido si necesito **todo** o solo unos segmentos

---

Cuando lo tengas claro: **[4. Restaurar en serio](restaurar.md)**.
