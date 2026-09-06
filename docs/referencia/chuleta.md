# Chuleta

Todo en una página. **La primera mitad no toca nada** y puedes ejecutarla entera
en producción sin pensarlo.

---

## :material-shield-check: Seguro — no escribe nada

Ejecuta lo que quieras de aquí. Solo lee.

```bash
backupctl web --open            # panel en el navegador, todos los VPS a la vez
backupctl                       # menú interactivo
backupctl --help                # ayuda, con la leyenda de qué escribe cada orden
backupctl profiles              # servidores que conoce el repositorio
```

### Acceso al servidor

```bash
backupctl -p MiVPS sshkey       # instala tu clave, pide la contraseña una vez
```

### Poder llamarlo sin `./bin/`

```bash
./bin/backupctl install         # enlace en ~/.local/bin, sin sudo
```

### Dar de alta un servidor

```bash
backupctl setup                 # asistente: pregunta todo y despliega
```

### Operar el servidor sin entrar por SSH

```bash
backupctl -p MiVPS remote status
backupctl -p MiVPS remote backup
backupctl -p MiVPS remote verify --restore-test tienda --with-data
backupctl -p MiVPS remote cron --install      # usa sudo solo si hace falta
backupctl -p MiVPS remote logs --errors
```

### ¿Estoy protegido?

```bash
backupctl status                # panel: último respaldo, disco, MySQL, avisos
backupctl doctor                # diagnóstico completo del entorno
```

Ambos devuelven código `!= 0` si algo requiere atención, así que sirven en una
comprobación automática.

### ¿Qué respaldos tengo?

```bash
backupctl list                          # tabla con tamaño, fecha, edad y nº de BD
backupctl list --databases              # qué bases contiene el más reciente
backupctl list --databases <zip>        # las de uno concreto
backupctl inspect                       # metadatos e inventario del más reciente
backupctl inspect <zip>                 # de uno concreto
```

### ¿Sirven?

```bash
backupctl verify --quick                # solo el CRC del zip (segundos)
backupctl verify                        # zip + .gz + sumas SHA-256 + contenido
backupctl verify <zip>                  # uno concreto
```

### ¿Qué pasó?

```bash
backupctl logs --list                   # todos los logs con su nº de errores
backupctl logs --errors                 # solo errores y avisos del último
backupctl logs --full                   # último log completo
backupctl logs --follow                 # seguirlo en vivo
```

### ¿Cómo está configurado?

```bash
backupctl config --show                 # valores efectivos, contraseña oculta
backupctl config --check                # ¿es válida? código 1 si no
backupctl config --path                 # ruta del env.sh
backupctl cron --show                   # programación actual y propuesta
backupctl restic-list                   # repositorios Restic detectados
```

---

## :material-eye-check: Ensayos — enseñan qué harían, sin hacerlo

También seguros. Es la forma de mirar antes de saltar.

```bash
backupctl backup --dry-run                          # qué respaldaría
backupctl restore '' <bd> --dry-run                 # qué restauraría
backupctl restore '' <bd> --into <otra> --dry-run
backupctl retention --dry-run                       # qué BORRARÍA
backupctl restic --dry-run                          # qué claves volcaría
backupctl deploy usuario@servidor --dry-run         # qué copiaría
backupctl pull usuario@servidor --dry-run           # qué diferencias hay
backupctl migrate --to usuario@servidor --dry-run   # qué migraría
```

!!! tip "La regla"
    Si la orden lleva `--dry-run`, úsalo la primera vez. Siempre.

---

## :material-alert: Escriben en disco

```bash
backupctl backup                        # crea un .zip y aplica retención
backupctl backup --only <bd>            # solo una base
backupctl backup --exclude <bd>         # todas menos esa
backupctl backup --no-data              # solo estructura

sudo backupctl restic                   # vuelca las claves Restic (requiere root)

backupctl deploy usuario@servidor       # sube bin/, lib/ y env.sh al servidor
backupctl pull   usuario@servidor       # escribe ESTADO.md; puede tocar env.sh

backupctl config --edit                 # abre env.sh en $EDITOR
backupctl notify-test                   # envía un aviso de prueba
sudo backupctl cron --install           # programa (en HestiaCP, v-add-cron-job)
sudo backupctl cron --remove            # desprograma
```

