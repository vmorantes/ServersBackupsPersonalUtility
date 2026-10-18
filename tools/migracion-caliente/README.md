# Migración caliente

La vía rápida para llevar cuentas de un servidor HestiaCP a otro: cuenta, dominios con su
versión de PHP, archivos, bases de datos, correo, cronjobs y certificados, **de servidor vivo a
servidor vivo**, sin pasar por un respaldo. La vía larga —respaldos que se guardan, se verifican
y se restauran— es `backupctl`.

## De dónde viene

Es una copia intacta de la herramienta `HestiaCPCliMigrationUtility`, commit `1474e4c`, la que
migró tres cuentas reales entre dos HestiaCP 1.10.5 el 2026-10-02. Los módulos `BASE_*.sh`,
`construir.sh` y `crear.sh` entraron **byte a byte** iguales a los de ese commit. Desde entonces
han cambiado `BASE_CONFIG.sh`, `BASE_LEER_CONFIG.sh`, `BASE_CONFIGURAR_DB.sh`, `BASE_PLAN.sh` y
`crear.sh`, en commits propios y cada uno con su prueba; `git log` sobre este directorio dice
qué y por qué.

No se trajo su historia, ni su archivo de migración de ejemplo, que llevaba datos reales. En su
lugar está `migracion-ejemplo.sh`, con nombres ficticios.

## Cómo se usa

La guía completa, paso a paso, está en `docs/migracion/caliente.md`. En resumen:

1. `construir-analizador.sh` empaqueta el **analizador**, que se ejecuta en el servidor de
   **origen**, no escribe nada en él salvo su informe, y propone un archivo de migración por
   cuenta.
2. Se revisa cada propuesta (o se escribe a mano, con `crear.sh` o desde `migracion-ejemplo.sh`).
3. `construir.sh` la empaqueta en un único archivo ejecutable, que se sube al servidor de
   **destino** y se ejecuta allí como root, por fases: `plan`, `1`, `sincronizar`, corte de DNS,
   `2`, `verificar`.
4. `recrear-zonas.sh` recrea en el **destino** las zonas DNS que el analizador exportó del
   origen (`zonas/<cuenta>/`), con la IP, los NS y la clave DKIM del destino. Va después de la
   fase 1 y antes del corte de DNS. Sin `--aplicar` solo muestra el diff.

Lo añadido aquí después de la copia (el analizador, el tipo `codeigniter3`, el arreglo de
`plan` y `verificar`, `recrear-zonas.sh`) solo se ha probado con datos inventados: ver
`tests/probar_migracion_*.sh`.

## Cuidado

- **El paquete construido lleva las contraseñas de las bases de datos en claro.** Este
  directorio ignora `*.paquete.sh` (incluido el del analizador) y `migracion-*.sh` (salvo el
  ejemplo) para que nunca se versionen. En el servidor, se borra al terminar.
- Los puntos débiles conocidos, de la migración del 2026-10-02, están en
  `.agents/docs/mejoras-herramienta-migracion.md`. El que más importa: **forzar HTTPS no
  comprueba que haya certificado**.
- El tipo `piecesphp` **no** sirve para CodeIgniter 3: para eso está `codeigniter3`.
