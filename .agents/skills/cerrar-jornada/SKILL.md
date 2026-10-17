---
name: cerrar-jornada
description: >
  Ritual obligatorio para CERRAR un día de trabajo como arquitecto de
  ServersBackupsPersonalUtility, o para cerrar un tramo antes de parar. Deja el árbol limpio y
  commiteado, reescribe `estado/AHORA.md` con las ocho respuestas que `abrir-jornada` va a
  exigir, poda lo que ya no sirve y entrega al PO el informe final único con su forma fija.
  Invócala cuando se diga «cerramos», «cerrar jornada», «paramos por hoy», «cierra el tramo»,
  cuando el PO pida parar, y antes de proponer un relevo de sesión.
---

# Cerrar jornada

La pareja de `abrir-jornada`, y la que hace el trabajo de verdad: **abrir solo puede leer lo
que cerrar escribió**.

**Absorbe la antigua skill `cierre-de-tramo`**, retirada el 2026-10-17 por decisión del PO:
cerrar un tramo es el caso corto de cerrar la jornada, y dos skills que hacen lo mismo
divergen. Cuando se cierra un tramo a mitad de día se ejecuta esta misma, saltando el punto
2.5 y acortando el informe del punto 3.

El sistema de herencia tiene que ser **volátil, pero no faltar ni mentir**. Las dos mitades
importan. **Volátil**: lo que ya no sirve se borra, porque la documentación muerta un agente
la lee como verdad (regla `60-estado.md`). **Que no falte ni mienta**: lo que queda tiene que
bastar para que una sesión recién nacida trabaje, y tiene que ser verdad en el momento en que
se escribió.

## 1. Cuándo se ejecuta

- **Al final de un tramo**, siempre.
- **Cuando el PO pide parar.** Si hay una ronda en vuelo, **se termina primero**: nunca se
  deja un árbol a medio commitear (regla `30`).
- **Antes de proponer un relevo** de cualquiera de las dos sesiones.
- **Cuando la sesión note que va a compactarse** y haya algo sin depositar. Si no es el final
  del día, basta `asentar-estado`.

**Ninguna jornada termina con el árbol sucio.** Si el arquitecto escribió documentación
después de la última ronda, **abre otra ronda corta** para que el coder la commitee. Esa ronda
es parte del cierre, no del día siguiente.

## 2. El orden del cierre

### 2.0. Antes del árbol: la cadena con el coder

Se comprueba que **ningún reporte recibido esté sin anotar** en el archivo del tramo
(`asentar-estado` §2.1bis) y que ninguna ronda enviada siga en vuelo. Si una lo está, se
termina primero.

Esto no es formalismo: pasó con la ronda `#079`, cuyo reporte nunca llegó y hubo que
recuperarlo pidiéndolo de nuevo. Lo único que evita repetirlo es que cada reporte deje su
línea con sus hashes en disco.

### 2.1. Primero el árbol, que es lo único que no se puede arreglar mañana

```bash
git --no-optional-locks status --short
```

Todo lo del arquitecto que esté sin commitear se reparte en la ronda del coder:

- el código en commits propios,
- la documentación en commits `docs:`, **sin editarla**,
- `estado/` en su `docs(estado):` aparte, nunca mezclado.

Conventional Commits, en español, imperativo, subject ≤ 50 caracteres. **Cero atribución a IA
o agentes.** Rutas explícitas, nunca `git add .` ni `-A`. **`git push` jamás: sube el PO.**

Lo que quede sin commitear a propósito —archivos fuera de git, trabajo del PO— se **nombra**
en el informe y en `AHORA.md`, con el motivo.

**Si no hay coder disponible**, el arquitecto no commitea: deja en `AHORA.md`, dentro de «Al
retomar», la lista exacta de archivos y los mensajes de commit ya redactados. Lo que no puede
quedar es un árbol sucio sin explicación.

### 2.2. Después `AHORA.md`, contra el contrato de las ocho

`AHORA.md` se reescribe **entero**, no se le añade al final. Tiene que contestar, sin que haga
falta otro archivo, **las ocho preguntas de `abrir-jornada` §3**:

| Sección obligatoria | Contesta |
| :-- | :-- |
| **Sesiones**, con las dos órdenes de `/rename` | 1 |
| **En vuelo** | 2 |
| **Los dos contadores**: `#NNN` (coder) y `A-NNN` (PO) | 3 |
| **Espera al PO**, arriba del todo, numerado y con los pasos | 4 |
| **Mandato vigente**, con quién lo nombró | 5 |
| **Qué falta**, como condiciones comprobables | 6 |
| **Decidido y sin implementar**, con su ADR | 7 |
| **Trampas del área en curso**, con su puntero a `.agents/context/` | 8 |

