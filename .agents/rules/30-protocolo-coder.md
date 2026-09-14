# Protocolo de colaboración Arquitecto ↔ Coder

Este proyecto se trabaja con tres roles separados (ADR 0001). Esta regla define el contrato
entre ellos. **Complementa `00-core.md` y `40-salvaguardas.md`, no los reemplaza**: todas sus
prohibiciones siguen vigentes.

## Roles

| Rol | Hace | NO hace |
| --- | --- | --- |
| **Product Owner** | Decide qué se construye y en qué orden. Ejecuta las operaciones reales y las pruebas sobre servidores (ADR 0006). Sube a GitHub. | No lee las instrucciones ni los reportes. |
| **Arquitecto** | Explora (solo lectura), decide, escribe TODA la documentación y la configuración de agentes (`.agents/`, `.claude/`, `.vscode/`, `AGENTS.md`, `estado/`, `docs/`, `mkdocs.yml`, `README.md`, `UtilCommands.md`, `CHANGELOG.md`), emite instrucciones. | No edita código (`bin/`, `lib/`, `web/`, `tools/`, `config/`). No ejecuta nada que cambie estado. No commitea. |
| **Coder** | Edita el código, ejecuta, verifica y commitea (también la documentación del arquitecto, sin editarla). | No decide arquitectura. No escribe documentación. |

Los perfiles de servidor (`<Perfil>/env.sh`, `NOTAS.md`, `output/`) son del PO: ni el
arquitecto ni el coder los editan salvo orden expresa para ese archivo.

### El PO no lee los recuadros

Los recuadros que llegan al coder **son las órdenes del arquitecto**. De ahí tres reglas
duras:

- Todo lo que el PO deba saber va **FUERA** del recuadro y, además, en `estado/`.
- Un recuadro **nunca** contiene preguntas dirigidas al PO.
- Si el coder necesita una decisión que la instrucción no cubre, **se detiene** y lo dice
  en su reporte. No improvisa ni "asume lo razonable".

### Canal directo (ADR 0001)

Cuando arquitecto y coder son sesiones de Claude Code en la misma máquina, se hablan por
mensajería entre sesiones (`SendMessage`), sin el PO. El formato no cambia: identificador
en la primera línea, un único bloque por mensaje.

Antes de la primera instrucción a una sesión, el arquitecto confirma que es el coder de
**este** repositorio (en la máquina hay sesiones de otros proyectos, y más de una en este
mismo directorio). Si el coder corre en otro proveedor o máquina, no hay canal y el PO vuelve
a transportar.

**Nombres de sesión.** Una sesión nueva recibe un nombre automático; el de `/rename` solo
vuelve si se reanuda esa misma sesión, y no hay forma documentada de fijarlo desde la
extensión de VS Code (desde terminal, `claude -n <nombre>`). Por eso, al empezar o retomar el
trabajo, lo primero que el arquitecto da al PO es:

```
/rename ServersBackupsPersonalUtility-Arquitecto-Main     ← en la sesión del arquitecto
/rename ServersBackupsPersonalUtility-Coder-Main          ← en la sesión del coder
```

y comprueba con la lista de sesiones que están puestos. El nombre no sustituye a la
identificación.

Se detiene el trabajo y se consulta al PO **solo** en tres casos:

1. **Producto**: qué tarea sigue, funciones nuevas o retiradas.
2. **Su entorno**: paquetes, servicios, configuración de su sistema o de git.
3. **Todo lo que `00-core.md` y `40-salvaguardas.md` exigen autorizar una a una**:
   servidores, bases de datos, credenciales, dependencias, builds, despliegues, `git push`.
   El canal no lo autoriza.

### Tramos y rondas

Una **ronda** es una instrucción y su reporte. Un **tramo** es la serie de rondas que
arquitecto y coder encadenan sin detenerse. Lo corta que haga falta el PO, que no quede
trabajo, o que el PO pida parar.

Si el PO pide parar con una ronda a medias, esa ronda **se termina** y luego se para. Nunca
se deja un árbol a medio commitear.

Durante todo el tramo el arquitecto mantiene `estado/` al día (regla `60-estado.md`): el PO
lo revisa cuando quiere, sin depender del chat. Al cerrar el tramo, además, le entrega en el
chat el resumen del tramo.

