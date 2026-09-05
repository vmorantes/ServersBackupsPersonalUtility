# 4. Restaurar en serio

!!! danger "Esta guía ESCRIBE en tus bases de datos"
    Haz primero **[3. Restaurar — ensayo](restaurar-ensayo.md)**. Si has llegado
    aquí sin verificar el respaldo, vuelve atrás.

## Regla número uno

**Si acabas de perder datos, deja de escribir en el servidor.** Cada minuto de
actividad hace más difícil la recuperación.

```bash
# En HestiaCP, parar el sitio afectado (no todo el servidor)
sudo v-suspend-web-domain admin midominio.com
```

O directamente el servicio si es urgente:

```bash
sudo systemctl stop nginx
```

## Regla número dos

**Restaura al lado, no encima.**

Restaurar encima destruye lo que quedaba, que puede ser más reciente que el
respaldo. Restaurar al lado te deja decidir con las dos versiones delante. Es lo
que quieres en el 90 % de los casos reales.

---

## Camino A — Restaurar al lado (recomendado)

### A1. Restaurar con otro nombre

```bash
ssh admin@mivps.example.com
cd /home/admin/scripts

./bin/backupctl restore all_databases_20260904_033010.zip tienda \
    --into tienda_recuperada
```

No pregunta nada si `tienda_recuperada` no existe. Al terminar:

```
[INFO ] Base de datos 'tienda_recuperada': 41 tablas, 6 vistas, 3 rutinas, 2 triggers.
[  OK ] Restauración completada.
```

### A2. Comparar

```sql
SELECT COUNT(*) FROM tienda.pedidos;
SELECT COUNT(*) FROM tienda_recuperada.pedidos;

-- Qué falta exactamente
SELECT id FROM tienda_recuperada.pedidos
WHERE id NOT IN (SELECT id FROM tienda.pedidos);
```

### A3. Recuperar solo lo que falta

```sql
-- Filas perdidas
INSERT INTO tienda.pedidos
SELECT * FROM tienda_recuperada.pedidos
WHERE id NOT IN (SELECT id FROM tienda.pedidos);

-- O una tabla entera
DROP TABLE tienda.pedidos;
CREATE TABLE tienda.pedidos LIKE tienda_recuperada.pedidos;
INSERT INTO tienda.pedidos SELECT * FROM tienda_recuperada.pedidos;
```

### A4. Limpiar

```sql
DROP DATABASE tienda_recuperada;
```

!!! tip "No tengas prisa en borrarla"
    Déjala unos días. Ocupa disco, pero es tu red de seguridad si aparece algo
    más que faltaba.

---

## Camino B — Restaurar encima

Solo cuando la base actual no vale para nada: está corrupta, vacía o sabes con
certeza que el respaldo es mejor que lo que hay.

### B1. Guardar lo que hay, aunque parezca inservible

```bash
mysqldump --single-transaction tienda | gzip > /tmp/tienda_antes_de_restaurar.sql.gz
ls -lh /tmp/tienda_antes_de_restaurar.sql.gz
```

!!! danger "No te saltes este paso"
    Es tu única marcha atrás. Cuesta treinta segundos.

### B2. Restaurar

```bash
./bin/backupctl restore all_databases_20260904_033010.zip tienda
```

Como la base existe, avisa y pide confirmación:

```
[AVISO] la base de datos 'tienda' YA EXISTE en el servidor y tiene 38 tablas.
[AVISO] Restaurar encima puede sobrescribir tablas con los datos del respaldo.
¿Continuar y restaurar sobre 'tienda'? [s/N]
```

### B3. Comprobar

```bash
mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='tienda';"
```

Compara con lo que decía `inspect` en el ensayo.

---

## Camino C — Solo una parte

Cuando lo roto es concreto:

```bash
# Alguien rompió una vista
./bin/backupctl restore '' tienda --segments views

# Se perdió un procedimiento almacenado
./bin/backupctl restore '' tienda --segments functions

# Solo la estructura, conservando los datos actuales
./bin/backupctl restore '' tienda --segments tables
```

!!! warning "`--segments tables` puede recrear tablas"
    Si el volcado trae `DROP TABLE IF EXISTS`, la tabla actual se sustituye por
    la vacía del respaldo. Para estructura pura sin perder datos, restaura al
    lado y compara con `SHOW CREATE TABLE`.

---

## Levantar el sitio otra vez

```bash
sudo v-unsuspend-web-domain admin midominio.com
# o
sudo systemctl start nginx
```

Comprueba la aplicación antes de dar por cerrado el incidente.

## Después

```bash
# Respaldo inmediato del estado ya corregido
./bin/backupctl backup
./bin/backupctl verify
```

Y en tu equipo, deja constancia:

```bash
backupctl -p MiVPS pull admin@mivps.example.com
${EDITOR:-nano} MiVPS/NOTAS.md      # qué pasó, qué se restauró, qué aprendiste
```

## Lista de comprobación

- [ ] Escritura parada durante la restauración
- [ ] Guardado lo que había antes (camino B)
- [ ] Restaurado y recuentos comprobados
- [ ] Aplicación funcionando
- [ ] Respaldo nuevo hecho y verificado
- [ ] Anotado en `NOTAS.md`

## Si algo va mal

| Error | Qué significa | Qué hacer |
|---|---|---|
| `'x' no está en este respaldo` | Nombre equivocado | `list --databases <zip>` |
| `Access denied ... CREATE` | Sin privilegios | `GRANT CREATE, DROP ON *.* TO ...` |
| `Table doesn't exist` en vistas | La vista depende de algo que no está | Restaura primero `tables` |
| `Duplicate entry` | Ya existían esas filas | Restaura al lado y compara |
| Restauración a medias | Un segmento falló | Mira qué segmento y repítelo con `--segments` |

Más detalle en [Cuando algo falla](../guias/diagnostico.md).
