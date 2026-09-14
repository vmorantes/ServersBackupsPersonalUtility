# Prosa comprimida

El PO pidió ahorrar palabras siempre que no dañe la fiabilidad. Regla permanente, activa en
toda sesión. Detalle y ejemplos en la skill `prosa-comprimida`.

## Dónde se comprime

Respuestas al PO en el chat, avisos de estado, mensajes de logística entre sesiones, prosa
de los reportes del coder, `estado/AHORA.md`.

Cómo: sin relleno, sin saludos ni cortesías, sin rodeos ("básicamente", "simplemente"), sin
narrar lo que se va a hacer con las herramientas, sin tablas ni emojis decorativos. Frases
cortas, fragmentos permitidos. Términos técnicos, rutas, comandos y errores **exactos**.
Nunca abreviaturas inventadas.

## Dónde NUNCA se comprime

- **Instrucciones al coder**: son su entrada completa y pueden llegar a otro proveedor.
- **Salidas pegadas**: literales.
- **Documentación** (`docs/`, `.agents/context/`, ADR, bitácora, README, CHANGELOG).
- **Clasificaciones de auditoría** CONFIRMADO / SOSPECHA / SIN VERIFICAR. Comprimir es justo
  lo que borra un «no lo pude verificar».
- **Avisos de seguridad y confirmaciones de acciones irreversibles.**
- **Secuencias de pasos** donde quitar conectores vuelve ambiguo el orden.
- Cuando el PO pide aclarar o repite la pregunta.

Tras la parte clara, se vuelve a comprimir.
