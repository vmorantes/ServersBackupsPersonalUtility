# Migración caliente de cuentas completas

Hay dos formas de llevar lo que vive en un HestiaCP a otro:

| | Vía larga: respaldos | Vía rápida: migración caliente |
|---|---|---|
| Herramienta | `backupctl` | `tools/migracion-caliente/` |
| Qué mueve | Bases de datos (y respaldos de cuenta con Restic) | La cuenta entera: dominios con su PHP, archivos, bases, correo, cronjobs, certificados |
| De dónde a dónde | Del servidor a un respaldo, y del respaldo a donde haga falta | De un servidor vivo a otro servidor vivo, sin respaldo de por medio |
| Para qué | Tener copias en el tiempo | Cambiar de servidor |

Esta página es la vía rápida.

!!! danger "Lo que nunca se ha ejecutado contra un servidor real"
    La herramienta de migración ya migró cuentas reales entre dos HestiaCP 1.10.5.
    Lo que se le ha añadido después **solo se ha probado con datos inventados**:

    - el **analizador** (paso 1);
    - el tipo de aplicación **`codeigniter3`**;
    - el arreglo de `plan` y `verificar` que antes daban por existentes dominios
      que no existían.

    La primera vez que corran en un servidor será en el tuyo. Lee lo que digan
    antes de seguir, y si algo no cuadra, para.

## Qué se migra y qué no

| | ¿Se migra? | Detalle |
|---|---|---|
| Web | Sí | Dominios, alias, versión de PHP, archivos, y la configuración de la aplicación reescrita. El alias `www` se puede quitar con `alias_www` (en subdominios, por defecto) |
| Certificados | No se copian | Se emiten nuevos en la fase 2, cuando el DNS ya apunta al servidor nuevo |
| Bases de datos | Sí | Con contraseña nueva, y comparando el número de tablas entre origen y destino |
| Correo | Sí | Cuentas, contraseñas sin cambiarlas, alias, reenvíos, cuotas y buzones enteros. **La clave DKIM es nueva**: hay que publicarla en el DNS |
| Cron | Sí, salvo dos casos | Los suspendidos en el origen no se migran; los puestos a mano con `crontab -e` no los ve |
| Cuentas FTP | **No** | Solo se informan |
| **Zonas DNS** | **No** | Ni una zona ni un registro. Ver abajo |

La herramienta **no cambia nada tuyo en el servidor viejo**: solo lee de él. Lo que haya
que cambiar allí lo haces tú. La única excepción: si el acceso a MySQL del origen va con
usuario y contraseña (`MYSQL_ORIGEN_AUTH="user"`; por defecto es `socket`), deja en su
`/tmp` un archivo temporal con esa contraseña mientras trabaja, y lo borra al salir. Si la
conexión se corta de golpe, puede quedarse allí: búscalo y bórralo.

!!! danger "El DNS no se migra"
    La herramienta no copia ningún registro DNS. Pero al crear cada dominio en el
    servidor nuevo, HestiaCP **sí le crea una zona**, desde la plantilla DNS del paquete
    de la cuenta. Con la plantilla `default` trae sus propios `@ A`, `www`, `mail`,
    `@ MX 0 mail.<dominio>`, un SPF, `_dmarc` y registros de correo. **No es tu zona.**

    Si el servidor viejo **sirve** el DNS de tus dominios, antes de cambiar los NS hacia
    el nuevo cada zona tiene que estar en el nuevo **como en el viejo**, con la IP nueva.

    **No añadas tus registros encima de esa zona.** HestiaCP no detecta duplicados: te
    quedarían dos `@ A`, dos SPF y **dos MX**, y el correo se repartiría entre los dos
    destinos. Hay que **reemplazar** los registros de la zona por los tuyos, no sumarlos.
    El informe del analizador te dice qué cuentas tienen zonas y cuántos registros tiene
    cada una.

!!! danger "Dominios con el correo fuera (por ejemplo, Microsoft 365)"
    La migración les crea igualmente un dominio de correo local en el servidor nuevo
    (`eliminar_mail` vale `false` por defecto). Con ese dominio de correo, el servidor
    trata el dominio como **local**: el correo que él mismo envíe a ese dominio
    (formularios, avisos de la aplicación, cron) **no se manda al MX, y no llega a
    Microsoft 365**. Comprobado en la configuración de correo de HestiaCP 1.10.5.

    Para esos dominios, en la propuesta: `eliminar_mail="true"` y `correo="false"`.

## Antes de empezar

- El servidor de **destino** con HestiaCP instalado, idealmente en la misma
  versión que el origen.
- Acceso como `root` por SSH a los dos, desde tu equipo.
- Que el **destino pueda entrar por SSH al origen**: la herramienta se ejecuta en
  el destino y desde ahí lee y copia del origen.
- Tu equipo con este repositorio actualizado.
- **Empieza por la cuenta más pequeña.** Valida el procedimiento entero antes de
  tocar las grandes.

## 1. Analizar el origen

