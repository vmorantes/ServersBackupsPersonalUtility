# Primeros pasos

Un recorrido de diez minutos por todo lo que necesitas saber.

## 1. ¿Dónde estoy?

```bash
backupctl profiles
```

```
PERFIL         CONFIGURACIÓN
TejidoTesting  /var/www/html/.../TejidoTesting/env.sh
```

Si solo hay un perfil, no hace falta nombrarlo nunca. Si hay varios, se indica
con `-p`:

```bash
backupctl -p TejidoTesting status
```

## 2. ¿Estoy protegido ahora mismo?

```bash
backupctl status
```

```
== Estado del respaldo — perfil 'TejidoTesting' ==
[  OK ] Último respaldo: all_databases_20260905_033012.zip — hace 0 días, 38.3M
[INFO ] Respaldos guardados: 14 (536M)
[  OK ] Disco: 55812MB libres (62% usado).
[  OK ] MySQL: accesible como 'admin_general', 76 bases de datos a respaldar.
[  OK ] Avisos configurados: healthcheck
[  OK ] Último log (backup_20260905_033012.log): sin errores.
[  OK ] Todo correcto.
```

Devuelve **0** si todo está bien y **1** si algo requiere atención, así que
sirve tal cual en una comprobación automática.

## 3. Un respaldo, sin miedo

Primero, mira qué haría sin hacerlo:

```bash
backupctl backup --dry-run
```

Cuando te convenza:

```bash
backupctl backup
```

Con terminal verás el progreso en vivo. Bajo cron, todo va al log.

!!! tip "Solo una base de datos"
    ```bash
    backupctl backup --only tienda
    ```
    Útil antes de un despliegue arriesgado sobre una base concreta.

## 4. Verificar

```bash
backupctl verify
```

Comprueba el zip, cada `.gz`, las sumas SHA-256 del manifiesto y el contenido
base de datos por base de datos.

Y ahora la prueba que de verdad importa:

```bash
backupctl verify --restore-test tienda --with-data
```

Crea una base de datos temporal, restaura ahí el respaldo, cuenta lo que quedó
y **elimina la base temporal**. Nada de tu producción se toca.

## 5. Qué tengo guardado

```bash
backupctl list
```

```
ARCHIVO                            TAMAÑO  FECHA             EDAD  BD
all_databases_20260905_033012.zip  38.3M   2026-09-05 03:30  0d    76
all_databases_20260904_033010.zip  38.1M   2026-09-04 03:30  1d    76
```

Y qué hay dentro de uno:

```bash
backupctl inspect                      # el más reciente
backupctl inspect all_databases_20260904_033010.zip
```

## 6. Programarlo

```bash
backupctl cron --show       # ver qué propone, sin instalar nada
backupctl cron --install    # instalarlo (pide confirmación)
```

Y configura al menos un aviso en `env.sh`, o un fallo pasará inadvertido:

```bash
export HEALTHCHECK_URL="https://hc-ping.com/tu-uuid"
```

```bash
backupctl notify-test       # comprobar que llega
```

## 7. El menú, para lo demás

```bash
backupctl
```

Todo lo anterior está ahí, navegable. Es la forma de no tener que recordar
ninguna opción.

## Resumen en una tarjeta

```bash
backupctl                      # menú interactivo
backupctl status               # ¿estoy protegido?
backupctl doctor               # ¿qué está mal?
backupctl backup               # respaldar
backupctl verify               # comprobar el último respaldo
backupctl list                 # qué respaldos tengo
backupctl restore '' <bd>      # restaurar una base de datos
backupctl logs --errors        # qué falló la última vez
```

Siguiente lectura recomendada: **[Recetas](../guias/recetas.md)**.
