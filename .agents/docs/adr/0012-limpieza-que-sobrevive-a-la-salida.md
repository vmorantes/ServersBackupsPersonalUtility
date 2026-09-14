# 0012 — La limpieza se registra y se ejecuta al salir, pase lo que pase

- **Estado:** Aceptada (sin implementar)
- **Fecha:** 2026-09-14
- **Decide:** Arquitecto, con el mandato del PO de arreglar T20 («Adelante, trabajen»)
- **Estructural:** sí (un contrato nuevo entre `lib/core.sh`, `bin/backupctl` y los módulos)

## En cristiano

Muchas órdenes de `backupctl` dejan algo a medias mientras trabajan: una carpeta temporal con
volcados, una base de datos de prueba, una copia de la configuración con contraseñas, o la
configuración de Restic de otro servidor cambiada. Hasta ahora lo deshacían al terminar, pero
solo si terminaban «bien»: si fallaban de golpe o alguien pulsaba Ctrl-C, se quedaba así. Desde
ahora cada orden apunta lo que tendrá que deshacer en una lista, y esa lista se ejecuta siempre
al salir, termine como termine.

## Contexto

- `bc_die` sale con `exit` (`lib/core.sh:39`) y la señal INT/TERM también (`bin/backupctl:53`).
  Un `trap … RETURN` solo corre cuando la función **retorna**: con `exit` no corre.
- `bc_cleanup_all` (`bin/backupctl:75-79`), que sí corre siempre por el `trap … EXIT` (52), solo
  borra `BC_TEMP_DIR` y el archivo de credenciales de MySQL.
- Consecuencias confirmadas en el código (`.agents/context/30-trampas.md` T20):
  - `restore` cancelado deja la base extraída en `$TMPDIR` (`lib/restore.sh:60-81`; lo mostró el
    banco);
  - `adoptar --to` pisa `conf/restic.conf` del destino (362-364) y lo devuelve en un
    `trap RETURN` (272): una interrupción o un `bc_die` posterior lo deja apuntando al
    repositorio rescatado, y si falla la propia escritura (364) puede quedar truncado;
  - `verify --restore-test` puede dejar su base `verifybk_*` en MySQL (57);
  - `pull` puede dejar la copia del `env.sh` del servidor, con credenciales (41);
  - `adoptar` deja temporales locales (140, 549, 1291) y el espacio de trabajo remoto con datos
    extraídos (855); `restic` deja su temporal (43).

## Decisión

- `lib/core.sh` ofrece un registro de limpiezas:
  - `bc_cleanup_register <clave> <orden>`: apunta (o sustituye) una limpieza pendiente;
  - `bc_cleanup_run <clave>`: la ejecuta ya y la quita del registro;
  - las pendientes se ejecutan en orden inverso de registro desde `bc_cleanup_all`, que ya corre
    siempre al salir. Cada una con `set +e` y sin que un fallo impida las siguientes.
- Los módulos registran la limpieza **en cuanto crean** lo que habrá que deshacer (antes de
  cualquier operación que pueda fallar), y en el camino normal la ejecutan con
  `bc_cleanup_run` (el `trap … RETURN` puede quedarse llamando a `bc_cleanup_run`).
- Las limpiezas deben ser **idempotentes**: pueden llegar a correr dos veces.
- Se aplica a las trampas `RETURN` que deshacen algo con efecto: `restore.sh:62`,
  `verify.sh:57`, `pull.sh:41`, `restic.sh:43`, `adoptar.sh:140, 272, 549, 855, 1291`. Las que
  solo cierran la conexión ssh maestra (`bc_ssh_close`, `bc_hestia_cerrar`) se dejan: la conexión
  caduca sola (`ControlPersist=600`, `lib/ssh.sh:39`).

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| `bc_die` con `return` en vez de `exit` | Cambia el contrato de cientos de llamadas: el código de después seguiría ejecutándose |
| Un `trap … EXIT` por módulo | Solo hay un `trap EXIT` por proceso: cada módulo pisaría el anterior |
| Arreglar solo `restore` (T20) | El mismo defecto deja la configuración de Restic de un servidor ajeno cambiada; T20 es el síntoma que se vio |
| Una variable global por limpieza en `bc_cleanup_all` | Acopla el despachador a cada módulo; el registro es genérico |

## Consecuencias

- Lo que se deja a medias se deshace también al interrumpir o al fallar.
- **Subshells**: lo que se registra dentro de `$(...)` o de una tubería no llega al registro del
  proceso principal. Una función que crea algo dentro de una subshell necesita su propia
  limpieza. Se documenta en `20-convenciones.md`.
- Toca código que se ejecuta en servidores (`restore`, `verify`, `pull`, `restic`, `adoptar`):
  no se fusiona en `master` sin la prueba del PO (ADR 0007).
- Una limpieza remota (devolver `restic.conf`, borrar el espacio de trabajo) al salir necesita
  que la conexión ssh siga viva: el orden inverso de registro garantiza que se ejecuta antes que
  el cierre de la conexión si esta se registró antes.

## Reversión

1. En cada módulo, devolver la limpieza a su `trap … RETURN` y quitar `bc_cleanup_register`.
2. Quitar el registro de `lib/core.sh` y su llamada en `bc_cleanup_all`.
3. Las pruebas del banco que lo cubren fallarán: quitarlas.

## Verificación

Pruebas del banco: `restore` cancelado no deja `backupctl-restore.*` en su `TMPDIR`; y, si el
banco llega hasta ahí con `ssh` falso, un fallo de `adoptar --to` después de pisar
`restic.conf` envía la orden que lo devuelve. Guía para el PO en `estado/AHORA.md`.
