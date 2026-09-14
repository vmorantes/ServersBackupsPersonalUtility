# Ahora

- **Actualizado:** 2026-09-14 14:50
- **Último mensaje:** #017 (ARQ) — A: commitear ADR 0011/0012 y documentación, borrar ramas
  fusionadas; B: implementar ADR 0012 en `fix/limpieza-al-salir`. Se espera #018.
- **Tramo en curso:** `estado/tramos/2026-09-14-1448-limpieza-al-salir.md` (el anterior,
  `2026-09-14-0949-adopcion-arquitecto-coder.md`, está cerrado).

## Espera al PO

1. **Quitar el enlace de `~/.local/bin`** (lo pediste; la guarda no deja a ningún agente escribir
   fuera del repositorio): `rm ~/.local/bin/backupctl`. Solo borra el enlace, no el programa. El
   lanzador de escritorio ya instalado no lo necesita.
2. **Aviso para tu migración real** mientras no se fusione `fix/limpieza-al-salir`: **no
   interrumpas `adoptar` (Ctrl-C ni cerrar la web) durante una migración.** Si se corta o falla a
   mitad, revisa en el servidor de destino `/usr/local/hestia/conf/restic.conf`: puede haberse
   quedado apuntando al repositorio rescatado (T20).
3. **Tu pregunta 5** (conservar las instantáneas del servidor de pruebas): verificando en el
   código de HestiaCP 1.10.4 antes de darte los pasos.
4. **`git push` de `master`** cuando quieras («Luego subo»).
5. En cada sesión nueva, los dos `/rename`.

## En curso

Ronda #017 en vuelo, dos tareas con puerta propia:

- A: rama `docs/adr-0011-0012`: guarda (borrado de ramas, redirecciones), ADR 0011 y 0012,
  reglas, trampas, roadmap, `estado/`; fusionar; borrar `chore/adopcion-arquitecto-coder`,
  `feat/banco-de-pruebas`, `docs/cierre-tramo-adopcion` y la propia `docs/adr-0011-0012`.
- B: rama `fix/limpieza-al-salir`: registro de limpiezas en `lib/core.sh` y su uso en `restore`,
  `verify`, `pull`, `restic`, `adoptar`; pruebas en el banco. NO se fusiona: toca lo que corre en
  servidores, espera tu prueba con la guía que dejará aquí el arquitecto (ADR 0007).

Si se corta ahora: A es solo documentación; B quedaría en su rama.

## Para una sesión nueva

`serversbackupspersonalutility-68` y `humilde_trabajador_presente_backups` no son parte del
trabajo. El coder es `ServersBackupsPersonalUtility-Coder-Main`.
