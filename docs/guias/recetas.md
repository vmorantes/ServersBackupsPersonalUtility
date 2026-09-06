# Recetas

Tareas del día a día, resueltas. **Esta es la página para cuando se te olvida
algo.**

## Repositorio ↔ servidor

```bash
backupctl -p MiVPS pull root@servidor      # DESCARGAR el estado real
backupctl -p MiVPS config --edit            # ajustar la configuración
backupctl -p MiVPS deploy root@servidor    # SUBIR los cambios
backupctl -p MiVPS pull root@servidor      # dejar constancia
```

```bash
# Recoger el estado de todos los servidores y ver qué se movió
for p in $(backupctl profiles | tail -n +3 | awk '{print $1}'); do
    backupctl -p "$p" pull
done
git diff --stat
```

## Comprobaciones rápidas

```bash
backupctl status                    # ¿estoy protegido?
backupctl doctor                    # ¿qué está mal?
backupctl list                      # qué respaldos tengo
backupctl logs --errors             # qué falló la última vez
backupctl inspect                   # qué hay en el último respaldo
```

## Antes de tocar producción

```bash
# Respaldo puntual de la base que vas a modificar
backupctl backup --only tienda

# Y confirmar que sirve
backupctl verify --restore-test tienda --with-data
```

## Recuperar algo borrado por error

No restaures encima. Restaura **al lado**:

```bash
backupctl restore '' tienda --into tienda_ayer
```

```sql
-- Comparar
SELECT COUNT(*) FROM tienda.pedidos;
SELECT COUNT(*) FROM tienda_ayer.pedidos;

-- Recuperar solo las filas que faltan
INSERT INTO tienda.pedidos
SELECT * FROM tienda_ayer.pedidos
WHERE id NOT IN (SELECT id FROM tienda.pedidos);

-- Recuperar una tabla entera
DROP TABLE tienda.pedidos;
CREATE TABLE tienda.pedidos LIKE tienda_ayer.pedidos;
INSERT INTO tienda.pedidos SELECT * FROM tienda_ayer.pedidos;
```

```sql
-- Limpiar cuando acabes
DROP DATABASE tienda_ayer;
```

## Recuperar de un respaldo concreto

```bash
backupctl list
backupctl restore all_databases_20260901_033010.zip tienda --into tienda_dia1
```

## Alguien rompió una vista

```bash
backupctl restore '' tienda --segments views
```

Sin tocar tablas ni datos.

## Clonar una base de datos

```bash
backupctl backup --only tienda
backupctl restore '' tienda --into tienda_desarrollo
```

## Comparar el esquema de dos días

```bash
mkdir -p /tmp/cmp && cd /tmp/cmp
unzip -p ~/scripts/output/mysql_backups/all_databases_20260901_033010.zip tienda/tables.sql.gz | gunzip > ayer.sql
unzip -p ~/scripts/output/mysql_backups/all_databases_20260905_033012.zip tienda/tables.sql.gz | gunzip > hoy.sql
diff -u ayer.sql hoy.sql
```

## Extraer una sola base de datos de un respaldo

```bash
cd /tmp
unzip ~/scripts/output/mysql_backups/all_databases_20260905_033012.zip 'tienda/*'
```

## Ver una tabla sin restaurar nada

```bash
unzip -p all_databases_XXXX.zip tienda/tables.sql.gz | gunzip | grep -A30 'CREATE TABLE `pedidos`'
```

## Liberar espacio

```bash
backupctl list                      # cuánto ocupa
backupctl retention --dry-run       # qué se borraría
backupctl retention                 # borrarlo
```

Y para bajar la retención de forma permanente:

```bash
backupctl config --edit             # BACKUP_RETENTION_DAYS="7"
```

## Migrar a un servidor nuevo

```bash
backupctl deploy root@nuevo.example
ssh root@nuevo.example '/home/admin/scripts/bin/backupctl doctor'
backupctl migrate --to root@nuevo.example --dry-run
backupctl migrate --to root@nuevo.example --fresh
```

## Migrar solo unas bases

```bash
backupctl migrate --to root@nuevo.example --databases tienda,blog --fresh
```

## Migrar sin pisar las que ya existen

```bash
backupctl migrate --to root@nuevo.example --prefix viejo_ --fresh
```

## Actualizar backupctl en todos los servidores

```bash
for p in $(backupctl profiles | tail -n +3 | awk '{print $1}'); do
    backupctl -p "$p" deploy
done
```

## Revisar todos los servidores de golpe

```bash
for p in $(backupctl profiles | tail -n +3 | awk '{print $1}'); do
    printf '=== %s ===\n' "$p"
    backupctl -p "$p" status || echo "  ⚠ requiere atención"
done
```

## Comprobar que los avisos funcionan

```bash
backupctl notify-test
```

## Radiografía del esquema, sin datos

```bash
backupctl backup --no-data
```

Rápido y ligero. Útil para llevarse la estructura a un entorno de desarrollo.

## Cambiar la hora del respaldo

```bash
backupctl cron --install --hour 2 --minute 15
```

Es idempotente: sustituye el bloque del perfil, no lo duplica.

## Ver el crontab que propone, sin instalarlo

```bash
backupctl cron --show
```

## Seguir un respaldo en vivo desde otra sesión

```bash
backupctl logs --follow
```

## Verificar sin backupctl

```bash
unzip -t all_databases_XXXX.zip                                  # CRC
unzip -qq all_databases_XXXX.zip -d /tmp/r && cd /tmp/r
grep -E '^[0-9a-f]{64}  \./' MANIFEST.txt | sha256sum -c --quiet  # sumas
```

## Restaurar sin backupctl

```bash
cd /tmp && unzip all_databases_XXXX.zip && cd tienda
zcat database.sql.gz  | mysql
zcat tables.sql.gz    | mysql
zcat data.sql.gz      | mysql
zcat functions.sql.gz | mysql
zcat views.sql.gz     | mysql
zcat others.sql.gz    | mysql
```

## Dar de alta un servidor nuevo en el repositorio

```bash
mkdir -p servers/NuevoServidor
cp config/env.sh.example servers/NuevoServidor/env.sh
touch servers/NuevoServidor/Instrucciones.md
${EDITOR:-nano} servers/NuevoServidor/env.sh
backupctl profiles                  # debería aparecer
backupctl -p NuevoServidor doctor
```

## Consultas de MySQL útiles

```sql
-- Tamaño de cada base, de mayor a menor
SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024) AS mb
FROM information_schema.tables GROUP BY table_schema ORDER BY mb DESC;

-- Tablas que no son InnoDB
SELECT table_schema, table_name, engine FROM information_schema.tables
WHERE engine NOT IN ('InnoDB') AND engine IS NOT NULL
  AND table_schema NOT IN ('information_schema','performance_schema','mysql','sys');

-- Privilegios del usuario de respaldo
SHOW GRANTS FOR 'backupctl'@'localhost';

-- Vistas con DEFINER que no existe (fallarían al migrar)
SELECT table_schema, table_name, definer FROM information_schema.views
WHERE SUBSTRING_INDEX(definer,'@',1) NOT IN (SELECT user FROM mysql.user);
```

## Comprobación externa de que sigue vivo

```bash
backupctl status >/dev/null || curl -fsS https://hc-ping.com/xxxx/fail
```
