# Portabilidad del volcado

Un volcado de `mysqldump` sin tratar **suele fallar al restaurarse en otra
máquina**. Estas son las cuatro razones y lo que hace `backupctl` con cada una.

## 1. DEFINER — el gran obstáculo

MySQL añade a cada vista, rutina y trigger la cláusula que dice quién los creó:

```sql
CREATE DEFINER=`backupctl`@`localhost` PROCEDURE `p_calcular`() ...
```

Al restaurar en un servidor donde `backupctl@localhost` **no existe**:

```
ERROR 1449 (HY000): The user specified as a definer ('backupctl'@'localhost') does not exist
```

`backupctl` elimina la cláusula en los segmentos de estructura:

```sql
CREATE PROCEDURE `p_calcular`() ...
```

Se cubren las siete formas que emite `mysqldump`:

| Forma | Dónde aparece |
|---|---|
| ``DEFINER=`u`@`h` `` | Procedimientos, funciones, triggers |
| `DEFINER='u'@'h'` | Vistas con comilla simple |
| `` DEFINER=`u`@`%` `` | Comodín de host |
| `` DEFINER=`u`@`10.0.0.5` `` | Host por IP |
| `/*!50013 DEFINER=... */` | Comentario versionado en vistas |
| `/*!50017 DEFINER=... */` | Comentario versionado en rutinas |
| `SQL SECURITY DEFINER` | Modo de ejecución |

## 2. SQL SECURITY DEFINER

Quitar el `DEFINER` pero dejar `SQL SECURITY DEFINER` deja el objeto en un
estado ambiguo. `backupctl` lo convierte:

```sql
-- antes
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
-- después
/*!50013 SQL SECURITY INVOKER */
```

Con `INVOKER`, la vista se ejecuta con los permisos de quien la consulta. Es lo
correcto para un volcado que va a otra máquina.

!!! warning "Un fallo real corregido"
    La versión anterior de estos scripts eliminaba el `DEFINER` pero dejaba
    `/*!50013  SQL SECURITY DEFINER */` intacto en los `views.sql`. Se comprobó
    sobre respaldos ya generados.

## 3. Codificación de caracteres

Si el cliente negocia `latin1` con un servidor `utf8mb4`, los emojis y
caracteres multibyte **se corrompen dentro del volcado**, sin ningún error. El
daño es permanente: el archivo ya contiene los datos mal.

```bash
--default-character-set=utf8mb4     # cliente y volcado
--hex-blob                          # binarios en hexadecimal
```

Y el `CREATE DATABASE` conserva el charset y collation exactos del origen:

```sql
CREATE DATABASE IF NOT EXISTS `tienda`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

## 4. Estado de replicación

En MySQL 8, `mysqldump` puede incluir:

```sql
SET @@GLOBAL.GTID_PURGED='...';
```

Que en un servidor distinto falla o deja la replicación en un estado incorrecto.
`backupctl` añade `--set-gtid-purged=OFF` **si el cliente lo soporta** (se
detecta en tiempo de ejecución, no se asume).

Igual con `--column-statistics=0`, necesario cuando un cliente MySQL 8 habla con
un servidor MariaDB.

## Lo que sigue sin ser portable

!!! danger "Lo que un volcado de datos no lleva"
    - **Usuarios y privilegios de MySQL.** Están en la base `mysql`, que se
      excluye a propósito. Hay que recrearlos en el destino.
    - **Configuración del servidor** (`my.cnf`, `sql_mode`, zonas horarias).
      Un `sql_mode` distinto puede rechazar datos que el origen aceptaba.
    - **Archivos de la aplicación.** Esto respalda bases de datos, no `/home`.
      De eso se encarga Restic/HestiaCP.

## Comprobarlo

La forma de saber que un volcado es portable es restaurarlo:

```bash
backupctl verify --restore-test tienda --with-data
```

Y en una migración real, `backupctl migrate` compara los recuentos de tablas
entre origen y destino automáticamente.
