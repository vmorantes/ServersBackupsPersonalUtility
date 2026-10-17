# 0019 — La migración caliente solo escribe en el destino y no despierta lo apagado

- **Estado:** Aceptada
- **Fecha:** 2026-10-17
- **Decide:** Product Owner (§1); arquitecto (§2 y §3)
- **Estructural:** sí (qué servidores modifica la herramienta)
- **Se apoya en:** 0018

## En cristiano

La migración caliente automatiza **la migración**: escribe en el servidor nuevo y solo lee del
viejo. Lo que haya que cambiar en el viejo —apuntar sus zonas al nuevo, apagar sus cron— lo hace
el PO a mano. Y nada que estuviera apagado en el viejo se enciende solo en el nuevo.

## Decisiones

### 1. El origen es de solo lectura

PO, 2026-10-17, literal: «El servidor viejo nunca lo toca la herramienta, cualquier cambio
necesario lo hago yo. La herramienta automatiza LA MIGRACION.»

Medido el mismo día: la herramienta solo lee en el origen, con **una excepción**. En el modo de
acceso a MySQL «user», crea en el `/tmp` del origen un temporal con la contraseña (`mktemp`,
`chmod 600`) para `mysqldump`, y lo borra con `trap EXIT`
(`tools/migracion-caliente/BASE_PRIVILEGIOS.sh:811-826, 919-922, 949`). Se acepta: es un archivo
propio, efímero, que no cambia nada del servidor. Si el proceso muere de golpe, queda allí.

El analizador (ADR 0018 §4) cumple esto por construcción y lo demuestra su suite.

### 2. Un cron suspendido en el origen no se migra

La herramienta lo creaba activo en el destino: solo anotaba que estaba suspendido. Se decide
**omitirlo** y anunciarlo en la fase 1, en vez de crearlo suspendido, porque omitir no exige
ninguna orden del panel nueva a dos días de usar la herramienta en producción, y es lo único que
no puede despertar nada. Crearlo suspendido queda para después, verificado contra la fuente.

### 3. Las propuestas no rellenan lo que no saben

Lo que el analizador no puede saber (la IP del destino, la versión de PHP de un dominio en
`default`) se deja **vacío**, no con un texto de relleno: la herramienta solo comprueba que esos
valores no estén vacíos, y un relleno habría pasado. Vacío, se niega antes de conectar.

## Consecuencias

- Las zonas DNS del origen no las ajusta la herramienta. El plan del PO para el corte (migrar,
  cambiar NS al destino, apuntar el origen al destino mientras propaga) lo ejecuta él.
- Cualquier función futura que escriba en el origen contradice este ADR y necesita uno nuevo.

## Reversión

Volver a crear los cron suspendidos (activos) es deshacer `2efdc4b`. El resto no tiene
reversión que tenga sentido.
