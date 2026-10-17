# Mejoras para la herramienta de migración

Documento de trabajo. Recoge lo aprendido usando `HestiaCPCliMigrationUtility` en una
migración real de tres cuentas entre dos servidores HestiaCP 1.10.5, el 2026-10-02.

Ese repositorio es de solo lectura desde aquí: esto es una lista de propuestas para cuando se
trabaje en él, no un cambio hecho. Los ejemplos usan nombres ficticios (`example.org`,
`203.0.113.10`) porque este archivo sí se versiona.

**Lo primero, en honor a la verdad**: la herramienta hizo su trabajo. Tres cuentas, nueve
dominios, dos Nextcloud y varias decenas de miles de archivos en una mañana, con buzones,
contraseñas y reenvíos conservados. Lo que sigue no la descalifica; son los sitios donde hubo
que vigilarla a mano, y cada uno podía haber costado un servicio caído.

---

## Principio que resume todas las mejoras

**La herramienta informa de lo que se propone hacer, no de lo que consiguió.** Casi todos los
puntos de abajo son la misma idea aplicada en sitios distintos: una línea de salida que dice
`Haciendo X` no es una comprobación de que X ocurrió. Una migración es irreversible en cuanto
se apaga el servidor de origen, así que cada afirmación tiene que apoyarse en una lectura
posterior e independiente.

---

## 1. Forzar HTTPS sin comprobar que hay certificado

**Gravedad: alta. Es la que puede tumbar todos los sitios de una cuenta a la vez.**

En la fase 2, la emisión del certificado y el forzado de HTTPS son dos bloques
independientes. El segundo se ejecuta aunque el primero se haya saltado o haya fallado. El
plan llegó a imprimir, para los cinco dominios a la vez:

```
emitir certificado SSL    [SE OMITIRÁ: aún no resuelve aquí]
forzar HTTPS              sí
```

Si eso se confirma, los cinco dominios quedan redirigiendo a un HTTPS sin certificado válido:
nadie entra a ninguno, y el navegador muestra un aviso de seguridad.

**Propuesta**: forzar HTTPS solo si el certificado de ese dominio quedó emitido y verificado en
la misma corrida. Si no, saltarlo y decirlo. Y en el plan, marcar la combinación
«sin certificado + forzar HTTPS» como un aviso destacado, no como dos líneas seguidas.

## 2. La emisión de certificados no comprueba su resultado

La salida fue, literalmente, una línea por dominio:

```
Let's Encrypt -> example.org
Let's Encrypt -> sub.example.org
```

Ni un código de salida, ni un `ok`, ni un `falló`. Para saber si habían funcionado hubo que
comprobarlo por fuera con `openssl s_client` y mirar el emisor y la fecha de caducidad.

**Propuesta**: capturar el resultado de cada emisión, y verificarlo después contra el puerto
443 leyendo emisor, CN y caducidad. Terminar la fase con un resumen de emitidos y fallidos.
Un dominio fallido no puede terminar en «FASE 2 COMPLETADA» sin más.

## 3. La comprobación de DNS usa el resolutor local

La herramienta decide si un dominio «ya resuelve aquí» preguntando con el resolutor del
sistema del servidor de destino. Ese resolutor puede tener cacheada la respuesta anterior
durante todo el TTL.

Pasó exactamente eso: el mundo entero veía ya la IP nueva —comprobado en cuatro resolutores
públicos— y el servidor seguía viendo la vieja, porque el resolutor de su proveedor no se
había actualizado. La herramienta se saltó los cinco certificados.

**Propuesta**: preguntar a un resolutor público (1.1.1.1, 8.8.8.8) o directamente a los NS
autoritativos del dominio, nunca solo al del sistema. Y decir en la salida **con qué resolutor
se comprobó**, para que una discrepancia sea legible en vez de un misterio.

## 4. Los cronjobs se migran con su comando literal

Un cronjob que invoca un intérprete por su nombre corto —`php`, `python`, `node`— no significa
lo mismo en los dos servidores. En esta migración, el cron de un Nextcloud llamaba a
`php .../cron.php`: en el origen era una versión compatible, y en el destino `php` resolvía a
una versión que esa aplicación rechaza. El cron habría fallado cada cinco minutos en silencio.

**Propuesta**: detectar en los comandos migrados las invocaciones a un intérprete por nombre
corto, avisar de ello en el plan, y ofrecer reescribirlas con la ruta explícita de la versión
que el dominio tiene declarada. Como mínimo, listarlas al terminar para revisarlas a mano.

## 5. Los cronjobs quedan activos desde el primer momento

Mientras el DNS siga apuntando al servidor viejo, las tareas programadas se ejecutan **en los
dos a la vez**, cada una contra su propia base de datos. Para un gestor de contenidos suele ser
inocuo; para algo que factura, envía correo o llama a una API, no.

**Propuesta**: migrarlos suspendidos por omisión, y una fase o una opción explícita para
activarlos cuando el corte de DNS ya esté hecho. Y documentar que en el servidor de origen hay
que desactivarlos.

## 6. Los alias y reenvíos de correo se dan por buenos sin comprobarlos

La salida imprime `alias: X` pase lo que pase. En esta migración, un alias de dominio web se
reportó como no migrado y, al mirarlo, había que crearlo a mano; pero la comprobación la hizo
una persona, no la herramienta.

