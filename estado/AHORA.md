# Ahora

- **Actualizado:** 2026-09-14 (tras las respuestas del PO)
- **Último mensaje:** #013 (ARQ) — cuarta y última corrección del banco antes de fusionar.
  Se espera #014. (#012: ADR 0010 implementado, 51 afirmaciones en verde, 5 mutaciones
  confirmadas; la revisión encontró que un perfil podía declarar rutas fuera del temporal —
  ninguna suite actual lo hace—, y un bug real de `restore` (T20).)
- **Tramo en curso:** `estado/tramos/2026-09-14-0949-adopcion-arquitecto-coder.md`

## Espera al PO

Nada que bloquee. Cuando quieras:

1. **Al arrancar cada sesión nueva**, los dos `/rename` (el arquitecto te los recordará):
   `ServersBackupsPersonalUtility-Arquitecto-Main` y `ServersBackupsPersonalUtility-Coder-Main`.
2. **`~/.local/bin/backupctl`**: el enlace que dejó el agente anterior el 2026-09-05. Decide si
   lo conservas (hace que `backupctl` funcione en cualquier terminal) o lo quitas
   (`rm ~/.local/bin/backupctl`). Ningún agente lo toca.
3. **Servidor de pruebas**: su baja, dos bloqueos de Restic y la poda que se come las
   instantáneas buenas de la cuenta grande hacia principios de octubre (roadmap).
4. **`git push` de `master`**: la adopción ya está fusionada (`7977793`). Subirla, cuando
   quieras, lo haces tú. La rama `chore/adopcion-arquitecto-coder` puede borrarse (también tú).

Decidido el 2026-09-14: pruebas en servidor, solo el PO (ADR 0006); `master` estable con ramas
(ADR 0007); credenciales versionadas a propósito (ADR 0008); push solo el PO; los 31 commits con
`Co-Authored-By` se quedan; `mkdocs build` y `shellcheck` fuera de `verificar.sh`; hook
`commit-msg` opcional (roadmap). El `git add` de las 10:00 lo hizo el PO para comparar.

## En curso

Ronda #013 en vuelo, en `feat/banco-de-pruebas` (30 commits, sin fusionar): validar las rutas
del perfil, cuatro endurecimientos menores, y fusionar. Criterio de corte: CRÍTICO solo si una
suite existente, SIN modificarla, puede tocar algo real o pasar con el código roto; lo que exige
escribir una prueba equivocada es advertencia (las pruebas nuevas pasan por revisión).

Si se corta ahora: quedaría la rama a medias; el coder termina la ronda antes de parar.

## Para una sesión nueva

La sesión que construyó el proyecto (`humilde_trabajador_presente_backups`) ya no escribe
aquí; su traspaso está en `.agents/HERENCIA.md`. `serversbackupspersonalutility-68` no es el
coder.
