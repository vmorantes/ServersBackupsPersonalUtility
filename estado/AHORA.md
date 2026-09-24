# Ahora

- **Actualizado:** 2026-09-24, madrugada.
- **Último mensaje:** #047 (ARQ). El próximo será #048. Ronda en vuelo: estilos propios de la
  documentación.
- **Ramas:** solo quedan `master` (estable, sin la 2.1) y `release/2.1`, que ya tiene la fase 1
  y lo del incidente (`562e02e`). El PO pidió unificar; `master` espera su prueba en servidor
  (ADR 0007 y 0013). Borradas: `fix/limpieza-al-salir`, `fix/incrementales-rutas`,
  `backupctl-2.0`, `version-inicial`.
- **Tramo:** `estado/tramos/2026-09-23-2145-incidente-incrementales.md`, cerrado.

## Cambio de tema de la documentación (decisión del PO, 2026-09-24)

El PO deja Material por el tema `readthedocs` incorporado: le parece más ameno y así el sitio
deja de depender de `mkdocs-material`, que queda sin parches de seguridad el **2027-05-05**.
Dijo qué quiere cubrir con CSS y JavaScript propios: «lo importante no tonterías como modo
oscuro sino los recuadros copiables y los tabs en secciones».

Hecho por el arquitecto (sin commitear al abrir la ronda): las 21 pestañas de Material
convertidas en secciones de nivel 3 en 8 páginas, retirada `pymdownx.tabbed`, quitada la
sintaxis que solo entiende Material (tarjetas, iconos y botones en `index.md`,
`paso-a-paso/index.md` y `referencia/chuleta.md`), tema cambiado en `mkdocs.yml` con
`highlightjs: false`, y `verificar.sh` comprueba también el JavaScript de `docs/estilos/`.

Verificado antes de decidir (informe completo en el scratchpad de la sesión): MkDocs 2.0 **no
existe** como versión estable (solo pre-lanzamientos) y Material se fija en `mkdocs<2`, así que
el aviso que ve el PO al construir no describe ningún riesgo para este repositorio; se silencia
con `NO_MKDOCS_2_WARNING=1`. Lo que sí tiene fecha es el fin de los parches de Material.
Ningún tema vivo de MkDocs tiene la estética de `readthedocs`: los que se le parecen llevan
muertos entre 2018 y 2023.

**Nadie ha construido el sitio todavía**: ni `mkdocs build` ni `mkdocs serve` están permitidos
aquí. Lo comprueba el PO.

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
