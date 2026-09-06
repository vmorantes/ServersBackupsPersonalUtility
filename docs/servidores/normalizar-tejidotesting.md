# Normalizar TejidoTesting

Pasar este servidor del sistema antiguo —scripts sueltos— al blindaje completo,
**sin tocar el terminal** y sin apagar nada de lo que ya funciona.

```bash
backupctl web --open
```

Y clic en la tarjeta **TejidoTesting**. Todo lo demás es en el navegador.

!!! success "Los scripts antiguos no se tocan"
    `RunBackupDB.sh` y compañía siguen en el servidor y siguen ejecutándose.
    Los dos sistemas conviven hasta que tú decidas retirar el viejo, en el
    último paso.

---

## Punto de partida

Lo que este servidor ya tiene, comprobado:

| | Estado |
|---|---|
| Acceso SSH | `root@vps-ef720100.vps.ovh.ca` |
| Usuario de MySQL | `admin_general` |
| Usuarios de HestiaCP | `admin`, `naturalsurf`, `testing-admin` |
| Restic | ✅ configurado contra Mega S4 |
| Retención Restic | 30 instantáneas · 8 diarias · 5 semanales · 3 mensuales · anuales ilimitadas |
| Claves Restic | ✅ rescatadas |
| **`rclone.conf`** | ❌ **sin rescatar** |
| **Avisos** | ❌ **sin configurar** |
| **backupctl en el servidor** | ❌ **sin instalar** |

Cinco de las ocho piezas están. Faltan tres.

!!! danger "La más grave es el `rclone.conf`"
    Tienes las claves que **descifran** el repositorio, pero no la configuración
    que permite **llegar** a él. Si pierdes el servidor hoy, tendrías que
    reconstruir el acceso a Mega S4 desde cero. Se resuelve en el paso 5.

---

## 1 · Dar acceso al servidor

Pestaña **Servidor** → **Configurar acceso por clave**.

| Campo | Valor |
|---|---|
| Usuario | `root` |
| Servidor | `vps-ef720100.vps.ovh.ca` |
| Contraseña | La de root de tu VPS |

Instala tu clave pública usando la contraseña **una sola vez**. A partir de ahí
no se vuelve a pedir en ningún sitio.

Después, **Actualizar estado** arriba. La cabecera debe pasar a verde y aparecer
el plan de lo que falta.

??? question "¿Por qué root y no admin?"
    En HestiaCP los usuarios del panel tienen la shell en `nologin`: no pueden
    abrir consola. Además las órdenes `v-*` exigen privilegios. `USER_NAME`
    sigue siendo `admin` —de quién son los respaldos—, y no necesita consola.

---

## 2 · Mirar antes de tocar

Pestaña **Blindaje**. Nada de esto escribe.

1. **Informe de blindaje** — qué falta, en orden
2. **Usuarios del panel** — tus tres usuarios, y si cada uno tiene ya su clave
3. **Cobertura de las bases de datos** — **la importante**

??? info "Qué esperar de la cobertura"
    Cruza tus ~76 bases de datos en tres columnas: si HestiaCP las conoce, si
    están en el último respaldo, y qué situación tienen.

    Presta atención a las marcadas **«solo backupctl»**: se crearon a mano en
    MySQL, HestiaCP no las conoce, y por tanto **no viajan dentro de sus
    respaldos ni se recrean al restaurar una cuenta**. Si algún día migras este
    servidor, hay que darlas de alta en el destino.

---

## 3 · Instalar la herramienta

Pestaña **Servidor**:

1. **Ensayo: qué copiaría** — no copia nada. Comprueba dependencias y avisa si
   falta `zip` o `rsync`, ofreciéndose a instalarlos.
2. **Instalar en el servidor**

Copia `bin/`, `lib/` y el `env.sh`. Los respaldos y registros que ya haya allí
no se tocan.

---

## 4 · Comprobar que respalda de verdad

Pestaña **Respaldar**:

1. **Respaldar en el servidor** — el primero, a mano. Verás las 76 bases pasar
   una a una.

Pestaña **Verificar**:

