# 0017 — Incrementales de punta a punta: los hechos corregidos

- **Estado:** Aceptada
- **Fecha:** 2026-09-23
- **Decide:** Arquitecto, por mandato del PO («Dale fase 1 y 2»)
- **Estructural:** sí (qué escribe la herramienta en el servidor y de qué se fía para decir que algo salió bien)
- **Reemplaza:** 0016
- **Se apoya en:** 0013 (versión 2.1), 0014 (informe de lo hecho), 0015 (interfaz por tareas)

## En cristiano

El plan del ADR 0016 sigue en pie, pero cuatro de los hechos en los que se apoyaba eran falsos, y
uno de ellos cambia la regla más importante: **HestiaCP puede decir que un respaldo incremental
salió bien cuando ha fallado**. Por eso la herramienta no creerá nunca a HestiaCP: comprobará que
existe una instantánea nueva. Este ADR corrige los hechos y ajusta los pasos que dependían de
ellos. Lo demás del 0016 se mantiene tal cual.

## Por qué se reemplaza el 0016 y no se corrige

Los ADR son inmutables una vez commiteados (`.agents/docs/adr/README.md`). El 0016 se commiteó el
2026-09-16 con hechos verificados que resultaron incompletos: la verificación de aquel día no
cubrió el manejo de errores de `v-backup-user-restic` ni el contenido real de `backup.log`. La
decisión de fondo no cambia; cambian los cimientos, y un cimiento equivocado dentro de un ADR es
justo lo que una sesión futura leería como verdad.

## Los cuatro hechos corregidos (fuente 1.10.4, verificados el 2026-09-23)

### 1. Un respaldo incremental que falla se registra como correcto — CONFIRMADO

`bin/v-backup-user-restic:80` usa `check_result $E_BACKUP "Unable to backup user"`, y `E_BACKUP`
**no está definida** en `func/main.sh` ni en `func/backup.sh`, `func/domain.sh` o `func/db.sh`,
que son los cuatro que el script carga. El bloque de constantes va de `OK=0` a `E_RESTART=20` y no
la incluye.

Con la constante vacía, la llamada llega a `check_result` con el mensaje como primer argumento, la
comparación numérica de dentro no puede evaluarse, la rama no ejecuta su `exit`, y el script
continúa hasta `log_event "$OK"` (línea 115). Es decir: **fallo del respaldo, salida `0` y registro
de éxito**. La lectura del código es CONFIRMADA; la consecuencia exacta en bash está razonada a
partir de `check_result`, no ejecutada (aquí no hay servidor).

**Consecuencia para nosotros:** ni el código de salida de `v-backup-user-restic` ni lo que HestiaCP
registre valen como prueba. Solo vale una instantánea nueva.

### 2. `$HESTIA/log/backup.log` no tiene nada que ver con los incrementales — CONFIRMADO

Lo escribe únicamente `bin/v-backup-users` (el clásico, con `>> $log` alrededor de cada usuario).
`v-backup-user-restic` no lo menciona en ninguna línea. El 0016 decía lo contrario y hacía depender
de él la comprobación del paso 6. **El incremental no deja rastro en ningún log de archivo**: solo
`v-log-action`, que va al registro de acciones del panel.

### 3. «Borrar el host de respaldo» no desactiva las cuentas — CONFIRMADO

`v-delete-backup-host-restic` borra `conf/restic.conf` y pone `BACKUP_INCREMENTAL='no'` en
`hestia.conf` (flag **de sistema**). Pero lo que de verdad frena a `v-backup-user-restic` es
`BACKUPS_INCREMENTAL` (con `S`) en el `user.conf` de **cada cuenta**, que nadie toca. Tras
«desactivar», las cuentas siguen marcadas como activas y lo único que las detiene es que el
repositorio queda mal formado al faltar `restic.conf`.

### 4. `v-change-user-config-value` con una clave ausente no es inofensivo — CONFIRMADO

Si la clave no está en `user.conf`, **dispara `v-rebuild-user` completo** (`useradd` si falta el
usuario del sistema, reescritura de permisos, `usermod`, jaula sftp, colas de disco y tráfico) y
después llama a `update_user_value`, que solo escribe si la línea existe. `rebuild_user_conf` solo
sabe reparar una lista cerrada de claves (`TWOFA`, `QRCODE`, `PHPCLI`, `ROLE`, `THEME`,
`PREF_UI_SORT`, `LOGIN_DISABLED`, `LOGIN_USE_IPLIST`, `LOGIN_ALLOW_IPS`, `RATE_LIMIT`), y
`BACKUPS_INCREMENTAL` **no está en esa lista**.

El 0016 ya decía «comprobar antes y no intentarlo»; lo que no sabía es el precio de intentarlo.

