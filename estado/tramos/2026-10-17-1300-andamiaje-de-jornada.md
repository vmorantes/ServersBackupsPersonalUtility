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
| #109→#110 | Cierre: bitácora 0003 y el estado al día | completado; **el coder encontró que los tres documentos daban tres recuentos distintos de los bloqueos de la guarda** | `3d4203b` `4fdc632` |
| #111→#112 | Corregir los recuentos, con auditoría de los cinco bloqueos | completado | `86cf1ae` |
| #113→#114 | Dejar `AHORA.md` verdadero al cerrar | completado; **el coder encontró una cifra rancia en «Espera al PO»** | `71a0f9f` |
| #115→#116 | Quitar esa cifra y dejar en su lugar cómo medirla | completado; **el coder encontró que un puntero de «Espera al PO» apuntaba a mensajes perdidos** | `e9b1a09` |
| #117→#118 | Recuperar la guía de pruebas de la fase 2 en un documento | completado; **el coder encontró que la guía mandaba ensayar sin decir cómo** | `ae581a9` |
| #119→#120 | Completar la guía: la bandera de ensayo y los cinco pasos que faltaban | completado; **el coder vio que ninguna orden llevaba el perfil** | `eaacadd` |
| #121→#122 | El perfil en cada orden de la guía | completado | — |

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

3. **La guarda frenó el trabajo CINCO veces en un día, y son DOS defectos distintos**, no
   uno. Lo separó el coder, que vio que se estaban contando juntos:
   - **Defecto A — confunde el contenido de un archivo con una orden: 4 veces.** El
     arquitecto escribiendo un documento que citaba órdenes `v-*`; el coder escribiendo un
     script que contenía su propio borrado de temporal; y el arquitecto dos veces más, al
     intentar escribir en el estado y en la bitácora la frase que describía ese bloqueo. Es el
     error ya arreglado para los mensajes de commit (H13), sin aplicar aquí.
   - **Defecto B — no distingue la ruta de un borrado legítimo: 1 vez.** El coder, borrando un
     temporal de su propio scratchpad, que `40-salvaguardas.md` §2 permite expresamente. La
     guarda solo ve que la ruta va en una variable.

   **Ninguna se esquivó**: se reportaron y se usó otra herramienta. Un arreglo que solo cubra
   A deja B vivo.

   **El cinco es un suelo auditado, no un total.** El defecto A siguió disparándose durante el
   propio cierre, al escribir en este archivo textos que citaban órdenes. Se deja de perseguir
   la cifra a propósito: lo que decide si el arreglo vale la pena es que ocurra varias veces
   al día, no el número exacto.

4. **El límite de la puerta nueva, dicho por el coder y que conviene no olvidar:** compara
   contra los tramos, así que **una ronda que no se anota no delata nada**. Protege al que
   escribe el tramo, no al que lo olvida.

5. **El formato de tres dígitos, arreglado en la ronda #107→#108.** Con una trampa dentro:
   `printf` interpreta el octal igual que la comparación, así que hay que normalizar antes de
   comparar **y** antes de imprimir.

6. **El margen del contador es de uno**, y así tiene que ser: los tramos citan hasta el `#110`
   y `AHORA.md` declara el `#110`. La puerta morderá el día que el tramo avance y `AHORA.md`
   no.

7. **Tres documentos de esta jornada daban tres recuentos distintos** de los bloqueos de la
   guarda, y dos se contradecían a sí mismos en párrafos consecutivos. Lo encontró el coder al
   firmarlos, haciendo la lectura de contraste que se le pidió. **Es el mismo defecto que esta
   jornada se dedicó a cazar**, cometido en el documento que lo cuenta. Ninguna puerta lo
   detecta: comparan números de mensaje, no prosa. Corregido con una auditoría de los cinco
   bloqueos, uno a uno.

8. **Cerrar el estado tiene un bucle, y hay que escribir pre-fechado para salir de él.** Cada
   actualización de `estado/` necesita un commit, que necesita una ronda, que genera estado
   nuevo que actualizar. La salida es la que se usó aquí: el arquitecto escribe la ronda de
   cierre **como ya ocurrida** —su número, su fila en este archivo, los contadores—, de modo
   que cuando el coder la commitea, lo escrito es verdad. Es lo mismo que ya se hacía con los
   contadores, aplicado también a la sección «En vuelo». Sin eso, `AHORA.md` termina siempre
   el día diciendo que hay una ronda en vuelo que ya terminó.

9. **Segunda cifra rancia del día, del mismo tipo que el contador.** «Espera al PO» decía
   «68 commits sin subir» desde hacía semanas. No coincide con ninguna medición posible: la
   rama lleva 118 commits sobre `master`, y 20 que este clon cree sin subir. Lo encontró el
   coder leyendo `AHORA.md` **en frío**, como una sesión nueva, que es justo lo que se le
   pidió.

   Y el arquitecto la había propagado al PO esa misma tarde, sumándole los commits del día:
   «82». Una cifra falsa operada aritméticamente sigue siendo falsa, y suena más fiable.

   **Decisión: en `estado/` no se escriben cifras que envejecen; se escribe cómo medirlas.**
   Con su salvedad, porque aquí `fetch` está prohibido: `origin/<rama>` es una referencia
   local, y lo que falta por subir de verdad solo lo sabe el PO.

