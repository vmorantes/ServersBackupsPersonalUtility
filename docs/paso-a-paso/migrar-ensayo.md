# 5. Migrar a otro servidor — ensayo

**Nada de esta guía escribe en el servidor destino.** Sirve para comprobar que
la migración es posible y qué exactamente se movería.

Escenario: tienes un VPS con HestiaCP (**origen**) y quieres llevar sus bases de
datos a otro VPS con HestiaCP (**destino**).

---

## Paso 1 — Preparar el destino

La migración necesita `backupctl` funcionando **en el destino**. Si no lo tiene,
haz allí primero la guía [1](instalar-ensayo.md) y [2](instalar.md).

```bash
# Perfil del destino en tu repositorio
mkdir VPSNuevo
cp config/env.sh.example VPSNuevo/env.sh
${EDITOR:-nano} VPSNuevo/env.sh
```

```bash
backupctl -p VPSNuevo deploy admin@nuevo.example --dry-run
```

## Paso 2 — Comprobar el acceso entre las tres máquinas

La orden `migrate` se lanza **desde el origen** y habla con el destino por SSH.

```bash
ssh admin@origen.example
cd /home/admin/scripts

# ¿Llega el origen al destino?
ssh admin@nuevo.example 'hostname'
```

Si pide contraseña:

```bash
ssh-keygen -t ed25519 -C "migracion"      # si el origen no tiene clave
ssh-copy-id admin@nuevo.example
```

## Paso 3 — Comprobar que el destino está listo

```bash
ssh admin@nuevo.example '/home/admin/scripts/bin/backupctl doctor'
```

Debe salir **sin fallos**. `migrate` se niega a empezar si el destino no tiene
un `backupctl` operativo con configuración válida.

## Paso 4 — Ensayar la migración

Desde el **origen**:

```bash
./bin/backupctl migrate --to admin@nuevo.example --dry-run
```

```
== Migración hacia admin@nuevo.example ==
[INFO ] Comprobando el destino...
[  OK ] backupctl encontrado en el destino.
[  OK ] la configuración del destino es válida.
[INFO ] Usando el respaldo más reciente: all_databases_20260905_033012.zip (0 días)
[INFO ] Bases de datos a migrar: 76
        - tienda
        - blog
        ...
[  OK ] Simulación (--dry-run): se habría transferido all_databases_...zip (38.3M)
        y restaurado 76 bases de datos en admin@nuevo.example.
```

No transfiere ni escribe nada.

## Paso 5 — Ensayar variantes

```bash
# Solo unas bases concretas
./bin/backupctl migrate --to admin@nuevo.example --databases tienda,blog --dry-run

# Con prefijo, si el destino ya tiene bases con esos nombres
./bin/backupctl migrate --to admin@nuevo.example --prefix viejo_ --dry-run

# Desde un respaldo concreto en vez del más reciente
./bin/backupctl migrate --to admin@nuevo.example \
    --from all_databases_20260901_033010.zip --dry-run
```

## Paso 6 — Anotar el "antes" de ambos lados

```bash
# En el ORIGEN
mysql -e "SELECT table_schema, COUNT(*) tablas
          FROM information_schema.tables
          WHERE table_schema NOT IN ('information_schema','performance_schema','mysql','sys')
          GROUP BY table_schema ORDER BY table_schema;" > /tmp/origen.txt

# Lo mismo en el DESTINO
ssh admin@nuevo.example "mysql -e \"SELECT table_schema, COUNT(*) tablas
          FROM information_schema.tables
          WHERE table_schema NOT IN ('information_schema','performance_schema','mysql','sys')
          GROUP BY table_schema ORDER BY table_schema;\"" > /tmp/destino.txt

diff /tmp/origen.txt /tmp/destino.txt
```

`migrate` compara recuentos automáticamente al terminar, pero tener el "antes"
por escrito ayuda cuando algo no cuadra.

## Paso 7 — Comprobar espacio en el destino

```bash
ssh admin@nuevo.example 'df -h /home/admin'
```

Hace falta sitio para el `.zip` transferido **más** el volcado descomprimido
durante la restauración.

## Lo que la migración NO lleva

!!! danger "Apúntalo antes de migrar"
    | Qué falta | Cómo resolverlo |
    |---|---|
    | **Usuarios y privilegios de MySQL** | Hay que recrearlos. Ver abajo |
    | **Archivos web** (`/home/admin/web/`) | HestiaCP: `v-backup-user` / Restic |
    | **Dominios, DNS, correo, SSL** | HestiaCP: `v-backup-user` |
    | **Configuración de MySQL** (`my.cnf`, `sql_mode`) | A mano |

Para listar los usuarios de MySQL que habrá que recrear:

```bash
mysql -e "SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';')
          FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session');"
```

!!! tip "En HestiaCP, migra también el usuario del panel"
    `backupctl migrate` mueve **bases de datos**. Para llevarte los dominios,
    correo y archivos, usa el respaldo propio de HestiaCP:

    ```bash
    sudo v-backup-user admin
    # deja el .tar en /backup/, se restaura con v-restore-user en el destino
    ```

    Los dos son complementarios: HestiaCP para la cuenta completa, `backupctl`
    para tener las bases de datos verificadas y portables.

## Lista de comprobación

- [ ] `backupctl doctor` sin fallos en el destino
- [ ] El origen entra por SSH al destino sin contraseña
- [ ] `migrate --dry-run` lista las bases correctas
- [ ] Hay espacio de sobra en el destino
- [ ] Tengo apuntados los recuentos de tablas del origen
- [ ] Tengo la lista de usuarios de MySQL que recrear
- [ ] Sé qué hago con dominios, correo y archivos (`v-backup-user`)

---

Cuando todo esté marcado: **[6. Migrar en serio](migrar.md)**.
