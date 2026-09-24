# Ahora

> **Para retomar, empieza aquí y sigue por «Dónde se quedó la fase 2».** El tramo se cerró a
> petición del PO con la fase 2 en siete pasos y medio de ocho.
>
> **Todo commiteado**, árbol limpio y `verificar.sh` en verde: 23 suites, 668 afirmaciones,
> guarda 193/193.
>
> **Un ejemplo de nuestra documentación rompió un SEGUNDO servidor del PO el 2026-09-24**, el
> mismo día. Causa: el 23 se corrigieron cuatro sitios de `protocolo-manual.md` y **no se hizo
> el barrido completo**; quedaban ocho ejemplos con rutas relativas en cuatro archivos, y uno
> era el `rclone mkdir` del paso 2. Corregidos todos, y añadido a `verificar.sh` el paso
> **«Rutas relativas en ejemplos de almacenamiento»**, que falla si alguien escribe en `docs/`
> una orden que CREA algo con una ruta que no empiece por `/` ni por `<`. Probado en las dos
> direcciones. La lección, para quien venga: **una corrección parcial que se anuncia como
> completa es peor que no corregir**, porque el que la lee se fía.

- **Actualizado:** 2026-09-24, al cerrar el tramo.
- **Último mensaje:** #081 (ARQ). El próximo será #082. Sin ronda en vuelo: el coder espera
  instrucción.
- **Tramo abierto:** `estado/tramos/2026-09-23-2300-fases-1-y-2.md`. Mandato del PO: «Dale fase
  1 y 2».
- **Ramas:** `master` (estable, sin la 2.1) y `release/2.1`, con todo el trabajo. Sin subir.
- **Aviso de continuidad:** las sesiones se cortaron otra vez (tercera). El coder commiteó la
  ronda #079 y su reporte (#080) no llegó; se recuperó pidiéndoselo de nuevo. Nada perdido.

## Espera al PO

### 1. Su producción, comprobada esta mañana: FUNCIONA

El cron de la 01:00 hizo su copia (instantánea `52e642b7`, 2026-09-24). Comprobado con
`restic snapshots`, no con el panel. Pendiente suyo, menor:

- `tar tzf /root/claves-restic-<fecha>.tgz` y `ls -la /IncrementalBackups/`: si el número de
  contraseñas guardadas no coincide con el de repositorios, la cuenta `administrator` no está
  marcada para respaldo incremental. Que lo decida él, no el olvido.
- **Bajarse el `.tgz` fuera del servidor.** Mientras viva solo dentro de lo que protege, no
  protege nada.

### 2. Tres guías de prueba listas, para el servidor de PRUEBAS

Son de la fase 2 y **nada de esto se ha ejecutado nunca contra un HestiaCP real**. Las tres
empiezan por un ensayo que no toca nada. Están enteras en los reportes #076, #078 y #080; lo
esencial:

| Paso | Orden | Lo que hay que comprobar por fuera |
| --- | --- | --- |
| Registrar el repositorio | `hestia restic --repo '<repo>'` | el panel muestra lo pedido; el `.bak` tiene lo anterior; el informe coincide con el panel |
| Programar el respaldo | `hestia cron` | `crontab -u hestiaweb -l` muestra la línea con ruta absoluta; el crontab queda `600 hestiaweb:hestiaweb` |
| Marcar las cuentas | `hestia cuentas` | `grep BACKUPS_INCREMENTAL .../users/*/user.conf`; y que **la cuenta siga igual en todo lo demás** (shell, cuotas, dominios) |

**Orden recomendado**: ensayo primero, siempre. Y en el de las cuentas, empezar por **una sola**
(`--usuarios <cuenta>`) antes de lanzarlo sobre todas: lo que sabemos de esa orden de HestiaCP
viene de leer su código, no de ejecutarlo.

La prueba de verdad de los tres tarda un día: al día siguiente, `hestia status` tiene que
enseñar una instantánea reciente.

### 3. Lo de siempre

- `git push` cuando quiera. `rm ~/.local/bin/backupctl` sigue pendiente.
- **Resuelto, NO es un fallo:** la base `stc-admin_stc_website_db` está excluida **a propósito**
  (datos sensibles; su aplicación genera volcados ofuscados, que HestiaCP no sabría producir).
  No volver a señalarlo como agujero.
