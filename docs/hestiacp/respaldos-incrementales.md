# Blindar un HestiaCP

Montar los respaldos incrementales de HestiaCP con Restic —remoto de rclone,
host de respaldo, cron y rescate de claves— **sin tocar nada a mano**.

```bash
backupctl hestia setup
```

Un asistente que pregunta lo necesario y lo deja todo montado.

!!! tip "¿Quieres entender qué está haciendo por debajo?"
    [El protocolo a mano](protocolo-manual.md) tiene los mismos pasos con las
    órdenes de HestiaCP, rclone y Restic. Útil para entenderlo, para auditarlo,
    y para arreglarlo si algún día la herramienta no está. Si prefieres ir
por partes, cada paso tiene su orden.

!!! info "Dos capas complementarias"
    ```
    MySQL ────backupctl backup────► respaldos verificables y portables
    Cuenta ───Restic vía HestiaCP─► archivos, correo, DNS, configuración
    ```
    `backupctl` respalda las bases de datos con verificación y formato abierto.
    Restic respalda la cuenta entera. **Las dos hacen falta**, y el informe de
    blindaje comprueba que ambas están.

---

## ¿Estoy protegido?

```bash
backupctl shield
```

Es la orden que responde a la pregunta que importa: **¿qué perdería si mañana
desapareciera este servidor?**

```
1 · Bases de datos
  ✓ último respaldo de hace 0 días, 76 bases
  ✗ hay 77 bases en MySQL pero solo 76 en el último respaldo
        SIN RESPALDAR:
          - cliente_nuevo

2 · Cuenta completa (archivos, correo, DNS)
  ✓ Restic configurado: rclone:mi-almacenamiento:mi-servidor/hestiacp/
  ✓ el repositorio está fuera del servidor
  ✗ el cron de Restic NO está activo: configurado pero nunca se ejecuta

3 · Claves de recuperación
  ✓ claves Restic rescatadas (hace 0 días)
  ✗ rclone.conf NO rescatado: no se podría LLEGAR al repositorio

BLINDAJE INCOMPLETO: 3 fallos y 1 avisos.
```

!!! success "Lo que ninguna otra herramienta te dice"
    Que has creado una base de datos que **nadie está respaldando**. HestiaCP no
    lo sabe y el cron tampoco: simplemente respalda lo que ve. `shield` compara
    lo que hay en MySQL con lo que hay dentro de tu último respaldo y **nombra
    las que faltan**.

Devuelve código `1` si hay fallos, así que sirve en una comprobación automática.

---

## Montarlo desde cero

=== "Todo de una vez"

    ```bash
    backupctl hestia setup
    ```

    Encadena los cuatro pasos preguntando lo necesario.

=== "Desde la interfaz web"

    ```bash
    backupctl web --open
    ```

    Pestaña **Blindaje**: los cuatro pasos con sus formularios, y el informe
    arriba del todo.

=== "Paso a paso"

    ```bash
    backupctl hestia rclone     # 1 · dónde se guarda
    backupctl hestia restic     # 2 · host de respaldo y retención
    backupctl hestia cron       # 3 · que se ejecute solo
    backupctl hestia keys       # 4 · rescatar las claves
    ```

---

## 1 · Dónde se guarda

```bash
backupctl hestia rclone
```

Pregunta el nombre del remoto, el tipo y las credenciales, y escribe la sección
en el `rclone.conf` del servidor. Guarda copia de la versión anterior.

| Destino | Protege ante… |
|---|---|
| **S3 / Mega S4** | La pérdida del servidor entero |
| **Disco externo o NAS** | El fallo del disco principal |
| **Mismo disco** | Nada. Solo da deduplicación y velocidad |

!!! danger "Para Mega S4, el endpoint es obligatorio"
    Mega S4 es compatible con S3, pero **no es Amazon**. Sin `endpoint`, rclone
    intentaría hablar con AWS y fallaría. Lo encuentras en el panel de Mega, en
    la sección S4.

    `backupctl` se niega a continuar sin él en lugar de dejarte una
    configuración que no funciona.

Las credenciales **nunca pasan por la línea de órdenes**: viajan por la entrada
estándar hasta el archivo de destino, que queda con permisos `600`. En `ps` no
aparecen.

---

## 2 · Host de respaldo y retención

```bash
backupctl hestia restic
```

Registra el repositorio en HestiaCP y, si hace falta, **lo inicializa**
(`restic init`), que es el paso que HestiaCP no hace y que provoca el clásico
«el repositorio no existe».

