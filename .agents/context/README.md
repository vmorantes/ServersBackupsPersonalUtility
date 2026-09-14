# Contexto para agentes

Contexto técnico del repositorio para agentes. **Denso a propósito**: rutas, líneas,
invariantes y trampas. Responde a una pregunta: **¿qué me va a morder si toco esto?**

| Va | No va |
| --- | --- |
| Invariantes que el código no declara | Lo que se deduce leyendo el código en treinta segundos |
| Trampas que ya mordieron o que están verificadas | Historial → `CHANGELOG.md`, bitácora |
| Rutas y líneas difíciles de encontrar | El *porqué* de una decisión → ADR |
| Deuda **verificada**, con archivo y línea | Deuda sospechada sin marcarla como tal |

Reglas:

- **No puede mentir.** Un cambio de código que invalide algo de aquí lo corrige en el mismo
  commit. Ante contradicción, gana el código.
- **Verdad hoy.** Lo que caduca (una reversión) vive en el ADR.
- **Se poda.** Lo que el código ya no hace, se borra. Una trampa cubierta por prueba se
  reduce a una línea con el nombre de la prueba.
- Cada afirmación sobre HestiaCP dice si está **verificada** (contra qué) o **sin
  verificar**.
- Nunca copia un valor de un perfil real: basta con la ruta y la línea.

## Índice

| Archivo | Contenido |
| --- | --- |
| [`10-mapa-del-sistema.md`](10-mapa-del-sistema.md) | Qué hay en el repositorio, qué hace cada orden de `backupctl` (y qué efectos tiene), perfiles, la web |
| [`20-convenciones.md`](20-convenciones.md) | Exigencias del PO sobre el producto, bash, Python, pruebas, textos, commits |
| [`30-trampas.md`](30-trampas.md) | Lo que muerde, con evidencia y estado |
| [`40-entorno.md`](40-entorno.md) | Qué hay en la máquina de desarrollo, cómo se prueba sin servidor, qué verifica `verificar.sh` |
| [`50-hestiacp.md`](50-hestiacp.md) | Rutas, comandos y comportamientos de HestiaCP de los que depende el código |

La lógica de producto y sus porqués para personas están en `docs/desarrollo/`
(`arquitectura.md`, `decisiones.md`, `repositorio.md`): aquí se citan, no se copian.

Verificado en rama `master` (`4435064`), 2026-09-14.
