# Salvaguardas del proyecto

Complementa `00-core.md`. Aquí lo específico de un repositorio cuyo código **se despliega en
servidores HestiaCP de producción, corre a veces con `sudo`, maneja credenciales de MySQL,
Restic, S3 y SSH**, y cuyos perfiles de servidor, versionados, contienen esas credenciales.
Aplica a toda sesión, rol y proveedor. Decisión y alcance: ADR 0003.

Parte de esto está además **forzado por máquina** en Claude Code
(`.agents/scripts/guardas/guardia.py`, enganchado en `.claude/settings.json`). Que la guarda
no bloquee algo **no** lo autoriza: la regla es esta, la guarda es una red.

## 1. Servidores, bases de datos y almacenamiento remoto

- **Ningún agente se conecta a un servidor, a MySQL ni al almacenamiento remoto**: nada de
  `ssh`, `scp`, `sftp`, `rsync` remoto, `sshpass`, `mysql`, `mysqldump`, `restic`, `rclone`.
- **Tampoco a través del proyecto**: de `backupctl` solo se ejecutan `--help`, `version` y
  `profiles`. Todas las demás órdenes cargan un perfil real y pueden conectar, escribir o usar
  `sudo`, y **ningún `--dry-run` está libre de efectos** (`.agents/context/30-trampas.md`).
  Tampoco se lanza `web/server.py`: ejecuta `backupctl` con `-y` y hace `ssh` a los perfiles
  en cuanto se abre la página.
- **Tampoco contra el servidor de pruebas** (ADR 0006): lo que solo se comprueba en un
  servidor lo prueba el PO con una guía de la ronda. Antes de la adopción un agente probaba
  allí con permiso por tanda (`.agents/HERENCIA.md`); el PO lo cerró el 2026-09-14.
- Si hace falta un dato de un servidor, se **pide al PO** el comando exacto y de solo
  lectura, y se espera su salida. Nunca se da por buena una suposición en su lugar.
- Los nombres de servidor, cuentas, dominios, bases de datos e IPs reales del PO **no se
  escriben** fuera de los directorios de perfil. En ejemplos: `example.org`,
  `sub.example.org`, `203.0.113.10` (RFC 5737).

## 2. El sistema local

- Nada de `sudo`, `su`, `pkexec`, gestores de paquetes (`apt`, `dpkg -i`, `snap`,
  `pip install`, `npm -g`, `composer global`), `systemctl`, `crontab`, `mkfs`, `dd`,
  `shutdown`.
- **Nunca se ejecuta** lo que escribe en el sistema del PO, ni «para probar»:
  `backupctl install`, `backupctl cron --install`, `backupctl web`,
  `tools/backupctl-escritorio.sh instalar|lanzar`, `mkdocs serve`, `mkdocs gh-deploy`. Ya pasó:
  una «prueba» de `backupctl install` creó `~/.local/bin/backupctl` sin permiso.
- Nada de escribir fuera del repositorio salvo el scratchpad de la sesión y `/tmp`.
- Borrados recursivos solo dentro del repositorio o de un temporal propio, y nunca sobre
  algo no versionado sin haberlo leído antes: lo no versionado no se recupera. Mejor mover a
  un temporal que borrar.

## 3. Git

- Lo de `00-core.md`, más: nada de `reset --hard`, `clean -f`, `checkout -- .`, `restore .`,
  `rebase`, `commit --amend`, `branch -D`, `filter-branch`/`filter-repo`.
- **`git push` lo hace solo el PO** (decidido el 2026-09-14; lo bloquea la guarda). `fetch`,
  `pull`, `ls-remote` y `git remote -v` tampoco: usan o muestran la URL del remoto, que lleva
  una credencial.
- `git config` no se toca: es configuración del entorno del PO.
- **`master` es la rama estable** (ADR 0007): se trabaja en ramas propias, que el coder crea,
  commitea y fusiona con `--no-ff` cuando la instrucción lo ordena y se cumplen los criterios
  del ADR. Borrar o renombrar ramas, el PO.