### 5. Un formato desconocido en `v-list-user-backups-restic` devuelve vacío y `0` — CONFIRMADO

Solo implementa `json` y `plain`, el `case` no tiene rama por defecto y el parámetro de formato
**no se valida**. Un formato distinto no produce error: produce silencio con código `0`, que se
leería como «esta cuenta no tiene copias».

## Decisión

Se mantiene todo el ADR 0016 salvo lo siguiente.

### Regla de oro: nada se da por bueno sin una instantánea

Toda comprobación de que un respaldo incremental funcionó se hace comparando la **lista de
instantáneas antes y después**, con su fecha, leída con `v-list-user-backups-restic <cuenta> json`
(o `restic snapshots` directo si aquello falla). El código de salida y el registro de HestiaCP se
muestran como dato, nunca como prueba.

`hestia status` diagnostica además el caso que ningún log revela: **la última instantánea es más
antigua que la periodicidad del cron**. Con el cron cada noche y una instantánea de hace tres días,
lo dice en esos términos.

Todo lo diagnosticable sin servidor —interpretar una línea de cron, decidir si una fecha es
demasiado vieja, cruzar «tiene contraseña» con «tiene repositorio»— vive en **funciones puras**
que el banco prueba sin ssh. Lo que necesita el servidor es solo la lectura; el juicio, no.

### Paso 6 (primera copia) — corregido

Se lee la lista de instantáneas, se ejecuta `v-backup-user-restic <cuenta>`, se vuelve a leer, y se
informa por la diferencia. Si no apareció ninguna instantánea nueva, es un **fallo**, aunque la
orden haya terminado con `0`. Se desecha la lectura de `backup.log` que proponía el 0016.

### Paso 3 (cuentas) — corregido

Antes de `v-change-user-config-value` se comprueba que `BACKUPS_INCREMENTAL` existe en el
`user.conf` de esa cuenta. Si no existe, **no se llama**: se explica que esa cuenta es anterior al
paquete que trae la clave y se ofrece la vía del paquete, diciendo qué cuentas arrastra. Motivo
nuevo: llamarlo dispararía un `v-rebuild-user` completo, que es una operación mucho mayor de lo que
el usuario pidió, y encima acabaría sin escribir nada.

### Paso 8 (desactivar) — corregido

Desactivar de verdad son dos cosas, y se hacen y se informan por separado:

1. Quitar la línea del cron y `v-delete-backup-host-restic` (lo que ya decía el 0016).
2. Poner `BACKUPS_INCREMENTAL='no'` en las cuentas que lo tuvieran en `yes`, una por una, con
   relectura.

Si solo se hace lo primero, se dice explícitamente: «las cuentas siguen marcadas para respaldo
incremental; si mañana vuelves a registrar un repositorio, empezarán a respaldar solas».

### No hay orden `hestia estado`: se amplía `hestia status`

El 0016 proponía una orden nueva, `hestia estado`, junto a la `hestia status` que ya existe y que
ya lee la configuración, los remotos, el cron y las claves. Dos órdenes con el mismo nombre en dos
idiomas, que hacen casi lo mismo, es exactamente lo que el PO lleva meses diciendo que le pesa de
esta herramienta («13 pestañas, 68 acciones»). **El diagnóstico se añade a `hestia status`**, que
pasa de describir la configuración a decir si funciona. La web llama a la misma.

Regla general para toda la fase 2: **antes de añadir una orden, mirar si amplía una que ya está.**

### Lecturas

`v-list-user-backups-restic` se llama **siempre** con `json` explícito, y una salida vacía se
distingue de un error: si la orden devuelve `0` con salida vacía, se contrasta con
`restic snapshots` antes de afirmar que la cuenta no tiene copias.

## Consecuencias

- La herramienta dirá, de un servidor bien configurado según HestiaCP, cosas que el panel no dice:
  que el último respaldo no se hizo, que una cuenta está marcada pero sin repositorio, que el cron
  está en el sitio equivocado.
- Eso hará que a veces contradiga al panel. Es el objetivo, no un efecto secundario.
- Dependemos de 1.10.4. Si el PO actualiza HestiaCP y el bug de `E_BACKUP` se arregla, nuestra
  comprobación sigue siendo válida: comprobar la instantánea no sobra nunca.

## Reversión

Igual que el 0016: las órdenes nuevas se retiran sin tocar las existentes.

## Verificación

Banco: una prueba con un `v-backup-user-restic` falso que **falla pero devuelve 0 y no crea
instantánea**; la herramienta tiene que reportar fallo. Mutación: hacer que se fíe del código de
salida → la prueba falla. Servidor (PO): comprobar en el suyo que la instantánea del día existe.
