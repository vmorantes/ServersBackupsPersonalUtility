# La interfaz como aplicación del escritorio

Añade backupctl al menú de aplicaciones. Al abrirla **arranca el servidor
local**; al cerrar la ventana, **se apaga**. No queda nada escuchando cuando no
la estás usando.

```bash
./tools/backupctl-escritorio.sh instalar
```

Después búscala en el menú como **backupctl**.

---

## Qué hace exactamente

| Orden | Qué hace |
|---|---|
| `instalar` | Crea el lanzador del menú y el icono. Nada más |
| `desinstalar` | Los quita, y detiene el servidor si estaba corriendo |
| `estado` | ¿Está instalada? ¿Hay un servidor encendido? |
| `parar` | Detiene el servidor |
| `lanzar` | Lo que ejecuta el icono. También sirve desde el terminal |

Se crean exactamente dos archivos, ambos dentro de tu usuario:

```
~/.local/share/applications/backupctl.desktop
~/.local/share/icons/hicolor/scalable/apps/backupctl.svg
```

Y al usarla, un perfil de navegador propio en
`~/.local/share/backupctl/navegador`. `desinstalar` pregunta si borrarlo.

!!! success "No toca nada del sistema"
    Ni `/usr`, ni servicios, ni `sudo`. Todo vive en tu carpeta de usuario y se
    deshace con `desinstalar`.

---

## Por qué se abre en ventana propia

La aplicación se lanza en **modo aplicación** (`--app=`) con un perfil de
navegador dedicado: una ventana sin barra de direcciones ni pestañas, que
parece un programa y no una página web.

??? question "¿Por qué un perfil de navegador aparte?"
    No es capricho. Sin `--user-data-dir` propio, Chrome delega la petición en
    la instancia que ya tengas abierta y **el proceso lanzado termina al
    instante**. Sin proceso al que esperar, no habría forma de saber cuándo
    cierras la ventana, y el servidor se quedaría encendido indefinidamente.

    El perfil propio garantiza un proceso nuevo con vida propia. El precio es
    que esa ventana no comparte sesiones ni extensiones con tu navegador
    habitual, lo cual para una aplicación local es indiferente.

Funciona con Chrome, Chromium, Brave, Edge y Vivaldi. Si no hay ninguno, se
abre en el navegador por defecto y se avisa de que hay que pararlo a mano con
`parar`, porque en una pestaña normal no hay forma de detectar el cierre.

---

## Cómo se apaga

Tres caminos, los tres cubiertos:

| Situación | Qué pasa |
|---|---|
| Cierras la ventana | El servidor se apaga |
| Cierras la sesión o apagas el equipo | El servidor se apaga con ella |
| `desinstalar` con la aplicación abierta | Se detiene antes de desinstalar |

??? info "Dos detalles que costó afinar"
    **El PID es una variable global.** El `trap` de salida se ejecuta cuando la
    función que arrancó el servidor ya ha retornado; con una variable local, en
    ese momento ya no existiría y, con `set -u`, el `trap` fallaría dejando el
    servidor encendido. Justo lo que esta utilidad existe para evitar.

    **El navegador se espera con `wait`, no en primer plano.** Bash aplaza los
    traps mientras hay un hijo en primer plano: una señal al cerrar la sesión no
    se atendería hasta que el navegador terminase. Con `wait`, la señal
    interrumpe la espera y la limpieza ocurre.

---

## Si ya está abierta

Volver a lanzarla no levanta un segundo servidor: reutiliza el que hay y abre
otra ventana contra él.

## Puerto

Usa el 8787 y, si está ocupado, va probando hacia arriba hasta el 8819. Como
siempre, solo escucha en `127.0.0.1`.

```bash
./tools/backupctl-escritorio.sh estado
```

Te dice si hay alguno corriendo y en qué dirección.
