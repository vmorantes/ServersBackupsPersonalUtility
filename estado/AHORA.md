# Ahora

- **Actualizado:** 2026-09-23, cierre del día.
- **Último mensaje:** #042 (COD). El próximo será #043. Ninguna ronda en vuelo.
- **Tramo:** `estado/tramos/2026-09-23-2145-incidente-incrementales.md`, cerrado.
- **Rama del árbol:** `release/2.1`, con la fase del incidente ya fusionada (`b811405`).
- **Sin commitear:** este archivo, el cierre del tramo, la sección nueva de
  `docs/hestiacp/protocolo-manual.md` («Quedarse solo con los incrementales») y lo añadido a
  `.agents/context/50-hestiacp.md`. Los commitea la ronda #043.

## Espera al PO

1. **Su servidor de producción quedó funcionando**: repositorio en `/IncrementalBackups/stc-admin`,
   instantánea `200953a7` comprobada con `restic snapshots`, cron a la 01:00 en el crontab de
   `hestiaweb`. Nada urgente pendiente ahí.
2. **Mañana:** comprobar que el cron respaldó (una instantánea con fecha del 24, y un directorio
   por cada cuenta del panel) y rehacer el `.tgz` de las claves, porque cada cuenta nueva trae la
   suya. Sin esas contraseñas ningún repositorio se abre.
3. **Decidido con él, sin ejecutar:** puede quitar el respaldo clásico (`v-backup-users` de las
   05:10 en el crontab de `hestiaweb`) y borrar `/backup/*.tar`. **No** debe vaciar
   `BACKUP_SYSTEM`: apagaría también los incrementales.
4. Fuera del alcance de los respaldos, visto en su servidor: `public_html` entero en `777`, y
   `secure-keys/` y `dumps/` dentro de la raíz web. Sin mirar todavía.
5. `git push` cuando quiera (`master` y `release/2.1`). `rm ~/.local/bin/backupctl` sigue
   pendiente.
6. **AVISO (T21):** antes de un `adoptar --to` real, copiar el `restic.conf` del destino y
   compararlo al terminar.
7. Los dos `/rename`, que el arquitecto le da al abrir y al cerrar cada sesión.

## Siguiente (mandato del PO: versión 2.1, ADR 0013)

- **Fase 1**, en `fix/limpieza-al-salir`: quedan S4–S8 de la instrucción #032 y la revisión final.
  Al fusionarla en `release/2.1` habrá conflicto en los archivos de documentación del incidente
  (están duplicados por los cherry-pick `f16f18c` y `b07d51e`): se resuelve **quedándose con la
  versión de `release/2.1`**, que es la posterior.
- **Fase 2** (ADR 0016): crecida con lo aprendido hoy; la lista está en el roadmap. Lo más
  urgente de ahí: diagnosticar «hay contraseña pero no hay repositorio», comprobar dónde está el
  cron, mostrar las bases excluidas, y avisar del área de preparación que nadie limpia.
- Fases 3 (ADR 0015) y 4 sin empezar.

## Para una sesión nueva

- Lee el tramo del 23, el del 16, ADR 0013–0016 y `.agents/context/30-trampas.md` T2, T20–T26.
- Ramas: `master` (estable), `release/2.1` (versión en curso, con lo del incidente),
  `fix/limpieza-al-salir` (fase 1, sin fusionar).
- Lo verificado hoy en la fuente de HestiaCP 1.10.4 está en `.agents/context/50-hestiacp.md`: no
  se vuelve a verificar.
