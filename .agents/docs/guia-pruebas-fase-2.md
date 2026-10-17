# Guía de pruebas de la fase 2, para el servidor de PRUEBAS del PO

**Nada de lo que describe este documento se ha ejecutado nunca contra un HestiaCP real.** Todo
se probó en el banco local, con órdenes falsas y datos sintéticos. El ADR 0006 reserva al PO
las operaciones contra servidores, y ésta es su guía.

**Servidor de PRUEBAS, no el de producción.**

---

## LO PRIMERO: cómo se ensaya, y por qué la ayuda dice otra cosa

El ensayo se activa con **`--dry-run`** (o `-n`), y **funciona en todas las subórdenes de
`hestia`**. Verificado el 2026-10-17 leyendo el código: el bloque `hestia` de `bin/backupctl`
reconoce la bandera, y las tres órdenes de la tabla de abajo salen con `return 0` **antes** de
escribir nada.

**Pero `backupctl --help` no lo dice.** Su sección ENSAYO lista
`backup · restore · retention · restic · deploy · pull · migrate` y **no menciona ninguna
suborden de `hestia`**. Ese `restic` de la lista es la orden de primer nivel, que es otra cosa
distinta de `hestia restic`.

Así que si contrasta esta guía con la ayuda, la ayuda le dirá que no hay ensayo. **La ayuda
está incompleta; la guía es correcta.** Es un fallo conocido de la ayuda, pendiente de
arreglar.

Lo escribo así de destacado porque el accidente del 2026-09-24 tuvo exactamente esta forma:
documentación que se sigue al pie de la letra y a la que le falta un dato.

---

## LO SEGUNDO: el perfil decide contra QUÉ servidor se ejecuta

Todas las órdenes de esta guía llevan **`-p <perfil-de-pruebas>`**. Sustituya el marcador por
el nombre de su perfil de pruebas, y no lo quite.

**Es lo único que decide contra qué servidor se ejecuta.** Que arriba ponga «servidor de
PRUEBAS» es prosa; lo que se copia y se pega son las líneas.

Y hay un caso que no avisa: **si en la máquina solo hay un perfil, se elige sin preguntar**.
Con varios, `backupctl` se niega a adivinar y le pide `-p`, listando los disponibles —el
comentario de `lib/config.sh` lo explica: adivinar cuál es el de producción sería peligroso—.
Pero con uno solo, ese camino seguro no se recorre.

`-p` puede ir en cualquier posición de la línea, también detrás de la suborden.

---

## Reglas que valen para todos los pasos

1. **El ensayo primero, siempre.** Se ejecuta con `--dry-run`, se lee lo que dice que va a
   hacer, y solo entonces se repite sin la bandera.
2. **La comprobación no la hace la orden.** Cada paso trae su comprobación **por fuera**, y es
   la única que vale (`40-salvaguardas.md` §5: ningún éxito sin comprobación independiente).
3. **Para diagnosticar, la línea de órdenes.** La web no siempre pasa por `backupctl` y puede
   enseñar un estado distinto del mismo servidor. **Si las dos discrepan, manda
   `hestia status`.** Se aborda en la fase 3 (decisión del PO, 2026-09-24).

---

## Paso 0 — el almacenamiento

```
backupctl -p <perfil-de-pruebas> hestia rclone --dry-run
backupctl -p <perfil-de-pruebas> hestia rclone
```

Es el primero de la cadena: sin remoto configurado, los demás no tienen dónde escribir. **Si
su servidor de pruebas ya lo tiene configurado, sáltelo**; `hestia status` se lo dirá.

---

## Pasos 1 a 3 — registrar, programar, marcar

| Paso | Orden (ensayo + real) | Qué comprobar POR FUERA |
| --- | --- | --- |
| Registrar el repositorio | `backupctl -p <perfil-de-pruebas> hestia restic --repo '<repo>' --dry-run`, luego sin `--dry-run` | que el panel muestre lo pedido; que el `.bak` conserve lo anterior; que el informe de la orden coincida con lo que enseña el panel |
| Programar el respaldo | `backupctl -p <perfil-de-pruebas> hestia cron --dry-run`, luego sin ella | `crontab -u hestiaweb -l` enseña la línea con **ruta absoluta**; el crontab queda en modo `600` y propiedad `hestiaweb:hestiaweb` |
| Marcar las cuentas | `backupctl -p <perfil-de-pruebas> hestia cuentas --usuarios <cuenta> --dry-run`, luego sin ella | `grep BACKUPS_INCREMENTAL /usr/local/hestia/data/users/*/user.conf`; **y que la cuenta siga igual en todo lo demás**: shell, cuotas, dominios |

### El tercero es el delicado

