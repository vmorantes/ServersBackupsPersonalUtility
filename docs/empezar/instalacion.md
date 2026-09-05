# Instalación

## Requisitos

**Imprescindibles** (el diagnóstico falla sin ellos):

```
bash 4+   mysql   mysqldump   gzip   zip   unzip   find   sha256sum   flock
```

**Opcionales** (cada uno habilita una función):

| Orden | Habilita |
|---|---|
| `curl` | Avisos por `HEALTHCHECK_URL` |
| `mail` | Avisos por `NOTIFY_EMAIL` |
| `rsync`, `ssh` | `deploy` y `migrate` |
| `whiptail` o `dialog` | Menús gráficos en la TUI (sin ellos, menú de texto) |
| `column` | Tablas mejor alineadas |

Comprueba todo de una vez:

```bash
backupctl doctor
```

## Instalar en un servidor

=== "Desde otra máquina (recomendado)"

    Si ya tienes el repositorio en tu equipo, despliega por SSH:

    ```bash
    backupctl -p TejidoTesting deploy admin@servidor.example
    ```

    Copia `bin/` y `lib/`, sube el `env.sh` del perfil y ejecuta el diagnóstico
    en el destino. Ver [Desplegar](../migracion/desplegar.md).

=== "A mano"

    ```bash
    # 1. Copiar el tooling
    scp -r bin lib admin@servidor:/home/admin/scripts/

    # 2. Configuración
    scp config/env.sh.example admin@servidor:/home/admin/scripts/env.sh

    # 3. En el servidor
    ssh admin@servidor
    cd /home/admin/scripts
    mkdir -p logs output
    chmod +x bin/backupctl
    ${EDITOR:-nano} env.sh          # completar MYSQL_USER y MYSQL_PASS
    ```

## Configurar

Edita `env.sh`. Lo mínimo son dos líneas:

```bash
export MYSQL_USER="admin_general"
export MYSQL_PASS="la-contraseña"
```

Todo lo demás tiene un valor por defecto razonable. La
[referencia de variables](../referencia/variables.md) las lista todas.

Comprueba que es válida:

```bash
backupctl config --check
backupctl config --show      # ver los valores efectivos, con los defectos ya aplicados
```

## Privilegios de MySQL

El usuario necesita esto para un volcado completo:

```sql
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES, PROCESS
  ON *.* TO 'admin_general'@'localhost';
FLUSH PRIVILEGES;
```

| Privilegio | Sin él |
|---|---|
| `SELECT` | No hay volcado posible |
| `SHOW VIEW` | Las vistas salen vacías |
| `TRIGGER` | Faltan los triggers |
| `EVENT` | Faltan los eventos programados |
| `LOCK TABLES` | Necesario para tablas no InnoDB |
| `PROCESS` | Solo si quitas `--no-tablespaces` |

`backupctl doctor` comprueba cuáles tienes y avisa de los que falten.

## Comprobar y programar

```bash
# 1. Diagnóstico: debe salir sin fallos
backupctl doctor

# 2. Primer respaldo a mano
backupctl backup
echo "código: $?"          # 0 = correcto

# 3. Verificarlo
backupctl verify

# 4. La prueba de verdad
backupctl verify --restore-test <una_base_de_datos> --with-data

# 5. Programarlo
backupctl cron --install
```

!!! danger "No des por instalado hasta el paso 4"
    Los pasos 1–3 comprueban que el archivo existe y está íntegro. El paso 4
    es el único que comprueba que **sirve para restaurar**.

## Acceso cómodo (opcional)

```bash
sudo ln -s /home/admin/scripts/bin/backupctl /usr/local/bin/backupctl
```

`backupctl` resuelve los enlaces simbólicos, así que encuentra su `lib/`
correctamente aunque se invoque desde otra ruta.
