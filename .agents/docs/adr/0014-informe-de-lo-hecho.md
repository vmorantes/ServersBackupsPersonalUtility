# 0014 — Toda acción que escribe informa de lo que hizo

- **Estado:** Propuesta
- **Fecha:** 2026-09-16
- **Decide:** Arquitecto, por mandato del PO («que me diga qué hizo»)
- **Estructural:** sí (contrato entre `lib/`, la CLI y la web)

## En cristiano

Cada vez que la herramienta cambia algo —en un servidor o en este equipo— deja escrito, en
lenguaje llano, qué había antes, qué hay ahora, qué órdenes ejecutó y cómo se deshace. Ese
informe se ve al terminar, se guarda en el perfil del servidor y se puede volver a abrir desde la
interfaz. Antes de ejecutar, la misma acción enseña el plan: lo mismo que el informe, pero en
futuro.

## Contexto

- Mandato del PO (2026-09-16): activar y configurar los incrementales «pero al mismo tiempo que
  me diga qué hizo». Exigencias previas: estados claros, no destruir, nombrar lo que se pierde.
- Inventario del código (2026-09-16): ninguna acción imprime «antes → después» ni «cómo
  revertir»; `hestia restic` pisa `conf/restic.conf` global sin copia ni valores previos;
  `hestia rclone --desde-repo` sustituye `rclone.conf` entero; `cron` no copia el crontab de
  `hestiaweb`; `.anterior` de un solo nivel que se sobrescribe; la web no relee el estado tras
  actuar.
- Hoy el único registro es la salida en vivo y los logs de `backup`: no sirven para responder
  «qué cambió en el servidor el martes».

## Decisión

1. **Primitivas en `lib/core.sh`** (nombres orientativos):
   - `bc_report_begin <acción> <destino>`: abre un informe (archivo temporal).
   - `bc_report_before <qué> <valor>` / `bc_report_after <qué> <valor>`: valores legibles
     (nunca secretos: las claves se muestran como «presente, 40 caracteres» o su huella).
   - `bc_report_file <ruta-remota> <copia>`: guarda la copia previa de un archivo que se va a
     tocar, con nombre fechado (`<archivo>.backupctl-AAAAMMDD-HHMMSS`), y la anota.
   - `bc_report_cmd <orden>`: orden ejecutada (sin secretos).
   - `bc_report_undo <texto u orden>`: cómo se deshace.
   - `bc_report_end <resultado>`: cierra; lo publica.
2. **Dónde queda**: `<Perfil>/informes/AAAAMMDD-HHMMSS-<acción>.md` en este equipo (el
   directorio del perfil ya guarda `ESTADO.md`). Markdown legible también sin la web. En el
   servidor, las copias previas quedan junto al original con sufijo fechado; nunca se
   sobrescribe una copia anterior.
3. **Plan antes de ejecutar**: toda acción que escribe tiene su ensayo, que lee el estado real y
   muestra el mismo informe en futuro («pasará de X a Y»). Un ensayo que no puede leer el estado
   lo dice: «se escribiría a ciegas».
4. **La web** muestra el plan antes de confirmar y el informe al terminar (arriba, resumido; la
   salida en vivo, plegada debajo), relee el estado de la pestaña, y lista los informes del perfil.
5. **Alcance inicial**: todo el ciclo de incrementales (almacenamiento, host, retención,
   programación, exclusiones, desactivar). Después, el resto de acciones que escriben.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Solo mejorar los mensajes de cada acción | Sigue sin quedar escrito ni poder consultarse después; cada módulo lo haría a su manera |
| Registro en una base de datos | `docs/desarrollo/decisiones.md` descartó ya una base de estado: el sistema de archivos lo es |
| Informe dentro del servidor | Si el servidor desaparece, desaparece el informe; y el PO trabaja desde este equipo |
| Guardar los secretos antes/después para poder revertir | Credenciales en claro en un archivo más; se guarda la copia fechada en el servidor, con los permisos del original |

## Consecuencias

- Más código en cada acción que escribe, y pruebas de banco que comprueban el informe (qué dice
  antes y después) además del efecto.
- Directorios de perfil con más archivos (`informes/`): se podan como los logs.
- Las copias fechadas en el servidor ocupan poco (archivos de configuración) pero se acumulan: se
  documenta cómo limpiarlas.

## Reversión

Quitar las llamadas `bc_report_*` de los módulos y las primitivas; la web vuelve a mostrar solo
la salida en vivo. Los informes ya escritos quedan como archivos sueltos.

## Verificación

Banco: cada acción de incrementales produce un informe con antes, después, órdenes y reversión;
un ensayo produce el plan sin escribir nada (mutación: escribir en el ensayo → falla).
