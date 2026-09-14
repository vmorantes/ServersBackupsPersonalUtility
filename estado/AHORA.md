# Ahora

- **Actualizado:** 2026-09-14 (tras las respuestas del PO)
- **Último mensaje:** #011 (ARQ) — tercera corrección del banco, con el diseño del ADR 0010.
  Se espera #012. (#010: el crítico de #008 cerrado, 5 mutaciones confirmadas, 45 afirmaciones
  en verde; la tercera revisión encontró otro fallo en abierto: la comprobación del `PATH` solo
  existía en `ejecutar.sh`. No se fusionó.)
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

Ronda #011 en vuelo, en `feat/banco-de-pruebas` (24 commits, sin fusionar): rediseño de las
salvaguardas para que ninguna dependa de quién la llama (ADR 0010, reemplaza al 0009): marca
con testigo, comprobación del `PATH` dentro de `lib.sh`, lista única de órdenes, temporal fijo
en `/tmp`; retención comprobada por nombre; afirmaciones que exigen su evidencia. Tras tres
revisiones con un crítico cada una, la revisión de esta ronda clasifica como CRÍTICO solo lo que
pueda tocar algo real o dejar pasar código roto.

Si se corta ahora: quedaría la rama a medias; el coder termina la ronda antes de parar.

## Para una sesión nueva

La sesión que construyó el proyecto (`humilde_trabajador_presente_backups`) ya no escribe
aquí; su traspaso está en `.agents/HERENCIA.md`. `serversbackupspersonalutility-68` no es el
coder.