2. **Verificar en el servidor**
3. **Probar restauración** con una base cualquiera (`encausa`, por ejemplo) y
   **Incluir los datos** marcado.

!!! danger "No sigas si el paso 3 falla"
    Los dos primeros comprueban que el archivo existe y está íntegro. El tercero
    es el único que comprueba que **sirve para restaurar**. Crea una base
    desechable, restaura dentro y la elimina: tu producción no se toca.

---

## 5 · Rescatar lo que falta

Pestaña **HestiaCP** → **Traer las claves del servidor**.

Trae los `restic.conf` de tus tres usuarios **y el `rclone.conf`**, que es el que
te falta.

!!! warning "La clave es de cada usuario"
    El repositorio y la retención son globales, pero **cada usuario tiene su
    propia clave de cifrado**. Con la de `admin` no se abren los respaldos de
    `naturalsurf`. Este botón las coge todas.

Comprueba con **¿Dónde están mis claves?**: deben aparecer los dos archivos.

Y luego **cópialos fuera de este repositorio** — a un gestor de contraseñas o a
otra máquina. Si solo están aquí, se pierden con tu equipo.

---

## 6 · Avisos

Ahora mismo un fallo no avisaría a nadie.

1. Crea un check gratuito en [healthchecks.io](https://healthchecks.io)
2. Pestaña **Configuración** → **Cargar para editar** → pon la URL en
   `HEALTHCHECK_URL` → **Guardar**
3. Pestaña **Servidor** → **Instalar en el servidor**, para subir el cambio
4. Pestaña **Programación** → **Probar los avisos**

!!! tip "Por qué un healthcheck y no un correo"
    Es el único que detecta que el cron **dejó de ejecutarse**. Si el respaldo
    nunca arranca, no hay nada que envíe un correo.

---

## 7 · Programar

Pestaña **Programación**:

1. **Ver la del servidor** — verás la línea antigua de `RunBackupDB.sh`
2. **Programar en el servidor**

Quedan los dos crones conviviendo, que es lo que queremos por ahora.

??? warning "La línea antigua tiene un fallo"
    Lleva un `%` sin escapar. En crontab eso se convierte en salto de línea y
    parte la orden. Da igual: la vas a retirar en el paso 9.

---

## 8 · Confirmar

Pestaña **Servidor** → **Traer el estado al repositorio**. Escribe `ESTADO.md`
con lo que hay realmente allí.

Pestaña **Blindaje** → **Informe de blindaje**. Debe salir **sin ✗**.

Y en tu equipo:

```bash
git add TejidoTesting/ && git commit -m "TejidoTesting: normalizado"
```

---

## 9 · Retirar el sistema antiguo

**Espera una semana.** Que el nuevo respalde solo, sin errores, y que
**Informe de blindaje** siga limpio.

Cuando te fíes, pestaña **Programación** → **Ver la del servidor**, localiza la
entrada antigua y quítala **desde el panel de HestiaCP** (sección Cron), no con
`crontab -e`: en HestiaCP el crontab es un archivo generado y una edición a mano
desaparece en la siguiente reconstrucción.

Los scripts viejos pueden quedarse donde están; ya no los ejecuta nadie.

---

## Lista de comprobación

- [ ] Acceso por clave instalado, cabecera en verde
- [ ] Revisada la cobertura de las bases de datos
- [ ] backupctl instalado en el servidor
- [ ] Primer respaldo hecho en el servidor
- [ ] **Prueba de restauración con datos superada**
- [ ] Claves traídas, incluido el `rclone.conf`
- [ ] **Claves copiadas fuera de este repositorio**
- [ ] `HEALTHCHECK_URL` configurado y probado
- [ ] Cron nuevo programado
- [ ] `ESTADO.md` actualizado y cometido
- [ ] *(una semana después)* cron antiguo retirado

---

## Después

| Cada | Qué | Dónde |
|---|---|---|
| Semana | Informe de blindaje | Blindaje |
| Mes | Prueba de restauración con datos | Verificar |
| Trimestre | Que las claves sigan fuera del servidor | — |
| Año | Restaurar un usuario completo desde Restic en una máquina desechable | — |