**El tope: 200 líneas.** Un archivo que una sesión nueva no lee entero no es estado, es
archivo. **Si no cabe, no se sube el tope: se poda.** Lo que sobra casi siempre es historia, y
la historia tiene su sitio.

### 2.3. La poda, con sus reglas

1. **Un solo bloque «al retomar»**, con su lista en orden. Dos bloques de arranque significa
   que uno de los dos está rancio.
2. **Ninguna decisión vive en `AHORA.md`.** Una decisión va a un ADR y `AHORA.md` la
   **apunta**. Si solo está aquí, el día que se poda se pierde; y si está en los dos sitios,
   el día que cambia miente uno de los dos.
3. **Lo cerrado sale en la ronda que lo cierra**, no «cuando se limpie».

Y lo demás, por su sitio (regla `60-estado.md`):

- **`estado/tramos/`**: se conservan los 10 más recientes. Uno más viejo se borra cuando lo
  que importaba ya está en la bitácora, un ADR o el `CHANGELOG`.
- **`.agents/context/`**: lo que el código ya no hace se borra **en el mismo commit que lo
  cambia**. Una trampa cubierta por una prueba se reduce a una línea con el nombre de la
  prueba, o se va.
- **`.agents/docs/roadmap.md`**: lo cerrado sale; su historia queda en la bitácora.
- **`.agents/docs/bitacora/`**: una entrada por **tarea cerrada**, no por ronda.
- **`CHANGELOG.md`**: lo que cambió para el usuario, en `[Sin publicar]`.
- **`HERENCIA.md`**: se borra cuando se cumplan sus propias condiciones, con entrada de
  bitácora.
- **ADR**: nunca se borran; se reemplazan.

El subagente `context-curator` propone; el arquitecto decide y ejecuta.

### 2.4. El archivo del tramo

Se cierra el de `estado/tramos/` con la hora de fin y la **duración**, todas las rondas con
sus commits, los hallazgos, las decisiones con su número de ADR, lo que falló y cómo se
resolvió, y la lista numerada de lo que espera al PO.

Es lo que `abrir-jornada` lee en segundo lugar para saber **por qué** se cortó donde se cortó.

### 2.5. Y la memoria nativa, al final

Se guarda el cierre, y **solo lo que ya vive en el repositorio, con su puntero**
(`10-memory-contract.md`). Si al escribirlo aparece algo que el repositorio no tiene, **eso es
el hallazgo**: se sube al repositorio primero y luego se guarda el puntero.

## 3. El informe al PO: uno solo, al final, con su forma fija

**Uno solo.** Es una preferencia asentada del PO: en trabajos largos no quiere avances
repartidos, quiere un informe unificado al cerrar. Identificador en la primera línea, prosa
comprimida, secciones numeradas para que pueda citarlas, y estos seis puntos:

1. **Rondas y duración**: `#NNN`–`#NNN`, de hh:mm a hh:mm.
2. **Cerrado**: qué, con sus commits.
3. **Encontrado y decidido**: con los ADR, si los hay.
4. **Falló por el camino**: y cómo se resolvió. **Incluidos los fallos propios**, con esas
   palabras.
5. **Lo que NO se pudo probar aquí**, separado de lo probado. Todo lo que toca un servidor,
   MySQL o HestiaCP entra en esta lista (ADR 0006), **con su guía de comprobación**: pasos por
   la web primero, qué debe verse, cómo comprobarlo por fuera, y qué quedó sin probar.
6. **Espera al PO**: lista numerada que pueda contestar punto por punto, cada punto con su
   contexto. Él no ha visto el trabajo: se le contextualiza.

Comprimido **salvo donde comprimir daña** (`50-prosa-comprimida.md`): las clasificaciones
CONFIRMADO / SOSPECHA / SIN VERIFICAR, los avisos de seguridad y las secuencias de pasos van
enteras.

**Un informe que omite un fallo es peor que el fallo.**

Y las dos órdenes de renombrado otra vez, al cierre, para que las tenga a mano la próxima vez.
El nombre solo vuelve si se reanuda esa misma sesión:

```
/rename ServersBackupsPersonalUtility-Arquitecto-Main
/rename ServersBackupsPersonalUtility-Coder-Main
```

## 4. Las puertas, para que esto no dependa de la disciplina