- Esos volcados viven en `public_html/dumps/`, dentro de un dominio público y con permisos
  `777`. Él dice que los protege un `.htaccess`; **pendiente de comprobar desde fuera**, porque
  ese archivo solo lo lee Apache: si el dominio lo sirve nginx, no protege nada.
  `curl -sI https://<dominio>/dumps/<archivo>` y
  `grep -E '^WEB_SYSTEM|^WEB_BACKEND|^PROXY_SYSTEM' /usr/local/hestia/conf/hestia.conf`.
  Son el único respaldo de esa base: si se pierden, se pierde.
- Sin mirar todavía: `public_html` entero en `777`, y `secure-keys/` dentro de la raíz web.
- **AVISO (T21):** antes de un `adoptar --to` real, copiar el `restic.conf` del destino.
- Los dos `/rename`, al abrir y al cerrar cada sesión (lo pidió expresamente el 2026-09-24).
  **Decisión del PO del 2026-09-24: el renombrado es OBLIGATORIO para trabajar.** No se emite la
  primera instrucción hasta que los dos nombres estén puestos y comprobados en la lista de
  sesiones. Sigue siendo obligatoria además la identificación (pedir al candidato un dato
  verificable del repositorio): el nombre no la sustituye. **Pendiente del arquitecto:** llevarlo
  a `.agents/rules/30-protocolo-coder.md` en cuanto termine la ronda en vuelo.

## Dónde se quedó la fase 2 (lo primero que hay que leer al retomar)

**Hecho y probado: el diagnóstico y siete de los ocho pasos** — registrar el repositorio,
programar el respaldo, marcar las cuentas, la primera copia comprobada, rescatar las claves,
desactivar, y el almacenamiento. Cada uno con ensayo, copia fechada, comprobación leyendo del
servidor e informe de qué se hizo y cómo deshacerlo. 22 suites en el banco.

**A medias: el paso 8, las exclusiones.** Está en **solo lectura** a propósito: muestra qué no
se respalda, traducido, y no ofrece escribir. El detalle exacto de qué quedó escrito y qué
desactivado está en el reporte del coder de la ronda de cierre.

**Lo que falta para poder terminarlo** (y no se debe escribir nada sin esto):

1. **El efecto real de cada exclusión, ya VERIFICADO** (llegó justo al cerrar; no se ha escrito
   nada con ello todavía):
   - **WEB — confirmado, y es el hallazgo:** `v-backup-user-config` solo copia *configuración*
     (vhost, SSL, plantillas); **nunca** el contenido del sitio. Y ese contenido vive en
     `/home/<cuenta>/web/<dominio>/public_html`, o sea **dentro** de lo que copia
     `restic backup /home/<cuenta>`. Conclusión: **excluir WEB no impide que los archivos del
     sitio acaben en la instantánea.** Solo evita que se preparen sus metadatos.
   - **DB — al revés, y por eso la exclusión del PO sí funciona:** el volcado no existe en el
     disco hasta que ese script lo genera. Si la base está excluida, no se genera, y no hay nada
     que copiar.
   - **DNS — sin el problema:** el archivo de zona *es* el contenido.
   - **MAIL — SIN VERIFICAR.** Solo se confirmó que se copia configuración, no los mensajes; no
     se miró dónde viven los buzones. **Es lo único que queda abierto.**
2. Con eso, el paso tiene que decir **por sección qué efecto real tiene excluirla en cada uno de
   los dos respaldos**, quitarle el modo solo lectura (hay un `bc_err` explícito que lo impide,
   con su comentario) y volver a poner las dos pruebas que se quitaron, documentadas en la
   propia suite.

   Nota de método: esa verificación se hizo sin poder ejecutar nada, así que da texto literal
   contrastado dos veces pero **no números de línea**. Para citarla en `50-hestiacp.md` con
   ancla hace falta un `grep -n` que alguien con shell haga sobre la fuente pública.

