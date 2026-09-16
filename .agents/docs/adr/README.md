# Decisiones de arquitectura (ADR)

Un ADR registra **por qué** se decidió algo, qué se descartó y a cambio de qué. No describe
cómo funciona el código: eso se lee del código.

> `git log` te dice qué cambió. Jamás te dice qué descartaste, ni por qué.

Viven en `.agents/` porque su lector principal es un agente que llega sin memoria y necesita
saber qué no rediscutir. Una persona los lee igual de bien.

## Dos registros de decisiones

- **`docs/desarrollo/decisiones.md`** (para personas, anterior a la adopción): las
  decisiones de producto de `backupctl` —detección de errores de `mysqldump`, archivo de
  credenciales, seis segmentos por base, `BACKUP_KEEP_MIN`, formato abierto, `--into`,
  confirmaciones que se degradan a «no», lo que se dejó fuera— con su porqué. Siguen
  vigentes. **No se duplican aquí**: contradecir una exige un ADR nuevo que la cite.
- **Aquí**, desde la adopción del modelo arquitecto-coder (2026-09-14): cómo se trabaja y
  toda decisión nueva con alternativas y consecuencias que duran.

## Regla dura: inmutables

**La inmutabilidad empieza cuando el ADR se commitea.** Antes es un borrador. Publicado, no
se toca: si la decisión cambia, se escribe uno nuevo con `Reemplaza: NNNN`, y del viejo solo
cambia la línea de estado a `Reemplazada por NNNN`.

## Cuándo escribir uno

Cuando hay una **elección real entre alternativas** con consecuencias que duran. Para un
agente, además: cuando sin él una sesión futura podría deshacer la decisión "mejorándola".

## Cambios estructurales

Un cambio es estructural si cambia **dónde vive** algo, un **contrato** entre partes (el
formato del respaldo, el `env.sh`, lo que se escribe en un servidor), **cómo se trabaja**, o
**configuración de alcance global** (`.gitignore`, hooks, cron, lo que se instala en un
servidor). Su ADR lleva obligatoriamente:

- **En cristiano** — cuatro frases sin jerga.
- **Reversión** — paso a paso, en orden inverso, en términos de estado (no de hashes), y qué
  comprobar después. Si es parcial o destructiva, se dice con esas palabras.

## Convención

`NNNN-titulo-en-kebab-case.md`, correlativos, sin reutilizar números. Plantilla:
`.agents/skills/arquitecto-coder/plantillas/adr-plantilla.md`. Estados: `Propuesta` ·
`Aceptada` · `Aceptada (sin implementar)` · `Reemplazada por NNNN` · `Descartada`.

## Índice

| ADR | Decisión | Estructural | Estado |
| --- | --- | --- | --- |
| [0001](0001-tres-roles-y-canal-directo.md) | Arquitecto, coder y PO, con canal directo entre sesiones | sí | Aceptada |
| [0002](0002-agentes-generados-desde-personas.md) | Subagentes generados desde personas, con modelo y esfuerzo por tarea | sí | Aceptada |
| [0003](0003-salvaguardas-forzadas-por-hooks.md) | Salvaguardas forzadas por una guarda de hooks | sí | Aceptada |
| [0004](0004-estado-volatil-versionado.md) | `estado/`: lo que pasa ahora, versionado y podado | sí | Aceptada |
| [0005](0005-prosa-comprimida.md) | Prosa comprimida donde no cuesta fiabilidad | sí | Aceptada |
| [0006](0006-pruebas-en-servidor-las-hace-el-po.md) | Las pruebas contra un servidor las hace el PO | sí | Aceptada |
| [0007](0007-ramas-master-estable.md) | `master` estable; ramas propias; lo que toca servidores espera la prueba del PO | sí | Aceptada |
| [0008](0008-credenciales-versionadas.md) | Los perfiles guardan sus credenciales en el repositorio | sí | Aceptada |
| [0009](0009-banco-de-pruebas-local.md) | Banco de pruebas local: órdenes falsas en el PATH y perfiles sintéticos | sí | Reemplazada por 0010 |
| [0010](0010-banco-de-pruebas-salvaguardas-propias.md) | Banco de pruebas: cada salvaguarda se comprueba a sí misma | sí | Aceptada |
| [0011](0011-borrado-de-ramas-fusionadas.md) | El coder borra las ramas locales ya fusionadas (`git branch -d`) | sí | Aceptada |
| [0012](0012-limpieza-que-sobrevive-a-la-salida.md) | La limpieza se registra y se ejecuta al salir, pase lo que pase | sí | Aceptada (sin implementar) |
| [0013](0013-programa-version-estable-2-1.md) | Camino a una versión estable: rama `release/2.1`, prueba única del PO, etiqueta | sí | Aceptada |
