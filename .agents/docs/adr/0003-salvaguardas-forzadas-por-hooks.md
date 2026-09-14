# 0003 — Salvaguardas forzadas por una guarda de hooks

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Arquitecto, con el modelo que trae el PO
- **Estructural:** sí (configuración de alcance global de las sesiones)

## En cristiano

Las reglas dicen qué no debe hacer un agente; esta guarda lo impide. Antes de cada comando,
lectura o escritura de un agente en Claude Code, un pequeño programa lo revisa. Lo bloquea si
toca servidores, MySQL o el almacenamiento remoto, usa `sudo`, ejecuta una orden de
`backupctl` que no sea la ayuda, lee un archivo con credenciales, sube a GitHub, reescribe la
historia de git o firma algo como hecho por una IA. Es una red: lo que la guarda no ve sigue
prohibido por las reglas.

## Contexto

- `backupctl` se despliega en servidores de producción, usa `sudo` y maneja credenciales de
  MySQL, Restic, S3 y SSH. El perfil `TejidoTesting` **tiene esas credenciales versionadas**
  en el árbol (`.agents/context/30-trampas.md` T1), y la URL del remoto lleva un token.
- **Ninguna orden de `backupctl` con perfil es inocua**: ni con `--dry-run` (T4), y sin `-p`
  usan el perfil real (T3). Abrir la web hace ssh al servidor.
- La sesión que construyó el proyecto probaba contra un servidor de pruebas real con permiso
  del PO en cada tanda, y aun así creó un enlace en `~/.local/bin` sin permiso
  (`.agents/HERENCIA.md`).
- El PO trae esta guarda de otro repositorio suyo. Al pegarla, se activó para **todas** las
  sesiones de este directorio, y el mismo día bloqueó un `ssh` de la sesión anterior.
- `00-core.md` exige permiso explícito para `git push` y prohíbe imprimir secretos.
- 31 commits hasta `4435064` llevan una línea `Co-Authored-By` de un asistente, ya subida al
  remoto.

## Decisión

- `.agents/scripts/guardas/guardia.py` como hook `PreToolUse` de `Bash`, `Write`, `Edit`,
  `MultiEdit`, `NotebookEdit`, `Read` y `Grep` en `.claude/settings.json`. Bloquea con código
  2; ante un error interno, también.
- Bloquea, además de lo genérico (sudo, paquetes, escribir fuera del repositorio, git
  destructivo, `git config`):
  - `ssh`, `scp`, `rsync` remoto, clientes MySQL, `restic` y `rclone` (salvo su versión);
  - `backupctl` salvo `--help`, `version` y `profiles`; `web/server.py`;
    `tools/backupctl-escritorio.sh instalar|lanzar`; `mkdocs serve|gh-deploy`; los `v-*`;
  - **todo `git push`**, y `fetch`, `pull`, `ls-remote`, `git remote -v`: usan o muestran la
    credencial del remoto;
  - leer, copiar o editar `env.sh` de perfiles, `output/HestiaCP/`, `ESTADO.md` y
    `.git/config`, también por búsquedas recursivas que los mostrarían;
  - menciones a IA en entregables y en mensajes de commit.
- Patrones de mención a IA en `guardas/patrones.py`, compartidos con `menciones_ia.py`, que
  revisa el árbol y **los commits posteriores a `4435064`** (`BASE_COMMITS`).
- `settings.json`: `attribution` vacía y denegaciones básicas que duplican lo más grave.
- Criterio: ante la duda, bloquear. Cada bloqueo con su caso legítimo en
  `probar_guardia.py`, que corre sobre un repositorio sintético con un perfil falso.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Solo reglas escritas | Dependen de la memoria del modelo; aquí ya se incumplieron (el enlace en `~/.local/bin`) |
| Solo `permissions.deny` | Casa por prefijo: no ve `env X=1 ssh`, heredocs, sustituciones ni rutas dentro de un argumento |
| Permitir las órdenes de `backupctl` con `--dry-run` | Ninguna es inocua (T4) |
| Pedir confirmación al PO en vez de bloquear (`permissionDecision: "ask"`) | La documentación de Claude Code no dice qué hace «ask» en modo automático ni en una sesión sin nadie mirando (consultado el 2026-09-14): **sin verificar**. Candidato si el PO autoriza pruebas en servidor |
| Revisar también los commits anteriores a la adopción | `verificar.sh` fallaría para siempre por una deuda que solo el PO puede saldar reescribiendo historia |
| Hooks de git (`commit-msg`) | Útiles también (existe uno y está en el roadmap), pero activarlos exige `git config`, que es del PO; y no cubren `ssh` ni lecturas |

## Consecuencias

- **El coder no puede comprobar nada contra un servidor.** Lo que antes se probaba en el
  servidor de pruebas ahora se prueba en aislado o lo prueba el PO. Hasta que exista un banco
  de pruebas (roadmap), buena parte del código solo se valida por lectura y sintaxis.
- El PO sube a GitHub él mismo: lo confirmó el 2026-09-14 («Solo yo»).
- Probar en un servidor lo hace el PO (ADR 0006).
- Solo protege sesiones de Claude Code. Otros proveedores dependen de las reglas y de
  `verificar.sh` (y del hook de git cuando el PO lo active).
- **Falla abierto** si `guardia.py` no llega a ejecutarse (un error de sintaxis): Claude Code
  trata ese fallo como no bloqueante. `verificar.sh` corre sus pruebas en cada ronda.
- Falsos positivos posibles (un `grep` cuyo patrón nombra un archivo de perfil existente): se
  resuelven ajustando la guarda y su prueba, nunca esquivándola.
- Residual conocido: `git show`/`git log -p` de commits que tocaron un perfil muestran su
  contenido; la guarda no lo ve. Lo cubre la regla 40 §6.

## Reversión

1. Quitar la entrada `hooks.PreToolUse` de `.claude/settings.json` (o solo `Read|Grep` del
   `matcher`, para dejar de vigilar lecturas).
2. Para permitir `git push`: quitar su bloqueo en `revisar_git` y la denegación en
   `settings.json`, mover sus casos de `BASH_BLOQUEA` a `BASH_PERMITE`, y escribir el ADR que
   lo autoriza.
3. Opcional: borrar `.agents/scripts/guardas/` y el paso «Guarda de hooks» de `verificar.sh`
   (si se borra, `menciones_ia.py` necesita los patrones: moverlos antes).
4. Comprobar que `verificar.sh` pasa.

## Verificación

`python3 .agents/scripts/guardas/probar_guardia.py` → todos los casos correctos.
