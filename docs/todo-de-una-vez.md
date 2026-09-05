# Hacerlo todo de una vez

**Una sola página, de cero a funcionando.** Sin saltar a ninguna otra. Los
enlaces son opcionales: solo para profundizar si algo no sale.

Tiempo: unos 30 minutos. Los pasos marcados 🛡️ **no tocan nada**.

---

## Parte 1 · En tu equipo (5 min)

```bash
cd /ruta/al/repositorio

# 🛡️ ¿Qué servidores conoce ya?
backupctl profiles

# Crear el perfil del servidor (si no existe)
mkdir MiVPS
cp config/env.sh.example MiVPS/env.sh
${EDITOR:-nano} MiVPS/env.sh
```

Rellena estas seis líneas y deja el resto como está:

```bash
export USER_NAME="admin"                  # usuario de HestiaCP
export MYSQL_USER="admin_general"
export MYSQL_PASS="la-contraseña"
export DEPLOY_HOST="mivps.example.com"
export DEPLOY_USER="admin"
export HEALTHCHECK_URL=""                 # se rellena en la parte 5
```

```bash
# 🛡️ ¿Es válida?
backupctl -p MiVPS config --check
```

---

## Parte 2 · Preparar el VPS (10 min)

Tres cosas, y solo tres.

```bash
# 1. Acceso SSH por clave
ssh-copy-id admin@mivps.example.com
ssh admin@mivps.example.com 'hostname'    # debe entrar y darte una shell
```

!!! warning "Si entra y cierra al instante"
    Los usuarios de HestiaCP se crean a menudo con `nologin`. Actívalo en el
    panel (**Usuarios → SSH Access → bash**) o:

    ```bash
    sudo v-change-user-shell admin bash
    ```

```bash
# 2. Paquetes que faltan en una instalación mínima
ssh admin@mivps.example.com 'sudo apt update && sudo apt install -y zip unzip rsync'

# 3. Usuario de MySQL con permisos (omítelo si ya lo tenías)
ssh admin@mivps.example.com
```

```sql
CREATE USER 'admin_general'@'localhost' IDENTIFIED BY 'la-contraseña';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS,
      CREATE, DROP
  ON *.* TO 'admin_general'@'localhost';
FLUSH PRIVILEGES;
```

!!! note "`CREATE` y `DROP` son para poder probar la restauración"
    `verify --restore-test` crea una base de datos desechable y la borra. Es la
    única prueba que demuestra que el respaldo sirve.

**No crees** `/home/admin/scripts`, ni `logs/`, ni `output/`: los crea `deploy`.

---

## Parte 3 · Desplegar (5 min)

```bash
# 🛡️ Ensayo: comprueba SSH, dependencias y lista qué copiaría
backupctl -p MiVPS deploy admin@mivps.example.com --dry-run

# 🛡️ Foto de cómo está el servidor AHORA (antes de tocarlo)
backupctl -p MiVPS pull admin@mivps.example.com
```

!!! danger "En el `pull`, si pregunta por el env.sh: responde `n`"
    Si el servidor ya tenía un `env.sh` antiguo, te enseñará el `diff` y
    preguntará si traértelo. Quieres conservar el del repositorio, que es el
    nuevo y completo.

```bash
# Copiar de verdad
backupctl -p MiVPS deploy admin@mivps.example.com
```

Si el servidor tenía un `env.sh` distinto, te lo enseñará y **preguntará antes
de sobrescribirlo**. Guarda una copia como `env.sh.anterior` en el propio
servidor.

---

## Parte 4 · Comprobar en el VPS (5 min)

```bash
ssh admin@mivps.example.com
cd /home/admin/scripts
```

```bash
# 🛡️ Diagnóstico. No escribe nada. Debe salir SIN fallos (✗)
./bin/backupctl doctor

# El primer respaldo
./bin/backupctl backup
echo "código: $?"           # 0 = correcto

# 🛡️ Verificarlo
./bin/backupctl verify
```

Y la prueba que de verdad importa. Elige una base de datos cualquiera:

