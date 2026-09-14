# 0001 — Arquitecto, coder y PO, con canal directo entre sesiones

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Product Owner
- **Estructural:** sí (cómo se trabaja)

## En cristiano

Desde ahora el trabajo lo hacen dos sesiones de agente con papeles separados: una decide y
documenta (arquitecto) y otra programa, prueba y commitea (coder). El PO decide qué se
construye y no tiene que leer ni transportar los mensajes: las sesiones se hablan
directamente y trabajan en tramos largos. El PO sigue lo que pasa en `estado/`, y solo se le
interrumpe para decisiones de producto, de su entorno o que las reglas exigen autorizar.

## Contexto

- Los 47 commits hasta `4435064` (2026-09-05 a 2026-09-10) los hizo una sola sesión que
  decidía, implementaba, probaba y commiteaba, con la continuidad en su conversación y en su
  memoria nativa.
- Esa forma de trabajar dejó incidentes registrados en la memoria del proyecto:
  - una «prueba» de `backupctl install` creó `~/.local/bin/backupctl` en el sistema del PO,
    confirmando la propia sesión el diálogo (2026-09-05);
  - la herramienta llegó a dar éxitos en falso que solo se vieron al comprobar por fuera
    (commit `bc52491`: el aviso de prueba decía «enviado» sin enviar nada).
- El PO no audita el código: juzga por lo que ve en la interfaz y en el panel. Un punto de
  control entre el análisis y el disco tiene que estar dentro del proceso, no en él.
- El 2026-09-14 el PO trajo al repositorio el andamiaje arquitecto-coder que usa en otro
  proyecto (CustomPluginsHestiaCP) y pidió adaptarlo a este.

## Decisión

Tres roles según `.agents/rules/30-protocolo-coder.md`; mensajería directa entre sesiones de
la misma máquina; contador de mensajes único con el último número en `estado/AHORA.md`.
Nombres de sesión: `ServersBackupsPersonalUtility-Arquitecto-Main` y
`ServersBackupsPersonalUtility-Coder-Main`.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Seguir con un solo agente que decide e implementa | Sin punto de control entre análisis y disco: es lo que produjo los incidentes de arriba |
| El PO transporta cada recuadro | Lo convierte en cuello de botella sin aportar: no los lee |
| Coder como subagente del arquitecto | Un subagente no persiste entre tandas ni puede ser de otro proveedor; y el arquitecto acabaría viendo y corrigiendo código en su propio contexto |

## Consecuencias

- El PO pierde la visión de cada recuadro: la compensan `estado/` y el resumen de tramo.
- Dos sesiones cuestan más que una. A cambio, cada una tiene su contexto limpio.
- La sesión que construyó el proyecto deja de ser la fuente: lo que sabía y no está en el
  repositorio se recoge en `.agents/HERENCIA.md` o se pierde.
- Si el coder corre en otro proveedor o máquina, el PO vuelve a transportar; el formato no
  cambia.

## Reversión

1. Volver a un solo agente: borrar de `30-protocolo-coder.md` las secciones de roles y canal,
   y quitar la exigencia de reportes.
2. `estado/` puede quedarse: sirve igual a una sola sesión.
3. Comprobar que ninguna regla restante habla de «el coder» o «el arquitecto».

## Verificación

Los reportes del coder abren con `[#NNN · COD · fecha · herramienta / modelo]` y
`estado/AHORA.md` lleva el último número.
