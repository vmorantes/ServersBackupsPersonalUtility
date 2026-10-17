---
name: abrir-jornada
description: >
  Ritual obligatorio para EMPEZAR o RETOMAR un día de trabajo como arquitecto de
  ServersBackupsPersonalUtility, y para volver a la realidad después de una compactación o de
  reabrir el chat. Lee el estado en un orden fijo y obliga a contestar en voz alta las ocho
  preguntas que un arquitecto tiene que saber antes de decidir nada. Si una pregunta no tiene
  respuesta en el repositorio, el hueco ES el hallazgo y se tapa antes de trabajar. Invócala
  cuando se diga «a trabajar», «retomamos», «abrir jornada», «¿dónde estábamos?», cuando la
  sesión se acabe de compactar, o en el primer mensaje de una sesión nueva del arquitecto.
---

# Abrir jornada

**Esta skill es el consumidor del estado.** Las ocho preguntas de la sección 3 son el contrato
que `estado/AHORA.md` tiene que satisfacer. Si una no se puede contestar leyendo el
repositorio, no se improvisa ni se le pregunta al PO: **el estado falló, y arreglarlo es el
primer trabajo del día**.

Es la aplicación directa del ADR 0004 y de la regla `60-estado.md`: *ningún trabajo depende de
una sesión*. En este proyecto las sesiones se han cortado **tres veces** sin aviso. Esta skill
es lo que hace que eso no cueste nada.

## 1. Quién la invoca, y quién no

- **El arquitecto**, siempre, antes de leer código, antes de decidir y antes de escribir el
  primer mensaje. También **después de una compactación** y **después de reabrir el chat**:
  las dos cosas dejan un resumen en lugar de la conversación.
- **El coder no la usa.** Su entrada completa es la instrucción que recibe, no el estado del
  repositorio. Las instrucciones son autocontenidas por diseño (regla `30`).
- **El PO no la lee.** Solo la entrega: pega `/abrir-jornada` en la sesión del arquitecto.

## 2. El orden de lectura, y por qué es ese

Se lee **entero** lo que se nombra, sin `head` y sin saltos. Son pocos archivos a propósito:
si hacen falta más, el estado está mal repartido, y eso se corrige, no se compensa leyendo de
más.

| Orden | Archivo | Qué saca de ahí |
| :-- | :-- | :-- |
| 1 | `estado/AHORA.md` | Qué pasa ahora, el contador, qué espera al PO, dónde se quedó lo que está a medias |
| 2 | El archivo más reciente de `estado/tramos/` | Dónde se cortó el último tramo y por qué |
| 3 | `.agents/docs/roadmap.md` | Qué falta hasta la versión en curso y en qué orden |
| 4 | Los ADR de los últimos días, de `.agents/docs/adr/` | Lo decidido que puede no estar implementado |
| 5 | `.agents/context/30-trampas.md`, del área que se va a tocar | Qué muerde hoy |

Y **tres mediciones, no tres recuerdos**:

```bash
git --no-optional-locks status --short
git --no-optional-locks log --oneline -12
git --no-optional-locks branch --show-current
```

El árbol y el historial se **miden** al abrir. Un `AHORA.md` escrito anoche puede describir un
árbol que ya no existe, porque el coder o el PO commitearon después. Y ten presente la
excepción de siempre: `estado/` la escribe el arquitecto, el coder la ignora en sus criterios.

**`git fetch`, `pull`, `ls-remote` y `remote -v` no se ejecutan**: usan o muestran la URL del
remoto, que lleva una credencial (`40-salvaguardas.md` §3).

## 3. Las ocho preguntas, y el hueco que no se tapa solo

Se contestan **en voz alta, en el chat, numeradas**, antes de hacer nada más. Cada una lleva
**dónde se leyó la respuesta**; una contestada de memoria no cuenta.

1. **¿En qué rama estoy y está el árbol limpio?** — medido, no leído.
2. **¿Qué está en vuelo?** ¿Hay una instrucción enviada sin reporte? Si la hay, **no se emite
   otra**: para el coder, cualquier mensaje con trabajo dentro es una ronda. **Se contesta
   contra el disco, no contra el chat**: el archivo del tramo lleva una línea por reporte
   recibido, y el `git log` dice si su trabajo está hecho. Si el estado dice «en vuelo» y los
   commits de esa ronda ya existen con el árbol limpio, **lo que falta es el reporte, no el
   trabajo**: se le pide y se anota, marcando lo que quede **sin verificar**. Pasó con la
   ronda `#079`, cuyo reporte `#080` nunca llegó.
3. **¿Qué números de mensaje tocan?** Son **dos** contadores y los dos viven en `AHORA.md`:
   `#NNN`, compartido con el coder, y `A-NNN`, de los mensajes al PO (regla `30`). Es el dato
   que más se pierde en una compactación o un `/clear`.
4. **¿Qué espera al PO?** Con sus pasos exactos. Si lleva días ahí sin que él lo sepa, el
   fallo es nuestro.
5. **¿Cuál es el mandato vigente y quién lo nombró?** El arquitecto **no elige** en qué se
   trabaja: detectar que algo conviene y decirlo es su trabajo; convertirlo en un recuadro sin
   que el PO lo haya nombrado, no.
6. **¿Qué falta, medible, para cerrar ese mandato?** Si la respuesta no es una lista de
   condiciones comprobables, el estado no sirve.
7. **¿Qué se decidió y no se ha implementado?** Los ADR recientes contra el código. Una
   decisión aceptada y sin implementar es la trampa más cara, porque parece hecha.
