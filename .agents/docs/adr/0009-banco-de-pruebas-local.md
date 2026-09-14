# 0009 — Banco de pruebas local: órdenes falsas en el PATH y perfiles sintéticos

- **Estado:** Reemplazada por 0010
- **Fecha:** 2026-09-14
- **Decide:** Arquitecto, por mandato del PO («banco de pruebas local», 2026-09-14)
- **Estructural:** sí (dónde viven las pruebas, cómo se ejecutan, qué entra en `verificar.sh`)

## En cristiano

Hasta hoy la única forma de saber si `backupctl` funcionaba era probarlo contra un servidor,
y eso ahora solo lo hace el PO (ADR 0006). El banco es una carpeta `tests/` que ejecuta
`backupctl` de verdad en esta máquina, pero sustituyendo `mysql`, `mysqldump`, `ssh` y
compañía por imitaciones que apuntan lo que reciben y responden con datos inventados. Todo
ocurre en una carpeta temporal, con un «servidor» y un «hogar» de mentira, así que ninguna
prueba puede tocar un servidor, una base de datos ni el sistema del PO. No sustituye a la
prueba del PO en un servidor: la prepara y la acota.

## Contexto

- No existe ninguna prueba automatizada (`.agents/context/30-trampas.md` T18).
- `bin/backupctl` y `lib/` invocan `mysql`, `mysqldump` (`lib/mysql.sh:58-59`), `ssh`
  (`lib/ssh.sh:53`), `rsync`, `sudo`, `crontab`, `restic` y `rclone` **por su nombre**: la única
  forma de sustituirlos sin tocar el código es anteponer un directorio en el `PATH`.
- Lo que se puede redirigir sin tocar el código: `TMPDIR` (credenciales temporales de MySQL,
  socket de ssh), `HOME` (`~/.ssh`, `~/.local/bin`, `~/.my.cnf`), las rutas del `env.sh` y el
  perfil con `-p <ruta>/env.sh` (`lib/config.sh:77-78`). Lo que no: `BC_ROOT` y las rutas
  `/usr/local/hestia` escritas a mano (T18).
- Sin `-p`, toda orden usa el perfil real (T3). Varias `BC_OPT_*` se heredan del entorno (T13).
- La guarda solo deja ejecutar `backupctl` a través de un guion (ADR 0003).
- En la máquina hay `bash`, `python3`, `node`; no hay `bats` ni `shellcheck` (`40-entorno.md`).

## Decisión

Una carpeta `tests/` en bash, sin dependencias:

| Pieza | Qué es |
| --- | --- |
| `tests/ejecutar.sh` | Única entrada. Sin argumentos. Aborta si corre como root. Crea un temporal `mktemp -d -t backupctl-pruebas.XXXXXX`, lo borra al salir, lanza cada suite en su propio proceso y sale con 0 solo si todas pasan. `verificar.sh` ya la ejecuta si existe |
| Entorno de cada suite | `HOME` y `TMPDIR` dentro del temporal; `PATH` con `falsos/` delante; `unset` de toda `BC_*` y `MYSQL_*` heredada; `LC_ALL=C` salvo donde se pruebe el locale |
| **Comprobación de seguridad** | Antes de ejecutar nada, `command -v` de cada orden peligrosa (`ssh scp rsync mysql mysqldump sudo crontab restic rclone mail curl`) tiene que resolver a su falso; si una no, aborta sin ejecutar ninguna prueba |
| `tests/falsos/_despachador.sh` + un enlace por orden | Registra argumentos y entrada estándar en `<temporal>/registro/<orden>.log` y responde según un guion por prueba (`<temporal>/guion/<orden>`: código de salida, archivo de salida estándar, archivo de salida de error). Sin guion, falla con un mensaje claro: nunca inventa un éxito |
| `tests/lib.sh` | Afirmaciones mínimas (`afirmar_codigo`, `afirmar_igual`, `afirmar_contiene`, `afirmar_intacto` con `cmp`), contador de resultados y `backupctl_prueba`, que **siempre** pasa `-p` con un perfil dentro del temporal y se niega a ejecutar si la ruta está fuera de él |
| `tests/datos/` | Perfil sintético (`env.sh` local, sin `DEPLOY_HOST`, con todas las rutas en el temporal) y volcados SQL sintéticos. `example.org`, `203.0.113.10`, credenciales falsas |
| `tests/probar_<área>.sh` | Una suite por área. Nombres de prueba en inglés; comentarios en español |

Primeras suites, por lo que costaría no tenerlas:

1. **Respaldo**: un `mysqldump` falso que escribe un error en stderr y sale con 0 (la mentira de
   `--force`) hace que `backup` salga con error y nombre la base; el caso limpio deja un zip con
   su manifiesto y sumas correctas.
2. **Verificación**: un zip alterado tras generarse hace fallar `verify`.
3. **Retención**: `BACKUP_KEEP_MIN` conserva los N más recientes aunque todos sean viejos;
   `--dry-run` no borra nada (T4).
4. **Restauración**: con `--into`, el `mysql` falso no recibe el `USE` de la base original (T8).
5. **Perfiles**: `-p` con el perfil sintético; nada escribe fuera del temporal.

Después, en rondas propias: `bc_ssh_sudo` y la entrada estándar (T2), `deploy`/`pull` contra
`ssh`/`rsync` falsos, confirmaciones sin terminal (T5). Lo que depende de `/usr/local/hestia`
escrito a mano (`hestia`, `adoptar`) queda **fuera** hasta decidir si se sustituye por
`$HESTIA_DIR`, que es un cambio de código con su propio ADR.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| `bats` | No está instalado; es una dependencia nueva (00-core). Unas pocas funciones de afirmación bastan. Si el PO lo instala, las suites se pueden migrar |
| Contenedor o máquina virtual con MySQL y HestiaCP | Dependencias, `sudo`, imágenes pesadas; y seguiría sin ser el servidor real. Candidato futuro para pruebas de integración |
| Pruebas en Python | Más lejos del código; el despacho y las trampas de bash (subshells, stdin) se prueban mejor desde bash |
| Parametrizar el código con `BC_SSH`, `MYSQL_CMD`… | Cambia el código de producción para servir a las pruebas y abre la puerta a inyectar órdenes desde el entorno (T13) |
| Seguir sin banco | Con ADR 0006, el coder no podría probar nada más que la sintaxis |

## Consecuencias

- Por primera vez, `verificar.sh` ejecuta comportamiento, no solo sintaxis.
- **Los falsos pueden mentir**: una prueba en verde demuestra que `backupctl` hace lo correcto
  con lo que el falso devuelve, no que MySQL o `ssh` devuelvan eso. Las salidas de los falsos
  se toman de salidas reales documentadas; lo que no se sepa, se marca «sin verificar» en la
  propia prueba. La prueba del PO en un servidor sigue siendo necesaria (ADR 0006).
- `hestia` y `adoptar`, lo más delicado, quedan sin cubrir en esta primera fase.
- `verificar.sh` tardará más.

## Reversión

1. `git rm -r tests/`.
2. `verificar.sh` ya tolera su ausencia («NO HAY»): no hace falta tocarlo.
3. Quitar las menciones en `.agents/context/40-entorno.md` y `20-convenciones.md`.

## Verificación

`bash tests/ejecutar.sh` sale con 0; `verificar.sh` lo ejecuta; ninguna prueba deja nada
fuera de su temporal (`ls -d /tmp/backupctl-pruebas.*` vacío tras la ejecución).
