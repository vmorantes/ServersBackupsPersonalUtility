# Respaldo y migración de servidores

Ecosistema de respaldo, verificación, restauración y migración de bases de datos
MySQL/MariaDB para servidores HestiaCP.

Todo se maneja con una sola orden, **`backupctl`**, que tiene dos compuertas
sobre la misma lógica:

```bash
backupctl              # menú interactivo, para personas
backupctl backup       # sin preguntas, para cron y scripts
```

## Documentación

La documentación completa vive en `docs/` y se sirve con MkDocs:

```bash
pipx install mkdocs mkdocs-material   # o: pip install --user
mkdocs serve                          # http://127.0.0.1:8000
```

Incluye instalación, operación diaria, migración entre servidores, referencia de
todas las órdenes y variables, recetas para el día a día, diagnóstico de fallos
y un plan de recuperación ante desastre.

## Lo mínimo

```bash
backupctl status               # ¿estoy protegido ahora mismo?
backupctl doctor               # ¿qué está mal?
backupctl backup               # respaldar
backupctl verify               # comprobar el último respaldo
backupctl list                 # qué respaldos tengo
backupctl restore '' <bd>      # restaurar una base de datos
backupctl --help               # todo lo demás
```

## Estructura — de todo esto, tú editas un archivo

```
bin/backupctl        🔧 la orden. Se sube igual a TODOS los servidores
lib/*.sh             🔧 la lógica. Se sube igual a TODOS los servidores
config/              📖 env.sh.example, referencia de configuración
docs/  mkdocs.yml    📖 documentación

TejidoTesting/          🖥️ un servidor
├── env.sh           ✏️ LO ÚNICO QUE EDITAS TÚ
├── NOTAS.md         ✏️ tus apuntes de despliegue (nadie los toca)
└── ESTADO.md        🤖 lo genera `backupctl pull`
```

`bin/` y `lib/` son **los archivos compartidos que se suben a cualquier
despliegue**. Son byte a byte idénticos en todas las máquinas: lo único distinto
entre un servidor y otro es su `env.sh`. Por eso no hay copias del script por
servidor que puedan divergir.

Si te pierdes, lee `docs/empezar/que-es-cada-cosa.md`.

## Los dos sentidos

```
   repositorio  ──── backupctl deploy (SUBIR) ────►  servidor
   repositorio  ◄─── backupctl pull  (DESCARGAR) ──  servidor
```

```bash
backupctl -p TejidoTesting deploy admin@servidor   # subir código + config
backupctl -p TejidoTesting pull   admin@servidor   # traer el estado real
```

`deploy` deja en el servidor exactamente esto, y allí los scripts viven y corren:

```
/home/admin/scripts/
├── bin/backupctl   ┐ copiados del repo,
├── lib/*.sh        ┘ idénticos en todos los servidores
├── env.sh          ← copiado de TejidoTesting/env.sh
├── logs/  output/  ← se generan allí
```

`pull` hace lo contrario: compara el `env.sh` del servidor con el tuyo (avisando
si alguien lo tocó allí) y escribe `ESTADO.md` con la versión instalada, el
crontab, los respaldos y el diagnóstico. Es lo que hace que el repositorio
**recuerde** cada despliegue.

```bash
backupctl profiles                  # servidores conocidos
backupctl -p TejidoTesting status   # trabajar con uno concreto
```

## Qué garantiza

- **Nunca reporta éxito si un volcado falló.** Lee la salida de error de
  `mysqldump`, no solo su código de salida, porque con `--force` este último
  miente.
- **Cada respaldo lleva sumas SHA-256** de todo lo que contiene, en un manifiesto
  dentro del propio zip.
- **El volcado es portable**: sin `DEFINER`, con `SQL SECURITY INVOKER`, charset
  explícito y sin estado de replicación. Se restaura en otra máquina.
- **Formato abierto**: zip + gzip + SQL plano. Si esto desapareciera, `unzip` y
  `mysql` bastan para restaurar.
- **`--dry-run` en casi todo**, y `--into` para restaurar al lado sin tocar la
  base viva.

## Comprobar el código

```bash
bash -n bin/backupctl lib/*.sh      # sintaxis
shellcheck bin/backupctl lib/*.sh   # análisis estático
backupctl doctor                    # entorno
mkdocs build --strict               # documentación
```