Un ritual que se cumple porque alguien se acuerda es un ritual que un día no se cumple. Estas
comprobaciones las hace **por máquina** `.agents/scripts/puertas_estado.sh`, que corre dentro
de `verificar.sh`. Su prueba de rechazo —cada puerta vista fallar— es
`.agents/scripts/probar_puertas_estado.sh` (ADR 0010).

| Puerta | Qué comprueba | Falla si |
| :-- | :-- | :-- |
| **El archivo existe** | Que hay un `estado/AHORA.md` | Falta |
| **El tope** | `estado/AHORA.md` ≤ 200 líneas | Lo pasa |
| **Un solo «al retomar»** | Cuenta los bloques de arranque de `AHORA.md` | Hay cero o más de uno |
| **Los contadores declarados** | Que `AHORA.md` tiene su sección y declara `#NNN` **y** `A-NNN` | Falta la sección o uno de los dos |
| **El contador no se queda atrás** | El `#NNN` que `AHORA.md` declara como último usado, contra el mayor que registren los tramos | El tramo va por delante, o falta el «Último usado» |
| **Tramos podados** | Que no hay más de 10 archivos en `estado/tramos/` | Hay más |

**Lo que la máquina NO puede comprobar, y sigue siendo del arquitecto:**

- Que el número del contador **acierte**. La puerta detecta que se haya quedado **atrás**
  respecto a los tramos, que es el fallo que ya ocurrió; no que el número sea el correcto. Si
  `AHORA.md` va por delante de la realidad, pasa.
- **Que ningún reporte recibido esté sin anotar** en el archivo del tramo (§2.0). No hay
  fuente canónica contra la que compararlo: si la hubiera, el problema no existiría. Y de aquí
  sale el límite de la puerta anterior: **compara contra los tramos, así que una ronda que no
  se anota no delata nada**. La puerta protege al que escribe el tramo, no al que lo olvida.
- Que lo escrito sea **verdad**. Ninguna puerta detecta un `AHORA.md` bien formado y falso.

Las puertas quitan de en medio los descuidos mecánicos para que la atención vaya a esto otro.

## 5. Lo que este cierre NO es

- **No es un volcado de la conversación.** La bitácora es una entrada por tarea cerrada, no
  una transcripción. Lo que no cambie lo que alguien hará mañana, no entra.
- **No es un sitio para decidir.** Si en el cierre aparece una decisión, se escribe su ADR y
  `AHORA.md` lo apunta.
- **No es opcional cuando el día acabó mal.** Un día que termina con un fallo propio se cierra
  igual, y el fallo entra en el punto 4 del informe.

## 6. La comprobación final

Antes de dar el cierre por hecho, cuatro preguntas:

- ¿`estado/AHORA.md` dice la verdad **en este instante**?
- ¿Hay alguna decisión tomada hoy que solo viva en la conversación? → ADR o
  `.agents/context/`.
- ¿Algún documento quedó contradiciendo al código?
- ¿El PO tiene su lista numerada, con los pasos, **fuera del chat**?

## 7. Sobrevivir a un `/clear`

Es la prueba que de verdad importa, y la única que vale es hacerla: **después de cerrar,
imagina que la sesión se vacía ahora mismo**.

Un `/clear` no mata la sesión —conserva el nombre y el proyecto— pero sí **borra la
conversación**, y con ella todo lo que no se haya escrito: los reportes recibidos, lo que el
PO dijo de pasada, el motivo por el que se eligió un camino y no otro.

Lo que tiene que estar en disco para sobrevivirlo:

| Lo que se pierde con el `/clear` | Dónde queda escrito |
| :-- | :-- |
| Los dos contadores | `AHORA.md`, sección «Contadores» |
| Que una ronda estaba en vuelo | `AHORA.md`, sección «En vuelo» |
| Los reportes recibidos y sus commits | El archivo del tramo, una línea por reporte |
| Lo que el PO decidió hoy | El archivo del tramo, con sus palabras y la hora |
| Por qué se eligió este camino | Un ADR |
| Qué muerde si se toca esa zona | `.agents/context/` |
| Qué espera al PO | `AHORA.md`, arriba del todo |
| Las dos órdenes de `/rename` | `AHORA.md`, sección «Sesiones» |

**Si algo de esa columna izquierda solo vive en el chat, el cierre no está hecho.** Y si el
`/clear` llega a mitad de jornada, sin cerrar, lo que toca es `asentar-estado`, que escribe
justo esas mismas cosas sin cerrar nada.