---

## :material-alert-octagon: Escriben en la base de datos o borran

**Ensáyalas primero.**

```bash
# Restaurar AL LADO (recomendado: no toca la base viva)
backupctl restore '' <bd> --into <bd>_recuperada

# Restaurar ENCIMA (pide confirmación si la base existe)
backupctl restore '' <bd>

# Solo una parte
backupctl restore '' <bd> --segments views
backupctl restore '' <bd> --segments tables,data

# Migrar a otro servidor
backupctl migrate --to usuario@servidor --fresh

# BORRAR respaldos antiguos
backupctl retention
```

Y una que escribe pero se limpia sola:

```bash
# Crea una BD desechable, restaura ahí y LA BORRA al terminar.
# Tu producción no se toca. Es la única prueba concluyente.
backupctl verify --restore-test <bd> --with-data
```

---

## Credenciales

!!! success "backupctl nunca te pide la contraseña de MySQL"
    La lee de `env.sh`. No hay ningún punto del programa que lea una contraseña
    por teclado.

| Qué | ¿Pide algo? |
|---|---|
| MySQL, al respaldar | **Nunca.** Sale de `env.sh` |
| MySQL, en `setup` | **Sí**, y a propósito: te pide una credencial de administrador para crear el usuario de respaldo. **No se guarda** |
| SSH | **Sí si hace falta**, y **una sola vez** para toda la operación. Funciona con clave o con contraseña |
| `sudo` | **Sí puede**, en `cron --install` bajo HestiaCP y en `restic`. Se avisa antes |

!!! info "Una conexión, una contraseña"
    Un despliegue hace unas ocho conexiones SSH. `backupctl` abre una conexión
    maestra y todo lo demás viaja por ella, así que la contraseña se pide una
    vez. No hace falta configurar claves, aunque con `ssh-copy-id admin@servidor`
    no te la pedirá nunca.

    Sin terminal (cron, scripts) se exige clave y se falla con un mensaje claro
    en lugar de quedarse esperando.

Para evitar que `sudo` pregunte a mitad, lanza la orden entera con sudo:

```bash
sudo backupctl cron --install
```

---

## Opciones globales

```bash
-p, --profile <nombre>    servidor con el que trabajar
-y, --yes                 responder que sí a todo (desatendido)
    --debug               salida detallada
    --no-color            sin colores
    --plain               TUI en texto plano
-V, --version
```

## Códigos de salida

| Código | Significado |
|---|---|
| `0` | Todo correcto |
| `1` | La operación encontró problemas (revisa la salida) |
| `2` | No se pudo ni empezar (entorno o uso incorrecto) |

```bash
backupctl backup || echo "REVISAR"
backupctl status >/dev/null || curl -fsS https://hc-ping.com/xxx/fail
```

---

## Los tres archivos por servidor

```
MiVPS/
├── env.sh       ✏️  lo editas tú          → sube con deploy
├── NOTAS.md     ✏️  tus apuntes           → pull nunca lo toca
└── ESTADO.md    🤖  lo genera pull        → se regenera entero
```

## Ciclo repositorio ↔ servidor

```bash
backupctl -p MiVPS pull   admin@servidor   # DESCARGAR el estado real
backupctl -p MiVPS config --edit           # ajustar
backupctl -p MiVPS deploy admin@servidor   # SUBIR
backupctl -p MiVPS pull   admin@servidor   # dejar constancia
```

## En el servidor

Allí solo hay un perfil (`local`), así que no hace falta `-p`:

```bash
ssh admin@servidor
cd /home/admin/scripts
./bin/backupctl status
```

---

Más recetas concretas en **[Recetas](../guias/recetas.md)**.
Los recorridos completos en **[Paso a paso](../paso-a-paso/index.md)**.
