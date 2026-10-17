# Tramo: la migración caliente

- **Inicio:** 2026-10-17, 17:00.
- **Mandato del PO:** «Quiero que unifiquemos funciones en este repo unicamente con ambas vias.
  Aquella otra herramienta puede ser una subherramienta de acá. […] hace falta algo, un
  "analizador" del estado de un HestiaCP de solo lectura». Decisión: ADR 0018.
- **Urgencia:** el lunes 2026-10-19 el PO migra un servidor muy grande (Joomla y muchos
  proyectos CodeIgniter 3.1.7). El destino aún no existe. Ya no hay servidor de pruebas.
- **Rama:** `feat/migracion-caliente`, desde `release/2.1`. No desde `master`, como dice ADR 0007
  por omisión: `master` no tiene el andamiaje (guarda, puertas, ADR) que este trabajo necesita.

## Rondas

| Ronda | Qué | Estado | Commits |
| --- | --- | --- | --- |
| #124→#125 | Identificación del coder | completado | — |
| #126 | Entrada intacta de la herramienta, ejemplo saneado, ADR 0018 y estado | en vuelo | — |

## Hallazgos

1. **La otra herramienta tiene secretos reales versionados.** Su `MIGRACION.sh` lleva seis
   contraseñas de base de datos que no son marcadores y tres dominios reales, en cuatro commits
   de su historia. Medido sin imprimir ningún valor. Avisado al PO en `A-018`. Decide cómo se
   trae: copia sin historia (ADR 0018 §1).
2. **Su tipo «PiecesPHP / CodeIgniter» no es CodeIgniter 3.** Forma `$config['database']…` y
   ruta `app/config/`; CodeIgniter 3 usa `$db['default']` en `application/config/`. Su opción
   `ruta_db` arregla la ruta, no la forma. Falla en voz alta, no corrompe.
3. **La guarda tomó un `grep -r .` en otro repositorio por la raíz de este** (cwd distinto).
   Variante del defecto B: no mira el directorio real. No se esquivó: se buscó sobre archivos
   nombrados.

## Decisiones

- ADR 0018: copia intacta primero, analizador de solo lectura, tipo CodeIgniter 3, y la
  unificación con `backupctl` después del lunes.
- La fase 2 de la 2.1 queda aparcada.

## Pendiente del PO

1. Decidir qué hace con los secretos versionados en `HestiaCPCliMigrationUtility` (`A-018` §2).
2. Crear el servidor de destino e instalar HestiaCP; pasar las salidas de solo lectura que se le
   den.
