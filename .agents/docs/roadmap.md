# Roadmap

Lo que falta, ordenado por lo que costaría no tenerlo. **No es una promesa**: es la lista de
la que elige el Product Owner. El arquitecto propone; no convierte nada de aquí en una
instrucción sin que el PO lo nombre.

Una tarea sale de aquí al cerrarse; su historia queda en la bitácora. Referencias
`T<n>` = trampa n de `.agents/context/30-trampas.md`.

---

## En curso (nombrado por el PO el 2026-09-14)

- [ ] **Commitear la adopción del modelo arquitecto-coder** en una rama y fusionarla.
- [ ] **Banco de pruebas local**: órdenes falsas (`ssh`, `rsync`, `mysql`, `mysqldump`,
      `sudo`, `v-*`, `restic`, `rclone`) delante en el `PATH` y perfiles sintéticos en un
      temporal, para probar sin servidor (T18; ADR 0006 lo vuelve imprescindible). Necesita
      ADR antes de escribir código.

## Pendiente en servidores (lo ejecuta el PO)

- [ ] **Migración real de la cuenta grande** del servidor de pruebas, con la guía
      `docs/hestiacp/tres-escenarios.md`. De punta a punta solo se probó una cuenta pequeña.
- [ ] **Sin probar contra un servidor**: buzones y DKIM, certificados SSL, alias web, cuentas
      grandes, remapeo de IP en una restauración real.
- [ ] **Baja del servidor de pruebas.** Su retención de Restic poda cada noche: las
      instantáneas buenas de la cuenta grande desaparecen hacia principios de octubre de 2026.
      Dos bloqueos de Restic quedaron sin liberar a propósito (`HERENCIA.md`).

## El repositorio

- [ ] **Datos reales del PO en el código** (T7): dominio de un cliente, usuario y bases en
      `lib/adoptar.sh`, placeholders de `web/index.html`, huellas del servidor en comentarios.
- [ ] **Documentación que miente** (`30-trampas.md`, última sección):
      `docs/desarrollo/arquitectura.md`, el enlace roto de `TejidoTesting/Instrucciones.md`,
      la ayuda de `bin/backupctl`.
- [ ] **Auditoría de seguridad** de lo marcado como SOSPECHA en T6 y de lo confirmado en T1
      que no es decisión del PO (la web devuelve el `env.sh`; `pull` copia su diff a
      `ESTADO.md`).
- [ ] **`web/__pycache__/server.cpython-312.pyc` está versionado** y `.gitignore` no ignora
      `__pycache__/`.
- [ ] **`shellcheck`** en `verificar.sh` si el PO lo instala.
- [ ] **Hook `commit-msg`** (`.agents/scripts/git-hooks/`): red opcional contra menciones a IA
      en commits hechos con cualquier herramienta. Lo activa el PO en su clon:
      `git config core.hooksPath .agents/scripts/git-hooks`.
- [ ] **`CHANGELOG.md`**: no existe. Crearlo cuando haya una primera versión que nombrar.

## Grande y sin decidir

- **Paridad web ↔ CLI.** El PO quiere que todo lo que hace `bin/backupctl` pueda hacerse
  desde `web/`, con botones atomizados. `web/comprobar.py` comprueba parte; falta saber si la
  paridad es completa hoy.