**Empezar por una sola cuenta** (`--usuarios <cuenta>`) antes de lanzarlo sobre todas. Motivo
concreto: lo que sabemos de la orden de HestiaCP que hay debajo viene de **leer su código, no
de ejecutarlo**. Que `v-change-user-config-value` con la clave ya presente no toque nada más
que esa clave está **SIN VERIFICAR** contra un servidor real.

Y el aviso que lo hace importante: si esa clave **falta** en el `user.conf`, esa orden de
HestiaCP dispara un `v-rebuild-user` completo. Por eso se mira la cuenta entera después, no
solo la clave.

**Ojo con la clave que se busca**: la de cada `user.conf` es `BACKUPS_INCREMENTAL`, en plural.
Existe otra parecida, `BACKUP_INCREMENTAL` en singular, que es la global que pone HestiaCP.
Son distintas.

---

## Paso 4 — la copia comprobada, que es la prueba de verdad

```
backupctl -p <perfil-de-pruebas> hestia copia --usuarios <cuenta> --dry-run
backupctl -p <perfil-de-pruebas> hestia copia --usuarios <cuenta>
```

**Este paso es el que demuestra que el respaldo funciona, y no hay que esperar al día
siguiente para tenerlo.** Lee la lista de instantáneas **antes**, lanza la copia, vuelve a
leerla, y el veredicto sale de la **diferencia**. Si no puede leer el «antes», **no lanza
nada**: sin ese dato no podría demostrar nada, y prefiere no hacer que mentir.

Hágalo **después** de marcar la cuenta y **antes** de dar nada por bueno.

---

## Paso 5 — las claves, y luego desactivar. En ese orden

```
backupctl -p <perfil-de-pruebas> hestia keys --dry-run
backupctl -p <perfil-de-pruebas> hestia keys

backupctl -p <perfil-de-pruebas> hestia desactivar --dry-run
backupctl -p <perfil-de-pruebas> hestia desactivar
```

**No son dos pasos independientes.** `desactivar` **se niega** si no encuentra un rescate
anterior de las claves. Si prueba `desactivar` sin haber hecho `keys` antes, verá una negativa
que parece un fallo **y no lo es**: es la protección funcionando.

`desactivar` **no borra** las copias que ya existen. Deja de hacer nuevas.

Y lo de siempre, que vale para su producción igual que para pruebas: **las claves rescatadas
hay que sacarlas del servidor**. Una clave que solo vive dentro de lo que protege no protege
nada.

---

## `hestia exclusiones` no necesita prueba

Está en **solo lectura a propósito**, con una negativa explícita antes de escribir. Muestra
qué queda fuera del respaldo, traducido, y no ofrece cambiarlo. Si lo prueba esperando que
escriba, verá una negativa **deliberada**, no un fallo. Se completará cuando se cierre el paso
8 de la fase 2.

---

## Y al día siguiente, el cron

Los pasos anteriores demuestran que se escribió lo que se pedía, y el paso 4 demuestra que una
copia lanzada a mano funciona. Falta que funcione **sola**.

Al día siguiente, con el cron ya ejecutado:

```
backupctl -p <perfil-de-pruebas> hestia status
```

Tiene que enseñar **una instantánea reciente**. Si no la hay, algo de la cadena falló en
silencio — y hay un motivo conocido para que falle en silencio: en HestiaCP, `E_BACKUP` está
sin definir, así que **un respaldo incremental fallido registra éxito**. Verificado contra su
código fuente (ADR 0017).

---

## Lo que se va a ver mal, y no es un fallo

Si estas órdenes se lanzan **desde la web**, la web llama a todo con `-y`. Las dos negativas
nuevas —negarse a desactivar sin claves rescatadas, y negarse a pisar un remoto existente— se
dispararán ahí con mensajes escritos para una terminal. **Protegen igual; se verán mal.** Se
arregla en la fase 3.

---

## Qué reportar después

Lo que la guía no puede anticipar es lo que más vale:

- La **salida real** de cada orden, no un resumen.
- Si el panel y la línea de órdenes dijeron cosas distintas, y cuál.
- Si alguna cuenta cambió en algo que no fuera la clave de respaldo.
- Si al día siguiente **no** había instantánea.

## Por qué existe este archivo

Las guías completas vivían en los reportes `#076`, `#078` y `#080`: mensajes de un canal que
ya no existe y que el PO no puede abrir. `estado/AHORA.md` conservaba una tabla condensada, y
**el arquitecto la borró al reescribir ese archivo el 2026-10-17**, podando algo que no estaba
recogido en ningún otro sitio. Lo detectó el coder al leer `AHORA.md` en frío, y amplió esta
guía contrastándola contra el código.

**El detalle completo de aquellos tres reportes se perdió y no se ha inventado.**

Lección, que vale más que el archivo: **lo que el PO necesita para trabajar no puede vivir
solo en un mensaje.** Si está en el chat y no en el repositorio, un `/clear` lo borra.
