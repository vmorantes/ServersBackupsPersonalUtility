# 0005 — Prosa comprimida donde no cuesta fiabilidad

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Arquitecto, con el modelo que trae el PO
- **Estructural:** sí (cómo se trabaja)

## En cristiano

Los agentes escriben corto y sin relleno cuando hablan con el PO o entre ellos para
coordinarse. Nunca recortan las instrucciones de trabajo, la documentación, las salidas de
comandos ni los avisos de seguridad, porque ahí una palabra de menos puede cambiar el
sentido.

## Contexto

El PO trae de su otro repositorio la regla `50-prosa-comprimida.md` y la skill
`prosa-comprimida`, adoptadas allí con la condición de que no dañen la fiabilidad. El caso que
fijó los límites: un «no lo pude verificar» desapareció al comprimir y se afirmó un problema
de seguridad inexistente.

En este proyecto pesa más: sus guías separan lo probado de lo no probado (memoria del PO,
2026-09-10: «separar lo probado de lo no probado»), y un respaldo dado por bueno sin serlo se
descubre el día que hace falta restaurar.

## Decisión

Regla permanente `.agents/rules/50-prosa-comprimida.md` y skill `prosa-comprimida` (niveles
`ligera` y `plena`). Se comprime: chat con el PO, logística entre sesiones, prosa de reportes,
`estado/AHORA.md`. No se comprime: instrucciones al coder, salidas, documentación,
clasificaciones de auditoría, avisos de seguridad y confirmaciones irreversibles, secuencias
de pasos, y guías de operación para el PO.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Compresión agresiva en todo | Quita conectores también donde fijan el orden de los pasos o la certeza de un hallazgo |
| Abreviaturas o variantes más densas | Un agente de otro proveedor puede leerlas mal |
| No comprimir | En logística no hay riesgo y ahorra contexto |

## Consecuencias

- Menos tokens en la conversación; mismos documentos.
- Riesgo residual: que un agente comprima donde no debe. Lo acota la lista explícita.

## Reversión

Borrar la regla 50, la skill `prosa-comprimida` y sus symlinks; quitar la mención en
`30-protocolo-coder.md` si la hubiera.

## Verificación

Las instrucciones al coder conservan frases completas; `estado/AHORA.md` no tiene relleno.
