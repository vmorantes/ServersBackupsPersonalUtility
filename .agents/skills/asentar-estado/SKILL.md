---
name: asentar-estado
description: >
  Deja en disco, VERDADERO, el estado del trabajo de ServersBackupsPersonalUtility sin cerrar la
  jornada ni tocar al coder: lo que está en vuelo, el contador, lo que espera al PO y lo que el
  arquitecto tiene a medio depositar. Es el punto intermedio entre `abrir-jornada` y
  `cerrar-jornada`. Invócala cuando el PO la mande, antes de compactar la sesión o de un
  `/clear`, cuando la propia sesión note que va a compactarse, y al recibir cada reporte del
  coder. Para retomar después se usa `abrir-jornada`.
---

# Asentar estado

**El hueco que tapa.** La única forma de dejar el estado bien escrito era `cerrar-jornada`,
que arrastra al coder —su ronda tiene que terminar—, el informe al PO y la poda. Una
compactación o un `/clear` a mitad de jornada no necesitan nada de eso: necesitan que **lo que
solo vive en la conversación pase al disco**, porque lo que no esté escrito se pierde con ella.

En este proyecto las sesiones se han cortado **tres veces**. Esta skill es barata y se usa
mucho.

**Lo que NO es.** No es un cierre: no se poda, no se entrega el informe final, no se reescribe
`AHORA.md` entero, no se toca al coder ni se espera su ronda, y no se instruye nada.

## 1. Cuándo

- **Al recibir cada reporte del coder**, antes de redactar la siguiente instrucción. Es el uso
  más frecuente y el que más vale.
- **Cuando el PO la mande**, normalmente antes de compactar o de un `/clear`.
- **Cuando la sesión note que va a compactarse** con algo sin depositar.
- **Antes de una tarea que vaya a ocupar mucho contexto**, o de cualquier operación larga.
- **Cuando el PO interrumpe** con otra cosa.

## 2. Qué se hace, en este orden

### 2.1. La conversación, al tramo

Todo lo que el PO dijo y todavía no está escrito, al archivo del tramo en curso
(`estado/tramos/`): sus palabras formalizadas, la hora y a qué contestan.

### 2.1bis. El reporte se anota al RECIBIRLO, y deja rastro en disco

**Una ronda se anota como cerrada cuando llega su reporte, nunca cuando sale su instrucción.**

Y el rastro va al disco, no al canal. Un reporte vive solo en la conversación, así que un
`/clear` en cualquiera de las dos sesiones lo borra sin dejar prueba de que se envió. Pasó con
la ronda `#079`: el coder commiteó, su reporte `#080` no llegó, y hubo que pedírselo otra vez.

Por eso, al recibir cada reporte, el arquitecto pega en el archivo del tramo una línea con:

- el número del mensaje,
- el estado (completado / con desviaciones / bloqueado),
- **los hashes cortos de los commits**,
- los hallazgos, en una línea cada uno.

Lo que **no** se pega: salidas enteras de verificación, ni nada que lleve un secreto.

**Cuando el rastro falta** —porque el canal se perdió— se escribe lo que se puede medir desde
`git log` y **se marca lo que no**: «reconstruido desde git; sin verificar». Un hueco dicho es
estado; un hueco tapado con una suposición es una trampa.

### 2.2. Lo pendiente de depositar, nombrado

Lo que el arquitecto decidió y todavía no pasó a su sitio —un ADR por escribir, una línea de
`.agents/context/`, documentación redactada en el scratchpad— se apunta en el tramo con
**«A DEPOSITAR»**, dónde va y por qué no está todavía. Casi siempre el motivo es el mismo:
**el coder tiene una ronda en vuelo y el árbol es suyo**.

**Si no hay ronda en vuelo, no se apunta: se deposita.**

### 2.3. `AHORA.md`, verdadero en cuatro secciones

No se reescribe entero; se corrigen las cuatro que una sesión nueva lee primero:

| Sección | Tiene que decir |
| :-- | :-- |
| **En vuelo** | La ronda enviada sin reporte, con su número y qué hace; o «nada» y por qué |
| **Contadores** | El último `#NNN` y el último `A-NNN` **reales**, y cuáles tocan |
| **Espera al PO** | Arriba del todo, numerado, con los pasos exactos |
| **Al retomar** | El primer paso concreto al volver |

### 2.4. La comprobación

```bash
bash .agents/scripts/verificar.sh
wc -l estado/AHORA.md    # tope: 200
```

## 3. Reglas que no se saltan

- **Sin secretos.** Ni contraseñas, ni la URL del remoto, ni nada de los `env.sh` de los
  perfiles, `output/HestiaCP/` o `ESTADO.md`. **Ni nombres de servidores, cuentas, dominios,
  bases de datos o IPs reales del PO**: en ejemplos, `example.org` y `203.0.113.10`
  (`40-salvaguardas.md` §1 y §6).
- **`estado/` solo la escribe el arquitecto**, también con una tanda en vuelo. Es la excepción
  a «no escribir en el árbol mientras hay una tanda en vuelo» (regla `30`).
- **No se commitea aquí.** Asentar es escribir en disco. El commit lo hace el coder en su
  próxima ronda, en un `docs(estado):` propio. Lo que importa es que esté en disco: git no se
  pierde con una compactación.
- **Lo escrito tiene que ser verdad en el instante de escribirlo.** Un `AHORA.md` que describe
  lo que *va* a pasar es peor que uno desactualizado: el siguiente se lo cree.

## 4. Tras una compactación

La sesión compactada envía a la otra, **antes de seguir**, el resumen con el que se quedó y en
qué paso estaba. La otra lo contrasta con lo que sabe y con `estado/AHORA.md`, y señala lo que
falte o esté mal. Ese resumen **no consume número** de mensaje y nunca lleva secretos.

## 5. Lo que se le dice al PO

Corto, con su identificador:

1. **Asentado**: qué quedó escrito y dónde.
2. **En vuelo**: lo que está a medias, en una línea.
3. **A depositar**: lo que espera a que el coder termine, si hay algo.
4. **Para retomar**: «`/abrir-jornada`».

## 6. Retomar

**No hay una skill «reanudar»: es `abrir-jornada`**, que ya existe para después de una
compactación o de reabrir el chat, y que lee justo lo que esta skill deja escrito. Dos skills
que hacen lo mismo divergen.

## 7. La comprobación que decide si está asentado

Léete el `AHORA.md` como si fueras una sesión nueva que no ha visto esta conversación:

- ¿Sabrías qué números de mensaje te tocan, los dos?
- ¿Sabrías si hay algo esperando respuesta, y de quién?
- ¿Sabrías cuál es el primer paso?
- ¿Hay algo importante de hoy que solo viva en el chat?

Si alguna respuesta es no, aún no está asentado.