## 4. Cero menciones a IA en lo que se entrega

El PO firma este código. Nada entregable dice ni sugiere que lo escribió una IA:

- **Prohibido** en código (`bin/`, `lib/`, `web/`, `tools/`, `config/`), en `docs/`,
  `README.md`, `UtilCommands.md`, `mkdocs.yml`, `CHANGELOG.md`, commits, ramas, tags y PRs:
  `Co-Authored-By`, "Generated with/by", "generado por IA", nombres de modelos o proveedores
  (Claude, Anthropic, GPT, OpenAI, Copilot, Gemini…), emojis de robot.
- **Permitido** solo donde el tema *son* los agentes: `.agents/`, `.claude/`, `AGENTS.md`,
  `estado/`. Ahí se habla de agentes con normalidad.
- Comentarios de código: explican el porqué del código, no quién lo escribió ni con qué.
- **Deuda conocida**: 31 commits anteriores a la adopción (hasta `4435064`) llevan una línea
  `Co-Authored-By`, y ya están en el remoto. El PO decidió dejarlos (2026-09-14): reescribir
  la historia sería destructivo. La comprobación empieza después de ese commit.

Comprobación: `python3 .agents/scripts/menciones_ia.py` (lo corre `verificar.sh`).

## 5. Datos verídicos

- **Ningún éxito sin comprobación independiente.** Esta herramienta ya ha dicho «enviado» sin
  enviar y ha dado éxitos en falso. Un respaldo, una restauración o una migración se dan por
  buenos cuando lo confirma algo que no es el mensaje de la propia orden: conteos, sumas,
  el panel.
- Un valor que el código muestra al usuario sale del servidor o del respaldo. Si no se puede
  obtener, se dice **explícitamente** que no está disponible. Nunca un placeholder que parezca
  un dato.
- Una afirmación técnica sobre HestiaCP, MySQL, Restic o rclone se apoya en su código fuente,
  su documentación o una salida real. Si no se pudo verificar, se escribe «sin verificar», no
  se redondea a un hecho.

## 6. Credenciales y datos del PO

Lo de `00-core.md`. Además, en este repositorio las credenciales **están dentro del árbol**,
por decisión del PO (ADR 0008: repositorio de uso propio). No se propone sacarlas:

- **No se leen, no se imprimen, no se copian, no se editan**: los `env.sh` de los perfiles (y
  sus `env.sh.anterior` / `env.sh.nuevo`), `<Perfil>/output/HestiaCP/`, `<Perfil>/ESTADO.md`
  (lleva el diff del `env.sh`) y `.git/config` (la URL del remoto lleva un token). La
  estructura de un perfil está en `config/env.sh.example`.
- **Cuidado con lo que los muestra de rebote**: búsquedas recursivas sobre la raíz (se
  limitan a `bin/ lib/ web/ tools/ docs/ config/ .agents/`, o `-l` para ver solo nombres),
  `git show` o `git log -p` de commits que tocaron un perfil, `backupctl config
  --show-secrets`, `/api/config-raw` de la web.
- Si un secreto aparece en una salida, no se repite en ningún mensaje ni documento; se avisa
  al PO de dónde salió.
- Los datos de prueba son sintéticos. Nunca se commitea un ejemplo real.

## 7. Lo que el PO exige del producto

Requisitos de producto que valen para todo lo que se añada; detalle en
`.agents/context/20-convenciones.md`:

- **La interfaz web es el centro**; la CLI es para servidores y cron. Todo lo que hace
  `backupctl` se puede hacer desde la web, con un botón por acción.
- **Estados claros y no destruir**: mostrar lo que ya hay antes de ofrecer una acción, y
  nombrar lo que se pierde antes de pisarlo.
- **Las operaciones reales las ejecuta el PO**: los agentes preparan, prueban en aislado y le
  entregan una guía que separa lo probado de lo no probado, con los pasos de la web primero.
