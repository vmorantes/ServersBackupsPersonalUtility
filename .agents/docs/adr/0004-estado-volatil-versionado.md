# 0004 — `estado/`: lo que pasa ahora, versionado y podado

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Arquitecto, con el modelo que trae el PO
- **Estructural:** sí (cómo se trabaja)

## En cristiano

Hay una carpeta, `estado/`, donde siempre está escrito qué se está haciendo, qué se hizo en
cada tanda de trabajo y qué espera al PO. El PO la mira cuando quiere, sin buscar en el chat.
Una sesión nueva la lee y sabe por dónde seguir. Lo viejo se borra cuando ya está recogido en
otro sitio.

## Contexto

- Con el canal directo (ADR 0001) el PO no ve los mensajes entre sesiones.
- Hasta la adopción, la continuidad de este proyecto vivía en la conversación de una sola
  sesión y en su memoria nativa (tres notas en la carpeta de memoria de Claude Code de esta
  máquina). Nada de eso viaja con el repositorio.
- En el otro repositorio del PO se pidió expresamente «un directorio con archivos volátil pero
  versionado» y que ningún trabajo dependa de una sesión.

## Decisión

- `estado/AHORA.md`: en curso, siguiente, espera al PO, último número de mensaje. Se reescribe
  en cada ronda.
- `estado/tramos/AAAA-MM-DD-HHMM-<tema>.md`: uno por tramo, ampliado en cada ronda, con
  duración al cerrar.
- Solo lo escribe el arquitecto; se commitea en `docs(estado):` aparte.
- Poda: se conservan los 10 tramos más recientes; uno más viejo se borra cuando lo que
  importaba está en bitácora, ADR o CHANGELOG.

Detalle operativo: `.agents/rules/60-estado.md`.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Solo el resumen en el chat | Se pierde entre salidas y muere con la sesión |
| Dentro de `.agents/` | Oculto (punto delante): el PO necesita algo a la vista |
| Sin versionar (`.gitignore`) | No sobreviviría a un clon ni a otra máquina |
| Usar la bitácora | Es una entrada por tarea cerrada, escrita al final; no refleja lo que está en vuelo |
| Seguir con la memoria nativa | Vive en una máquina y un proveedor (`10-memory-contract.md`) |

## Consecuencias

- Commits frecuentes de `estado/` en el historial: es el precio de que sea versionado.
- Si `AHORA.md` miente, una sesión nueva arranca mal: por eso se actualiza antes de enviar
  cada instrucción, no después.
- `estado/` no es un perfil de servidor: `backupctl` descubre perfiles buscando directorios
  con un `env.sh` dentro (`docs/desarrollo/repositorio.md`, «Añadir un servidor»). `estado/`
  nunca debe contener un `env.sh`.

## Reversión

1. Mover lo útil de `estado/tramos/` a la bitácora.
2. `git rm -r estado/` y borrar `.agents/rules/60-estado.md` y su symlink.
3. Quitar las menciones en `AGENTS.md`, `.claude/CLAUDE.md`, `.agents/README.md` y
   `30-protocolo-coder.md`.

## Verificación

`estado/AHORA.md` indica el mismo último número de mensaje que el último reporte recibido.
