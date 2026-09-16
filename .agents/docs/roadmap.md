# Roadmap

Lo que falta, ordenado por lo que costaría no tenerlo. **No es una promesa**: es la lista de
la que elige el Product Owner. El arquitecto propone; no convierte nada de aquí en una
instrucción sin que el PO lo nombre.

Una tarea sale de aquí al cerrarse; su historia queda en la bitácora. Referencias
`T<n>` = trampa n de `.agents/context/30-trampas.md`.

---

## Versión 2.1 estable (nombrado por el PO el 2026-09-16; ADR 0013)

Mandato: «rigurosa y bonita como tú quieras; activar y configurar los incrementales desde ella,
sin HestiaCP, y que me diga qué hizo; potenciarla; dejar una versión estable». Todo en la rama
`release/2.1`.

- [ ] **Fase 1 — Rigor.** Terminar `fix/limpieza-al-salir` (T20/T21, los cuatro puntos de abajo)
      y llevarla a `release/2.1`; aviso falso de `adoptar --como`; `adoptar --snapshot` sin
      validar; otros ALTA de las revisiones.
      Después de la fase 1, hallazgos de #031 que no la bloquean: `adoptar --to` no limpia la
      sección que añade al `rclone.conf` del destino y aborta a mitad con sudo con contraseña;
      reintento de `adoptar_conf` con la conexión ya cerrada; hasta tres intentos inútiles de
      devolver `restic.conf`; camino `bc_ssh_tty` sin prueba; la contraseña de panel sale por
      stdout (puede quedar en un log); registro de limpiezas solo en memoria.
- [ ] **Fase 2 — Incrementales de punta a punta desde la herramienta.** Activar, configurar
      (almacenamiento, retención, programación, exclusiones), comprobar y desactivar Restic de
      HestiaCP sin entrar al panel, usando su mecanismo propio por debajo. Toda acción que escribe
      informa de lo hecho: qué había antes, qué cambió, qué órdenes se ejecutaron y cómo se
      deshace. Necesita verificación en la fuente de HestiaCP y ADR.
- [ ] **Fase 3 — Interfaz rigurosa y bonita.** Diagnóstico de tareas, maqueta, ADR; organizada
      por tareas, estado y siguiente paso a la vista, lo avanzado plegado.
- [ ] **Fase 4 — Salida.** Documentación de usuario al día (incluida
      `docs/desarrollo/arquitectura.md`), `CHANGELOG.md`, versión 2.1.0, guía única de prueba para
      el PO, su conformidad, fusión en `master` y etiqueta `v2.1.0`.

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

- [ ] **`adoptar --como` informa «no se hizo el traslado» cuando solo faltan las bases**
      (visto por el PO en el servidor de pruebas, 2026-09-16). En el script remoto
      (`lib/adoptar.sh:1180-1181`), `grep -c . || echo 0` produce `0` y otro `0` cuando no hay
      coincidencias: `[` falla con «integer expression expected», se pierde el aviso «el respaldo
      tenía N bases y solo hay M», y el mensaje final generaliza. Además, en ese camino de error
      no se muestra la contraseña de panel de la cuenta creada. Mismo patrón en `ESPERADAS`
      (1180). Nombrarlo al PO antes de arreglarlo.

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

- **La interfaz web es pesada y poco intuitiva** (queja recurrente del PO; la última, el
  2026-09-16; ya el 2026-09-06: «me turba y abruma»). Hechos: 13 pestañas, 68 acciones
  (`web/comprobar.py`), cada una con su párrafo; acciones duplicadas «en local» y «vía el
  backupctl del servidor»; el PO no encontró «Resucitar» en la fila de pestañas. Choca con dos
  exigencias suyas que empujan en sentido contrario: «un botón por acción, granularidad máxima»
  y «estados claros». Antes de tocar código: diagnóstico con el PO de qué tareas hace de verdad, y
  propuesta de diseño (maqueta) con ADR.

- **Paridad web ↔ CLI.** El PO quiere que todo lo que hace `bin/backupctl` pueda hacerse
  desde `web/`, con botones atomizados. `web/comprobar.py` comprueba parte; falta saber si la
  paridad es completa hoy.