El analizador lee el servidor de origen y te propone un archivo de migración por
cuenta. **No escribe nada en el servidor** salvo su propio informe en un
directorio de `/tmp`, **no ejecuta ninguna orden del panel** y **no imprime
ninguna contraseña**.

En tu equipo, **justo antes de subirlo** (el paquete no se actualiza solo):

```bash
bash tools/migracion-caliente/construir-analizador.sh
```

Súbelo al **origen** y ejecútalo. La primera vez, con `--rapido`: no mide tamaños
ni cuenta mensajes, que en un servidor grande puede tardar mucho.

```bash
cd tools/migracion-caliente
scp analizar.paquete.sh root@203.0.113.10:/root/
ssh root@203.0.113.10 'bash /root/analizar.paquete.sh --rapido'
```

Al terminar te dice dónde dejó el resultado:

```
/tmp/analisis-hestia.XXXXXX/
├── informe.txt              el inventario, con los AVISOS arriba
└── migracion-<cuenta>.sh    una propuesta por cuenta
```

Tráetelo a tu equipo y **borra ese directorio del servidor**: las propuestas
llevan contraseñas nuevas para las bases del destino.

```bash
scp -r root@203.0.113.10:/tmp/analisis-hestia.XXXXXX ./analisis
ssh root@203.0.113.10 'rm -r /tmp/analisis-hestia.XXXXXX /root/analizar.paquete.sh'
```

!!! warning "El informe lleva nombres reales"
    Cuentas, dominios y rutas de tu servidor. No es un secreto, pero no lo pegues
    en ningún sitio público.

Si quieres los tamaños y el número de mensajes por buzón, repítelo sin
`--rapido` cuando ya hayas leído el primer informe.

## 2. Revisar cada propuesta

Copia la propuesta de cada cuenta a `tools/migracion-caliente/` (git ignora los
`migracion-*.sh`, salvo el ejemplo) y revísala. Hay dos huecos que **tienes que**
rellenar tú:

- **`IP_DESTINO`**: la IP del servidor nuevo.
- **`php=""`** en los dominios cuyo PHP en el origen era `default`: desde los
  archivos no se puede saber qué versión es. Mírala en el panel del origen y
  escribe la plantilla exacta (`PHP-7_4`, `PHP-8_1`…). Nunca `default`: no es la
  misma versión en los dos servidores.

Si se te olvida alguno, la herramienta se niega al lanzar `plan`, antes de tocar
nada, y dice cuál falta. Pero **lee el plan entero de todos modos**: es la última
vez que ves todo lo que va a hacer antes de que lo haga.

Y busca cada `REVISAR:`. Los que más importan:

| Aviso | Qué hacer |
|---|---|
| Aplicación «no se pudo determinar» | Va como `tipo="ninguno"`: la base se migra, pero **la configuración no se reescribe**. Las credenciales nuevas se escriben a mano tras la fase 1 |
| CodeIgniter con directorio de entorno | El analizador apunta `ruta_db` al `database.php` del entorno activo (por ejemplo `public_html/application/config/production/database.php`; la ruta es relativa a la carpeta del dominio), que es el que manda. Compruébalo |
| `active_group` distinto de `default`, o una clave repetida en `database.php` | La herramienta se negará con ese proyecto. Corrige el archivo en el origen o trátalo a mano |
| Cron **suspendido** en el origen | Alguien lo apagó a propósito. La herramienta **no lo migra**. El plan no lo dice: lo ves marcado en el informe del analizador, y la fase 1 lo anuncia al llegar a él («NO MIGRADO (estaba suspendido en el origen)») y lo deja anotado para recrearlo. Recréalo a mano solo si de verdad hace falta |
| Cron que llama a `php` sin ruta | En el servidor nuevo puede ser otra versión. Pon la ruta absoluta |
| Cron puesto a mano (`crontab -e`) | La migración no lo lleva. Recréalo tú |
| Base que ninguna aplicación usa | Va como base suelta. Decide si hace falta |
| La cuenta tiene zonas DNS | Si el servidor viejo **sirve** el DNS, apagarlo deja los dominios sin responder |

En los dominios, **`forzar_ssl` va siempre en `"false"`**. Forzar HTTPS no
comprueba que el certificado exista, y un dominio redirigido a un HTTPS sin
certificado deja de responder. Se fuerza a mano después (paso 5). Ojo: cualquier
valor que no sea exactamente `"true"` cuenta como falso, sin error.

## 3. Construir el paquete

```bash
cd tools/migracion-caliente
./construir.sh migracion-cuenta.sh
```

Genera `migracion-cuenta.paquete.sh`: un solo archivo con la herramienta y tu
configuración dentro. **Lleva las contraseñas de las bases en claro.** Se sube al
servidor de **destino**:

```bash
scp migracion-cuenta.paquete.sh root@203.0.113.20:/tmp/
```

## 4. Las fases, en este orden

Todas se ejecutan **en el destino**:

