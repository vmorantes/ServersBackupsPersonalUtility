# 0018 — La migración caliente entra como subherramienta, con un analizador delante

- **Estado:** Aceptada (sin implementar)
- **Fecha:** 2026-10-17
- **Decide:** Arquitecto, por mandato del PO
- **Estructural:** sí (una segunda vía de trabajo en el repositorio, con su propio modelo de ejecución)
- **Se apoya en:** 0006 (pruebas en servidor las hace el PO), 0013 (versión 2.1)

## En cristiano

Este repositorio pasa a tener **dos vías** para llevar un servidor HestiaCP a otro:

- **La vía larga, la de siempre**: respaldos que se guardan, se verifican y se restauran
  (`backupctl`). Sirve para tener copias en el tiempo y, algún día, para migrar desde ellas.
- **La vía rápida, nueva aquí**: la migración caliente de cuenta completa —cuenta, dominios,
  archivos, bases, correo, cronjobs, certificados— de servidor vivo a servidor vivo, **sin
  pasar por un respaldo**. Es la herramienta `HestiaCPCliMigrationUtility`, que ya migró tres
  cuentas reales el 2026-10-02, y que entra aquí como subherramienta.

Delante de la vía rápida va algo que hoy no existe: un **analizador de solo lectura** que se
ejecuta en el servidor de origen, inventaría todo lo que se puede migrar y **propone** el
archivo de migración, con sus avisos. Propone; la persona decide.

## Mandato

PO, 2026-10-17, literal: «Quiero que unifiquemos funciones en este repo unicamente con ambas
vias. Aquella otra herramienta puede ser una subherramienta de acá. Piensalo como una
migracion caliente independiente de respaldos. Y además la principal nuestra debe llegar a ser
util algun dia que tiene que ver con respaldos. […] hace falta algo, un "analizador" del
estado de un HestiaCP de solo lectura que "aprenda" todo lo que se puede migrar y luego
decida.»

Contexto que lo fuerza: el lunes 2026-10-19 el PO migra un servidor **muy grande**, con un
Joomla y muchos proyectos CodeIgniter 3.1.7. El servidor de destino aún no existe. **Ya no hay
servidor de pruebas.**

## Decisiones

### 1. Se trae una copia, no la historia

El código entra como **instantánea** del commit `1474e4c` de aquel repositorio, sin su
historia de git.

Motivo, medido el 2026-10-17 sin imprimir ningún valor: su `MIGRACION.sh` está versionado con
seis contraseñas de base de datos que no son marcadores y tres dominios reales, en cuatro
commits. Traer la historia —`git subtree`, `merge` de historias— metería esos secretos en la
historia de este repositorio, que se sube a un remoto. Una copia no los trae.

### 2. Dónde vive

`tools/migracion-caliente/`. Es una herramienta con su propio modelo de ejecución: se
**construye** en la máquina del PO un único archivo autoextraíble, que se sube al servidor de
destino y se ejecuta allí como root, por fases. `backupctl`, en cambio, corre en la máquina del
PO y habla con el servidor por ssh. Mezclar los dos modelos en `lib/` confundiría qué corre
dónde, que es justo lo que más daño hace en un servidor.

### 3. Entra intacta primero

La primera entrada es **byte a byte** igual a la del commit de origen, comprobado con sumas.
Solo así el código que el PO ejecute el lunes es el mismo que ya funcionó en una migración
real. Cualquier cambio va en commits posteriores, cada uno con su prueba.

Lo que **no** entra:

- `MIGRACION.sh` con datos reales. En su lugar, un ejemplo con nombres ficticios
  (`example.org`, `203.0.113.10`) y la misma estructura.
- `site/` (documentación generada), el andamiaje de agentes de aquel repositorio (`.agents/`,
  `.claude/`, `AGENTS.md`, `CLAUDE.md`), sus hooks de git y sus cachés.
- Su documentación entra después, reescrita en `docs/` de este repositorio.

### 4. El analizador

Una pieza nueva, en la misma subherramienta, que **no escribe nada en el servidor** salvo su
propio informe en un directorio temporal que dice cuál es. Lee e inventaría:

- cuentas, dominios web con su versión de PHP **explícita**, alias, certificados;
- el **tipo de aplicación** de cada dominio, **solo con evidencia** (el archivo de
  configuración que lo demuestra); lo que no se puede demostrar se escribe «no se pudo
  determinar», nunca una suposición (lección del punto 9 de
  `.agents/docs/mejoras-herramienta-migracion.md`);
- bases de datos con su tamaño, buzones con su número de mensajes, zonas DNS, cronjobs —
  marcando los que llaman a un intérprete por nombre corto—, y tamaños de disco por cuenta.

Y con eso **propone** el archivo de migración, con avisos explícitos: versiones de PHP que
cambiarían, aplicaciones que la herramienta no sabe reconfigurar, HTTPS forzado sin
certificado.

Cada orden `v-*` y cada ruta de HestiaCP que use se verifica contra la fuente
(`hestia-verifier`) o está ya citada en `.agents/context/50-hestiacp.md`.

### 5. CodeIgniter 3

La herramienta reconoce un tipo «PiecesPHP / CodeIgniter» que **no** es CodeIgniter 3: busca
`$config['database']['default'][…]` en `app/config/database.php`, y CodeIgniter 3 declara
`$db['default']` en `application/config/database.php` (medido en un proyecto del PO de la misma
versión). Hoy falla en voz alta («No se encontró ninguna asignación»), no corrompe. Se añade un
tipo propio, con pruebas sobre archivos sintéticos.

### 6. La unificación con `backupctl`, después

Que `backupctl` y la web ofrezcan la vía rápida —con perfiles, botones e informe de lo hecho—
es trabajo posterior. **No antes del lunes**: cambiar cómo se lanza una herramienta probada dos
días antes de usarla en el servidor más grande es el error que este proyecto ya pagó dos veces.

## Orden

1. Entrada intacta, con su verificación por sumas y el ejemplo saneado.
2. El analizador, de solo lectura.
3. El tipo CodeIgniter 3.
4. Documentación de usuario de las dos vías y la guía del lunes.
5. Después del lunes: lo aprendido, los 12 puntos de `mejoras-herramienta-migracion.md`, y la
   unificación con `backupctl` y la web.

## Consecuencias

- **Sin servidor de pruebas, la primera ejecución real de todo lo nuevo será en producción.**
  Lo que no viene de la copia intacta (el analizador, el tipo CodeIgniter 3) se prueba con datos
  sintéticos y se entrega diciendo con esas palabras que nunca corrió en un servidor. El
  analizador es de solo lectura, que es lo que lo hace aceptable en esas condiciones.
- Hay dos copias de la herramienta hasta que el PO decida qué hacer con la original. Esta es la
  que evoluciona.
- La guarda de este repositorio se aplicará a ese código, que habla de órdenes remotas en sus
  comentarios: el defecto A de la guarda morderá más.

## Alternativas descartadas

| Alternativa | Por qué no |
| --- | --- |
| Traer la historia con `git subtree` | Mete secretos reales en la historia de este repositorio |
| Reescribir la migración dentro de `lib/` como órdenes de `backupctl` | Dos días antes de usarla en el servidor más grande, y sin servidor de pruebas |
| Dejarla en su repositorio y solo documentarla aquí | El PO pidió unificar en este repositorio |

## Reversión

Borrar `tools/migracion-caliente/` y sus documentos, y marcar este ADR como descartado. No toca
nada de `backupctl`.
