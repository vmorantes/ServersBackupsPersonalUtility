# El mismo protocolo, a mano

Todo lo que hace `backupctl hestia setup`, paso a paso y sin la herramienta.

!!! question "¿Para qué querría hacerlo a mano?"
    Por tres razones legítimas:

    - **Para entender qué está pasando.** Una herramienta que hace magia es una
      herramienta en la que no puedes confiar cuando falla.
    - **Para arreglarlo cuando algo se rompe.** Si `backupctl` no está o no
      funciona, esto es lo que hay que teclear.
    - **Para auditar.** Comparar lo que la herramienta hizo con lo que debía
      hacer.

    Para el día a día, usa la herramienta: hace estos mismos pasos, comprueba
    lo que aquí se comprueba a ojo, y no se olvida del cron.

| Paso | A mano | Con la herramienta |
|---|---|---|
| 1 · Elegir destino | Decidir tú | — |
| 2 · Remoto de rclone | `rclone config` | `hestia rclone` |
| 3 · Host de respaldo | `v-add-backup-host-restic` | `hestia restic` |
| 4 · Inicializar | `restic init` | incluido en `hestia restic` |
| 5 · Cron | Panel de HestiaCP | `hestia cron` |
| 6 · Rescatar claves | `cp` a mano | `hestia keys` |
| 7 · Comprobar | `restic snapshots` | `hestia verify` |

---

## 1 · Elegir dónde se guarda

| Destino | Protege ante | No protege ante |
|---|---|---|
| **S3 / Mega S4** | Pérdida del servidor entero | Perder las claves |
| **Disco externo o NAS** | Fallo del disco principal | Incendio, robo, pérdida del sitio |
| **Mismo disco** | Nada | Nada. Solo da deduplicación y velocidad |

La tercera opción es válida como primera capa, pero **no es un respaldo**: si el
disco muere, se van los datos y sus copias a la vez.

---

## 2 · Configurar el remoto de rclone

Restic habla S3 de forma nativa, pero en HestiaCP el puente por rclone es lo
estable y permite cambiar de destino sin tocar HestiaCP.

```bash
rclone config
```

=== "S3 / Mega S4"

    ```
    n                          nuevo remoto
    name> mi-almacenamiento
    Storage> s3                Amazon S3 Compliant Storage Providers
    provider> Other            Mega S4 es compatible, no es un proveedor listado
    env_auth> false
    access_key_id> …           del panel de Mega, sección S4
    secret_access_key> …
    region>                    vacío salvo que Mega indique otra
    endpoint> …                OBLIGATORIO
    location_constraint>       vacío
    acl> private
    Edit advanced config? n
    Keep this remote? y
    q
    ```

    !!! danger "Sin `endpoint`, rclone habla con Amazon"
        Es el error que hace que «no funcione y no se sepa por qué». Mega S4 es
        compatible con S3 pero **no es AWS**: sin endpoint, rclone dirige las
        peticiones a Amazon, donde tus credenciales no valen nada.

=== "Disco local o NAS montado"

    ```
    n
    name> almacenamiento_local
    Storage> local
    Edit advanced config? n
    Keep this remote? y
    q
    ```

**Comprobar antes de seguir.** Si esto falla, nada de lo que viene después
funcionará:

```bash
rclone lsd mi-almacenamiento:
rclone mkdir mi-almacenamiento:mi-servidor
```

La configuración queda en `/root/.config/rclone/rclone.conf`, **con las claves
en claro**. Acuérdate de este archivo: vuelve a aparecer en el paso 6.

---

## 3 · Registrar el host de respaldo

```bash
v-add-backup-host-restic 'rclone:REMOTO:RUTA/' SNAPSHOTS DIARIAS SEMANALES MENSUALES ANUALES
```

```bash
v-add-backup-host-restic 'rclone:mi-almacenamiento:mi-servidor/hestiacp/' 30 8 5 3 -1
```

!!! danger "El orden de los cinco números"
    **No** son «días, semanas, meses, años, total». El primero es el total de
    instantáneas y el resto van desplazados respecto a lo que uno espera:

    | Posición | Variable | Con `30 8 5 3 -1` |
    |---|---|---|
    | 1ª | `SNAPSHOTS` | 30 instantáneas **en total** |
    | 2ª | `KEEP_DAILY` | 8 diarias |
    | 3ª | `KEEP_WEEKLY` | 5 semanales |
    | 4ª | `KEEP_MONTHLY` | 3 mensuales |
    | 5ª | `KEEP_YEARLY` | anuales **ilimitadas** (`-1`) |

    Compruébalo siempre, porque es fácil creer que tienes «3 años» cuando lo que
    tienes es «3 mensuales y anuales para siempre»:

    ```bash
    cat /usr/local/hestia/data/users/conf/restic.conf
    ```

---

## 4 · Inicializar el repositorio

HestiaCP **no** lo hace. Si el primer respaldo falla diciendo que el repositorio
no existe, es esto:

```bash
restic init -r rclone:mi-almacenamiento:mi-servidor/hestiacp/
```

