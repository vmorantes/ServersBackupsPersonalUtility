---
trigger: always_on
description: Contrato de memoria persistente entre sesiones, agnóstico del backend concreto
---

# Memoria persistente

> **El repositorio manda.** La memoria nativa de cada herramienta vive en una máquina y en
> un proveedor; el repositorio viaja con el proyecto. Nada que otra sesión necesite para
> trabajar puede vivir **solo** en la memoria nativa: decisiones van a un ADR, trampas a
> `.agents/context/`, el estado a `estado/` (regla `60-estado.md`). La memoria nativa es un
> atajo personal, nunca la fuente.

Este proyecto usa memoria persistente entre sesiones y compactaciones. No dependas de ningún MCP ni servicio externo de memoria: usa el motor de memoria persistente NATIVO de la herramienta en la que estés corriendo ahora mismo — cada una ya trae uno propio, sin instalar nada. Este archivo define SOLO el contrato de comportamiento: cuándo guardar, qué guardar, cuándo buscar. El mecanismo exacto para escribir y leer es el que tu motor nativo exponga.

## Cuándo guardar (proactivo — no esperes a que se te pida)

Guarda inmediatamente después de cualquiera de estos eventos:

- Se tomó una decisión de arquitectura o diseño
- Se estableció o documentó una convención de equipo
- Se acordó un cambio de flujo de trabajo
- Se eligió una herramienta o librería, con sus tradeoffs
- Se corrigió un bug (incluye la causa raíz)
- Se implementó una feature con un approach no obvio
- Se hizo un cambio de configuración o de entorno
- Se descubrió algo no obvio sobre el código base
- Se encontró un gotcha, edge case o comportamiento inesperado
- Se aprendió una preferencia o restricción mía

Autochequeo después de CADA tarea: "¿Tomé una decisión, arreglé un bug, aprendí algo no obvio, o establecí una convención? Si sí, guárdalo AHORA."

## Qué guardar

- **Qué**: una frase — qué se hizo
- **Por qué**: qué lo motivó (pedido mío, bug, performance, etc.)
- **Dónde**: archivos o rutas afectadas
- **Aprendido**: gotchas, edge cases, sorpresas (omitir si no hay)

Los temas que evolucionan (una decisión de arquitectura que se revisita, una convención que cambia) deben actualizarse bajo la misma referencia/clave existente, nunca duplicarse como una entrada nueva desconectada.

## Cuándo buscar en memoria

Ante cualquier variante de "recuerda", "qué hicimos", "cómo resolvimos", o referencias a trabajo pasado:

1. Revisa primero el contexto/histórico reciente de la sesión (rápido y barato).
2. Si no aparece ahí, busca por palabras clave en la memoria persistente de largo plazo.
3. Si lo encuentras, recupera el contenido completo — no te quedes con un resumen truncado.

Busca también de forma proactiva cuando:

- Empieces a trabajar en algo que pudo haberse hecho antes
- Yo mencione un tema del que no tengas contexto
- Mi PRIMER mensaje de la sesión mencione el proyecto, una feature o un problema conocido

## Cierre de sesión

Antes de terminar una sesión o decir "listo", guarda un resumen de cierre con:

- Objetivo de la sesión
- Instrucciones o restricciones mías descubiertas (omite si no hay)
- Hallazgos técnicos no obvios
- Qué se logró
- Próximos pasos para la siguiente sesión
- Archivos relevantes y qué cambió en cada uno

Esto no es opcional: sin este cierre, la siguiente sesión (o la siguiente herramienta) empieza a ciegas.

## Nota de implementación (una vez, no repetir en cada sesión)

Ninguna instalación adicional hace falta: Claude Code trae Auto Memory activado por defecto (notas que el propio Claude escribe en su carpeta de memoria del proyecto), y Antigravity trae Knowledge Items (patrones y decisiones que el agente destila en su base de conocimiento). Cada herramienta resuelve este contrato con su propio mecanismo nativo — no hay nada que configurar aquí.
