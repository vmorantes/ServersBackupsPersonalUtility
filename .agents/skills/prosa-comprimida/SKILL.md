---
name: prosa-comprimida
description: Escritura comprimida sin relleno para el chat con el Product Owner, la logística entre sesiones y la prosa de los reportes, con límites estrictos donde comprimir dañaría la fiabilidad. Siempre activa por la regla 50-prosa-comprimida; invócala con /prosa-comprimida ligera|plena para cambiar el nivel, o "prosa normal" para desactivarla en la sesión.
effort: low
---

# Prosa comprimida

Escribe corto. Toda la sustancia técnica se queda; solo muere el relleno.

## Niveles

| Nivel | Qué cambia |
| --- | --- |
| **ligera** (por defecto) | Sin relleno, sin cortesías, sin rodeos. Frases completas, tono profesional. |
| **plena** | Además: fragmentos permitidos, sinónimos cortos, sin artículos cuando no hacen falta. |

No hay nivel más agresivo a propósito (ADR 0005): abreviar palabras o quitar conectores lo
lee mal un agente de otro proveedor.

## Reglas

- Fuera: «claro», «por supuesto», «básicamente», «simplemente», «en realidad», disculpas de
  más, anunciar lo que se va a hacer con las herramientas, tablas y emojis decorativos,
  volcados largos de error (cita la línea decisiva).
- Dentro, **exactos**: términos técnicos, rutas, comandos, nombres de funciones, mensajes de
  error, tipos de commit.
- Nunca abreviaturas inventadas. Siglas conocidas sí (CSV, DNS, SSH).
- Español del PO. No anuncies el modo ni te refieras a él.
- Patrón: `[cosa] [acción] [motivo]. [siguiente paso].`

No: «¡Claro! Con gusto te ayudo. El problema que estás viendo probablemente se deba a que…»
Sí: «Falla `bc_ssh_sudo`: se come la entrada estándar. Usar `bc_ssh_sudo_stdin` en `lib/…:454`.»

## Dónde no se aplica nunca

- Instrucciones al coder. Salidas pegadas. Documentación de cualquier tipo.
- Clasificaciones CONFIRMADO / SOSPECHA / SIN VERIFICAR: la palabra que falta es la que
  importa.
- Avisos de seguridad y confirmaciones de acciones irreversibles.
- Secuencias de pasos donde quitar conectores vuelve ambiguo el orden.
- Cuando el PO pide aclarar o repite la pregunta.

Tras la parte clara, vuelve a comprimir.

Ejemplo, acción irreversible:

> **Aviso:** esto borra del historial el archivo con el nombre del servidor y obliga a
> reescribir todos los commits posteriores. No se puede deshacer en los clones existentes.
>
> Pendiente de tu decisión.
