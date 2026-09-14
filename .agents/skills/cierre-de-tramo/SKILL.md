---
name: cierre-de-tramo
description: Cierra un tramo de trabajo arquitecto-coder dejando el repositorio autosuficiente - resumen del tramo con duración, estado/AHORA.md al día, bitácora, roadmap, CHANGELOG y poda de documentación. Úsala al detenerse por cualquier motivo (falta el PO, no queda trabajo, el PO pide parar) y antes de cerrar la sesión.
effort: medium
---

# Cierre de tramo

Objetivo: que una sesión nueva, de cualquier proveedor, pueda seguir sin esta conversación.

## Pasos

1. **Ninguna ronda a medias.** Si hay una en vuelo, espera su reporte. Si el coder quedó
   bloqueado, que el bloqueo esté descrito en `estado/AHORA.md`.
2. **Archivo del tramo** (`estado/tramos/…`): fin, duración, todas las rondas con commits,
   hallazgos, decisiones con número de ADR, fallos y cómo se resolvieron, lista numerada de lo
   que espera al PO, resumen en prosa llana.
3. **`estado/AHORA.md`**: último número de mensaje, «Espera al PO» igual que en el tramo,
   «Siguiente».
4. **Bitácora**: una entrada por tarea cerrada en el tramo (no por ronda).
5. **Roadmap**: sacar lo cerrado; añadir lo descubierto, sin convertirlo en trabajo.
6. **CHANGELOG**: lo que cambió para el usuario en `[Sin publicar]`.
7. **Poda**: lanza `context-curator`; aplica lo que proponga y sea correcto; tramos más allá
   de los 10 últimos cuyo contenido ya está recogido, fuera.
8. **Commit**: todo lo anterior es documentación: instrucción al coder para commitearlo en
   commits `docs:` / `docs(estado):` separados, o dejarlo dicho en `AHORA.md` si no hay
   coder.
9. **Chat**: el mismo resumen del tramo, comprimido, con la lista de lo que espera al PO.

## Comprobación final

- ¿`AHORA.md` dice la verdad ahora mismo?
- ¿Hay alguna decisión tomada en el tramo que solo esté en la conversación? → ADR o contexto.
- ¿Algún documento quedó contradiciendo al código?
