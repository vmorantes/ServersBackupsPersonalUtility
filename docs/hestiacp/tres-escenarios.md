# Migrar, independizar y blindar

Tres situaciones distintas que se confunden con facilidad:

| Situación | Qué quieres | Sección |
|---|---|---|
| El servidor **A** desaparece o se jubila | Que sus cuentas vivan en **B** | [1 · Migrar A → B](#1-migrar-a-b) |
| **B** ya tiene las cuentas | Que B se respalde **por su cuenta**, en otro bucket | [2 · B con su propio incremental](#2-b-con-su-propio-incremental-en-otro-bucket) |
| Un servidor **X** que no tiene nada que ver | Blindarlo desde cero, sin migrar nada | [3 · Blindar un servidor independiente](#3-blindar-un-servidor-independiente-x) |

Todo se hace desde la interfaz. Cada botón dice antes si **no toca**, **escribe**
o **destruye**, y cada pestaña enseña primero lo que ya hay configurado.

---

## Antes de nada

**En el destino tiene que haber HestiaCP instalado** y acceso como `root` por SSH.

**El bucket tiene que existir.** Créalo en el panel de tu proveedor S3. Comprobado:

| Destino | Resultado |
|---|---|
| Ruta nueva y vacía dentro de un bucket que existe | Se acepta |
| Bucket que no existe | HestiaCP lo rechaza («directory not found») |

Las carpetas de dentro no hay que crearlas: HestiaCP crea el repositorio de cada
cuenta la primera vez que la respalda.

**Las claves S3.** Tenlas a mano. Un par de claves normal abre **todos** los
buckets de la cuenta: quien entre en un servidor que las tenga puede leer y
borrar los respaldos de los demás. Si tu proveedor permite claves limitadas a un
bucket, usa una por servidor.

---

## ¿Es inocuo?

| Dónde | Qué pasa |
|---|---|
| **Servidor de origen (A)** | Nada. Ninguna orden de migración se conecta a A: se lee del almacenamiento y del zip de este equipo |
| **Almacenamiento** | Solo se lee. Restic deja bloqueos de lectura mientras trabaja y los retira al terminar |
| **Destino (B), cuenta nueva** | Se crean la cuenta, sus dominios, bases y archivos. **Se detiene antes de escribir nada** si la cuenta ya existe o si **cualquiera de sus dominios** existe ya en otra cuenta. Una base con el mismo nombre o el mismo usuario MySQL se salta y se avisa |
| **Destino (B), resto de cuentas** | No se tocan |

La **configuración de respaldo** del destino se apunta temporalmente al
almacenamiento de A durante la migración, y se devuelve a como estaba al terminar,
pase lo que pase.

---

## 1 · Migrar A → B

Partes de dos archivos rescatados de A: el `rclone.conf`, que dice cómo **llegar**
al almacenamiento, y las claves Restic, que dicen cómo **descifrarlo**. A puede
estar ya apagado.

### 1.1 · Preparar B

1. **+ Añadir servidor** → rellena solo el nombre del perfil, el servidor y el
   usuario SSH (`root`). Crea el perfil.
2. En su tarjeta, **Servidor → Configurar acceso por clave**. Pide la contraseña
   de root una vez.

### 1.2 · Mirar antes de tocar

Elige el perfil de **A** y ve a **Resucitar**. Nada de esto escribe.

1. **¿Qué se puede resucitar?** Cada cuenta debe decir «descifra: sí». Si alguna
   no abre, te enteras ahora y no a mitad de la migración.
2. **Ver el historial de instantáneas**, cuenta por cuenta.

!!! danger "La instantánea más reciente no siempre es la buena"
    Si se borró algo en A antes de su último respaldo, la instantánea más
    reciente es la de **A ya vaciado**. El historial lo detecta y te dice cuál es
    la más completa. Usa esa, con su identificador, en vez de `latest`.

### 1.3 · Resucitar las cuentas

Sección **Con otro nombre**. En «Nombre nuevo» pon **el mismo nombre** si en B
está libre, u otro si choca con una cuenta que ya existe allí.

1. **Ensayo: traer con otro nombre**: comprueba B, avisa si la instantánea está
   menguada y enumera los pasos.
2. **Traer con otro nombre**.
3. **Apunta la contraseña de panel** que te da al final. No se guarda en ningún
   sitio.

Empieza por la cuenta más pequeña. Deja la más grande para cuando hayas visto
salir bien una.

Qué conserva y qué no:

| Cosa | Se conserva |
|---|---|
| Nombre de la cuenta | El que elijas |
| Dominios | Sí, tal cual. **Nunca se renombran**: son nombres DNS |
| Nombre, usuario y contraseña de cada base | **Sí**. Las aplicaciones conectan sin tocar su configuración |
| Archivos, DNS, crones | Sí |
| Buzones y contraseñas de correo | Sí. El archivo de contraseñas lo regenera HestiaCP a partir de la configuración de la cuenta, que viaja en el respaldo |
| Claves DKIM del correo | Sí. Si cambiaran, la firma dejaría de coincidir con el DKIM publicado en el DNS |
| IP de los dominios | **Se sustituye** por la de B: en web, DNS, registros A y dentro del SPF (`ip4:`). La del servidor viejo no existe allí |
| Dominios que el respaldo no traía | Se reconstruyen desde sus carpetas, y se avisa |

Lo que la detiene antes de escribir nada: que la cuenta ya exista en B, o que
**alguno de sus dominios** ya exista en otra cuenta de B. El ensayo te lo dice.

### 1.4 · Las bases que HestiaCP no conocía

Las bases creadas a mano en MySQL no están en ninguna instantánea de HestiaCP.
Solo están en el zip de backupctl. Hazlo **después** del paso 1.3:

1. **Ensayo: qué bases llevaría**: lista las que B no tiene todavía. Las que ya
   existan allí se saltan, nunca se pisan.

    Las bases de **configuración del servidor** —`information_schema`, `mysql`,
    `sys`, `performance_schema`, `phpmyadmin`, `roundcube`— no se migran nunca,
    ni pidiéndolas por nombre: mueren con su servidor, y el destino tiene las
    suyas.
2. **Llevar las bases al destino**.
3. **Ensayo: cuáles registraría** → **Registrarlas en el panel**, bajo la cuenta
   que prefieras. Si no, llegan pero siguen invisibles en el panel.

### 1.5 · Poner B en servicio

1. En quien sirva tus DNS, cambia a la IP de B los registros **A**, **MX** y el
   **SPF** (`v=spf1 ip4:…`). Si tus dominios usan los DNS del proveedor y no los
   de HestiaCP, la herramienta no puede hacerlo por ti: las zonas que restaura
   en B ya van con la IP nueva, pero no son las que responden en Internet.
2. Cuando apunten a B, activa **SSL** en cada dominio desde el panel. Antes no se
   puede emitir.
3. Abre los sitios y comprueba que cargan con sus datos.

### 1.6 · Qué hacer con A

!!! warning "Mientras A siga encendido, su retención borra las copias buenas"
    Tras cada respaldo, HestiaCP ejecuta
    `restic forget --keep-last N --keep-daily … --prune`. Si A ya está vacío,
    cada noche añade una instantánea vacía y expulsa una anterior. Las cuentas
    que ya no existen en A no se tocan: el cron solo recorre las que existen.

Apaga A, o desactiva su cron de Restic, en cuanto termines. Sus copias siguen en
el almacenamiento.

### Lo que todavía no está probado

Probado de punta a punta con una cuenta pequeña: web, DNS y base con su
contraseña original. **Sin probar todavía**: buzones de correo y DKIM,
certificados SSL, alias web, cuentas de varios GB y **la sustitución de IP** (en
el banco de pruebas origen y destino eran la misma máquina). Revísalos en el
panel después de cada cuenta.

---

## 2 · B con su propio incremental en otro bucket

!!! danger "Nunca en la misma ruta que A"
    Si A y B escriben en los mismos repositorios, la retención de uno borra las
    instantáneas del otro, y dos cuentas con el mismo nombre acaban compartiendo
    repositorio. Otro bucket, o como mínimo otra ruta.

    La herramienta **se niega** a registrar una ruta que ya contiene
    repositorios que el servidor no tiene registrados. Solo lo permite a
    propósito, desde la línea de órdenes, con `--ruta-compartida`.

Con el perfil de **B** seleccionado, pestaña **HestiaCP**. Lee primero las franjas
de estado: dicen qué hay ya configurado.

1. Crea el bucket en el panel de tu proveedor.
2. **Configurar el remoto**: nombre, claves y endpoint. Si falta `rclone` en B, se
   ofrece a instalarlo. Si ya hay un remoto con ese nombre, la franja lo dice y
   el aviso enseña qué se sustituye.
3. **Registrar en HestiaCP** con el repositorio
   `rclone:<remoto>:<bucket-de-B>/hestiacp/`.
   El primer número de la retención es el **total de instantáneas**, no días.
4. **Activar su cron**. HestiaCP no lo hace solo, y si ya existe no añade otro.
5. **Traer las claves del servidor**. Cópialas también a un gestor de contraseñas.
6. Pestaña **Programación** → **Programar en el servidor** (el volcado diario de
   todas las bases, incluidas las que HestiaCP no conoce) y **Probar los avisos**.
7. Al día siguiente, **Blindaje → Informe de blindaje** debe salir en verde.

La configuración de respaldo de HestiaCP es **una sola para todo el servidor**.
Registrarla sustituye la anterior para todas las cuentas: por eso el aviso de
confirmación enseña el repositorio que se pisaría.

---

## 3 · Blindar un servidor independiente X

Mismo resultado que el escenario 2, empezando desde cero.

1. **+ Añadir servidor**. La primera vez, rellena solo el perfil, el servidor y el
   usuario SSH, y crea.
2. **Servidor → Configurar acceso por clave**.
3. **Servidor → Ensayo: qué copiaría** → **Instalar en el servidor**.
4. Sigue los pasos 2 a 7 del [escenario 2](#2-b-con-su-propio-incremental-en-otro-bucket),
   con un bucket o una ruta **propios de X**.

Si X ya tenía acceso por clave, puedes rellenar el alta entera de una vez. Al
pulsar **Crear** se crea el usuario MySQL (si lo marcas) y se instala en el
servidor. También se configuran el remoto y el host, se activa el cron de Restic
y se rescatan las claves. Lo único que queda aparte es **Programación →
Programar en el servidor**.

!!! note "Si X ya tenía Restic configurado a mano"
    No lo registres de nuevo: la pestaña HestiaCP te enseña el repositorio y la
    retención actuales. Sigue [Normalizar uno que ya existe](../paso-a-paso/normalizar-existente.md).

---

## Comprobar que quedó bien

| Dónde | Qué debe decir |
|---|---|
| Blindaje → Informe de blindaje | Todo en verde |
| HestiaCP, sección 2 | El repositorio que registraste y «El cron ya está activo» |
| HestiaCP, sección 3 | Las claves rescatadas en este equipo |
| Programación | Respaldo de bases programado, Restic programado, al menos un canal de aviso |
| Respaldar | Un respaldo de hoy o de ayer |