```bash
./bin/backupctl list --databases | head
./bin/backupctl verify --restore-test <una_base_de_datos> --with-data
```

!!! danger "No sigas si este paso falla"
    Los anteriores comprueban que el archivo existe y está íntegro. Este es el
    único que comprueba que **sirve para restaurar**.

---

## Parte 5 · Avisos y programación (5 min)

Primero los avisos, porque sin ellos un fallo pasa inadvertido.

Crea un check gratuito en [healthchecks.io](https://healthchecks.io) y:

```bash
./bin/backupctl config --edit
```

```bash
export HEALTHCHECK_URL="https://hc-ping.com/tu-uuid"
```

```bash
./bin/backupctl notify-test      # comprueba que llega
```

!!! tip "Por qué un healthcheck y no un correo"
    Es el único canal que detecta que el cron **dejó de ejecutarse**. Si el
    respaldo nunca arranca, no hay nada que envíe un correo.

Ahora la programación:

```bash
# 🛡️ Ver qué propone, sin instalar
./bin/backupctl cron --show

# Instalar
sudo ./bin/backupctl cron --install
```

!!! info "En HestiaCP hace falta `sudo`, y es importante"
    El crontab del sistema es un archivo **generado** a partir de
    `cron.conf`. Una línea puesta con `crontab -e` no aparece en el panel y
    **desaparece** en el siguiente rebuild. `backupctl` usa `v-add-cron-job`,
    que exige root, para que quede registrada de verdad.

Compruébalo en el panel de HestiaCP, sección **Cron**: deben aparecer tres
trabajos.

---

## Parte 6 · Cerrar el círculo (2 min)

De vuelta en tu equipo:

```bash
backupctl -p MiVPS pull admin@mivps.example.com
git add MiVPS/
git commit -m "MiVPS: backupctl instalado y programado"
```

`MiVPS/ESTADO.md` queda con la versión instalada, el crontab, los respaldos y el
diagnóstico. El repositorio ya recuerda el despliegue.

---

## Ya está. ¿Y ahora?

### Mañana

```bash
backupctl -p MiVPS status      # 🛡️ ¿se ejecutó anoche?
```

### Si tenías scripts antiguos

Déjalos unos días conviviendo. `deploy` no los ha tocado y siguen funcionando.
Cuando el nuevo lleve una semana sin errores:

```bash
ssh admin@mivps.example.com
sudo /usr/local/hestia/bin/v-list-cron-jobs admin       # localizar el viejo
sudo /usr/local/hestia/bin/v-delete-cron-job admin <ID>
rm /home/admin/scripts/RunBackupDB.sh
```

### Cada mes

```bash
./bin/backupctl verify --restore-test <bd> --with-data
```

### Otro servidor

Repite desde la Parte 1 con otro nombre de carpeta. El código no se duplica:
`bin/` y `lib/` son los mismos para todos.

---

## Lista completa

- [ ] `MiVPS/env.sh` creado y `config --check` en verde
- [ ] SSH por clave, y el usuario **tiene shell**
- [ ] `zip`, `unzip`, `rsync` instalados en el VPS
- [ ] Usuario de MySQL con permisos (incluidos `CREATE` y `DROP`)
- [ ] `deploy --dry-run` sin errores
- [ ] `pull` hecho antes de desplegar
- [ ] `deploy` completado
- [ ] `doctor` sin fallos en el VPS
- [ ] `backup` con código `0`
- [ ] **`verify --restore-test --with-data` pasa**
- [ ] `HEALTHCHECK_URL` configurado y `notify-test` llega
- [ ] `cron --install` con `sudo`, y los 3 trabajos se ven en el panel
- [ ] `pull` final y commit en el repositorio

---

## Si algo falla

```bash
./bin/backupctl doctor          # 🛡️ qué está mal y qué hacer
./bin/backupctl logs --errors   # 🛡️ qué falló la última vez
```

Casi todo lo que puede salir mal está en
[Cuando algo falla](guias/diagnostico.md). Para las órdenes sueltas, la
[Chuleta](referencia/chuleta.md). Para restaurar o migrar, las
[guías paso a paso](paso-a-paso/index.md).
