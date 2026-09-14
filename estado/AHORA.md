# Ahora

- **Actualizado:** 2026-09-14 (tras las respuestas del PO)
- **Último mensaje:** #003 (ARQ) — instrucción: commitear la adopción en
  `chore/adopcion-arquitecto-coder` y fusionarla en `master`. Se espera el reporte #004.
  (#001 saludo; #002 el coder confirmó: Claude Code / Sonnet 5, rama `master`.)
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
4. **`git push`** de `master` cuando se fusione la adopción: lo haces tú.

Decidido el 2026-09-14: pruebas en servidor, solo el PO (ADR 0006); `master` estable con ramas
(ADR 0007); credenciales versionadas a propósito (ADR 0008); push solo el PO; los 31 commits con
`Co-Authored-By` se quedan; `mkdocs build` y `shellcheck` fuera de `verificar.sh`; hook
`commit-msg` opcional (roadmap). El `git add` de las 10:00 lo hizo el PO para comparar.

## En curso

Saludo al coder. Después:

1. Ronda: commitear la adopción en la rama `chore/adopcion-arquitecto-coder` y fusionarla en
   `master` (vaciar antes el índice que dejó el `git add` de comparación).
2. Tarea nombrada: **banco de pruebas local**. El arquitecto escribe antes su ADR.

Si se corta ahora: nada a medias; todo está en disco sin commitear.

## Para una sesión nueva

La sesión que construyó el proyecto (`humilde_trabajador_presente_backups`) ya no escribe
aquí; su traspaso está en `.agents/HERENCIA.md`. `serversbackupspersonalutility-68` no es el
coder.