**Propuesta**: después de crear cada alias o reenvío, releerlo del destino y comparar con el
origen. Mismo principio que todo lo demás.

## 7. El correo cuenta archivos, no mensajes

Lo que se reporta es lo que movió `rsync`. Un buzón puede copiarse con archivos de menos sin
que nada chille.

**Propuesta**: contar mensajes por buzón en origen y destino y compararlos, como ya se hace
con las tablas de las bases de datos. Ese recuento de tablas fue, de hecho, lo más tranquilizador
de toda la migración: es el modelo a imitar.

## 8. Nextcloud no está entre las aplicaciones conocidas

La herramienta sabe reescribir la configuración de WordPress, Joomla, Drupal, PrestaShop y
Laravel. Con Nextcloud hay que declarar `tipo="ninguno"` y editar a mano `config/config.php`
tras la fase 1. Hasta que eso se hace, la aplicación no arranca.

**Propuesta**: añadir el tipo, cambiando **solo** la contraseña de la base de datos. Nunca
`instanceid`, `passwordsalt` ni `secret`: tocarlos inutiliza las contraseñas guardadas de los
usuarios. Avisar también de que el `config.php` puede tener `config_is_read_only`.

## 9. La detección automática del tipo de aplicación adivina

En cuatro dominios que solo contenían un `index.html` y un `robots.txt`, la herramienta
dedujo `tipo: piecesphp`. No tuvo consecuencias porque ninguno tenía base de datos, pero la
deducción era falsa.

**Propuesta**: distinguir «detectado con evidencia» de «no se pudo determinar», y no reescribir
nada basándose en lo segundo. Es el mismo principio que ya está escrito en las convenciones de
este repositorio: vacío y «no lo sé» no se escriben igual.

## 10. Nada impide saltarse `sincronizar`

Se puede ir de la fase 1 a la fase 2 con el DNS ya movido por el medio. Todo lo que se
escribiera en el origen entre ambas se queda atrás, sin que nadie lo diga.

**Propuesta**: registrar cuándo se ejecutó cada fase, y que la fase 2 avise si ha pasado un
tiempo relevante desde la fase 1 sin un `sincronizar` por medio. Y documentar que lanzar
`sincronizar` **después** del corte de DNS es peligroso, porque puede pisar con versiones
antiguas lo que ya se escribió en el destino.

## 11. El paquete lleva contraseñas y no se limpia solo

El autoextractor contiene el archivo de descripción con las contraseñas de todas las bases de
datos. Se sube a `/tmp` del destino y ahí se queda.

**Propuesta**: avisarlo al terminar cada fase, con la orden de borrado, y ofrecer borrarse a sí
mismo tras la última. Lo mismo para el directorio fechado de cada corrida, que guarda volcados
de bases de datos completos y en claro.

## 12. La propiedad de los archivos no se reporta

Se hace bien —el `chown` final deja `<cuenta>:www-data`—, pero durante la copia los archivos
aparecen con el propietario equivocado por el `--numeric-ids` del `rsync`, y al terminar no se
dice nada. Da un susto innecesario y, sobre todo, un fallo ahí pasaría desapercibido.

**Propuesta**: comprobar y reportar la propiedad al cerrar cada dominio.

---

## Lo que esta herramienta hace bien y conviene copiar

Esto mira hacia `backupctl`, no hacia ella.

- **El plan se lee antes de confirmar.** Imprime todo lo que va a hacer, dominio por dominio,
  con sus parámetros resueltos, y termina en `NADA DE LO ANTERIOR DESTRUYE DATOS` antes de
  pedir una confirmación escrita. Es exactamente lo que este proyecto llama «informe de lo
  hecho», pero por delante.
- **Un solo archivo que se sube y se ejecuta.** Sin dependencias en el destino, sin instalar
  nada, sin repositorio clonado. Para un servidor ajeno o recién creado vale oro.
- **La descripción de la migración es declarativa y se versiona aparte.** Lo que se edita es un
  archivo de datos legible, no la herramienta. Los comentarios de ese archivo acabaron
  documentando las trampas de la migración concreta, que es justo donde hacían falta.
- **Fases con nombre, repetibles e idempotentes en lo posible**: `plan`, `1`, `sincronizar`,
  `2`, `verificar`. Que `verificar` sea de solo lectura y se pueda repetir cuantas veces se
  quiera es un acierto.
- **Un directorio fechado por corrida** con logs, volcados y copias de seguridad.
- **Comparar recuentos de tablas entre origen y destino.** Es la única parte que demuestra algo
  en vez de afirmarlo.

---

## La pregunta de producto que esto deja abierta

`backupctl migrate` migra **bases de datos** entre servidores, con volcado portable y
comparación de recuentos. Lo hace bien y no pretende otra cosa.

Lo que esta migración necesitaba era **cuenta completa**: crear la cuenta, sus dominios con su
versión de PHP, copiar los archivos, recrear buzones con contraseñas y reenvíos, migrar
cronjobs, emitir certificados y coordinar el corte de DNS. Eso hoy no está.

No es una propuesta: es la pregunta para el Product Owner. Si la respuesta es que sí, es una
fase propia, con su ADR, y con un servidor de pruebas donde ejecutarla de verdad antes de que
vuelva a hacer falta con el reloj en contra. Lo que **no** debe repetirse es lo de esta
migración: estrenar un camino nunca ejecutado contra un servidor real sobre el único servidor
que quedaba vivo.
