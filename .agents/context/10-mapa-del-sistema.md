# Mapa del sistema

Verificado en rama `master` (`4435064`), 2026-09-14, leyendo el código. Líneas aproximadas:
si el código se movió, búscalas por el nombre de la función.

## Ramas y remoto

- **`master`** es la única rama de trabajo hasta hoy: los 47 commits se hicieron ahí.
  `backupctl-2.0` y `version-inicial` están contenidas enteras en `master` (0 commits
  propios); son puntos de control viejos. Borrarlas, si acaso, el PO.
- Remoto `origin` en GitHub. **Su URL lleva una credencial**: no se muestra (`git remote -v`,
  `git config --list` y leer `.git/config` están bloqueados por la guarda).

## El repositorio

```
bin/backupctl            Despachador (573 líneas). Carga los 26 módulos de lib/
lib/*.sh                 Toda la lógica. Se sube igual a todos los servidores
web/                     Interfaz web local: server.py (stdlib), app.js, index.html, app.css
  comprobar.py           Comprobación estática de la web (sin red ni subprocess)
  __pycache__/           ¡versionado por error! (roadmap)
tools/backupctl-escritorio.sh   Lanzador de escritorio de la web (escribe en ~/.local/share)
config/env.sh.example    Estructura de un perfil: la ÚNICA referencia que leen los agentes
docs/  mkdocs.yml        Documentación MkDocs para personas; la navegación vive en mkdocs.yml
site/                    Sitio compilado, ignorado por git
README.md  UtilCommands.md
TejidoTesting/           PERFIL REAL del PO: env.sh, Instrucciones.md, output/HestiaCP/
                         Credenciales dentro (30-trampas.md T1). No se lee.
estado/  .agents/  .claude/  .vscode/  AGENTS.md    Trabajo con agentes
```

Módulos de `lib/` (los 16 primeros son los que cuenta `docs/desarrollo/arquitectura.md`;
los 10 siguientes faltan allí): `core config mysql backup verify restore archive restic
retention notify doctor cron logs deploy migrate tui` · `ssh sshkey pull remote setup web
install hestia shield adoptar`. Los mayores: `adoptar.sh` (1483 líneas) y `hestia.sh` (1072).

## Arranque (`bin/backupctl`)

- `set -Eeuo pipefail` (16). Carga los módulos (34-35); al cargarse no ejecutan nada salvo
  `hestia.sh:25,30`, que calcula rutas.
- `-h`, `-V`, `-p`, `-y`, `--debug` se buscan en **todos** los argumentos (201-213):
  `backupctl deploy -h` solo imprime la ayuda.
- Sin perfil: `help`, `version`, `profiles`, `install`, `setup`, `web` (233-268).
- Todo lo demás carga el perfil con `bc_config_load` (273): hace `source` del `env.sh`
  (`config.sh:89`), así que ejecuta lo que tenga y exporta `MYSQL_PASS` a todos los hijos.
- `backup`, `restic` y `migrate` crean el log y toman el bloqueo **antes** de mirar sus
  opciones (278-285).

## Perfiles (`lib/config.sh`)

- Descubrimiento (19-63), por orden: `$BC_ROOT/env.sh` (perfil «local»),
  `$BC_ROOT/servers/*/env.sh`, `$BC_ROOT/*/env.sh`. Excluye `bin lib docs config site .git
  servers node_modules` (35); **no** excluye `web`, `tools` ni directorios nuevos. Los ocultos
  no entran. Un directorio con un `env.sh` dentro se convierte en perfil.
- **Perfil por defecto**: si hay exactamente uno, ese (56-63). Hoy es `TejidoTesting`: toda
  orden sin `-p` usa sus credenciales reales.
- `-p <ruta>/env.sh` acepta un perfil fuera del repositorio (77-78): así se usa un perfil
  sintético en un temporal. La web no lo ve.
- Perfil **remoto** (`DEPLOY_HOST` puesto y `SCRIPTS_DIR` inexistente en esta máquina): sus
  rutas se remapean al directorio del perfil (122-144), así que sus logs y bloqueos caen
  dentro del repositorio.
- `BC_ROOT` sale de la ruta real del script (bin:23-31) y no se cambia desde fuera.

## Qué hace cada orden

