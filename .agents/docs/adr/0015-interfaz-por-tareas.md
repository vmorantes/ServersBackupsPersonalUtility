# 0015 — La interfaz web se organiza por tareas, no por órdenes

- **Estado:** Propuesta (pendiente de maqueta)
- **Fecha:** 2026-09-16
- **Decide:** Arquitecto, por mandato del PO («rigurosa y bonita como tú quieras»)
- **Estructural:** sí (la interfaz, que es el centro del producto para el PO)
- **Matiza:** la exigencia «un botón por acción, granularidad máxima» (HERENCIA.md)

## En cristiano

La web deja de enseñar todas las órdenes a la vez. Al entrar, se ve cada servidor con un
semáforo: protegido, con avisos o sin proteger, y el siguiente paso. Dentro de un servidor hay
pocas tareas —Resumen, Proteger, Comprobar, Recuperar, Servidor— y cada una se hace como un
recorrido: qué hay ahora, qué va a cambiar, confirmar, informe de lo hecho. Lo técnico o poco
frecuente sigue estando, pero plegado. Cada botón sigue haciendo una sola cosa: lo que cambia es
cuántos se ven a la vez.

## Contexto

- Queja recurrente del PO: la web es pesada y poco intuitiva (2026-09-06, 2026-09-16). No
  encontró «Resucitar» en la fila de pestañas.
- Inventario (2026-09-16): 13 pestañas, unas 73 acciones; siete pares duplicados «directo por
  SSH» / «vía el backupctl del servidor»; etiquetas «(aquí)» que actúan en el servidor; textos
  que contradicen al código; colores fijos fuera de las variables; la clase `btn-destruye` sin
  estilo; el estado de la pestaña HestiaCP no se relee tras actuar; `#rotulo-local` inexistente.
- Restricciones que se mantienen: sin dependencias externas (CSP `default-src 'self'`), Python de
  biblioteca estándar, JavaScript sin marcos, escucha solo en `127.0.0.1` con testigo.

## Decisión

1. **Portada «Mis servidores»**: una tarjeta por perfil con semáforo calculado de hechos leídos
   (último respaldo de bases y su verificación; incrementales: `BACKUP_INCREMENTAL`, repositorio,
   programación y fecha de la última instantánea; claves rescatadas fuera del servidor; avisos
   configurados) y un único «siguiente paso».
2. **Dentro de un servidor, cinco tareas**:
   - **Resumen**: el semáforo desglosado, el siguiente paso y los últimos informes (ADR 0014).
   - **Proteger**: respaldo de bases (programación, retención, avisos); **respaldos incrementales**
     como asistente (almacenamiento → repositorio y retención → programación → exclusiones →
     primera copia y comprobación → activo), con «cambiar» y «desactivar»; claves de recuperación.
   - **Comprobar**: verificar respaldos, verificar el repositorio, cobertura de bases y usuarios,
     informe de blindaje.
   - **Recuperar**: restaurar una base (con ensayo); resucitar cuentas como asistente
     (inventario → historial → ensayo → traer → bases a mano).
   - **Servidor**: acceso SSH, instalar o actualizar backupctl, configuración del perfil, traer el
     estado, registros.
3. **Un patrón único para escribir**: «Ahora» (leído) → «Plan» (qué cambia, con valores) →
   confirmación que nombra lo que se pierde → ejecución (salida en vivo plegada) → «Informe».
   Los ensayos dejan de ser botones hermanos: son el paso «Plan».
4. **Sin duplicados visibles**: la herramienta elige la vía (SSH directo o `backupctl` del
   servidor); las variantes técnicas van a «Avanzado» de cada tarea.
5. **Aspecto**: tipografía del sistema, una escala de espaciado, un color de acento y tres de
   estado (bien, aviso, peligro) solo en variables; claro y oscuro; texto de ayuda de una línea
   visible y el resto a demanda. Sin iconos externos (SVG en línea).
6. **Rigor de la web**: `web/comprobar.py` amplía sus comprobaciones (cada acción en exactamente
   una tarea, ninguna clase CSS sin estilo, ningún color fuera de variables, ningún id huérfano).
   Se relee el estado de la tarea tras cada acción.
7. **Maqueta antes de código**, revisada con el PO si quiere; si no la comenta, se construye.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Pulir el diseño actual (colores, espaciado) | El problema es de organización: 73 acciones a la vista siguen abrumando aunque sean bonitas |
| Un marco de interfaz (React, Vue) o una librería de componentes | Dependencias, compilación y CSP; la web es local y pequeña |
| Quitar acciones para simplificar | El PO quiere poder hacerlo todo desde la web; se pliegan, no se quitan |
| Asistentes para todo | Lo frecuente y simple (respaldar ahora, ver registros) no necesita pasos |

## Consecuencias

- Reescritura grande de `web/index.html`, `web/app.js` y `web/app.css`; `web/server.py` gana
  endpoints de estado por tarea y de informes.
- Toda la documentación de `docs/interfaces/web.md` y de las guías paso a paso se reescribe.
- La web actual deja de existir en la versión 2.1: no se mantienen las dos.

## Reversión

Volver a la web de la versión 2.0 (en `master` antes de la fusión de `release/2.1`, o la
etiqueta que se ponga): los endpoints nuevos de `server.py` no rompen la web antigua si se
conservan los existentes.

## Verificación

`web/comprobar.py` con sus comprobaciones nuevas; el PO recorre en la prueba final las cinco
tareas en el servidor de pruebas con la guía única.
