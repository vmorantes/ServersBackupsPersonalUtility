# Respaldo y migración de servidores

Documentación operativa de **`backupctl`**: respaldo, verificación, restauración
y migración de bases de datos MySQL/MariaDB en servidores HestiaCP.

!!! success "¿Quieres hacerlo todo sin recorrer la documentación?"
    **[Hacerlo todo de una vez](todo-de-una-vez.md)** — una sola página, de cero
    a funcionando en unos 30 minutos. Copiar, pegar y seguir.

!!! tip "¿Vienes a buscar algo concreto?"
    Usa el buscador de arriba. Si no sabes qué buscar, empieza por
    [Recetas](guias/recetas.md): son las tareas del día a día resueltas de una
    línea.

## Lo que hay que recordar

Si solo te llevas tres cosas de esta documentación, que sean estas.

=== "¿Estoy protegido?"

    ```bash
    backupctl status
    ```

    Responde en dos segundos y devuelve un código de salida distinto de cero si
    algo no está bien. Sirve tal cual dentro de una comprobación automática.

=== "Algo va mal"

    ```bash
    backupctl doctor
    ```

    Revisa órdenes del sistema, configuración, permisos, disco, MySQL,
    privilegios, capacidades de `mysqldump`, respaldos y cron. Dice qué está
    mal **y qué hacer**.

=== "No recuerdo la orden"

    ```bash
    backupctl
    ```

    Sin argumentos abre el menú interactivo. O mira la
    **[Chuleta](referencia/chuleta.md)**: todo en una página, con lo que no
    toca nada arriba del todo.

## Las tres fachadas

Tres formas de uso sobre **la misma lógica**:

<div class="grid cards" markdown>

-   :material-monitor-dashboard: **Web — todos los VPS a la vez**

    ---

    Un panel local en el navegador con el estado de todos tus servidores,
    y la salida real de cada orden en vivo.

    ```bash
    backupctl web --open
    ```

    [:octicons-arrow-right-24: La interfaz web](interfaces/web.md)

-   :material-console: **TUI — para personas**

    ---

    Un menú navegable para cuando no recuerdas el nombre exacto de una opción,
    o cuando quieres ver qué haría algo antes de lanzarlo.

    ```bash
    backupctl
    ```

    [:octicons-arrow-right-24: La TUI](interfaces/tui.md)

-   :material-robot: **CLI — para servidores**

    ---

    Sin preguntas, con códigos de salida fiables y avisos automáticos. Es lo
    que corre en el cron todas las noches.

    ```bash
    backupctl backup
    ```

    [:octicons-arrow-right-24: CLI y automatización](interfaces/cli.md)

</div>

!!! info "No hay dos implementaciones"
    La TUI llama exactamente a las mismas funciones que el cron. Lo que pruebas
    a mano es literalmente lo que se ejecuta de madrugada. Ver
    [Arquitectura](desarrollo/arquitectura.md).

## Qué hace el sistema

| Área | Qué resuelve |
|---|---|
| **Respaldo** | Vuelca todas las bases de datos en seis archivos por base, comprimidos y empaquetados con un manifiesto. |
| **Detección de fallos** | Nunca reporta éxito si un volcado falló. Lee la salida de error de `mysqldump`, no solo su código de salida. |
| **Verificación** | Cuatro niveles, desde el CRC del zip hasta una restauración real en una base de datos desechable. |
| **Restauración** | Por segmentos, con posibilidad de restaurar bajo otro nombre para no tocar la base de datos viva. |
| **Migración** | Despliegue del tooling en otro servidor y traslado de bases de datos con comprobación de recuentos. |
| **Retención** | Borrado automático de lo viejo, conservando siempre los N más recientes. |
| **Avisos** | Correo, orden arbitraria o healthcheck. Un cron que falla en silencio es un respaldo que no existe. |
| **Claves Restic** | Volcado de las claves de repositorio de HestiaCP. |
| **Despliegue** | `deploy` sube el código y la config a un servidor; `pull` baja al repositorio lo que hay realmente allí. |

## Principios

!!! quote "Un respaldo que nunca se ha restaurado no es un respaldo: es un archivo."

1. **Fallar ruidosamente.** Un respaldo incompleto que parece correcto es peor
   que uno que falla. Todo el diseño de la
   [detección de errores](desarrollo/decisiones.md#deteccion-de-errores) sale de aquí.
2. **Verificable.** Cada respaldo lleva sumas SHA-256 de todo lo que contiene.
3. **Portable.** El volcado está preparado para restaurarse en **otra** máquina:
   sin `DEFINER`, con charset explícito y sin estado de replicación.
   Ver [Portabilidad](migracion/portabilidad.md).
4. **Una sola fuente de verdad.** El código es idéntico en todos los servidores;
   lo único que cambia es `env.sh`.
5. **Reversible antes de destructivo.** Casi todo tiene `--dry-run`.

## Las seis guías paso a paso

Cada operación en dos versiones: **ensayo** (no toca nada) y **en serio**.

| # | Guía | |
|---|---|---|
| 1 | [Instalar — ensayo](paso-a-paso/instalar-ensayo.md) | no escribe nada |
| 2 | [Instalar en serio](paso-a-paso/instalar.md) | |
| 3 | [Restaurar — ensayo](paso-a-paso/restaurar-ensayo.md) | no escribe nada |
| 4 | [Restaurar en serio](paso-a-paso/restaurar.md) | escribe en la BD |
| 5 | [Migrar — ensayo](paso-a-paso/migrar-ensayo.md) | no escribe nada |
| 6 | [Migrar en serio](paso-a-paso/migrar.md) | escribe en el destino |

Y una tabla de [qué escribe cada orden](paso-a-paso/index.md#que-escribe-cada-orden),
para saber qué es seguro ejecutar sin pensarlo.

## Mapa de la documentación

- **[Qué es cada cosa](empezar/que-es-cada-cosa.md)** — de todos los archivos del
  repositorio, cuál tocas tú. **Empieza aquí si te pierdes.**
- **[Conceptos](empezar/conceptos.md)** — perfiles, segmentos, el flujo completo.
- **[Instalación](empezar/instalacion.md)** — poner esto en un servidor.
- **[Operación](operacion/respaldar.md)** — el día a día.
- **[Migración](migracion/desplegar.md)** — llevarlo o llevarse los datos a otra máquina.
- **[Referencia](referencia/ordenes.md)** — todas las órdenes y variables.
- **[Guías](guias/diagnostico.md)** — qué hacer cuando algo falla.

---

Para levantar esta documentación en local:

```bash
mkdocs serve      # http://127.0.0.1:8000
```
