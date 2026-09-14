# Tramo 2026-09-14 14:48 — Limpieza que sobrevive a la salida (T20)

- **Inicio:** 2026-09-14 14:48 (hora en que el arquitecto abrió el tramo tras las respuestas del PO)
- **Fin:** *(al cerrar)* — **Duración:** *(al cerrar)*
- **Mensajes:** #017–
- **Mandato del PO** (respuestas al cierre del tramo anterior): «1. Luego subo. 2. Bórralas tú.
  3. Adelante, trabajen. 4. Quítalo. En todo caso podemos hacer un installer/uninstaller que sea
  un desktop. 5. ¿Qué debo hacer para que no se borren? Ya no las necesito, pero son útiles para
  las pruebas. 6. Perfecto.»

## Rondas

| # | Qué | Resultado | Commits |
| --- | --- | --- | --- |
| #017→#018 | A: commitear ADR 0011/0012, guarda y documentación; borrar las ramas fusionadas. B: implementar ADR 0012 en `fix/limpieza-al-salir` | en vuelo | — |

## Encontrado y decidido

- «Bórralas tú»: la guarda bloqueaba borrar ramas. Se delega de forma estrecha (ADR 0011): el
  coder borra ramas locales fusionadas con `git branch -d`; `-D`, renombrar y remotas, el PO.
- «Quítalo» (`~/.local/bin/backupctl`): la guarda no deja a ningún agente escribir fuera del
  repositorio y no se abre esa puerta por un archivo: el PO ejecuta `rm ~/.local/bin/backupctl`.
  El lanzador de escritorio que propone ya existe (`tools/backupctl-escritorio.sh`), está
  instalado y no depende de ese enlace (su `.desktop` ejecuta la ruta del repositorio).
- T20 era un síntoma: ninguna limpieza en `trap RETURN` corre si la orden muere. El caso grave:
  `adoptar --to` puede dejar `restic.conf` del destino apuntando al repositorio rescatado.
  ADR 0012. Se interpreta «Adelante, trabajen» como mandato para arreglar la causa en todos los
  módulos afectados; lo que toca servidores espera la prueba del PO antes de fusionar.
- La guarda daba un falso positivo con redirecciones (`2>&1` contaba como argumentos): corregida,
  con sus casos (182/182).

## Falló por el camino

- La guarda bloqueó `tools/backupctl-escritorio.sh estado 2>&1 | head` (falso positivo de
  redirecciones). Corregido.

## Espera al PO

Ver `estado/AHORA.md`.

## Resumen

*(al cerrar)*
