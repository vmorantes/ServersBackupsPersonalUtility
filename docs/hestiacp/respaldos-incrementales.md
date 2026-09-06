# Respaldos incrementales con Restic

HestiaCP puede sustituir sus respaldos tradicionales en `.tar` —que consumen
mucho espacio y CPU— por respaldos incrementales con **Restic**, con
deduplicación y cifrado.

Esta página unifica la configuración completa: disco local, NAS y **S3
(Mega S4)**, que es lo que usa TejidoTesting.

!!! info "Esto es de HestiaCP, no de backupctl"
    Restic respalda **la cuenta entera**: archivos web, correo, DNS, configuración.
    `backupctl` respalda **las bases de datos** con verificación y formato
    portable. Son capas complementarias, y las dos hacen falta.

    ```
    MySQL ──backupctl──► output/mysql_backups/ ─┐
    Cuenta ─────────────────────────────────────┴─Restic──► repositorio remoto
    ```

---

## 1. Elegir dónde se guarda

=== "S3 / Mega S4 (fuera del servidor)"

    La única que protege ante la pérdida del VPS entero. Es lo que usa
    TejidoTesting.

    **Ventaja:** los datos salen de la máquina.
    **A tener en cuenta:** depende de la red y del proveedor.

=== "Disco externo o NAS"

    Un segundo disco físico montado (por ejemplo en `/mnt/backup_incremental`),
    un NAS o un NFS.

    **Ventaja:** rápido y protege ante el fallo del disco principal.
    **A tener en cuenta:** no protege si se pierde el servidor entero.

=== "Mismo disco"

    Una carpeta en el disco actual, por ejemplo `/backup_incremental`.

    **Ventaja:** cero infraestructura, y aun así ganas deduplicación y
    velocidad (ahorros de hasta 25:1).
    **A tener en cuenta:** **no es un respaldo real.** Si el disco muere, se van
    los datos y sus copias a la vez. Válido solo como primera capa.

---

## 2. Configurar rclone

Restic habla S3 de forma nativa, pero en HestiaCP el puente por **rclone** es
el método estable, y además permite cambiar de destino sin tocar HestiaCP.

```bash
rclone config
```

=== "Remoto S3 (Mega S4)"

    ```
    n                          nuevo remoto
    name> megas3-vicsen        el nombre que quieras
    Storage> s3                (Amazon S3 Compliant Storage Providers)
    provider> Other            Mega S4 es compatible con S3, no es un proveedor listado
    env_auth> false            las credenciales se escriben aquí
    access_key_id> ...         tu clave de acceso de Mega S4
    secret_access_key> ...     tu clave secreta
    region>                    (vacío, salvo que Mega indique otra cosa)
    endpoint> ...              el endpoint S3 que te da Mega S4
    location_constraint>       (vacío)
    acl> private
    Edit advanced config? n
    Keep this remote? y
    q                          salir
    ```

    !!! warning "El endpoint es obligatorio"
        Mega S4 no es AWS: sin `endpoint`, rclone intentaría hablar con Amazon.
        Lo encuentras en el panel de Mega, en la sección de S4/S3.

    Comprueba que funciona **antes** de seguir:

    ```bash
    rclone lsd megas3-vicsen:
    rclone mkdir megas3-vicsen:tejido-testing
    ```

=== "Remoto local"

    ```
    n
    name> almacenamiento_local
    Storage> local
    Edit advanced config? n
    Keep this remote? y
    q
    ```

### Dónde vive esa configuración

```
/root/.config/rclone/rclone.conf
```

!!! danger "Ese archivo lleva tus claves de S3 en claro"
    Y no lo respalda nadie: Restic respalda las cuentas de usuario, no la
    configuración de root. Si pierdes el servidor, pierdes las claves para
    llegar a tus propios respaldos.

    Guárdalo fuera del servidor, junto a los `restic.conf`. Ver
    [Claves Restic](../operacion/restic.md).

---

## 3. Vincular con HestiaCP

```bash
v-add-backup-host-restic 'rclone:REMOTO:RUTA/' SNAPSHOTS DIARIAS SEMANALES MENSUALES ANUALES
```

=== "Mega S4"

    ```bash
    v-add-backup-host-restic 'rclone:megas3-vicsen:tejido-testing/hestiacp/' 30 8 5 3 -1
    ```

=== "Disco externo"

    ```bash
    v-add-backup-host-restic 'rclone:almacenamiento_local:/mnt/backup_incremental/' 30 8 5 3 -1
    ```

