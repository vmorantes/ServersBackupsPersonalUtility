# Ahora

- **Actualizado:** 2026-09-14 (tras las respuestas del PO)
- **Último mensaje:** #015 (ARQ) — commitear la documentación de cierre del tramo en
  `docs/cierre-tramo-adopcion` y fusionar. Se espera #016. (#014: banco fusionado en `master`,
  `d5483d0`.)
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
4. **`git push` de `master`**: lleva la adopción (`7977793`) y el banco de pruebas
   (`d5483d0`). Lo haces tú. Las ramas `chore/adopcion-arquitecto-coder` y
   `feat/banco-de-pruebas` ya están fusionadas y pueden borrarse (también tú).
5. **Qué sigue.** No queda trabajo nombrado. Candidata: arreglar T20 (`restore` cancelado deja
   volcados de la base en `/tmp`), con su prueba en el banco.

Decidido el 2026-09-14: pruebas en servidor, solo el PO (ADR 0006); `master` estable con ramas
(ADR 0007); credenciales versionadas a propósito (ADR 0008); push solo el PO; los 31 commits con
`Co-Authored-By` se quedan; `mkdocs build` y `shellcheck` fuera de `verificar.sh`; hook
`commit-msg` opcional (roadmap). El `git add` de las 10:00 lo hizo el PO para comparar.

## En curso

Cierre del tramo: el trabajo nombrado por el PO (adopción y banco de pruebas) está hecho y en
`master`. El arquitecto audita la documentación con el curador de contexto y después manda
commitearla en `docs/cierre-tramo-adopcion`. No queda más trabajo nombrado: lo siguiente lo
elige el PO (primera candidata: T20).

Si se corta ahora: quedaría la rama a medias; el coder termina la ronda antes de parar.

## Para una sesión nueva

La sesión que construyó el proyecto (`humilde_trabajador_presente_backups`) ya no escribe
aquí; su traspaso está en `.agents/HERENCIA.md`. `serversbackupspersonalutility-68` no es el
coder.
