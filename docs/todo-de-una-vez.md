# Hacerlo todo desde la interfaz

**Una sola página, de cero a blindado, sin tocar el terminal** salvo la primera
línea.

```bash
backupctl web --open
```

Se abre el navegador en `http://127.0.0.1:8787`. Todo lo demás se hace ahí.

!!! info "Por qué existe también una CLI"
    La línea de órdenes está para **los servidores**: el cron la usa cada noche
    y no hay nadie mirando. Para ti está esta interfaz. Cualquier cosa que se
    pueda hacer con una, se puede hacer con la otra.

---

## Antes de empezar

Solo dos cosas, y las dos en el servidor:

1. **Un usuario que pueda entrar por SSH.** Vale con contraseña: la interfaz te
   la pedirá una vez y dejará instalada tu clave.
2. **Un usuario de MySQL**, o su credencial de administrador para que la
   interfaz cree uno.

**No hace falta** nada más: ni crear directorios, ni instalar paquetes, ni
configurar rclone a mano. De eso se encarga la herramienta.

---

## 1 · Añadir el servidor

Botón **+ Añadir servidor**, arriba del panel.

| Campo | Qué poner |
|---|---|
| Nombre del perfil | `MiVPS` |
| Servidor | El nombre o la IP que te da tu proveedor. En OVH, algo como `vps-xxxxxxx.vps.ovh.net` |
| Usuario SSH | `admin` — necesita shell |
| Usuario propietario | Vacío = el mismo |
| Ruta en el servidor | Vacío = `/home/admin/scripts` |
| URL de healthcheck | Opcional, pero ponla |

Para MySQL, dos caminos:

- **«Ya tengo un usuario»** → sus credenciales, que se comprueban antes de guardar.
- **«Créalo tú»** → una credencial de **administrador** de MySQL. Se usa una vez
  para crear el usuario de respaldo y **se descarta**: no se guarda en ningún
  archivo y el formulario la borra al enviar.

Deja marcado **«Desplegar al terminar»**. Verás en vivo cómo conecta, comprueba
dependencias, crea el usuario, escribe la configuración y copia la herramienta.

---

## 2 · Estado

Al abrir el perfil, la cabecera te dice en qué punto estás:

```
✓ Conectado a admin@vps-xxxxxxx.vps.ovh.net
✓ backupctl instalado en /home/admin/scripts
Siguiente paso: Todo listo: puedes operar el servidor desde aquí.
```

Si sale **«Sin acceso por clave»**, aparece el botón **Configurar acceso por
clave**: te pide la contraseña **una vez** y deja el acceso resuelto para
siempre. Si no tienes clave, la genera.

!!! tip "Esa es la única vez que la interfaz pide una contraseña de SSH"
    A partir de ahí no vuelve a pedirla: ni aquí, ni en el cron, ni en nada.

---

## 3 · Las cinco pestañas

| Pestaña | Para qué | ¿Escribe? |
|---|---|---|
| **Estado** | ¿Cómo está todo? Blindaje, diagnóstico, registros, respaldos guardados | No |
| **Desplegar y validar** | Poner el servidor a punto: acceso, herramienta, cron, Restic, claves | Sí |
| **Respaldar** | Correr y comprobar respaldos de bases de datos | Sí |
| **Restaurar** | Recuperar una base de datos | **En la BD** |
| **Migrar** | Trasladar las bases a otra máquina | **En la BD destino** |

Cada acción destructiva pide confirmación explicando qué va a pasar, y las que
tienen ensayo lo ofrecen justo al lado.

---

## 4 · Blindar el servidor

Pestaña **Desplegar y validar**, apartados 3 a 5. Es lo que convierte un
servidor «con respaldos» en un servidor del que **no se pierde nada**.

### 3 · Programación

**Programar en el servidor.** Instala el cron del respaldo de bases de datos.
En HestiaCP lo registra con `v-add-cron-job`, así que aparece en el panel y
sobrevive a sus reconstrucciones.

Después, **Probar los avisos** para confirmar que un fallo te llegaría.

### 4 · Respaldos incrementales de HestiaCP

