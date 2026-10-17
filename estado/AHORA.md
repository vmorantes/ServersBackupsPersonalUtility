# Ahora

> **Para retomar: `/abrir-jornada`.** Esta skill lee este archivo y exige que conteste las ocho
> preguntas de abajo. Si alguna no se contesta aquí, **el estado falló y arreglarlo es el primer
> trabajo del día**.

- **Actualizado:** 2026-10-17, al adoptar las skills de jornada.
- **Formato:** este archivo sigue el contrato de `cerrar-jornada` §2.2. Tope: 200 líneas.

## Al retomar — el primer paso, uno solo

1. Poner los dos nombres de sesión (§1) y comprobarlos en la lista.
2. **Medir si hay coder**, listando las sesiones. No suponerlo (regla `30`).
3. `bash .agents/scripts/verificar.sh` — tiene que salir en verde, 23 suites y seis puertas.
4. Preguntar al PO qué sigue: hay dos frentes abiertos y **él elige** (§5).


## Espera al PO

1. **`git push` de `release/2.1`.** Hay commits sin subir; **no se escribe aquí cuántos**.
   Una cifra escrita una vez envejece y se lee como medida: este archivo dijo «68» durante
   semanas y no coincidía con ninguna medición posible. Lo que sí se puede medir sin tocar el
   remoto, y que quien lea esto debe **repetir en vez de creer**:

   ```
   git rev-list --count master..release/2.1
   git rev-list --count origin/release/2.1..release/2.1
   ```

   **La segunda cifra no es una verdad del servidor**: `origin/release/2.1` es una referencia
   local, de la última vez que alguien sincronizó. No se refresca desde aquí —`fetch` y
   `ls-remote` usan la URL del remoto, que lleva credencial (`40-salvaguardas.md` §3)—. Lo que
   falta por subir de verdad solo lo sabe el PO.

2. **La migración de sus servidores del 2026-10-02**: las tareas pendientes están en
   `migraciones/PENDIENTES.md`, fuera de git porque llevan datos reales. Fases A y B antes de
   apagar el servidor viejo.
3. **`rm ~/.local/bin/backupctl`** — resto de una «prueba» que nunca debió ejecutarse.
4. **Bajarse el `.tgz` de las claves** fuera del servidor que protegen.
5. **Ya no hay servidor de pruebas** (PO, 2026-10-17). Lo de la fase 2 **nunca** se ha ejecutado
   contra un HestiaCP real y ahora no hay dónde ensayarlo: no se usa en producción. Guía, por si vuelve uno:
   `.agents/docs/guia-pruebas-fase-2.md`. **Lunes 2026-10-19: migra un servidor MUY grande** (Joomla y
   proyectos CodeIgniter 3.1.7). Mandato: ADR 0018.
6. **El PO borró `TejidoTesting/` del disco (2026-10-17)**: era el único perfil versionado, con su
   `env.sh` y seis archivos de claves de Restic y rclone. **Sigue en la historia** (4 commits) y
   probablemente en el remoto. Si el almacenamiento de esos `rclone_*.conf` sigue activo, sus
   credenciales hay que rotarlas. Borrado sin commitear: lo commitea el coder cuando se le ordene.
   Mandato nuevo: claves fuera del repositorio y un método para respaldarlas a mano (A-022).
6. **Decidir qué sigue** (§5).

## 1. Sesiones

El renombrado es **obligatorio para trabajar** (PO, 2026-09-24): no se emite la primera
instrucción hasta que los dos nombres estén puestos y comprobados.

```
/rename ServersBackupsPersonalUtility-Arquitecto-Main
/rename ServersBackupsPersonalUtility-Coder-Main
```

Tras un `/clear` **no** hace falta renombrar: conserva el nombre. Hace falta si la sesión se
mató de verdad. El nombre **no sustituye a la identificación**: al coder se le pide un dato
verificable del repositorio antes de la primera instrucción.

## 2. En vuelo

**Tramo «migración caliente» (ADR 0018)**, abierto el 2026-10-17. Rama `feat/migracion-caliente`,
creada desde `release/2.1`. Coder identificado en `#124→#125`.

