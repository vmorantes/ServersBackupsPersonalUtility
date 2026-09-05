# Guías paso a paso

Seis recorridos completos. Cada operación viene en dos versiones: **ensayo**
(no toca nada) y **en serio**.

!!! tip "Haz siempre el ensayo primero"
    Los ensayos no escriben, no borran y no modifican nada. Sirven para ver
    exactamente qué pasaría y detectar problemas de configuración, permisos o
    conectividad **antes** de que importen.

<div class="grid cards" markdown>

-   :material-download: **Instalar**

    ---

    Poner el ecosistema en un VPS con HestiaCP.

    [:octicons-arrow-right-24: 1. Ensayo](instalar-ensayo.md)
    · [2. En serio](instalar.md)

-   :material-backup-restore: **Restaurar**

    ---

    Recuperar una base de datos desde un respaldo.

    [:octicons-arrow-right-24: 3. Ensayo](restaurar-ensayo.md)
    · [4. En serio](restaurar.md)

-   :material-server-network: **Migrar**

    ---

    Llevar las bases de datos a otro servidor.

    [:octicons-arrow-right-24: 5. Ensayo](migrar-ensayo.md)
    · [6. En serio](migrar.md)

</div>

## Qué escribe cada orden

La referencia rápida para saber qué es seguro ejecutar sin pensarlo.

| Orden | ¿Escribe algo? | Qué toca |
|---|---|---|
| `profiles` | No | — |
| `config --show` `--check` `--path` | No | — |
| `status` | No | — |
| `doctor` | No | Solo lee. No crea directorios |
| `list` `inspect` | No | Solo lee los `.zip` |
| `logs --list` `--errors` `--full` | No | Solo lee |
| `cron --show` | No | Solo lee el crontab |
| `restic-list` | No | Solo lee |
| `verify` | Temporal | Extrae a `/tmp` y lo borra al salir |
| `backup --dry-run` | No | — |
| `restore --dry-run` | No | — |
| `retention --dry-run` | No | — |
| `restic --dry-run` | No | — |
| `deploy --dry-run` | No | Se conecta por SSH y lista |
| `pull --dry-run` | No | Se conecta por SSH y compara |
| `migrate --dry-run` | No | Se conecta por SSH y comprueba |
| `verify --restore-test` | **Sí** | Crea una BD desechable y **la borra** al terminar |
| `backup` | **Sí** | Crea un `.zip`, un log y aplica retención |
| `retention` | **Sí** | **Borra** respaldos y logs antiguos |
| `restore` | **Sí** | **Escribe en la base de datos** |
| `restic` | **Sí** | Crea un `.txt` (requiere root) |
| `deploy` | **Sí** | Escribe en el servidor remoto |
| `pull` | **Sí** | Escribe `ESTADO.md`; puede sobrescribir `env.sh` si lo aceptas |
| `migrate` | **Sí** | **Escribe en las bases de datos del destino** |
| `cron --install` `--remove` | **Sí** | Modifica la programación |
| `notify-test` | Externo | Envía un aviso de prueba |

!!! warning "Las tres órdenes que hay que mirar dos veces"
    `restore`, `migrate` y `retention`. Las dos primeras escriben en bases de
    datos; la tercera borra respaldos. Las tres tienen `--dry-run`.

## Nota sobre HestiaCP

Estas guías dan por hecho un VPS con HestiaCP. Hay dos cosas que lo hacen
distinto de un servidor normal:

**El cron lo gestiona HestiaCP.** El crontab del sistema es un archivo
*generado* a partir de `/usr/local/hestia/data/users/<user>/cron.conf`. Una
línea puesta con `crontab -e` no aparece en el panel y **desaparece** en el
siguiente `v-rebuild-cron-jobs`. `backupctl cron --install` lo detecta y usa
`v-add-cron-job`.

**Restic es la copia externa.** `backupctl` guarda los respaldos en el disco del
servidor; Restic/HestiaCP se los lleva fuera. Son capas distintas y ambas hacen
falta. Ver [Claves Restic](../operacion/restic.md).
