# Convenciones

Cómo se escribe aquí. Lo que ya explica `docs/desarrollo/arquitectura.md` («Convenios»,
«Añadir una orden nueva») se cita, no se copia: si divergen, gana el código y se corrigen los
dos.

## Exigencias del PO que condicionan todo el código

Vienen de la sesión que construyó el proyecto (`../HERENCIA.md`) y de la memoria del PO. No
son preferencias de estilo: son requisitos de producto.

1. **La interfaz web es el centro.** Todo lo que hace `bin/backupctl` debe poder hacerse desde
   `web/`, con un botón por acción (granularidad máxima, para evitar accidentes). La CLI es para
   servidores y cron. Una orden nueva sin su botón está a medias.
2. **Estados claros.** Antes de ofrecer una acción, se muestra lo que ya hay configurado, con
   el valor concreto leído del servidor. Los formularios se rellenan con lo que ya hay, para
   que reenviarlos no cambie nada. Lo hecho se marca como hecho.
3. **No destruir.** Si una acción pisa algo existente, la confirmación nombra el valor que se
   pierde. Si no se puede leer el estado, se advierte de que se escribiría a ciegas. Antes que
   añadir a ciegas, detectar y negarse a duplicar.
4. **Cada acción declara su alcance**: si solo lee, si escribe o si destruye, y sobre qué
   (una base, una cuenta, todo el HestiaCP).
5. **Verificar por fuera.** El éxito lo decide una comprobación independiente (conteos,
   sumas, el panel), no el mensaje de la propia orden: ya ha dado éxitos en falso.

## Bash (`bin/`, `lib/`)

- Convenios de `docs/desarrollo/arquitectura.md`: prefijo `bc_` en lo público, guarda de carga
  múltiple, nada se ejecuta al cargar un módulo, opciones por variables `BC_OPT_*`,
  `set -Eeuo pipefail` solo en `bin/backupctl`, `bc_die` y `BC_DELIBERATE_EXIT` para las
  salidas decididas.
- Indentación de **2 espacios**, como el código existente.
- Variables entre comillas siempre.
- **Credenciales**: nunca en la línea de órdenes (las ve cualquiera con `ps`). MySQL por
  archivo de opciones (`docs/desarrollo/decisiones.md`, «Fichero de credenciales»); contenido
  sensible hacia el servidor por la entrada estándar con `bc_ssh_sudo_stdin`, nunca con
  `bc_ssh_sudo` (trampa T2).
- `ssh` dentro de un bucle `while read`: entrada estándar cerrada (`< /dev/null`), o se come
  el resto del bucle (`lib/hestia.sh:65-68`).
- **Reescribir un archivo existente, siempre en tres pasos**: generar el resultado en un
  temporal del mismo directorio, comprobar el código de salida y que el contenido es sensato
  (no vacío, conserva lo que siempre debe estar), y solo entonces sustituir con `mv`
  conservando modo y propietario. Si algo falla, el original queda intacto.
- `--dry-run` real: no escribe, no conecta para escribir, no borra. Confirmaciones que sin
  terminal se degradan a «no»; `--yes` para lo contrario (`decisiones.md`).
- Órdenes remotas que no dejan archivos de root en el árbol del usuario (commit `67e43bc`).

## Una orden nueva

Los seis pasos de `docs/desarrollo/arquitectura.md` («Añadir una orden nueva»), más:

7. Su acción y su botón en `web/` (`web/server.py`, `web/app.js`, `web/index.html`), y
   `python3 web/comprobar.py` en verde.
8. Su línea en `docs/referencia/chuleta.md` si es de uso diario.

## Python (`web/`)

- Solo biblioteca estándar. Una dependencia nueva, con propuesta y alternativas
  (`00-core.md`).
- La web escucha solo en `127.0.0.1` (según la sesión anterior; confirmar en
  `.agents/context/10-mapa-del-sistema.md`).

## Pruebas

- Sin servidor, sin MySQL real y sin HestiaCP: en el banco `tests/`, con las piezas de
  `tests/lib.sh` (`.agents/context/40-entorno.md`).
- Las afirmaciones no se hacen dentro de `$(...)` ni de una tubería: una subshell pierde lo
  que cuenta (la trampa de `arquitectura.md` vale también para las pruebas).
- Un patrón de texto que se afirma debe ser el del fallo, no una palabra que también sale
  en el éxito (`suma` salía en los dos mensajes de `verify`).
- **Cubren el camino de fallo** de todo lo que escribe, borra o restaura: el original queda
  byte a byte igual (`cmp`) cuando la operación no puede completarse.
- **Temporales con prefijo propio** (`mktemp -d -t backupctl-pruebas.XXXXXX`), para comprobar
  que no queda ninguno sin contar entradas de un `/tmp` compartido.
- Nombres de test en inglés; cuerpo y comentarios en español.

## Textos y documentación

- Español en todo lo visible. Sin menciones a IA (regla 40 §4).
- **Agnóstica**: ningún servidor, dominio, cuenta, base de datos ni IP real del PO, ni su
  nombre como placeholder. Ejemplos con `example.org`, `203.0.113.10` (RFC 5737), perfiles
  `MiServidor` o `Ejemplo`.
- Guías de operación: primero los pasos de la web, separando lo probado de lo no probado.
- Una página nueva de `docs/` va también a la `nav` de `mkdocs.yml`.

## Commits

Conventional Commits en español, imperativo, subject ≤ 50. **Desde la adopción** (ADR 0001):
los 47 commits anteriores son frases libres y no se reescriben. Ámbito = módulo o área cuando
aplica: `fix(adoptar): ...`, `feat(web): ...`, `docs(hestiacp): ...`. Para la infraestructura
de agentes: `chore(agentes): ...`; para `estado/`: `docs(estado): ...`.
