# Decisiones de arquitectura (ADR)

> **Plantilla.** Colócala en `docs/adr/README.md`. **Antes de nada, comprueba que la ruta
> no está ignorada:** `git check-ignore -v docs/adr/x.md` no debe devolver nada.

Un ADR registra **por qué** se decidió algo, qué se descartó y a cambio de qué. No
describe cómo funciona el código: eso se lee del código.

> `git log` te dice qué cambió. Jamás te dice qué descartaste, ni por qué.

## Regla dura: los ADR son inmutables

**La inmutabilidad empieza cuando el ADR se commitea.** Antes es un borrador y se edita
libremente. Publicado, no se toca.

Si la decisión cambia, se escribe uno nuevo: el nuevo lleva `Reemplaza: NNNN`; del viejo
**solo** se toca la línea de estado, que pasa a `Reemplazado por NNNN`.

Editar un ADR publicado destruye lo que lo hace valioso: el rastro de por qué pensabas
distinto entonces.

## Cuándo escribir uno

Cuando hay una **elección real entre alternativas** con consecuencias que duran. No cuando
hay código nuevo. Renombrar una variable o arreglar un typo no es una decisión.

## Cambios estructurales: dos secciones obligatorias

Un cambio es **estructural** si cumple alguna de estas cuatro:

1. Cambia **dónde vive** algo — carpetas, rutas, nombres de módulos.
2. Cambia un **contrato** entre partes — API, esquema de datos, formato compartido.
3. Cambia **cómo se trabaja** — roles, proceso, reglas, herramientas.
4. Cambia **configuración de alcance global** — `.gitignore`, base de datos, build, deploy.

No lo es añadir un campo, arreglar un bug o cambiar un texto.

Cuando lo es, el ADR lleva sí o sí:

| Sección | Para qué |
| --- | --- |
| **En cristiano** | Entenderlo sin leer el análisis. Cuatro frases, sin jerga. |
| **Reversión** | Deshacerlo. Paso a paso, en orden inverso, y qué comprobar después. |

### Por qué la reversión vive aquí y no en el `CHANGELOG.md`

El changelog es cronológico y solo crece. Una receta de urgencia enterrada en una lista
por fechas es inencontrable justo cuando hace falta: en una urgencia nadie busca *"qué
pasó el día tal"*, busca *"cómo deshago esto"*.

Y de fondo: el contexto para agentes debe ser **verdad hoy**; un ADR es **verdad en su
fecha**. Una guía de reversión es, por naturaleza, verdad en su fecha.

## Convención

`NNNN-titulo-en-kebab-case.md`, correlativos, sin reutilizar números. Estados:
`Propuesta` · `Aceptada` · `Aceptada (sin implementar)` · `Reemplazada por NNNN` ·
`Descartada`.

## Índice

| # | Decisión | Estructural | Estado |
| --- | --- | --- | --- |
| 0001 | … | | |