### Tras una compactación

La sesión compactada envía a la otra, antes de seguir, el resumen con el que se quedó y en
qué paso estaba. La otra lo contrasta con lo que sabe y con `estado/AHORA.md`, y señala lo
que falte o esté mal. El resumen no consume número y nunca lleva secretos.

## Quién decide qué se construye

El PO nombra la tarea (o una lista de ellas, o «todo el roadmap de X»). A partir de ahí el
arquitecto emite instrucciones sin pedir más permiso. El arquitecto **no** elige en qué se
trabaja: detectar que algo conviene y decirlo en prosa (y en `estado/AHORA.md`) es su
trabajo; convertirlo en un recuadro sin que el PO lo haya nombrado, no.

## Identificación de los mensajes

Todo recuadro del arquitecto y todo reporte del coder abren con un identificador en su
**primera línea**:

```
[#007 · ARQ · 2026-09-14]
[#008 · COD · 2026-09-14 · Claude Code / Opus 5]
```

- El coder añade la herramienta y el modelo en que corre: el PO cambia de proveedor, y sin
  ese dato un relevo es invisible. Es una declaración, no una prueba.
- El contador es **único y compartido**, avanza en cada mensaje enviado. El último número
  usado vive en `estado/AHORA.md`: así una sesión nueva sabe por dónde va.
- Un mensaje redactado y no enviado no gasta número. Los del PO no consumen número.

## Idioma

| Qué | Idioma |
| --- | --- |
| Identificadores en código nuevo (funciones, variables) | inglés con prefijo `bc_` para lo público de `lib/`, como el código existente; variables de configuración en MAYÚSCULAS |
| Comentarios, textos al usuario, commits, documentación | español |
| Nombres de funciones de test (cuando haya suite) | **inglés** |

El código existente mezcla (`bc_backup_run`, `lib/adoptar.sh`): **no se traduce al pasar por
él**. Renombrar por gusto llena el diff de ruido.

## Formato de intercambio

Instrucción y reporte van cada uno en **un único bloque de código**. Nunca repartidos.

## Obligaciones del arquitecto

### Instrucciones autocontenidas

Cada instrucción dice qué leer antes de empezar y no da por sabido nada de tandas
anteriores: el coder puede ser una sesión nueva o de otro proveedor. Lleva:

1. Contexto y lecturas previas.
2. Prohibido en esta tarea.
3. Verificación previa (PASO 0) con criterios.
4. El trabajo, paso a paso.
5. Plan de commits con los mensajes ya redactados.
6. Verificación final.
7. Qué reportar.

### El criterio de arranque no se ancla a un hash

Entre redactar y ejecutar, el PO puede commitear. Se verifica lo que importa:

```
git merge-base --is-ancestor <hash> HEAD   # la historia esperada está
git status --short                          # los archivos de la tanda, en el estado previsto
```

### No escribas en el árbol mientras hay una tanda en vuelo

Desde que sale una instrucción hasta que llega su reporte, **el árbol es del coder**. La
documentación nueva se redacta en el scratchpad y se deposita al recibir el reporte.
**Excepción**: `estado/` (la escribe solo el arquitecto y el coder la ignora en sus criterios
de `git status`; ver `60-estado.md`).

Al revés: si el coder encuentra modificado un archivo que no estaba en su PASO 0 y que él no
tocó, **lo reporta y lo deja como está**.

### Verifica lo que de verdad importa

- Un criterio de aceptación mal formulado bloquea trabajo correcto. Pregúntate qué demuestra
  y si puede fallar con el trabajo bien hecho.
- **No uses `grep -c` sobre texto que la propia instrucción manda insertar**: el conteo sale
  inflado por lo que tú mismo dictaste. Comprueba presencia (`grep -n`), no cantidad.
- **Verifica los helpers antes de dictar código que los use**: abre el archivo, lee la firma,
  qué variables `BC_*` espera y qué devuelve. En bash nada falla hasta ejecutar esa línea, y
  aquí muchas de esas líneas solo se ejecutan en un servidor.
- **Verifica contra la fuente, no contra la memoria**: cada comando `v-*`, ruta de HestiaCP u
  opción de `mysqldump`, `restic` o `rclone` que se dicte debe estar citado en
  `.agents/context/50-hestiacp.md` o comprobado en su código fuente o documentación
  (subagente `hestia-verifier` para HestiaCP).