Aquí se configura Restic, que respalda **la cuenta entera**: archivos web,
correo, DNS y configuración. Es la capa que `backupctl` no cubre.

Rellena el remoto:

| Campo | Para Mega S4 |
|---|---|
| Nombre del remoto | `megas3-vicsen` — el que tú quieras |
| Tipo | S3 |
| Access key ID | Del panel de Mega, sección **S4** |
| Secret access key | Del mismo sitio |
| **Endpoint** | **Obligatorio.** Del panel de Mega |

!!! danger "El endpoint no es opcional"
    Mega S4 es compatible con S3, pero **no es Amazon**. Sin `endpoint`, rclone
    intentaría hablar con AWS. La interfaz se niega a continuar sin él en vez de
    dejarte una configuración que no funciona.

Botón **Configurar el remoto**. Las claves se escriben en el `rclone.conf` del
servidor con permisos `600`; no pasan por la línea de órdenes, así que no son
visibles para otros usuarios de la máquina.

Después, **Registrar en HestiaCP** con el repositorio
(`rclone:megas3-vicsen:mi-servidor/hestiacp/`) y **Activar su cron**.

!!! warning "HestiaCP no activa ese cron por su cuenta"
    Sin él, Restic queda perfectamente configurado y **no se ejecuta nunca**. El
    informe de blindaje lo marca en rojo.

### 5 · Rescatar las claves

Botón **Traer las claves del servidor**. Trae al repositorio los **dos**
archivos sin los cuales tus respaldos son irrecuperables aunque estén intactos.

Y el botón **¿Dónde están mis claves?** te responde con rutas concretas.

---

## 5 · ¿De dónde salen las claves en un servidor nuevo?

La pregunta importa, y tiene dos respuestas según el caso:

=== "Mismo destino S3"

    Si el servidor nuevo va a guardar en el **mismo** Mega S4 que ya usas, no
    hay que teclear nada. Botón **Reusar las claves guardadas**: instala allí el
    `rclone.conf` que ya rescataste antes.

    ```
    Origen: MiVPS/output/HestiaCP/rclone_20260905.conf  (2 días)
    Remotos que contiene:
            megas3-vicsen
    ```

=== "Destino nuevo"

    Si va a otro sitio, las claves salen del **panel de tu proveedor**
    (Mega → sección S4) y se introducen una vez en el formulario.

!!! info "backupctl no inventa credenciales"
    Solo guarda las que rescata del servidor y te las devuelve cuando montas
    otro. Si nunca has hecho **Traer las claves del servidor**, no hay nada que
    reusar.

---

## 6 · Comprobar que funciona

Pestaña **Estado**:

1. **Informe de blindaje** — debe salir sin ✗
2. **Diagnóstico del servidor** — sin fallos

Pestaña **Respaldar**:

3. **Respaldar en el servidor** — el primero, a mano
4. **Probar restauración**, con datos, sobre una base cualquiera

!!! danger "El paso 4 no es opcional"
    Los anteriores comprueban que el archivo existe. Ese es el único que
    comprueba que **sirve para restaurar**. Crea una base desechable, restaura
    dentro y la elimina; tu producción no se toca.

---

## Lista de comprobación

- [ ] Servidor añadido y desplegado
- [ ] Cabecera en verde: conectado y con backupctl instalado
- [ ] Cron del respaldo de bases de datos programado
- [ ] Avisos probados y recibidos
- [ ] Remoto de rclone configurado con su endpoint
- [ ] Host de respaldo Restic registrado y su cron activo
- [ ] Claves traídas al repositorio
- [ ] **Claves copiadas también fuera de este repositorio**
- [ ] Informe de blindaje sin ✗
- [ ] Prueba de restauración superada

---

## Después

| Cada | Qué | Dónde |
|---|---|---|
| Semana | Informe de blindaje | Estado |
| Mes | Prueba de restauración con datos | Respaldar |
| Trimestre | Comprobar que las claves siguen fuera del servidor | — |

Si algo sale mal, **Diagnóstico** y **Registros → Solo errores**, ambos en la
pestaña Estado. Casi todo lo que puede fallar está en
[Cuando algo falla](guias/diagnostico.md).
