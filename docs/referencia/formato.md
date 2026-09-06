# Formato del respaldo

## Estructura del zip

```
all_databases_20260905_033012.zip
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

El nombre lleva la marca de tiempo del inicio: `all_databases_AAAAMMDD_HHMMSS.zip`.

!!! info "Por qué gzip dentro de zip"
    Cada `.sql` se comprime con `gzip -9` y el zip se crea con `-0` (sin
    recomprimir). El contenido ya viene comprimido: volver a comprimirlo
    gastaría CPU sin reducir el tamaño.

    Efecto secundario útil: cada `.gz` se puede extraer y leer por separado sin
    descomprimir el resto.

## Los seis segmentos

| Archivo | Opciones de `mysqldump` | Se limpia el DEFINER |
|---|---|---|
| `database.sql` | *(construido a mano)* | n/a |
| `tables.sql` | `--no-data --skip-triggers` | Sí |
| `data.sql` | `--no-create-info --skip-triggers` | **No** |
| `views.sql` | `--no-data --skip-triggers <vista>` | Sí |
| `functions.sql` | `--no-create-info --no-data --routines --skip-triggers` | Sí |
| `others.sql` | `--no-create-info --no-data --triggers --events` | Sí |

!!! note "Por qué `data.sql` no pasa por el filtro"
    Dos razones: una fila que contuviera el texto `DEFINER=` quedaría alterada,
    y es con diferencia el archivo más grande — pasarlo por `sed` alargaría el
    respaldo sin ninguna ganancia, porque los datos no llevan `DEFINER`.

Cada archivo empieza con su propia cabecera `USE`, así que es **autónomo**:

```sql
USE `tienda`;
```

```bash
zcat tables.sql.gz | mysql      # funciona sin más
```

## Opciones comunes de mysqldump

```
--single-transaction        instantánea coherente sin bloquear (solo InnoDB)
--force                     continuar aunque falle un objeto
--no-tablespaces            omitir TABLESPACE (exigiría privilegio PROCESS)
--hex-blob                  binarios en hexadecimal
--default-character-set=utf8mb4
```

Y, si el cliente las soporta (se detecta en tiempo de ejecución):

```
--column-statistics=0       cliente MySQL 8 contra servidor MariaDB
--set-gtid-purged=OFF       sin estado de replicación
```

## El manifiesto

```
# backupctl MANIFEST
formato_version: 1
generado: 2026-09-05 03:30:12 -05
perfil: MiVPS
servidor: servidor.example
usuario_mysql: backupctl
mysql_version: 10.11.6-MariaDB
charset: utf8mb4
backupctl_version: 2.0.0
incluye_datos: si
definers_eliminados: si
bases_de_datos: 76
bases_con_fallos: 0

# inventario: base_de_datos<TAB>tablas<TAB>vistas<TAB>inserts<TAB>bytes_en_origen
tienda	41	6	160	52428800
blog	22	0	31	10485760

# sumas SHA-256 de cada archivo comprimido
a1b2c3...  ./tienda/data.sql.gz
d4e5f6...  ./tienda/tables.sql.gz
```

Sirve para tres cosas:

1. **Inspeccionar sin extraer**: `backupctl inspect` lee solo este archivo.
2. **Detectar corrupción archivo a archivo**: las sumas se comprueban en
   `verify`. Un zip puede tener el CRC correcto y aun así contener datos
   alterados si se reempaquetó.
3. **Saber qué esperabas**: si el respaldo se generó con fallos, queda escrito
   dentro del propio respaldo (`bases_con_fallos`), y `verify` lo detecta aunque
   no tengas el log.

## Leerlo sin backupctl

```bash
# Qué contiene
unzip -l all_databases_20260905_033012.zip | head

# El manifiesto, sin extraer nada
unzip -p all_databases_20260905_033012.zip MANIFEST.txt

# Una sola base de datos
unzip all_databases_20260905_033012.zip 'tienda/*'

# Un archivo concreto por pantalla
unzip -p all_databases_20260905_033012.zip tienda/tables.sql.gz | gunzip | less

# Verificar las sumas a mano
unzip -qq all_databases_20260905_033012.zip -d /tmp/r && cd /tmp/r
grep -E '^[0-9a-f]{64}  \./' MANIFEST.txt | sha256sum -c --quiet
```

!!! success "Sin dependencia del tooling"
    El formato es `zip` + `gzip` + SQL plano. Si `backupctl` desapareciera,
    cualquiera con `unzip` y `mysql` puede restaurar. Eso es deliberado: un
    formato propietario en un sistema de respaldo es un riesgo, no una función.

## Tamaños de referencia

Con 76 bases de datos de tamaño medio:

| Concepto | Tamaño |
|---|---|
| Datos en MySQL | ~4 GB |
| Volcado sin comprimir (temporal) | ~5 GB |
| Zip final | ~38 MB |
| 14 días de retención | ~530 MB |
