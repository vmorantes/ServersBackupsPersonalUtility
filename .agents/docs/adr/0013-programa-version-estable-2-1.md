# 0013 — Camino a una versión estable: rama de versión, prueba única del PO y etiqueta

- **Estado:** Aceptada
- **Fecha:** 2026-09-16
- **Decide:** Arquitecto, por mandato del PO
- **Estructural:** sí (cómo se entrega una versión)
- **Complementa:** 0006 (pruebas en servidor), 0007 (ramas)

## En cristiano

Todo lo que el PO pidió el 2026-09-16 —herramienta rigurosa y bonita, incrementales que se
activan desde ella contando lo que hizo, y una versión estable— se reúne en una sola rama de
versión. Cada mejora entra en esa rama cuando pasa el banco de pruebas y las revisiones. Al
final el PO prueba la versión completa en el servidor de pruebas, una sola vez y con una sola
guía, y solo entonces pasa a `master` con su número de versión y su registro de cambios. Así el
PO no tiene que probar cada arreglo por separado, y `master` sigue siendo siempre lo desplegable.

## Contexto

- El PO, el 2026-09-16: «Mejora la herramienta para que sea rigurosa y bonita como tú quieras.
  Debo poder activar los incrementales y configurarlos desde ella sin HestiaCP, pero al mismo
  tiempo que me diga qué hizo. Es hora de potenciarla. […] Y dejar una versión estable.»
- ADR 0007 exige la prueba del PO antes de fusionar en `master` lo que toca servidores; con una
  rama por arreglo, eso serían muchas pruebas sueltas en el servidor.
- Pendientes que impiden llamar estable a `master` hoy: T21 (`adoptar` puede dejar vacío el
  `restic.conf` del destino), la rama `fix/limpieza-al-salir` sin terminar, el aviso falso de
  `adoptar --como` (roadmap), `adoptar --snapshot` sin validar, documentación desfasada.
- La versión que declara la herramienta es la 2.0.0 (web: «Respaldos HestiaCP 2.0.0»). No hay
  `CHANGELOG.md`.

## Decisión

1. **Rama de versión `release/2.1`**, creada desde `master`. Las ramas de trabajo (`fix/…`,
   `feat/…`) salen de ella y vuelven a ella con `--no-ff` cuando pasan `verificar.sh`, el banco y
   las revisiones (`code-reviewer`; `security-auditor` si tocan credenciales, `ssh`, `sudo` o la
   web). A esa rama **no** se le exige la prueba del PO fusión a fusión.
2. **Criterio de «estable» para salir de `release/2.1`**:
   - ningún hallazgo CRÍTICO abierto, y ninguno ALTA sin decisión escrita;
   - `verificar.sh` en verde; mutaciones que demuestran cada garantía nueva;
   - documentación de usuario al día y `CHANGELOG.md` con la versión;
   - **una prueba del PO en el servidor de pruebas** con una guía única que separa lo que el banco
     ya demuestra de lo que solo demuestra el servidor, y su conformidad por escrito.
3. **Salida**: fusión `--no-ff` en `master`, versión `2.1.0` en el código, etiqueta anotada
   `v2.1.0` creada por el coder. Subir la rama y la etiqueta a GitHub: el PO.
4. **Orden del trabajo**: primero rigor (T20/T21, avisos falsos, validaciones), después los
   incrementales de punta a punta con informe de lo hecho, en paralelo el diseño de la nueva
   interfaz (maqueta antes de código), al final documentación, versión y prueba del PO.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Seguir fusionando rama a rama en `master` con prueba del PO cada vez | Decenas de pruebas sueltas en el servidor; el PO pidió una versión estable, no un goteo |
| Fusionar en `master` sin prueba del PO | Contradice ADR 0006/0007: `master` es lo que se despliega |
| Etiquetar ya `master` como estable | Tiene T21 abierto |
| Llamarla 3.0.0 | No se rompe ninguna orden de la CLI ni el formato del respaldo; si el rediseño lo exigiera, se decide en su ADR |

## Consecuencias

- `master` no recibe mejoras hasta la salida de la versión (salvo documentación de agentes y
  `estado/`, que siguen el camino de siempre).
- Una rama de versión larga acumula riesgo de choques: las ramas de trabajo deben ser cortas.
- La prueba final del PO será más larga, pero única y guiada.

## Reversión

1. Fusionar `release/2.1` en `master` tal como esté, o abandonarla (borrarla es del PO).
2. Volver a ADR 0007 sin este complemento: quitar la mención en `30-protocolo-coder.md`.

## Verificación

`git log --first-parent master` tras la salida muestra una fusión de `release/2.1` y la etiqueta
`v2.1.0`; `CHANGELOG.md` tiene la entrada; `estado/` guarda la conformidad del PO.
