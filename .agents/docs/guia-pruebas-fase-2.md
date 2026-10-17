# Guía de pruebas de la fase 2, para el servidor de PRUEBAS del PO

**Nada de lo que describe este documento se ha ejecutado nunca contra un HestiaCP real.** Todo
se probó en el banco local, con órdenes falsas y datos sintéticos. El ADR 0006 reserva al PO
las operaciones contra servidores, y ésta es su guía.

**Servidor de PRUEBAS, no el de producción.**

## Por qué existe este archivo

Las guías completas vivían en los reportes `#076`, `#078` y `#080`, que eran mensajes de un
canal que ya no existe: el PO no puede abrirlos. `estado/AHORA.md` conservaba una tabla
condensada, y **el arquitecto la borró al reescribir ese archivo el 2026-10-17**, podando algo
que no estaba recogido en ningún otro sitio. Lo detectó el coder al leer `AHORA.md` en frío.

Esto es esa tabla recuperada y ampliada. **Lo que no se pudo recuperar está marcado como tal**:
el detalle completo de los tres reportes originales se perdió, y lo que queda es la forma
condensada más lo que consta en el archivo del tramo de la fase 2.

Lección, que vale más que el archivo: **lo que el PO necesita para trabajar no puede vivir solo
en un mensaje**. Si está en el chat y no en el repositorio, un `/clear` lo borra.

## Regla que vale para los tres pasos

1. **El ensayo primero, siempre.** Las tres órdenes tienen modo de ensayo que no escribe nada.
   Se ejecuta, se lee lo que dice que va a hacer, y solo entonces se repite en serio.
2. **La comprobación no la hace la orden.** Cada paso trae su comprobación **por fuera**, y es
   la única que vale. `40-salvaguardas.md` §5: ningún éxito sin comprobación independiente.
3. **Para diagnosticar, la línea de órdenes.** La web no siempre pasa por `backupctl` y puede
   enseñar un estado distinto del mismo servidor. **Si las dos discrepan, manda
   `hestia status`.** Se aborda en la fase 3 (decisión del PO, 2026-09-24).

## Los tres pasos

| Paso | Orden | Qué comprobar POR FUERA |
| --- | --- | --- |
| Registrar el repositorio | `hestia restic --repo '<repo>'` | que el panel muestre lo pedido; que el `.bak` conserve lo anterior; que el informe de la orden coincida con lo que enseña el panel |
| Programar el respaldo | `hestia cron` | `crontab -u hestiaweb -l` enseña la línea con **ruta absoluta**; el crontab queda en modo `600` y propiedad `hestiaweb:hestiaweb` |
| Marcar las cuentas | `hestia cuentas` | `grep BACKUPS_INCREMENTAL /usr/local/hestia/data/users/*/user.conf`; **y que la cuenta siga igual en todo lo demás**: shell, cuotas, dominios |

### El tercero es el delicado

**Empezar por una sola cuenta** (`--usuarios <cuenta>`) antes de lanzarlo sobre todas. Motivo
concreto: lo que sabemos de la orden de HestiaCP que hay debajo viene de **leer su código, no
de ejecutarlo**. En particular, que `v-change-user-config-value` con la clave ya presente no
toque nada más que esa clave está **SIN VERIFICAR** contra un servidor real.

Y el aviso que lo hace importante: si esa clave **falta** en el `user.conf`, esa orden de
HestiaCP dispara un `v-rebuild-user` completo. Por eso se mira la cuenta entera después, no
solo la clave.

## La prueba que de verdad demuestra algo tarda un día

Los tres pasos anteriores demuestran que **se escribió** lo que se pedía. No demuestran que el
respaldo funcione.

Al día siguiente, con el cron ya ejecutado:

```
hestia status
```

Tiene que enseñar **una instantánea reciente**. Si no la hay, algo de la cadena falló en
silencio — y hay un motivo conocido para que falle en silencio: en HestiaCP, `E_BACKUP` está
sin definir, así que **un respaldo incremental fallido registra éxito**. Verificado contra su
código fuente.

## Lo que se va a ver mal, y no es un fallo

Si estas órdenes se lanzan **desde la web**, la web llama a todo con `-y`. Las dos negativas
nuevas —negarse a desactivar sin claves rescatadas, y negarse a pisar un remoto existente— se
dispararán ahí con mensajes escritos para una terminal. **Protegen igual; se verán mal.** Se
arregla en la fase 3.

## Qué reportar al arquitecto después

Lo que la guía no puede anticipar es lo que más vale:

- La **salida real** de cada orden, no un resumen.
- Si el panel y la línea de órdenes dijeron cosas distintas, y cuál.
- Si alguna cuenta cambió en algo que no fuera la clave de respaldo.
- Si al día siguiente **no** había instantánea.
