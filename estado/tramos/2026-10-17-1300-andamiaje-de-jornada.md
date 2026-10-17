# Tramo: el andamiaje de jornada

- **Inicio:** 2026-10-17, 13:00.
- **Mandato del PO:** «necesitamos imitar las skills `asentar-estado`, `cerrar-jornada`,
  `abrir-jornada` adaptadas a nosotros», y después: «termina de implementar este asunto ya
  […] deja el árbol limpio».
- **Rama:** `release/2.1`.
- **Referencia que el PO dio:** las skills del mismo nombre de otro de sus repositorios, en
  solo lectura.

## Rondas

| Ronda | Qué | Estado | Commits |
| --- | --- | --- | --- |
| sin coder | Las tres skills, la unificación de `cierre-de-tramo`, las puertas del estado y su prueba de rechazo, el contador `A-NNN`, `AHORA.md` reescrito | completado, **con desviación**: lo escribió y commiteó el arquitecto por orden expresa del PO | `7f0eb3d` `70a69c3` `13d5650` `bb6f4f8` `576a860` `ca0f649` `f360830` `623728f` `44b0e49` `67fcc70` |
| #103→#104 | Identificación del coder y su resumen de compactación | completado; **el coder encontró el desfase del contador** | — |
| #105→#106 | La puerta del contador contra los tramos, con su prueba de rechazo | completado | `4267744` `c2e67c2` |
| #107→#108 | Documentación, el archivo de este tramo, y los números a tres dígitos | completado; **el coder separó dos defectos de la guarda que se contaban como uno** | `5427423` `dac630b` `0bf1291` |
| #109→#110 | Cierre: bitácora 0003 y el estado al día | completado | — |

## Hallazgos

1. **El contador llevaba casi un mes mintiendo.** `estado/AHORA.md` declaraba «último usado
   #081» desde el 2026-09-24, mientras `estado/tramos/2026-09-23-2300-fases-1-y-2.md`
   registraba rondas hasta el **#097** y decía «Mensajes: #053–#097». Dos documentos del mismo
   día, escritos por el mismo arquitecto, contradiciéndose. Lo detectó el coder al volver de
   una compactación, comparándolo con su propio último número, el **#102**.

   Lo hizo **como debe hacerse**: lo reportó, no lo arregló, y aceptó la numeración del
   arquitecto dejando constancia de la discrepancia.

   Consecuencia: los mensajes etiquetados `#082` y `#083` son en realidad el `#103` y el
   `#104`. Se dejan con su etiqueta y consta aquí.

2. **Dos fallos de disciplina del arquitecto, el mismo día.**
   - Commiteó sin coder. Autorizado por el PO, pero no lo dijo: lo hizo en silencio.
   - Afirmó que **no había coder** sin medirlo. Lo había, abierto y renombrado por el PO. Una
     orden lo contestaba.

   Los dos están convertidos en regla, no en nota: `30-protocolo-coder.md`, sección «Si no hay
   coder, se pide; no se sustituye», y la pregunta 2 de `abrir-jornada` pasa a ser «¿hay
   coder, y qué está en vuelo?», con la medición obligatoria.

3. **La guarda frenó el trabajo cuatro veces en un día, y son DOS defectos distintos**, no
   uno. Lo separó el coder, que vio que se estaban contando juntos:
   - **Defecto A — confunde el contenido de un archivo con una orden.** Cinco veces: al
     arquitecto escribiendo un documento que citaba órdenes `v-*`; al coder escribiendo un
     script que contenía su propio borrado de temporal; y al arquitecto tres veces más, al
     intentar describir por escrito ese mismo bloqueo. Es el error ya arreglado para los
     mensajes de commit (H13), sin aplicar aquí.
   - **Defecto B — no distingue la ruta de un borrado legítimo.** Al coder, borrando un
     temporal de su propio scratchpad, que `40-salvaguardas.md` §2 permite expresamente. La
     guarda solo ve que la ruta va en una variable.

   **Ninguna se esquivó**: se reportaron y se usó otra herramienta. Un arreglo que solo cubra
   A deja B vivo.

4. **El límite de la puerta nueva, dicho por el coder y que conviene no olvidar:** compara
   contra los tramos, así que **una ronda que no se anota no delata nada**. Protege al que
   escribe el tramo, no al que lo olvida.

5. **El formato de tres dígitos, arreglado en la ronda #107→#108.** Con una trampa dentro:
   `printf` interpreta el octal igual que la comparación, así que hay que normalizar antes de
   comparar **y** antes de imprimir.

6. **El margen del contador es de uno**, y así tiene que ser: los tramos citan hasta el `#110`
   y `AHORA.md` declara el `#110`. La puerta morderá el día que el tramo avance y `AHORA.md`
   no.

## Decisiones

- **`cierre-de-tramo` se unifica en `cerrar-jornada`** y se borra. Cerrar un tramo es el caso
  corto de cerrar la jornada; dos skills que hacen lo mismo divergen. No quedaba ninguna
  referencia a ella en el repositorio.
- **Se adopta el contador `A-NNN`** para los mensajes del arquitecto al PO, además del `#NNN`
  compartido con el coder, y **las partes de cada mensaje van numeradas** para que el PO pueda
  citarlas. Petición suya del 2026-10-17; escrito en `30-protocolo-coder.md`.
- **`migraciones/` no se versiona entera.** El `.gitignore` exceptuaba su `README.md`, y ese
  README nombra cuentas, dominios y servidores reales, que `40-salvaguardas.md` §1 prohíbe
  fuera de los directorios de perfil. Error del arquitecto al crearlo, corregido el mismo día.
  Lo genérico vive en `.agents/docs/mejoras-herramienta-migracion.md`, que sí se versiona.

## Fallos por el camino, y cómo se resolvieron

- **La prueba de rechazo de las puertas falló en su primera ejecución**, y el fallo estaba en
  la prueba: generaba nombres de archivo de tramo repetidos, así que el caso de «14 tramos sin
  podar» nunca llegaba a crear 14 y pasaba en falso. Corregido antes de entrar. Es exactamente
  para lo que sirve una prueba de mutación.
- **El octal.** La comparación aritmética de bash lee `097` como octal y habría dado error de
  sintaxis en vez de comparar. El tramo real tiene ese número. Lo cazó el coder y quitó los
  ceros a la izquierda antes de comparar.

## Cerrado

- **Duración:** 13:00 a 16:00 del 2026-10-17. Tres rondas con coder, más un tramo inicial sin
  él por orden del PO.
- **Bitácora:** `.agents/docs/bitacora/0003-andamiaje-de-jornada.md`.

## Pendiente del PO

1. `git push` de `release/2.1`.
2. Nombrar la tarea siguiente: cerrar la fase 2, o lo que él decida.
3. Lo anterior suyo sigue en `estado/AHORA.md`, «Espera al PO».
