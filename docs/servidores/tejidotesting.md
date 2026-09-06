# TejidoTesting

Servidor HestiaCP de TejidoTesting.

| Dato | Valor |
|---|---|
| Perfil | `TejidoTesting` |
| Configuración | `TejidoTesting/env.sh` |
| Usuario del sistema | `admin` |
| Ruta en el servidor | `/home/admin/scripts` |
| Bases de datos | ~76 |
| Tamaño del respaldo | ~38 MB |

```bash
backupctl -p TejidoTesting status
```

!!! note "En el servidor no hace falta `-p`"
    Allí el `env.sh` está junto al tooling, el perfil se llama `local` y es el
    único:

    ```bash
    ssh root@servidor
    /home/admin/scripts/bin/backupctl status
    ```

## Puesta en marcha

```bash
# Desde este repositorio
backupctl -p TejidoTesting deploy root@servidor

# En el servidor
ssh root@servidor
cd /home/admin/scripts
./bin/backupctl doctor
./bin/backupctl backup
./bin/backupctl verify --restore-test encausa --with-data
./bin/backupctl cron --install
```

## Programación

```cron
30 3 * * * /home/admin/scripts/bin/backupctl backup || echo "Respaldo MySQL FALLIDO"
0  5 * * 0 /home/admin/scripts/bin/backupctl verify --quick
0  9 * * 1 /home/admin/scripts/bin/backupctl status || true
```

## Claves de Restic

```bash
sudo /home/admin/scripts/bin/backupctl restic
```

A mano, cuando cambien los repositorios. Deja el resultado en
`output/HestiaCP/Restic_Configs_AAAAMMDD.txt`.

## Migración desde los scripts antiguos

Este servidor venía de tres scripts sueltos. Equivalencias:

| Antes | Ahora |
|---|---|
| `RunBackupDB.sh` | `backupctl backup` |
| `BackupAllMySQLServer.sh` | `backupctl backup` |
| `HestiaCPResticUserPassBackup.sh` | `sudo backupctl restic` |
| *(no existía)* | `backupctl verify` |
| *(no existía)* | `backupctl restore` |
| *(no existía)* | `backupctl migrate` |
| *(no existía)* | `backupctl doctor` / `status` |

!!! warning "Hay que actualizar el crontab"
    La línea antigua llevaba un `$(date +%Y...)` con **`%` sin escapar**, que
    cron convierte en salto de línea y parte la orden. Ver
    [El fallo del porcentaje](../operacion/automatizacion.md#el-fallo-del-porcentaje).

    ```bash
    backupctl cron --install     # instala la versión correcta
    ```

## Particularidades

??? info "Nombres de base de datos con guiones"
    Varias bases usan guiones (`codrid-website`, `geo-project`,
    `testing-admin_landing-kata`). Todos los identificadores se escapan con
    acentos graves y los literales SQL con `bc_sql_quote`, así que no dan
    problema.

??? info "Bases de datos vacías"
    `admin_ficicaweb` aparece con 0 tablas en las verificaciones. Puede ser
    legítimo o el resto de una base que se vació. Compruébalo:

    ```bash
    mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='admin_ficicaweb';"
    ```

    Si ya no se usa, conviene excluirla en `EXCLUDE_DBS` para que deje de
    generar avisos.

## Comprobaciones periódicas

| Cada | Qué |
|---|---|
| Semana | `backupctl -p TejidoTesting status` |
| Mes | `backupctl verify --restore-test <bd> --with-data` en el servidor |
| Trimestre | Ensayo de recuperación completa desde Restic |