**Verificado en esta sesión y ya en `50-hestiacp.md`:** hay **dos implementaciones gemelas** de
las exclusiones. `v-backup-user` (clásico) filtra con seis claves —WEB, DNS, MAIL, DB, CRON y
**USER**— y `v-backup-user-config` (el que usa el incremental) con cinco, sin USER. Cada una
tiene su propio `source`, que va **antes** de las secciones que filtran. `v-backup-user-restic`
llama al segundo y nunca al primero. Dos verificaciones se contradijeron por mirar cada una un
archivo: la lección está abajo.

**Después de cerrar el paso 8 queda, para dar la fase 2 por terminada:** la revisión de
seguridad y de código de todo lo de estos dos días (obligatoria: se ha tocado mucho código que
corre como root), arreglar lo que salga, y la documentación de usuario de las órdenes nuevas,
que escribe el arquitecto.

## Dónde va la versión 2.1 (ADR 0013, 0017)

- **Fase 1 — terminada.**
- **Fase 2 — tres de ocho pasos**: diagnóstico (la base), registrar el repositorio, programar el
  respaldo, marcar las cuentas. **Faltan**: almacenamiento (`hestia rclone`), exclusiones,
  primera copia comprobada, claves (`hestia keys`), desactivar. Y llevarlo todo a la web y a la
  TUI.
- **Fases 3 y 4** sin empezar. La 3 (interfaz) necesita una sesión de diseño con el PO.

Estimación dada al PO: 6–9 rondas para cerrar la fase 2.

## AVISO VIGENTE: la web puede contradecir a la línea de órdenes

Encontrado en la ronda #092. La web **no siempre pasa por `backupctl`**: lee el servidor por su
cuenta en al menos tres sitios (configuración de Restic, lista de cuentas, y qué cuentas tienen
clave) y decide con eso. Son **dos implementaciones** de la misma pregunta.

Todo lo construido en la fase 2 —distinguir «no» de «no se pudo leer», exigir el huso de las
fechas, no fiarse del código de salida de HestiaCP— vive **solo en la línea de órdenes**. La web
puede enseñar un estado distinto del mismo servidor sin que nadie sepa cuál creer.

**Decisión del PO (2026-09-24): se aborda en la fase 3**, con el rediseño de la interfaz, no
antes. Motivo: no añadir superficie a una web que ya le pesa, y decidir allí qué tareas hace de
verdad. Consecuencia mientras tanto, y hay que decírselo cuando pruebe: **para diagnosticar, la
línea de órdenes; si las dos discrepan, manda `hestia status`.**

Segundo hallazgo de la misma ronda: la web llama a todo con `-y`, así que las dos negativas
nuevas (desactivar sin claves rescatadas, y pisar un remoto existente) se dispararán ahí con
mensajes escritos para una terminal. Protegen igual; se verán mal. También para la fase 3.

## Pendiente de decidir o de cerrar

- **Zona horaria (#081)**: en el servidor del PO, la misma instantánea se imprimió con cinco
  horas de diferencia entre dos sesiones. `bc_hestia_diag_instantanea` compara esa fecha con
  «ahora»: si las dos puntas no están en la misma referencia, un respaldo que se saltó una noche
  puede parecer reciente. **Falso OK.** El coder está mirando si ya está bien resuelto.
- **H36**: `hestia cuentas` no aparece en la TUI, y ninguno de los pasos nuevos está en la web.
  La interfaz es el centro (`20-convenciones.md`): hay que cerrarlo antes de dar la 2.1.
- **H34** (decidido, se queda): cada cuenta se lee dos veces, una para la foto que se enseña y
  otra justo antes de escribir. Entre las dos hay una persona decidiendo; escribir sobre la
  lectura vieja sería escribir a ciegas.
- **Sin verificar contra un servidor real**: que `v-change-user-config-value` con la clave
  presente no toque nada más que esa clave. Lo que sabemos viene de leer su código.

## Para una sesión nueva

- Lee este archivo, el tramo abierto, y los ADR 0013, 0014, 0015 y **0017** (el 0016 está
  reemplazado).
- `.agents/context/20-convenciones.md` («vacío no es lo mismo que no lo sé»),
  `30-trampas.md` T2 y T20–T26, `40-entorno.md` (el banco y sus salvaguardas) y `50-hestiacp.md`
  entero: lo verificado ahí no se vuelve a verificar.