10. **Lo que encontró el coder salió de leer, no de ejecutar.** Sus tres hallazgos del día
    —el desfase del contador, los recuentos contradictorios y esta cifra— vinieron de un
    resumen de compactación que la regla obliga a enviar, de una lectura de contraste pedida
    expresamente, y de mandarle leer el archivo entero en frío. Ninguno habría aparecido
    ejecutando pasos. **Pedir lectura, y no solo ejecución, es lo que lo hizo rentable hoy.**

11. **El arquitecto podó lo único que el PO tenía para probar la fase 2, el mismo día que
    escribió las reglas de poda.** «Espera al PO» remitía a los reportes `#076`, `#078` y
    `#080` para las tres guías de prueba: mensajes de un canal que ya no existe, que el PO no
    puede abrir. `AHORA.md` conservaba una tabla condensada con las tres órdenes y qué
    comprobar por fuera, y **se borró al reescribir el archivo**, sin estar recogida en ningún
    otro sitio.

    Lo detectó el coder leyendo `AHORA.md` en frío y preguntándose si un puntero servía de
    algo. Recuperado en `.agents/docs/guia-pruebas-fase-2.md`, con lo irrecuperable marcado
    como tal.

    **La lección, que vale más que el archivo: lo que el PO necesita para trabajar no puede
    vivir solo en un mensaje.** Y podar exige comprobar antes que lo podado está recogido en
    otro sitio, no suponerlo.

12. **Cifras que pueden envejecer, medidas y listadas por el coder** (§4.2 de la ronda
    `#115`): «23 suites», «seis puertas» y «12 afirmaciones» son correctas hoy **y las imprime
    `verificar.sh` en cada ejecución**, así que son las únicas de `AHORA.md` que una puerta
    podría comprobar por máquina. «Siete pasos y medio de ocho» es la que peor envejece:
    parece precisa y «medio» es un juicio. Ninguna se arregla hoy; quedan medidas para cuando
    el PO lo nombre.

    Detalle que sorprende y no es un error: el script tiene **seis** puertas pero imprime
    **cinco** líneas `ok:`. La puerta 0, la de que el archivo existe, solo habla cuando falla.

13. **La guía recuperada mandaba ensayar y no decía cómo.** Decía «el ensayo primero,
    siempre» sin nombrar `--dry-run` en ninguna de sus tres filas. Y la ayuda del programa
    agrava el hueco: su sección ENSAYO lista siete órdenes y **ninguna suborden de `hestia`**,
    así que el PO habría concluido que no hay ensayo, en el paso que la propia guía llama «el
    delicado».

    Verificado antes de corregir: el bloque `hestia` de `bin/backupctl` **sí** reconoce
    `--dry-run|-n`, y `lib/hestia.sh` corta antes de escribir. **El código está bien; la ayuda
    y la guía estaban mal.** Guía corregida; la ayuda queda pendiente.

    Es la tercera vez en el proyecto que un documento correcto en lo que afirma resulta
    peligroso por lo que **omite**. Las otras dos rompieron servidores del PO.

14. **La guía cubría tres de los ocho pasos.** Ampliada con `hestia rclone` como paso 0,
    `hestia copia` —que demuestra el respaldo en minutos en vez de esperar al cron del día
    siguiente, leyendo las instantáneas antes y después— y `hestia keys` + `hestia desactivar`
    **en ese orden**, porque `desactivar` se niega sin un rescate previo y esa negativa parece
    un fallo sin serlo. Y una línea diciendo que `exclusiones` está en solo lectura a
    propósito, para ahorrar un viaje.

15. **La guía no decía contra QUÉ servidor se ejecuta.** Ninguna de sus trece órdenes llevaba
    `-p <perfil>`. El encabezado decía «servidor de PRUEBAS» en negrita, pero eso es prosa y
    lo que se copia son las líneas. Mismo patrón que el `--dry-run`: dicho en prosa, ausente
    del comando.

    Y el matiz que lo hace serio, medido por el coder: con **varios** perfiles la herramienta
    se niega a adivinar y pide `-p`; **con uno solo, elige en silencio**. El PO acaba de
    migrar servidores, así que su juego de perfiles puede no ser el de este clon.

16. **El ensayo de `hestia exclusiones` promete una escritura que no ocurre.** El corte por
    `--dry-run` está antes del `bc_err` que deja la orden en solo lectura, así que el ensayo
    anuncia una copia fechada y el camino real se niega. No escribe en ninguno de los dos
    casos. Es la única orden donde el ensayo y el camino real no dicen lo mismo, y se resuelve
    solo al cerrar el paso 8.

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
