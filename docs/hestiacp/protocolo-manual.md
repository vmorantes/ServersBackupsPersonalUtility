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
| 4 · Inicializar | lo hace `v-backup-user-restic` | lo hace `v-backup-user-restic` |
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
v-add-backup-host-restic 'rclone:mi-almacenamiento:mi-bucket/hestiacp' 30 8 5 3 -1
```

!!! danger "La ruta, absoluta siempre que el remoto sea `local`"
    Con un remoto de tipo `local` (o un `alias` sin raíz fija), rclone resuelve
    una ruta **sin barra inicial desde el directorio en el que estés parado**.
    Registrar `mi-servidor/hestiacp/` estando dentro de `public_html` crea los
    respaldos **dentro de la web**, servidos por internet. Ocurrió en un servidor
    real el 2026-09-23, siguiendo un ejemplo de esta misma página.

    | Tipo de remoto | Cómo se escribe la ruta |
    |---|---|
    | `local`, `alias`, `sftp` | absoluta: `'rclone:almacen:/IncrementalBackups'` |
    | Bucket (S3, B2, Mega S4) | empieza por el bucket: `'rclone:mi-almacenamiento:mi-bucket/hestiacp'` |

    Comprueba dónde apunta el remoto antes de registrarlo:

    ```bash
    rclone config show mi-almacenamiento | grep -E '^(type|root|remote) ='
    ```

    La barra **final** da igual: `v-add-backup-host-restic` la quita
    ([líneas 85-87](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-add-backup-host-restic#L85-L87)).
    La que importa es la inicial.

!!! danger "El orden de los cinco números"
    **No** son «días, semanas, meses, años, total». El primero es el total de
    instantáneas y el resto van desplazados respecto a lo que uno espera:

    | Posición | Variable | Con `30 8 5 3 -1` |
    |---|---|---|
    | 1ª | `SNAPSHOTS` | 30 instantáneas **en total** |
    | 2ª | `KEEP_DAILY` | 8 diarias |
    | 3ª | `KEEP_WEEKLY` | 5 semanales |
    | 4ª | `KEEP_MONTHLY` | 3 mensuales |
    | 5ª | `KEEP_YEARLY` | con `-1`, **ninguna regla anual** |

    `-1` **no** significa «ilimitadas»: `v-backup-user-restic` solo añade
    `--keep-yearly` cuando el valor es `>= 0`, así que con `-1` la política que
    se aplica no tiene tramo anual. Comprobado en un servidor real el
    2026-09-23, donde restic imprimió `Applying Policy: keep 30 latest, 8 daily,
    5 weekly, 3 monthly snapshots` — sin anuales.

    Compruébalo siempre, porque es fácil creer que tienes «3 años» cuando lo que
    tienes es «3 mensuales y anuales para siempre»:

    ```bash
    cat /usr/local/hestia/conf/restic.conf
    ```

---

## 4 · Inicializar el repositorio

**Normalmente no hay nada que hacer en este paso.** Lo hace HestiaCP, pero con
una condición que no es evidente: `v-backup-user-restic` crea el repositorio de
una cuenta **solo si todavía no existe su archivo de contraseña**,
`/usr/local/hestia/data/users/<cuenta>/restic.conf`
([líneas 54-60](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-backup-user-restic#L54-L60)).
Si ese archivo ya está, da por hecho que el repositorio existe y se limita a
comprobarlo.

!!! danger "Nunca inicialices la ruta que registraste"
    Esa ruta es el **padre**, no un repositorio. HestiaCP le añade `/<cuenta>` y
    guarda **un repositorio por cuenta**, cada uno con la contraseña de 32
    caracteres que él mismo genera
    ([línea 58](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-backup-user-restic#L58)).

    Un `restic init` sobre el padre deja un repositorio huérfano por encima de
    los de verdad, cifrado con una contraseña que HestiaCP no conoce, y **no
    arregla el error**: el respaldo seguirá fallando exactamente igual.

Si el primer respaldo falla con `unable to open config file: <config/> does not
exist`, significa que la contraseña de la cuenta ya existía y su repositorio no.
Hay dos salidas:

```bash
# a) Que lo haga HestiaCP: apartar la contraseña y repetir el respaldo
mv /usr/local/hestia/data/users/<cuenta>/restic.conf /root/clave-vieja.conf
v-backup-user-restic <cuenta>