!!! danger "El error de retención más común"
    `v-add-backup-host-restic REPO 30 8 5 3 -1` **no** significa
    «días, semanas, meses, años, total».

    | Posición | Variable | Con `30 8 5 3 -1` |
    |---|---|---|
    | 1ª | `SNAPSHOTS` | 30 instantáneas **en total** |
    | 2ª | `KEEP_DAILY` | 8 diarias |
    | 3ª | `KEEP_WEEKLY` | 5 semanales |
    | 4ª | `KEEP_MONTHLY` | 3 mensuales |
    | 5ª | `KEEP_YEARLY` | anuales **ilimitadas** |

    Es fácil creer que tienes «3 años» cuando lo que tienes es «3 mensuales y
    anuales para siempre». `backupctl hestia status` te lo muestra ya
    interpretado, con las etiquetas correctas.

---

## 3 · Que se ejecute solo

```bash
backupctl hestia cron
```

!!! warning "HestiaCP no activa este cron al añadir el host"
    Es el paso que más se olvida. Sin él, Restic queda perfectamente configurado
    y **no se ejecuta nunca**. `shield` lo marca como fallo.

`v-backup-users-restic` recorre **todas** las cuentas, así que es una tarea del
sistema y no de un usuario del panel. Por eso se registra en el crontab de
`hestiaweb` —donde el instalador de HestiaCP pone `v-backup-users`,
`v-update-sys-queue` y las demás tareas propias— y no con `v-add-cron-job`, que
lo ataría a una cuenta concreta.

`v-rebuild-cron-jobs` actúa sobre un usuario del panel y regenera su crontab a
partir de su `cron.conf`. `hestiaweb` no es un usuario del panel, de modo que
esta línea no la borra ningún rebuild.

Por defecto a las 05:45, para no solaparse con los respaldos tradicionales, que
corren a las 05:10.

!!! warning "Buscar el cron en un solo sitio da falsos negativos"
    La entrada puede estar en el crontab de `hestiaweb`, en el de `root`, en
    `/etc/cron.d/` o en el `cron.conf` de una cuenta, según quién y cómo la
    pusiera. Mirar solo `crontab -l` informa de que el cron **no está activo**
    en servidores que llevan meses respaldando cada noche. La orden busca en
    todos esos sitios, y si encuentra uno **no añade un segundo**: dos
    respaldos simultáneos competirían por el mismo repositorio.

---

## 4 · Rescatar las claves

```bash
backupctl hestia keys
```

Trae al repositorio los **dos** archivos sin los cuales tus respaldos son
irrecuperables aunque estén intactos:

| Archivo | Sin él |
|---|---|
| `data/users/*/restic.conf` | El repositorio queda **ilegible** |
| `/root/.config/rclone/rclone.conf` | No puedes **llegar** al repositorio |

!!! danger "El segundo no lo respalda nadie"
    Restic guarda las cuentas de usuario, no la configuración de root. El
    `rclone.conf`, donde están tus claves de S3, queda fuera de todos los
    respaldos. Es la dependencia circular clásica: la llave para abrir la caja
    está dentro de la caja.

**Guárdalos también fuera de este repositorio** — en un gestor de contraseñas o
en otra máquina. `shield` te lo recuerda.

---

## Comprobar

```bash
backupctl hestia status     # configuración, remotos, cron, claves
backupctl hestia verify     # instantáneas, integridad y espacio real
```

`verify` ejecuta `restic snapshots`, `check` y `stats` contra el repositorio de
verdad.

---

## Desde tu equipo o desde el servidor

Todas estas órdenes funcionan igual desde los dos sitios:

```bash
backupctl -p MiVPS hestia status          # va por SSH si hace falta
ssh root@servidor '.../backupctl hestia status'
```

Si el perfil tiene `DEPLOY_HOST` y HestiaCP no está en tu equipo, `backupctl`
abre la conexión y trabaja sobre el servidor. Una sola implementación para los
dos casos.

---

## Los `.tar` que no se pueden quitar del todo

HestiaCP exige que `Backups` en el paquete sea **al menos 1**. Con `0`, los
respaldos de Restic salen en carpetas vacías; y si se desactiva el respaldo
local globalmente, la pestaña *Backups* desaparece del panel.

**Recomendación:** `Backups = 1` y aceptar un único `.tar` residual.

---

## Rutina recomendada

| Cada | Qué |
|---|---|
| Semana | `backupctl shield` — debe salir sin fallos |
| Mes | `backupctl hestia verify` y una prueba de restauración de BD |
| Trimestre | Comprobar que las claves rescatadas siguen fuera del servidor |
| Año | Restaurar un usuario completo en una máquina desechable y medir el tiempo |