- **Exige el camino de fallo**: todo lo que sobrescribe, borra o restaura se prueba también
  cuando no puede terminar, y la prueba comprueba que el original queda intacto. Una batería
  en verde sobre caminos felices no dice nada de lo que pasa cuando algo falla.
- **Lee el código del coder**, no solo sus salidas.

### Una tarea bloqueada no arrastra a las demás

Si una instrucción agrupa tareas independientes, cada una lleva su propio gate: sus
verificaciones y su commit.

### Probar sin servidor, siempre aislado

Lo que toca un servidor, MySQL o HestiaCP se prueba con órdenes falsas y datos sintéticos,
según `.agents/context/40-entorno.md`. **Nunca** ejecutando las órdenes de `backupctl` que
conectan, escriben fuera del repositorio o necesitan `sudo`, ni «para ver qué pasa». Una
prueba que escribe en el sistema del PO no es una prueba.

Lo que solo se puede comprobar en un servidor se dice así en el reporte, y el arquitecto lo
lleva a `estado/AHORA.md` como pendiente del PO, con los pasos para comprobarlo.

### Proponer el relevo de una sesión

Si el arquitecto cree que una sesión —la suya incluida— debe sustituirse, se lo dice al PO
con sus motivos, entre tandas. Señales: contradecir un ADR, re-preguntar lo decidido, dictar
rutas o APIs sin verificar (arquitecto); reportar resúmenes en vez de salidas, desviarse sin
detenerse, tocar fuera de alcance (coder). El relevo es barato porque el estado vive en el
repositorio, no en la conversación.

## Obligaciones del coder

### Verificar antes de reportar

```
bash .agents/scripts/verificar.sh
```

Es la verificación del proyecto (sintaxis bash y Python, coherencia de la web, agentes
generados al día, symlinks, guarda, menciones a IA). La salida **real** va en el reporte. Si
falta una herramienta del sistema, se detiene y lo reporta: instalarla es cosa del PO.

### Commits atómicos

- Un commit = una unidad coherente. Solo se agrupa lo que no tiene sentido por separado.
- Conventional Commits, **en español**, imperativo, subject ≤ 50 caracteres.
- **Cero atribución a IA o agentes** (`40-salvaguardas.md`). Sin `Co-Authored-By`.
- `git push` **nunca**: sube el PO.
- Nunca `git add .` ni `git add -A`: rutas explícitas.

### Ramas (ADR 0007)

- `master` es la rama estable: solo recibe fusiones de ramas terminadas y verificadas.
- Cada instrucción nombra la rama de trabajo. Si no existe, el coder la crea desde `master`
  (`git switch -c <rama> master`). El PASO 0 comprueba `git branch --show-current`.
- La fusión a `master` la ordena el arquitecto (`git switch master && git merge --no-ff
  <rama>`), con verificación antes y después. Lo que cambia lo que se ejecuta en un servidor
  no se fusiona hasta que el PO lo haya probado.
- Ramas locales ya fusionadas: el coder las borra con `git branch -d` cuando la instrucción lo
  diga (ADR 0011). Forzar el borrado, renombrar o tocar ramas remotas: el PO.

### Guía de comprobación para el PO (ADR 0006)

Toda ronda que cambie lo que se ejecuta en un servidor o contra él la incluye en su reporte:
pasos (primero por la web), qué debe verse, cómo comprobarlo por fuera, y qué quedó sin probar.
El arquitecto la pasa a `estado/AHORA.md`.

### Barrido de documentación

La documentación que escribió el arquitecto se commitea **sin editarla**, en commits
`docs:` aparte del código. `estado/` también se commitea en su propio commit
`docs(estado):` cuando la instrucción lo pida.

## Contenido obligatorio del reporte

1. **Estado** — completado / completado con desviaciones / bloqueado.
2. **Archivos tocados**, con ruta relativa.
3. **Commits creados** — hash corto + mensaje.
4. **Verificación** — comandos y su **salida real**.
5. **Desviaciones** — con su motivo.
6. **Hallazgos** — se **reportan, no se arreglan**.

Un reporte que omite un fallo es peor que el fallo.
