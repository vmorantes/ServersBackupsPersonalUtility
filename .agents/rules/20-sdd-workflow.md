---
trigger: model_decision
description: Se activa con tareas grandes o cambios sustanciales que se benefician de planificación estructurada por fases (spec-driven development) — comandos /sdd-*, o cuando yo pida "planifiquemos esto por fases"
---

# SDD — Spec-Driven Development (agnóstico)

Capa de planificación estructurada para cambios sustanciales. No asumas ningún backend de memoria ni orquestador de sub-agentes concreto — la persistencia de artefactos sigue el contrato de `10-memory-contract.md`.

## Grafo de dependencias entre fases

```
explore -> proposal -> spec --> tasks -> apply -> verify -> archive
                         ^
                         |
                       design
```

## Fases

| Fase | Qué hace | Lee | Produce |
| --- | --- | --- | --- |
| `explore` | Investiga una idea; compara approaches; no crea archivos de producción | nada | notas de exploración |
| `propose` | Propone el cambio con su razonamiento | exploración (opcional) | propuesta |
| `spec` | Redacta la especificación formal | propuesta (requerido) | spec |
| `design` | Decisiones de arquitectura para el cambio | propuesta (requerido) | diseño |
| `tasks` | Desglosa en tareas ejecutables | spec + design (requerido) | lista de tareas |
| `apply` | Implementa las tareas en lotes, marcando progreso | tasks + spec + design + progreso previo (si existe) | progreso de implementación |
| `verify` | Valida la implementación contra la spec | spec + tasks + progreso | reporte: CRITICAL / WARNING / SUGGESTION |
| `archive` | Cierra el cambio y persiste el estado final | todos los artefactos | reporte de cierre |

## Regla de "¿esto infla el contexto sin necesidad?"

| Acción | Inline (misma fase) | Requiere fase propia |
| --- | --- | --- |
| Leer para decidir/verificar (1-3 archivos) | ✅ | — |
| Leer para explorar/entender (4+ archivos) | — | ✅ fase `explore` |
| Leer como preparación de una escritura | — | ✅ misma fase que la escritura |
| Escritura atómica (un archivo, mecánica, ya sabes qué) | ✅ | — |
| Escritura con análisis (varios archivos, lógica nueva) | — | ✅ fase `apply` |
| Comandos de estado (git status, git log) | ✅ | — |
| Comandos de ejecución (test, build, install) | — | ✅ fase `verify` |

Si una tarea grande se puede resolver leyendo/escribiendo poco, no la conviertas en un ciclo SDD completo — esto es para cambios sustanciales, no para todo.

## Modo de ejecución

Al iniciar un flujo SDD por primera vez en la sesión, pregunta qué modo prefiero:

- **Automático**: corre todas las fases en secuencia sin pausar, muestra solo el resultado final. Úsalo cuando priorizo velocidad y confío en el proceso.
- **Interactivo** (default si no especifico): después de cada fase, muestra un resumen de lo que produjo, qué hará la siguiente fase, y pregunta si continuamos, ajustamos algo, o paramos.

Cachea mi elección para el resto de la sesión — no vuelvas a preguntar salvo que yo pida cambiar de modo.

## Profundidad de razonamiento por fase

No asumas un modelo concreto — esto es una guía de cuánta profundidad necesita cada fase, para que la ajustes a lo que tengas disponible:

| Fase | Profundidad |
| --- | --- |
| orquestador general | Arquitectónica profunda — coordina y decide |
| explore | Estructural — lee y entiende, no decide arquitectura |
| propose | Arquitectónica — decisiones de diseño |
| spec | Escritura estructurada |
| design | Arquitectónica |
| tasks | Mecánica — desglose |
| apply | Implementación |
| verify | Validación contra spec |
| archive | Mecánica — copiar y cerrar |

## Persistencia de artefactos

Cada artefacto de fase se guarda siguiendo el contrato de `10-memory-contract.md` (qué/por qué/dónde/aprendido), bajo una referencia estable por cambio — por ejemplo `sdd/{nombre-del-cambio}/{fase}` — para que fases posteriores y sesiones futuras puedan recuperarlo. Si una fase se re-ejecuta (un lote adicional de `apply`, por ejemplo), MEZCLA el progreso nuevo con el existente en vez de sobrescribirlo.

Antes de ejecutar `apply` o `verify`, recupera primero los artefactos de los que depende (ver tabla de fases) — no confíes solo en el historial de la conversación, que es un mal sustituto de la persistencia entre sesiones.