```bash
bash /tmp/migracion-cuenta.paquete.sh plan
bash /tmp/migracion-cuenta.paquete.sh 1
bash /tmp/migracion-cuenta.paquete.sh sincronizar
#  ─── aquí apuntas el DNS al servidor nuevo ───
bash /tmp/migracion-cuenta.paquete.sh 2
bash /tmp/migracion-cuenta.paquete.sh verificar
```

`plan`
:   No toca nada. Lee todo lo que va a hacer, dominio por dominio, antes de
    seguir.

`1`
:   Antes de mover el DNS. Crea dominios, bases de datos, PHP, alias, DNS y
    correo; copia los archivos, importa las bases y reescribe la configuración de
    cada aplicación. Al terminar, el sitio nuevo está completo, pero nadie lo
    visita todavía.

`sincronizar`
:   Vuelve a copiar lo que haya cambiado en el origen desde la fase 1. **Deja el
    destino idéntico al origen: borra en el nuevo lo que no exista en el viejo.**
    Se puede repetir cuantas veces quieras **hasta apuntar el DNS. Nunca
    después**: pisaría con datos viejos lo que los visitantes ya hayan escrito en
    el servidor nuevo.

`2`
:   Después de mover el DNS: emite los certificados, que no pueden emitirse
    mientras el dominio resuelva al servidor viejo. **No vuelve a copiar
    archivos**: eso está desactivado a propósito. No actives
    `SINCRONIZAR_EN_FASE2`: borraría lo escrito en el servidor nuevo desde el
    corte.

`verificar`
:   Solo lee. Comprueba que cada aplicación tenga sus credenciales y que conecte.
    Se puede lanzar cuando quieras, antes o después.

!!! warning "Las dos formas de equivocarse con `sincronizar`"
    - **Saltárselo** pierde, sin un solo aviso, todo lo escrito en el servidor
      viejo entre la fase 1 y el corte de DNS.
    - **Lanzarlo después del corte** pisa lo nuevo con lo viejo.

!!! warning "Los cronjobs migrados quedan activos desde la fase 1"
    Mientras el DNS siga apuntando al servidor viejo, se ejecutan **en los dos**,
    cada uno contra su propia base. Para la mayoría de sitios es inocuo. Para uno
    que envía correo, factura o llama a una API, no: en el modo `preguntar`,
    contesta que no a esos y recréalos después del corte. Y desactívalos en el
    servidor viejo.

## 5. Comprobar por fuera

No te fíes solo de lo que diga la herramienta. Comprueba con algo que no sea ella:

**Certificados**, desde tu equipo, dominio por dominio:

```bash
openssl s_client -connect example.org:443 -servername example.org </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer -enddate
```

Solo cuando el emisor y la fecha sean los correctos, fuerza HTTPS en el panel.

**DNS**, contra un resolutor público, no el del servidor (el del servidor puede
tener cacheada la IP vieja durante horas):

```bash
dig +short example.org @1.1.1.1
dig +short example.org @8.8.8.8
```

**Correo**, el número de mensajes de un buzón en los dos servidores (los buzones
viven en `/home/<cuenta>/mail/<dominio>/<buzón>/`, en formato Maildir):

```bash
find /home/cuenta/mail/example.org/info -type f \( -path '*/cur/*' -o -path '*/new/*' \) | wc -l
```

**Los sitios**, abriéndolos: la portada y una página que lea la base de datos.

## 6. Limpiar

En el **destino**, el paquete lleva contraseñas:

```bash
rm /tmp/migracion-cuenta.paquete.sh
```

La herramienta deja en el destino un directorio por corrida:

```
/home/<cuenta>/migraciones/<AAAAMMDD_HHMMSS>/
/home/<cuenta>/migraciones/ultima   → la última corrida
```

Ahí están los volcados de las bases **en claro**, y también **`deshacer.sh`, la
marcha atrás** de lo que esa corrida creó. La herramienta te imprime la ruta al
empezar cada fase que escribe (`1`, `sincronizar` y `2`), y la fase 1 la repite al
terminar.

**No lo borres hasta haber descartado la marcha atrás**: con todo comprobado y
unos días sin sorpresas. Entonces sí, porque lleva las bases en claro:

```bash
rm -r /home/cuenta/migraciones
```

Y no apagues el servidor viejo hasta que hayan pasado unos días sin sorpresas.

## Lo que esta herramienta aún no hace bien

Está apuntado en el repositorio, con lo aprendido en la migración del
2026-10-02. Lo que más importa al usarla:

- La emisión de certificados no comprueba su resultado: compruébalo tú (paso 5).
- La comprobación de DNS usa el resolutor del servidor de destino, que puede
  tener cacheada la IP vieja: si se salta certificados diciendo que el dominio
  «aún no resuelve aquí», compruébalo contra `1.1.1.1` antes de creerla.
- Los alias de correo y los reenvíos se dan por buenos sin releerlos del destino.
- El tipo `piecesphp` **no sirve para CodeIgniter 3**: usa `codeigniter3`.