`#126→#129` hecho: copia intacta, 13/13 sumas y modos, ejemplo corregido. `#130→#133` hecho: tipo CodeIgniter 3 con guardas, 82 afirmaciones. **En vuelo: `#134`** (retirar el perfil, el falso OK de `verificar`, claves repetidas). En paralelo,
el subagente `hestia-verifier` verifica las órdenes de listado que usará el analizador. Detalle: `estado/tramos/2026-10-17-1700-migracion-caliente.md`.

## 3. Contadores

Son **dos**, y los dos avanzan por separado (regla `30`):

- **`#NNN`, cadena con el coder.** Último usado: **#134**. El próximo: **#135**.
  El `#123` se emitió y el canal lo descartó: **consume número igual** (tramo, hallazgo 19).
- **`A-NNN`, mensajes al PO.** Estrenado el 2026-10-17. Último usado: **A-022**. El próximo:
  **A-023**.

**Reparado el 2026-10-17, y vale la pena saber por qué.** Este archivo declaraba «último usado
#081» desde el 2026-09-24. Era **falso**: el archivo del tramo de ese mismo día registra
`#097` en vuelo y «Mensajes: #053–#097». Los dos documentos se contradecían y nadie lo vio en
casi un mes. El coder, al volver de una compactación, dijo que su último número era el `#102`
—el de su reporte del commit `e99a338`—, y la medición le dio la razón.

Consecuencia: los dos mensajes de hoy etiquetados `#082` (ARQ) y `#083` (COD) **son en
realidad el `#103` y el `#104`**. Se dejan con su etiqueta original —reescribir lo ya enviado
sería peor— y constan aquí. La cadena continúa en **#105**.

## 4. Qué espera al PO

Arriba, en «Espera al PO». Si cambia, se cambia en los dos sitios o en ninguno.

## 5. Mandato vigente

**PO, 2026-10-17**: unificar aquí las dos vías —respaldos (larga) y migración caliente de cuenta
completa (rápida)—, con la otra herramienta como subherramienta y un analizador de solo lectura
delante. Urgencia: el **lunes 2026-10-19** migra un servidor muy grande. Decisión: ADR 0018.

La fase 2 de la 2.1 queda **aparcada**, sin servidor de pruebas donde ensayarla.

## 6. Qué falta, medible

### Para el lunes (ADR 0018, «Orden»)

1. Entrada intacta: hecha (`#127`, `#129`).
2. Analizador de solo lectura, con pruebas sintéticas.
3. Tipo CodeIgniter 3: hecho (`3be710b`). Falta la guarda de claves duplicadas.
4. Guía del lunes y documentación de las dos vías (las escribe el arquitecto).

### Para cerrar la fase 2

1. **El paso 8, las exclusiones.** Está en **solo lectura** a propósito, con un `bc_err`
   explícito que lo impide y su comentario. Lo que falta para quitarlo:
   - **WEB — confirmado:** `v-backup-user-config` solo copia configuración, nunca el contenido
     del sitio; y ese contenido vive dentro de lo que copia `restic backup /home/<cuenta>`.
     **Excluir WEB no impide que los archivos acaben en la instantánea.**
   - **DB — al revés:** el volcado no existe hasta que el script lo genera, así que excluir sí
     funciona.
   - **DNS:** el archivo de zona *es* el contenido.
   - **MAIL — SIN VERIFICAR.** Es lo único abierto: no se miró dónde viven los buzones.
   - Con eso: decir por sección **qué efecto real tiene excluirla en cada uno de los dos
     respaldos**, quitar el modo solo lectura y devolver las dos pruebas retiradas.
2. **Revisión de seguridad y de código** de todo lo de la fase 2 — obligatoria: se ha tocado
   mucho código que corre como root.
3. **Documentación de usuario** de las órdenes nuevas, que escribe el arquitecto.
4. **H36**: `hestia cuentas` no está en la TUI, y ningún paso nuevo está en la web. La interfaz
   es el centro: hay que cerrarlo antes de dar la 2.1 por buena.