=== "Mismo disco"

    ```bash
    mkdir -p /backup_incremental
    v-add-backup-host-restic 'rclone:almacenamiento_local:/backup_incremental/' 30 8 5 3 -1
    ```

### Qué significan esos cinco números

!!! danger "Cuidado con el orden: es fácil equivocarse"
    No son «días, semanas, meses, años, total». El **primero** es el total de
    instantáneas. Compruébalo tú mismo en
    `/usr/local/hestia/data/users/conf/restic.conf`:

    | Posición | Variable | Con `30 8 5 3 -1` | Significa |
    |---|---|---|---|
    | 1ª | `SNAPSHOTS` | `30` | Guardar 30 instantáneas en total |
    | 2ª | `KEEP_DAILY` | `8` | 8 diarias |
    | 3ª | `KEEP_WEEKLY` | `5` | 5 semanales |
    | 4ª | `KEEP_MONTHLY` | `3` | 3 mensuales |
    | 5ª | `KEEP_YEARLY` | `-1` | anuales **ilimitadas** |

    Con `-1` en la última posición, las anuales no se purgan nunca. Si esperabas
    «3 años», lo que tienes es «3 mensuales y anuales para siempre».

Comprobación:

```bash
cat /usr/local/hestia/data/users/conf/restic.conf
```

### Si falla porque el repositorio no existe

Solo la primera vez:

```bash
restic init -r rclone:megas3-vicsen:tejido-testing/hestiacp/
```

---

## 4. Programar el cron

!!! warning "HestiaCP no activa el cron de Restic al añadir el host"
    Es el paso que más se olvida, y sin él no se respalda nunca.

**a) Habilitar en el paquete.** *Packages* → editar el paquete de tus usuarios
(`default`) y asegurarse de que los respaldos están activos.

**b) Añadir el cron.** En *Cron* del panel, como `admin`:

```
Comando:  v-backup-users-restic
Horario:  30 05 * * *
```

A una hora distinta de los respaldos tradicionales, para no solaparlos.

!!! tip "Ojo con el porcentaje"
    Igual que con `backupctl`: en crontab un `%` sin escapar se convierte en
    salto de línea y parte la orden. No pongas fechas en esa línea.

**c) Probar a mano** antes de fiarte:

```bash
v-backup-user-restic admin
```

---

## 5. Los `.tar` que no se pueden eliminar del todo

HestiaCP exige que `Backups` en el paquete sea **al menos 1** para que el
proceso capture datos reales. Con `0`, los respaldos de Restic salen en
carpetas vacías. Y si se desactiva el respaldo local globalmente
(`local = no`), la pestaña *Backups* desaparece de la interfaz.

**Recomendación:** `Backups = 1` en el paquete y aceptar un único `.tar`
residual. Es el precio de mantener la gestión desde el panel.

---

## 6. Lo que hay que guardar fuera del servidor

!!! danger "La dependencia circular de todo sistema de respaldos"
    Las claves para leer tus respaldos están en la máquina que puedes perder.

| Archivo | Qué pasa si lo pierdes |
|---|---|
| `/usr/local/hestia/data/users/*/restic.conf` | El repositorio queda **ilegible** |
| `/root/.config/rclone/rclone.conf` | No puedes **llegar** al repositorio |

`backupctl` recoge los primeros:

```bash
sudo backupctl restic
```

El `rclone.conf` hay que copiarlo a mano. Guarda ambos en un gestor de
contraseñas o en otra máquina — **no solo en el propio servidor**.

---

## 7. Comprobaciones periódicas

```bash
# ¿Hay instantáneas y de cuándo?
restic -r rclone:megas3-vicsen:tejido-testing/hestiacp/ snapshots

# ¿El repositorio está sano?
restic -r rclone:megas3-vicsen:tejido-testing/hestiacp/ check

# ¿Cuánto ocupa de verdad, tras deduplicar?
restic -r rclone:megas3-vicsen:tejido-testing/hestiacp/ stats

# HestiaCP: respaldos de un usuario
v-list-user-backups admin
```

!!! quote "Un respaldo que nunca se ha restaurado no es un respaldo"
    Vale igual para Restic. Una vez al año, restaura un usuario completo en una
    máquina desechable y mide cuánto tardas. Ver
    [Recuperación ante desastre](../guias/desastre.md).

---

## 8. Espacio de caché

Restic usa `/root/.cache/restic`. Con repositorios grandes crece bastante, y si
el disco principal se llena, las purgas fallan.

```bash
du -sh /root/.cache/restic
df -h /
```
