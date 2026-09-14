# Roadmap

Lo que falta, ordenado por lo que costaría no tenerlo. **No es una promesa**: es la lista de
la que elige el Product Owner. El arquitecto propone; no convierte nada de aquí en una
instrucción sin que el PO lo nombre.

Una tarea sale de aquí al cerrarse; su historia queda en la bitácora. Referencias
`T<n>` = trampa n de `.agents/context/30-trampas.md`.

---

## El banco de pruebas (ADR 0010; primera fase fusionada el 2026-09-14, bitácora 0002)

- [ ] **Siguientes suites del banco**: `ssh`/`deploy`/`pull`/`remote` contra falsos,
      confirmaciones sin terminal (T5), `bc_ssh_sudo` y la entrada estándar (T2), `hestia` con
      `HESTIA_DIR` en el temporal. `adoptar` exige antes sustituir `/usr/local/hestia` por
      `$HESTIA_DIR` (T18, ADR propio).
- [ ] **Endurecimientos pendientes** (advertencias de la quinta revisión; todas exigen escribir
      una prueba equivocada, ninguna la dispara una suite actual): leer el perfil por nombre de
      variable y no por posición en `bc_comprobar_rutas_perfil`; auditar o vaciar
      `NOTIFY_COMMAND`; exigir rutas absolutas en el perfil; comprobar el `mkdir`/`cd` de
      `nueva_prueba`; sembrar también `LOG_DIR` y `HESTIA_OUTPUT_DIR` en la prueba de retención.

## Pendiente en servidores (lo ejecuta el PO)

- [ ] **Migración real de la cuenta grande** del servidor de pruebas, con la guía
      `docs/hestiacp/tres-escenarios.md`. De punta a punta solo se probó una cuenta pequeña.
- [ ] **Sin probar contra un servidor**: buzones y DKIM, certificados SSL, alias web, cuentas
      grandes, remapeo de IP en una restauración real.
- [ ] **Baja del servidor de pruebas.** Ya no poda (el PO quitó el respaldo Restic del cron el
      2026-09-14). Dos bloqueos de Restic quedaron sin liberar a propósito (`HERENCIA.md`).

## Bugs de `backupctl` encontrados por el banco

- [ ] **Limpieza que no corre al morir** (T20, T21; ADR 0012). Nombrado por el PO el
      2026-09-14. Implementado en `fix/limpieza-al-salir` (sin fusionar, 7 suites en verde).
      **Antes de pedir la prueba al PO** (revisiones de la ronda #023):
      - [ ] `bc_ssh_sudo_stdin`: cerrar la entrada estándar también en `bc_ssh_can_sudo_nopass`
            (T2), con prueba de destino no-root en `probar_adoptar_conf.sh`.
      - [ ] Existencia de `restic.conf` en el destino con centinela (`SI`/`NO`), no con el código
            de `test -e`; registrar la limpieza de `adoptar_conf` solo cuando haya algo que
            deshacer.
      - [ ] Una limpieza que termina en error debe poder reintentarse o avisarse; un fallo de
            `adoptar_conf` no debe ocultar los avisos finales a los usuarios restaurados bien.
      - [ ] `trap '' INT TERM` en `bc_cleanup_all`: sustituir por un trap que no se herede a los
            hijos; prueba que reproduzca `bc_cleanup_all` entero (la mutación M26 no la ve hoy).
- [ ] **`adoptar --snapshot` sin validar** en la CLI (la web sí valida): se interpola entre
      comillas simples y se ejecuta como root en el destino (`adoptar.sh:419,925`). Seguridad.

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
