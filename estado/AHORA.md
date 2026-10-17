# Ahora

> **Para retomar: `/abrir-jornada`.** Esta skill lee este archivo y exige que conteste las ocho
> preguntas de abajo. Si alguna no se contesta aquí, **el estado falló y arreglarlo es el primer
> trabajo del día**.

- **Actualizado:** 2026-10-17, al adoptar las skills de jornada.
- **Formato:** este archivo sigue el contrato de `cerrar-jornada` §2.2. Tope: 200 líneas.

## Al retomar — el primer paso, uno solo

1. Poner los dos nombres de sesión (§1) y comprobarlos en la lista.
2. `bash .agents/scripts/verificar.sh` — tiene que salir en verde.
3. **Commitear el árbol pendiente** (§2). Está escrito y verificado; solo falta el commit.
4. Preguntar al PO qué sigue: hay dos frentes abiertos y **él elige** (§5).

## Espera al PO

1. **`git push` de `release/2.1`.** Son 68 commits sin subir. Solo lo hace él.
2. **La migración de sus servidores del 2026-10-02**: las tareas pendientes están en
   `migraciones/PENDIENTES.md`, fuera de git porque llevan datos reales. Fases A y B antes de
   apagar el servidor viejo.
3. **`rm ~/.local/bin/backupctl`** — resto de una «prueba» que nunca debió ejecutarse.
4. **Bajarse el `.tgz` de las claves** fuera del servidor que protegen.
5. **Tres guías de prueba de la fase 2**, para su servidor de PRUEBAS, enteras en los reportes
   #076, #078 y #080. Nada de eso se ha ejecutado nunca contra un HestiaCP real. Empezar
   siempre por el ensayo, y en `hestia cuentas` por **una sola** cuenta.
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

**Nada en vuelo.** No hay ronda enviada sin reporte y no hay coder activo.

**Desviación del 2026-10-17, anotada a propósito:** todo el andamiaje de jornada —las tres
skills, las dos puertas y sus ocho commits— lo escribió y lo commiteó **el arquitecto, sin
coder**, por orden expresa del PO («implementa las puertas, deja el árbol limpio»). La regla
`30` reserva el commit al coder. La orden del PO autoriza la excepción; que quede escrita es
lo que impide que se convierta en costumbre. **Lo siguiente que toque `lib/`, `bin/`, `web/`
o `tools/` va por coder**, sin excepción: ahí la regla no la mueve la prisa.

**El árbol está sucio a propósito**, con trabajo del arquitecto sin commitear:

| Archivo | Qué es | Commit propuesto |
| :-- | :-- | :-- |
| `.gitignore` | Excluye `migraciones/` salvo su README | `chore: excluir los archivos de migración` |
| `.agents/docs/mejoras-herramienta-migracion.md` | Doce mejoras de la herramienta de migración, con la evidencia del 2026-10-02 | `docs: mejoras de la herramienta de migración` |
| `.agents/skills/{abrir-jornada,asentar-estado,cerrar-jornada}/` + enlaces en `.claude/skills/` | Las tres skills de jornada | `docs(agentes): skills de jornada` |
| `.agents/skills/cierre-de-tramo/` **borrada** + su enlace | Unificada en `cerrar-jornada` | el mismo commit |
| `.agents/rules/30-protocolo-coder.md` | Contador `A-NNN` y partes numeradas | `docs(agentes): etiquetar los mensajes al PO` |
| `.agents/scripts/puertas_estado.sh` + `probar_puertas_estado.sh` + `verificar.sh` | Las puertas del estado, con su prueba de rechazo | `feat(agentes): puertas del estado versionado` |
| `migraciones/` | **Fuera de git**: lleva datos reales del PO | no se commitea |

## 3. Contadores

Son **dos**, y los dos avanzan por separado (regla `30`):

- **`#NNN`, cadena con el coder.** Último usado: **#081** (ARQ). El próximo: **#082**.
- **`A-NNN`, mensajes al PO.** Estrenado el 2026-10-17. El próximo: **A-001**.

## 4. Qué espera al PO

Arriba, en «Espera al PO». Si cambia, se cambia en los dos sitios o en ninguno.

## 5. Mandato vigente

El último que el PO nombró fue **«dale fase 1 y 2»** de la versión 2.1 (ADR 0013). La fase 1
está terminada; la fase 2, en siete pasos y medio de ocho.

Desde entonces el trabajo ha sido suyo, no del repositorio: la migración real de sus
servidores del 2026-10-02 y, el 2026-10-17, el andamiaje de jornada.

**Hay dos frentes y el arquitecto no elige**:

- **(a)** Cerrar la fase 2: el paso 8, la revisión de seguridad y la documentación de usuario.
- **(b)** Lo que quede del andamiaje: solo el punto 5 de §6, la guarda.

## 6. Qué falta, medible

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

Las puertas del estado ya corren por máquina en `verificar.sh`
(`.agents/scripts/puertas_estado.sh`, con su prueba de rechazo). Queda:

5. **La guarda confunde el contenido de un documento con una orden.** El 2026-10-17 bloqueó
   escribir un documento porque el texto citaba órdenes `v-*`. Es el mismo error que ya se
   arregló con los mensajes de commit (H13): falta la misma distinción para los heredocs que
   escriben documentación. **Es lo único que queda abierto del andamiaje.**

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

El 2026-09-23 se corrigieron cuatro ejemplos de `docs/hestiacp/protocolo-manual.md` y se
anunció la guía como arreglada. Quedaban ocho ejemplos con rutas relativas en otros cuatro
archivos, y **el 2026-09-24 esa misma documentación rompió un segundo servidor del PO**.

Corregidos todos, y añadido a `verificar.sh` el paso «Rutas relativas en ejemplos de
almacenamiento», probado en las dos direcciones.

**Una corrección parcial que se anuncia como completa es peor que no corregir**, porque quien
la lee se fía.

## Para una sesión nueva

Lee este archivo, el último de `estado/tramos/`, y los ADR **0013, 0014, 0015 y 0017** (el 0016
está reemplazado). Luego `.agents/README.md` para el orden del resto.
