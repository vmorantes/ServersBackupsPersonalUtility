# Tramo 2026-09-14 14:48 — Limpieza que sobrevive a la salida (T20)

- **Inicio:** 2026-09-14 14:48 (hora en que el arquitecto abrió el tramo tras las respuestas del PO)
- **Fin:** 2026-09-14 16:35 — **Duración:** 1 h 47 min (con un corte de las sesiones de por medio)
- **Mensajes:** #017–#025 (#025: reporte de la ronda de cierre)
- **Mandato del PO** (respuestas al cierre del tramo anterior): «1. Luego subo. 2. Bórralas tú.
  3. Adelante, trabajen. 4. Quítalo. En todo caso podemos hacer un installer/uninstaller que sea
  un desktop. 5. ¿Qué debo hacer para que no se borren? Ya no las necesito, pero son útiles para
  las pruebas. 6. Perfecto.» Cierre: «vayan cerrando adecuadamente el día de trabajo de hoy».

## Rondas

| # | Qué | Resultado | Commits |
| --- | --- | --- | --- |
| #017→(corte) | A: ADR 0011/0012, guarda y documentación; borrar ramas fusionadas. B: implementar ADR 0012 en `fix/limpieza-al-salir` | A completada; B commiteada sin revisar: los editores del PO se cerraron y el reporte no llegó | A: `7125f3a` `91df0b9` `80d6351`, fusión `9f82430`; B: `070107d` `b4430bc` `fda4642` `c617d1a` `b75bdd4` `8a5b3a4` `70b53a3` |
| #018→#019 | Saludo tras el corte | el coder conserva el contexto; M20/M21 confirmadas; prueba de `adoptar` descartada (12 respuestas de falsos) | — |
| #020→#021 | Documentación de retención a `master`; `set -e` en `bc_cleanup_eval`; revisiones; guía | completado; M23 confirmada; sin críticos en el diff, pero la revisión de seguridad destapa T21 (preexistente) | `36c8196` `d7e468d`, fusión `141c416`; `ae9bff1` `58a0c3a` `81d23ae` |
| #022→#023 | Traer `master`; reparar la devolución de `restic.conf` (T21) y huecos del registro | completado con dos agujeros ALTA abiertos (usuario no-root; «no existe» frente a «no se pudo comprobar»); M24/M25 confirmadas, M26 no la ve ninguna prueba | fusión `f802f50`; `afeb5c0` `522b6c4` `41ffe6b` `fb3e880` |
| #024→#025 | Cierre del día: documentación a `master`, árbol en `master` | enviada | — |

Tras el corte, el estado se reconstruyó desde git, no desde la conversación: nada se había
perdido.

## Encontrado y decidido

- «Bórralas tú»: se delega de forma estrecha (ADR 0011): el coder borra ramas locales fusionadas
  con `git branch -d`; `-D`, renombrar y remotas, el PO.
- «Quítalo» (`~/.local/bin/backupctl`): lo hace el PO (la guarda no deja escribir fuera del
  repositorio). El lanzador de escritorio que propone ya existe y no depende del enlace.
- T20 era un síntoma: ninguna limpieza en `trap RETURN` corre si la orden muere. ADR 0012.
  «Adelante, trabajen» se interpretó como mandato para arreglar la causa en todos los módulos.
- **T21**, lo más grave del día: en `master`, `adoptar --to` puede dejar vacío (o borrar) el
  `restic.conf` del destino al terminar, aunque vaya bien. Aviso al PO en `AHORA.md`.
- Pregunta 5: verificada en la fuente de HestiaCP 1.10.4; la resolvió el PO quitando el respaldo
  Restic del cron. `50-hestiacp.md` corregido (el `restic.conf` por usuario solo es la clave).
- La guarda daba un falso positivo con redirecciones: corregida (182/182).

## Falló por el camino

- La guarda bloqueó `tools/backupctl-escritorio.sh estado 2>&1 | head`. Corregida.
- Los editores del PO se cerraron con la ronda #017 a medias. Todo estaba commiteado; el coder
  conservaba el contexto; las revisiones que corrían se perdieron y se repitieron.
- Al fusionar documentación en `master` desde una rama y volver a `fix/limpieza-al-salir`, el
  árbol mostró las versiones viejas de esos archivos y dos ediciones del arquitecto cayeron sobre
  ellas: se deshicieron y se rehicieron tras traer `master` a la rama (`f802f50`). Lección: la
  documentación que va a `master` se deposita con el árbol en `master`, o la rama trae `master`
  antes.

## Espera al PO

1. Copia y comprobación de `restic.conf` en el destino antes y después de cualquier
   `adoptar --to` (T21).
2. Nada que probar todavía en el servidor.
3. `rm ~/.local/bin/backupctl`.
4. `git push` de `master`.
5. Los dos `/rename` en cada sesión nueva.

## Resumen

Se decidieron y documentaron el borrado de ramas fusionadas (ADR 0011) y un registro de
limpiezas que corre aunque una orden muera (ADR 0012), y se implementó en
`fix/limpieza-al-salir` para `restore`, `verify`, `pull`, `restic` y `adoptar`, con pruebas en el
banco (7 suites) y seis mutaciones que lo demuestran. Al revisar ese trabajo apareció un defecto
serio que ya está en `master` (T21): `adoptar` puede dejar vacío el `restic.conf` del servidor de
destino. La rama lo arregla solo en parte; quedan dos agujeros graves que se cierran en el próximo
tramo, antes de pedir al PO que la pruebe. La pregunta de las instantáneas del servidor de pruebas
quedó resuelta y verificada en la fuente de HestiaCP.
