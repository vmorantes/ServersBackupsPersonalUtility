# Bitácora

Registro de cómo se llegó a cada cambio: qué se pidió, qué se encontró, qué se instruyó y qué
se obtuvo. **No es una transcripción.** Una entrada por tarea cerrada, nunca una por mensaje.

El changelog cuenta qué cambió; los ADR, por qué se eligió una opción; la bitácora, lo que
ninguno guarda: qué se probó y falló, qué apareció a mitad de camino, qué se dejó fuera.
Contesta «¿por qué esto tardó tres vueltas?» y «¿esto ya lo intentamos?».

Empieza con la adopción del modelo arquitecto-coder (ADR 0001, 2026-09-14). Lo anterior está
en `git log` (47 commits con mensajes descriptivos) y lo que no cuenta `git log`, en
`../../HERENCIA.md`.

## Convención

`NNNN-titulo-en-kebab-case.md`, correlativos. Se escribe **al cerrar** la tarea, con el
reporte del coder en mano. Plantilla:
`.agents/skills/arquitecto-coder/plantillas/bitacora-plantilla.md`.

## Índice

| Entrada | Qué cierra | Fecha |
| --- | --- | --- |
| [0001](0001-adopcion-arquitecto-coder.md) | Adopción del modelo arquitecto-coder | 2026-09-14 |