Efectos: **L** lee el repositorio · **R** escribe en el repositorio · **S** escribe fuera,
en esta máquina · **N** conecta por ssh/rsync · **M** conecta a MySQL · **H** ejecuta `v-*` de
HestiaCP · **U** usa sudo. El dry-run «parcial» ya ha escrito o conectado antes de mirar la
opción.

| Orden | Efectos | Dry-run |
| --- | --- | --- |
| `help`, `version`, `profiles` | L | — |
| `install [--remove]` | S (`~/.local/bin` o `~/bin`), U si no hay ninguno en el PATH (`install.sh:64`). Sin terminal confirma «sí» | no |
| `setup` | N, M (`CREATE USER`, `GRANT`), R (`env.sh`), luego `deploy`; con `BC_SETUP_NAME` entra en modo desatendido en silencio | no |
| `web` | Proceso en 127.0.0.1:8787 que ejecuta backupctl | — |
| `backup` | R/S, M, borra por retención | parcial (`backup.sh:265-331`) |
| `verify [--restore-test]` | L; con `--restore-test`, M (`CREATE`/`DROP DATABASE verifybk_*`) | no |
| `restore` | M escribe | casi real: conecta y consulta (`restore.sh:36,74`) |
| `list`, `inspect`, `status`, `doctor` | L; M o `sudo -n` solo con perfil local | — |
| `restic` | exige root; escribe `Restic_Configs_*` | parcial; solo como primer argumento |
| `retention` | borra archivos | real; solo como primer argumento |
| `cron --install/--remove` | S (crontab) o H+U. Sin terminal `--install` confirma «sí» | no |
| `config --show-secrets` | **imprime `MYSQL_PASS`** | — |
| `deploy` | N, U remoto (`apt-get`, `rsync --delete`, copia de `env.sh`) | real en remoto, pero conecta y escribe `~/.ssh/known_hosts` |
| `sshkey` | S (`~/.ssh/id_ed25519`), N (`authorized_keys`), R (`env.sh`) | no |
| `pull` | N; R: `ESTADO.md` (**con el diff del `env.sh`**), `NOTAS.md`, `env.sh` | real en local, pero lee por ssh |
| `remote <orden…>` | N; ejecuta cualquier orden en el servidor, U para `restic` y `cron` | no |
| `migrate --to` | N, M local y remoto | parcial (`migrate.sh:47,79-91`) |
| `shield`, `hestia status/users/dbs` | N, U, M remoto (un cnf con la contraseña vive un momento en el servidor, `hestia.sh:808-835`) | — |
| `hestia rclone/restic/cron` | H, U; escriben en el servidor | sí |
| `hestia keys` | R: `<perfil>/output/HestiaCP/` (claves) | no, ni en `hestia setup --dry-run` |
| `adoptar*` | N, H, U, M, restic contra el S3; pisa `conf/restic.conf` del destino durante la operación | parcial |
| `notify-test` | red: correo, `curl`, `NOTIFY_COMMAND` | no |

Fuera de `bc_usage`: `adoptar*` y `exec-count`.

## La web (`web/server.py`)

- Escucha en `127.0.0.1:8787` (1010-1011); token por arranque en la URL (40, 1042-1049); la
  API exige host local y token (667-675). `--open` abre el navegador.
- Ejecuta `backupctl` con `subprocess` y lista de argumentos, sin shell. `build_argv`
  (220-258) añade siempre `--no-color -y -p <perfil>`: **toda confirmación dice «sí»**.
- Lista blanca de acciones `A` (86-212); su tercer campo («¿escribe?») no se usa al ejecutar,
  y `NECESITA_ROOT` (216-217) no se usa en ningún sitio.
- **Al seleccionar un perfil** la página llama a `/api/probe` y `/api/hestia-estado`: ssh real
  al servidor (`app.js:378-387`).
- `/api/config-raw` devuelve el `env.sh` entero al navegador (755-771);
  `/api/config-save` lo reescribe dejando `.anterior` (833-861).

## En el servidor

`deploy` deja en `/home/<usuario>/scripts/` una copia de `bin/` y `lib/` (idénticas en todos
los servidores) y el `env.sh` del perfil; `logs/` y `output/` se generan allí (`README.md`,
«Los dos sentidos»).

## Agentes

Ver `.agents/README.md`. Piezas ejecutables: `.agents/scripts/verificar.sh`,
`generar_agentes.py`, `menciones_ia.py`, `guardas/guardia.py` (+ `probar_guardia.py`,
`patrones.py`), `git-hooks/commit-msg`.