8. **¿Qué me va a morder hoy?** Las trampas de `.agents/context/30-trampas.md` del área que se
   va a tocar, y lo que `50-hestiacp.md` ya dé por verificado — **que no se vuelve a
   verificar**.

**Si una pregunta no tiene respuesta en el repositorio:**

- Se dice cuál, con esas palabras: **«el estado no contesta la pregunta N»**.
- Se tapa el hueco **ahí mismo**, escribiendo la respuesta donde le toque vivir.
- Se nombra en el primer mensaje al PO.
- **No se arranca trabajo con una pregunta sin contestar.** Es la única parada que esta skill
  impone, y es su razón de ser.

## 4. Las puertas del andamiaje, que se comprueban al abrir

```bash
bash .agents/scripts/verificar.sh
```

Si falla algo, **eso es lo primero de la jornada**, por delante de lo que el PO tuviera
pensado. Trabajar sobre un árbol que no verifica es acumular causas para un fallo posterior.

Eso incluye ya las **puertas del estado** (`puertas_estado.sh`): el tope de 200 líneas de
`AHORA.md`, un solo bloque «al retomar», los dos contadores declarados y los tramos podados.

A mano queda lo que ninguna máquina puede comprobar:

- **Que el número de cada contador sea el correcto**, no solo que esté escrito.
- **Que lo que dice `AHORA.md` sea verdad.** Un archivo bien formado y falso pasa todas las
  puertas.
- **Los enlaces de reglas y skills son enlaces, no copias:**

```bash
git ls-files -s .claude/rules .claude/skills   # todas las líneas: 120000
ls -la .claude/rules/ .claude/skills/          # SIN truncar con head
```

Un `100644` significa que el enlace se materializó como copia —clon con
`core.symlinks=false`— y las reglas divergirán en silencio. Para afirmar que algo **no**
existe hace falta la salida completa.

## 5. El primer mensaje, y el dato que casi todos se inventan

Lo primero que el arquitecto da al PO son las dos órdenes de renombrado, pegables, sin que él
las pida. **Decisión del PO del 2026-09-24: el renombrado es OBLIGATORIO para trabajar**, y no
se emite la primera instrucción hasta que los dos nombres estén puestos y comprobados en la
lista de sesiones.

```
/rename ServersBackupsPersonalUtility-Arquitecto-Main     ← sesión del arquitecto
/rename ServersBackupsPersonalUtility-Coder-Main          ← sesión del coder
```

**Hacen falta solo si la sesión se mató de verdad:**

- **`/clear`** vacía la conversación **dentro de la misma sesión**: conserva el nombre. Tras un
  `/clear` no hay que volver a renombrar.
- **Matar la sesión** (`/exit`, o cerrarla y relanzar) **autogenera un nombre nuevo**. Por eso
  las dos órdenes viven en `AHORA.md`.

El nombre **no sustituye a la identificación**: antes de la primera instrucción hay que
confirmar que esa sesión es el coder de **este** repositorio, pidiéndole un dato verificable
—la rama, el último commit, el número que dice `AHORA.md`—. En la máquina hay sesiones de
otros proyectos, y más de una en este mismo directorio. Si el coder corre en otro proveedor o
en otra máquina, no hay canal directo y el PO transporta.

Después, el resumen de arranque: **identificador en la primera línea**, prosa comprimida,
secciones numeradas para que el PO pueda citarlas, y dentro: dónde estamos, qué está en vuelo,
y qué espera de él.

## 6. Lo que NO se hace al abrir

- **No se emite una instrucción** antes de contestar las ocho preguntas.
- **No se emite una instrucción si hay una en vuelo.** Ni «un aviso», ni «una lista de
  tareas»: para el coder, cualquier mensaje con trabajo dentro es una ronda.
- **No se escribe en el árbol si el coder tiene una ronda en vuelo**, salvo `estado/`.
- **No se decide nada que las reglas reserven al PO** (`30` §«Se detiene el trabajo»):
  producto, su entorno, y todo lo que `00-core.md` y `40-salvaguardas.md` exigen autorizar una
  a una.
- **No se da por bueno un dato de la memoria nativa.** El repositorio manda
  (`10-memory-contract.md`). Si la memoria dice algo que el repositorio no dice, **eso es el
  hallazgo**.

## 7. La trampa que esta skill existe para evitar

Un arquitecto recién nacido —o recién compactado— **habla con fluidez de cosas que no ha
medido**. Suena igual que uno que las conoce, y ahí está el daño.

En este proyecto ya costó caro: el 2026-09-23 se corrigieron cuatro ejemplos de
`docs/hestiacp/protocolo-manual.md` y se anunció la guía como arreglada. Quedaban ocho
ejemplos con rutas relativas en otros cuatro archivos, y **el 2026-09-24 esa misma
documentación rompió un segundo servidor del PO**. Sus palabras: *«Prometiste que estaría
corregida la guía, ahora destruí otro servidor»*.

**La regla que sale de ahí, y vale para toda la jornada: una corrección parcial anunciada como
completa es peor que no corregir**, porque quien la lee se fía. Y su gemela, de
`40-salvaguardas.md` §5: **ningún éxito sin comprobación independiente**. Toda afirmación
técnica sobre HestiaCP, MySQL, Restic o rclone va citada de su fuente —o del subagente
`hestia-verifier`— o marcada «sin verificar». Sin una de las dos cosas, el PO puede tratarla
como falsa.