### Para cerrar el andamiaje de jornada

Las **seis** puertas del estado corren por máquina en `verificar.sh`
(`.agents/scripts/puertas_estado.sh`, con su prueba de rechazo: 12 afirmaciones). Queda:

0. **Pendientes de código, nacidos hoy** (detalle en el tramo, hallazgos 13 y 16): la sección
   ENSAYO de la ayuda no nombra las subórdenes de `hestia`, aunque las ocho admiten
   `--dry-run`; y el ensayo de `hestia exclusiones` anuncia una escritura que el camino real
   se niega a hacer. Lo segundo se resuelve solo al cerrar el paso 8.


5. **La guarda: DOS defectos distintos**, que frenaron el trabajo **cinco veces** el
   2026-10-17. Contarlos como uno haría que el arreglo dejara vivo el segundo; lo separó el
   coder.
   - **A — confunde el contenido de un archivo con una orden (4 veces).** Es el error ya
     arreglado para los mensajes de commit (H13), sin aplicar aquí.
   - **B — no distingue la ruta de un borrado legítimo (1 vez).** Un temporal del scratchpad
     de la sesión, que `40-salvaguardas.md` §2 permite expresamente.

   Ninguna se esquivó. El detalle de los cinco, en el tramo del 2026-10-17. **Es lo único que
   queda abierto del andamiaje**, y el coste ya es real.


## 7. Decidido y sin implementar

- **ADR 0013** (fases de la 2.1): la fase 2 sin terminar; las fases 3 y 4 sin empezar.
- **ADR 0015** (interfaz por tareas): sin empezar; necesita una sesión de diseño con el PO.
- **La web puede contradecir a la línea de órdenes.** No siempre pasa por `backupctl`: lee el
  servidor por su cuenta en al menos tres sitios. Todo el rigor de la fase 2 vive **solo en la
  CLI**. **Decisión del PO (2026-09-24): se aborda en la fase 3.** Mientras tanto, y hay que
  decírselo cuando pruebe: **si las dos discrepan, manda `hestia status`.**
- La web llama a todo con `-y`, así que las dos negativas nuevas se dispararán allí con
  mensajes escritos para una terminal. Protegen igual; se verán mal. También para la fase 3.

## 8. Trampas del área en curso

- `.agents/context/30-trampas.md`, **T2 y T20–T26**. **T21**: antes de un `adoptar --to` real,
  copiar el `restic.conf` del destino.
- `.agents/context/50-hestiacp.md` **entero**: lo verificado ahí **no se vuelve a verificar**.
  Incluido lo del 2026-10-17: la etiqueta del repositorio de HestiaCP es `1.10.5`, **sin `v`**.
- `.agents/context/20-convenciones.md`: «vacío» y «no lo sé» no se escriben igual.
- `.agents/context/40-entorno.md`: el banco de pruebas y sus salvaguardas.
- **Zona horaria, sin cerrar**: `bc_hestia_diag_instantanea` compara la fecha de la instantánea
  con «ahora». Si las dos puntas no están en la misma referencia, un respaldo que se saltó una
  noche puede parecer reciente. **Falso OK.**
- **Sin verificar contra un servidor real**: que `v-change-user-config-value` con la clave
  presente no toque nada más que esa clave. Lo que sabemos viene de leer su código.
- **H34** (decidido, se queda): cada cuenta se lee dos veces, una para la foto y otra justo
  antes de escribir. Entre las dos hay una persona decidiendo.

## La lección que no se poda

**Una corrección parcial que se anuncia como completa es peor que no corregir**, porque quien
la lee se fía. Y un documento correcto en lo que afirma puede ser peligroso por lo que omite.
Las dos lecciones costaron un servidor del PO cada una. El relato entero, en `abrir-jornada`
§7.

## Para una sesión nueva

Lee este archivo, el último de `estado/tramos/`, y los ADR **0013, 0014, 0015 y 0017** (el 0016
está reemplazado). Luego `.agents/README.md` para el orden del resto.
