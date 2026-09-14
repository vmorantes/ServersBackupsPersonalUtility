# 0002 — Subagentes generados desde personas, con modelo y esfuerzo por tarea

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Arquitecto, con mandato del PO
- **Estructural:** sí (cómo se trabaja)

## En cristiano

Cada subagente se escribe una sola vez, como «persona», en `.agents/personas/`. Un script
genera a partir de ella el archivo que entiende Claude Code y el que entiende Antigravity,
cada uno con su formato. Así todos los proveedores usan el mismo agente, y cada tarea va a un
modelo proporcionado a lo que cuesta equivocarse en ella.

## Contexto

- El PO trae este andamiaje de otro repositorio suyo (CustomPluginsHestiaCP), donde se decidió
  igual. Aquí se adapta al proyecto: `backupctl` en bash más una web local en Python.
- Claude Code y Antigravity leen agentes con frontmatter distinto (nombres de herramientas,
  modelos); un symlink no sirve.
- El PO pidió modelos y esfuerzo adecuados a cada tarea, reglas de autodisparo claras, y
  **nunca** el modelo `fable`.
- La documentación de Claude Code lista `effort` para skills pero no para subagentes. El
  cargador de subagentes de Claude Code 2.1.238 sí lo lee (comprobado en el binario, en el
  otro repositorio; aquí **sin volver a verificar**).

## Decisión

- Fuente: `.agents/personas/<nombre>.md` + `_comun.md` (reglas comunes que se anexan a todos).
- Configuración (descripción, herramientas, modelo, esfuerzo) en `AGENTES` de
  `.agents/scripts/generar_agentes.py`. Salidas: `.claude/agents/` y `.agents/agents/`.
- `verificar.sh` falla si lo generado está desfasado; el generador aborta si alguien pone
  `fable`.
- Reglas y skills, que sí son idénticas, se comparten por symlink.

| Agente | Claude | Antigravity | Por qué |
| --- | --- | --- | --- |
| architect, code-reviewer, debugger | opus / high | pro | Un error aquí acaba en un respaldo que no restaura |
| security-auditor | opus / xhigh | pro | El código corre con privilegios en servidores con datos de clientes y maneja credenciales |
| hestia-verifier | sonnet / high | flash | Lectura precisa de código ajeno; no decide |
| test-writer, doc-writer, context-curator | sonnet / medium | flash | Trabajo acotado con criterio |
| explorer | haiku / low | flash | Búsqueda mecánica |

Autodisparo: la `description` dice cuándo (`Use PROACTIVELY ...`) y cuándo no.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Editar a mano cada formato | Divergen en silencio |
| Configuración en frontmatter YAML dentro de la persona | Exige un parser YAML (dependencia) o uno casero frágil; el diccionario Python se valida al ejecutarse |
| Un solo modelo para todo | O caro en búsquedas triviales o flojo en auditorías |
| Copiar tal cual los agentes del otro repositorio | Hablan de plugins PHP, `panel.php` e instaladores que aquí no existen: un agente los tomaría como verdad |

## Consecuencias

- Cambiar un agente exige regenerar; `verificar.sh` lo recuerda.
- Si una versión de Claude Code deja de aceptar `effort` en subagentes, se ignorará o
  fallará al cargar: comprobarlo tras actualizar Claude Code.
- Los dos repositorios del PO comparten el diseño pero no los archivos: una mejora en uno no
  llega sola al otro.

## Reversión

1. Borrar `.claude/agents/*.md` y `.agents/agents/*.md` (generados; se pueden regenerar).
2. Si se abandona el generador: copiar los generados a mano antes de borrarlo, y quitar el
   paso «Subagentes generados al día» de `verificar.sh`.
3. Comprobar que `/agents` en Claude Code lista lo esperado.

## Verificación

`python3 .agents/scripts/generar_agentes.py --check` → «agentes al día».
