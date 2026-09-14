# Entorno de desarrollo

Verificado 2026-09-14 en la máquina del PO (Linux), con `command -v`.

## Qué hay

| Herramienta | Estado |
| --- | --- |
| `bash` | sí |
| `python3` | sí; la web y los scripts de `.agents/` usan solo la biblioteca estándar |
| `node` | sí, vía `fnm` en el `PATH` de la sesión; solo para `node --check web/app.js` |
| `mkdocs` | sí, en `~/.local/bin`. `mkdocs build` es un build: solo con permiso del PO |
| `mysql`, `restic`, `rclone` | **instalados** en `/usr/bin` y funcionales: justo por eso la guarda los bloquea |
| `php` | instalado; el proyecto no tiene PHP |
| `shellcheck`, `bats` | **no instalados**. Instalarlos es decisión del PO |
| HestiaCP, servidor MySQL de pruebas | no |

**`~/.local/bin/backupctl` existe**: es el enlace que creó la «prueba» de `backupctl install`
del 2026-09-05 y apunta a `bin/backupctl` de este repositorio. Con él, `backupctl` a secas
funciona en cualquier terminal y usa el perfil real por defecto (`30-trampas.md` T3).

## Qué no se puede verificar aquí

- Nada que dependa de un servidor: el comportamiento real de HestiaCP, de un volcado contra
  un MySQL con datos, de Restic contra el S3, de `deploy`/`pull`/`adoptar`.
- Que la web funcione contra un perfil: abrirla hace ssh al servidor.

Decirlo así en cualquier reporte, en vez de dar por probado lo que solo se razonó. Lo que el
PO tenga que comprobar en un servidor va a «Espera al PO» con los pasos.

## Cómo se prueba sin servidor

**Hoy no existe un banco de pruebas** (`30-trampas.md` T18; roadmap). Cualquier prueba
nueva sigue estas reglas, que son las que tendrá que cumplir el banco:

1. Un guion de entrada, `tests/ejecutar.sh`, sin argumentos; sale con 0 si todo pasa.
   `verificar.sh` lo ejecuta si existe. La guarda no deja ejecutar `backupctl` directamente
   (salvo `--help`, `version`, `profiles`): las pruebas lo ejecutan desde ese guion.
2. Aborta si corre como root.
3. Un temporal propio: `mktemp -d -t backupctl-pruebas.XXXXXX`, borrado al salir.
4. Un directorio de órdenes falsas **delante en el `PATH`** (`ssh`, `rsync`, `mysql`,
   `mysqldump`, `sudo`, `crontab`, `restic`, `rclone` y los `v-*` que hagan falta), que
   registran sus argumentos y su entrada estándar en el temporal y devuelven datos sintéticos.
   **Antes de ejecutar nada**, el guion comprueba que `command -v` de cada una resuelve a su
   falso; si no, aborta.
5. Un perfil sintético en el temporal, pasado **siempre** con `-p <temporal>/Perfil/env.sh`
   (T3). Credenciales falsas, `example.org`, `203.0.113.10`.
6. Lo que se puede redirigir: `TMPDIR`; las rutas del `env.sh` (`SCRIPTS_DIR`,
   `BACKUP_*_DIR`, `LOG_DIR`, `HESTIA_OUTPUT_DIR`); `BC_RCLONE_CONF`; `HESTIA_DIR` solo en
   parte. Lo que no: `BC_ROOT`, las rutas `/usr/local/hestia` escritas a mano (T18). Lo que
   depende de ellas se reporta como no probado; no se rodea tocando el sistema.
7. Cubren el camino de fallo (`20-convenciones.md`, «Pruebas»).

Montar el banco es una tarea del roadmap que necesita ADR.

## Verificación del proyecto

```
bash .agents/scripts/verificar.sh
```

Comprueba: `bash -n` de `bin/backupctl` y todos los `.sh` (sin los `env.sh` de perfiles),
ausencia de CRLF, el modo `100755` de `bin/backupctl`, sintaxis Python y JavaScript,
`web/comprobar.py`, que `backupctl --help` arranca, agentes generados al día, symlinks de
`.claude/`, pruebas de la guarda, menciones a IA en entregables y en commits posteriores a la
adopción, y `tests/ejecutar.sh` si existe. No conecta a nada, no lee credenciales, no escribe
fuera del repositorio.

No incluye `mkdocs build --strict` (es un build: pendiente de que el PO lo autorice) ni
`shellcheck` (no instalado).
