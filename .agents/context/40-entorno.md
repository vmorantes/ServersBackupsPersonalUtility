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

## Cómo se prueba sin servidor: el banco (`tests/`, ADR 0009)

```
bash tests/ejecutar.sh      # también lo ejecuta verificar.sh
```

| Pieza | Qué hace |
| --- | --- |
| `tests/ejecutar.sh` | Única entrada. Aborta como root. Crea `/tmp/backupctl-pruebas.XXXXXX` y lo borra al salir. Crea en `<T>/bin` un enlace a `falsos/despachador.sh` por cada orden peligrosa (`ssh scp sftp sshpass ssh-keygen ssh-copy-id rsync mysql mysqldump sudo crontab restic rclone mail curl`). Comprueba que `command -v` de cada una resuelve a `<T>/bin` antes de lanzar nada. Lanza cada `probar_*.sh` con `env -i` (sin `MYSQL_*`, `BC_*` ni `DEPLOY_*` heredados), `HOME` y `TMPDIR` en el temporal, `LANG=C.UTF-8`, y `BANCO_RAIZ`/`BANCO_TMP` |
| `tests/falsos/despachador.sh` | Registra cada invocación en `$BANCO_TMP/registro/<orden>.log`; responde cargando `$BANCO_TMP/guion/<orden>.sh`; sin guion, sale con 97. **No lee la entrada estándar por su cuenta** (backup llama a mysql dentro de un `while read`); solo el guion que lo pide |
| `tests/lib.sh` | `afirmar_*`, `crear_perfil <dir>` (perfil local con todas las variables explícitas y `BACKUP_WORK_DIR` ya creado), `backupctl_prueba <perfil_dir> …` (siempre `-p`, stdin de `/dev/null`, se niega fuera de `$BANCO_TMP`) |
| `tests/probar_<área>.sh` | `perfil`, `respaldo`, `verificacion`, `retencion`, `restauracion` |

Cómo se escribe una prueba nueva:

- Una función `test_…` (inglés) por caso; cuerpo y comentarios en español.
- Guion por prueba en `$BANCO_TMP/guion/`, y registro limpio al empezar cada prueba.
- **Sin terminal, `backup` no escribe nada en stdout ni stderr**: los mensajes están en
  `$LOG_DIR/backup_<fecha>.log`.
- **Una afirmación debe poder fallar**: si se puede, demuéstralo estropeando el código en una
  copia del repositorio en un temporal y viendo la prueba en rojo (mutación). Así se
  encontraron dos afirmaciones que pasaban con el código roto (tramo del 2026-09-14).
- Cubre el camino de fallo con `afirmar_intacto` (`20-convenciones.md`, «Pruebas»).

Qué **no** demuestra el banco: que las respuestas sintéticas coincidan con un MySQL real, que un
`mysqldump` real falle con ese texto, que el SQL sea válido contra un motor real, ni que
`restore` cree nada de verdad (solo que envía el SQL correcto). Eso lo prueba el PO (ADR 0006).

Sin cubrir todavía: `ssh`/`deploy`/`pull`/`remote`, confirmaciones sin terminal (T5), y todo
lo que depende de `/usr/local/hestia` escrito a mano (`hestia`, `adoptar`; T18).

## Verificación del proyecto

```
bash .agents/scripts/verificar.sh
```

Comprueba: `bash -n` de `bin/backupctl` y todos los `.sh` (sin los `env.sh` de perfiles),
ausencia de CRLF, el modo `100755` de `bin/backupctl`, sintaxis Python y JavaScript,
`web/comprobar.py`, que `backupctl --help` arranca, agentes generados al día, symlinks de
`.claude/`, pruebas de la guarda, menciones a IA en entregables y en commits posteriores a la
adopción, y el banco (`tests/ejecutar.sh`). No conecta a nada, no lee credenciales, no escribe
fuera del repositorio salvo el temporal del banco.

No incluye `mkdocs build --strict` (es un build: pendiente de que el PO lo autorice) ni
`shellcheck` (no instalado).
