# TejidoTesting

Servidor HestiaCP de TejidoTesting. Este directorio contiene únicamente la
**configuración** de este servidor (`env.sh`) y sus salidas.

El código vive en `bin/` y `lib/` en la raíz del repositorio, y es idéntico para
todos los servidores. Aquí no hay ninguna copia que mantener.

## Documentación

La documentación completa —instalación, operación, migración, referencia,
recetas y recuperación ante desastre— está en el sitio MkDocs:

```bash
mkdocs serve        # http://127.0.0.1:8000
```

La página específica de este servidor es **Servidores → TejidoTesting**, o
directamente [`docs/servidores/tejidotesting.md`](../docs/servidores/tejidotesting.md).

## Lo mínimo

```bash
# Desde el repositorio
backupctl -p TejidoTesting status
backupctl -p TejidoTesting doctor

# En el servidor (allí el perfil se llama 'local' y no hace falta -p)
ssh admin@servidor
/home/admin/scripts/bin/backupctl status
```

## Puesta al día desde los scripts antiguos

Este servidor venía de tres scripts sueltos. Equivalencias:

| Antes | Ahora |
|---|---|
| `RunBackupDB.sh` | `backupctl backup` |
| `BackupAllMySQLServer.sh` | `backupctl backup` |
| `HestiaCPResticUserPassBackup.sh` | `sudo backupctl restic` |

```bash
backupctl -p TejidoTesting deploy admin@servidor    # instalar la versión nueva
ssh admin@servidor '/home/admin/scripts/bin/backupctl doctor'
ssh admin@servidor '/home/admin/scripts/bin/backupctl cron --install'
```

El `cron --install` es necesario: la línea antigua llevaba un `%` sin escapar que
cron convierte en salto de línea y parte la orden.
