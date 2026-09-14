# 0011 — El coder borra las ramas locales ya fusionadas

- **Estado:** Aceptada
- **Fecha:** 2026-09-14
- **Decide:** Product Owner
- **Estructural:** sí (salvaguardas de git)
- **Complementa:** 0007 (ramas); 0003 (guarda)

## En cristiano

Cuando una rama de trabajo ya está fusionada en `master`, el coder la borra, sin pedírselo al
PO. Solo puede borrar ramas de esta máquina y solo con la orden de git que se niega si la rama
tiene algo sin fusionar, así que no se puede perder trabajo. Forzar el borrado, renombrar ramas
o tocar las de GitHub sigue siendo cosa del PO.

## Contexto

- El ADR 0007 dejaba al PO borrar ramas, y la guarda bloqueaba todo `git branch -d/-D`.
- Tras el primer tramo quedaron tres ramas locales fusionadas y nunca subidas
  (`chore/adopcion-arquitecto-coder`, `feat/banco-de-pruebas`, `docs/cierre-tramo-adopcion`).
  El PO, el 2026-09-14: «Bórralas tú».

## Decisión

- El coder borra, cuando la instrucción lo diga, ramas **locales** fusionadas en `master` con
  `git branch -d <rama>` (sin `-f`).
- La guarda permite `git branch -d/--delete` y bloquea `-D`, `--force`, `-r`/`--remotes`,
  `-a`/`--all`, renombrar (`-m`/`-M`) y copiar (`-c`/`-C`).
- Ramas en GitHub y ramas sin fusionar: el PO.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Que el PO las borre siempre | Lo delegó expresamente; y git ya protege lo sin fusionar |
| Permitir `-D` | Borra aunque haya commits sin fusionar: se puede perder trabajo |
| Una excepción solo para estas tres ramas | Cada tramo deja ramas fusionadas; sería la misma pregunta cada vez |

## Consecuencias

- Las ramas fusionadas no se acumulan. Su historia sigue en `master` (fusiones `--no-ff`).
- Una rama local borrada que el PO quisiera conservar como referencia se recupera desde su
  commit de fusión, no por nombre.

## Reversión

1. En `guardia.py`, volver a bloquear `git branch -d/--delete` y mover sus casos de
   `BASH_PERMITE` a `BASH_BLOQUEA` en `probar_guardia.py`.
2. Quitar la mención de este ADR en `30-protocolo-coder.md` y `40-salvaguardas.md` §3.
3. Comprobar que `verificar.sh` pasa.

## Verificación

`probar_guardia.py` permite `git branch -d <rama>` y bloquea `-D`, `-d -f` y `-d -r`.
