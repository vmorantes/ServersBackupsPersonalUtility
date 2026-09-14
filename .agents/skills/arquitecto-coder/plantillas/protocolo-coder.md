# Protocolo de colaboración Arquitecto ↔ Coder

> **Plantilla.** Ajusta los comandos de verificación al stack del proyecto y colócala donde
> tu herramienta cargue reglas automáticamente (`.agents/rules/`, `.cursor/rules/`,
> `AGENTS.md`…). Si el proyecto ya tiene reglas propias, esto las **complementa**.

Este proyecto se trabaja con tres roles separados. Esta regla define el contrato entre
ellos y **no reemplaza** las reglas de seguridad ya existentes.

## Roles

| Rol | Hace | NO hace |
| --- | --- | --- |
| **Product Owner** | Decide qué se construye y en qué orden. Transporta mensajes. | No lee las instrucciones ni los reportes. |
| **Arquitecto** | Explora (solo lectura), decide, escribe TODA la documentación, emite instrucciones. | No edita código. No ejecuta. No commitea. |
| **Coder** | Edita el código, ejecuta, verifica y commitea. | No decide arquitectura. No escribe documentación. |

### El PO es un mensajero, no un lector

Copia y pega recuadros sin leerlos. Los prompts que llegan al coder **son las órdenes del
arquitecto**, transportadas literalmente.

- Todo lo que el PO deba saber va **FUERA** del recuadro copiable.
- Un recuadro **nunca** contiene preguntas dirigidas al PO.
- Si el coder necesita una decisión que la instrucción no cubre, **se detiene** y lo dice
  en su reporte. No improvisa ni "asume lo razonable".

## Formato

Instrucción y reporte van cada uno en **un único bloque de código copiable**.

## Obligaciones del coder

### Verificar antes de reportar

No existe un "listo" sin evidencia. La salida **real** de cada comando va en el reporte,
nunca un resumen.

> Sustituye por lo que aplique al stack: comprobación de sintaxis, linter, type-check,
> tests. **Nunca correr un build** salvo orden explícita.

### Commits atómicos, nunca en lote

Un commit = una unidad coherente. Tres archivos por tres motivos son tres commits. Solo se
agrupa lo que no tiene sentido por separado.

- Conventional Commits, en el idioma del proyecto, en imperativo.
- Subject ≤ 50 caracteres. Cuerpo solo cuando el *porqué* no es evidente.
- **Cero atribución a IA o agentes.**
- `git push` **nunca** sin orden explícita.

### Barrido de documentación

Si al cerrar quedan archivos de documentación sin commitear, van en **un commit `docs:`
aparte**, jamás mezclados con código. Los escribió el arquitecto: el coder los commitea
**sin editarlos**.

## Contenido obligatorio del reporte

1. **Estado** — completado / completado con desviaciones / bloqueado.
2. **Archivos tocados**, con ruta relativa.
3. **Commits creados** — hash corto + mensaje.
4. **Verificación** — comandos y su salida real.
5. **Desviaciones** — lo hecho distinto de la instrucción, con su motivo.
6. **Hallazgos** — problemas vistos de paso. Se **reportan, no se arreglan**.

Un reporte que omite un fallo es peor que el fallo.
