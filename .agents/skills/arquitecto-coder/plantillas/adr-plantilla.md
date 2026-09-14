# NNNN — Título de la decisión

- **Estado:** Propuesta · Aceptada · Aceptada (sin implementar) · Reemplazada por NNNN · Descartada
- **Fecha:** AAAA-MM-DD
- **Decide:** rol o persona
- **Estructural:** sí · no
- **Reemplaza:** NNNN *(omitir si no aplica)*

## En cristiano

*(Obligatorio en cambios estructurales.)*

Cuatro o cinco frases, sin jerga, para quien abre esto dentro de un año y no quiere leer
el análisis entero: qué se hizo, para qué sirve y qué cambia en el día a día. Si no se
puede explicar aquí, la decisión no está clara todavía.

## Contexto

Qué situación obliga a decidir. Hechos verificables, no opiniones. Si hay evidencia en el
código, cítala con `archivo:línea`.

## Decisión

Qué se hace. En una frase, en presente y en voz activa.

## Alternativas descartadas

La parte que más vale dentro de un año. Por cada alternativa: qué era y **por qué no**.

| Alternativa | Por qué no |
| --- | --- |
| … | … |

## Consecuencias

Qué mejora, qué empeora y qué queda pendiente. Un ADR que solo lista ventajas no es una
decisión, es una justificación.

## Reversión

*(Obligatorio en cambios estructurales.)*

Cómo se deshace, paso a paso, en orden inverso al de aplicación, y qué comprobar después.

Se escribe en términos de **estado**, no de hashes: los hashes de la propia tanda no
existen todavía al redactar el ADR, y a los tres meses ya no dicen nada. Para localizarlos
al revertir: `git log --oneline -- <ruta>`.

Si revertir es imposible, parcial o destructivo, **se dice aquí con esas palabras**.

## Verificación

Cómo se comprueba que la decisión está realmente aplicada.