Una sola vez, y solo la primera.

---

## 5 · Activar el cron

!!! warning "El paso que más se olvida"
    HestiaCP **no** activa el cron de Restic al añadir el host. Sin esto queda
    todo perfectamente configurado y **no se ejecuta nunca**. Es el fallo
    silencioso más caro de esta configuración.

**a) Habilitar en el paquete.** *Packages* → editar el paquete de tus usuarios
(`default`) y comprobar que los respaldos están activos.

**b) Añadir el cron.** En la sección *Cron* del panel, como `admin`:

```
Comando:  v-backup-users-restic
Horario:  30 05 * * *
```

A una hora distinta de los respaldos tradicionales, para no solaparlos.

O desde la línea de órdenes:

```bash
v-add-cron-job admin 30 5 '*' '*' '*' 'v-backup-users-restic'
```

!!! tip "Hazlo por la vía de HestiaCP, no con `crontab -e`"
    En HestiaCP, el crontab del sistema es un archivo **generado** a partir de
    `data/users/<user>/cron.conf`. Una línea puesta a mano no aparece en el
    panel y **desaparece** en el siguiente `v-rebuild-cron-jobs`.

**c) Probar a mano** antes de fiarte:

```bash
v-backup-user-restic admin
```

---

## 6 · Rescatar las claves

!!! danger "La dependencia circular"
    Las llaves para abrir la caja están dentro de la caja.

Hay que sacar del servidor **dos** archivos, no uno:

```bash
# 1. Las claves de cifrado, una por usuario
cat /usr/local/hestia/data/users/*/restic.conf

# 2. La configuración de rclone, con las claves de S3
cat /root/.config/rclone/rclone.conf
```

| Archivo | Si lo pierdes |
|---|---|
| `restic.conf` | El repositorio queda **ilegible** |
| `rclone.conf` | No puedes **llegar** al repositorio |

**El segundo no lo respalda nadie.** Restic guarda las cuentas de usuario, no la
configuración de root. Es el que casi todo el mundo se deja.

Cópialos **fuera del servidor**: a un gestor de contraseñas o a otra máquina.
Guardarlos solo en el propio servidor no sirve de nada.

---

## 7 · Comprobar

```bash
# ¿Hay instantáneas y de cuándo?
restic -r rclone:mi-almacenamiento:mi-servidor/hestiacp/ snapshots

# ¿El repositorio está sano?
restic -r rclone:mi-almacenamiento:mi-servidor/hestiacp/ check

# ¿Cuánto ocupa de verdad tras deduplicar?
restic -r rclone:mi-almacenamiento:mi-servidor/hestiacp/ stats

# Lo que ve HestiaCP
v-list-user-backups admin
```

---

## 8 · Montar el mismo protocolo en otro servidor

Con el `rclone.conf` que rescataste en el paso 6, no hace falta volver al panel
del proveedor:

```bash
# En el servidor NUEVO
mkdir -p /root/.config/rclone
cp rclone_20260905.conf /root/.config/rclone/rclone.conf
chmod 600 /root/.config/rclone/rclone.conf
rclone lsd mi-almacenamiento:          # comprobar que responde
```

Y después los pasos 3 a 5 con **otra ruta dentro del mismo bucket**, para que
los dos servidores no se pisen:

```bash
v-add-backup-host-restic 'rclone:mi-almacenamiento:servidor-nuevo/hestiacp/' 30 8 5 3 -1
restic init -r rclone:mi-almacenamiento:servidor-nuevo/hestiacp/
v-add-cron-job admin 30 5 '*' '*' '*' 'v-backup-users-restic'
```

---

## Los `.tar` residuales

HestiaCP exige que `Backups` en el paquete sea **al menos 1**. Con `0`, los
respaldos de Restic salen en carpetas vacías; y si se desactiva el respaldo local
globalmente (`local = no`), la pestaña *Backups* desaparece del panel.

Lo práctico es `Backups = 1` y aceptar un único `.tar` residual.

---

## Espacio de caché

Restic usa `/root/.cache/restic`. Con repositorios grandes crece, y si el disco
principal se llena las purgas fallan.

```bash
du -sh /root/.cache/restic
df -h /
```

---

## Comparado con la herramienta

Lo que `backupctl` añade sobre hacerlo a mano no es hacerlo más rápido, sino
**comprobar lo que aquí se comprueba a ojo**:

- Se niega a configurar S3 sin `endpoint`, en lugar de dejar algo que no funciona.
- Interpreta la retención con sus nombres reales, para que no la leas al revés.
- Inicializa el repositorio si hace falta, sin esperar a que falle el primer respaldo.
- Registra el cron por la vía de HestiaCP, así que sobrevive a los rebuilds.
- Rescata **los dos** archivos de claves, incluido el que nadie recuerda.
- Y `backupctl shield` te dice si falta alguna de estas piezas, incluida una base
  de datos que exista y **nadie esté respaldando**.

```bash
backupctl hestia setup      # los pasos 2 a 6
backupctl shield            # ¿está todo?
```
