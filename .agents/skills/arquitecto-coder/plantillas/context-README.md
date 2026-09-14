# Contexto para agentes

> **Plantilla.** Colócala en `.agents/context/README.md` (o donde el proyecto guarde las
> notas para agentes) y enlázala desde el README de esa carpeta.

Contexto técnico del proyecto para agentes de IA. **Denso a propósito**: rutas, números de
línea, invariantes y trampas. Lo que a una persona le sobra pero a un agente le ahorra
explorar medio repositorio.

## Qué va aquí y qué no

| Va | No va |
| --- | --- |
| Invariantes que el código no declara | Lo que se deduce leyendo el código en treinta segundos |
| Trampas que ya mordieron a alguien | Historial de cambios → changelog |
| Rutas y líneas donde vive algo difícil de encontrar | El *porqué* de una decisión → ADR |
| Deuda técnica **verificada**, con archivo y línea | Deuda sospechada sin verificar |

Regla de oro: **estos documentos no pueden mentir.** Si un cambio de código invalida lo
que dice uno, se corrige en el mismo commit. Ante contradicción, gana el código.

Cada archivo abre con la fecha y la rama en que se verificó su contenido.

## Índice sugerido

| Archivo | Contenido |
| --- | --- |
| `00-mapa-del-sistema.md` | Repos, módulos propios frente a los del framework, contratos entre partes |
| `10-convenciones.md` | Cómo se hacen las cosas aquí y qué te va a morder |
| `90-deuda-conocida.md` | Bugs y deuda verificados, con archivo y línea |