# b) Crearlo a mano, con la contraseña que HestiaCP ya tiene
restic init -r rclone:mi-almacenamiento:mi-bucket/hestiacp/<cuenta> \
  --password-file /usr/local/hestia/data/users/<cuenta>/restic.conf
```

La opción (a) solo es segura si esa contraseña no abre ningún repositorio con
instantáneas dentro: si lo abre y la pierdes, esas copias no se recuperan nunca.

!!! tip "Distinguir los dos fallos"
    `unable to open config file` = no hay repositorio en esa ruta.
    `wrong password or no key found` = el repositorio está, pero la contraseña no
    es la suya. HestiaCP los tapa a los dos con el mismo `Unable to access restic
    repo` ([línea 68](https://github.com/hestiacp/hestiacp/blob/1.10.4/bin/v-backup-user-restic#L68)),
    así que hay que leer la línea de restic que va justo encima.

---

## 5 · Activar el cron

!!! warning "El paso que más se olvida"
    HestiaCP **no** activa el cron de Restic al añadir el host. Sin esto queda
    todo perfectamente configurado y **no se ejecuta nunca**. Es el fallo
    silencioso más caro de esta configuración.

**a) Habilitar en el paquete.** *Packages* → editar el paquete de tus usuarios
(`default`) y comprobar que los respaldos están activos.

**b) Añadir el cron.** Va en el crontab de `hestiaweb`, **no en la pestaña
*Cron* del panel**. Comprobar con `grep`, añadir al final, y dejar los permisos
como estaban:

```bash
CT=/var/spool/cron/crontabs/hestiaweb
grep -q v-backup-users-restic "$CT" \
  || echo "45 05 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" >> "$CT"
chmod 600 "$CT"; chown hestiaweb:hestiaweb "$CT"
```

A una hora distinta de los respaldos tradicionales, que corren a las 05:10.

!!! danger "Por qué no vale la pestaña *Cron* del panel"
    Es el atajo que parece razonable y falla en silencio. La pestaña escribe la
    tarea en el crontab de **esa cuenta del panel**, y ahí pasan tres cosas:

    - El `PATH` de cron no incluye `/usr/local/hestia/bin`, así que
      `v-backup-users-restic` a secas no se encuentra.
    - Sin `sudo`, esa cuenta no puede respaldar a las demás.
    - `v-rebuild-cron-jobs` regenera el crontab de una cuenta del panel desde su
      `cron.conf`, y puede llevarse la línea por delante.

    Resultado: una línea que existe, que se ve en el panel, y que no respalda
    nada. Encontrada así en un servidor real el 2026-09-23
    (`30 5 * * * v-backup-users-restic` en el crontab de una cuenta).

!!! warning "No es una tarea de un usuario del panel"
    `v-backup-users-restic` recorre **todas** las cuentas: es una tarea del
    sistema. Va en el crontab de `hestiaweb`, junto a `v-backup-users` y
    `v-update-sys-queue`, no en el `cron.conf` de una cuenta.

    `v-rebuild-cron-jobs` recibe un USUARIO del panel y regenera su crontab a
    partir de su `cron.conf`. `hestiaweb` no es usuario del panel, así que esta
    línea no la borra ningún rebuild.

    Comprobado en HestiaCP 1.10.4: no hay una sola mención a
    `v-backup-users-restic` en `bin/`, `func/` ni `install/`. Configurar el
    respaldo incremental **no** programa nada.

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
v-add-backup-host-restic 'rclone:mi-almacenamiento:mi-bucket/servidor-nuevo' 30 8 5 3 -1
grep -q v-backup-users-restic /var/spool/cron/crontabs/hestiaweb \
  || echo "45 05 * * * sudo /usr/local/hestia/bin/v-backup-users-restic" \
     >> /var/spool/cron/crontabs/hestiaweb
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
