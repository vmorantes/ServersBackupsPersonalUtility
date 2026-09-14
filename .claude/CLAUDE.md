# Claude Code — instrucciones del proyecto

**ServersBackupsPersonalUtility** («Respaldos HestiaCP» para quien lo usa): `backupctl`, una
herramienta bash que respalda, verifica, restaura y migra bases de datos y cuentas de
servidores HestiaCP, con una interfaz web local en Python. Se despliega en servidores de
producción y maneja credenciales. **Aquí no hay servidor**: nada se ejecuta contra uno.

## Antes de tocar nada

1. `estado/AHORA.md` — qué está pasando ahora y qué número de mensaje toca.
2. `.agents/README.md` — el mapa de todo lo demás y el orden de lectura.

Las reglas de `.agents/rules/` ya están cargadas (ver abajo). Las que no se negocian:
`40-salvaguardas.md`.

## Lo imprescindible

```
bash .agents/scripts/verificar.sh
```

- Ningún servidor, MySQL, `restic` ni `rclone`; ningún `sudo`. De `backupctl`, solo
  `--help`, `version` y `profiles`: el resto usa un perfil real, y ningún `--dry-run` es
  inocuo.
- **Credenciales dentro del árbol**: los `env.sh` de los perfiles, `<Perfil>/output/HestiaCP/`,
  `ESTADO.md` y `.git/config` no se leen ni se imprimen. La estructura está en
  `config/env.sh.example`.
- Ningún cambio de git sin orden. `git push`, nunca (lo hace el PO).
- Cero menciones a IA en `bin/`, `lib/`, `web/`, `tools/`, `config/`, `docs/`, `README.md`,
  `UtilCommands.md`, `mkdocs.yml` y commits.
- Nada inventado sobre HestiaCP: se verifica (subagente `hestia-verifier`) o se dice.
- El repositorio manda sobre la memoria de la sesión (`10-memory-contract.md`).

---

Lo que sigue es específico de Claude Code. Las reglas núcleo viven en `.agents/rules/`,
compartidas con otros proveedores; el punto de entrada para ellos es `AGENTS.md`.

## Cómo está montado

| Ruta | Qué es | Se edita |
| --- | --- | --- |
| `.claude/rules/*.md` | Symlinks a `.agents/rules/*.md` | En `.agents/rules/` |
| `.claude/skills/*` | Symlinks a `.agents/skills/*` | En `.agents/skills/` |
| `.claude/agents/*.md` | **Generados** desde `.agents/personas/` | Nunca a mano: `python3 .agents/scripts/generar_agentes.py` |
| `.claude/settings.json` | Guarda de hooks, denegaciones, atribución vacía | Aquí (ADR 0003) |
| `.claude/settings.local.json` | Ajustes personales | Ignorado por git |

Una regla nueva: se crea en `.agents/rules/` y se enlaza con
`ln -s ../../.agents/rules/<archivo> .claude/rules/<archivo>`. Una skill, igual en
`.claude/skills/`. `verificar.sh` falla si falta un enlace.

Reglas con alcance por ruta: frontmatter `paths:` (lista de globs) para que solo carguen
al tocar esos archivos.

## Subagentes

Nueve, con modelo y esfuerzo por tarea (ADR 0002). **Nunca `fable`**. Se disparan solos
según su `description`; los que deben usarse sin que se pidan dicen `PROACTIVELY`:

| Agente | Modelo / esfuerzo | Cuándo |
| --- | --- | --- |
| `explorer` | haiku / low | Antes de cambios de más de un archivo |
| `architect` | opus / high | Antes de un cambio estructural |
| `hestia-verifier` | sonnet / high | Antes de depender de un comportamiento de HestiaCP no citado |
| `code-reviewer` | opus / high | Tras modificar `bin/`, `lib/`, `web/` o `tools/`, antes de commitear |
| `security-auditor` | opus / xhigh | Si cambian deploy, remote, ssh, adoptar, hestia, setup o la web; antes de entregar una versión |
| `debugger` | opus / high | Ante un fallo concreto |
| `test-writer` | sonnet / medium | Tras implementar algo sin prueba |
| `doc-writer` | sonnet / medium | Cuando un cambio deja documentación desactualizada |
| `context-curator` | sonnet / medium | Al cerrar un tramo |

## Guarda de hooks

`.agents/scripts/guardas/guardia.py` corre antes de cada `Bash`, `Write`, `Edit`, `Read` y
`Grep`, y bloquea lo que viola `40-salvaguardas.md` (servidores, MySQL, almacenamiento
remoto, `sudo`, órdenes de `backupctl` con perfil, lectura de credenciales, `git push` y git
destructivo, rutas del sistema, menciones a IA en entregables). Sus pruebas:
`python3 .agents/scripts/guardas/probar_guardia.py`. Si bloquea algo legítimo, no se esquiva:
se dice, y el arquitecto ajusta la guarda con su prueba.

## Verificar el puente de reglas

```
git ls-files -s .claude/rules .claude/skills   # todas las líneas deben empezar por 120000
ls -la .claude/rules/ .claude/skills/          # SIN truncar con head
```

Un `100644` significa que el symlink se materializó como copia (clon con
`core.symlinks=false`) y las reglas divergirán en silencio. Para afirmar que algo **no**
existe hace falta la salida completa.
