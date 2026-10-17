# 0003 — Andamiaje de jornada

- **Fecha:** 2026-10-17
- **Pedido por:** Product Owner («necesitamos imitar las skills `asentar-estado`,
  `cerrar-jornada`, `abrir-jornada` adaptadas a nosotros»; después: «termina de implementar
  este asunto ya […] deja el árbol limpio»)
- **ADR relacionados:** 0004 (estado y continuidad), 0010 (prueba de mutación obligatoria)

## Qué se pidió

Tres rituales —abrir el día, asentar el estado a mitad, cerrar el día— imitando los de otro
repositorio del PO, que él señaló como referencia en solo lectura. Con una condición explícita
suya: **que sirvan para sobrevivir a un `/clear`**.

## Qué se encontró al explorar

Las skills de referencia tenían tres ideas que aquí no existían y que resultaron ser lo
valioso:

- **Las preguntas de apertura como contrato**, no como recordatorio: `AHORA.md` tiene que
  poder contestarlas, y si no puede, el hueco es el hallazgo y se tapa antes de trabajar.
- **Dos contadores**: uno para la cadena con el coder y otro para los mensajes al PO. Sin el
  segundo, el PO no puede citar un mensaje.
- **Anotar el reporte del coder al recibirlo, con sus hashes, en disco.** Un reporte vive solo
  en el canal; un `/clear` lo borra sin dejar prueba de que se envió. Aquí ya había pasado con
  la ronda `#079`.

Y una redundancia propia: `cierre-de-tramo` hacía casi lo mismo que `cerrar-jornada`. No
quedaba ninguna referencia a ella en el repositorio.

## Qué se instruyó

El primer tramo lo escribió y commiteó **el arquitecto sin coder**, por orden expresa del PO
(diez commits). Es una desviación de la regla 30, anotada como tal.

Después, con coder: `#103→#104` la identificación y su resumen de compactación; `#105→#106`
la puerta del contador y su prueba de rechazo; `#107→#108` la
documentación, el tramo y el formato de tres dígitos; `#109→#110` el cierre, y `#111→#112` la corrección
de los recuentos que el coder encontró al firmarlo.

## Qué se obtuvo

- Tres skills (`abrir-jornada`, `asentar-estado`, `cerrar-jornada`), con `cierre-de-tramo`
  unificada dentro de la última y borrada.
- El contador `A-NNN` y las partes numeradas de cada mensaje al PO, en la regla 30.
- **Seis puertas por máquina** en `.agents/scripts/puertas_estado.sh`, dentro de
  `verificar.sh`, con 12 afirmaciones de prueba de rechazo: existencia de `AHORA.md`, tope de
  200 líneas, un solo bloque «al retomar», los dos contadores declarados, el contador contra
  los tramos, y los tramos podados.
- `estado/AHORA.md` reescrito entero contra el contrato de ocho secciones.

## Lo que apareció a mitad de camino, y es lo que vale de esta entrada

**El contador llevaba casi un mes mintiendo.** `AHORA.md` declaraba «último usado #081» desde
el 2026-09-24, mientras el archivo del tramo de **ese mismo día** registraba rondas hasta el
`#097`. Dos documentos del mismo día, del mismo autor, contradiciéndose. Lo detectó el coder
al volver de una compactación, comparándolo con su propio último número, el `#102`. Lo reportó
y **no lo arregló**, que es lo que la regla pide.

De ahí salió la puerta del contador: comparar lo que `AHORA.md` declara con el mayor `#NNN`
que registren los tramos. Su límite, dicho por el mismo coder: **compara contra los tramos,
así que una ronda que no se anota no delata nada**. Protege al que escribe el tramo, no al que
lo olvida.

**Dos fallos de disciplina del arquitecto, el mismo día**, los dos convertidos en regla y no
en nota: commitear sin coder sin decirlo, y **afirmar que no había coder sin medirlo** —lo
había, abierto y renombrado por el PO, y una orden lo contestaba—.

**El octal.** La comparación aritmética de bash lee `097` como octal y habría dado error de
sintaxis. El tramo real tiene ese número. Lo cazó el coder, y volvió a cazarlo al rellenar a
tres dígitos: `printf '%03d' 097` falla igual. Normalizar antes de comparar **y** antes de
imprimir.

**Una prueba de mutación que cazó su propia prueba.** El caso de «14 tramos sin podar» pasaba
cuando debía fallar, porque la prueba generaba nombres de archivo repetidos y nunca llegaba a
crear 14. Corregido antes de entrar.

**Y la guarda, cinco veces en un día, por DOS defectos distintos.** Cuatro por confundir el
contenido de un archivo con una orden —un documento que citaba órdenes `v-*`, un script que
contenía su propio borrado de temporal, y dos intentos de escribir en el estado y aquí mismo
la frase que describía ese bloqueo—, y una quinta por no distinguir la ruta de un borrado
legítimo dentro del scratchpad de la sesión, que las salvaguardas permiten expresamente. Los
separó el coder, que vio que se estaban contando como un solo defecto. Ninguna de las cinco se
esquivó: se reportaron y se usó otra herramienta.

**Y una última, que es la que más dice de todo esto.** Al cerrar, el coder encontró que los
tres documentos de esta jornada daban **tres recuentos distintos** de esos bloqueos, y que dos
se contradecían a sí mismos en párrafos consecutivos. El hallazgo central del día es «dos
documentos del mismo día, del mismo autor, contradiciéndose, y nadie lo vio en un mes», y el
documento que lo cuenta tenía el mismo defecto al lado. **Ninguna puerta lo caza**: la del
contador compara números de mensaje, no recuentos en prosa. Lo caza alguien que lee. Las
cifras de arriba son las de una auditoría de los cinco bloqueos, uno a uno.

## Qué se dejó fuera

- **El arreglo de la guarda**, que son dos defectos distintos y no uno.
- **Comprobar que ningún reporte quede sin anotar.** No hay fuente canónica contra la que
  compararlo; si la hubiera, el problema no existiría.
- **Que el contador acierte.** La puerta detecta que se quede atrás, que es el fallo que ya
  ocurrió; no que el número sea el correcto.
