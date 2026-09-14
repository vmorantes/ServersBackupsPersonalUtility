# Estado y continuidad

**Ningún trabajo depende de una sesión.** Una sesión nueva, de cualquier proveedor, debe
saber desde el repositorio qué hay detrás, qué está en curso y qué viene. Si no puede, el
fallo es de la documentación, y se corrige ahí. Decisión: ADR 0004.

`estado/` nunca contiene un `env.sh`: `backupctl` tomaría el directorio por un perfil de
servidor.

## Dónde vive cada cosa

| Pregunta | Dónde | Vida |
| --- | --- | --- |
| ¿Qué está pasando ahora? ¿Qué número de mensaje toca? ¿Qué espera al PO? | `estado/AHORA.md` | Se reescribe en cada ronda |
| ¿Qué se hizo en este tramo? | `estado/tramos/AAAA-MM-DD-HHMM-<tema>.md` | Volátil: se poda |
| ¿Qué viene? | `.agents/docs/roadmap.md` | Se tacha y se saca al cerrar |
| ¿Por qué se decidió así? | `.agents/docs/adr/` | Inmutable |
| ¿Cómo se llegó aquí? | `.agents/docs/bitacora/` | Crece |
| ¿Qué me muerde si toco esto? | `.agents/context/` | Verdad hoy; se corrige y se poda |
| ¿Qué cambió para el usuario? | `CHANGELOG.md` | Crece |

## `estado/` — obligaciones del arquitecto

- **`AHORA.md` se actualiza en cada ronda**, antes de enviar la instrucción y al recibir el
  reporte. Lo que diga debe ser verdad en ese momento: una sesión puede morir en cualquier
  punto y la siguiente arranca de ahí.
- **Cada tramo tiene su archivo** en `estado/tramos/`, creado al empezar y ampliado en cada
  ronda: hora de inicio, rondas (número, qué, commits), hallazgos, decisiones, fallos y cómo
  se resolvieron, pendiente del PO, y al cerrar la duración.
- **Lo que necesite al PO** va arriba en `AHORA.md`, bajo «Espera al PO», además del chat.
- `estado/` es la excepción a «no escribir con tanda en vuelo»: solo lo escribe el
  arquitecto y el coder la excluye de sus criterios de `git status`. Se commitea en commits
  `docs(estado):` propios, nunca mezclados.

## Poda — la muerte de lo inservible

Documentación que ya no sirve es ruido que un agente leerá como verdad. Se poda:

- **Tramos**: se conservan los 10 más recientes. Uno más viejo se borra cuando lo que
  importaba de él ya está en la bitácora, un ADR o el CHANGELOG.
- **`context/`**: lo que el código ya no hace se borra en el mismo commit que lo cambia.
  Una trampa resuelta con un test que la cubre se reduce a una línea o se va.
- **Roadmap**: lo cerrado sale; su historia queda en la bitácora.
- **`HERENCIA.md`**: se borra cuando se cumplan sus propias condiciones, con entrada de
  bitácora.
- **ADR**: nunca se borran; se reemplazan.

El subagente `context-curator` audita esto; el arquitecto decide y ejecuta.

## Arranque de una sesión nueva

1. `estado/AHORA.md` — dónde estamos.
2. El último archivo de `estado/tramos/`.
3. `.agents/README.md` — el orden de lectura del resto.
