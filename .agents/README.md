# .agents

Todo lo que un agente necesita para trabajar en este repositorio sin depender de ninguna
sesión anterior. Compartido por todos los proveedores; Claude Code lo ve además a través de
`.claude/` (symlinks y generados).

| Ruta | Contenido |
| :-- | :-- |
| `rules/` | Reglas de comportamiento. Todas se aplican siempre |
| `personas/` | **Fuente** de los subagentes: cuerpo del prompt, sin frontmatter |
| `agents/` | Subagentes para Antigravity, **generados** (no editar) |
| `skills/` | Skills compartidas; `.claude/skills/` enlaza aquí |
| `scripts/` | Verificación, generador de agentes, guarda de hooks, hook de git |
| `context/` | Qué hay y qué muerde. Denso, verdad **hoy** |
| `docs/adr/` | Por qué se decidió así. Inmutables. **Lo más importante para un agente** |
| `docs/bitacora/` | Cómo se llegó hasta ahí, una entrada por tarea cerrada |
| `docs/roadmap.md` | Lo que falta, de donde elige el Product Owner |
| `HERENCIA.md` | **Borrable.** Lo que sabía la sesión que construyó el proyecto y no estaba escrito |

Fuera de aquí: `estado/` (qué pasa ahora, para el PO y para la siguiente sesión),
`AGENTS.md` (entrada genérica), `.claude/CLAUDE.md` (entrada de Claude Code).

## Orden de lectura para una sesión nueva

1. `../estado/AHORA.md` y el último archivo de `../estado/tramos/` — dónde estamos.
2. `rules/` — lo que no se hace nunca y cómo se colabora. `40-salvaguardas.md` entera.
3. `context/10-mapa-del-sistema.md` y `context/30-trampas.md`.
4. `docs/adr/README.md` — el índice; los ADR que toque tu tarea, enteros. Y
   `../docs/desarrollo/decisiones.md`, las decisiones de producto anteriores.
5. `HERENCIA.md` — mientras exista: qué exige el PO y en qué se falló antes.
6. `docs/roadmap.md` — si toca elegir o proponer.

## Documentación para agentes y para personas

| Para | Dónde | Qué |
| :-- | :-- | :-- |
| Personas (usuarios) | `README.md`, `docs/` (sitio MkDocs) | Qué es, cómo se instala, se usa y se recupera un desastre |
| Personas (usuarios) | `CHANGELOG.md` (cuando exista) | Qué cambió, en lenguaje de producto |
| Personas (programadores) | `docs/desarrollo/` | Arquitectura, decisiones de producto, mantenimiento del repositorio |
| El PO | `estado/` | Qué se hizo y qué espera de él |
| Agentes (y quien quiera) | `.agents/docs/adr/` | Por qué se decidió así, qué se descartó |
| Agentes | `.agents/context/` | Rutas, efectos de cada orden, invariantes y trampas |
| Agentes | `.agents/docs/bitacora/` | Qué se probó y falló en cada tarea |

Una sola regla los mantiene sanos: **ninguno puede mentir.** Si un cambio de código
invalida un documento, se corrige en el mismo commit. Si dos se contradicen, gana el
código y se arreglan los dos. Y lo que ya no sirve se poda (`rules/60-estado.md`).

## Cambiar un agente, una regla o una skill

- **Agente**: edita `personas/<nombre>.md` (o `AGENTES` en `scripts/generar_agentes.py`
  para modelo, esfuerzo, herramientas y descripción) y regenera. `verificar.sh` falla si
  quedó desfasado.
- **Regla**: archivo en `rules/` + symlink en `.claude/rules/`.
- **Skill**: carpeta en `skills/` + symlink en `.claude/skills/`.
- **Guarda**: `scripts/guardas/guardia.py` y, siempre, su caso en `probar_guardia.py`.
- Si cambia cómo se trabaja, es estructural: ADR.

## Origen

El andamiaje se trajo el 2026-09-14 de otro repositorio del PO (CustomPluginsHestiaCP) y se
adaptó a este (ADR 0001). Lo que era de aquel proyecto —plugins PHP, `panel.php`,
instaladores, sus ADR y su herencia— se retiró; no se conserva aquí.
