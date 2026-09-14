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
| #017→(corte) | A: commitear ADR 0011/0012, guarda y documentación; borrar las ramas fusionadas. B: implementar ADR 0012 en `fix/limpieza-al-salir` | A completada; B commiteada sin revisar: los editores del PO se cerraron y el reporte no llegó | A: `7125f3a` `91df0b9` `80d6351`, fusión `9f82430`; B: `070107d` `b4430bc` `fda4642` `c617d1a` `b75bdd4` `8a5b3a4` `70b53a3` |
| #018→#019 | Saludo tras el corte | el coder conserva el contexto; M20/M21 confirmadas; prueba de `adoptar` descartada (12 respuestas de falsos) | — |
| #020→#021 | Terminar B: `set -e` en `bc_cleanup_eval`, revisiones, guía para el PO | en vuelo | — |

Tras el corte, el estado se reconstruyó desde git, no desde la conversación: nada se había
perdido (todo lo hecho estaba commiteado; el árbol, limpio salvo `estado/`).

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

- Pregunta 5 del PO (conservar instantáneas): verificada en la fuente de HestiaCP 1.10.4 por
  `hestia-verifier`. La poda la hace el propio servidor (`v-backup-user-restic`, `forget
  --prune`, retención global en `conf/restic.conf`); `v-delete-backup-host-restic` la detiene
  para todo el panel. Respuesta en `AHORA.md`. Corrección de `50-hestiacp.md` (el
  `restic.conf` por usuario solo guarda la contraseña) redactada en el scratchpad para
  depositarla tras #018. El informe del verificador salió corrupto en su último párrafo: solo
  se usó lo citado literalmente.

## Falló por el camino

- La guarda bloqueó `tools/backupctl-escritorio.sh estado 2>&1 | head` (falso positivo de
  redirecciones). Corregido.

## Espera al PO

Ver `estado/AHORA.md`.

## Resumen

*(al cerrar)*
