# Cuando algo falla

## Empieza siempre por aquí

```bash
backupctl doctor
```

Comprueba todo de una vez y dice qué está mal **y qué hacer**. La mayoría de los
problemas de esta página los detecta él solo.

```bash
backupctl logs --errors      # qué falló la última vez
backupctl status             # ¿estoy protegido?
```

---

## No se puede conectar a MySQL

```
[ERROR] no se pudo conectar a MySQL como 'admin_general':
        ERROR 1045 (28000): Access denied for user 'admin_general'@'localhost'
```

**Causas y comprobación:**

```bash
backupctl config --show-secrets      # ¿la contraseña es la que crees?
mysql -u admin_general -p -e "SELECT 1"    # ¿funciona a mano?
```

Si funciona a mano pero no desde `backupctl`, revisa `MYSQL_HOST`: vacío
significa socket local, y un `localhost` explícito puede resolverse por TCP.

```
ERROR 1698 (28000): Access denied for user 'x'@'localhost'
```

Ese código es distinto: el usuario existe pero usa autenticación por *socket*
(`unix_socket`), no por contraseña. Hay que ejecutar como ese usuario del
sistema o cambiarle el método de autenticación.

---

## El respaldo dice que hay bases fallidas

```
[ERROR] Bases de datos CON FALLOS (2):
        - tienda
        - facturacion
```

**Esto es el sistema funcionando bien**: ha detectado un volcado incompleto en
lugar de dártelo por bueno.

```bash
backupctl logs --errors
```

Busca las líneas `mysqldump:`, que llevan el error real:

| Mensaje | Causa | Solución |
|---|---|---|
| `Access denied ... SHOW VIEW` | Falta privilegio | `GRANT SHOW VIEW ON *.* TO ...` |
| `Table ... doesn't exist` | Vista huérfana apuntando a una tabla borrada | Arreglar o borrar la vista |
| `Table ... is marked as crashed` | Tabla MyISAM corrupta | `REPAIR TABLE ...` |
| `Got error: 1356` | Vista que referencia objetos inexistentes | Revisar la definición |

---

## Espacio insuficiente

```
[ERROR] espacio insuficiente: 512MB libres, se estiman 8601MB necesarios.
```

```bash
df -h /home/admin/scripts/output
backupctl list                       # cuánto ocupan los respaldos
backupctl retention --dry-run        # qué se podría borrar
backupctl retention                  # borrarlo
```

Si sigue sin caber, baja `BACKUP_RETENTION_DAYS` o mueve `BACKUP_OUTPUT_DIR` a
otro disco.

??? question "¿Y si el cálculo se pasa de conservador?"
    Se estima `tamaño_datos × DISK_SAFETY_FACTOR` (2 por defecto). Con datos muy
    comprimibles puede sobrar margen. Bájalo con cuidado:

    ```bash
    export DISK_SAFETY_FACTOR="1"
    ```

    Quedarse sin disco a mitad del volcado deja un respaldo truncado y puede
    tumbar el servidor. El margen está para eso.

---

## Ya hay una operación en curso

```
[ERROR] ya hay una operación 'backup' en curso (bloqueo: .../.backupctl.backup.lock)
```

Es la protección contra ejecuciones solapadas.

```bash
ps aux | grep backupctl        # ¿hay uno de verdad?
```

Si no hay ninguno, el bloqueo es de un proceso muerto. `flock` lo libera solo al
morir el proceso, así que esto es raro; si pasa, el archivo se puede borrar:

```bash
rm /home/admin/scripts/output/.backupctl.backup.lock
```

---

## El cron no se ejecuta

```bash
crontab -l                            # ¿está la línea?
grep CRON /var/log/syslog | tail -20  # ¿la ejecuta el sistema?
backupctl list                        # ¿hay un zip reciente?
```

**Causas frecuentes:**

1. **Un `%` sin escapar.** Cron lo convierte en salto de línea y parte la orden.
   `backupctl doctor` lo detecta. Ver
   [El fallo del porcentaje](../operacion/automatizacion.md#el-fallo-del-porcentaje).
2. **PATH mínimo.** Reprodúcelo:
   ```bash
   env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c '/home/admin/scripts/bin/backupctl status'
   ```
3. **Ruta relativa.** La línea de cron debe llevar la ruta absoluta.
4. **El usuario equivocado.** `crontab -l -u admin`.

---

## Verificación fallida

=== "Zip corrupto"

    ```
    [ERROR] el zip está corrupto o incompleto. No se puede seguir.
    ```

    Ese respaldo no sirve. Comprueba el anterior:

    ```bash
    backupctl list
    backupctl verify all_databases_ANTERIOR.zip
    ```

    Si varios seguidos están corruptos, sospecha del disco: `dmesg | grep -i error`.

=== "Sumas que no coinciden"

    ```
    [ERROR] hay archivos cuya suma no coincide con el manifiesto:
            ./blog/data.sql.gz: La suma no coincide
    ```

    El archivo cambió después de generarse el respaldo. O el zip se reempaquetó,
    o hay corrupción en disco. El contenido de ese `.gz` no es de fiar.

=== "Base de datos INCOMPLETA"

    ```
    [ERROR] tienda: falta data.sql.gz
    ```

    El volcado se interrumpió. Mira el log de aquella ejecución y vuelve a
    respaldar esa base:

    ```bash
    backupctl backup --only tienda
    ```

=== "Sin datos"

    ```
    [AVISO] 3 bases de datos con estructura pero sin ningún INSERT
    ```

    Puede ser legítimo (bases realmente vacías) o un volcado fallido.
    Compruébalo:

    ```bash
    mysql -e "SELECT COUNT(*) FROM tienda.pedidos;"
    ```

---

## La prueba de restauración falla

```
[ERROR] no se pudo crear la base de datos temporal (¿falta el privilegio CREATE?)
```

`--restore-test` necesita `CREATE` y `DROP`. Si tu usuario de respaldo es de
solo lectura —lo cual es buena práctica—, usa otro perfil con más privilegios
solo para la prueba.

```
[ERROR]   views NO se pudo restaurar:
          ERROR 1146: Table 'verifybk_xxx.otra_cosa' doesn't exist
```

Una vista depende de un objeto que no está en el respaldo. Suele indicar una
vista que referencia **otra base de datos**. Es información útil: esa vista
tampoco se restauraría en un servidor nuevo.

---

## La TUI se ve mal

```bash
backupctl --plain      # menú de texto, sin whiptail
backupctl --no-color   # sin códigos de color
```

Si los acentos salen mal, revisa el locale:

```bash
locale
export LANG=es_ES.UTF-8
```

---

## Sigo sin saber qué pasa

```bash
backupctl --debug backup --dry-run
```

Muestra las opciones de `mysqldump` detectadas, el perfil resuelto, la ruta del
fichero de credenciales y cada objeto procesado.

```bash
bash -x bin/backupctl status 2>&1 | less    # traza completa
bash -n lib/*.sh bin/backupctl              # sintaxis de todo
```
